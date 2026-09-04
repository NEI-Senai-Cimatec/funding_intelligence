build_search_text <- function(df, text_cols = c(
  "titulo", "subtitulo", "descricao_resumida", "descricao_completa",
  "palavras_chave", "area_tematica", "elegibilidade"
)) {
  cols <- intersect(text_cols, names(df))
  if (length(cols) == 0L || nrow(df) == 0L) {
    return(rep("", nrow(df)))
  }
  apply(df[, cols, drop = FALSE], 1, function(row) {
    normalize_text(paste(row, collapse = " "))
  })
}

insert_implicit_and <- function(tokens) {
  if (length(tokens) <= 1L) return(tokens)

  is_term <- function(tok) !(tok %in% c("AND", "OR", "NOT", "(", ")"))
  out <- character()

  for (i in seq_along(tokens)) {
    out <- c(out, tokens[i])
    if (i == length(tokens)) next

    cur <- tokens[i]
    nxt <- tokens[i + 1L]
    needs_and <- (is_term(cur) || identical(cur, ")")) &&
      (is_term(nxt) || nxt %in% c("(", "NOT"))

    if (isTRUE(needs_and)) out <- c(out, "AND")
  }

  out
}

tokenize_boolean_query <- function(query) {
  query <- stringr::str_squish(query %||% "")
  if (!nzchar(query)) return(character())

  pattern <- '"[^"]+"|\\(|\\)|\\bAND\\b|\\bOR\\b|\\bNOT\\b|[^[:space:]()]+'
  tokens <- stringr::str_extract_all(query, stringr::regex(pattern, ignore_case = TRUE))[[1]]
  if (length(tokens) == 0L) return(character())

  tokens <- vapply(tokens, function(tok) {
    up <- toupper(tok)
    if (up %in% c("AND", "OR", "NOT")) up else tok
  }, character(1))

  insert_implicit_and(tokens)
}

regex_escape <- function(x) {
  x <- x %||% ""
  x <- as.character(x)
  specials <- c("\\", ".", "|", "(", ")", "[", "]", "{", "}", "^", "$", "*", "+", "?")
  for (ch in specials) {
    x <- gsub(ch, paste0("\\", ch), x, fixed = TRUE)
  }
  x
}

term_to_pattern <- function(term) {
  term <- term %||% ""
  is_phrase <- grepl('^".*"$', term)
  raw_term <- gsub('^"|"$', "", term)
  raw_term <- normalize_text(raw_term)
  if (!nzchar(raw_term)) return("(?!)")

  parts <- strsplit(raw_term, "*", fixed = TRUE)[[1]]
  parts <- vapply(parts, regex_escape, character(1))
  pattern_body <- paste(parts, collapse = ".*")

  if (is_phrase || grepl("\\s", raw_term, perl = TRUE)) {
    pattern_body
  } else {
    paste0("\\b", pattern_body, "\\b")
  }
}

parse_boolean_query <- function(query) {
  tokens <- tokenize_boolean_query(query)
  if (length(tokens) == 0L) return(NULL)

  if (!any(tokens %in% c("AND", "OR", "NOT", "(", ")"))) {
    return(list(
      type = "OR",
      children = lapply(tokens, function(x) list(type = "TERM", value = x))
    ))
  }

  pos <- 1L

  current_token <- function() {
    if (pos <= length(tokens)) tokens[[pos]] else NA_character_
  }

  consume <- function(expected = NULL) {
    tok <- current_token()
    if (!is.null(expected) && !identical(tok, expected)) {
      stop(
        sprintf("Token inesperado: esperado '%s', recebido '%s'", expected, tok),
        call. = FALSE
      )
    }
    pos <<- pos + 1L
    tok
  }

  parse_expression <- parse_term <- parse_factor <- parse_primary <- NULL

  parse_expression <- function() {
    node <- parse_term()
    while (identical(current_token(), "OR")) {
      consume("OR")
      node <- list(type = "OR", children = list(node, parse_term()))
    }
    node
  }

  parse_term <- function() {
    node <- parse_factor()
    while (identical(current_token(), "AND")) {
      consume("AND")
      node <- list(type = "AND", children = list(node, parse_factor()))
    }
    node
  }

  parse_factor <- function() {
    if (identical(current_token(), "NOT")) {
      consume("NOT")
      return(list(type = "NOT", child = parse_factor()))
    }
    parse_primary()
  }

  parse_primary <- function() {
    tok <- current_token()

    if (identical(tok, "(")) {
      consume("(")
      node <- parse_expression()
      consume(")")
      return(node)
    }

    if (is.na(tok)) stop("Consulta booleana incompleta.", call. = FALSE)

    consume()
    list(type = "TERM", value = tok)
  }

  ast <- parse_expression()
  if (pos <= length(tokens)) {
    stop("Consulta booleana inválida: tokens remanescentes.", call. = FALSE)
  }
  ast
}

evaluate_boolean_ast <- function(ast, text_value) {
  if (is.null(ast)) return(TRUE)
  text_value <- normalize_text(text_value)

  switch(
    ast$type,
    TERM = grepl(term_to_pattern(ast$value), text_value, ignore.case = TRUE, perl = TRUE),
    AND = all(vapply(ast$children, evaluate_boolean_ast, logical(1), text_value = text_value)),
    OR = any(vapply(ast$children, evaluate_boolean_ast, logical(1), text_value = text_value)),
    NOT = !evaluate_boolean_ast(ast$child, text_value = text_value),
    TRUE
  )
}

extract_terms_from_ast <- function(ast, positive_only = TRUE) {
  if (is.null(ast)) return(character())

  if (identical(ast$type, "TERM")) {
    return(gsub('^"|"$', "", ast$value))
  }

  if (identical(ast$type, "NOT")) {
    if (isTRUE(positive_only)) return(character())
    return(extract_terms_from_ast(ast$child, positive_only = FALSE))
  }

  if (!is.null(ast$children)) {
    return(unique(unlist(lapply(ast$children, extract_terms_from_ast, positive_only = positive_only))))
  }

  character()
}

extract_query_terms <- function(query) {
  ast <- tryCatch(parse_boolean_query(query), error = function(e) NULL)
  if (is.null(ast)) return(character())
  unique(extract_terms_from_ast(ast, positive_only = TRUE))
}

apply_boolean_search <- function(df, query, text_cols = c(
  "titulo", "subtitulo", "descricao_resumida", "descricao_completa",
  "palavras_chave", "area_tematica", "elegibilidade"
)) {
  if (!nzchar(stringr::str_squish(query %||% ""))) {
    df$matched_terms <- ""
    return(df)
  }

  ast <- parse_boolean_query(query)
  text_index <- build_search_text(df, text_cols = text_cols)
  match_mask <- vapply(text_index, function(txt) evaluate_boolean_ast(ast, txt), logical(1))
  out <- df[match_mask, , drop = FALSE]

  positive_terms <- unique(normalize_text(extract_terms_from_ast(ast, positive_only = TRUE)))
  positive_terms <- positive_terms[nzchar(positive_terms)]

  if (nrow(out) > 0L) {
    out_text_index <- build_search_text(out, text_cols = text_cols)
    out$matched_terms <- vapply(out_text_index, function(txt) {
      if (length(positive_terms) == 0L) return("")
      hits <- positive_terms[
        vapply(positive_terms, function(term) {
          grepl(term_to_pattern(term), txt, ignore.case = TRUE, perl = TRUE)
        }, logical(1))
      ]
      paste(unique(hits), collapse = "; ")
    }, character(1))
  } else {
    out$matched_terms <- character()
  }

  out
}

build_advanced_query <- function(required_terms = "", optional_terms = "", exclude_terms = "", exact_phrase = "") {
  req <- safe_split(required_terms)
  opt <- safe_split(optional_terms)
  exc <- safe_split(exclude_terms)
  exa <- safe_split(exact_phrase)

  chunks <- character()
  if (length(req) > 0L) chunks <- c(chunks, paste(req, collapse = " AND "))
  if (length(opt) > 0L) chunks <- c(chunks, paste0("(", paste(opt, collapse = " OR "), ")"))
  if (length(exa) > 0L) chunks <- c(chunks, paste(sprintf('"%s"', exa), collapse = " AND "))
  if (length(exc) > 0L) chunks <- c(chunks, paste(paste0("NOT ", exc), collapse = " AND "))

  stringr::str_squish(paste(chunks, collapse = " AND "))
}

apply_structured_filters <- function(df, filters = list()) {
  out <- df
  if (!nrow(out)) return(out)

  if (!is.null(filters$idioma) && nzchar(filters$idioma) && filters$idioma != "Todos") {
    out <- dplyr::filter(out, idioma == filters$idioma)
  }
  if (!is.null(filters$pais) && length(filters$pais) > 0L) {
    out <- dplyr::filter(out, pais_origem %in% filters$pais)
  }
  if (!is.null(filters$tipo) && length(filters$tipo) > 0L) {
    out <- dplyr::filter(out, tipo_oportunidade %in% filters$tipo)
  }
  if (!is.null(filters$area_tematica) && length(filters$area_tematica) > 0L) {
    out <- dplyr::filter(out, area_tematica %in% filters$area_tematica)
  }
  if (!is.null(filters$financiador) && length(filters$financiador) > 0L) {
    out <- dplyr::filter(out, entidade %in% filters$financiador)
  }
  if (!is.null(filters$elegibilidade) && nzchar(filters$elegibilidade)) {
    out <- dplyr::filter(out, stringr::str_detect(normalize_text(elegibilidade), normalize_text(filters$elegibilidade)))
  }
  if (!is.null(filters$valor_range) && length(filters$valor_range) == 2L) {
    out <- dplyr::filter(
      out,
      dplyr::coalesce(valor_financiado, 0) >= filters$valor_range[1],
      dplyr::coalesce(valor_financiado, 0) <= filters$valor_range[2]
    )
  }
  if (!is.null(filters$deadline_range) && length(filters$deadline_range) == 2L) {
    start <- parse_date_safe(filters$deadline_range[1])
    end <- parse_date_safe(filters$deadline_range[2])
    dates <- parse_date_safe(out$data_limite)
    out <- out[is.na(dates) | (dates >= start & dates <= end), , drop = FALSE]
  }

  out
}

simple_keyword_frequency <- function(df, top_n = 20) {
  if (nrow(df) == 0L) return(tibble::tibble(term = character(), n = integer()))

  terms <- safe_split(df$palavras_chave)
  if (length(terms) == 0L) return(tibble::tibble(term = character(), n = integer()))

  tibble::tibble(term = normalize_text(terms)) |>
    dplyr::filter(nzchar(term)) |>
    dplyr::count(term, sort = TRUE) |>
    dplyr::slice_head(n = top_n)
}

# ─── Trim inteligente para IA (corrige BUG-09) ────────────────────────────────
# Prazos e valores ficam com frequência no FINAL de PDFs longos. Em vez de
# truncar a cauda, mantemos: cabeçalho (4k) + janelas ±120 chars em torno de
# keywords de prazo/valor + cauda (2k), tudo limitado a max_chars (12k).

trim_for_ai <- function(text, max_chars = NULL, window = 120L, header_chars = 4000L, tail_chars = 2000L) {
  if (is.null(max_chars)) {
    max_chars <- as.numeric(Sys.getenv("AI_MAX_CHARS", "12000"))
    if (is.na(max_chars) || max_chars <= 0) max_chars <- 12000
  }
  text <- normalize_ws(text %||% "")
  if (nchar(text) <= max_chars) {
    return(text)
  }

  keywords <- c("prazo", "deadline", "submiss", "inscri", "valor", "orçamento", "orcamento", "budget", "recurso")
  windows <- character()
  for (kw in keywords) {
    matches <- gregexpr(paste0(kw, ".{0,", window, "}"), text, ignore.case = TRUE, perl = TRUE)[[1]]
    if (length(matches) == 0L || is.na(matches[[1]])) next
    for (pos in matches) {
      start <- max(1L, pos - window)
      end <- min(nchar(text), pos + window)
      windows <- c(windows, substr(text, start, end))
    }
  }

  header <- substr(text, 1, header_chars)
  tail <- substr(text, max(1L, nchar(text) - tail_chars), nchar(text))
  result <- paste(c(header, windows, tail), collapse = "\n\n---\n\n")

  if (nchar(result) > max_chars) {
    result <- substr(result, 1, max_chars)
  }
  result
}
