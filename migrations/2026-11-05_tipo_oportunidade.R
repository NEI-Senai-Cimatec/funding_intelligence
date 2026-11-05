#!/usr/bin/env Rscript
# Migração: normaliza tipo_oportunidade para a taxonomia canônica de 5 categorias.
#
# Uso (a partir da raiz do projeto):
#   Rscript migrations/2026-11-05_tipo_oportunidade.R
#   Rscript migrations/2026-11-05_tipo_oportunidade.R caminho/para/base.sqlite
#   Rscript migrations/2026-11-05_tipo_oportunidade.R --force
#
# A migração é idempotente: se o marker `tipo_oportunidade_v1` já existir,
# ela não faz nada (use --force para reaplicar o mapa).
# Um backup da base é criado em backups/ antes de qualquer alteração.

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
args_posicionais <- args[!grepl("^--", args)]

root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
for (i in 1:5) {
  if (file.exists(file.path(root, "app.R"))) break
  root <- dirname(root)
}
if (!file.exists(file.path(root, "app.R"))) {
  stop("Execute a partir da raiz do projeto (app.R não encontrado).", call. = FALSE)
}
setwd(root)

db_path <- if (length(args_posicionais) >= 1L) {
  args_posicionais[[1]]
} else {
  file.path(root, "funding_intelligence.sqlite")
}
if (!file.exists(db_path)) {
  stop(sprintf("Base não encontrada: %s", db_path), call. = FALSE)
}
db_path <- normalizePath(db_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R", "helpers_utils.R"), encoding = "UTF-8")
source(file.path(root, "R", "helpers_taxonomy.R"), encoding = "UTF-8")
source(file.path(root, "R", "helpers_db.R"), encoding = "UTF-8")

cat(sprintf("Base: %s\n", db_path))
cat(sprintf("Force: %s\n\n", force))

conn <- get_db_connection(db_path)
on.exit(DBI::dbDisconnect(conn), add = TRUE)

if (!force && isTRUE(migration_marker(conn, "tipo_oportunidade_v1"))) {
  cat("Migração já aplicada (marker tipo_oportunidade_v1). Use --force para reaplicar.\n")
  quit(status = 0L)
}

backup_dir <- file.path(root, "backups")
ensure_dir(backup_dir)
backup_path <- file.path(
  backup_dir,
  sprintf(
    "%s.pre_tipo_oportunidade_%s.sqlite",
    tools::file_path_sans_ext(basename(db_path)),
    format(Sys.time(), "%Y%m%d_%H%M%S")
  )
)
backup_path_sql <- normalizePath(backup_path, winslash = "/", mustWork = FALSE)
backup_ok <- tryCatch(
  {
    DBI::dbExecute(conn, sprintf("VACUUM INTO '%s'", gsub("'", "''", backup_path_sql)))
    TRUE
  },
  error = function(e) {
    message(sprintf("Backup via VACUUM INTO falhou (%s); tentando cópia simples.", conditionMessage(e)))
    tryCatch(
      {
        DBI::dbExecute(conn, "PRAGMA wal_checkpoint(FULL)")
        file.copy(db_path, backup_path, overwrite = FALSE)
      },
      error = function(e2) {
        message(sprintf("Backup também falhou: %s", conditionMessage(e2)))
        FALSE
      }
    )
  }
)
if (isTRUE(backup_ok)) {
  cat(sprintf("Backup: %s\n", backup_path))
} else {
  stop("Não foi possível criar o backup; migração abortada.", call. = FALSE)
}

res <- tryCatch(
  migrate_tipo_oportunidade(conn, force = force),
  error = function(e) {
    message(sprintf("Falha na migração: %s", conditionMessage(e)))
    quit(status = 1L)
  }
)

if (!isTRUE(res$applied)) {
  cat("Migração já aplicada (marker tipo_oportunidade_v1). Use --force para reaplicar.\n")
  quit(status = 0L)
}

cat(sprintf("Registros processados: %d\n", res$total))
cat("\nCategorias:\n")
for (i in seq_len(nrow(res$counts))) {
  cat(sprintf("  %-24s %d\n", res$counts$categoria[[i]], res$counts$n[[i]]))
}
cat("\nOrigens:\n")
for (i in seq_len(nrow(res$origens))) {
  cat(sprintf("  %-10s %d\n", res$origens$origem[[i]], res$origens$n[[i]]))
}
cat("\nValores em Outros:\n")
if (nrow(res$unknown) == 0L) {
  cat("  (nenhum)\n")
} else {
  for (i in seq_len(nrow(res$unknown))) {
    cat(sprintf(
      "  %s: %d | exemplo: %s\n",
      res$unknown$valor[[i]],
      res$unknown$n[[i]],
      res$unknown$exemplo_titulo[[i]]
    ))
  }
}
if (!is.na(res$log_path)) {
  cat(sprintf("\nLog: %s\n", res$log_path))
}
cat("\nMigração concluída. Reinicie a aplicação para carregar a UI nova.\n")
