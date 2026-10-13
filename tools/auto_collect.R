#!/usr/bin/env Rscript
# tools/auto_collect.R — Execução autônoma de coleta para GitHub Actions ou Cron

main_auto_collect <- function(test_mode = FALSE, source_filter = NULL) {
  app_dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)

  # Define SCRAPE_WORKERS = 1 por padrão para garantir execução estável e sequencial
  if (!nzchar(Sys.getenv("SCRAPE_WORKERS"))) {
    Sys.setenv(SCRAPE_WORKERS = "1")
  }

  # Identificação do ambiente de execução (Posit Connect, GitHub Actions ou Cron)
  exec_env <- if (nzchar(Sys.getenv("CONNECT_SERVER")) || nzchar(Sys.getenv("R_CONFIG_ACTIVE"))) {
    "POSIT_CONNECT"
  } else if (nzchar(Sys.getenv("GITHUB_ACTIONS"))) {
    "GITHUB_ACTIONS"
  } else {
    "AUTO_COLLECT"
  }
  exec_url <- if (nzchar(Sys.getenv("CONNECT_SERVER"))) {
    Sys.getenv("CONNECT_SERVER")
  } else {
    "https://github.com/workflows/auto_collect"
  }

  # Suporte a biblioteca local R_libs (desenvolvimento local) ou biblioteca do sistema (GHA/Connect)
  local_libs <- file.path(app_dir, "R_libs")
  if (dir.exists(local_libs)) {
    .libPaths(c(local_libs, .libPaths()))
  }

  suppressPackageStartupMessages({
    library(DBI)
    library(RSQLite)
    library(jsonlite)
    library(digest)
    library(dplyr)
    library(purrr)
    library(stringr)
    library(httr2)
    library(rvest)
    library(xml2)
    library(lubridate)
    library(tibble)
    library(readr)
    library(writexl)
  })

  # Fonte única de verdade dos módulos de coleta
  COLLECTOR_HELPER_FILES <- c(
    "R/helpers_utils.R",
    "R/helpers_db.R",
    "R/helpers_status.R",
    "R/helpers_validation.R",
    "R/helpers_schedule.R",
    "R/helpers_text.R",
    "R/helpers_ai.R",
    "R/helpers_collect.R",
    "R/helpers_sources_br.R",
    "R/helpers_sources_br_federal.R",
    "R/helpers_sanitize.R"
  )

  message("----------------------------------------------------------------------")
  message(sprintf("[AutoCollect] Iniciando ciclo de busca automática (%s)...", exec_env))
  message(sprintf("[AutoCollect] Horário de execução: %s", as.character(Sys.time())))
  message("----------------------------------------------------------------------")

  for (helper_file in COLLECTOR_HELPER_FILES) {
    helper_path <- file.path(app_dir, helper_file)
    if (!file.exists(helper_path)) {
      stop(sprintf("Erro: Helper essencial ausente: %s", helper_path), call. = FALSE)
    }
    source(helper_path, encoding = "UTF-8")
  }

  # Conexão com o banco: Postgres (se DATABASE_URL definida) ou SQLite local
  db_target <- if (nzchar(Sys.getenv("DATABASE_URL"))) "PostgreSQL (DATABASE_URL)" else "funding_intelligence.sqlite"
  message(sprintf("[AutoCollect] Conectando ao banco de dados: %s", db_target))

  conn <- tryCatch(
    conectar_banco("funding_intelligence.sqlite"),
    error = function(e) {
      stop(sprintf("Falha crítica ao conectar no banco de dados: %s", e$message), call. = FALSE)
    }
  )
  on.exit({
    try(DBI::dbDisconnect(conn), silent = TRUE)
    message("[AutoCollect] Conexão com banco encerrada.")
  }, add = TRUE)

  # Garantir integridade de esquema e novas colunas de aderência por campi
  message("[AutoCollect] Verificando e criando tabelas/fontes caso não existam...")
  create_tables(conn)
  seed_sources(conn)
  migrate_enrichment_columns(conn)

  # Registrar log inicial de início de coleta
  log_collection(
    conn = conn,
    fonte = exec_env,
    metodo_coleta = "agendamento_automatico",
    status_execucao = "iniciado",
    mensagem = sprintf("Busca automática disparada às %s via %s", format(Sys.time(), "%H:%M:%S"), exec_env),
    n_paginas = 0L,
    n_registros = 0L,
    url = exec_url
  )

  # Configurações de coleta
  max_pages <- if (test_mode) 1L else 5L
  max_records <- if (test_mode) 5L else 20L
  use_ai <- ai_available()

  # Se for teste rápido e nenhuma fonte informada, filtra para teste rápido
  if (is.null(source_filter) && isTRUE(test_mode)) {
    source_filter <- c("fapesb")
  }

  message(sprintf("[AutoCollect] Parâmetros: max_pages=%d, max_records=%d, use_ai=%s, fontes=%s", 
                  max_pages, max_records, as.character(use_ai), 
                  if (is.null(source_filter)) "TODAS" else paste(source_filter, collapse = ", ")))

  # Execução oficial da coleta
  res <- tryCatch(
    {
      collect_all_sources(
        conn = conn,
        source_ids = source_filter,
        max_pages = max_pages,
        max_records_per_source = max_records,
        use_ai = use_ai,
        do_export = TRUE,
        export_dir = file.path(app_dir, "data_exports"),
        log_path = file.path(app_dir, "logs", "funding_collection.log")
      )
    },
    error = function(e) {
      log_collection(
        conn = conn,
        fonte = exec_env,
        metodo_coleta = "agendamento_automatico",
        status_execucao = "erro",
        mensagem = sprintf("Erro na execução automática: %s", e$message),
        n_paginas = 0L,
        n_registros = 0L,
        url = exec_url
      )
      stop(sprintf("[AutoCollect] Falha durante a coleta: %s", e$message), call. = FALSE)
    }
  )

  # Registrar log de conclusão
  log_collection(
    conn = conn,
    fonte = exec_env,
    metodo_coleta = "agendamento_automatico",
    status_execucao = "sucesso",
    mensagem = sprintf("Ciclo concluído via %s: %d fontes processadas, %d novos registros adicionados.", 
                       exec_env, res$sources_processed %||% 0L, res$inserted_now %||% 0L),
    n_paginas = 0L,
    n_registros = res$inserted_now %||% 0L,
    url = exec_url
  )

  message("----------------------------------------------------------------------")
  message(sprintf("[AutoCollect] SUCESSO: %d fontes processadas.", res$sources_processed %||% 0L))
  message(sprintf("[AutoCollect] Novos registros inseridos nesta rodada: %d", res$inserted_now %||% 0L))
  message(sprintf("[AutoCollect] Total de oportunidades no banco: %d", res$n_records %||% 0L))
  message("----------------------------------------------------------------------")
  invisible(res)
}

# Executa automaticamente apenas se invocado diretamente via linha de comando/Rscript
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  is_test <- "--test" %in% args || "--dry-run" %in% args
  main_auto_collect(test_mode = is_test)
}
