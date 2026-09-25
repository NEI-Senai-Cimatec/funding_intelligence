#!/usr/bin/env Rscript
# migrate_to_neon.R — Fase 4 da migração SQLite -> PostgreSQL (Neon.tech)
#
# Lê o funding_intelligence.sqlite local e grava todas as linhas no Postgres
# configurado em DATABASE_URL, com conversão de tipos (DATE, TIMESTAMPTZ,
# BOOLEAN, JSONB) e preservação dos IDs explícitos (IDENTITY BY DEFAULT).
#
# Uso:
#   Rscript migrate_to_neon.R                    # migra funding_intelligence.sqlite
#   Rscript migrate_to_neon.R --dry-run          # valida conexão/schema/contagens sem gravar
#   Rscript migrate_to_neon.R --sqlite=outro.db  # origem alternativa
#
# O script é idempotente: reexecuções fazem UPSERT (ON CONFLICT por chave
# primária). Execute-o ANTES de apontar o app para o Neon (ou aceite que o
# snapshot local sobrescreva o que estiver no destino).

# ─── Utilitários puros (testáveis sem conexão) ───────────────────────────────

.mig_date_cols <- c("data_publicacao", "data_abertura", "data_limite", "data_encerramento")
.mig_time_cols <- c(
  "data_hora_coleta", "enrichment_at", "applied_at", "created_at", "last_run_at",
  "tracked_at", "updated_at", "executed_at", "data_execucao", "timestamp"
)
.mig_json_cols <- c("payload_avancado", "filtros_json", "context")

mig_quote_ident <- function(x) paste0('"', gsub('"', '""', x), '"')

# SQL de UPSERT no dialect Postgres com placeholders nomeados (':col'),
# reescritos para '$n' por prepare_sql()/db_exec() dos helpers.
mig_pg_upsert_sql <- function(table, cols, pk) {
  q <- vapply(cols, mig_quote_ident, character(1), USE.NAMES = FALSE)
  q_pk <- mig_quote_ident(pk)
  non_pk <- cols[cols != pk]
  if (length(non_pk) == 0L) {
    return(sprintf(
      'INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO NOTHING',
      mig_quote_ident(table), paste(q, collapse = ", "),
      paste0(":", cols, collapse = ", "), q_pk
    ))
  }
  q_np <- vapply(non_pk, mig_quote_ident, character(1), USE.NAMES = FALSE)
  set_clause <- paste(sprintf("%s = excluded.%s", q_np, q_np), collapse = ", ")
  sprintf(
    'INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO UPDATE SET %s',
    mig_quote_ident(table), paste(q, collapse = ", "),
    paste0(":", cols, collapse = ", "), q_pk, set_clause
  )
}

mig_to_pg_value <- function(col, value) {
  if (col %in% .mig_date_cols) {
    return(parse_date_safe(value))
  }
  if (col %in% .mig_time_cols) {
    v <- as.character(value)
    if (length(v) == 0L || is.na(v) || !nzchar(trimws(v))) {
      return(as.POSIXct(NA, tz = "UTC"))
    }
    # Strings sem fuso são interpretadas como UTC (sessão fixada em UTC pelo
    # conectar_postgres), preservando a semântica atual do SQLite.
    return(tryCatch(
      {
        if (grepl("^\\d{4}-\\d{2}-\\d{2}", v)) {
          suppressWarnings(as.POSIXct(v, tz = "UTC", tryFormats = c(
            "%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d"
          )))
        } else {
          as.POSIXct(NA, tz = "UTC")
        }
      },
      error = function(e) as.POSIXct(NA, tz = "UTC")
    ))
  }
  if (col %in% .mig_json_cols) {
    v <- as.character(value)
    if (length(v) == 0L || is.na(v) || !nzchar(trimws(v))) {
      return(NA_character_)
    }
    if (!isTRUE(jsonlite::validate(v))) {
      warning(sprintf("[migrate] JSON inválido em '%s' migrado como NULL: %s", col, substr(v, 1, 80)), call. = FALSE)
      return(NA_character_)
    }
    return(v)
  }
  if (identical(col, "alerta_ativo")) {
    return(as.logical(value))
  }
  value
}

mig_convert_row <- function(src, i, cols) {
  row <- lapply(cols, function(cl) mig_to_pg_value(cl, src[[cl]][[i]]))
  names(row) <- cols
  row
}

# ─── Ordem de migração (respeita FKs) e chaves primárias ─────────────────────

mig_table_order <- c(
  "fontes_financiamento", "pesquisadores_vencedores", "oportunidades",
  "editais_rastreados", "projetos_aprovados", "migration_flags",
  "perfil_usuario", "buscas_salvas", "historico_buscas", "colaboradores",
  "logs_coleta", "metrics_coleta"
)

mig_pk_map <- c(
  fontes_financiamento = "id_fonte",
  pesquisadores_vencedores = "id",
  oportunidades = "id_registro",
  editais_rastreados = "id",
  projetos_aprovados = "id",
  migration_flags = "flag",
  perfil_usuario = "id",
  buscas_salvas = "id",
  historico_buscas = "id",
  colaboradores = "id",
  logs_coleta = "id",
  metrics_coleta = "id"
)

mig_count <- function(conn, table) {
  # as.numeric normaliza integer64 (RPostgres/Postgres) para double comum
  as.numeric(db_qry(conn, sprintf("SELECT COUNT(*) AS n FROM %s", mig_quote_ident(table)))$n[[1]])
}

# ─── Main ────────────────────────────────────────────────────────────────────

migrate_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  has_flag <- function(f) f %in% args
  get_opt <- function(name, default) {
    hit <- grep(paste0("^", name, "="), args, value = TRUE)
    if (length(hit) > 0L) sub(paste0("^", name, "="), "", hit[[1]]) else default
  }

  full_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", full_args, value = TRUE)
  app_dir <- if (length(file_arg) > 0L) {
    dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE))
  } else {
    getwd()
  }
  # Fallback: ao ser sourceado de outro diretório (testes), usa o working dir.
  if (!file.exists(file.path(app_dir, "R", "helpers_utils.R"))) {
    app_dir <- getwd()
  }
  if (!file.exists(file.path(app_dir, "R", "helpers_utils.R"))) {
    stop("Não localizei R/helpers_utils.R. Execute o script a partir da raiz do projeto.", call. = FALSE)
  }

  dry_run <- has_flag("--dry-run")
  sqlite_path <- get_opt("--sqlite", file.path(app_dir, "funding_intelligence.sqlite"))

  source(file.path(app_dir, "R", "helpers_utils.R"), encoding = "UTF-8")
  source(file.path(app_dir, "R", "helpers_db.R"), encoding = "UTF-8")

  database_url <- trimws(Sys.getenv("DATABASE_URL"))
  if (!nzchar(database_url)) {
    stop("DATABASE_URL não configurada. Exporte a URL do Neon antes de executar.", call. = FALSE)
  }
  if (!file.exists(sqlite_path)) {
    stop(sprintf("Banco SQLite de origem não encontrado: %s", sqlite_path), call. = FALSE)
  }

  message("== Migração SQLite -> PostgreSQL (Neon) ==")
  message("Origem:   ", sqlite_path)
  message("Destino:  ", sub("://[^@]*@", "://***@", database_url))
  if (dry_run) message("Modo:    DRY-RUN (nenhuma linha será escrita)")

  lite <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(if (DBI::dbIsValid(lite)) DBI::dbDisconnect(lite), add = TRUE)

  pg <- conectar_postgres(database_url)
  on.exit(if (DBI::dbIsValid(pg)) DBI::dbDisconnect(pg), add = TRUE)

  verificar_schema_postgres(pg)

  origem_counts <- integer(length(mig_table_order))
  names(origem_counts) <- mig_table_order

  for (t in mig_table_order) {
    src <- DBI::dbReadTable(lite, t)
    origem_counts[[t]] <- nrow(src)
    pg_cols <- DBI::dbListFields(pg, t)
    cols <- names(src)

    divergentes <- setdiff(union(cols, pg_cols), intersect(cols, pg_cols))
    if (length(divergentes) > 0L) {
      stop(sprintf(
        "Colunas divergentes entre SQLite e Postgres na tabela '%s': %s",
        t, paste(divergentes, collapse = ", ")
      ), call. = FALSE)
    }

    if (dry_run || nrow(src) == 0L) {
      message(sprintf(
        "[%s] %d linha(s) na origem | %d no destino (pré)",
        t, nrow(src), as.integer(mig_count(pg, t))
      ))
      next
    }

    sql <- mig_pg_upsert_sql(t, cols, mig_pk_map[[t]])
    n_ok <- 0L
    DBI::dbBegin(pg)
    tx_ok <- FALSE
    on.exit(if (!tx_ok && DBI::dbIsValid(pg)) try(DBI::dbRollback(pg), silent = TRUE), add = TRUE)
    for (i in seq_len(nrow(src))) {
      row <- mig_convert_row(src, i, cols)
      res <- tryCatch(
        {
          db_exec(pg, sql, params = row)
          TRUE
        },
        error = function(e) {
          stop(sprintf(
            "Falha ao migrar %s linha %d/%d (id=%s): %s",
            t, i, nrow(src), as.character(src[[mig_pk_map[[t]]]][[i]]), conditionMessage(e)
          ), call. = FALSE)
        }
      )
      if (isTRUE(res)) n_ok <- n_ok + 1L
    }
    DBI::dbCommit(pg)
    tx_ok <- TRUE
    message(sprintf("[%s] %d linha(s) migrada(s).", t, n_ok))
  }

  # Realinha as sequências IDENTITY com os IDs explícitos migrados.
  if (!dry_run) {
    ident <- db_qry(
      pg,
      "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'public' AND is_identity = 'YES'"
    )
    for (k in seq_len(nrow(ident))) {
      t <- ident$table_name[[k]]
      pk <- ident$column_name[[k]]
      mx <- db_qry(pg, sprintf("SELECT COALESCE(MAX(%s), 0) AS m FROM %s", mig_quote_ident(pk), mig_quote_ident(t)))$m[[1]]
      if (isTRUE(as.numeric(mx) > 0)) {
        db_exec(pg, "SELECT setval(pg_get_serial_sequence(?, ?), ?, true)", params = list(t, pk, as.integer(mx)))
      } else {
        db_exec(pg, "SELECT setval(pg_get_serial_sequence(?, ?), 1, false)", params = list(t, pk))
      }
    }
    message("[sequences] Identities realinhadas.")
  }

  # Validação final: contagens origem x destino
  destino <- vapply(mig_table_order, function(t) mig_count(pg, t), numeric(1))
  rel <- data.frame(
    tabela = mig_table_order,
    sqlite = as.numeric(origem_counts[mig_table_order]),
    postgres = destino,
    ok = as.numeric(origem_counts[mig_table_order]) == destino,
    row.names = NULL
  )
  message("\n== Validação de contagens ==")
  print(rel, row.names = FALSE)

  if (dry_run) {
    message("\nDRY_RUN_OK — conexão, schema e contagens verificados; nada foi gravado.")
    return(invisible(rel))
  }

  if (any(!rel$ok)) {
    stop(sprintf(
      "Migração incompleta — contagens divergentes em: %s",
      paste(rel$tabela[!rel$ok], collapse = ", ")
    ), call. = FALSE)
  }
  message("\nMIGRACAO_OK — todas as tabelas migradas com contagens conferidas.")
  invisible(rel)
}

if (sys.nframe() == 0L) {
  migrate_main()
}
