`%||%` <- function(x, y) {
  if (is.null(x)) {
    return(y)
  }
  if (length(x) == 0) {
    return(y)
  }
  if (is.function(x)) {
    return(y)
  }
  if (all(is.na(x))) {
    return(y)
  }
  if (is.character(x)) {
    xx <- trimws(x)
    xx[is.na(xx)] <- ""
    if (!any(nzchar(xx))) {
      return(y)
    }
  }
  x
}


ensure_dir <- function(path) {
  if (is.null(path) || !nzchar(path)) {
    return(invisible(path))
  }
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}

safe_split <- function(x, pattern = "[;,|]+") {
  if (length(x) == 0 || is.null(x) || all(is.na(x))) {
    return(character())
  }
  out <- unlist(strsplit(paste(stats::na.omit(as.character(x)), collapse = ";"), pattern, perl = TRUE), use.names = FALSE)
  out <- trimws(out)
  out[nzchar(out)]
}

collapse_non_empty <- function(..., sep = "; ") {
  vals <- unlist(list(...), use.names = FALSE)
  vals <- as.character(vals)
  vals <- vals[!is.na(vals) & nzchar(trimws(vals))]
  paste(vals, collapse = sep)
}

sanitize_id <- function(x) {
  x <- stringi::stri_trans_general(as.character(x %||% ""), "Latin-ASCII")
  x <- tolower(gsub("[^a-zA-Z0-9]+", "_", x))
  x <- gsub("(^_+|_+$)", "", x)
  x
}

normalize_text <- function(x) {
  if (is.function(x)) {
    return("")
  }
  x <- x %||% ""
  x <- stringi::stri_trans_general(as.character(x), "Latin-ASCII")
  x <- tolower(x)
  x <- gsub("\\s+", " ", x, perl = TRUE)
  trimws(x)
}

normalize_ws <- function(x) {
  if (is.function(x)) {
    return("")
  }
  x <- x %||% ""
  x <- as.character(x)
  # Normaliza espaços Unicode comuns em páginas web, incluindo NBSP.
  x <- stringi::stri_replace_all_fixed(x, c(" ", " ", " "), " ", vectorize_all = FALSE)
  x <- stringi::stri_replace_all_regex(x, "\\p{Z}+", " ")
  x <- gsub("[[:space:]]+", " ", x, perl = TRUE)
  trimws(x)
}


null_if_empty <- function(v) {
  if (is.function(v)) {
    return(NA_character_)
  }
  if (is.null(v)) {
    return(NA_character_)
  }
  if (length(v) == 0) {
    return(v)
  }

  out <- tryCatch(as.character(v), error = function(e) rep(NA_character_, length(v)))
  if (length(out) == 0) {
    return(out)
  }
  out <- normalize_ws(out)
  out[is.na(out) | !nzchar(out)] <- NA_character_
  out
}


safe_numeric <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(NA_real_)
  }
  x <- normalize_ws(as.character(x))
  x <- stringi::stri_replace_all_fixed(x, c(" ", " ", " "), " ", vectorize_all = FALSE)
  x <- gsub("(?<=\\d)\\.(?=\\d{3}(\\D|$))", "", x, perl = TRUE)
  x <- gsub(",", ".", x, fixed = TRUE)
  x <- gsub("[^0-9.\\-]", "", x, perl = TRUE)
  suppressWarnings(as.numeric(x))
}

parse_date_safe <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (inherits(x, "POSIXct")) {
    return(as.Date(x))
  }
  if (length(x) == 0 || all(is.na(x))) {
    return(as.Date(rep(NA, length(x))))
  }
  x <- as.character(x)
  x[!nzchar(trimws(x))] <- NA_character_
  out <- suppressWarnings(lubridate::ymd(x, quiet = TRUE))
  idx <- is.na(out)
  if (any(idx)) out[idx] <- suppressWarnings(lubridate::dmy(x[idx], quiet = TRUE))
  idx <- is.na(out)
  if (any(idx)) out[idx] <- suppressWarnings(lubridate::mdy(x[idx], quiet = TRUE))
  idx <- is.na(out)
  if (any(idx)) out[idx] <- as.Date(suppressWarnings(lubridate::ymd_hms(x[idx], quiet = TRUE)))
  idx <- is.na(out)
  if (any(idx)) out[idx] <- as.Date(suppressWarnings(lubridate::dmy_hms(x[idx], quiet = TRUE)))
  as.Date(out)
}

parse_datetime_safe <- function(x) {
  if (inherits(x, "POSIXct")) {
    return(x)
  }
  if (length(x) == 0 || all(is.na(x))) {
    return(as.POSIXct(rep(NA, length(x)), origin = "1970-01-01", tz = "UTC"))
  }
  x <- as.character(x)
  x[!nzchar(trimws(x))] <- NA_character_
  out <- suppressWarnings(lubridate::ymd_hms(x, quiet = TRUE, tz = "UTC"))
  idx <- is.na(out)
  if (any(idx)) out[idx] <- suppressWarnings(lubridate::dmy_hms(x[idx], quiet = TRUE, tz = "UTC"))
  idx <- is.na(out)
  if (any(idx)) out[idx] <- suppressWarnings(lubridate::ymd(x[idx], quiet = TRUE, tz = "UTC"))
  idx <- is.na(out)
  if (any(idx)) out[idx] <- suppressWarnings(lubridate::dmy(x[idx], quiet = TRUE, tz = "UTC"))
  out
}

format_date_br <- function(x) {
  x <- parse_date_safe(x)
  ifelse(is.na(x), "-", format(x, "%d/%m/%Y"))
}

days_to_deadline <- function(x) {
  x <- parse_date_safe(x)
  as.integer(x - Sys.Date())
}

classify_status <- function(deadline = NA, start = NA, end = NA, text = NULL) {
  dl <- parse_date_safe(deadline)
  st <- parse_date_safe(start)
  en <- parse_date_safe(end)
  txt <- as.character(text %||% NA_character_)
  n <- max(length(dl), length(st), length(en), length(txt), 1L)
  dl <- rep_len(dl, n)
  st <- rep_len(st, n)
  en <- rep_len(en, n)
  txt <- rep_len(txt, n)

  out <- vapply(seq_len(n), function(i) {
    txt_i <- normalize_text(txt[[i]] %||% "")
    dl_i <- dl[[i]]
    en_i <- en[[i]]
    st_i <- st[[i]]
    ref <- if (!is.na(dl_i)) dl_i else en_i
    today <- Sys.Date()
    if (!is.na(ref)) {
      diff_days <- as.integer(ref - today)
      return(dplyr::case_when(
        diff_days < 0 ~ "encerrado",
        diff_days <= 14 ~ "encerrando",
        !is.na(st_i) && st_i > today ~ "em breve",
        TRUE ~ "aberto"
      ))
    }
    if (grepl("encerrad|closed|finalizad|expired", txt_i, ignore.case = TRUE)) {
      return("encerrado")
    }
    if (grepl("open|abert|ongoing|em andamento", txt_i, ignore.case = TRUE)) {
      return("aberto")
    }
    if (grepl("coming soon|em breve|upcoming", txt_i, ignore.case = TRUE)) {
      return("em breve")
    }
    "indefinido"
  }, character(1))
  out
}

normalize_country <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) {
    return(NA_character_)
  }
  key <- normalize_text(x)
  dict <- c(
    "brazil" = "Brasil", "brasil" = "Brasil", "brazilian" = "Brasil",
    "united states" = "Estados Unidos", "usa" = "Estados Unidos", "u.s." = "Estados Unidos",
    "canada" = "Canadá", "germany" = "Alemanha", "deutschland" = "Alemanha",
    "france" = "França", "european union" = "União Europeia", "eu" = "União Europeia",
    "uniao europeia" = "União Europeia",
    "international" = "Internacional", "global" = "Internacional", "multicountry" = "Internacional",
    "united kingdom" = "Reino Unido"
  )
  if (key %in% names(dict)) dict[[key]] else tools::toTitleCase(trimws(x))
}

infer_language_simple <- function(text) {
  vals <- as.character(text %||% NA_character_)
  vapply(vals, function(one) {
    if (length(one) == 0 || is.na(one)) {
      return(NA_character_)
    }
    txt <- normalize_text(substr(one, 1, 3000))
    if (!length(txt) || is.na(txt) || !nzchar(txt)) {
      return(NA_character_)
    }
    if (grepl("\\b(edital|chamada|fomento|bolsa|auxilio|inscricoes|prazo)\\b", txt, perl = TRUE, ignore.case = TRUE)) {
      return("pt")
    }
    if (grepl("\\b(call|grant|funding|scholarship|deadline|eligibility)\\b", txt, perl = TRUE, ignore.case = TRUE)) {
      return("en")
    }
    if (grepl("\\b(convocatoria|subvencion|beca|financiacion)\\b", txt, perl = TRUE, ignore.case = TRUE)) {
      return("es")
    }
    NA_character_
  }, character(1))
}

funding_lexicon <- function() {
  c(
    "edital", "chamada", "bolsa", "auxilio", "auxílio", "subvenção", "subvencao", "fomento",
    "grant", "funding", "fellowship", "scholarship", "call for proposals", "call for applications",
    "research funding", "research grant", "innovation funding", "innovation grant", "subsidy",
    "financial support", "research support", "innovation support", "award", "proposal"
  )
}

infer_type_from_text <- function(text) {
  txt <- normalize_text(text %||% "")
  dplyr::case_when(
    grepl("fellowship|scholarship|bolsa", txt) ~ "bolsa",
    grepl("subvenc|subsidy|financial support", txt) ~ "subvenção",
    grepl("call for proposals|call for applications|chamada", txt) ~ "chamada pública",
    grepl("grant|research grant|funding", txt) ~ "grant",
    grepl("award|premio|premio", txt) ~ "prêmio",
    grepl("edital", txt) ~ "edital",
    TRUE ~ "oportunidade"
  )
}

extract_keywords_simple <- function(text, top_n = 8) {
  txt <- normalize_text(text %||% "")
  if (!nzchar(txt)) {
    return(NA_character_)
  }
  tokens <- unlist(strsplit(txt, "[^a-z0-9]+", perl = TRUE), use.names = FALSE)
  tokens <- tokens[nchar(tokens) >= 4]
  stopwords <- unique(c(
    funding_lexicon(),
    # Pronomes, preposições, verbos e termos comuns de conexão
    "para", "with", "from", "that", "this", "will", "have", "your", "than", "como", "mais", "para", "com", "uma", "mais", "será", "pelo", "pela", "sobre", "entre", "onde", "quem", "seus", "suas",
    # Palavras administrativas/procedimentais genéricas em português
    "projeto", "projetos", "recurso", "recursos", "proposta", "propostas", "instituicao", "instituicoes", "instituição", "instituições", "bolsa", "bolsas", "execucao", "execução", "inovacao", "inovação", "proponente", "proponentes", "desenvolvimento", "desenvolvimentos", "tecnologia", "tecnologias", "apoio", "pesquisa", "pesquisas", "cientifico", "científico", "ciencia", "ciência", "chamada", "chamadas", "publica", "pública", "publico", "público", "fomento", "fomentos", "financiar", "financiamento", "financiamentos", "paragrafo", "parágrafo", "documento", "documentos", "beneficiaria", "beneficiária", "prazo", "prazos", "valor", "valores", "edital", "editais", "anexo", "anexos", "artigo", "artigos", "inciso", "incisos", "lei", "leis", "portaria", "portarias", "decreto", "decretos", "resolucao", "resolução", "pagina", "página", "paginas", "páginas", "site", "sites", "web", "link", "links", "email", "e-mail", "telefone", "telefones", "endereco", "endereço", "candidato", "candidatos", "candidatura", "candidaturas", "submissao", "submissão", "formulario", "formulário", "anual", "mensal", "diario", "diário", "devera", "deverá", "cada", "despesas", "despesa", "cientifica", "científica", "cooperacao", "cooperação", "sendo", "pode", "devem", "serao", "serão", "sobre", "pelas", "pelos", "caso", "seria", "serian", "seriam", "esta", "está", "estao", "estão",
    # Palavras administrativas genéricas em inglês
    "proposal", "proposals", "application", "applications", "research", "researches", "programa", "program", "programs", "state", "fapes", "cnpq", "capes", "finep", "funding", "fundings", "grant", "grants", "scholarship", "scholarships", "fellowship", "fellowships", "award", "awards", "call", "calls", "deadline", "deadlines", "eligible", "eligibility", "institution", "institutions", "candidate", "candidates", "submission", "submissions", "form", "forms", "annex", "annexes", "guideline", "guidelines", "notice", "notices", "budget", "budgets", "cost", "costs", "partner", "partners", "project", "projects", "support", "supports", "development", "developments"
  ))
  tokens <- tokens[!(tokens %in% normalize_text(stopwords))]
  if (length(tokens) == 0) {
    return(NA_character_)
  }
  freq <- sort(table(tokens), decreasing = TRUE)
  paste(names(freq)[seq_len(min(top_n, length(freq)))], collapse = "; ")
}

parse_money_text <- function(text) {
  txt <- normalize_ws(text %||% "")
  if (!nzchar(txt)) {
    return(list(value = NA_real_, currency = NA_character_))
  }
  currency <- dplyr::case_when(
    grepl("R\\$|reais|brl", txt, ignore.case = TRUE) ~ "BRL",
    grepl("US\\$|usd|dollars?", txt, ignore.case = TRUE) ~ "USD",
    grepl("€|eur|euros?", txt, ignore.case = TRUE) ~ "EUR",
    grepl("cad|canadian", txt, ignore.case = TRUE) ~ "CAD",
    grepl("gbp|£|pounds?", txt, ignore.case = TRUE) ~ "GBP",
    TRUE ~ NA_character_
  )
  value <- suppressWarnings({
    m <- stringr::str_extract(txt, "(R\\$|US\\$|USD|EUR|€|CAD|GBP|£)\\s*[0-9][0-9\\., ]+")
    safe_numeric(m)
  })
  list(value = value, currency = currency)
}

extract_dates_from_text <- function(text) {
  txt <- text %||% ""
  pats <- c(
    "\\b\\d{1,2}/\\d{1,2}/\\d{4}\\b",
    "\\b\\d{4}-\\d{2}-\\d{2}\\b",
    "\\b\\d{1,2} de [A-Za-zçãéíóúâêô]+ de \\d{4}\\b"
  )
  hits <- unique(unlist(lapply(pats, function(p) stringr::str_extract_all(txt, stringr::regex(p, ignore_case = TRUE))[[1]]), use.names = FALSE))
  hits <- hits[nzchar(hits)]
  if (length(hits) == 0) {
    return(as.Date(character()))
  }
  month_map <- c(
    janeiro = "01", fevereiro = "02", marco = "03", março = "03", abril = "04", maio = "05", junho = "06",
    julho = "07", agosto = "08", setembro = "09", outubro = "10", novembro = "11", dezembro = "12"
  )
  normalize_pt_date <- function(x) {
    key <- normalize_text(x)
    if (!grepl(" de ", key, fixed = TRUE)) {
      return(x)
    }
    m <- regmatches(key, regexec("(\\d{1,2}) de ([a-zçãéíóúâêô]+) de (\\d{4})", key))[[1]]
    if (length(m) == 4) sprintf("%s-%s-%02d", m[4], month_map[[m[3]]] %||% "01", as.integer(m[2])) else x
  }
  parse_date_safe(vapply(hits, normalize_pt_date, character(1)))
}

make_hash <- function(...) digest::digest(paste(..., collapse = "||"), algo = "xxhash64")

safe_html_text <- function(node) {
  if (is.null(node) || length(node) == 0 || inherits(node, "xml_missing")) {
    return(NA_character_)
  }
  if (inherits(node, "xml_nodeset")) {
    if (length(node) == 0) {
      return(NA_character_)
    }
    node <- node[[1]]
  }
  # Clone para evitar mutação indesejada do DOM original
  node_copy <- tryCatch(xml2::xml_clone(node), error = function(e) node)
  try(
    {
      xml2::xml_remove(xml2::xml_find_all(node_copy, ".//script|.//style|.//iframe|.//noscript|.//svg"))
    },
    silent = TRUE
  )
  out <- tryCatch(rvest::html_text2(node_copy, preserve_nbsp = FALSE), error = function(e) NA_character_)
  normalize_ws(out)
}

safe_attr <- function(node, attr) {
  if (inherits(node, "xml_missing") || length(node) == 0 || is.null(node)) {
    return(NA_character_)
  }
  val <- rvest::html_attr(node, attr)
  if (length(val) == 0) {
    return(NA_character_)
  }
  val
}

resolve_url <- function(base_url, href) {
  if (is.null(href) || length(href) == 0) {
    return(NA_character_)
  }
  href <- as.character(href[[1]])
  if (is.na(href)) {
    return(NA_character_)
  }
  href <- trimws(href)
  if (!nzchar(href)) {
    return(NA_character_)
  }
  if (grepl("^(javascript:|mailto:|tel:)", href, ignore.case = TRUE)) {
    return(NA_character_)
  }
  if (grepl("^https?://", href, ignore.case = TRUE)) {
    return(href)
  }
  if (grepl("^//", href)) {
    scheme <- tryCatch(xml2::url_parse(base_url)$scheme, error = function(e) "https")
    scheme <- if (is.null(scheme) || !nzchar(scheme)) "https" else scheme
    return(paste0(scheme, ":", href))
  }
  href_enc <- tryCatch(utils::URLencode(href, repeated = FALSE), error = function(e) href)
  out <- tryCatch(xml2::url_absolute(href_enc, base_url), error = function(e) NA_character_)
  if (length(out) == 0 || is.na(out) || !nzchar(out)) {
    return(NA_character_)
  }
  out
}


pick_first_nonempty <- function(...) {
  vals <- list(...)
  for (v in vals) {
    if (is.null(v) || is.function(v) || length(v) == 0) next
    vv <- tryCatch(as.character(v), error = function(e) character())
    if (length(vv) == 0) next
    vv <- normalize_ws(vv)
    vv <- vv[!is.na(vv) & nzchar(vv)]
    if (length(vv) > 0) {
      return(vv[[1]])
    }
  }
  NA_character_
}


extract_pdf_links <- function(html, base_url) {
  hrefs <- rvest::html_elements(html, "a[href]") |> rvest::html_attr("href")
  hrefs <- hrefs[grepl("\\.pdf($|\\?)", hrefs, ignore.case = TRUE)]
  unique(vapply(hrefs, function(h) resolve_url(base_url, h), character(1)))
}

nearest_block_text <- function(node, max_levels = 4) {
  if (is.null(node) || length(node) == 0 || inherits(node, "xml_missing")) {
    return(NA_character_)
  }
  if (inherits(node, "xml_nodeset")) {
    if (length(node) == 0) {
      return(NA_character_)
    }
    node <- node[[1]]
  }
  cur <- node
  best <- safe_html_text(cur)
  if (is.na(best)) best <- ""
  for (i in seq_len(max_levels)) {
    cur <- tryCatch(xml2::xml_parent(cur), error = function(e) xml2::xml_missing())
    if (inherits(cur, "xml_missing") || length(cur) == 0 || is.null(cur)) break
    txt <- safe_html_text(cur)
    txt_len <- ifelse(is.na(txt), 0L, nchar(txt))
    best_len <- ifelse(is.na(best), 0L, nchar(best))
    if (txt_len > best_len && txt_len <= 2500) best <- txt
  }
  if (!nzchar(best)) NA_character_ else best
}

log_write <- function(log_path, level = "INFO", message = "") {
  ensure_dir(dirname(log_path))
  line <- sprintf("[%s] [%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, message)
  cat(line, file = log_path, append = TRUE, sep = "\n")
  message(line)
  invisible(line)
}

badge_status_html <- function(status) {
  status <- tolower(status %||% "indefinido")
  class_name <- switch(status,
    "aberto" = "badge-soft-open",
    "encerrando" = "badge-soft-warning",
    "em breve" = "badge-soft-info",
    "encerrado" = "badge-soft-closed",
    "badge-soft-neutral"
  )
  sprintf("<span class='status-badge %s'>%s</span>", class_name, tools::toTitleCase(status))
}

score_bar_html <- function(score) {
  score <- round(pmax(pmin(score %||% 0, 100), 0))
  sprintf("<div class='score-wrap'><div class='score-bar'><div class='score-bar-fill' style='width:%s%%;'></div></div><div class='score-label'>%s</div></div>", score, score)
}

make_click_button <- function(id_value, label = "Rastrear", class = "btn btn-sm btn-outline-primary action-link-btn") {
  sprintf(
    "<button class='%s' data-id='%s' onclick=\"Shiny.setInputValue('row_action', {id: '%s', nonce: Math.random()}, {priority: 'event'})\">%s</button>",
    class, id_value, id_value, label
  )
}

make_view_button <- function(id_value, label = "🔍", class = "btn btn-sm btn-outline-info action-view-btn") {
  sprintf(
    "<button class='%s' data-id='%s' onclick=\"Shiny.setInputValue('row_view', {id: '%s', nonce: Math.random()}, {priority: 'event'})\">%s</button>",
    class, id_value, id_value, label
  )
}

make_actions_html <- function(id_value) {
  btn_view <- sprintf(
    "<button class='btn btn-sm btn-outline-primary action-view-btn' style='padding: 2px 8px; font-size: 0.75rem;' onclick=\"Shiny.setInputValue('row_view', {id: '%s', nonce: Math.random()}, {priority: 'event'})\"><i class='fa fa-eye'></i> Visualizar</button>",
    id_value
  )
  btn_track <- sprintf(
    "<button class='btn btn-sm btn-success action-link-btn' style='padding: 2px 8px; font-size: 0.75rem;' onclick=\"Shiny.setInputValue('row_action', {id: '%s', nonce: Math.random()}, {priority: 'event'})\"><i class='fa fa-map-marker-alt'></i> Rastrear</button>",
    id_value
  )
  sprintf("<div style='display: flex; gap: 4px; white-space: nowrap;'>%s%s</div>", btn_view, btn_track)
}

calculate_dynamic_adherence <- function(query, keywords, summary, title = "", subtitle = "", default_score = 0) {
  if (is.null(query) || !nzchar(trimws(query))) {
    return(as.integer(default_score %||% 0))
  }

  # Normalize and clean the query string
  query_clean <- tolower(query)
  # Remove boolean logic symbols and punctuation
  query_clean <- gsub("[()\"':;,!?|]", " ", query_clean)
  query_clean <- gsub("\\b(and|or|not|&&|\\|\\||!)\\b", " ", query_clean, perl = TRUE)

  # Split into unique terms
  words <- unlist(strsplit(query_clean, "\\s+"))
  words <- unique(trimws(words))
  words <- words[nzchar(words) & nchar(words) >= 3]

  if (length(words) == 0) {
    return(as.integer(default_score %||% 0))
  }

  # Text to search in: title, subtitle, keywords, and summary/object
  text_to_search <- tolower(paste(
    title %||% "",
    subtitle %||% "",
    keywords %||% "",
    summary %||% "",
    collapse = " "
  ))

  # Count matches
  matches <- vapply(words, function(w) {
    w_esc <- gsub("([^a-zA-Z0-9])", "\\\\\\1", w)
    grepl(paste0("\\b", w_esc, "\\b"), text_to_search, perl = TRUE) || grepl(w, text_to_search, fixed = TRUE)
  }, logical(1))

  # Calculate match percentage
  match_ratio <- sum(matches) / length(words)
  as.integer(round(match_ratio * 100))
}

link_html <- function(url, label = NULL) {
  if (is.na(url) || !nzchar(url)) {
    return("-")
  }
  label <- label %||% "Abrir"
  sprintf("<a href='%s' target='_blank' rel='noopener noreferrer'>%s</a>", url, label)
}

clean_edital_title <- function(title) {
  if (is.null(title) || is.na(title) || !nzchar(title)) {
    return(NA_character_)
  }

  # Se parecer um nome de arquivo (termina com extensões comuns ou não tem espaços e tem extensão)
  if (grepl("\\.(pdf|docx|xlsx|zip)$", title, ignore.case = TRUE) || !grepl(" ", title)) {
    # Remove extensão
    title <- tools::file_path_sans_ext(title)
    # Substitui underlines e hifens por espaços
    title <- gsub("[_-]", " ", title)
    # Insere espaço entre letras minúsculas/números e maiúsculas
    title <- gsub("([a-z0-9])([A-Z])", "\\1 \\2", title)
    # Insere espaço entre letras e números
    title <- gsub("([a-zA-Z])([0-9])", "\\1 \\2", title)
    title <- gsub("([0-9])([a-zA-Z])", "\\1 \\2", title)
    # Tenta separar preposições e conjunções em português que possam estar coladas
    # ex: "FamiliaePoliticas" -> "Familia e Politicas", "PublicasnoBrasil" -> "Publicas no Brasil"
    title <- gsub("(\\b[A-Za-z]+a)e(\\b|\\s|[A-Z])", "\\1 e \\2", title)
    title <- gsub("(\\b[A-Za-z]+o)e(\\b|\\s|[A-Z])", "\\1 e \\2", title)
    title <- gsub("(\\b[A-Za-z]+[a-z])no(\\b|\\s|[A-Z])", "\\1 no \\2", title)
    title <- gsub("(\\b[A-Za-z]+[a-z])na(\\b|\\s|[A-Z])", "\\1 na \\2", title)
    title <- gsub("(\\b[A-Za-z]+[a-z])de(\\b|\\s|[A-Z])", "\\1 de \\2", title)
    title <- gsub("(\\b[A-Za-z]+[a-z])do(\\b|\\s|[A-Z])", "\\1 do \\2", title)
    title <- gsub("(\\b[A-Za-z]+[a-z])da(\\b|\\s|[A-Z])", "\\1 da \\2", title)
    title <- gsub("(\\b[A-Za-z]+[a-z])para(\\b|\\s|[A-Z])", "\\1 para \\2", title)
    title <- gsub("(\\b[A-Za-z]+[a-z])em(\\b|\\s|[A-Z])", "\\1 em \\2", title)

    # Normaliza espaços
    title <- trimws(gsub("\\s+", " ", title))
  }

  title
}

is_current_year_record <- function(pub_date_str, limit_date_str, title, text, is_eu_source = FALSE) {
  current_year <- as.integer(format(Sys.Date(), "%Y"))

  # Heuristica rapida: se o titulo menciona explicitamente o ano corrente, aceitar
  year_pattern <- sprintf("\\b%d\\b", current_year)
  if (grepl(year_pattern, title %||% "")) {
    return(TRUE)
  }

  pub_date <- parse_date_safe(pub_date_str)
  limit_date <- parse_date_safe(limit_date_str)

  pub_year <- if (!is.na(pub_date)) as.integer(format(pub_date, "%Y")) else NA_integer_
  limit_year <- if (!is.na(limit_date)) as.integer(format(limit_date, "%Y")) else NA_integer_

  # Para fontes EU (HEU/ERC): work programmes sao plurianuais
  # Aceitar registros com deadline >= ano corrente
  if (is_eu_source) {
    if (!is.na(limit_year) && limit_year >= current_year) {
      return(TRUE)
    }
    if (!is.na(pub_year) && pub_year >= current_year) {
      return(TRUE)
    }
    year_pattern_future <- sprintf("\\b(%d|%d)\\b", current_year, current_year + 1)
    if (grepl(year_pattern_future, title %||% "")) {
      return(TRUE)
    }
    if (grepl(year_pattern_future, text %||% "")) {
      return(TRUE)
    }
    return(TRUE)
  }

  # Se tiver data limite, valida pelo ano corrente
  if (!is.na(limit_year)) {
    if (limit_year == current_year) {
      return(TRUE)
    }
    if (limit_year > current_year) {
      return(TRUE)
    }
  }

  # Se tiver data de publicacao, valida pelo ano corrente
  if (!is.na(pub_year)) {
    if (pub_year == current_year) {
      return(TRUE)
    }
    if (pub_year > current_year) {
      return(TRUE)
    }
  }

  # Heuristica: se mencionar o ano corrente no texto
  if (grepl(year_pattern, text %||% "")) {
    return(TRUE)
  }

  # Se mencionar anos passados recentes e nenhum sinal de ano corrente, consideramos edital antigo
  past_years <- (current_year - 2):(current_year - 1)
  past_patterns <- paste0("\\b", past_years, "\\b")
  has_past_year <- any(vapply(past_patterns, function(p) grepl(p, title %||% "") || grepl(p, text %||% ""), logical(1)))
  if (has_past_year) {
    return(FALSE)
  }

  TRUE
}

# ── Pool rotativo de User-Agents e headers centralizados ──────────────────────

.USER_AGENTS <- c(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0"
)

get_random_ua <- function() {
  sample(.USER_AGENTS, 1L)
}

build_scrape_headers <- function(ua = NULL) {
  if (is.null(ua)) ua <- get_random_ua()
  list(
    `User-Agent` = ua,
    `Accept` = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    `Accept-Language` = "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7",
    `Accept-Encoding` = "gzip, deflate, br",
    `Connection` = "keep-alive",
    `Upgrade-Insecure-Requests` = "1",
    `Sec-Fetch-Dest` = "document",
    `Sec-Fetch-Mode` = "navigate",
    `Sec-Fetch-Site` = "none",
    `Sec-Fetch-User` = "?1",
    `Cache-Control` = "max-age=0"
  )
}

# ── Função unificada de preenchimento de campos via IA ────────────────────────

#' Preenche um campo de um dataframe com valor extraído pela IA.
#' Modifica `target_df` e `inferred_fields` no escopo pai via `<<-`.
#'
#' @param field Nome do campo a preencher.
#' @param value Valor extraído pela IA.
#' @param overwrite Se TRUE, sobrescreve valor existente.
#' @param target_df Dataframe alvo (será modificado via <<-).
#' @param row_idx Índice da linha a modificar (para dataframes multi-linha).
#' @param inferred_fields Vetor de campos já inferidos (será modificado via <<-).
fill_ai_field <- function(field, value, overwrite = FALSE,
                          target_df, row_idx = 1L, inferred_fields) {
  if (is.null(value) || length(value) == 0) {
    return(invisible(NULL))
  }
  if (length(value) > 1) {
    value <- paste(vapply(value, as.character, character(1)), collapse = "; ")
  } else {
    value <- as.character(value[[1]])
  }
  if (is.na(value) || !nzchar(trimws(value))) {
    return(invisible(NULL))
  }

  if (field == "palavras_chave") {
    value <- gsub(",\\s*", "; ", value)
    value <- gsub(";+", ";", value)
  }

  if (!field %in% names(target_df)) {
    target_df[[field]] <<- NA_character_
  }

  current <- target_df[[field]][[row_idx]]
  if (overwrite || is.null(current) || length(current) == 0 ||
    is.na(current) || !nzchar(trimws(as.character(current)))) {
    target_df[[field]][[row_idx]] <<- value
    inferred_fields <<- unique(c(inferred_fields, field))
  }
  invisible(NULL)
}

#' Aplica todos os campos de IA extraídos a um dataframe.
#' Modifica `target_df` e retorna o vetor de campos inferidos.
#'
#' @param ai Lista de campos extraídos pela IA.
#' @param target_df Dataframe alvo.
#' @param row_idx Índice da linha.
#' @param inferred_fields Vetor de campos inferidos (pass-by-reference via <<-).
apply_ai_fields_to_df <- function(ai, target_df, row_idx, inferred_fields) {
  fill_ai_field("titulo", ai$titulo_limpo, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("descricao_resumida", ai$resumo, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("palavras_chave", ai$palavras_chave, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("elegibilidade", ai$elegibilidade, target_df, row_idx, inferred_fields)
  fill_ai_field("area_tematica", ai$area_tematica, target_df, row_idx, inferred_fields)
  fill_ai_field("tipo_oportunidade", ai$tipo_oportunidade, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("status_oportunidade", ai$status_oportunidade, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("idioma", ai$idioma, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("data_limite", ai$data_limite, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("data_publicacao", ai$data_publicacao, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("observacoes", ai$observacoes, target_df, row_idx, inferred_fields)
  fill_ai_field("modalidade", ai$modalidade, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("publico_alvo", ai$publico_alvo, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("nivel_academico", ai$nivel_academico, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("data_abertura", ai$data_abertura, overwrite = TRUE, target_df, row_idx, inferred_fields)
  fill_ai_field("data_encerramento", ai$data_encerramento, overwrite = TRUE, target_df, row_idx, inferred_fields)

  # valor_financiado e moeda (tipos especiais)
  ai_val <- if (!is.null(ai$valor_financiado) && !is.na(ai$valor_financiado)) as.numeric(ai$valor_financiado[[1]]) else NA_real_
  ai_curr <- if (!is.null(ai$moeda) && !is.na(ai$moeda) && nzchar(trimws(ai$moeda[[1]]))) as.character(ai$moeda[[1]]) else NA_character_

  if (!identical(target_df$valor_financiado[[row_idx]], ai_val)) {
    target_df$valor_financiado[[row_idx]] <<- ai_val
    inferred_fields <<- unique(c(inferred_fields, "valor_financiado"))
  }
  if (!identical(target_df$moeda[[row_idx]], ai_curr)) {
    target_df$moeda[[row_idx]] <<- ai_curr
    inferred_fields <<- unique(c(inferred_fields, "moeda"))
  }

  invisible(NULL)
}


# --- Rate Limiting por Domínio ---

extract_domain <- function(url) {
  parsed <- tryCatch(xml2::url_parse(url), error = function(e) NULL)
  if (is.null(parsed) || is.na(parsed$server)) {
    return("")
  }
  paste0(parsed$server, if (!is.na(parsed$port)) paste0(":", parsed$port))
}

DomainRateLimiter <- R6::R6Class("DomainRateLimiter",
  public = list(
    last_request = NULL,
    min_delay_same = NULL,
    min_delay_diff = NULL,
    last_domain = NULL,
    initialize = function(min_delay_same = 2.0, min_delay_diff = 0.5) {
      self$last_request <- new.env(parent = emptyenv())
      self$min_delay_same <- min_delay_same
      self$min_delay_diff <- min_delay_diff
      self$last_domain <- ""
    },
    wait_if_needed = function(url) {
      domain <- extract_domain(url)
      if (!nzchar(domain)) {
        return(invisible(NULL))
      }

      now <- as.numeric(Sys.time())
      last <- now
      if (exists(domain, envir = self$last_request, inherits = FALSE)) {
        last <- get(domain, envir = self$last_request, inherits = FALSE)
      }

      delay <- if (identical(domain, self$last_domain)) self$min_delay_same else self$min_delay_diff
      elapsed <- now - last
      if (elapsed < delay) {
        Sys.sleep(delay - elapsed)
      }

      assign(domain, as.numeric(Sys.time()), envir = self$last_request)
      self$last_domain <- domain
      invisible(NULL)
    }
  )
)

.scrape_rate_limiter <- DomainRateLimiter$new(
  min_delay_same = as.numeric(Sys.getenv("SCRAPE_DOMAIN_DELAY", "2.0")),
  min_delay_diff = as.numeric(Sys.getenv("SCRAPE_DIFF_DELAY", "0.5"))
)

is_plone_search_url <- function(url, current_url = NULL) {
  if (is.null(url) || !nzchar(url)) return(FALSE)
  u <- tolower(url)
  if (grepl("@@search", u, fixed = TRUE)) return(TRUE)
  if (grepl("/search\\?|/\\?q=|SearchableText=", u)) return(TRUE)
  if (!is.null(current_url) && nzchar(current_url)) {
    cu <- tolower(current_url)
    base_current <- sub("\\?.*", "", cu)
    base_target <- sub("\\?.*", "", u)
    if (identical(base_current, base_target)) return(FALSE)
  }
  FALSE
}

extract_inscricoes_dates <- function(text) {
  txt <- text %||% ""
  pattern <- "inscri[çc][õo]es?\\s*:\\s*(\\d{1,2}/\\d{1,2}/\\d{4})\\s*a\\s*(\\d{1,2}/\\d{1,2}/\\d{4})"
  m <- regmatches(txt, regexec(pattern, txt, ignore.case = TRUE))[[1]]
  if (length(m) == 3) {
    list(
      data_abertura = as.character(parse_date_safe(m[2])),
      data_limite = as.character(parse_date_safe(m[3]))
    )
  } else {
    list(data_abertura = NA_character_, data_limite = NA_character_)
  }
}
