# ─── Saneamento retroativo dos registros brasileiros (R07 / T24) ──────────────
# Princípios:
#  * Dry run é o padrão: `sanitize_br_plan()` nunca escreve.
#  * `sanitize_br_apply()` é transacional, idempotente e registra ANTES/DEPOIS em `saneamento_log`.
#  * Quarentena é reversível (UPDATE de validacao_*; nenhum DELETE). Rollback por lote.
#  * Campos só são limpos quando sua ORIGEM ARTIFICIAL é demonstrada (data de coleta + N dias e
#    metadados fixos dos coletores antigos). Dados incertos ficam em revisão até serem recoletados.
#  * Registros internacionais e fontes fora da lista NUNCA são tocados.
#  * Favoritos/observações (editais_rastreados) são preservados; renomeações geram mapa em id_aliases.

SANITIZE_BR_SOURCES <- c("anp_shell", "sigitec", "bnb_fundeci", "aeb", "bndes", "fab_dcta", "embrapa", "funcap", "bnb_hubine")
# Coletores antigos que gravavam metadados fixos (elegibilidade, nível acadêmico, área...) sem extração.
SANITIZE_FIXED_METADATA_SOURCES <- c("aeb", "fab_dcta", "bnb_fundeci", "embrapa", "anp_shell")
# Varredura (mesmo defeito estrutural, fora dos 8 grupos): apenas datas artificiais demonstradas.
SANITIZE_SWEEP_SOURCES <- c("codevasf", "sudene", "pncp_gov", "sebrae", "fapesp", "faperj")
SANITIZE_ARTIFICIAL_DEADLINE_DAYS <- c(40L, 45L, 60L, 90L)
SANITIZE_CLEARABLE_FIELDS <- c("elegibilidade", "publico_alvo", "nivel_academico", "modalidade", "area_tematica", "palavras_chave")
SANITIZE_SYNTH_VALUES <- c(bnb_fundeci = 8000000, anp_shell = 3500000)

.san_json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, na = "null", null = "null", digits = NA))

.san_has_artificial_dates <- function(pub, lim, coleta, fonte, fontes_scope) {
  if (!(fonte %in% fontes_scope)) return(FALSE)
  dp <- suppressWarnings(as.Date(substr(as.character(pub), 1, 10)))
  dl <- suppressWarnings(as.Date(substr(as.character(lim), 1, 10)))
  dc <- suppressWarnings(as.Date(substr(as.character(coleta), 1, 10)))
  if (is.na(dc)) return(FALSE)
  pub_art <- !is.na(dp) && dp == dc
  lim_art <- !is.na(dl) && as.integer(dl - dc) %in% SANITIZE_ARTIFICIAL_DEADLINE_DAYS
  (pub_art && lim_art) || (is.na(dp) && lim_art) || (pub_art && is.na(dl))
}

# Plano (somente leitura). Uma linha por registro avaliado, com o antes/depois proposto.
sanitize_br_plan <- function(conn, fontes = SANITIZE_BR_SOURCES, ids = NULL, include_sweep = FALSE, now = NULL) {
  now <- now %||% Sys.time()
  scope <- unique(c(fontes, if (isTRUE(include_sweep)) SANITIZE_SWEEP_SOURCES))
  cols <- DBI::dbListFields(conn, "oportunidades")
  for (nm in setdiff(c("validacao_status", "validacao_motivo", "validacao_versao", "tipo_escopo"), cols)) {
    stop(sprintf("Coluna '%s' ausente: execute migrate_br_integrity_columns() antes do saneamento.", nm), call. = FALSE)
  }
  ph <- paste(rep("?", length(scope)), collapse = ", ")
  df <- db_qry(conn, sprintf("SELECT * FROM oportunidades WHERE pais_origem = 'Brasil' AND fonte_oficial IN (%s)", ph), params = as.list(scope))
  df <- tibble::as_tibble(df)
  if (!is.null(ids)) df <- df[df$id_registro %in% ids, , drop = FALSE]
  empty <- tibble::tibble(id_registro = character(), fonte_oficial = character(), titulo = character(),
                          tipo_escopo = character(), estado_antes = character(), estado_depois = character(),
                          motivo = character(), campos_limpos = character(), novo_id = character(), acao = character())
  if (nrow(df) == 0L) return(empty)
  existing_ids <- DBI::dbGetQuery(conn, "SELECT id_registro FROM oportunidades")$id_registro
  rows <- lapply(seq_len(nrow(df)), function(i) {
    r <- df[i, ]
    fonte <- r$fonte_oficial
    manual <- !is.na(r$validacao_motivo) && startsWith(r$validacao_motivo, "manual:")
    desc <- paste(r$descricao_resumida %||% "", "")
    val <- validate_opportunity(r$titulo %||% "", desc, r$link_detalhe %||% r$link_origem %||% "", fonte,
                                evidencia_chamada = FALSE, id_registro = r$id_registro, now = now)
    tipo <- val$tipo_escopo
    dec <- unname(SCOPE_DECISION[tipo]); if (is.na(dec)) dec <- "revisar"
    depois <- if (manual) r$validacao_status else if (dec %in% c("quarentena", "rejeitar")) "quarentena" else "a_verificar"
    motivo <- if (manual) r$validacao_motivo else sprintf("saneamento_br:%s;tipo=%s", if (depois == "quarentena") "fora_do_escopo_ou_sintetico" else "sem_evidencia_estruturada", tipo)
    limpar <- character()
    art <- !manual && depois != "quarentena" &&
      .san_has_artificial_dates(r$data_publicacao, r$data_limite, r$data_hora_coleta, fonte, c(SANITIZE_BR_SOURCES, SANITIZE_SWEEP_SOURCES))
    if (art) {
      limpar <- c(limpar, intersect(c("data_publicacao", "data_limite"), cols))
      if (fonte %in% SANITIZE_FIXED_METADATA_SOURCES) limpar <- c(limpar, intersect(SANITIZE_CLEARABLE_FIELDS, cols))
      sv <- unname(SANITIZE_SYNTH_VALUES[fonte])
      if (!is.na(sv) && !is.na(r$valor_financiado) && isTRUE(as.numeric(r$valor_financiado) == sv)) limpar <- c(limpar, "valor_financiado")
    }
    novo_id <- NA_character_
    if (!manual && depois != "quarentena" && fonte %in% c("fab_dcta", "bnb_fundeci", "funcap", "bndes")) {
      cid <- extract_call_id(r$titulo %||% "")
      if (!is.na(cid) && fonte %in% c("fab_dcta", "bndes")) {
        cand <- stable_opportunity_id(fonte, call_id = cid)
        if (!identical(cand, r$id_registro) && !(cand %in% existing_ids)) novo_id <- cand
      }
    }
    mudou <- !identical(as.character(r$validacao_status), depois) || !identical(as.character(r$validacao_versao), VALIDATOR_VERSION) ||
      !identical(as.character(r$tipo_escopo), tipo) || length(limpar) > 0L || !is.na(novo_id)
    if (manual) mudou <- FALSE
    acao <- if (!mudou) "nenhuma" else paste(c(
      if (!identical(as.character(r$validacao_status), depois)) paste0("estado->", depois) else "revalidar",
      if (length(limpar)) "limpar_campos", if (!is.na(novo_id)) "renomear_id"), collapse = "+")
    tibble::tibble(id_registro = r$id_registro, fonte_oficial = fonte, titulo = substr(r$titulo %||% "", 1L, 90),
                   tipo_escopo = tipo, estado_antes = as.character(r$validacao_status), estado_depois = depois,
                   motivo = motivo, campos_limpos = paste(limpar, collapse = ","), novo_id = novo_id, acao = acao)
  })
  dplyr::bind_rows(rows)
}

sanitize_br_summary <- function(plan) {
  if (is.null(plan) || nrow(plan) == 0L) return(tibble::tibble())
  plan |>
    dplyr::group_by(fonte_oficial) |>
    dplyr::summarise(
      total = dplyr::n(), quarentena = sum(estado_depois == "quarentena"), a_verificar = sum(estado_depois == "a_verificar"),
      validado = sum(estado_depois == "validado"), campos_limpos = sum(nzchar(campos_limpos)),
      renomeados = sum(!is.na(novo_id)), pendentes = sum(acao != "nenhuma"), .groups = "drop")
}

.san_row_cols <- function(conn) DBI::dbListFields(conn, "oportunidades")

# Aplicação transacional e idempotente.
sanitize_br_apply <- function(conn, plan, batch_id = NULL, now = NULL) {
  now <- now %||% Sys.time()
  batch_id <- batch_id %||% format(now, "san_%Y%m%d_%H%M%S")
  pend <- plan[plan$acao != "nenhuma", , drop = FALSE]
  if (nrow(pend) == 0L) return(invisible(list(batch_id = batch_id, aplicados = 0L, mensagem = "nada a fazer (idempotente)")))
  cols <- .san_row_cols(conn)
  ts <- format(now, "%Y-%m-%d %H:%M:%S")
  n_ok <- 0L
  DBI::dbBegin(conn)
  ok <- FALSE
  on.exit(if (!ok) try(DBI::dbRollback(conn), silent = TRUE), add = TRUE)
  for (i in seq_len(nrow(pend))) {
    p <- pend[i, ]
    antes <- db_qry(conn, "SELECT * FROM oportunidades WHERE id_registro = ?", params = list(p$id_registro))
    if (nrow(antes) == 0L) next
    antes_json <- .san_json(as.list(antes[1, , drop = FALSE]))
    sets <- c("validacao_status = ?", "validacao_motivo = ?", "validacao_evidencia = ?", "validacao_versao = ?", "validacao_em = ?", "tipo_escopo = ?")
    params <- list(p$estado_depois, p$motivo, substr(paste(p$titulo, "|", antes$link_detalhe[[1]] %||% ""), 1L, 400L),
                   VALIDATOR_VERSION, ts, p$tipo_escopo)
    limpos <- if (nzchar(p$campos_limpos)) strsplit(p$campos_limpos, ",", fixed = TRUE)[[1]] else character()
    for (cn in limpos) sets <- c(sets, sprintf("%s = NULL", cn))
    if (length(limpos)) {
      # estado legado recalculado sem datas artificiais; campus re-inferido só do objeto (título/descrição)
      sets <- c(sets, "status_oportunidade = ?")
      params <- c(params, list("desconhecido"))
      cp <- infer_campus_candidates(antes$titulo[[1]], antes$descricao_resumida[[1]] %||% "", "", "")
      sets <- c(sets, "campus = ?", "campus_justificativa = ?")
      params <- c(params, list(if (nrow(cp)) paste(cp$campus, collapse = "; ") else NA_character_,
                               if (nrow(cp)) paste0("Sugest\u00e3o por regra br-campus-1.0 (n\u00e3o extra\u00eddo do edital): ", paste(sprintf("%s [%s]", cp$campus, cp$evidencias), collapse = " | ")) else NA_character_))
    } else if (p$estado_depois == "quarentena") {
      # sem alterar dados; apenas escondemos do universo público via validacao_status
    }
    params <- c(params, list(p$id_registro))
    db_exec(conn, sprintf("UPDATE oportunidades SET %s WHERE id_registro = ?", paste(sets, collapse = ", ")), params = params)
    depois_id <- p$id_registro
    if (!is.na(p$novo_id)) {
      novo_hash <- digest::digest(paste0(p$novo_id, "|", canonical_url(antes$link_detalhe[[1]])), algo = "xxhash64")
      db_exec(conn, "UPDATE oportunidades SET id_registro = ?, hash_deduplicacao = ? WHERE id_registro = ?", params = list(p$novo_id, novo_hash, p$id_registro))
      db_exec(conn, "UPDATE editais_rastreados SET id_oportunidade = ? WHERE id_oportunidade = ?", params = list(p$novo_id, p$id_registro))
      db_exec(conn, "INSERT INTO id_aliases (id_antigo, id_novo, motivo, criado_em) VALUES (?, ?, ?, ?) ON CONFLICT(id_antigo) DO UPDATE SET id_novo = excluded.id_novo, motivo = excluded.motivo, criado_em = excluded.criado_em",
              params = list(p$id_registro, p$novo_id, paste0("saneamento:", batch_id), ts))
      depois_id <- p$novo_id
    }
    depois <- db_qry(conn, "SELECT * FROM oportunidades WHERE id_registro = ?", params = list(depois_id))
    db_exec(conn, "INSERT INTO saneamento_log (batch_id, id_registro, acao, justificativa, antes_json, depois_json, criado_em) VALUES (?, ?, ?, ?, ?, ?, ?)",
            params = list(batch_id, p$id_registro, p$acao, p$motivo, antes_json, .san_json(as.list(depois[1, , drop = FALSE])), ts))
    n_ok <- n_ok + 1L
  }
  DBI::dbCommit(conn)
  ok <- TRUE
  invisible(list(batch_id = batch_id, aplicados = n_ok, mensagem = sprintf("%d registro(s) saneado(s) no lote %s", n_ok, batch_id)))
}

# Rollback por lote: restaura o estado ANTES (todas as colunas) e reverte renomeações de ID.
sanitize_br_rollback <- function(conn, batch_id, now = NULL) {
  now <- now %||% Sys.time()
  ts <- format(now, "%Y-%m-%d %H:%M:%S")
  logs <- db_qry(conn, "SELECT * FROM saneamento_log WHERE batch_id = ? AND revertido_em IS NULL ORDER BY id DESC", params = list(batch_id))
  if (nrow(logs) == 0L) return(invisible(list(batch_id = batch_id, revertidos = 0L)))
  cols <- .san_row_cols(conn)
  n <- 0L
  DBI::dbBegin(conn); ok <- FALSE
  on.exit(if (!ok) try(DBI::dbRollback(conn), silent = TRUE), add = TRUE)
  for (i in seq_len(nrow(logs))) {
    antes <- jsonlite::fromJSON(logs$antes_json[[i]], simplifyVector = FALSE)
    depois <- jsonlite::fromJSON(logs$depois_json[[i]], simplifyVector = FALSE)
    cur_id <- depois$id_registro %||% logs$id_registro[[i]]
    old_id <- logs$id_registro[[i]]
    use <- intersect(names(antes), cols)
    vals <- lapply(use, function(cn) { v <- antes[[cn]]; if (is.null(v)) NA else v })
    sets <- paste(sprintf("%s = ?", use), collapse = ", ")
    db_exec(conn, sprintf("UPDATE oportunidades SET %s WHERE id_registro = ?", sets), params = c(vals, list(cur_id)))
    if (!identical(cur_id, old_id)) {
      db_exec(conn, "UPDATE editais_rastreados SET id_oportunidade = ? WHERE id_oportunidade = ?", params = list(old_id, cur_id))
      db_exec(conn, "DELETE FROM id_aliases WHERE id_antigo = ?", params = list(old_id))
    }
    db_exec(conn, "UPDATE saneamento_log SET revertido_em = ? WHERE id = ?", params = list(ts, logs$id[[i]]))
    n <- n + 1L
  }
  DBI::dbCommit(conn); ok <- TRUE
  invisible(list(batch_id = batch_id, revertidos = n))
}
