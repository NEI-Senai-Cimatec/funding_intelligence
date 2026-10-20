# QA de integração: coleta CNPq + CAPES replicando EXATAMENTE o job background
# corrigido (callr::r_bg com sourcing local=TRUE dentro do processo), em banco
# SQLite temporário (não toca no DB do app em execução).
#
# Valida a spec collection-pipeline:
#  - "Background collector process loads complete helper module set"
#  - "Collector error transparency in dispatch"
#
# Uso:  Rscript scratch/qa_cnpq_capes_integration.R
# Critério de aceite: cnpq e capes com status_execucao = "sucesso" e
# n_registros > 0 em logs_coleta.

.libPaths(c(file.path(getwd(), "R_libs"), .libPaths()))
stopifnot(file.exists("app.R"))  # rodar a partir da raiz do projeto

# ---- 1. Extrair a lista única de helpers do app.R --------------------------
app_lines <- readLines("app.R", warn = FALSE)
start <- grep("COLLECTOR_HELPER_FILES <- c\\(", app_lines)
stopifnot(length(start) == 1)
block <- character(0)
for (i in seq(start, length(app_lines))) {
  block <- c(block, app_lines[[i]])
  if (grepl("^\\)", app_lines[[i]])) break
}
helper_files <- gsub('"', "", unlist(regmatches(block, gregexpr('"R/[^"]+\\.R"', block))))
cat("QA: helpers do pipeline:", paste(basename(helper_files), collapse = ", "), "\n")
stopifnot("R/helpers_status.R" %in% helper_files)

# ---- 2. Diretório temporário do QA -----------------------------------------
qa_dir <- file.path(tempdir(), sprintf("qa_cnpq_capes_%s", format(Sys.time(), "%H%M%S")))
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
db_path <- file.path(qa_dir, "qa.sqlite")
log_path <- file.path(qa_dir, "qa_collection.log")
status_file <- file.path(qa_dir, "qa_status.json")
modal_log <- file.path(qa_dir, "qa_modal_log.txt")
cat(sprintf("QA: diretório temporário %s\n", qa_dir))

# ---- 3. Job background idêntico ao app.R (callr::r_bg) ---------------------
cat("QA: lançando processo background via callr::r_bg (como em app.R)...\n")
t0 <- Sys.time()
bg <- callr::r_bg(
  func = function(app_dir_bg, helper_files_bg, db_path_bg, log_path_bg,
                  status_file_bg, modal_log_file_bg) {
    local_libs_bg <- file.path(app_dir_bg, "R_libs")
    if (dir.exists(local_libs_bg)) .libPaths(c(local_libs_bg, .libPaths()))
    for (pkg in c("DBI", "RSQLite", "jsonlite", "digest", "dplyr", "purrr",
                  "stringr", "httr2", "rvest", "xml2", "lubridate", "tibble",
                  "readr", "writexl")) {
      library(pkg, character.only = TRUE)
    }
    for (helper_file_bg in helper_files_bg) {
      source(file.path(app_dir_bg, helper_file_bg), local = TRUE, encoding = "UTF-8")
    }
    init_database(db_path_bg)
    bg_conn <- DBI::dbConnect(RSQLite::SQLite(), db_path_bg)
    on.exit(DBI::dbDisconnect(bg_conn), add = TRUE)
    collect_all_sources(
      conn               = bg_conn,
      source_ids         = c("cnpq", "capes"),
      max_pages          = 5,
      max_records_per_source = 15,
      use_ai             = FALSE,
      export_dir         = dirname(db_path_bg),
      log_path           = log_path_bg,
      do_export          = FALSE,
      status_file        = status_file_bg,
      modal_log_file     = modal_log_file_bg
    )
  },
  args = list(
    app_dir_bg       = getwd(),
    helper_files_bg  = helper_files,
    db_path_bg       = db_path,
    log_path_bg      = log_path,
    status_file_bg   = status_file,
    modal_log_file_bg = modal_log
  ),
  stdout = file.path(qa_dir, "stdout.log"),
  stderr = file.path(qa_dir, "stderr.log"),
  supervise = FALSE
)

# Aguarda o processo terminar (timeout 20 min)
while (bg$is_alive() && difftime(Sys.time(), t0, units = "mins") < 20) {
  Sys.sleep(10)
}
if (bg$is_alive()) {
  bg$kill()
  stop("QA: TIMEOUT — processo background não concluiu em 20 min")
}
cat(sprintf("QA: processo background concluído em %.1f min (exit status: %s)\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins")), bg$get_exit_status()))

# ---- 4. Asserções -----------------------------------------------------------
qa_conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(try(DBI::dbDisconnect(qa_conn), silent = TRUE), add = TRUE)

logs <- DBI::dbGetQuery(qa_conn, "
  SELECT fonte, status_execucao, mensagem, n_paginas, n_registros, url
  FROM logs_coleta WHERE fonte IN ('cnpq','capes') ORDER BY fonte")
logs[is.na(logs)] <- ""
cat("\nQA: logs_coleta\n")
print(logs)

qa_ok <- TRUE
for (src in c("capes", "cnpq")) {
  row <- logs[logs$fonte == src, , drop = FALSE]
  if (nrow(row) == 0 || row$status_execucao[1] != "sucesso" || row$n_registros[1] < 1) {
    qa_ok <- FALSE
    cat(sprintf("QA: FALHA para %s (status=%s, registros=%s)\n", src,
                if (nrow(row)) row$status_execucao else "ausente",
                if (nrow(row)) row$n_registros else "NA"))
  }
}

# Erros nunca podem ter a mensagem genérica mascarada
masked <- logs[grepl("Resultado vazio na coleta paralela", logs$mensagem), , drop = FALSE]
if (nrow(masked) > 0) {
  qa_ok <- FALSE
  cat("QA: FALHA — mensagem genérica 'Resultado vazio' presente (transparência de erro quebrou)\n")
}

stderr_lines <- readLines(file.path(qa_dir, "stderr.log"), warn = FALSE)
fatal <- stderr_lines[grepl("Execution halted|could not find function", stderr_lines)]
if (length(fatal) > 0) {
  qa_ok <- FALSE
  cat("\nQA: FALHA — erros fatais no stderr do bg-job:\n")
  cat(paste("  ", fatal, collapse = "\n"), "\n")
}

if (qa_ok) {
  cat("\nQA: APROVADO — CNPq e CAPES coletando com sucesso no ambiente do bg-job (callr::r_bg).\n")
} else {
  cat("\nQA: REPROVADO — ver logs acima. Artefatos em:", qa_dir, "\n")
  quit(save = "no", status = 1)
}
