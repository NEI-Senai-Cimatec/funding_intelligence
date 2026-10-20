# ─── Coletores brasileiros dedicados (openspec: brazilian-sources-data-integrity) ─
# Fontes: BNB FUNDECI, AEB, FUNCAP, Embrapa, Hubine BNB (este arquivo) e
#         SIGITEC, BNDES, DCTA/FAB (helpers_sources_br_federal.R).
#
# Regras que TODOS os adaptadores seguem:
#  * Nenhum conteúdo de exemplo/fallback: zero itens válidos => zero registros.
#  * Parsers puros (HTML/JSON/PDF-texto in -> tibble out): testáveis offline.
#  * Datas/valores/elegibilidade só quando extraídos do documento; senão NA.
#  * Estado oficial (`status_oficial`) separado do estado derivado (helpers_status.R).
#  * Cada registro tem identidade estável, proveniência por campo e validação.
#  * HTML, PDFs e saídas de modelos são DADOS: nenhuma instrução neles é executada.

BR_SOURCE_ALIASES <- c(anp_shell = "sigitec")

resolve_source_aliases <- function(ids) {
  if (is.null(ids)) return(ids)
  ids <- as.character(ids)
  hit <- ids %in% names(BR_SOURCE_ALIASES)
  ids[hit] <- unname(BR_SOURCE_ALIASES[ids[hit]])
  unique(ids)
}

BR_CANONICAL_URLS <- list(
  sigitec = "https://sigitec-competitividade.petrobras.com.br/v2/public/opportunities",
  bnb_fundeci = "https://www.bnb.gov.br/fundeci/editais",
  aeb = "https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos",
  bndes = "https://www.bndes.gov.br/wps/portal/site/home/transparencia/licitacoes-contratos/licitacoes/",
  fab_dcta = "https://ieav.dcta.mil.br/index.php/editais",
  embrapa = "https://www.embrapa.br/acessoainformacao/editais",
  funcap = "https://www.funcap.ce.gov.br/editais/",
  funcap_montenegro = "https://montenegro.funcap.ce.gov.br/sugba/editais/index_montenegro.php",
  bnb_hubine = "https://www.bnb.gov.br/hub-de-inovacao"
)

# URLs legadas persistidas em `fontes_financiamento` que devem ser substituídas.
BR_LEGACY_URL_PATTERNS <- c(
  bnb_fundeci = "ConveniosWeb",
  bndes = "onde-estamos/licitacoes-e-compras",
  bnb_hubine = "bnb\\.gov\\.br/hubine/?$",
  sigitec = "NEVER_MATCHES"
)

br_source_url <- function(source_row, id) {
  canon <- BR_CANONICAL_URLS[[id]]
  cur <- tryCatch(as.character(source_row$url_oportunidades[[1]]), error = function(e) NA_character_)
  if (is.null(cur) || length(cur) == 0L || is.na(cur) || !nzchar(cur)) return(canon)
  pat <- unname(BR_LEGACY_URL_PATTERNS[id])
  if (length(pat) == 1L && !is.na(pat) && grepl(pat, cur)) return(canon)
  cur
}

br_now <- function() {
  x <- getOption("fi.br_now", NULL)
  if (is.null(x)) Sys.time() else as.POSIXct(x, tz = STATUS_TZ)
}

br_today <- function() as.Date(lubridate::with_tz(br_now(), STATUS_TZ))

.br_ws <- function(x) normalize_ws(as.character(x %||% ""))

# ─── Aquisição ────────────────────────────────────────────────────────────────

# Página HTML. `options(fi.br_fetcher = function(url) list(ok, text, final_url, http_status, ...))`
# permite injetar fixtures. Em produção usa safe_request_page (TLS validado).
br_fetch <- function(url, log_path = NULL) {
  t0 <- Sys.time()
  res <- safe_request_page(url, log_path = log_path)
  acq <- res$acq %||% classify_acquisition(res$text %||% NA_character_, 200L, error = res$error %||% NA_character_)
  list(url = url, final_url = as.character(res$final_url %||% url), ok = isTRUE(res$ok) && isTRUE(acq$ok),
       text = if (isTRUE(res$ok)) as.character(res$text) else NA_character_,
       acq = acq, http_status = res$http_status %||% NA_integer_,
       latency = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

# Texto de PDF (TLS validado). `options(fi.br_pdf_fetcher = function(url) text|NA)` para testes.
br_fetch_pdf_text <- function(url, log_path = NULL) {
  injected <- getOption("fi.br_pdf_fetcher", NULL)
  if (is.function(injected)) return(injected(url))
  if (is.na(url) || !nzchar(url) || !requireNamespace("pdftools", quietly = TRUE)) return(NA_character_)
  tmp <- tempfile(fileext = ".pdf")
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch({
    hdr <- build_scrape_headers()
    httr2::request(url) |>
      httr2::req_user_agent(hdr$`User-Agent`) |>
      httr2::req_timeout(30) |>
      httr2::req_retry(max_tries = 2) |>
      httr2::req_perform(path = tmp)
    TRUE
  }, error = function(e) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("PDF indisponivel %s: %s", url, conditionMessage(e)))
    FALSE
  })
  if (!ok || !file.exists(tmp)) return(NA_character_)
  tryCatch(paste(pdftools::pdf_text(tmp), collapse = "\n"), error = function(e) NA_character_)
}

# JSON público (TLS validado). Injetável por `options(fi.br_json_fetcher=)`.
# Retorna list(ok, status, body, error, kind).
br_fetch_json_text <- function(url, log_path = NULL, headers = list()) {
  injected <- getOption("fi.br_json_fetcher", NULL)
  if (is.function(injected)) return(injected(url))
  hdr <- build_scrape_headers()
  req <- httr2::request(url) |>
    httr2::req_user_agent(hdr$`User-Agent`) |>
    httr2::req_headers(Accept = "application/json, text/plain, */*", !!!headers) |>
    httr2::req_timeout(45) |>
    httr2::req_retry(max_tries = 2, backoff = function(i) 2^i)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (!inherits(resp, "error") || !is.null(resp$response)) {
    r <- if (inherits(resp, "error")) resp$response else resp
    st <- httr2::resp_status(r)
    body <- tryCatch(httr2::resp_body_string(r), error = function(e) NA_character_)
    if (st >= 200 && st < 300) return(list(ok = TRUE, status = st, body = body))
    return(list(ok = FALSE, status = st, body = body, error = sprintf("HTTP %d", st),
                kind = if (st %in% c(401L, 403L, 429L)) "blocked" else "http_error"))
  }
  msg <- conditionMessage(resp)
  if (grepl("ssl|tls|certificate", tolower(msg))) {
    return(list(ok = FALSE, status = NA_integer_, body = NA_character_, error = msg, kind = "tls_error"))
  }
  # Fallback de aquisição (curl_cffi via tools/stealth_fetch.py; TLS permanece validado)
  st <- safe_request_page_stealth(url, log_path = log_path)
  if (isTRUE(st$ok)) return(list(ok = TRUE, status = 200L, body = st$text))
  list(ok = FALSE, status = NA_integer_, body = NA_character_, error = st$error %||% msg,
       kind = st$error_kind %||% "network_error")
}

br_unwrap_safelink <- function(url) {
  u <- as.character(url %||% NA_character_)
  if (is.na(u) || !grepl("safelinks\\.protection\\.outlook\\.com", u)) return(u)
  m <- regmatches(u, regexec("[?&]url=([^&]+)", u))[[1]]
  if (length(m) == 2L) return(utils::URLdecode(m[[2]]))
  u
}

br_abs_url <- function(base, href) {
  href <- as.character(href %||% NA_character_)
  if (is.na(href) || !nzchar(href)) return(NA_character_)
  href <- gsub("&amp;", "&", href, fixed = TRUE)
  if (grepl("^(javascript|mailto|tel):", href, ignore.case = TRUE) || startsWith(href, "#")) return(NA_character_)
  out <- tryCatch(xml2::url_absolute(href, base), error = function(e) NA_character_)
  br_unwrap_safelink(out)
}

br_html <- function(text) xml2::read_html(as.character(text), encoding = "UTF-8")

# ─── Extração textual auxiliar ────────────────────────────────────────────────

# Valor em R$ ("R$ 30,0 milhões", "R$ 300 mil", "R$ 8.000.000,00") -> numeric
br_parse_brl <- function(s) {
  s <- as.character(s %||% NA_character_)
  if (is.na(s)) return(NA_real_)
  m <- regmatches(s, regexec("(?i)R\\$\\s*([0-9][0-9.,]*)\\s*(milh[\u00f5o]es|milh[\u00e3a]o|mil|bilh[\u00f5o]es|bilh[\u00e3a]o)?", s, perl = TRUE))[[1]]
  if (length(m) < 2L) return(NA_real_)
  num <- gsub("\\.(?=\\d{3}(\\D|$))", "", m[[2]], perl = TRUE)
  num <- suppressWarnings(as.numeric(sub(",", ".", num, fixed = TRUE)))
  if (is.na(num)) return(NA_real_)
  mult <- if (length(m) >= 3L && nzchar(m[[3]])) {
    u <- normalize_text(m[[3]])
    if (grepl("^bilh", u)) 1e9 else if (grepl("^milh", u)) 1e6 else 1e3
  } else 1
  num * mult
}

# Prazo de submissão em texto corrido: "enviar ... até 05/04/2026" (NUNCA máximo global).
br_extract_deadline_text <- function(text) {
  t <- gsub("\u00a0", " ", as.character(text %||% ""), fixed = TRUE)
  t <- gsub("\\s+", " ", t)
  if (!nzchar(t)) return(as.Date(NA))
  if (grepl("T[0-9]\\s*=\\s*T?[0-9]?\\s*\\+", t)) {
    # cronograma relativo (T0, T1...): sem T0 publicado não há data absoluta de submissão
    return(extract_submission_deadline_strict(t))
  }
  verbs <- "(?:enviar|envio|enviem|inscri\\w+|apresent\\w+|submet\\w+|submiss\\w+|candidat\\w+|propost\\w+|curr[i\u00ed]culo|cadastr\\w+)"
  dt <- "(\\d{1,2}/\\d{1,2}/\\d{2,4})"
  p1 <- sprintf("(?i)%s[^.;]{0,140}?\\b(?:at\u00e9|ate)\\s+(?:o\\s+dia\\s+|dia\\s+)?%s", verbs, dt)
  m <- regmatches(t, regexec(p1, t, perl = TRUE))[[1]]
  if (length(m) == 2L) return(parse_br_date_token(m[[2]]))
  p2 <- sprintf("(?i)\\b(?:at\u00e9|ate)\\s+(?:o\\s+dia\\s+|dia\\s+)?%s[^.;]{0,80}?%s", dt, verbs)
  m <- regmatches(t, regexec(p2, t, perl = TRUE))[[1]]
  if (length(m) == 2L) return(parse_br_date_token(m[[2]]))
  p3 <- sprintf("(?i)prazo[^.;]{0,60}?(?:submiss\\w+|inscri\\w+|envio|propost\\w+)[^.;]{0,60}?%s", dt)
  m <- regmatches(t, regexec(p3, t, perl = TRUE))[[1]]
  if (length(m) == 2L) return(parse_br_date_token(m[[2]]))
  extract_submission_deadline_strict(t)
}

br_has_relative_schedule <- function(text) {
  grepl("T[0-9]\\s*=\\s*T?[0-9]?\\s*\\+", gsub("\\s+", " ", as.character(text %||% "")))
}

# ─── Construção, validação e finalização de registros ────────────────────────

BR_EXTRA_COLUMNS <- c("status_oficial", "fluxo_continuo", "id_chamada", "tipo_escopo", "validacao_status",
                      "validacao_motivo", "validacao_evidencia", "validacao_versao", "validacao_em",
                      "proveniencia_json", "campus_justificativa", "valor_teto_projeto", "data_vigencia_fim")

br_record <- function(fonte, entidade, nome_fonte, titulo, link_origem, link_detalhe = NA_character_,
                      link_pdf = NA_character_, descricao = NA_character_, descricao_completa = NA_character_,
                      tipo_oportunidade = "edital", modalidade = NA_character_, area = NA_character_,
                      elegibilidade = NA_character_, publico_alvo = NA_character_,
                      valor_total = NA_real_, valor_teto = NA_real_, moeda = NA_character_,
                      data_publicacao = NA, data_abertura = NA, data_limite = NA, data_vigencia_fim = NA,
                      status_oficial = NA_character_, fluxo_continuo = NA, id_chamada = NA_character_,
                      observacoes = NA_character_, texto_bruto = NA_character_, pagina = 1L,
                      provenance = list(), tipo_escopo = NA_character_, tipo_default = NA_character_,
                      detalhe_ok = TRUE, idioma = "pt", localidade = "Brasil", now = NULL) {
  now <- now %||% br_now()
  fmt <- function(x) {
    if (inherits(x, "Date")) return(if (is.na(x)) NA_character_ else format(x, "%Y-%m-%d"))
    x <- as.character(x %||% NA_character_)
    if (length(x) == 0L || is.na(x[[1]]) || !nzchar(x[[1]])) NA_character_ else x[[1]]
  }
  dl <- fmt(data_limite); ab <- fmt(data_abertura); pub <- fmt(data_publicacao); vig <- fmt(data_vigencia_fim)
  so <- normalize_status_oficial(status_oficial)
  fc <- if (isTRUE(fluxo_continuo)) 1L else NA_integer_
  url_id <- if (!is.na(link_detalhe) && nzchar(link_detalhe)) link_detalhe else link_pdf
  id <- stable_opportunity_id(fonte, call_id = id_chamada, url = url_id, title = titulo)
  hash <- digest::digest(paste0(id, "|", canonical_url(url_id)), algo = "xxhash64")

  obj_text <- paste(titulo, descricao %||% "", descricao_completa %||% "", area %||% "")
  camp <- infer_campus_candidates(titulo, paste(descricao %||% "", descricao_completa %||% ""), area, "")
  campus <- if (nrow(camp)) paste(camp$campus, collapse = "; ") else NA_character_
  camp_just <- if (nrow(camp)) {
    paste0("Sugest\u00e3o por regra br-campus-1.0 (n\u00e3o extra\u00eddo do edital): ",
           paste(sprintf("%s [%s]", camp$campus, camp$evidencias), collapse = " | "))
  } else NA_character_

  tipo_final <- if (!is.na(tipo_escopo) && nzchar(tipo_escopo)) tipo_escopo else {
    tp <- classify_scope_type(titulo, paste(descricao %||% "", descricao_completa %||% ""), url_id, fonte)
    if (identical(tp, "indeterminado") && !is.na(tipo_default)) tipo_default else tp
  }
  val <- validate_opportunity(titulo, paste(descricao %||% "", descricao_completa %||% ""), url_id, fonte,
                              evidencia_chamada = TRUE, tipo_escopo = tipo_final, now = now)
  if (!isTRUE(detalhe_ok) && val$validacao_status == "validado") {
    val$validacao_status <- "a_verificar"
    val$validacao_motivo <- sprintf("tipo=%s;detalhe_indisponivel_objeto_nao_confirmado", tipo_final)
  }

  st_legacy <- tryCatch(derive_status_one(dl, ab, now = now, status_oficial = so, fluxo_continuo = !is.na(fc)),
                        error = function(e) "desconhecido")
  tibble::tibble(
    id_registro = id, entidade = entidade, pais_origem = "Brasil", titulo = .br_ws(titulo),
    subtitulo = NA_character_, descricao_resumida = if (is.na(descricao)) NA_character_ else substr(.br_ws(descricao), 1L, 600L),
    descricao_completa = if (is.na(descricao_completa)) NA_character_ else .br_ws(descricao_completa),
    tipo_oportunidade = tipo_oportunidade, modalidade = modalidade, area_tematica = area,
    palavras_chave = NA_character_, elegibilidade = elegibilidade, publico_alvo = publico_alvo,
    nivel_academico = NA_character_, instituicao_financiadora = nome_fonte,
    valor_financiado = as.numeric(valor_total), moeda = if (is.na(valor_total)) NA_character_ else (moeda %||% "BRL"),
    data_publicacao = pub, data_abertura = ab, data_limite = dl, data_encerramento = NA_character_,
    status_oportunidade = st_legacy, link_origem = link_origem, link_detalhe = link_detalhe,
    link_documento_pdf = link_pdf, idioma = idioma, localidade = localidade, observacoes = observacoes,
    texto_bruto = if (is.na(texto_bruto)) NA_character_ else substr(.br_ws(texto_bruto), 1L, 20000L),
    pagina_coletada = as.integer(pagina), fonte_oficial = fonte,
    data_hora_coleta = format(now, "%Y-%m-%d %H:%M:%S"), hash_deduplicacao = hash, campus = campus,
    campos_inferidos_ia = NA_character_, enrichment_status = NA_character_, enrichment_model = NA_character_,
    enrichment_at = NA_character_, enrichment_error = NA_character_,
    status_oficial = so, fluxo_continuo = fc, id_chamada = id_chamada, tipo_escopo = val$tipo_escopo,
    validacao_status = val$validacao_status, validacao_motivo = val$validacao_motivo,
    validacao_evidencia = val$validacao_evidencia, validacao_versao = val$validacao_versao,
    validacao_em = val$validacao_em, proveniencia_json = provenance_to_json(provenance),
    campus_justificativa = camp_just, valor_teto_projeto = as.numeric(valor_teto), data_vigencia_fim = vig
  )
}

br_empty_records <- function() {
  df <- ensure_record_schema(tibble::tibble())
  for (nm in BR_EXTRA_COLUMNS) df[[nm]] <- character()
  df$fluxo_continuo <- integer(); df$valor_teto_projeto <- numeric()
  df
}

# Aplica o limite DEPOIS da validação (T26) e relata truncamento.
br_finalize <- function(records, max_records = 15L, rejeitados = character()) {
  if (is.null(records) || nrow(records) == 0L) {
    return(list(records = br_empty_records(), n_aceitos = 0L, truncado = FALSE, n_omitidos = 0L, rejeitados = as.character(rejeitados)))
  }
  records <- records[!duplicated(records$id_registro), , drop = FALSE]
  keep <- records$validacao_status %in% c("validado", "a_verificar")
  rejeitados <- c(rejeitados, paste0("validacao:", records$validacao_motivo[!keep]))
  acc <- records[keep, , drop = FALSE]
  # validados primeiro: itens a_verificar não consomem limite antes dos validados
  acc <- acc[order(match(acc$validacao_status, c("validado", "a_verificar"))), , drop = FALSE]
  n_total <- nrow(acc)
  lim <- suppressWarnings(as.integer(max_records))
  trunc <- !is.na(lim) && n_total > lim
  if (trunc) acc <- acc[seq_len(lim), , drop = FALSE]
  list(records = acc, n_aceitos = nrow(acc), truncado = trunc, n_omitidos = max(0L, n_total - nrow(acc)),
       rejeitados = rejeitados[nzchar(rejeitados)])
}

br_result <- function(source_id, records, diag, pages = 1L, last_url = NA_character_) {
  list(records = records, pages_visited = as.integer(pages), last_url = last_url,
       diagnostics = diag, finalized = TRUE, source_id = source_id)
}

br_acquisition_failure <- function(source_id, fetched, url, log_path = NULL) {
  kind <- fetched$acq$kind %||% "network_error"
  state <- acquisition_to_state(kind)
  msg <- sprintf("Aquisicao falhou (%s): %s", kind, fetched$acq$reason %||% "")
  if (!is.null(log_path)) log_write(log_path, "ERROR", sprintf("[%s] %s | %s", source_id, msg, url))
  diag <- make_source_diagnostics(state, mensagem = msg, url_final = fetched$final_url %||% url,
                                  http_status = fetched$http_status %||% NA_integer_,
                                  latencia_s = fetched$latency %||% NA_real_, paginas = 0L)
  br_result(source_id, br_empty_records(), diag, pages = 0L, last_url = url)
}

# ─── BNB FUNDECI (BR02) ───────────────────────────────────────────────────────

.PT_MONTH_ABBR <- c(jan = 1, fev = 2, mar = 3, abr = 4, mai = 5, jun = 6, jul = 7, ago = 8, set = 9, out = 10, nov = 11, dez = 12)

parse_fundeci_listing <- function(html_text, base_url) {
  doc <- br_html(html_text)
  items <- xml2::xml_find_all(doc, "//li[contains(@class,'list-group-item')][.//a[@href]]")
  rows <- lapply(items, function(li) {
    a <- xml2::xml_find_first(li, ".//a[@href]")
    href <- br_abs_url(base_url, xml2::xml_attr(a, "href"))
    title <- .br_ws(xml2::xml_text(a))
    labels <- .br_ws(xml2::xml_text(xml2::xml_find_all(li, ".//span[contains(@class,'label-item')]")))
    if (!nzchar(title) || is.na(href)) return(NULL)
    ln <- normalize_text(labels)
    status_of <- if (any(grepl("inscricoes encerradas", ln))) "encerrado" else
      if (any(grepl("inscricoes abertas", ln))) "aberto" else
      if (any(grepl("^concluido|^concluida", ln))) "encerrado" else NA_character_
    vig <- if (any(grepl("^vigente", ln))) "vigente" else if (any(grepl("^concluid", ln))) "concluido" else NA_character_
    asset <- regmatches(href, regexec("assetEntryId=([0-9]+)", href))[[1]]
    tibble::tibble(titulo = title, url = href, rotulos = paste(labels, collapse = " | "), status_oficial = status_of,
                   situacao_vigencia = vig, asset_id = if (length(asset) == 2L) asset[[2]] else NA_character_)
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) return(tibble::tibble(titulo = character(), url = character(), rotulos = character(),
                                                 status_oficial = character(), situacao_vigencia = character(),
                                                 asset_id = character()))
  out <- dplyr::bind_rows(rows)
  out[grepl("(?i)edital|chamada", out$titulo, perl = TRUE), , drop = FALSE]
}

parse_fundeci_detail <- function(html_text, base_url) {
  doc <- br_html(html_text)
  main <- xml2::xml_find_first(doc, "//*[@id='main-content']")
  if (inherits(main, "xml_missing")) main <- doc
  text <- .br_ws(xml2::xml_text(main))
  paras <- .br_ws(xml2::xml_text(xml2::xml_find_all(main, ".//p")))
  vig <- regmatches(text, regexec("(?i)Vig[e\u00ea]ncia:\\s*(\\d{1,2})\\s+([a-z\u00e7]{3}),?\\s*(\\d{4})\\s+a\\s+(\\d{1,2})\\s+([a-z\u00e7]{3}),?\\s*(\\d{4})", text, perl = TRUE))[[1]]
  vig_ini <- vig_fim <- as.Date(NA)
  if (length(vig) == 7L) {
    mi <- unname(.PT_MONTH_ABBR[normalize_text(vig[[3]])]); mf <- unname(.PT_MONTH_ABBR[normalize_text(vig[[6]])])
    if (!is.na(mi)) vig_ini <- .mk_date(vig[[2]], mi, vig[[4]])
    if (!is.na(mf)) vig_fim <- .mk_date(vig[[5]], mf, vig[[7]])
  }
  # Orçamento total: "recursos no valor total de R$ 30,0 milhões" (não confundir com teto/projeto)
  tot <- regmatches(text, regexec("(?i)(?:recursos?\\s+(?:no\\s+)?valor\\s+total\\s+de|valor\\s+total\\s+de|or\u00e7amento\\s+total\\s+de)\\s*(R\\$\\s*[0-9][0-9.,]*\\s*(?:milh[\u00f5o]es|milh[\u00e3a]o|mil)?)", text, perl = TRUE))[[1]]
  teto <- regmatches(text, regexec("(?i)(?:at\u00e9|limite\\s+de|valor\\s+m\u00e1ximo\\s+de)\\s*(R\\$\\s*[0-9][0-9.,]*\\s*(?:milh[\u00f5o]es|milh[\u00e3a]o|mil)?)[^.]{0,60}por\\s+projeto", text, perl = TRUE))[[1]]
  elig <- paras[grepl("(?i)convida|poder[a\u00e3]o\\s+participar|podem\\s+participar|destina-se", paras, perl = TRUE)]
  objeto <- paras[grepl("(?i)o\\s+objetivo\\s+do\\s+edital|tem\\s+por\\s+objeto|objeto\\s+do\\s+edital", paras, perl = TRUE)]

  # Tabela de prazos (Fases | Prazo): etapa + data (ou intervalo)
  events <- list()
  trs <- xml2::xml_find_all(main, ".//table[.//th[contains(., 'Fases')]]//tr[td]")
  for (tr in trs) {
    tds <- .br_ws(xml2::xml_text(xml2::xml_find_all(tr, "./td")))
    if (length(tds) < 2L) next
    label <- tds[[1]]; cell <- tds[[2]]
    ds <- regmatches(cell, gregexpr("\\d{1,2}/\\d{1,2}/\\d{4}", cell))[[1]]
    if (length(ds) == 0L) next
    ds <- parse_br_date_token(ds)
    et <- classify_stage_label(label)
    nl <- normalize_text(label)
    is_project_submission <- grepl("(cadastro e )?(envio|apresentacao|submissao)[^|]{0,30}(projetos|propostas)", nl) &&
      !grepl("resultado|recurso|analise|avaliacao", nl)
    if (is_project_submission && length(ds) >= 2L) {
      events[[length(events) + 1L]] <- data.frame(etapa = "submissao_inicio", data = ds[[1]], hora = NA_character_, trecho = substr(paste(label, cell), 1, 240))
      events[[length(events) + 1L]] <- data.frame(etapa = "submissao_fim", data = ds[[length(ds)]], hora = NA_character_, trecho = substr(paste(label, cell), 1, 240))
    } else if (grepl("^publicacao do edital", nl)) {
      events[[length(events) + 1L]] <- data.frame(etapa = "publicacao", data = ds[[1]], hora = NA_character_, trecho = substr(paste(label, cell), 1, 240))
    } else {
      events[[length(events) + 1L]] <- data.frame(etapa = et, data = ds[[length(ds)]], hora = NA_character_, trecho = substr(paste(label, cell), 1, 240))
    }
  }
  ev <- if (length(events)) do.call(rbind, events) else data.frame(etapa = character(), data = as.Date(character()), hora = character(), trecho = character())

  # Anexos: data + link (edital, errata, comunicados, resultados)
  docs <- list()
  for (tr in xml2::xml_find_all(main, ".//table[.//th[contains(., 'Anexo')]]//tr[td]")) {
    tds <- xml2::xml_find_all(tr, "./td")
    if (length(tds) < 2L) next
    a <- xml2::xml_find_first(tds[[2]], ".//a[@href]")
    if (inherits(a, "xml_missing")) next
    docs[[length(docs) + 1L]] <- data.frame(
      data = parse_br_date_token(.br_ws(xml2::xml_text(tds[[1]]))),
      nome = .br_ws(xml2::xml_text(a)), url = br_abs_url(base_url, xml2::xml_attr(a, "href")), stringsAsFactors = FALSE)
  }
  docs <- if (length(docs)) do.call(rbind, docs) else data.frame(data = as.Date(character()), nome = character(), url = character())
  list(text = text, vigencia_ini = vig_ini, vigencia_fim = vig_fim,
       valor_total = if (length(tot) == 2L) br_parse_brl(tot[[2]]) else NA_real_,
       valor_teto = if (length(teto) == 2L) br_parse_brl(teto[[2]]) else NA_real_,
       valor_total_trecho = if (length(tot) == 2L) tot[[1]] else NA_character_,
       elegibilidade = if (length(elig)) elig[[1]] else NA_character_,
       objeto = if (length(objeto)) objeto[[1]] else NA_character_, eventos = ev, documentos = docs)
}

collect_bnb_fundeci <- function(source_row, max_pages = 1, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- "bnb_fundeci"
  url <- br_source_url(source_row, sid)
  now <- br_now()
  fx <- br_fetch(url, log_path)
  if (!fx$ok) return(br_acquisition_failure(sid, fx, url, log_path))
  cands <- parse_fundeci_listing(fx$text, fx$final_url)
  if (nrow(cands) == 0L) {
    diag <- make_source_diagnostics("erro_parser", mensagem = "Contrato da listagem FUNDECI nao reconhecido (nenhum card de edital).",
                                    url_final = fx$final_url, latencia_s = fx$latency)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  max_details <- 6L
  recs <- list(); n_det <- 0L; det_fail <- 0L
  for (i in seq_len(nrow(cands))) {
    cd <- cands[i, ]
    det <- NULL
    want_detail <- n_det < max_details && (is.na(cd$situacao_vigencia) || cd$situacao_vigencia != "concluido" || n_det < 2L)
    if (want_detail) {
      fd <- br_fetch(cd$url, log_path); n_det <- n_det + 1L
      if (fd$ok) det <- tryCatch(parse_fundeci_detail(fd$text, fd$final_url), error = function(e) NULL) else det_fail <- det_fail + 1L
    }
    prov <- list(make_provenance("titulo", cd$titulo, fx$final_url, cd$titulo, "html:li.list-group-item a", "oficial", now),
                 make_provenance("status_oficial", cd$status_oficial, fx$final_url, cd$rotulos, "html:span.label-item", "oficial", now))
    pub <- ab <- dl <- vig <- as.Date(NA); val <- teto <- NA_real_; elig <- obj <- area <- NA_character_; pdf <- NA_character_
    if (!is.null(det)) {
      sch <- det$eventos
      pub_e <- sch[sch$etapa == "publicacao", ]; if (nrow(pub_e)) pub <- min(pub_e$data)
      ini <- sch[sch$etapa == "submissao_inicio", ]; fim <- sch[sch$etapa == "submissao_fim", ]
      if (nrow(ini)) ab <- min(ini$data)
      if (nrow(fim)) dl <- max(fim$data)
      vig <- det$vigencia_fim; val <- det$valor_total; teto <- det$valor_teto
      elig <- det$elegibilidade; obj <- det$objeto
      area <- if (grepl("\\s[-–]\\s", cd$titulo)) sub("^.*?\\s[-–]\\s", "", cd$titulo, perl = TRUE) else NA_character_
      ed <- det$documentos[grepl("(?i)^edital", det$documentos$nome, perl = TRUE) & grepl("\\.pdf", det$documentos$url, ignore.case = TRUE), ]
      if (nrow(ed)) pdf <- ed$url[[1]]
      prov <- c(prov, list(
        make_provenance("data_limite", dl, fd$final_url, fim$trecho[1] %||% NA, "html:tabela Fases/Prazo", "oficial", now),
        make_provenance("data_publicacao", pub, fd$final_url, pub_e$trecho[1] %||% NA, "html:tabela Fases/Prazo", "oficial", now),
        make_provenance("valor_financiado", val, fd$final_url, det$valor_total_trecho, "regex:valor total", "oficial", now),
        make_provenance("elegibilidade", elig, fd$final_url, elig, "html:p convida/poder\u00e3o participar", "oficial", now),
        make_provenance("data_vigencia_fim", vig, fd$final_url, "Vig\u00eancia:", "regex:Vig\u00eancia", "oficial", now)))
    }
    obs <- paste(c(
      if (!is.na(cd$situacao_vigencia)) sprintf("Vig\u00eancia (situa\u00e7\u00e3o oficial): %s. Vig\u00eancia n\u00e3o equivale a inscri\u00e7\u00f5es abertas.", cd$situacao_vigencia),
      if (!is.null(det) && any(grepl("(?i)prorroga|errata|retifica", det$documentos$nome, perl = TRUE)))
        "H\u00e1 errata/comunicado de prorroga\u00e7\u00e3o entre os anexos: confirmar cronograma vigente no documento.",
      if (is.null(det)) "Detalhe do edital n\u00e3o consultado/indispon\u00edvel nesta rodada."), collapse = " ")
    recs[[length(recs) + 1L]] <- br_record(
      fonte = sid, entidade = "Banco do Nordeste - FUNDECI", nome_fonte = "BNB / FUNDECI", titulo = cd$titulo,
      link_origem = fx$final_url, link_detalhe = cd$url, link_pdf = pdf,
      descricao = obj, descricao_completa = if (!is.null(det)) det$text else NA_character_,
      area = area, elegibilidade = elig, valor_total = val, valor_teto = teto,
      data_publicacao = pub, data_abertura = ab, data_limite = dl, data_vigencia_fim = vig,
      status_oficial = cd$status_oficial, id_chamada = if (!is.na(cd$asset_id)) paste0("asset:", cd$asset_id) else NA_character_,
      observacoes = if (nzchar(obs)) obs else NA_character_, provenance = prov, tipo_default = "fomento",
      detalhe_ok = !is.null(det), now = now, texto_bruto = if (!is.null(det)) det$text else cd$titulo)
  }
  fin <- br_finalize(dplyr::bind_rows(recs), max_records)
  n_open <- sum(derive_status_df(fin$records, now = now) %in% c("aberto", "encerrando"))
  diag <- make_source_diagnostics(
    if (nrow(fin$records) > 0L) (if (det_fail > 0L) "parcial" else "sucesso") else "vazio_confirmado",
    n_candidatos = nrow(cands), n_aceitos = fin$n_aceitos, n_rejeitados = nrow(cands) - fin$n_aceitos,
    motivos_rejeicao = fin$rejeitados, url_final = fx$final_url, latencia_s = fx$latency, truncado = fin$truncado,
    paginas = 1L + n_det,
    mensagem = sprintf("%d edital(is) FUNDECI; %d com inscri\u00e7\u00e3o aberta (derivado); %d detalhe(s) consultado(s), %d falha(s).",
                       fin$n_aceitos, n_open, n_det, det_fail))
  br_result(sid, fin$records, diag, 1L + n_det, fx$final_url)
}
register_collector("bnb_fundeci", collect_bnb_fundeci, "BNB FUNDECI: editais oficiais (cards/detalhes/PDFs) sem fallback")

# ─── AEB (BR03) ───────────────────────────────────────────────────────────────

parse_aeb_listing <- function(html_text, base_url) {
  doc <- br_html(html_text)
  core <- xml2::xml_find_first(doc, "//*[@id='content-core']")
  empty <- tibble::tibble(titulo = character(), url = character(), secao = character(), estado_secao = character())
  if (inherits(core, "xml_missing")) return(empty)
  nodes <- xml2::xml_find_all(core, ".//*[self::h2 or self::h3 or self::h4 or self::p or self::li]")
  secao <- NA_character_; estado <- NA_character_; rows <- list()
  for (n in nodes) {
    nm <- xml2::xml_name(n)
    txt <- .br_ws(xml2::xml_text(n))
    if (nm %in% c("h2", "h3", "h4")) { secao <- txt; estado <- NA_character_; next }
    if (nm == "p") {
      tn <- normalize_text(txt)
      if (tn %in% c("abertos", "abertas")) estado <- "abertos"
      if (tn %in% c("encerrados", "encerradas")) estado <- "encerrados"
      next
    }
    a <- xml2::xml_find_first(n, ".//a[@href]")
    if (inherits(a, "xml_missing")) next
    title <- .br_ws(xml2::xml_text(a))
    if (!nzchar(gsub("[[:punct:][:space:]]", "", title))) next
    href <- br_abs_url(base_url, xml2::xml_attr(a, "href"))
    if (is.na(href)) next
    rows[[length(rows) + 1L]] <- tibble::tibble(titulo = sub("[.]\\s*$", "", title), url = href, secao = secao, estado_secao = estado)
  }
  if (length(rows) == 0L) return(empty)
  out <- dplyr::bind_rows(rows)
  out$k <- canonical_url(out$url)
  out <- out[!duplicated(paste(out$k, out$estado_secao)), , drop = FALSE]
  out$k <- NULL
  out
}

parse_aeb_detail <- function(text, is_pdf = FALSE) {
  t <- .br_ws(text)
  list(
    texto = t,
    prazo = br_extract_deadline_text(text),
    prazo_relativo = br_has_relative_schedule(text),
    publicacao = extract_publication_date(t),
    objeto = {
      m <- regmatches(t, regexec("(?i)OBJETO:\\s*(.{20,400}?)(?:\\s+\u00cdNDICE|\\s+INDICE|\\s+1\\.)", t, perl = TRUE))[[1]]
      if (length(m) == 2L) m[[2]] else NA_character_
    })
}

collect_aeb <- function(source_row, max_pages = 1, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- "aeb"
  url <- br_source_url(source_row, sid)
  now <- br_now()
  fx <- br_fetch(url, log_path)
  if (!fx$ok) return(br_acquisition_failure(sid, fx, url, log_path))
  cands <- parse_aeb_listing(fx$text, fx$final_url)
  if (nrow(cands) == 0L) {
    diag <- make_source_diagnostics("erro_parser", mensagem = "Contrato da pagina AEB nao reconhecido (#content-core sem itens).",
                                    url_final = fx$final_url, latencia_s = fx$latency)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  rejeitados <- character(); recs <- list(); n_det <- 0L; det_fail <- 0L
  max_details <- 8L
  for (i in seq_len(nrow(cands))) {
    cd <- cands[i, ]
    if (grepl("(?i)concursos?\\s+p[u\u00fa]blicos?", cd$secao, perl = TRUE)) {
      rejeitados <- c(rejeitados, "concurso_cargo"); next
    }
    is_pdf <- grepl("\\.pdf($|\\?)", cd$url, ignore.case = TRUE)
    det_txt <- NA_character_; det <- NULL
    if (n_det < max_details) {
      n_det <- n_det + 1L
      if (is_pdf) det_txt <- br_fetch_pdf_text(cd$url, log_path) else {
        fd <- br_fetch(cd$url, log_path)
        if (fd$ok) {
          d <- br_html(fd$text)
          core <- xml2::xml_find_first(d, "//*[@id='content-core']")
          det_txt <- if (inherits(core, "xml_missing")) NA_character_ else xml2::xml_text(core)
        }
      }
      if (is.na(det_txt)) det_fail <- det_fail + 1L else det <- parse_aeb_detail(det_txt, is_pdf)
    }
    so <- if (identical(cd$estado_secao, "encerrados")) "encerrado" else NA_character_
    prov <- list(make_provenance("titulo", cd$titulo, fx$final_url, cd$titulo, "html:#content-core li a", "oficial", now),
                 make_provenance("status_oficial", so, fx$final_url, paste(cd$secao, cd$estado_secao), "html:secao Abertos/Encerrados", "oficial", now))
    dl <- pub <- as.Date(NA); obj <- NA_character_
    if (!is.null(det)) {
      dl <- det$prazo; pub <- det$publicacao; obj <- det$objeto
      prov <- c(prov, list(make_provenance("data_limite", dl, cd$url, "at\u00e9 <data> (envio de curr\u00edculo/candidatura)", "regex:prazo textual", "oficial", now)))
    }
    obs <- paste(c(
      if (identical(cd$estado_secao, "abertos")) "Listado em 'Abertos' na p\u00e1gina; estado de inscri\u00e7\u00e3o n\u00e3o assumido sem prazo confirmado no detalhe.",
      if (!is.null(det) && isTRUE(det$prazo_relativo) && is.na(dl)) "Cronograma relativo (T0+n) sem data de publica\u00e7\u00e3o absoluta: prazo n\u00e3o determinado.",
      if (is.null(det)) "Detalhe n\u00e3o consultado/indispon\u00edvel."), collapse = " ")
    recs[[length(recs) + 1L]] <- br_record(
      fonte = sid, entidade = "Ag\u00eancia Espacial Brasileira", nome_fonte = "AEB", titulo = cd$titulo,
      link_origem = fx$final_url, link_detalhe = cd$url,
      link_pdf = if (is_pdf) cd$url else NA_character_,
      descricao = obj, descricao_completa = if (!is.null(det)) det$texto else NA_character_,
      data_publicacao = pub, data_limite = dl, status_oficial = so,
      observacoes = if (nzchar(obs)) obs else NA_character_, provenance = prov,
      detalhe_ok = !is.null(det), now = now, texto_bruto = if (!is.null(det)) det$texto else cd$titulo)
  }
  fin <- br_finalize(dplyr::bind_rows(recs), max_records, rejeitados)
  diag <- make_source_diagnostics(
    if (fin$n_aceitos > 0L) (if (det_fail > 0L) "parcial" else "sucesso") else "vazio_confirmado",
    n_candidatos = nrow(cands), n_aceitos = fin$n_aceitos, n_rejeitados = length(fin$rejeitados %||% rejeitados),
    motivos_rejeicao = fin$rejeitados %||% rejeitados, url_final = fx$final_url, latencia_s = fx$latency,
    truncado = fin$truncado, paginas = 1L + n_det,
    mensagem = sprintf("%d item(ns) de processos seletivos; %d concurso(s) de cargo excluidos; %d detalhe(s), %d falha(s).",
                       fin$n_aceitos, sum(rejeitados == "concurso_cargo"), n_det, det_fail))
  br_result(sid, fin$records, diag, 1L + n_det, fx$final_url)
}
register_collector("aeb", collect_aeb, "AEB: processos seletivos/editais (secoes abertos/encerrados), sem fallback")

# ─── FUNCAP (BR07) ────────────────────────────────────────────────────────────

funcap_is_official_host <- function(url) grepl("(^|\\.)funcap\\.ce\\.gov\\.br($|/)", sub("^https?://", "", tolower(as.character(url %||% ""))))

# Plataforma Montenegro: seções "Editais Abertos" (tabela) e "Editais Encerrados" (blocos por ano).
# O DOM é usado (comentários HTML NÃO são conteúdo). Itens sob "Encerrados" => estado oficial encerrado.
parse_funcap_montenegro <- function(html_text, base_url) {
  doc <- br_html(html_text)
  rows_open <- xml2::xml_find_all(doc, "//table[@id='tabela-editais-abertos']//tr[td]")
  open_n <- length(rows_open)
  out <- list()
  for (blk in xml2::xml_find_all(doc, "//div[contains(@class,'bloco-ano-edital')]")) {
    ano <- sub("^bloco-ano-", "", xml2::xml_attr(blk, "id"))
    current <- NULL; kind <- NA_character_
    for (tr in xml2::xml_find_all(blk, ".//tr[contains(@class,'linha-titulo-edital') or contains(@class,'linha-cabecalho-edital') or contains(@class,'linha-documento-edital')]")) {
      cls <- xml2::xml_attr(tr, "class")
      if (grepl("linha-titulo-edital", cls)) {
        if (!is.null(current)) out[[length(out) + 1L]] <- current
        current <- list(titulo = .br_ws(xml2::xml_text(tr)), ano = ano, docs = list())
        kind <- NA_character_
      } else if (grepl("linha-cabecalho-edital", cls)) {
        kind <- normalize_text(.br_ws(xml2::xml_text(xml2::xml_find_first(tr, ".//th"))))
      } else if (!is.null(current)) {
        a <- xml2::xml_find_first(tr, ".//a[@href]")
        tds <- .br_ws(xml2::xml_text(xml2::xml_find_all(tr, "./td")))
        dt <- regmatches(paste(tds, collapse = " "), regexpr("\\d{2}/\\d{2}/\\d{4}", paste(tds, collapse = " ")))
        current$docs[[length(current$docs) + 1L]] <- list(
          grupo = kind, nome = sub("^-\\s*", "", tds[[1]] %||% ""),
          url = if (inherits(a, "xml_missing")) NA_character_ else br_abs_url(base_url, xml2::xml_attr(a, "href")),
          data = if (length(dt)) parse_br_date_token(dt) else as.Date(NA))
      }
    }
    if (!is.null(current)) out[[length(out) + 1L]] <- current
  }
  list(abertos_n = open_n, itens = out, titulo_pagina = .br_ws(xml2::xml_text(xml2::xml_find_first(doc, "//title"))))
}

collect_funcap <- function(source_row, max_pages = 1, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- "funcap"
  primary <- br_source_url(source_row, sid)
  alt <- BR_CANONICAL_URLS$funcap_montenegro
  now <- br_now()
  fx <- br_fetch(primary, log_path)
  used <- primary; fallback_note <- NA_character_
  if (!fx$ok) {
    kind <- fx$acq$kind %||% "network_error"
    fallback_note <- sprintf("P\u00e1gina principal indispon\u00edvel (%s: %s); consultada plataforma oficial Montenegro.", kind, fx$acq$reason %||% "")
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("[funcap] %s", fallback_note))
    fx2 <- br_fetch(alt, log_path)
    if (!fx2$ok) {
      res <- br_acquisition_failure(sid, fx, primary, log_path)
      res$diagnostics$mensagem <- paste(res$diagnostics$mensagem, "| alternativa Montenegro tambem falhou:", fx2$acq$reason %||% "")
      return(res)
    }
    fx <- fx2; used <- alt
  }
  if (!funcap_is_official_host(fx$final_url)) {
    diag <- make_source_diagnostics("erro_parser", mensagem = sprintf("Host nao vinculado ao dominio oficial funcap.ce.gov.br: %s", fx$final_url),
                                    url_final = fx$final_url)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  pg <- parse_funcap_montenegro(fx$text, fx$final_url)
  if (length(pg$itens) == 0L && pg$abertos_n == 0L) {
    diag <- make_source_diagnostics("erro_parser", mensagem = "Contrato da plataforma FUNCAP nao reconhecido.", url_final = fx$final_url,
                                    latencia_s = fx$latency)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  recs <- list()
  for (it in pg$itens) {
    ed <- Filter(function(d) grepl("(?i)^edital|^chamada", d$grupo %||% "", perl = TRUE), it$docs)
    ed_main <- if (length(ed)) ed[[1]] else NULL
    adendos <- Filter(function(d) grepl("(?i)adendo|errata|retifica", d$nome %||% "", perl = TRUE), it$docs)
    pub <- if (!is.null(ed_main)) ed_main$data else as.Date(NA)
    prov <- list(make_provenance("titulo", it$titulo, fx$final_url, it$titulo, "html:tr.linha-titulo-edital", "oficial", now),
                 make_provenance("status_oficial", "encerrado", fx$final_url, "Se\u00e7\u00e3o 'Editais Encerrados'", "html:div.bloco-ano-edital", "oficial", now),
                 make_provenance("data_publicacao", pub, fx$final_url, if (!is.null(ed_main)) ed_main$nome else NA, "html:tr.linha-documento-edital", "oficial", now))
    obs <- paste(c(fallback_note, "Item listado na se\u00e7\u00e3o 'Editais Encerrados' da plataforma oficial; prazo de submiss\u00e3o n\u00e3o extra\u00eddo (est\u00e1 no PDF do edital/adendos).",
                   if (length(adendos)) sprintf("%d adendo(s)/errata(s) publicados: o PDF vigente prevalece.", length(adendos))), collapse = " ")
    recs[[length(recs) + 1L]] <- br_record(
      fonte = sid, entidade = "FUNCAP", nome_fonte = "FUNCAP", titulo = it$titulo,
      link_origem = fx$final_url, link_detalhe = paste0(fx$final_url, "#", sanitize_id(it$titulo)),
      link_pdf = if (!is.null(ed_main)) ed_main$url else NA_character_,
      data_publicacao = pub, status_oficial = "encerrado",
      id_chamada = { cid <- extract_call_id(it$titulo); if (is.na(cid)) NA_character_ else paste(cid, it$ano) },
      observacoes = obs, provenance = prov, tipo_default = "fomento", now = now,
      texto_bruto = paste(it$titulo, paste(vapply(it$docs, function(d) d$nome %||% "", character(1)), collapse = "; ")))
    # sem número oficial reconhecível, a identidade usa a URL do PDF do edital (estável), não o título/prazo
    if (is.na(extract_call_id(it$titulo)) && !is.null(ed_main) && !is.na(ed_main$url)) {
      recs[[length(recs)]]$id_registro <- stable_opportunity_id(sid, url = ed_main$url)
    }
  }
  fin <- br_finalize(dplyr::bind_rows(recs), max_records)
  diag <- make_source_diagnostics(
    if (fin$n_aceitos > 0L) (if (!is.na(fallback_note)) "parcial" else "sucesso") else "vazio_confirmado",
    n_candidatos = length(pg$itens), n_aceitos = fin$n_aceitos, n_rejeitados = length(pg$itens) - fin$n_aceitos,
    motivos_rejeicao = fin$rejeitados, url_final = fx$final_url, latencia_s = fx$latency, truncado = fin$truncado, paginas = 1L,
    mensagem = sprintf("%d edital(is) na plataforma Montenegro (se\u00e7\u00e3o Abertos: %d linha(s)); fonte usada: %s%s",
                       fin$n_aceitos, pg$abertos_n, used, if (!is.na(fallback_note)) paste0(" | ", fallback_note) else ""))
  br_result(sid, fin$records, diag, 1L, fx$final_url)
}
register_collector("funcap", collect_funcap, "FUNCAP: plataforma oficial de editais (TLS validado; sem bypass)")

# ─── Embrapa (BR06) ───────────────────────────────────────────────────────────

parse_embrapa_listing <- function(html_text, base_url) {
  doc <- br_html(html_text)
  items <- xml2::xml_find_all(doc, "//li[contains(@class,'embp-latest-news_item')]")
  rows <- lapply(items, function(li) {
    a <- xml2::xml_find_first(li, ".//a[@href]")
    if (inherits(a, "xml_missing")) return(NULL)
    dt <- regmatches(.br_ws(xml2::xml_text(xml2::xml_find_first(li, ".//div[contains(@class,'header')]"))),
                     regexpr("\\d{2}/\\d{2}/\\d{4}", .br_ws(xml2::xml_text(xml2::xml_find_first(li, ".//div[contains(@class,'header')]")))))
    tibble::tibble(titulo = .br_ws(xml2::xml_text(a)), url = br_abs_url(base_url, xml2::xml_attr(a, "href")),
                   data_listagem = if (length(dt)) parse_br_date_token(dt) else as.Date(NA))
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(tibble::tibble(titulo = character(), url = character(), data_listagem = as.Date(character())))
  dplyr::bind_rows(rows)
}

collect_embrapa <- function(source_row, max_pages = 1, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- "embrapa"
  url <- br_source_url(source_row, sid)
  now <- br_now()
  fx <- br_fetch(url, log_path)
  if (!fx$ok) return(br_acquisition_failure(sid, fx, url, log_path))
  cands <- parse_embrapa_listing(fx$text, fx$final_url)
  if (nrow(cands) == 0L) {
    diag <- make_source_diagnostics("erro_parser", mensagem = "Contrato da listagem Embrapa nao reconhecido.", url_final = fx$final_url)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  recs <- list()
  for (i in seq_len(nrow(cands))) {
    cd <- cands[i, ]
    recs[[i]] <- br_record(
      fonte = sid, entidade = "Embrapa", nome_fonte = "Embrapa", titulo = cd$titulo, link_origem = fx$final_url,
      link_detalhe = cd$url, data_publicacao = cd$data_listagem, id_chamada = extract_call_id(cd$titulo),
      provenance = list(make_provenance("titulo", cd$titulo, fx$final_url, cd$titulo, "html:li.embp-latest-news_item a", "oficial", now)),
      detalhe_ok = FALSE, now = now, texto_bruto = cd$titulo)
  }
  fin <- br_finalize(dplyr::bind_rows(recs), max_records)
  n_rej <- nrow(cands) - fin$n_aceitos
  diag <- make_source_diagnostics(
    if (fin$n_aceitos > 0L) "sucesso" else "vazio_confirmado",
    n_candidatos = nrow(cands), n_aceitos = fin$n_aceitos, n_rejeitados = n_rej,
    motivos_rejeicao = fin$rejeitados, url_final = fx$final_url, latencia_s = fx$latency, truncado = fin$truncado, paginas = 1L,
    mensagem = sprintf("Pagina oficial lista licitacoes administrativas: %d item(ns) avaliados, %d no escopo de fomento a pesquisa. Nenhuma URL alternativa foi assumida; procurar secao oficial de pesquisa/cooperacao/inovacao.",
                       nrow(cands), fin$n_aceitos))
  br_result(sid, fin$records, diag, 1L, fx$final_url)
}
register_collector("embrapa", collect_embrapa, "Embrapa: editais oficiais; licitacoes de compra sao rejeitadas por tipo/objeto")

# ─── Hubine BNB (BR08) ────────────────────────────────────────────────────────

# Conteúdo principal apenas (#main-content); menus/rodapé/redes sociais não são candidatos.
# Seleção concreta = link para edital/regulamento/chamada (PDF ou página de chamada) com participação possível.
parse_hubine_page <- function(html_text, base_url) {
  doc <- br_html(html_text)
  main <- xml2::xml_find_first(doc, "//*[@id='main-content']")
  nav <- xml2::xml_find_all(doc, "//a[@href]")
  nav_links <- tibble::tibble(
    texto = .br_ws(xml2::xml_text(nav)),
    url = vapply(xml2::xml_attr(nav, "href"), function(h) br_abs_url(base_url, h), character(1)))
  nav_links <- nav_links[!is.na(nav_links$url) & grepl("/hub-de-inovacao/", nav_links$url), , drop = FALSE]
  nav_links <- nav_links[!duplicated(nav_links$url), , drop = FALSE]
  cands <- tibble::tibble(titulo = character(), url = character())
  main_text <- NA_character_
  if (!inherits(main, "xml_missing")) {
    main_text <- .br_ws(xml2::xml_text(main))
    a <- xml2::xml_find_all(main, ".//a[@href]")
    t <- .br_ws(xml2::xml_text(a)); u <- vapply(xml2::xml_attr(a, "href"), function(h) br_abs_url(base_url, h), character(1))
    sel <- !is.na(u) & nzchar(t) &
      (grepl("(?i)\\.pdf($|\\?)", u, perl = TRUE) | grepl("(?i)edital|chamada|regulamento|sele[c\u00e7][a\u00e3]o|inscri", t, perl = TRUE)) &
      !grepl("(?i)instagram|youtube|facebook|linkedin|twitter", u, perl = TRUE)
    cands <- tibble::tibble(titulo = t[sel], url = u[sel])
    cands <- cands[!duplicated(cands$url), , drop = FALSE]
  }
  list(main_found = !inherits(main, "xml_missing"), main_text = main_text, candidatos = cands, links_hub = nav_links)
}

collect_bnb_hubine <- function(source_row, max_pages = 3, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- "bnb_hubine"
  url <- br_source_url(source_row, sid)
  now <- br_now()
  fx <- br_fetch(url, log_path)
  if (!fx$ok) return(br_acquisition_failure(sid, fx, url, log_path))
  top <- parse_hubine_page(fx$text, fx$final_url)
  if (!isTRUE(top$main_found)) {
    diag <- make_source_diagnostics("erro_parser", mensagem = "Contrato do portal BNB nao reconhecido (#main-content ausente).", url_final = fx$final_url)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  # Descobre subpáginas relevantes a partir dos links do hub (sem assumir caminhos antigos)
  rel <- top$links_hub[grepl("(?i)edital|aceleracao|selecao|chamada", top$links_hub$url, perl = TRUE), , drop = FALSE]
  rel <- rel[!grepl("(?i)coworking", rel$url, perl = TRUE), , drop = FALSE]
  pages <- list(list(url = fx$final_url, page = top, fx = fx))
  n_pg <- 1L; fails <- 0L
  for (u in utils::head(rel$url, max(0L, as.integer(max_pages) - 1L))) {
    fp <- br_fetch(u, log_path)
    if (!fp$ok) { fails <- fails + 1L; next }
    n_pg <- n_pg + 1L
    pages[[length(pages) + 1L]] <- list(url = fp$final_url, page = parse_hubine_page(fp$text, fp$final_url), fx = fp)
  }
  recs <- list(); n_cand <- 0L
  for (p in pages) {
    cd <- p$page$candidatos
    n_cand <- n_cand + nrow(cd)
    for (i in seq_len(nrow(cd))) {
      recs[[length(recs) + 1L]] <- br_record(
        fonte = sid, entidade = "Hubine BNB", nome_fonte = "Banco do Nordeste - Hubine", titulo = cd$titulo[[i]],
        link_origem = p$url, link_detalhe = cd$url[[i]],
        link_pdf = if (grepl("\\.pdf", cd$url[[i]], ignore.case = TRUE)) cd$url[[i]] else NA_character_,
        provenance = list(make_provenance("titulo", cd$titulo[[i]], p$url, cd$titulo[[i]], "html:#main-content a", "oficial", now)),
        detalhe_ok = FALSE, now = now, texto_bruto = cd$titulo[[i]])
    }
  }
  fin <- br_finalize(if (length(recs)) dplyr::bind_rows(recs) else NULL, max_records)
  diag <- make_source_diagnostics(
    if (fin$n_aceitos > 0L) (if (fails > 0L) "parcial" else "sucesso") else (if (fails > 0L) "parcial" else "vazio_confirmado"),
    n_candidatos = n_cand, n_aceitos = fin$n_aceitos, n_rejeitados = n_cand - fin$n_aceitos,
    motivos_rejeicao = fin$rejeitados, url_final = fx$final_url, latencia_s = fx$latency, paginas = n_pg,
    mensagem = sprintf("%d pagina(s) do Hubine analisadas (conteudo principal); %d selecao(oes) concreta(s) com documento; %d falha(s) de acesso. Paginas institucionais nao sao persistidas.",
                       n_pg, fin$n_aceitos, fails))
  br_result(sid, fin$records, diag, n_pg, fx$final_url)
}
register_collector("bnb_hubine", collect_bnb_hubine, "Hubine BNB: apenas selecoes concretas com documento; paginas institucionais rejeitadas")
