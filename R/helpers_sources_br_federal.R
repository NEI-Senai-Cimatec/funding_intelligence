# ─── Coletores brasileiros (parte 2): SIGITEC, BNDES, DCTA/FAB ────────────────
# Ver helpers_sources_br.R para o contrato comum (parsers puros, sem fallback fabricado,
# proveniência por campo, validação de domínio, estado oficial separado do derivado).

# ─── Petrobras SIGITEC / Conexões para Inovação (BR01) ────────────────────────
# A fonte mudou do antigo SIGITEC (/v2/public/opportunities) para o portal
# Conexões para Inovação (Salesforce Experience Cloud / Aura):
#   listagem: POST /conexoesinovacao/s/sfsites/aura  (ListViewDataManager.getItems)
#             objeto Desafio__c, list view 00BU4000009TpOhMAK, 50/página
#   detalhe : POST .../aura (RecordUiController.getRecordWithFields)
#   desafio : url_LinkDoDesafio__c -> API pública SIGITEC
#             GET /v2/ms-authorization/opportunity/public-opportunity/{id}
# Só entram desafios com pkl_Status__c == "Aberto". Recoletas são incrementais:
# o pipeline faz upsert por id_registro e não remove registros ausentes.
# A listagem Aura pode vir ordenada por Status ou por Data Limite; por isso a
# paginação não assume que todos os abertos estejam na primeira página.

SIGITEC_BASE <- "https://sigitec-competitividade.petrobras.com.br"
CONEXOES_BASE <- "https://conexoes-inovacao.petrobras.com.br"
CONEXOES_LIST_PATH <- "/conexoesinovacao/s/cooperacoes-tecnologicas?language=pt_BR"
CONEXOES_LIST_VIEW_ID <- "00BU4000009TpOhMAK"
CONEXOES_ENTITY <- "Desafio__c"
CONEXOES_STATUS_ABERTO <- "Aberto"
CONEXOES_MAX_OPEN <- 200L
CONEXOES_MAX_PAGES <- 40L
CONEXOES_DETAIL_FIELDS <- c(
  "Desafio__c.Name", "Desafio__c.pkl_Status__c", "Desafio__c.url_LinkDoDesafio__c",
  "Desafio__c.pkl_Fase__c", "Desafio__c.mpk_TipoDeChamada__c",
  "Desafio__c.dat_DataLimiteRecebimentoPreProposta__c",
  "Desafio__c.pkl_IdiomaDesafio__c", "Desafio__c.pkl_Modulo__c",
  "Desafio__c.SolucaoEsperadaDetalhada__c"
)

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

# Prazo ISO com offset -> data civil em America/Sao_Paulo (mesma semântica do cliente: formato YYYY-MM-DD local).
sigitec_deadline_date <- function(iso) {
  iso <- as.character(iso %||% NA_character_)
  if (length(iso) != 1L || is.na(iso) || !nzchar(iso)) return(as.Date(NA))
  p <- suppressWarnings(lubridate::ymd_hms(iso, quiet = TRUE, tz = "UTC"))
  if (is.na(p)) {
    d <- suppressWarnings(as.Date(substr(iso, 1L, 10L)))
    return(d)
  }
  as.Date(lubridate::with_tz(p, STATUS_TZ), tz = STATUS_TZ)
}

# ─── Aura (portal Conexões) ───────────────────────────────────────────────────

conexoes_aura_meta <- function(html) {
  h <- as.character(html %||% NA_character_)
  if (length(h) != 1L || is.na(h) || !nzchar(trimws(h))) {
    return(list(ok = FALSE, kind = "empty", reason = "HTML vazio"))
  }
  m <- regmatches(h, regexec("auraFW/javascript/([^/]+)/aura_prod\\.js", h, perl = TRUE))[[1]]
  fwuid <- if (length(m) >= 2L) utils::URLdecode(m[[2]]) else NA_character_
  if (is.na(fwuid) || !nzchar(fwuid)) {
    m2 <- regmatches(h, regexec("fwuid%22%3A%22([^%&\"']+)", h, perl = TRUE))[[1]]
    if (length(m2) >= 2L) fwuid <- utils::URLdecode(m2[[2]])
  }
  if (is.na(fwuid) || !nzchar(fwuid)) {
    return(list(ok = FALSE, kind = "sem_fwuid", reason = "fwuid Aura nao encontrado no HTML"))
  }
  list(ok = TRUE, kind = "aura_page", fwuid = fwuid, app = "siteforce:communityApp")
}

conexoes_aura_context <- function(meta) {
  list(
    mode = "PROD",
    fwuid = meta$fwuid %||% "",
    app = meta$app %||% "siteforce:communityApp",
    loaded = structure(list(), names = character(0)),
    dn = list(),
    globals = structure(list(), names = character(0)),
    uad = TRUE
  )
}

conexoes_page_uri <- function(url) {
  u <- as.character(url %||% NA_character_)
  if (length(u) != 1L || is.na(u) || !nzchar(u)) return(CONEXOES_LIST_PATH)
  sub("^https?://[^/]+", "", u)
}

conexoes_origin <- function(url) {
  u <- as.character(url %||% NA_character_)
  if (length(u) != 1L || is.na(u) || !nzchar(u)) return(CONEXOES_BASE)
  m <- regmatches(u, regexec("^(https?://[^/]+)", u, perl = TRUE))[[1]]
  if (length(m) >= 2L) m[[2]] else CONEXOES_BASE
}

conexoes_detail_page_url <- function(record_id, origin = CONEXOES_BASE) {
  sprintf("%s/conexoesinovacao/s/desafio/%s", origin, record_id)
}

conexoes_aura_fetch <- function(meta, actions, action_name, page_uri, origin = CONEXOES_BASE, log_path = NULL) {
  r <- as.integer(Sys.time()) %% 1000000L
  endpoint <- sprintf("%s/conexoesinovacao/s/sfsites/aura?r=%d&%s=1", origin, r, action_name)
  form <- list(
    message = jsonlite::toJSON(list(actions = actions), auto_unbox = TRUE, null = "null"),
    aura.context = jsonlite::toJSON(conexoes_aura_context(meta), auto_unbox = TRUE, null = "null"),
    aura.pageURI = page_uri,
    aura.token = "null"
  )
  br_fetch_json_post(
    endpoint, form, log_path,
    headers = list(Referer = paste0(origin, page_uri), Origin = origin)
  )
}

conexoes_aura_listing_actions <- function(offset = 0L) {
  list(list(
    id = "377;a",
    descriptor = "serviceComponent://ui.force.components.controllers.lists.listViewDataManager.ListViewDataManagerController/ACTION$getItems",
    callingDescriptor = "UNKNOWN",
    params = list(
      filterName = CONEXOES_LIST_VIEW_ID,
      entityName = CONEXOES_ENTITY,
      pageSize = 50L,
      layoutType = "LIST",
      sortBy = NULL,
      getCount = FALSE,
      enableRowActions = FALSE,
      offset = as.integer(offset)
    ),
    storable = TRUE
  ))
}

conexoes_aura_detail_actions <- function(record_id) {
  list(list(
    id = "309;a",
    descriptor = "aura://RecordUiController/ACTION$getRecordWithFields",
    callingDescriptor = "UNKNOWN",
    params = list(recordId = record_id, fields = CONEXOES_DETAIL_FIELDS)
  ))
}

# JSON Aura -> list(ok, kind, items, has_more, next_offset). Itens trazem
# id + fields (valores) + display (rótulos exibidos).
conexoes_parse_aura_listing <- function(body) {
  b <- as.character(body %||% NA_character_)
  if (length(b) != 1L || is.na(b) || !nzchar(trimws(b))) {
    return(list(ok = FALSE, kind = "empty", items = list(), reason = "corpo vazio"))
  }
  if (grepl("^\\s*<", b)) {
    return(list(ok = FALSE, kind = "html_nao_json", items = list(), reason = "HTML em vez de JSON Aura"))
  }
  parsed <- tryCatch(jsonlite::fromJSON(b, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed)) return(list(ok = FALSE, kind = "json_invalido", items = list(), reason = "JSON invalido"))
  acts <- parsed$actions
  if (!is.list(acts) || length(acts) == 0L) {
    return(list(ok = FALSE, kind = "aura_sem_actions", items = list(),
                reason = "resposta Aura sem actions (sessao invalida?)"))
  }
  act <- NULL
  for (a in acts) {
    if (is.list(a$returnValue) && !is.null(a$returnValue$recordIdActionsList)) { act <- a; break }
  }
  if (is.null(act)) {
    return(list(ok = FALSE, kind = "aura_sem_lista", items = list(),
                reason = "actions sem recordIdActionsList"))
  }
  rv <- act$returnValue
  raw_ids <- rv$recordIdActionsList
  ids <- if (is.list(raw_ids)) {
    vapply(raw_ids, function(x) as.character(x$recordId %||% NA_character_), character(1))
  } else character(0)
  ids <- ids[!is.na(ids) & nzchar(ids)]

  recs <- NULL
  for (g in parsed$context$globalValueProviders %||% list()) {
    if (isTRUE(as.character(g$type) == "$Record") && is.list(g$values$records)) { recs <- g$values$records; break }
  }
  if (length(ids) > 0L && is.null(recs)) {
    return(list(ok = FALSE, kind = "aura_sem_registros", items = list(),
                reason = "lista de IDs sem $Record no contexto Aura"))
  }
  items <- lapply(ids, function(id) {
    w <- recs[[id]]
    flds <- w[[CONEXOES_ENTITY]]$record$fields %||% list()
    list(
      id = id,
      fields = lapply(flds, function(x) x$value),
      display = lapply(flds, function(x) x$displayValue)
    )
  })
  list(
    ok = TRUE, kind = "aura_json", items = items,
    has_more = isTRUE(rv$hasMoreData),
    next_offset = suppressWarnings(as.integer(rv$offset %||% NA_integer_)),
    ordered_by = rv$orderedByInfo %||% NULL
  )
}

conexoes_parse_aura_detail <- function(body) {
  b <- as.character(body %||% NA_character_)
  if (length(b) != 1L || is.na(b) || !nzchar(trimws(b))) {
    return(list(ok = FALSE, kind = "empty", fields = list(), reason = "corpo vazio"))
  }
  if (grepl("^\\s*<", b)) {
    return(list(ok = FALSE, kind = "html_nao_json", fields = list(), reason = "HTML em vez de JSON Aura"))
  }
  parsed <- tryCatch(jsonlite::fromJSON(b, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed)) return(list(ok = FALSE, kind = "json_invalido", fields = list(), reason = "JSON invalido"))
  acts <- parsed$actions
  if (!is.list(acts) || length(acts) == 0L) {
    return(list(ok = FALSE, kind = "aura_sem_actions", fields = list(),
                reason = "resposta Aura sem actions (sessao invalida?)"))
  }
  rv <- acts[[1]]$returnValue
  if (is.null(rv) || !is.list(rv$fields)) {
    return(list(ok = FALSE, kind = "aura_sem_campos", fields = list(),
                reason = "detalhe Aura sem fields"))
  }
  list(ok = TRUE, kind = "aura_json", id = rv$id %||% NA_character_,
       fields = lapply(rv$fields, function(x) x$value))
}

conexoes_challenge_id <- function(url) {
  u <- as.character(url %||% NA_character_)
  if (length(u) != 1L || is.na(u) || !nzchar(u)) return(NA_character_)
  m <- regmatches(u, regexec("/(?:opportunity|opportunitysigitec)/([0-9]+)", u, perl = TRUE))[[1]]
  if (length(m) >= 2L) m[[2]] else NA_character_
}

# Item do portal + detalhe + API SIGITEC -> registro canônico da plataforma.
conexoes_item_to_record <- function(item, detail = NULL, challenge = NULL, now = NULL, page_url = NULL) {
  now <- now %||% br_now()
  val <- function(src, nm) {
    v <- src[[nm]]
    if (is.null(v) || length(v) == 0L) return(NA_character_)
    v <- v[[1]]
    if (length(v) != 1L || is.na(v)) return(NA_character_)
    v <- as.character(v)
    if (!nzchar(trimws(v))) NA_character_ else v
  }
  pick <- function(nm) {
    for (src in list(challenge, detail, item$fields)) {
      v <- val(src, nm)
      if (!is.na(v)) return(v)
    }
    NA_character_
  }
  nz <- function(x) if (is.na(x)) "" else x

  num <- val(challenge, "numberOP")
  ttl <- pick("titleOP")
  if (is.na(ttl)) ttl <- pick("Name")
  if (is.na(ttl)) ttl <- paste0("Desafio ", item$id %||% "")
  status_portal <- val(item$fields, "pkl_Status__c")
  if (is.na(status_portal)) status_portal <- val(detail, "pkl_Status__c")
  fase <- val(detail, "pkl_Fase__c")
  tipo <- val(detail, "mpk_TipoDeChamada__c")
  idioma_txt <- val(detail, "pkl_IdiomaDesafio__c")
  if (is.na(idioma_txt)) idioma_txt <- val(item$fields, "pkl_IdiomaDesafio__c")
  modulo <- val(detail, "pkl_Modulo__c")
  if (is.na(modulo)) modulo <- val(item$fields, "pkl_Modulo__c")

  portal_dl <- val(item$fields, "dat_DataLimiteRecebimentoPreProposta__c")
  if (is.na(portal_dl)) portal_dl <- val(detail, "dat_DataLimiteRecebimentoPreProposta__c")
  dl <- if (!is.na(portal_dl)) suppressWarnings(as.Date(substr(portal_dl, 1L, 10L))) else as.Date(NA)
  if (is.na(dl)) dl <- sigitec_deadline_date(val(challenge, "deadlineSubmissionOfProposal"))
  pub <- sigitec_deadline_date(val(challenge, "publicationDate"))

  portal_desc <- val(detail, "SolucaoEsperadaDetalhada__c")
  if (is.na(portal_desc)) portal_desc <- val(item$fields, "SolucaoEsperadaDetalhada__c")
  challenge_txt <- val(challenge, "challenge")
  objective <- val(challenge, "objective")
  expected <- val(challenge, "expectedSolutionDetail")
  theme <- val(challenge, "theme")
  subtheme <- val(challenge, "subTheme")
  area_sig <- val(challenge, "area")
  trl <- val(challenge, "intendedTrl")
  crl <- val(challenge, "intendedCrl")
  agency <- val(challenge, "regulatoryAgency")
  commitment <- val(challenge, "commitment")

  origin <- conexoes_origin(page_url %||% CONEXOES_BASE)
  portal_url <- conexoes_detail_page_url(item$id, origin)
  link_desafio <- val(detail, "url_LinkDoDesafio__c")
  if (is.na(link_desafio)) {
    cid <- val(challenge, "id")
    if (!is.na(cid)) link_desafio <- sprintf("%s/v2/public/opportunity/%s", SIGITEC_BASE, cid)
  }
  id_chamada <- if (!is.na(num)) paste0("OP", num) else paste0("CONEXOES-", item$id %||% "")
  titulo <- if (!is.na(num)) sprintf("OP%s - %s", num, ttl) else ttl

  status_oficial <- if (!is.na(status_portal) && isTRUE(tolower(trimws(status_portal)) == tolower(CONEXOES_STATUS_ABERTO))) {
    "aberto"
  } else {
    st <- sigitec_status_map(val(challenge, "status"))
    if (isTRUE(st$conhecido)) st$status_oficial else NA_character_
  }

  parts <- c(
    if (!is.na(challenge_txt)) paste0("Desafio:\n", challenge_txt),
    if (!is.na(objective)) paste0("Objetivo:\n", objective),
    if (!is.na(expected)) paste0("Solu\u00e7\u00e3o esperada:\n", expected)
  )
  desc_full <- if (length(parts) > 0L) paste(parts, collapse = "\n\n") else portal_desc
  area <- if (!is.na(theme) && !is.na(subtheme)) paste(theme, "-", subtheme)
          else if (!is.na(theme)) theme
          else if (!is.na(area_sig)) area_sig
          else modulo

  obs_parts <- c(
    if (!is.na(status_portal)) sprintf("Status no portal Conex\u00f5es: %s.", status_portal),
    if (!is.na(fase)) sprintf("Fase: %s.", fase),
    if (!is.na(tipo)) sprintf("Tipo de chamada: %s.", tipo),
    if (!is.na(trl) || !is.na(crl)) sprintf("N\u00edvel de maturidade pretendido: %s.",
                                             paste(stats::na.omit(c(trl, crl)), collapse = " / ")),
    if (!is.na(agency)) sprintf("Ag\u00eancia reguladora: %s.", agency),
    if (!is.na(commitment)) sprintf("Inten\u00e7\u00e3o de enquadramento: %s.", commitment),
    if (!is.na(link_desafio)) sprintf("Link do Desafio (SIGITEC): %s", link_desafio),
    if (!is.na(val(challenge, "status"))) {
      st <- sigitec_status_map(val(challenge, "status"))
      if (isTRUE(st$conhecido)) sprintf("Status oficial SIGITEC: %s (%s).", st$label, st$codigo)
      else sprintf("C\u00f3digo de status SIGITEC n\u00e3o reconhecido ('%s').", st$codigo)
    }
  )

  sigitec_url <- if (!is.na(link_desafio)) link_desafio else portal_url
  prov <- list(
    make_provenance("titulo", titulo, if (!is.na(num)) sigitec_url else portal_url, "titleOP/numberOP", "json:titleOP", "oficial", now),
    make_provenance("status_oficial", status_oficial, portal_url, sprintf("pkl_Status__c = %s", nz(status_portal)), "json:pkl_Status__c", "oficial", now),
    make_provenance("data_limite", dl, portal_url, nz(portal_dl), "json:dat_DataLimiteRecebimentoPreProposta__c", "oficial", now),
    make_provenance("data_publicacao", pub, sigitec_url, nz(val(challenge, "publicationDate")), "json:publicationDate", "oficial", now),
    make_provenance("link_desafio", link_desafio, portal_url, "url_LinkDoDesafio__c", "json:url_LinkDoDesafio__c", "oficial", now),
    make_provenance("area_tematica", area, sigitec_url, "theme/subTheme", "json:theme", "oficial", now)
  )

  br_record(
    fonte = "sigitec", entidade = "PETROBRAS", nome_fonte = "Petrobras SIGITEC",
    titulo = titulo,
    link_origem = portal_url,
    link_detalhe = if (!is.na(link_desafio)) link_desafio else portal_url,
    descricao = if (!is.na(portal_desc)) portal_desc else desc_full,
    descricao_completa = desc_full,
    tipo_oportunidade = "chamada", modalidade = "competitividade",
    area = area, data_publicacao = pub, data_limite = dl, status_oficial = status_oficial,
    id_chamada = id_chamada, observacoes = paste(obs_parts, collapse = " "),
    provenance = prov, tipo_escopo = "fomento",
    idioma = if (!is.na(idioma_txt) && grepl("ingl", idioma_txt, ignore.case = TRUE)) "en" else "pt",
    now = now, texto_bruto = paste(titulo, desc_full, area)
  )
}

collect_sigitec <- function(source_row = NULL, max_pages = 5, max_records = 50, use_ai = FALSE, log_path = NULL) {
  sid <- "sigitec"
  now <- br_now()
  page_url <- br_source_url(source_row, sid)
  if (is.null(page_url) || length(page_url) != 1L || is.na(page_url) || !nzchar(page_url)) {
    page_url <- BR_CANONICAL_URLS$sigitec
  }
  origin <- conexoes_origin(page_url)
  page_uri <- conexoes_page_uri(page_url)
  t0 <- Sys.time()

  fp <- br_fetch(page_url, log_path)
  if (!isTRUE(fp$ok)) return(br_acquisition_failure(sid, fp, page_url, log_path))
  meta <- conexoes_aura_meta(fp$text %||% "")
  if (!isTRUE(meta$ok)) {
    diag <- make_source_diagnostics(
      "erro_parser",
      mensagem = sprintf("Pagina do portal Conexoes sem contexto Aura (%s): %s", meta$kind %||% "?", meta$reason %||% ""),
      url_final = fp$final_url %||% page_url, http_status = fp$http_status %||% NA_integer_,
      latencia_s = as.numeric(difftime(Sys.time(), t0, units = "secs")), paginas = 0L
    )
    return(br_result(sid, br_empty_records(), diag, 0L, page_url))
  }

  # A ordenação da list view varia (Status/Data Limite) e os abertos podem estar
  # em qualquer página; por isso percorremos a listagem inteira com teto de segurança.
  max_pages <- suppressWarnings(as.integer(max_pages))
  if (is.na(max_pages) || max_pages < 1L) max_pages <- CONEXOES_MAX_PAGES
  page_cap <- max(max_pages, CONEXOES_MAX_PAGES)
  offset <- 0L; pages <- 0L; total_scanned <- 0L
  open <- list(); seen <- character(); listing_truncated <- FALSE; more_listing <- FALSE

  for (pg in seq_len(page_cap)) {
    fj <- conexoes_aura_fetch(
      meta, conexoes_aura_listing_actions(offset),
      "ui-force-components-controllers-lists-listViewDataManager.ListViewDataManager.getItems",
      page_uri, origin, log_path
    )
    if (!isTRUE(fj$ok)) {
      state <- switch(fj$kind %||% "network_error", tls_error = "erro_tls", blocked = "bloqueio", "erro_rede")
      diag <- make_source_diagnostics(
        state,
        mensagem = sprintf("Listagem do portal Conexoes indisponivel (%s): %s", fj$kind %||% "?", fj$error %||% ""),
        http_status = fj$status %||% NA_integer_, url_final = page_url,
        latencia_s = as.numeric(difftime(Sys.time(), t0, units = "secs")), paginas = pages
      )
      return(br_result(sid, br_empty_records(), diag, pages, page_url))
    }
    pl <- conexoes_parse_aura_listing(fj$body)
    if (!isTRUE(pl$ok)) {
      diag <- make_source_diagnostics(
        "erro_parser",
        mensagem = sprintf("Resposta da listagem do portal Conexoes nao e JSON Aura reconhecido (%s): %s",
                           pl$kind %||% "?", pl$reason %||% ""),
        http_status = fj$status %||% NA_integer_, url_final = page_url,
        latencia_s = as.numeric(difftime(Sys.time(), t0, units = "secs")), paginas = pages
      )
      return(br_result(sid, br_empty_records(), diag, pages, page_url))
    }

    pages <- pages + 1L
    total_scanned <- total_scanned + length(pl$items)
    open_page <- Filter(function(x) {
      st <- x$fields$pkl_Status__c %||% NA_character_
      !is.na(st) && isTRUE(tolower(trimws(st)) == tolower(CONEXOES_STATUS_ABERTO))
    }, pl$items)
    new_open <- Filter(function(x) !(x$id %in% seen), open_page)
    if (length(new_open) > 0L) {
      seen <- c(seen, vapply(new_open, function(x) x$id, character(1)))
      open <- c(open, new_open)
    }
    more_listing <- isTRUE(pl$has_more)
    if (!more_listing) break
    next_offset <- pl$next_offset
    offset <- if (!is.na(next_offset)) next_offset else offset + length(pl$items)
    if (offset <= 0L) break
  }
  listing_truncated <- isTRUE(more_listing) && pages >= page_cap

  n_open_total <- length(open)
  if (n_open_total == 0L) {
    diag <- make_source_diagnostics(
      if (listing_truncated) "parcial" else "vazio_confirmado",
      mensagem = sprintf(
        "%s (%d registro(s) verificado(s) em %d pagina(s)%s).",
        if (listing_truncated) "Nenhum desafio 'Aberto' nas paginas consultadas; listagem truncada"
        else "Nenhum desafio com Status 'Aberto' no portal Conexoes",
        total_scanned, pages, if (listing_truncated) sprintf(" de %d", page_cap) else ""
      ),
      url_final = page_url, latencia_s = as.numeric(difftime(Sys.time(), t0, units = "secs")),
      truncado = listing_truncated,
      paginas = pages,
      extras = list(total_listagem = total_scanned, abertos = 0L, truncado_listagem = listing_truncated)
    )
    return(br_result(sid, br_empty_records(), diag, pages, page_url))
  }

  # Abertos não são cortados pelo max_records padrão (15): o requisito é capturar
  # todos os abertos. Teto de segurança CONEXOES_MAX_OPEN (200), elevável por max_records.
  mr <- suppressWarnings(as.integer(max_records))
  if (is.na(mr) || mr < 1L) mr <- CONEXOES_MAX_OPEN
  open_limit <- min(max(CONEXOES_MAX_OPEN, mr), 500L)
  truncated_open <- n_open_total > open_limit
  open <- utils::head(open, open_limit)

  recs <- list(); n_detail_fail <- 0L; n_challenge_fail <- 0L
  n_no_link <- 0L; n_challenge_ok <- 0L; n_calls <- 0L

  for (it in open) {
    detail <- NULL; challenge <- NULL
    page_uri_det <- sprintf("/conexoesinovacao/s/desafio/%s", it$id)
    for (attempt in 1:2) {
      if (!is.function(getOption("fi.br_json_post_fetcher"))) {
        Sys.sleep(if (attempt == 1L) 0.15 else 0.4)
      }
      fd <- conexoes_aura_fetch(
        meta, conexoes_aura_detail_actions(it$id),
        "aura.RecordUi.getRecordWithFields", page_uri_det, origin, log_path
      )
      n_calls <- n_calls + 1L
      if (isTRUE(fd$ok)) {
        dp <- conexoes_parse_aura_detail(fd$body)
        if (isTRUE(dp$ok)) { detail <- dp$fields; break }
      }
    }
    if (is.null(detail)) {
      n_detail_fail <- n_detail_fail + 1L
      next
    }

    link <- detail$url_LinkDoDesafio__c %||% NA_character_
    if (is.na(link) || !nzchar(link)) {
      # Sem Link do Desafio: mantém o registro do portal com identidade provisória estável.
      n_no_link <- n_no_link + 1L
    } else {
      cid <- conexoes_challenge_id(link)
      if (is.na(cid)) {
        n_challenge_fail <- n_challenge_fail + 1L
        next
      }
      for (attempt in 1:2) {
        if (!is.function(getOption("fi.br_json_fetcher"))) {
          Sys.sleep(if (attempt == 1L) 0.25 else 0.6)
        }
        fj2 <- br_fetch_json_text(
          paste0(SIGITEC_BASE, "/v2/ms-authorization/opportunity/public-opportunity/", cid),
          log_path, headers = list(Referer = link, Origin = SIGITEC_BASE)
        )
        n_calls <- n_calls + 1L
        if (isTRUE(fj2$ok)) {
          challenge <- tryCatch(jsonlite::fromJSON(fj2$body, simplifyVector = FALSE), error = function(e) NULL)
        }
        if (!is.null(challenge)) break
      }
      if (is.null(challenge)) {
        n_challenge_fail <- n_challenge_fail + 1L
        next
      }
      n_challenge_ok <- n_challenge_ok + 1L
    }

    recs[[length(recs) + 1L]] <- conexoes_item_to_record(it, detail, challenge, now, page_url)
  }

  rec_df <- if (length(recs) > 0L) dplyr::bind_rows(recs) else br_empty_records()
  fin <- br_finalize(rec_df, Inf)
  n_fail <- n_detail_fail + n_challenge_fail
  trunc <- truncated_open || listing_truncated
  diag <- make_source_diagnostics(
    if (n_fail > 0L) "parcial" else "sucesso",
    n_candidatos = n_open_total, n_aceitos = fin$n_aceitos,
    n_rejeitados = max(0L, n_open_total - fin$n_aceitos),
    motivos_rejeicao = fin$rejeitados,
    url_final = page_url, latencia_s = as.numeric(difftime(Sys.time(), t0, units = "secs")),
    truncado = trunc, paginas = pages + n_calls,
    mensagem = sprintf(
      "%d desafio(s) no portal; %d aberto(s) capturado(s); %d processado(s)%s%s; %d falha(s) de detalhe; %d falha(s) no Link do Desafio.",
      total_scanned, n_open_total, fin$n_aceitos,
      if (truncated_open) sprintf(" (TRUNCADO: %d aberto(s) omitido(s) por limite)", n_open_total - open_limit) else "",
      if (listing_truncated) sprintf(" (LISTAGEM TRUNCADA em %d pagina(s))", page_cap) else "",
      n_detail_fail, n_challenge_fail
    ),
    extras = list(
      abertos = n_open_total, abertos_processados = length(open),
      total_listagem = total_scanned, detalhes_falhos = n_detail_fail,
      desafios_falhos = n_challenge_fail, sem_link_desafio = n_no_link,
      link_desafio_ok = n_challenge_ok, paginas_listagem = pages,
      truncado_listagem = listing_truncated
    )
  )
  br_result(sid, fin$records, diag, pages + n_calls, page_url)
}
register_collector("sigitec", collect_sigitec, "Petrobras SIGITEC/Conexoes: listagem Aura + detalhe + Link do Desafio; somente Aberto; sem fallback")

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
