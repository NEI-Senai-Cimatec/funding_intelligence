log_progress <- function(detail, phase = "Scraping") {
  try({
    log_line <- sprintf("[%s] [%s] %s", format(Sys.time(), "%H:%M:%S"), phase, detail)
    cat(log_line, "\n", file = file.path(getwd(), "logs", "collection_modal_log.txt"), append = TRUE)
  }, silent = TRUE)
}

detect_next_page <- function(html, current_url) {
  nodes <- rvest::html_nodes(html, "a")
  if (length(nodes) == 0) return(NA_character_)
  
  hrefs <- rvest::html_attr(nodes, "href")
  texts <- tolower(rvest::html_text(nodes, trim = TRUE))
  rels <- tolower(rvest::html_attr(nodes, "rel"))
  
  valid <- !is.na(hrefs) & nzchar(hrefs)
  if (!any(valid)) return(NA_character_)
  
  hrefs <- hrefs[valid]
  texts <- texts[valid]
  rels <- rels[valid]
  
  next_idx <- which(rels == "next")
  if (length(next_idx) > 0) {
    return(resolve_url(current_url, hrefs[[next_idx[1]]]))
  }
  
  match_idx <- which(grepl("pr[oó]xim[oa]|next|\\bsecund\\b|\\bseg\\b|\\bdaqui\\b|>", texts))
  if (length(match_idx) > 0) {
    return(resolve_url(current_url, hrefs[[match_idx[1]]]))
  }
  
  NA_character_
}

source_dispatch <- function(source_row, max_pages = 5, max_records = 50, use_ai = FALSE, log_path = NULL) {
  sid <- source_row$id_fonte[[1]]
  if (sid %in% c("facepe", "fapesb")) {
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = source_row$url_oportunidades[[1]]))
  }
  if (identical(sid, "fapes_es")) {
    return(collect_fapes_es(source_row, max_pages, max_records, use_ai, log_path))
  }
  if (identical(sid, "confap")) {
    return(collect_confap(source_row, max_pages, max_records, use_ai, log_path))
  }
  if (identical(sid, "fapesc")) {
    return(collect_fapesc(source_row, max_pages, max_records, use_ai, log_path))
  }
  if (identical(sid, "eureka")) {
    return(collect_eureka(source_row, max_pages, max_records, use_ai, log_path))
  }
  collect_generic_official(source_row, max_pages, max_records, use_ai, log_path)
}

safe_request_page_playwright <- function(url, log_path = NULL) {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    return(list(ok = FALSE))
  }
  py_playwright <- try(reticulate::import("playwright.sync_api", delay_load = TRUE), silent = TRUE)
  if (inherits(py_playwright, "try-error")) {
    return(list(ok = FALSE))
  }
  res <- tryCatch({
    reticulate::py_run_string("
def run_playwright_stealth(url):
    from playwright.sync_api import sync_playwright
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                viewport={'width': 1920, 'height': 1080},
                locale='pt-BR',
                timezone_id='America/Sao_Paulo'
            )
            page = context.new_page()
            page.add_init_script(\"\"\"
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                Object.defineProperty(navigator, 'languages', { get: () => ['pt-BR', 'pt', 'en-US', 'en'] });
                Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
                window.chrome = { runtime: {} };
            \"\"\")
            page.goto(url, wait_until='networkidle', timeout=45000)
            content = page.content()
            browser.close()
            return {'content': content, 'ok': True}
    except Exception as e:
        return {'content': str(e), 'ok': False}
")
    playwright_run <- reticulate::py$run_playwright_stealth(url)
    if (isTRUE(playwright_run$ok)) {
      html <- xml2::read_html(playwright_run$content)
      list(url = url, html = html, text = playwright_run$content, ok = TRUE, method = "playwright")
    } else {
      if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Playwright falhou para %s: %s", url, playwright_run$content))
      list(ok = FALSE)
    }
  }, error = function(e) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Erro de execucao Playwright: %s", e$message))
    list(ok = FALSE)
  })
  res
}

safe_request_page <- function(url, log_path = NULL, use_browser_fallback = TRUE) {
  # 1. Tentar httr2 (metodo rapido)
  req <- httr2::request(url) |>
    httr2::req_user_agent("FundingIntelligenceHub/1.1 (+local-shiny-app)") |>
    httr2::req_headers(
      `Accept-Language` = "pt-BR,pt;q=0.9,en;q=0.8",
      `Accept` = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    ) |>
    httr2::req_timeout(45) |>
    httr2::req_retry(max_tries = 2)

  resp <- try(httr2::req_perform(req), silent = TRUE)
  if (!inherits(resp, "try-error")) {
    txt <- try(httr2::resp_body_string(resp), silent = TRUE)
    txt_ok <- !inherits(txt, "try-error") && length(txt) == 1 && !is.na(txt) && nzchar(txt)
    if (txt_ok) {
      html <- try(xml2::read_html(txt), silent = TRUE)
      if (!inherits(html, "try-error")) {
        # Verifica se o conteudo contem sinal obvio de captcha/bloqueio por CDN antes de aceitar
        has_block_signal <- grepl("attention required! \\| cloudflare|cf-challenge|ray id:|checking your browser before accessing|security challenge|access denied", tolower(txt))
        if (!has_block_signal) {
          return(list(url = url, html = html, text = txt, ok = TRUE, method = "httr2"))
        } else {
          if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("Bloqueio de CDN/CAPTCHA detectado via httr2 para %s. Acionando fallbacks...", url))
        }
      }
    }
  }

  # 2. Tentar Playwright (se habilitado/instalado via reticulate)
  if (isTRUE(use_browser_fallback)) {
    pw_res <- safe_request_page_playwright(url, log_path = log_path)
    if (isTRUE(pw_res$ok)) return(pw_res)
  }

  # 3. Tentar Chromote Stealth (R nativo)
  if (isTRUE(use_browser_fallback) && requireNamespace("chromote", quietly = TRUE)) {
    b <- try(chromote::ChromoteSession$new(), silent = TRUE)
    if (!inherits(b, "try-error")) {
      on.exit(try(b$close(), silent = TRUE), add = TRUE)
      
      js_stealth_code <- paste(
        "Object.defineProperty(navigator, 'webdriver', { get: () => undefined });",
        "Object.defineProperty(navigator, 'languages', { get: () => ['pt-BR', 'pt', 'en-US', 'en'] });",
        "Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });",
        "window.chrome = { runtime: {} };",
        "const originalQuery = window.navigator.permissions.query;",
        "window.navigator.permissions.query = (parameters) =>",
        "  parameters.name === 'notifications' ?",
        "    Promise.resolve({ state: Notification.permission }) :",
        "    originalQuery(parameters);",
        sep = "\n"
      )
      
      try(b$Page$addScriptToEvaluateOnNewDocument(source = js_stealth_code), silent = TRUE)
      try(b$Network$setUserAgentOverride(
        userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      ), silent = TRUE)
      
      try(b$Page$navigate(url), silent = TRUE)
      Sys.sleep(5)
      html_txt <- try(b$Runtime$evaluate("document.documentElement.outerHTML")$result$value, silent = TRUE)
      txt_ok <- !inherits(html_txt, "try-error") && length(html_txt) == 1 && !is.null(html_txt) && !is.na(html_txt) && nzchar(html_txt)
      if (txt_ok) {
        html <- try(xml2::read_html(html_txt), silent = TRUE)
        if (!inherits(html, "try-error")) {
          return(list(url = url, html = html, text = html_txt, ok = TRUE, method = "chromote_stealth"))
        }
      }
    }
  }

  if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Falha ao requisitar %s apos tentar todos os metodos (httr2, Playwright, Chromote Stealth)", url))
  list(url = url, html = NULL, text = NA_character_, ok = FALSE, method = NA_character_)
}


text_has_funding_signal <- function(text) {
  vals <- as.character(text %||% NA_character_)
  vapply(vals, function(one) {
    if (length(one) == 0 || is.na(one)) return(FALSE)
    txt <- normalize_text(substr(one, 1, 5000))
    if (!nzchar(txt)) return(FALSE)
    grepl(
      paste(
        c(
          funding_lexicon(),
          "deadline", "eligibility", "submission", "proposal", "applications", "notice",
          "calls?", "opportunit", "research support", "financial support", "mobility",
          "apoio", "inscricoes", "inscrições", "prazo", "seleção", "selecoes", "seleções"
        ),
        collapse = "|"
      ),
      txt,
      ignore.case = TRUE,
      perl = TRUE
    )
  }, logical(1))
}

extract_meta_title <- function(html) {
  if (is.null(html)) return(NA_character_)
  h1 <- try(rvest::html_element(html, "h1"), silent = TRUE)
  title_1 <- if (!inherits(h1, "try-error")) safe_html_text(h1) else NA_character_
  if (!is.na(title_1) && nzchar(title_1)) return(title_1)

  og <- try(rvest::html_element(html, "meta[property='og:title']"), silent = TRUE)
  title_og <- if (!inherits(og, "try-error")) safe_attr(og, "content") else NA_character_
  if (!is.na(title_og) && nzchar(title_og)) return(normalize_ws(title_og))

  ttl <- try(rvest::html_element(html, "title"), silent = TRUE)
  title_tag <- if (!inherits(ttl, "try-error")) safe_html_text(ttl) else NA_character_
  if (!is.na(title_tag) && nzchar(title_tag)) return(title_tag)
  NA_character_
}

extract_page_summary <- function(html, max_chars = 1200) {
  if (is.null(html)) return(NA_character_)
  nodes <- try(rvest::html_elements(html, "main p, article p, .content p, .entry-content p, .post-content p, body p"), silent = TRUE)
  if (inherits(nodes, "try-error") || length(nodes) == 0) {
    body <- try(rvest::html_element(html, "body"), silent = TRUE)
    txt <- if (!inherits(body, "try-error")) safe_html_text(body) else NA_character_
    if (is.na(txt) || !nzchar(txt)) return(NA_character_)
    return(stringr::str_squish(stringr::str_sub(txt, 1, max_chars)))
  }
  txt <- vapply(nodes, safe_html_text, character(1))
  txt <- txt[!is.na(txt) & nzchar(txt)]
  if (length(txt) == 0) return(NA_character_)
  stringr::str_squish(stringr::str_sub(paste(txt, collapse = " "), 1, max_chars))
}

extract_listing_candidates <- function(html, base_url, source_row) {
  if (is.null(html)) return(tibble::tibble())

  # 1) Candidatos por blocos de conteúdo
  block_sel <- paste(
    c(
      "article", ".card", ".cards-item", ".views-row", ".view-content .views-row", ".resultado",
      ".result", ".results-item", ".entry", ".post", ".item", ".media", ".tile", ".callout",
      ".news-item", ".list-item", ".node", ".content-item", "li", "tr", "section"
    ),
    collapse = ", "
  )
  blocks <- try(rvest::html_elements(html, block_sel), silent = TRUE)
  block_df <- tibble::tibble()

  if (!inherits(blocks, "try-error") && length(blocks) > 0) {
    block_df <- purrr::map_dfr(seq_along(blocks), function(i) {
      node <- blocks[[i]]
      raw_txt <- safe_html_text(node)
      if (is.na(raw_txt) || nchar(raw_txt) < 40) return(tibble::tibble())

      anchors <- try(rvest::html_elements(node, "a[href]"), silent = TRUE)
      if (inherits(anchors, "try-error") || length(anchors) == 0) return(tibble::tibble())

      hrefs <- rvest::html_attr(anchors, "href")
      hrefs[is.na(hrefs)] <- ""
      abs_urls <- vapply(hrefs, function(h) resolve_url(base_url, h), character(1))
      anchor_txt <- vapply(anchors, safe_html_text, character(1))

      heading_nodes <- try(rvest::html_elements(node, "h1, h2, h3, h4, strong, .title, .titulo, .headline"), silent = TRUE)
      heading_txt <- if (!inherits(heading_nodes, "try-error") && length(heading_nodes) > 0) {
        vapply(heading_nodes, safe_html_text, character(1))
      } else {
        character(0)
      }

      pdf_idx <- grepl("\\.pdf($|\\?)", abs_urls, ignore.case = TRUE)
      detail_idx <- !pdf_idx & !is.na(abs_urls) & nzchar(abs_urls)
      detail_urls <- unique(abs_urls[detail_idx])
      pdf_urls <- unique(abs_urls[pdf_idx])

      title <- pick_first_nonempty(
        heading_txt[!is.na(heading_txt) & nzchar(heading_txt)],
        anchor_txt[!is.na(anchor_txt) & nzchar(anchor_txt)],
        stringr::str_sub(raw_txt, 1, 140)
      )
      summary <- stringr::str_squish(stringr::str_sub(raw_txt, 1, 700))
      keep <- text_has_funding_signal(c(title, raw_txt))[[1]] ||
        length(pdf_urls) > 0 ||
        any(grepl("edital|grant|funding|call|bolsa|auxilio|subvenc|fomento|apply|proposal", normalize_text(detail_urls), perl = TRUE))
      if (!isTRUE(keep)) return(tibble::tibble())

      tibble::tibble(
        candidate_title = null_if_empty(title),
        candidate_summary = null_if_empty(summary),
        detail_url = pick_first_nonempty(detail_urls),
        pdf_url = pick_first_nonempty(pdf_urls),
        source_text = null_if_empty(raw_txt)
      )
    })
  }

  # 2) Candidatos por links diretamente detectados
  anchor_df <- try(extract_candidate_links(html, base_url, source_row$id_fonte[[1]]), silent = TRUE)
  if (inherits(anchor_df, "try-error") || is.null(anchor_df) || nrow(anchor_df) == 0) {
    anchor_df <- tibble::tibble()
  } else {
    anchor_df <- anchor_df |>
      dplyr::transmute(
        candidate_title = dplyr::coalesce(anchor_text, stringr::str_sub(container_text, 1, 140)),
        candidate_summary = container_text,
        detail_url = dplyr::if_else(is_pdf, NA_character_, href),
        pdf_url = dplyr::if_else(is_pdf, href, NA_character_),
        source_text = container_text
      )
  }

  out <- dplyr::bind_rows(block_df, anchor_df) |>
    dplyr::mutate(
      candidate_title = null_if_empty(candidate_title),
      candidate_summary = null_if_empty(candidate_summary),
      source_text = null_if_empty(source_text),
      detail_url = null_if_empty(detail_url),
      pdf_url = null_if_empty(pdf_url)
    ) |>
    dplyr::filter(!is.na(candidate_title) | !is.na(detail_url) | !is.na(pdf_url)) |>
    dplyr::mutate(canonical_url = dplyr::coalesce(detail_url, pdf_url, candidate_title)) |>
    dplyr::distinct(canonical_url, .keep_all = TRUE) |>
    dplyr::select(-canonical_url) |>
    dplyr::rename(title = candidate_title, summary = candidate_summary)

  if (nrow(out) == 0) {
    # Fallback: capturar todos os PDFs da página e transformá-los em registros candidatos.
    pdfs <- try(extract_pdf_links(html, base_url), silent = TRUE)
    if (!inherits(pdfs, "try-error") && length(pdfs) > 0) {
      out <- tibble::tibble(
        title = basename(pdfs),
        summary = extract_meta_title(html),
        detail_url = NA_character_,
        pdf_url = pdfs,
        source_text = extract_page_summary(html)
      ) |>
        dplyr::distinct(pdf_url, .keep_all = TRUE)
    }
  }

  out
}

extract_detail_bundle <- function(detail_url = NA_character_, page_url = NA_character_, pdf_url = NA_character_, log_path = NULL) {
  out <- list(
    detail_title = NA_character_,
    detail_subtitle = NA_character_,
    detail_summary = NA_character_,
    full_text = NA_character_,
    pdf_url = pdf_url
  )

  if (!is.na(detail_url) && nzchar(detail_url)) {
    det <- safe_request_page(detail_url, log_path = log_path)
    if (isTRUE(det$ok) && !is.null(det$html)) {
      out$detail_title <- extract_meta_title(det$html)

      subtitle_node <- try(rvest::html_element(det$html, "h2, .subtitle, .subtitulo"), silent = TRUE)
      out$detail_subtitle <- if (!inherits(subtitle_node, "try-error")) safe_html_text(subtitle_node) else NA_character_

      para_nodes <- try(rvest::html_elements(det$html, "main p, article p, .content p, .entry-content p, .post-content p, body p"), silent = TRUE)
      if (!inherits(para_nodes, "try-error") && length(para_nodes) > 0) {
        para_txt <- vapply(para_nodes, safe_html_text, character(1))
        para_txt <- para_txt[!is.na(para_txt) & nzchar(para_txt)]
        if (length(para_txt) > 0) {
          out$detail_summary <- stringr::str_squish(stringr::str_sub(paste(utils::head(para_txt, 4), collapse = " "), 1, 900))
          out$full_text <- stringr::str_squish(stringr::str_sub(paste(para_txt, collapse = "\n"), 1, 20000))
        }
      }

      if (is.na(out$pdf_url) || !nzchar(out$pdf_url)) {
        det_pdfs <- try(extract_pdf_links(det$html, detail_url), silent = TRUE)
        if (!inherits(det_pdfs, "try-error") && length(det_pdfs) > 0) {
          out$pdf_url <- det_pdfs[[1]]
        }
      }
    }
  }

  if (!is.na(out$pdf_url) && nzchar(out$pdf_url)) {
    pdf_txt <- extract_text_from_pdf(out$pdf_url, log_path = log_path)
    if (!is.na(pdf_txt) && nzchar(pdf_txt)) {
      out$full_text <- collapse_non_empty(out$full_text, stringr::str_sub(pdf_txt, 1, 20000), sep = "\n")
      if (is.na(out$detail_summary) || !nzchar(out$detail_summary)) {
        out$detail_summary <- stringr::str_squish(stringr::str_sub(pdf_txt, 1, 900))
      }
    }
  }

  out
}

extract_text_from_pdf <- function(pdf_url, log_path = NULL) {
  tf <- tempfile(fileext = ".pdf")
  ok <- try({
    req <- httr2::request(pdf_url) |>
      httr2::req_user_agent("FundingIntelligenceHub/1.1 (+local-shiny-app)") |>
      httr2::req_timeout(60)
    httr2::req_perform(req, path = tf)
  }, silent = TRUE)
  if (inherits(ok, "try-error") || !file.exists(tf)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Falha ao baixar PDF %s", pdf_url))
    return(NA_character_)
  }
  txt <- try(pdftools::pdf_text(tf), silent = TRUE)
  unlink(tf)
  if (inherits(txt, "try-error")) return(NA_character_)
  normalize_ws(paste(txt, collapse = "\n"))
}


extract_core_record <- function(source_row, input_title = NA_character_, input_subtitle = NA_character_, input_summary = NA_character_, input_full_text = NA_character_, page_url = NA_character_, detail_url = NA_character_, pdf_url = NA_character_, page_no = 1L) {
  source_id <- source_row$id_fonte[[1]]
  entity_name <- source_row$sigla[[1]] %||% source_row$nome_fonte[[1]]

  v_title <- null_if_empty(input_title)
  v_subtitle <- null_if_empty(input_subtitle)
  v_summary <- null_if_empty(input_summary)
  v_full_text <- null_if_empty(input_full_text)

  raw_text <- collapse_non_empty(v_title, v_subtitle, v_summary, v_full_text, sep = "\n")
  dates <- extract_dates_from_text(raw_text)
  deadline <- if (length(dates) > 0 && any(!is.na(dates))) suppressWarnings(max(dates, na.rm = TRUE)) else as.Date(NA)
  pub_date <- if (length(dates) > 0 && any(!is.na(dates))) suppressWarnings(min(dates, na.rm = TRUE)) else as.Date(NA)
  money <- parse_money_text(raw_text)
  main_url <- pick_first_nonempty(detail_url, pdf_url, page_url, source_row$url_oportunidades[[1]])

  if (is.na(v_title)) {
    v_title <- paste("Oportunidade -", entity_name, format(Sys.Date(), "%d/%m/%Y"))
  }

  rec <- tibble::tibble(
    id_registro = NA_character_,
    entidade = as.character(entity_name),
    pais_origem = normalize_country(source_row$pais[[1]]),
    titulo = as.character(v_title),
    subtitulo = as.character(v_subtitle),
    descricao_resumida = as.character(v_summary),
    descricao_completa = as.character(v_full_text),
    tipo_oportunidade = infer_type_from_text(raw_text),
    modalidade = NA_character_,
    area_tematica = NA_character_,
    palavras_chave = extract_keywords_simple(raw_text),
    elegibilidade = NA_character_,
    publico_alvo = NA_character_,
    nivel_academico = NA_character_,
    instituicao_financiadora = as.character(source_row$nome_fonte[[1]]),
    valor_financiado = money$value,
    moeda = money$currency,
    data_publicacao = as.character(pub_date),
    data_abertura = NA_character_,
    data_limite = as.character(deadline),
    data_encerramento = NA_character_,
    status_oportunidade = classify_status(deadline = deadline, text = raw_text)[[1]],
    link_origem = as.character(pick_first_nonempty(page_url, source_row$url_oportunidades[[1]])),
    link_detalhe = as.character(null_if_empty(detail_url)),
    link_documento_pdf = as.character(null_if_empty(pdf_url)),
    idioma = as.character(pick_first_nonempty(source_row$idioma[[1]], infer_language_simple(raw_text)[[1]])),
    localidade = as.character(source_row$pais[[1]]),
    observacoes = NA_character_,
    texto_bruto = as.character(null_if_empty(raw_text)),
    pagina_coletada = as.integer(page_no),
    fonte_oficial = as.character(source_id),
    data_hora_coleta = as.character(Sys.time()),
    hash_deduplicacao = NA_character_,
    campos_inferidos_ia = ""
  )

  hash_val <- digest::digest(paste0(rec$titulo, rec$link_origem), algo = "xxhash64")
  rec$hash_deduplicacao <- hash_val
  rec$id_registro <- paste0(source_id, "_", substr(hash_val, 1, 16))
  rec
}


enrich_record_with_ai <- function(record, log_path = NULL) {
  log_progress(sprintf("Enriquecendo edital '%s' com IA...", record$titulo[[1]]), "IA")
  status_file <- file.path(getwd(), "logs", "collection_status.json")
  if (file.exists(status_file)) {
    try({
      status_data <- jsonlite::fromJSON(status_file, simplifyVector = FALSE)
      status_data$phase <- "IA"
      status_data$detail <- sprintf("Enriquecendo dados via IA para edital: %s", record$titulo[[1]])
      jsonlite::write_json(status_data, status_file, auto_unbox = TRUE)
    }, silent = TRUE)
  }
  text <- collapse_non_empty(record$titulo, record$descricao_resumida, record$descricao_completa, record$texto_bruto, sep = "\n")
  ai <- ai_extract_fields(
    text,
    current = as.list(record[1, c("titulo", "tipo_oportunidade", "status_oportunidade", "idioma")]),
    log_path = log_path
  )
  if (length(ai) == 0) return(record)

  inferred <- character()
  fill_field <- function(field, value) {
    if (is.null(value) || length(value) == 0) return(invisible(NULL))
    value <- as.character(value[[1]])
    if (is.na(value) || !nzchar(trimws(value))) return(invisible(NULL))
    current <- record[[field]][[1]]
    if (is.na(current) || !nzchar(trimws(as.character(current)))) {
      record[[field]] <<- value
      inferred <<- unique(c(inferred, field))
    }
    invisible(NULL)
  }

  fill_field("titulo", ai$titulo_limpo)
  fill_field("descricao_resumida", ai$resumo)
  fill_field("elegibilidade", ai$elegibilidade)
  fill_field("area_tematica", ai$area_tematica)
  fill_field("tipo_oportunidade", ai$tipo_oportunidade)
  fill_field("status_oportunidade", ai$status_oportunidade)
  fill_field("idioma", ai$idioma)
  fill_field("data_limite", ai$data_limite)
  fill_field("data_publicacao", ai$data_publicacao)
  fill_field("observacoes", ai$observacoes)
  record$campos_inferidos_ia <- paste(unique(inferred), collapse = "; ")
  record
}

dedupe_records <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(tibble::tibble())
  df |>
    dplyr::mutate(
      title_norm = normalize_text(titulo),
      date_norm = as.character(parse_date_safe(data_limite)),
      url_norm = dplyr::coalesce(link_detalhe, link_documento_pdf, link_origem),
      dedupe_key = dplyr::coalesce(hash_deduplicacao, make_hash(entidade, title_norm, url_norm, date_norm))
    ) |>
    dplyr::arrange(dplyr::desc(nchar(dplyr::coalesce(texto_bruto, "")))) |>
    dplyr::distinct(dedupe_key, .keep_all = TRUE) |>
    dplyr::select(-title_norm, -date_norm, -url_norm, -dedupe_key)
}

infer_area_from_text_one <- function(text) {
  txt <- normalize_text(text %||% "")
  dplyr::case_when(
    grepl("health|medical|saude|biomed", txt) ~ "Saúde",
    grepl("climate|clima|agricultur|bioeconom", txt) ~ "Mudanças Climáticas e Agricultura",
    grepl("hydrogen|biomethane|energy|energia|decarbon", txt) ~ "Transição Energética",
    grepl("innovation|inovacao|industrial|empresa|empreendedor", txt) ~ "Inovação e Indústria",
    grepl("culture|cultura", txt) ~ "Cultura",
    grepl("education|educacao|scholarship|mobility|intercambio", txt) ~ "Educação e Mobilidade",
    TRUE ~ "Multitemático"
  )
}

ensure_record_schema <- function(df) {
  schema_cols <- c(
    "id_registro", "entidade", "pais_origem", "titulo", "subtitulo", "descricao_resumida",
    "descricao_completa", "tipo_oportunidade", "modalidade", "area_tematica", "palavras_chave",
    "elegibilidade", "publico_alvo", "nivel_academico", "instituicao_financiadora",
    "valor_financiado", "moeda", "data_publicacao", "data_abertura", "data_limite",
    "data_encerramento", "status_oportunidade", "link_origem", "link_detalhe",
    "link_documento_pdf", "idioma", "localidade", "observacoes", "texto_bruto",
    "pagina_coletada", "fonte_oficial", "data_hora_coleta", "hash_deduplicacao", "campos_inferidos_ia"
  )
  if (is.null(df) || nrow(df) == 0) {
    out <- as.list(rep(NA_character_, length(schema_cols)))
    names(out) <- schema_cols
    out$valor_financiado <- numeric()
    out$pagina_coletada <- integer()
    return(tibble::as_tibble(out)[0, ])
  }
  missing_cols <- setdiff(schema_cols, names(df))
  if (length(missing_cols) > 0) {
    for (nm in missing_cols) df[[nm]] <- NA
  }
  tibble::as_tibble(df)[, schema_cols]
}

finalize_records <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(ensure_record_schema(tibble::tibble()))
  df <- ensure_record_schema(df)

  lang_guess <- infer_language_simple(df$texto_bruto)
  status_guess <- classify_status(df$data_limite, df$data_abertura, df$data_encerramento, df$texto_bruto)
  area_guess <- vapply(df$texto_bruto, infer_area_from_text_one, character(1))

  df |>
    dplyr::mutate(
      titulo = dplyr::coalesce(titulo, subtitulo, descricao_resumida, paste("Oportunidade", entidade)),
      idioma = dplyr::coalesce(idioma, lang_guess),
      status_oportunidade = dplyr::coalesce(status_oportunidade, status_guess),
      area_tematica = dplyr::coalesce(area_tematica, area_guess),
      valor_financiado = suppressWarnings(as.numeric(valor_financiado)),
      pais_origem = vapply(pais_origem, normalize_country, character(1)),
      hash_deduplicacao = dplyr::coalesce(hash_deduplicacao, make_hash(entidade, titulo, dplyr::coalesce(link_detalhe, link_documento_pdf, link_origem), data_limite)),
      id_registro = dplyr::coalesce(id_registro, paste0(fonte_oficial, "_", substr(hash_deduplicacao, 1, 16)))
    ) |>
    dedupe_records()
}

collect_listing_with_pagination <- function(source_row, first_url, max_pages = 5, max_records = 50, use_ai = FALSE, log_path = NULL, page_builder = NULL, follow_details = TRUE) {
  pages_seen <- character()
  current_url <- first_url
  page_no <- 1L
  all_records <- tibble::tibble()
  last_url <- first_url

  while (!is.na(current_url) && nzchar(current_url) && page_no <= max_pages && !(current_url %in% pages_seen)) {
    pages_seen <- c(pages_seen, current_url)
    last_url <- current_url
    pg <- safe_request_page(current_url, log_path = log_path)
    if (!isTRUE(pg$ok) || is.null(pg$html)) {
      if (page_no == 1L) {
        stop(sprintf("Erro ao carregar a pagina inicial: %s", current_url), call. = FALSE)
      }
      break
    }

    candidates <- extract_listing_candidates(pg$html, current_url, source_row)
    if (nrow(candidates) > 0) {
      remaining <- max_records - nrow(all_records)
      if (remaining <= 0) break
      if (nrow(candidates) > remaining) candidates <- candidates[seq_len(remaining), , drop = FALSE]

      page_records <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
        one <- candidates[i, , drop = FALSE]
        detail_bundle <- list(
          detail_title = NA_character_,
          detail_subtitle = NA_character_,
          detail_summary = one$summary[[1]],
          full_text = one$source_text[[1]],
          pdf_url = one$pdf_url[[1]]
        )

        if (isTRUE(follow_details) && !is.na(one$detail_url[[1]]) && nzchar(one$detail_url[[1]])) {
          detail_bundle <- extract_detail_bundle(
            detail_url = one$detail_url[[1]],
            page_url = current_url,
            pdf_url = one$pdf_url[[1]],
            log_path = log_path
          )
        } else if (!is.na(one$pdf_url[[1]]) && nzchar(one$pdf_url[[1]])) {
          detail_bundle <- extract_detail_bundle(
            detail_url = NA_character_,
            page_url = current_url,
            pdf_url = one$pdf_url[[1]],
            log_path = log_path
          )
        }

        rec <- extract_core_record(
          source_row = source_row,
          input_title = pick_first_nonempty(detail_bundle$detail_title, one$title[[1]]),
          input_subtitle = pick_first_nonempty(detail_bundle$detail_subtitle),
          input_summary = pick_first_nonempty(detail_bundle$detail_summary, one$summary[[1]]),
          input_full_text = pick_first_nonempty(detail_bundle$full_text, one$source_text[[1]]),
          page_url = current_url,
          detail_url = one$detail_url[[1]],
          pdf_url = pick_first_nonempty(detail_bundle$pdf_url, one$pdf_url[[1]]),
          page_no = page_no
        )

        if (isTRUE(use_ai)) rec <- enrich_record_with_ai(rec, log_path = log_path)
        rec
      })

      all_records <- dplyr::bind_rows(all_records, page_records)
      if (nrow(all_records) >= max_records) break
    }

    next_url <- if (!is.null(page_builder)) page_builder(page_no + 1L) else detect_next_page(pg$html, current_url)
    if (is.na(next_url) || !nzchar(next_url) || identical(next_url, current_url)) break
    current_url <- next_url
    page_no <- page_no + 1L
  }

  # Fallback leve: se nada foi encontrado, cria um registro mínimo da própria página oficial.
  if (nrow(all_records) == 0) {
    pg0 <- safe_request_page(first_url, log_path = log_path)
    if (isTRUE(pg0$ok) && !is.null(pg0$html)) {
      fallback_record <- extract_core_record(
        source_row = source_row,
        input_title = extract_meta_title(pg0$html) %||% paste("Oportunidades", source_row$sigla[[1]] %||% source_row$nome_fonte[[1]]),
        input_summary = extract_page_summary(pg0$html),
        input_full_text = extract_page_summary(pg0$html, max_chars = 3000),
        page_url = first_url,
        detail_url = NA_character_,
        pdf_url = pick_first_nonempty(extract_pdf_links(pg0$html, first_url)),
        page_no = 1L
      )
      all_records <- fallback_record
    }
  }

  list(
    records = finalize_records(all_records),
    pages_visited = length(pages_seen),
    last_url = last_url
  )
}

collect_generic_official <- function(source_row, max_pages, max_records, use_ai, log_path) {
  collect_listing_with_pagination(
    source_row = source_row,
    first_url = source_row$url_oportunidades[[1]],
    max_pages = max_pages,
    max_records = max_records,
    use_ai = use_ai,
    log_path = log_path
  )
}

collect_confap <- function(source_row, max_pages, max_records, use_ai, log_path) {
  page_builder <- function(page_no) {
    if (page_no <= 1) return(source_row$url_oportunidades[[1]])
    sprintf("%s/page/%s", sub("/$", "", source_row$url_oportunidades[[1]]), page_no)
  }
  collect_listing_with_pagination(
    source_row = source_row,
    first_url = page_builder(1),
    max_pages = max_pages,
    max_records = max_records,
    use_ai = use_ai,
    log_path = log_path,
    page_builder = page_builder
  )
}

collect_fapes_es <- function(source_row, max_pages, max_records, use_ai, log_path) {
  pg <- safe_request_page(source_row$url_oportunidades[[1]], log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]]))
  }

  pdfs <- extract_pdf_links(pg$html, source_row$url_oportunidades[[1]])
  pdfs <- pdfs[!is.na(pdfs) & nzchar(pdfs)]
  if (length(pdfs) > max_records) pdfs <- pdfs[seq_len(max_records)]

  recs <- purrr::map_dfr(seq_along(pdfs), function(i) {
    pdf_url <- pdfs[[i]]
    pdf_text <- extract_text_from_pdf(pdf_url, log_path = log_path)
    rec <- extract_core_record(
      source_row = source_row,
      input_title = basename(pdf_url),
      input_summary = stringr::str_sub(pdf_text, 1, 900),
      input_full_text = pdf_text,
      page_url = source_row$url_oportunidades[[1]],
      detail_url = NA_character_,
      pdf_url = pdf_url,
      page_no = 1L
    )
    rec$tipo_oportunidade <- "edital"
    if (isTRUE(use_ai)) rec <- enrich_record_with_ai(rec, log_path)
    rec
  })

  if (nrow(recs) == 0) {
    recs <- extract_core_record(
      source_row = source_row,
      input_title = "Editais abertos FAPES",
      input_summary = extract_page_summary(pg$html),
      input_full_text = extract_page_summary(pg$html, max_chars = 3000),
      page_url = source_row$url_oportunidades[[1]],
      detail_url = NA_character_,
      pdf_url = NA_character_,
      page_no = 1L
    )
  }

  list(records = finalize_records(recs), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]])
}

collect_cnpq <- collect_generic_official
collect_capes <- collect_generic_official
collect_finep <- collect_generic_official
collect_fapesp <- collect_generic_official
collect_faperj <- collect_generic_official
collect_fapemig <- collect_generic_official
collect_bndes <- collect_generic_official
collect_mcti <- collect_generic_official
collect_horizon_europe <- collect_generic_official
collect_erc <- collect_generic_official
collect_nih <- collect_generic_official
collect_nsf <- collect_generic_official
collect_wellcome <- collect_generic_official
collect_gates <- collect_generic_official
collect_idrc <- collect_generic_official
collect_unesco <- collect_generic_official
collect_daad <- collect_generic_official
collect_world_bank <- collect_generic_official
collect_idb <- collect_generic_official
collect_undp <- collect_generic_official
collect_embrapii <- collect_generic_official
collect_ics <- collect_generic_official
collect_min_saude <- collect_generic_official
collect_facepe <- function(source_row, max_pages, max_records, use_ai, log_path) list(records = ensure_record_schema(tibble::tibble()), pages_visited = 0L, last_url = source_row$url_oportunidades[[1]])
collect_fapesb <- function(source_row, max_pages, max_records, use_ai, log_path) list(records = ensure_record_schema(tibble::tibble()), pages_visited = 0L, last_url = source_row$url_oportunidades[[1]])

collect_fapesc <- function(source_row, max_pages, max_records, use_ai, log_path) {
  pg <- safe_request_page(source_row$url_oportunidades[[1]], log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]]))
  }

  links <- try({
    rvest::html_elements(pg$html, "article a, .entry-content a, .content a, main a, a[href]")
  }, silent = TRUE)

  if (inherits(links, "try-error") || length(links) == 0) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]]))
  }

  hrefs <- rvest::html_attr(links, "href")
  texts <- rvest::html_text2(links)

  valid_idx <- !is.na(hrefs) & nzchar(hrefs) & 
    (grepl("edital|chamada|fapesc", tolower(hrefs)) | grepl("edital|chamada|submiss", tolower(texts))) &
    !grepl("wp-content/uploads", hrefs)

  hrefs <- hrefs[valid_idx]
  texts <- texts[valid_idx]

  hrefs <- vapply(hrefs, function(h) resolve_url(source_row$url_oportunidades[[1]], h), character(1))

  unique_links <- tibble::tibble(url = hrefs, text = texts) |>
    dplyr::distinct(url, .keep_all = TRUE) |>
    dplyr::filter(nzchar(text))

  if (nrow(unique_links) == 0) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]]))
  }

  if (nrow(unique_links) > max_records) {
    unique_links <- unique_links[seq_len(max_records), ]
  }

  recs <- purrr::map_dfr(seq_len(nrow(unique_links)), function(i) {
    row <- unique_links[i, ]
    detail_bundle <- extract_detail_bundle(detail_url = row$url[[1]], page_url = source_row$url_oportunidades[[1]], log_path = log_path)

    rec <- extract_core_record(
      source_row = source_row,
      input_title = pick_first_nonempty(detail_bundle$detail_title, row$text[[1]]),
      input_summary = pick_first_nonempty(detail_bundle$detail_summary, row$text[[1]]),
      input_full_text = pick_first_nonempty(detail_bundle$full_text, row$text[[1]]),
      page_url = source_row$url_oportunidades[[1]],
      detail_url = row$url[[1]],
      pdf_url = detail_bundle$pdf_url,
      page_no = 1L
    )
    if (isTRUE(use_ai)) rec <- enrich_record_with_ai(rec, log_path)
    rec
  })

  list(records = finalize_records(recs), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]])
}

collect_eureka <- function(source_row, max_pages, max_records, use_ai, log_path) {
  pg <- safe_request_page(source_row$url_oportunidades[[1]], log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]]))
  }

  links <- try({
    rvest::html_elements(pg$html, "a[href]")
  }, silent = TRUE)

  if (inherits(links, "try-error") || length(links) == 0) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]]))
  }

  hrefs <- rvest::html_attr(links, "href")
  texts <- rvest::html_text2(links)

  valid_idx <- !is.na(hrefs) & nzchar(hrefs) & 
    (grepl("/open-calls/|/call-for-", hrefs) | grepl("open call|call for", tolower(texts)))

  hrefs <- hrefs[valid_idx]
  texts <- texts[valid_idx]

  hrefs <- vapply(hrefs, function(h) resolve_url(source_row$url_oportunidades[[1]], h), character(1))

  unique_links <- tibble::tibble(url = hrefs, text = texts) |>
    dplyr::distinct(url, .keep_all = TRUE) |>
    dplyr::filter(nzchar(text))

  if (nrow(unique_links) == 0) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]]))
  }

  if (nrow(unique_links) > max_records) {
    unique_links <- unique_links[seq_len(max_records), ]
  }

  recs <- purrr::map_dfr(seq_len(nrow(unique_links)), function(i) {
    row <- unique_links[i, ]
    detail_bundle <- extract_detail_bundle(detail_url = row$url[[1]], page_url = source_row$url_oportunidades[[1]], log_path = log_path)

    rec <- extract_core_record(
      source_row = source_row,
      input_title = pick_first_nonempty(detail_bundle$detail_title, row$text[[1]]),
      input_summary = pick_first_nonempty(detail_bundle$detail_summary, row$text[[1]]),
      input_full_text = pick_first_nonempty(detail_bundle$full_text, row$text[[1]]),
      page_url = source_row$url_oportunidades[[1]],
      detail_url = row$url[[1]],
      pdf_url = detail_bundle$pdf_url,
      page_no = 1L
    )
    if (isTRUE(use_ai)) rec <- enrich_record_with_ai(rec, log_path)
    rec
  })

  list(records = finalize_records(recs), pages_visited = 1L, last_url = source_row$url_oportunidades[[1]])
}

truncate_excel_strings <- function(df, max_chars = 32000L) {
  # Convert to plain data.frame to prevent tibble Rcpp compatibility issues
  out <- as.data.frame(df, stringsAsFactors = FALSE)
  for (nm in names(out)) {
    if (is.character(out[[nm]])) {
      x <- out[[nm]]
      # Clean any invalid UTF-8 bytes that cause nchar/substr or libxlsxwriter C++ errors
      x <- iconv(x, to = "UTF-8", sub = "")
      nch <- nchar(x, type = "chars")
      too_long <- !is.na(x) & !is.na(nch) & nch > max_chars
      if (any(too_long)) {
        x[too_long] <- paste0(substr(x[too_long], 1L, max_chars - 3L), "...")
      }
      out[[nm]] <- x
    }
  }
  out
}

save_collection_exports <- function(df, export_dir, prefix = "funding_base", log_path = NULL) {
  ensure_dir(export_dir)
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  csv_path <- file.path(export_dir, sprintf("%s_%s.csv", prefix, stamp))
  rds_path <- file.path(export_dir, sprintf("%s_%s.rds", prefix, stamp))
  xlsx_path <- file.path(export_dir, sprintf("%s_%s.xlsx", prefix, stamp))

  export_paths <- character()
  export_warnings <- character()

  # Preprocessamento para evitar incompatibilidades de tipos e classes com writexl/readr
  clean_df <- as.data.frame(df, stringsAsFactors = FALSE)
  row.names(clean_df) <- NULL
  for (nm in names(clean_df)) {
    attr(clean_df[[nm]], "names") <- NULL
    if (inherits(clean_df[[nm]], c("POSIXt", "Date"))) {
      clean_df[[nm]] <- as.character(clean_df[[nm]])
    }
  }

  tryCatch({
    readr::write_csv(clean_df, csv_path, na = "")
    export_paths <- c(export_paths, csv_path)
  }, error = function(e) {
    export_warnings <<- c(export_warnings, paste0("Falha ao exportar CSV: ", e$message))
    if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
  })

  tryCatch({
    saveRDS(clean_df, rds_path)
    export_paths <- c(export_paths, rds_path)
  }, error = function(e) {
    export_warnings <<- c(export_warnings, paste0("Falha ao exportar RDS: ", e$message))
    if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
  })

  tryCatch({
    xlsx_df <- truncate_excel_strings(clean_df)
    writexl::write_xlsx(list(oportunidades = xlsx_df), xlsx_path)
    export_paths <- c(export_paths, xlsx_path)
    if (any(vapply(names(clean_df), function(nm) {
      if (!is.character(clean_df[[nm]])) return(FALSE)
      nch <- nchar(clean_df[[nm]], type = "chars")
      any(!is.na(nch) & nch > 32000L, na.rm = TRUE)
    }, logical(1)))) {
      export_warnings <<- c(export_warnings, "Exportação XLSX gerada com truncamento de textos acima de 32.000 caracteres.")
      if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
    }
  }, error = function(e) {
    export_warnings <<- c(export_warnings, paste0("Falha ao exportar XLSX: ", e$message))
    if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
  })

  list(paths = export_paths, warnings = unique(export_warnings))
}

collect_all_sources <- function(conn, source_ids = NULL, max_pages = 5, max_records_per_source = 50, use_ai = FALSE, export_dir = "data_exports", log_path = "logs/funding_collection.log", progress_cb = NULL, do_export = TRUE) {
  ensure_dir(dirname(log_path))
  log_write(log_path, "INFO", "Início da coleta oficial.")

  status_file <- file.path(getwd(), "logs", "collection_status.json")
  log_file <- file.path(getwd(), "logs", "collection_modal_log.txt")
  dir.create(dirname(status_file), recursive = TRUE, showWarnings = FALSE)
  try({
    file.remove(status_file)
    file.remove(log_file)
  }, silent = TRUE)

  sources <- tibble::as_tibble(DBI::dbReadTable(conn, "fontes_financiamento")) |>
    dplyr::filter(!(.data$id_fonte %in% c("facepe", "fapesb")))

  if (!is.null(source_ids) && length(source_ids) > 0) {
    source_ids <- setdiff(source_ids, c("facepe", "fapesb"))
    sources <- dplyr::filter(sources, .data$id_fonte %in% source_ids)
  }

  total <- nrow(sources)
  processed <- 0L
  inserted_total <- 0L

  for (i in seq_len(total)) {
    src <- sources[i, , drop = FALSE]
    sid <- src$id_fonte[[1]]
    
    status_data <- list(
      step = i - 1L,
      total = total,
      percentage = round(((i - 1L) / total) * 100),
      detail = sprintf("Processando %s (%d/%d)", src$nome_fonte[[1]], i, total),
      phase = "Scraping",
      timestamp = as.character(Sys.time()),
      status = "running"
    )
    try(jsonlite::write_json(status_data, status_file, auto_unbox = TRUE), silent = TRUE)
    log_progress(sprintf("Iniciando coleta da agência %s...", src$sigla[[1]]), "Scraping")
    
    if (!is.null(progress_cb)) progress_cb(i - 1L, total, sprintf("Coletando %s", sid))
    log_write(log_path, "INFO", sprintf("Fonte em processamento: %s | %s", sid, src$url_oportunidades[[1]]))

    result <- tryCatch({
      source_dispatch(
        source_row = src,
        max_pages = max_pages,
        max_records = max_records_per_source,
        use_ai = use_ai,
        log_path = log_path
      )
    }, error = function(e) {
      log_write(log_path, "ERROR", sprintf("Falha na fonte %s: %s", sid, e$message))
      log_collection(conn, sid, src$metodo_coleta[[1]], "erro", e$message, n_paginas = 0L, n_registros = 0L, url = src$url_oportunidades[[1]])
      NULL
    })

    if (is.null(result)) next

    recs <- tryCatch(finalize_records(result$records), error = function(e) {
      log_write(log_path, "ERROR", sprintf("Falha ao finalizar registros da fonte %s: %s", sid, e$message))
      ensure_record_schema(tibble::tibble())
    })
    n_inserted <- upsert_opportunities(conn, recs)
    inserted_total <- inserted_total + n_inserted
    log_collection(
      conn = conn,
      fonte = sid,
      metodo_coleta = src$metodo_coleta[[1]],
      status_execucao = "sucesso",
      mensagem = sprintf("%s registro(s) processado(s)", n_inserted),
      n_paginas = result$pages_visited %||% 0L,
      n_registros = n_inserted,
      url = result$last_url %||% src$url_oportunidades[[1]]
    )
    processed <- processed + 1L
  }

  final_df <- tibble::as_tibble(DBI::dbReadTable(conn, "oportunidades"))
  if (nrow(final_df) == 0) {
    seed_demo_opportunities(conn)
    final_df <- tibble::as_tibble(DBI::dbReadTable(conn, "oportunidades"))
  }

  exports <- NULL
  if (isTRUE(do_export)) exports <- save_collection_exports(final_df, export_dir, prefix = "funding_intelligence_base", log_path = log_path)
  log_write(log_path, "INFO", sprintf("Fim da coleta oficial. %s fontes processadas. %s registros adicionados nesta rodada. %s registros na base.", processed, inserted_total, nrow(final_df)))

  status_data <- list(
    step = total,
    total = total,
    percentage = 100,
    detail = "Coleta finalizada com sucesso!",
    phase = "Concluído",
    timestamp = as.character(Sys.time()),
    status = "done"
  )
  try(jsonlite::write_json(status_data, status_file, auto_unbox = TRUE), silent = TRUE)
  log_progress("Processamento concluído com sucesso.", "Concluído")

  list(
    msg = sprintf("Coleta finalizada com %s fonte(s) processadas.", processed),
    sources_processed = processed,
    inserted_now = inserted_total,
    n_records = nrow(final_df),
    exports = if (is.list(exports)) exports$paths else exports,
    export_warnings = if (is.list(exports)) exports$warnings else character(),
    data = final_df
  )
}

run_full_collection_cycle <- function(conn, sources_ids = NULL, max_pages = 5, max_records_per_source = 50, use_ai = FALSE, export_dir = "data_exports", log_path = "logs/funding_collection.log", do_export = TRUE) {
  res <- collect_all_sources(
    conn = conn,
    source_ids = sources_ids,
    max_pages = max_pages,
    max_records_per_source = max_records_per_source,
    use_ai = use_ai,
    export_dir = export_dir,
    log_path = log_path,
    do_export = do_export
  )
  res$data <- tibble::as_tibble(DBI::dbReadTable(conn, "oportunidades"))
  res
}
