# ─── Coletores brasileiros (parte 2): SIGITEC, BNDES, DCTA/FAB ────────────────
# Ver helpers_sources_br.R para o contrato comum (parsers puros, sem fallback fabricado,
# proveniência por campo, validação de domínio, estado oficial separado do derivado).

# ─── Petrobras SIGITEC (BR01) ─────────────────────────────────────────────────
# Contrato validado em 07/10/2026 (bundle público https://sigitec-competitividade.petrobras.com.br/v2/assets/index-*.js):
#   listagem: GET /v2/ms-authorization/opportunity/getAllPublicOpportunities  (JSON, array)
#   detalhe : GET /v2/ms-authorization/opportunity/public-opportunity/{id}
#   rota SPA: nodeBackend ? /v2/public/opportunitysigitec/{id} : /v2/public/opportunity/{id}
#   status  : y8 = {A: "Aberta para envio de proposta", J: "Julgamento", R: "Resultado",
#                   F: "Finalizada", CC: "Cancelada"}
#   O cliente público só habilita "Submeter" quando status == "A" E o dia atual não passou do prazo.
# A URL /v2/public/opportunities devolve HTML de uma SPA (div#root vazio): NÃO é endpoint JSON.

SIGITEC_BASE <- "https://sigitec-competitividade.petrobras.com.br"
SIGITEC_STATUS_LABELS <- c(A = "Aberta para envio de proposta", J = "Julgamento", R = "Resultado",
                           F = "Finalizada", CC = "Cancelada")
SIGITEC_STATUS_INTERNAL <- c(A = "aberto", J = "em_julgamento", R = "em_julgamento",
                             F = "encerrado", CC = "cancelado")

# Código oficial -> list(status_oficial, label, conhecido). Código desconhecido NÃO vira aberto.
sigitec_status_map <- function(code) {
  code <- toupper(trimws(as.character(code %||% NA_character_)))
  if (is.na(code) || !nzchar(code) || !(code %in% names(SIGITEC_STATUS_INTERNAL))) {
    return(list(status_oficial = NA_character_, label = NA_character_, conhecido = FALSE, codigo = code))
  }
  list(status_oficial = unname(SIGITEC_STATUS_INTERNAL[[code]]), label = unname(SIGITEC_STATUS_LABELS[[code]]),
       conhecido = TRUE, codigo = code)
}

sigitec_detail_route <- function(id, node_backend = FALSE) {
  if (isTRUE(node_backend)) sprintf("%s/v2/public/opportunitysigitec/%s", SIGITEC_BASE, id)
  else sprintf("%s/v2/public/opportunity/%s", SIGITEC_BASE, id)
}

# Prazo ISO com offset -> data civil em America/Sao_Paulo (mesma semântica do cliente: formato YYYY-MM-DD local).
sigitec_deadline_date <- function(iso) {
  iso <- as.character(iso %||% NA_character_)
  if (is.na(iso) || !nzchar(iso)) return(as.Date(NA))
  p <- suppressWarnings(lubridate::ymd_hms(iso, quiet = TRUE, tz = "UTC"))
  if (is.na(p)) {
    d <- suppressWarnings(as.Date(substr(iso, 1L, 10L)))
    return(d)
  }
  as.Date(lubridate::with_tz(p, STATUS_TZ), tz = STATUS_TZ)
}

sigitec_parse_listing <- function(body) {
  b <- as.character(body %||% "")
  if (length(b) != 1L || is.na(b) || !nzchar(trimws(b))) return(list(ok = FALSE, kind = "empty", items = list()))
  if (grepl("^\\s*<", b)) {
    acq <- classify_acquisition(b, 200L)
    return(list(ok = FALSE, kind = if (identical(acq$kind, "spa_shell")) "spa_shell" else "html_nao_json", items = list(), reason = acq$reason))
  }
  parsed <- tryCatch(jsonlite::fromJSON(b, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed)) return(list(ok = FALSE, kind = "json_invalido", items = list()))
  items <- if (is.list(parsed) && !is.null(names(parsed)) && !is.null(parsed$data)) parsed$data else parsed
  if (!is.list(items) || (length(items) > 0L && is.null(items[[1]]$id))) return(list(ok = FALSE, kind = "esquema_inesperado", items = list()))
  list(ok = TRUE, kind = "json", items = items)
}

.sg <- function(x, ...) { v <- x[[...]]; if (is.null(v) || (length(v) == 1L && is.na(v))) NA else v }

sigitec_item_to_record <- function(item, detail = NULL, now = NULL, page_url = NULL) {
  now <- now %||% br_now()
  pick <- function(nm) { v <- detail[[nm]]; if (is.null(v)) v <- item[[nm]]; if (is.null(v) || (length(v) == 1L && is.na(v)) || !nzchar(as.character(v)[1])) NA_character_ else as.character(v) }
  st <- sigitec_status_map(item$status %||% detail$status)
  num <- pick("numberOP"); ttl <- pick("titleOP")
  titulo <- if (!is.na(num)) sprintf("OP%s - %s", num, ttl) else ttl
  dl <- sigitec_deadline_date(pick("deadlineSubmissionOfProposal"))
  pub <- sigitec_deadline_date(pick("publicationDate"))
  so <- st$status_oficial
  nota <- NULL
  # Mesmo critério do cliente público: "A" com prazo já vencido não aceita submissão.
  if (identical(so, "aberto") && !is.na(dl) && dl < as.Date(lubridate::with_tz(now, STATUS_TZ))) {
    so <- "encerrado"; nota <- "C\u00f3digo A com prazo vencido: o cliente p\u00fablico desabilita a submiss\u00e3o (tratado como encerrado)."
  }
  if (!st$conhecido) nota <- sprintf("C\u00f3digo de status SIGITEC n\u00e3o reconhecido ('%s'): estado preservado como desconhecido.", st$codigo %||% "")
  objective <- pick("objective"); challenge <- pick("challenge")
  desc <- if (!is.na(challenge)) paste0("Desafio: ", challenge, "\n\nObjetivo: ", objective) else objective
  theme <- pick("theme"); sub <- pick("subTheme")
  area <- if (!is.na(sub) && !is.na(theme)) paste0(theme, " - ", sub) else if (!is.na(theme)) theme else pick("area")
  trl <- pick("intendedTrl"); crl <- pick("intendedCrl")
  agencia <- pick("regulatoryAgency")
  obs <- paste(c(
    sprintf("Status oficial SIGITEC: %s (%s).", st$label %||% "desconhecido", st$codigo %||% ""),
    if (!is.na(trl) || !is.na(crl)) sprintf("N\u00edvel de maturidade pretendido: %s.", paste(stats::na.omit(c(trl, crl)), collapse = " / ")),
    if (!is.na(agencia)) sprintf("Ag\u00eancia reguladora (campo regulatoryAgency): %s.", agencia),
    nota), collapse = " ")
  det_url <- sigitec_detail_route(item$id, isTRUE(item$nodeBackend))
  prov <- list(
    make_provenance("titulo", titulo, paste0(SIGITEC_BASE, "/v2/ms-authorization/opportunity/getAllPublicOpportunities"), "titleOP/numberOP", "json:titleOP", "oficial", now),
    make_provenance("status_oficial", item$status %||% NA_character_, paste0(SIGITEC_BASE, "/v2/ms-authorization/opportunity/getAllPublicOpportunities"), paste("status =", item$status), "json:status", "oficial", now),
    make_provenance("data_limite", dl, paste0(SIGITEC_BASE, "/v2/ms-authorization/opportunity/getAllPublicOpportunities"), pick("deadlineSubmissionOfProposal"), "json:deadlineSubmissionOfProposal", "oficial", now),
    make_provenance("data_publicacao", pub, paste0(SIGITEC_BASE, "/v2/ms-authorization/opportunity/getAllPublicOpportunities"), pick("publicationDate"), "json:publicationDate", "oficial", now))
  br_record(
    fonte = "sigitec", entidade = "PETROBRAS", nome_fonte = "Petrobras SIGITEC", titulo = titulo,
    link_origem = page_url %||% BR_CANONICAL_URLS$sigitec, link_detalhe = det_url,
    descricao = desc, descricao_completa = desc, tipo_oportunidade = "chamada", modalidade = "competitividade",
    area = area, data_publicacao = pub, data_limite = dl, status_oficial = so,
    id_chamada = if (!is.na(num)) paste0("OP", num) else paste0("ID", item$id),
    observacoes = obs, provenance = prov, tipo_escopo = "fomento", now = now,
    texto_bruto = paste(titulo, desc))
}

collect_sigitec <- function(source_row = NULL, max_pages = 1, max_records = 50, use_ai = FALSE, log_path = NULL) {
  sid <- "sigitec"
  now <- br_now()
  listing_url <- paste0(SIGITEC_BASE, "/v2/ms-authorization/opportunity/getAllPublicOpportunities")
  page_url <- BR_CANONICAL_URLS$sigitec
  t0 <- Sys.time()
  hdr <- list(Referer = page_url, Origin = SIGITEC_BASE)
  fj <- br_fetch_json_text(listing_url, log_path, headers = hdr)
  if (!isTRUE(fj$ok)) {
    state <- switch(fj$kind %||% "network_error", tls_error = "erro_tls", blocked = "bloqueio", "erro_rede")
    diag <- make_source_diagnostics(state, mensagem = sprintf("Listagem SIGITEC indisponivel (%s): %s", fj$kind %||% "?", fj$error %||% ""),
                                    http_status = fj$status %||% NA_integer_, url_final = listing_url)
    return(br_result(sid, br_empty_records(), diag, 0L, listing_url))
  }
  pl <- sigitec_parse_listing(fj$body)
  if (!pl$ok) {
    # SPA/HTML/JSON inesperado: NAO e vazio confirmado (T06)
    diag <- make_source_diagnostics("erro_parser", mensagem = sprintf("Resposta da listagem SIGITEC nao e JSON de oportunidades (%s). A SPA exige render ou a API publica.", pl$kind),
                                    url_final = listing_url, http_status = fj$status %||% NA_integer_)
    return(br_result(sid, br_empty_records(), diag, 1L, listing_url))
  }
  items <- pl$items
  if (length(items) == 0L) {
    diag <- make_source_diagnostics("vazio_confirmado", mensagem = "Listagem SIGITEC retornou array JSON vazio (contrato reconhecido).", url_final = listing_url)
    return(br_result(sid, br_empty_records(), diag, 1L, listing_url))
  }
  # Prioridade: A > J > R > demais (mais recentes primeiro). Itens históricos não consomem limite dos ativos.
  prio <- vapply(items, function(i) match(toupper(i$status %||% ""), c("A", "J", "R", "F", "CC"), nomatch = 6L), integer(1))
  pubd <- vapply(items, function(i) as.numeric(sigitec_deadline_date(i$publicationDate %||% NA)), numeric(1))
  ord <- order(prio, -ifelse(is.na(pubd), 0, pubd))
  items <- items[ord]
  lim <- suppressWarnings(as.integer(max_records)); if (is.na(lim)) lim <- length(items)
  sel <- items[seq_len(min(lim, length(items)))]
  detail_fail <- 0L; recs <- list(); n_det <- 0L
  for (it in sel) {
    detail <- NULL
    if (toupper(it$status %||% "") %in% c("A", "J") && !isTRUE(it$nodeBackend) && n_det < 40L) {
      Sys.sleep(if (is.function(getOption("fi.br_json_fetcher"))) 0 else 0.4)
      fd <- br_fetch_json_text(paste0(SIGITEC_BASE, "/v2/ms-authorization/opportunity/public-opportunity/", it$id), log_path, headers = hdr)
      n_det <- n_det + 1L
      if (isTRUE(fd$ok)) detail <- tryCatch(jsonlite::fromJSON(fd$body, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(detail)) detail_fail <- detail_fail + 1L
    }
    recs[[length(recs) + 1L]] <- sigitec_item_to_record(it, detail, now, page_url)
  }
  fin <- br_finalize(dplyr::bind_rows(recs), Inf)
  st_derived <- derive_status_df(fin$records, now = now)
  n_open <- sum(st_derived %in% c("aberto", "encerrando"))
  n_unknown_code <- sum(vapply(sel, function(i) !sigitec_status_map(i$status)$conhecido, logical(1)))
  trunc <- length(items) > length(sel)
  diag <- make_source_diagnostics(
    if (detail_fail > 0L) "parcial" else "sucesso",
    n_candidatos = length(items), n_aceitos = fin$n_aceitos, n_rejeitados = length(items) - fin$n_aceitos,
    motivos_rejeicao = fin$rejeitados, url_final = listing_url, latencia_s = as.numeric(difftime(Sys.time(), t0, units = "secs")),
    truncado = trunc, paginas = 1L + n_det,
    mensagem = sprintf("%d oportunidade(s) SIGITEC no listing; %d processada(s)%s; %d aberta(s) para submiss\u00e3o (derivado); %d c\u00f3digo(s) de status desconhecido; %d falha(s) de detalhe.",
                       length(items), fin$n_aceitos, if (trunc) sprintf(" (TRUNCADO: %d omitida(s) por max_records, ativas priorizadas)", length(items) - length(sel)) else "",
                       n_open, n_unknown_code, detail_fail),
    extras = list(abertas = n_open))
  br_result(sid, fin$records, diag, 1L + n_det, listing_url)
}
register_collector("sigitec", collect_sigitec, "Petrobras SIGITEC: API publica (A/J/R/F/CC), sem fallback; substitui anp_shell")

# ─── BNDES (BR04) ─────────────────────────────────────────────────────────────
# Fonte: página oficial de licitações -> link "Chamadas públicas para contratação de inovação".
# A consulta estruturada geral de licitações tem fonte aberta própria (Portal de Dados Abertos do BNDES:
# https://dadosabertos.bndes.gov.br/dataset/licitacoes); seu adaptador está PENDENTE de validação online.

parse_bndes_licitacoes_links <- function(html_text, base_url) {
  doc <- br_html(html_text)
  a <- xml2::xml_find_all(doc, "//a[@href]")
  tibble::tibble(texto = .br_ws(xml2::xml_text(a)),
                 url = vapply(xml2::xml_attr(a, "href"), function(h) br_abs_url(base_url, h), character(1)))
}

parse_bndes_chamadas <- function(html_text, base_url) {
  doc <- br_html(html_text)
  nodes <- xml2::xml_find_all(doc, "//h1[contains(@class,'tituloConteudoInterna')]/following::*[self::h3 or self::h4 or self::p]")
  secao <- NA_character_; cur <- NULL; rows <- list()
  flush <- function() { if (!is.null(cur)) rows[[length(rows) + 1L]] <<- cur; cur <<- NULL }
  for (n in nodes) {
    cls <- xml2::xml_attr(n, "class") %||% ""
    if (grepl("grey-text", cls)) break
    nm <- xml2::xml_name(n); txt <- .br_ws(xml2::xml_text(n))
    if (nm == "h3") { flush(); secao <- txt; next }
    if (nm == "h4") { flush(); cur <- list(titulo = txt, descricao = NA_character_, url = NA_character_, secao = secao, extra = character()); next }
    if (is.null(cur) || !nzchar(gsub("\\s|\u00a0", "", txt))) next
    a <- xml2::xml_find_first(n, ".//a[@href]")
    if (!inherits(a, "xml_missing") && is.na(cur$url)) {
      cur$url <- br_abs_url(base_url, xml2::xml_attr(a, "href"))
    } else if (is.na(cur$descricao) && nchar(txt) > 40L) {
      cur$descricao <- txt
    } else cur$extra <- c(cur$extra, txt)
  }
  flush()
  if (!length(rows)) return(tibble::tibble(titulo = character(), descricao = character(), url = character(), secao = character()))
  tibble::tibble(titulo = vapply(rows, `[[`, "", "titulo"), descricao = vapply(rows, function(r) r$descricao, ""),
                 url = vapply(rows, function(r) r$url, ""), secao = vapply(rows, function(r) r$secao %||% NA_character_, ""))
}

collect_bndes <- function(source_row, max_pages = 2, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- "bndes"
  url <- br_source_url(source_row, sid)
  now <- br_now()
  fx <- br_fetch(url, log_path)
  if (!fx$ok) return(br_acquisition_failure(sid, fx, url, log_path))
  links <- parse_bndes_licitacoes_links(fx$text, fx$final_url)
  hit <- links[grepl("(?i)chamadas?\\s+p[u\u00fa]blicas?\\s+para\\s+contrata[c\u00e7][a\u00e3]o\\s+de\\s+inova", links$texto, perl = TRUE) & !is.na(links$url), , drop = FALSE]
  if (nrow(hit) == 0L) {
    diag <- make_source_diagnostics("erro_parser", mensagem = "Link 'Chamadas publicas para contratacao de inovacao' nao encontrado na pagina de licitacoes (contrato nao reconhecido).",
                                    url_final = fx$final_url, latencia_s = fx$latency)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  fc <- br_fetch(hit$url[[1]], log_path)
  if (!fc$ok) return(br_acquisition_failure(sid, fc, hit$url[[1]], log_path))
  cands <- parse_bndes_chamadas(fc$text, fc$final_url)
  if (nrow(cands) == 0L) {
    diag <- make_source_diagnostics("vazio_confirmado", mensagem = "Pagina de chamadas de inovacao reconhecida, sem chamadas listadas.",
                                    url_final = fc$final_url, latencia_s = fc$latency, paginas = 2L)
    return(br_result(sid, br_empty_records(), diag, 2L, fc$final_url))
  }
  recs <- list()
  for (i in seq_len(nrow(cands))) {
    cd <- cands[i, ]
    realizada <- grepl("(?i)j[a\u00e1]\\s+realizadas?", cd$secao, perl = TRUE)
    em_andamento <- grepl("(?i)em\\s+andamento", cd$secao, perl = TRUE)
    so <- if (realizada) "encerrado" else NA_character_
    ext <- !is.na(cd$url) && !grepl("(^|\\.)bndes\\.gov\\.br", sub("^https?://", "", cd$url))
    obs <- paste(c(
      if (em_andamento) "Listada como 'em andamento' (pode ser sele\u00e7\u00e3o ou execu\u00e7\u00e3o contratual): abertura efetiva de propostas deve ser confirmada no detalhe/edital.",
      if (ext) sprintf("Plataforma externa vinculada oficialmente pelo BNDES (%s); proveni\u00eancia preservada.", sub("^https?://([^/]+).*$", "\\1", cd$url))), collapse = " ")
    recs[[i]] <- br_record(
      fonte = sid, entidade = "BNDES", nome_fonte = "BNDES", titulo = cd$titulo, link_origem = fc$final_url,
      link_detalhe = cd$url, descricao = cd$descricao, descricao_completa = cd$descricao,
      tipo_oportunidade = "cpsi", modalidade = "contratacao de solucao inovadora",
      valor_total = NA_real_, status_oficial = so, id_chamada = extract_call_id(cd$titulo),
      observacoes = if (nzchar(obs)) obs else NA_character_, now = now, texto_bruto = paste(cd$titulo, cd$descricao),
      provenance = list(make_provenance("titulo", cd$titulo, fc$final_url, cd$titulo, "html:h4", "oficial", now),
                        make_provenance("objeto", cd$descricao, fc$final_url, cd$descricao, "html:p", "oficial", now),
                        make_provenance("status_oficial", so, fc$final_url, cd$secao, "html:h3 secao", "oficial", now)))
  }
  fin <- br_finalize(dplyr::bind_rows(recs), max_records)
  diag <- make_source_diagnostics(
    if (fin$n_aceitos > 0L) "sucesso" else "vazio_confirmado",
    n_candidatos = nrow(cands), n_aceitos = fin$n_aceitos, n_rejeitados = nrow(cands) - fin$n_aceitos, motivos_rejeicao = fin$rejeitados,
    url_final = fc$final_url, latencia_s = fc$latency, truncado = fin$truncado, paginas = 2L,
    mensagem = sprintf("%d chamada(s) de inova\u00e7\u00e3o/CPSI. Consulta estruturada de licita\u00e7\u00f5es (Dados Abertos BNDES) pendente de adaptador.", fin$n_aceitos))
  br_result(sid, fin$records, diag, 2L, fc$final_url)
}
register_collector("bndes", collect_bndes, "BNDES: chamadas publicas de inovacao/CPSI (sem navegacao/institucional)")

# ─── DCTA / Força Aérea Brasileira (BR05) ─────────────────────────────────────

parse_dcta_listing <- function(html_text, base_url) {
  doc <- br_html(html_text)
  body <- xml2::xml_find_first(doc, "//*[contains(@class,'com-content-article__body')]")
  empty <- tibble::tibble(titulo = character(), url = character(), rotulo = character())
  if (inherits(body, "xml_missing")) return(empty)
  ps <- xml2::xml_find_all(body, ".//p")
  rows <- list(); last_label <- NA_character_
  for (p in ps) {
    a <- xml2::xml_find_first(p, ".//a[@href]")
    txt <- .br_ws(xml2::xml_text(p))
    if (inherits(a, "xml_missing")) { if (nzchar(txt)) last_label <- txt; next }
    title <- .br_ws(xml2::xml_text(a))
    if (!grepl("(?i)chamada", title, perl = TRUE)) next
    rows[[length(rows) + 1L]] <- tibble::tibble(titulo = title, url = br_abs_url(base_url, xml2::xml_attr(a, "href")), rotulo = last_label)
  }
  if (!length(rows)) return(empty)
  dplyr::bind_rows(rows)
}

parse_dcta_detail <- function(html_text, base_url) {
  doc <- br_html(html_text)
  a <- xml2::xml_find_all(doc, "//a[@href]")
  pdfs <- tibble::tibble(nome = .br_ws(xml2::xml_text(a)),
                         url = vapply(xml2::xml_attr(a, "href"), function(h) br_abs_url(base_url, h), character(1)))
  pdfs <- pdfs[!is.na(pdfs$url) & grepl("(?i)\\.pdf($|\\?)", pdfs$url, perl = TRUE), , drop = FALSE]
  pdfs <- pdfs[!duplicated(pdfs$url), , drop = FALSE]
  art <- xml2::xml_find_first(doc, "//*[contains(@class,'com-content-article__body') or contains(@class,'item-page')]")
  txt <- if (inherits(art, "xml_missing")) .br_ws(xml2::xml_text(doc)) else .br_ws(xml2::xml_text(art))
  list(pdfs = pdfs, texto = txt, publicacao = extract_publication_date(txt))
}

collect_fab_dcta <- function(source_row, max_pages = 1, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- "fab_dcta"
  url <- br_source_url(source_row, sid)
  now <- br_now()
  fx <- br_fetch(url, log_path)
  if (!fx$ok) return(br_acquisition_failure(sid, fx, url, log_path))
  cands <- parse_dcta_listing(fx$text, fx$final_url)
  if (nrow(cands) == 0L) {
    diag <- make_source_diagnostics("erro_parser", mensagem = "Contrato da listagem DCTA/IEAv nao reconhecido (nenhuma chamada em .com-content-article__body).",
                                    url_final = fx$final_url, latencia_s = fx$latency)
    return(br_result(sid, br_empty_records(), diag, 1L, fx$final_url))
  }
  recs <- list(); n_det <- 0L; det_fail <- 0L
  for (i in seq_len(nrow(cands))) {
    cd <- cands[i, ]
    sched <- NULL; det <- NULL; pdf_main <- NA_character_
    fd <- br_fetch(cd$url, log_path); n_det <- n_det + 1L
    if (fd$ok) {
      det <- tryCatch(parse_dcta_detail(fd$text, fd$final_url), error = function(e) NULL)
      docs <- list()
      if (!is.null(det) && nrow(det$pdfs)) {
        for (j in seq_len(nrow(det$pdfs))) {
          pt <- br_fetch_pdf_text(det$pdfs$url[[j]], log_path)
          if (is.na(pt)) next
          retif <- grepl("(?i)retific", paste(det$pdfs$nome[[j]], det$pdfs$url[[j]]), perl = TRUE)
          docs[[length(docs) + 1L]] <- list(events = extract_labeled_events(pt), retificado = retif,
                                            nome = det$pdfs$url[[j]], ordem = if (retif) 2L else 1L)
          if (is.na(pdf_main) && !retif) pdf_main <- det$pdfs$url[[j]]
          if (is.na(pdf_main)) pdf_main <- det$pdfs$url[[j]]
        }
      }
      if (length(docs)) sched <- resolve_schedule(docs, now = now)
    } else det_fail <- det_fail + 1L
    pub <- if (!is.null(det) && !is.na(det$publicacao)) det$publicacao else if (!is.null(sched)) {
      if (!is.na(sched$data_publicacao)) sched$data_publicacao else sched$data_abertura
    } else as.Date(NA)
    dl <- if (!is.null(sched)) sched$data_limite else NA_character_
    ab <- if (!is.null(sched)) sched$data_abertura else as.Date(NA)
    prov <- list(make_provenance("titulo", cd$titulo, fx$final_url, cd$titulo, "html:.com-content-article__body a", "oficial", now))
    if (!is.null(sched) && !is.na(dl)) {
      prov <- c(prov, list(make_provenance("data_limite", dl, sched$fonte_prazo, "T\u00e9rmino do recebimento de Propostas", "pdf:cronograma", "oficial", now),
                           make_provenance("data_publicacao", pub, sched$fonte_prazo %||% fx$final_url, "In\u00edcio do recebimento de Propostas", "pdf:cronograma (in\u00edcio do recebimento = publica\u00e7\u00e3o)", "oficial", now)))
    }
    obs <- paste(c(
      if (!is.null(sched) && isTRUE(sched$retificacao_aplicada)) "Cronograma retificado aplicado: prazo de submiss\u00e3o vem da retifica\u00e7\u00e3o; datas de resultado/implementa\u00e7\u00e3o n\u00e3o substituem o prazo.",
      if (is.null(det)) "Detalhe indispon\u00edvel nesta rodada (bloqueio/erro de acesso).",
      if (!is.null(det) && is.null(sched)) "Detalhe lido, mas nenhum cronograma/PDF p\u00f4de ser extra\u00eddo: prazo desconhecido."), collapse = " ")
    recs[[i]] <- br_record(
      fonte = sid, entidade = "DCTA / For\u00e7a A\u00e9rea Brasileira", nome_fonte = "IEAv / DCTA / FAB", titulo = cd$titulo,
      link_origem = fx$final_url, link_detalhe = cd$url, link_pdf = pdf_main,
      descricao = if (!is.null(det)) substr(det$texto, 1L, 600L) else NA_character_,
      descricao_completa = if (!is.null(det)) det$texto else NA_character_,
      data_publicacao = pub, data_abertura = ab, data_limite = dl, id_chamada = extract_call_id(cd$titulo),
      observacoes = if (nzchar(obs)) obs else NA_character_, provenance = prov,
      tipo_default = "bolsa", detalhe_ok = !is.null(sched) && !is.na(dl), now = now,
      texto_bruto = if (!is.null(det)) det$texto else cd$titulo)
    recs[[i]]$tipo_escopo <- if (grepl("(?i)chamada\\s+p[u\u00fa]blica\\s+capa", cd$titulo, perl = TRUE)) "bolsa" else recs[[i]]$tipo_escopo
  }
  recs <- dplyr::bind_rows(recs)
  # Reaplica a decisão de validação após o tipo explícito (CAPA = bolsa/projeto de pesquisa)
  keep_ok <- recs$tipo_escopo == "bolsa"
  recs$validacao_status[keep_ok & recs$validacao_status == "rejeitado"] <- "a_verificar"
  fin <- br_finalize(recs, max_records)
  diag <- make_source_diagnostics(
    if (fin$n_aceitos > 0L) (if (det_fail > 0L) "parcial" else "sucesso") else "vazio_confirmado",
    n_candidatos = nrow(cands), n_aceitos = fin$n_aceitos, n_rejeitados = nrow(cands) - fin$n_aceitos, motivos_rejeicao = fin$rejeitados,
    url_final = fx$final_url, latencia_s = fx$latency, truncado = fin$truncado, paginas = 1L + n_det,
    mensagem = sprintf("%d chamada(s) IEAv/DCTA; %d detalhe(s) consultado(s), %d indispon\u00edvel(is). Chamadas sem detalhe/prazo ficam 'a verificar'.",
                       fin$n_aceitos, n_det, det_fail))
  br_result(sid, fin$records, diag, 1L + n_det, fx$final_url)
}
register_collector("fab_dcta", collect_fab_dcta, "DCTA/IEAv: chamadas CAPA com cronograma retificado (links resolvidos no host IEAv)")
