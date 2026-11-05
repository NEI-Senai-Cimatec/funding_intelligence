#!/usr/bin/env Rscript
# Migra a base SQLite local para o Postgres/Neon configurado em DATA_BASE_URL.
#
# Uso:
#   $env:DATA_BASE_URL = "postgresql://..."
#   Rscript migrations/2026-11-05_sqlite_to_neon.R
#   Rscript migrations/2026-11-05_sqlite_to_neon.R caminho/base.sqlite --force
#
# Sem --force, aborta se o destino já tiver oportunidades. Com --force,
# trunca as tabelas do app e recopia tudo em uma única transação.

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

sqlite_path <- if (length(args_posicionais) >= 1L) {
  args_posicionais[[1]]
} else {
  file.path(root, "funding_intelligence.sqlite")
}
if (!file.exists(sqlite_path)) {
  stop(sprintf("Base SQLite não encontrada: %s", sqlite_path), call. = FALSE)
}
sqlite_path <- normalizePath(sqlite_path, winslash = "/", mustWork = TRUE)

url <- Sys.getenv("DATA_BASE_URL", unset = "")
if (!nzchar(url)) url <- Sys.getenv("DATABASE_URL", unset = "")
if (!nzchar(url)) {
  stop("Defina DATA_BASE_URL com a connection string do Neon/Postgres.", call. = FALSE)
}

source(file.path(root, "R", "helpers_utils.R"), encoding = "UTF-8")
source(file.path(root, "R", "helpers_taxonomy.R"), encoding = "UTF-8")
source(file.path(root, "R", "helpers_db.R"), encoding = "UTF-8")

u <- httr::parse_url(url)
cat(sprintf("Origem SQLite: %s\n", sqlite_path))
cat(sprintf("Destino Postgres: %s/%s\n", u$hostname, u$path))
cat(sprintf("Force: %s\n\n", force))

sqlite_conn <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
on.exit(DBI::dbDisconnect(sqlite_conn), add = TRUE)

pg_conn <- get_db_connection("ignored.sqlite")
on.exit(DBI::dbDisconnect(pg_conn), add = TRUE)
if (!identical(db_backend(pg_conn), "postgres")) {
  stop("DATA_BASE_URL não produziu uma conexão Postgres.", call. = FALSE)
}

create_tables(pg_conn)

tables <- c(
  "fontes_financiamento",
  "oportunidades",
  "migration_flags",
  "buscas_salvas",
  "editais_rastreados",
  "perfil_usuario",
  "historico_buscas",
  "colaboradores",
  "logs_coleta",
  "pesquisadores_vencedores",
  "projetos_aprovados",
  "metrics_coleta"
)
serial_tables <- c(
  "buscas_salvas",
  "editais_rastreados",
  "perfil_usuario",
  "historico_buscas",
  "colaboradores",
  "logs_coleta",
  "pesquisadores_vencedores",
  "projetos_aprovados",
  "metrics_coleta"
)

existing <- db_get_query(pg_conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]]
if (as.numeric(existing) > 0 && !force) {
  stop(
    sprintf(
      "O destino já tem %s oportunidade(s). Use --force para truncar e recopiar.",
      existing
    ),
    call. = FALSE
  )
}

in_tx <- FALSE
DBI::dbBegin(pg_conn)
in_tx <- TRUE
on.exit(
  if (in_tx) try(DBI::dbRollback(pg_conn), silent = TRUE),
  add = TRUE
)

if (force) {
  DBI::dbExecute(pg_conn, sprintf(
    "TRUNCATE TABLE %s RESTART IDENTITY CASCADE",
    paste(tables, collapse = ", ")
  ))
}

cat("Copiando tabelas...\n")
for (table_name in tables) {
  df <- DBI::dbReadTable(sqlite_conn, table_name)
  n <- nrow(df)
  if (n == 0L) {
    cat(sprintf("  %-28s %6d (vazia, ignorada)\n", table_name, n))
    next
  }
  DBI::dbWriteTable(pg_conn, table_name, df, append = TRUE, row.names = FALSE)
  cat(sprintf("  %-28s %6d\n", table_name, n))
}

for (table_name in serial_tables) {
  DBI::dbExecute(
    pg_conn,
    sprintf(
      "SELECT setval(pg_get_serial_sequence('%s','id'), COALESCE(MAX(id), 1), MAX(id) IS NOT NULL) FROM %s",
      table_name, table_name
    )
  )
}

DBI::dbCommit(pg_conn)
in_tx <- FALSE

cat("\nVerificação de contagens:\n")
ok <- TRUE
for (table_name in tables) {
  local_n <- as.numeric(DBI::dbGetQuery(
    sqlite_conn,
    sprintf("SELECT COUNT(*) AS n FROM %s", table_name)
  )$n[[1]])
  remote_n <- as.numeric(db_get_query(
    pg_conn,
    sprintf("SELECT COUNT(*) AS n FROM %s", table_name)
  )$n[[1]])
  status <- if (identical(local_n, remote_n)) "OK" else "DIVERGENTE"
  if (!identical(local_n, remote_n)) ok <- FALSE
  cat(sprintf("  %-28s local=%6.0f remoto=%6.0f  %s\n", table_name, local_n, remote_n, status))
}
if (!ok) {
  stop("Contagens divergentes após a migração.", call. = FALSE)
}

cat("\nMigração concluída com sucesso.\n")
