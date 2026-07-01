log_progress <- function(detail, phase = "Scraping") {
  try({
    log_file <- Sys.getenv("COLLECTION_MODAL_LOG_FILE")
    if (!nzchar(log_file)) {
      log_file <- file.path(getwd(), "logs", "collection_modal_log.txt")
    }
    log_line <- sprintf("[%s] [%s] %s", format(Sys.time(), "%H:%M:%S"), phase, detail)
    cat(log_line, "\n", file = log_file, append = TRUE)
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

source_dispatch <- function(source_row, max_pages = 5, max_records = 15, use_ai = FALSE, log_path = NULL) {
  sid <- source_row$id_fonte[[1]]
  
  result <- if (identical(sid, "finep")) {
    collect_finep(source_row, max_pages, max_records, FALSE, log_path)
  } else {
    collect_generic_official(source_row, max_pages, max_records, FALSE, log_path)
  }

  if (isTRUE(use_ai) && !is.null(result$records) && nrow(result$records) > 0) {
    result$records <- enrich_records_parallel(result$records, log_path = log_path)
  }

  result
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
            try:
                from playwright_stealth import stealth_sync
                stealth_sync(page)
            except ImportError:
                page.add_init_script(\"\"\"
                    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                    Object.defineProperty(navigator, 'languages', { get: () => ['pt-BR', 'pt', 'en-US', 'en'] });
                    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
                    window.chrome = { runtime: {} };
                \"\"\")
            page.goto(url, wait_until='networkidle', timeout=15000)
            content = page.content()
            browser.close()
            return {'content': content, 'ok': True}
    except Exception as e:
        return {'content': str(e), 'ok': False}
")
    playwright_run <- reticulate::py$run_playwright_stealth(url)
    if (isTRUE(playwright_run$ok)) {
      has_block <- grepl("attention required! \\| cloudflare|cf-challenge|ray id:|checking your browser before accessing|security challenge|access denied", tolower(playwright_run$content))
      if (has_block) {
        if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Bloqueio de CDN/CAPTCHA detectado via Playwright para %s.", url))
        list(ok = FALSE)
      } else {
        html <- xml2::read_html(playwright_run$content)
        list(url = url, html = html, text = playwright_run$content, ok = TRUE, method = "playwright")
      }
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

is_host_alive <- function(url) {
  tryCatch({
    req <- httr2::request(url) |>
      httr2::req_method("HEAD") |>
      httr2::req_timeout(3)
    httr2::req_perform(req)
    TRUE
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("Could not resolve host|Could not resolve hostname|Timeout was reached|Connection refused|Failed to connect", msg, ignore.case = TRUE)) {
      return(FALSE)
    }
    TRUE
  })
}

safe_request_page <- function(url, log_path = NULL, use_browser_fallback = TRUE) {
  if (!is_host_alive(url)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Host offline ou inacessivel: %s. Pulando requisicoes antecipadamente.", url))
    return(list(url = url, html = NULL, text = NA_character_, ok = FALSE, method = "ping_failed"))
  }

  # 1. Tentar httr2 (metodo rapido)
  req <- httr2::request(url) |>
    httr2::req_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") |>
    httr2::req_headers(
      `Accept-Language` = "pt-BR,pt;q=0.9,en;q=0.8",
      `Accept` = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    ) |>
    httr2::req_timeout(15) |>
    httr2::req_retry(max_tries = 2)

  resp <- tryCatch({
    httr2::req_perform(req)
  }, error = function(e) {
    if (!is.null(e$response)) return(e$response)
    e
  })

  if (!inherits(resp, "error")) {
    status <- httr2::resp_status(resp)
    if (status == 404) {
      if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("URL nao encontrada (404) para %s. Ignorando fallbacks.", url))
      return(list(url = url, html = NULL, text = NA_character_, ok = FALSE, method = "httr2_404"))
    }

    txt <- try(httr2::resp_body_string(resp), silent = TRUE)
    txt_ok <- !inherits(txt, "try-error") && length(txt) == 1 && !is.na(txt) && nzchar(txt)
    if (txt_ok) {
      html <- try(xml2::read_html(txt), silent = TRUE)
      if (!inherits(html, "try-error") && status >= 200 && status < 300) {
        # Verifica se o conteudo contem sinal obvio de captcha/bloqueio por CDN antes de aceitar
        has_block_signal <- grepl("attention required! \\| cloudflare|cf-challenge|ray id:|checking your browser before accessing|security challenge|access denied", tolower(txt))
        if (!has_block_signal) {
          return(list(url = url, html = html, text = txt, ok = TRUE, method = "httr2"))
        } else {
          if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("Bloqueio de CDN/CAPTCHA (status %d) detectado via httr2 para %s. Acionando fallbacks...", status, url))
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
        has_block <- grepl("attention required! \\| cloudflare|cf-challenge|ray id:|checking your browser before accessing|security challenge|access denied", tolower(html_txt))
        if (has_block) {
          if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Bloqueio de CDN/CAPTCHA detectado via Chromote para %s.", url))
        } else {
          html <- try(xml2::read_html(html_txt), silent = TRUE)
          if (!inherits(html, "try-error")) {
            return(list(url = url, html = html, text = html_txt, ok = TRUE, method = "chromote_stealth"))
          }
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

is_funding_opportunity_heuristics <- function(title, description = "", url = "", body_text = "") {
  # Normalizar entradas (remover acentos, minúsculo, espaços múltiplos)
  t_norm <- normalize_text(title %||% "")
  d_norm <- normalize_text(description %||% "")
  u_norm <- tolower(url %||% "")
  b_norm <- normalize_text(body_text %||% "")

  # 1. Regras de descarte pelo URL (notícias, institucionais, privacidade, etc.)
  invalid_url_patterns <- c(
    "/noticias", "/noticia", "/tv-", "/tv/", "/video", "/membros", 
    "/regulamentos", "/como-usar", "/archive", "/privacidade", 
    "/lgpd", "/politica-de-privacidade", "/contatos", "/fale-conosco",
    "/equipe", "/quem-somos", "/sobre-nos", "/servicos-ao-cidadao",
    "/perguntas-frequentes", "/faq", "/documentos",
    "/acesso-a-informacao", "/institucional", "/financiamento-via-credito",
    "/financiamento-reembolsavel", "retificacao", "retificado",
    "prorrogacao", "aditivo", "errata", "gabarito", "homologacao",
    "perguntas-frequentes", "perguntas_frequentes",
    "nota-de-esclarecimento", "anexo"
  )
  
  if (any(vapply(invalid_url_patterns, function(pat) grepl(pat, u_norm, fixed = TRUE), logical(1)))) {
    return(FALSE)
  }

  # Ignorar alterações que não sejam climáticas
  if (grepl("alteracao", u_norm, fixed = TRUE)) {
    if (!grepl("alteracoes-climaticas|alteracao-climatica", u_norm)) {
      return(FALSE)
    }
  }

  # Bloquear resultados/recursos na URL
  if (grepl("resultado", u_norm, fixed = TRUE) && !grepl("resultado-recursos|recursos-naturais", u_norm)) {
    if (grepl("resultado-final|resultado-preliminar|resultado_final|resultado_preliminar|/resultados/", u_norm)) {
      return(FALSE)
    }
  }

  # 2. Regras de descarte pelo Título (remover manuais, procedimentos, páginas genéricas)
  invalid_title_patterns <- c(
    "manual do cartao", "cobranca administrativa", "carta de servico",
    "mapa de fomento", "bolsas e projetos vigentes", "acesso a informacao",
    "lgpd", "privacidade e protecao", "formict", "lei do bem",
    "acoes e programas", "este link", "qualifications and eligibility",
    "noticias", "tv fapesc", "sobre a finep", "financiamento nao reembolsavel",
    "strategic plan", "ebook", "relatorio de atividades", "como usar",
    "membros do comite", "perguntas frequentes", "faq", "contato", "quem somos",
    "links uteis", "documentos importantes", "tutoriais", "tutorial",
    "instrucoes para envio", "privacidade e protecao de dados",
    "temas em destaque", "carta de servicos ao cidadao", "archive",
    "retificacao", "retificacoes", "prorrogacao",
    "prorrogacoes", "termo aditivo", "aditivo", "errata", "gabarito",
    "esclarecimento", "esclarecimentos", "nota de esclarecimento", "homologacao",
    "oportunidades - finep", "oportunidades de financiamento",
    "financiamento via credito", "financiamento para inovacao", "a finep"
  )

  for (pat in invalid_title_patterns) {
    if (grepl(pat, t_norm, fixed = TRUE)) {
      return(FALSE)
    }
  }

  # Ignorar alteração no título se não for climática
  if (grepl("alteracao", t_norm, fixed = TRUE)) {
    if (!grepl("alteracoes climaticas|alteracao climatica", t_norm)) {
      return(FALSE)
    }
  }

  # Julgamentos, recursos ou resultados específicos
  if (grepl("resultado final|resultado preliminar|resultado provisorio|resultado de recurso|fase de recurso|prazo de recurso|julgamento da chamada|homologacao do resultado", t_norm)) {
    return(FALSE)
  }

  # 3. Regras específicas sobre e-books, manuais e materiais institucionais
  if (grepl("daad 2025 confap", t_norm) || 
      grepl("fapes 20 anos", t_norm) || 
      grepl("ebook", t_norm) ||
      grepl("relatorio anual", t_norm)) {
    return(FALSE)
  }

  # 4. Caso o título seja apenas um arquivo de retificação/anexo/resultado
  if (grepl("\\.pdf$", t_norm) && 
      (grepl("alteracao", t_norm) || 
       grepl("retificacao", t_norm) || 
       grepl("aditivo", t_norm) || 
       grepl("anexo", t_norm) || 
       grepl("resultado", t_norm) || 
       grepl("prorrogacao", t_norm))) {
    return(FALSE)
  }

  # 5. Caso o título seja apenas um texto de navegação/link quebrado
  if (t_norm %in% c("link", "este link", "aqui", "clique aqui", "saiba mais", "visualizar", "abrir")) {
    return(FALSE)
  }

  return(TRUE)
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

extract_candidate_links <- function(html, base_url, source_id) {
  anchors <- try(rvest::html_elements(html, "a[href]"), silent = TRUE)
  if (inherits(anchors, "try-error") || length(anchors) == 0) return(tibble::tibble())
  
  hrefs <- rvest::html_attr(anchors, "href")
  abs_urls <- vapply(hrefs, function(h) resolve_url(base_url, h), character(1))
  
  valid <- !is.na(abs_urls) & nzchar(abs_urls)
  if (!any(valid)) return(tibble::tibble())
  
  anchors <- anchors[valid]
  abs_urls <- abs_urls[valid]
  
  anchor_texts <- vapply(anchors, safe_html_text, character(1))
  container_texts <- vapply(anchors, function(a) {
    parent <- try(rvest::html_parent(a), silent = TRUE)
    nearest_block_text(a) %||% (if (!inherits(parent, "try-error")) safe_html_text(parent) else "") %||% ""
  }, character(1))
  
  is_pdf <- grepl("\\.pdf($|\\?)", abs_urls, ignore.case = TRUE)
  
  tibble::tibble(
    anchor_text = anchor_texts,
    container_text = container_texts,
    href = abs_urls,
    is_pdf = is_pdf
  )
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

  schema <- tibble::tibble(
    candidate_title = character(),
    candidate_summary = character(),
    detail_url = character(),
    pdf_url = character(),
    source_text = character()
  )
  out <- dplyr::bind_rows(schema, block_df, anchor_df) |>
    dplyr::mutate(
      candidate_title = null_if_empty(candidate_title),
      candidate_summary = null_if_empty(candidate_summary),
      source_text = null_if_empty(source_text),
      detail_url = null_if_empty(detail_url),
      pdf_url = null_if_empty(pdf_url)
    ) |>
    dplyr::filter(!is.na(candidate_title) | !is.na(detail_url) | !is.na(pdf_url)) |>
    dplyr::filter(vapply(seq_len(dplyr::n()), function(idx) {
      is_funding_opportunity_heuristics(
        title = candidate_title[[idx]],
        description = candidate_summary[[idx]],
        url = dplyr::coalesce(detail_url[[idx]], pdf_url[[idx]], ""),
        body_text = source_text[[idx]]
      )
    }, logical(1))) |>
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
        dplyr::distinct(pdf_url, .keep_all = TRUE) |>
        dplyr::filter(vapply(seq_len(dplyr::n()), function(idx) {
          is_funding_opportunity_heuristics(
            title = title[[idx]],
            description = summary[[idx]],
            url = pdf_url[[idx]],
            body_text = source_text[[idx]]
          )
        }, logical(1)))
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
      httr2::req_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") |>
      httr2::req_timeout(20)
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
  status_file <- Sys.getenv("COLLECTION_STATUS_FILE")
  if (!nzchar(status_file)) {
    status_file <- file.path(getwd(), "logs", "collection_status.json")
  }
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

  # Verifica se a IA classificou como nao-edital
  is_edital <- TRUE
  if (!is.null(ai$e_edital_fomento)) {
    val <- ai$e_edital_fomento[[1]]
    if (is.logical(val)) {
      is_edital <- val
    } else if (is.character(val)) {
      is_edital <- !tolower(val) %in% c("false", "f")
    }
  }

  if (!is_edital) {
    log_progress(sprintf("Descartando edital '%s' via classificação de IA (Motivo: %s)", record$titulo[[1]], ai$motivo_descarte[[1]] %||% "não especificado"), "IA")
    return(tibble::tibble())
  }

  fill_field <- function(field, value, overwrite = FALSE) {
    if (is.null(value) || length(value) == 0) return(invisible(NULL))
    if (length(value) > 1) {
      value <- paste(vapply(value, as.character, character(1)), collapse = "; ")
    } else {
      value <- as.character(value[[1]])
    }
    if (is.na(value) || !nzchar(trimws(value))) return(invisible(NULL))
    if (field == "palavras_chave") {
      value <- gsub(",\\s*", "; ", value)
      value <- gsub(";+", ";", value)
    }
    if (!field %in% names(record)) {
      record[[field]] <<- NA_character_
    }
    current <- record[[field]][[1]]
    if (overwrite || is.null(current) || length(current) == 0 || is.na(current) || !nzchar(trimws(as.character(current)))) {
      record[[field]] <<- value
      inferred <<- unique(c(inferred, field))
    }
    invisible(NULL)
  }

  inferred <- character()
  fill_field("titulo", ai$titulo_limpo, overwrite = TRUE)
  fill_field("descricao_resumida", ai$resumo, overwrite = TRUE)
  fill_field("palavras_chave", ai$palavras_chave, overwrite = TRUE)
  fill_field("elegibilidade", ai$elegibilidade)
  fill_field("area_tematica", ai$area_tematica)
  fill_field("tipo_oportunidade", ai$tipo_oportunidade, overwrite = TRUE)
  fill_field("status_oportunidade", ai$status_oportunidade, overwrite = TRUE)
  fill_field("idioma", ai$idioma, overwrite = TRUE)
  fill_field("data_limite", ai$data_limite, overwrite = TRUE)
  fill_field("data_publicacao", ai$data_publicacao, overwrite = TRUE)
  fill_field("observacoes", ai$observacoes)
  fill_field("modalidade", ai$modalidade, overwrite = TRUE)
  fill_field("publico_alvo", ai$publico_alvo, overwrite = TRUE)
  fill_field("nivel_academico", ai$nivel_academico, overwrite = TRUE)
  fill_field("data_abertura", ai$data_abertura, overwrite = TRUE)
  fill_field("data_encerramento", ai$data_encerramento, overwrite = TRUE)

  # Sobrescreve valor_financiado e moeda com os valores extraidos pela IA
  ai_val <- if (!is.null(ai$valor_financiado) && !is.na(ai$valor_financiado)) as.numeric(ai$valor_financiado[[1]]) else NA_real_
  ai_curr <- if (!is.null(ai$moeda) && !is.na(ai$moeda) && nzchar(trimws(ai$moeda[[1]]))) as.character(ai$moeda[[1]]) else NA_character_
  
  if (!identical(record$valor_financiado[[1]], ai_val)) {
    record$valor_financiado[[1]] <- ai_val
    inferred <- c(inferred, "valor_financiado")
  }
  if (!identical(record$moeda[[1]], ai_curr)) {
    record$moeda[[1]] <- ai_curr
    inferred <- c(inferred, "moeda")
  }

  record$campos_inferidos_ia <- paste(unique(inferred), collapse = "; ")
  record
}

enrich_records_parallel <- function(df, log_path = NULL) {
  if (is.null(df) || nrow(df) == 0) return(df)

  df$keep_record <- TRUE

  # Garante id_registro e hash_deduplicacao
  df$hash_deduplicacao <- vapply(seq_len(nrow(df)), function(i) {
    h <- df$hash_deduplicacao[[i]]
    if (is.na(h) || !nzchar(h)) {
      digest::digest(paste0(df$titulo[[i]], df$link_origem[[i]]), algo = "xxhash64")
    } else {
      h
    }
  }, character(1))

  df$id_registro <- vapply(seq_len(nrow(df)), function(i) {
    id <- df$id_registro[[i]]
    if (is.na(id) || !nzchar(id)) {
      paste0(df$fonte_oficial[[i]], "_", substr(df$hash_deduplicacao[[i]], 1, 16))
    } else {
      id
    }
  }, character(1))

  # 1. Cache Lógico (Deduplicação)
  conn <- if (exists("conn", envir = .GlobalEnv)) .GlobalEnv$conn else NULL
  if (is.null(conn)) {
    db_path <- file.path(getwd(), "funding_intelligence.sqlite")
    if (file.exists(db_path)) {
      conn <- tryCatch(DBI::dbConnect(RSQLite::SQLite(), db_path), error = function(e) NULL)
      on.exit({ if (!is.null(conn) && DBI::dbIsValid(conn)) DBI::dbDisconnect(conn) })
    }
  }

  to_enrich_indices <- integer()

  for (i in seq_len(nrow(df))) {
    need_ia <- TRUE
    if (!is.null(conn) && DBI::dbIsValid(conn)) {
      id <- df$id_registro[[i]]
      hash_val <- df$hash_deduplicacao[[i]]

      existing <- tryCatch({
        DBI::dbGetQuery(
          conn,
          "SELECT id_registro, descricao_resumida, campos_inferidos_ia FROM oportunidades WHERE id_registro = ? OR hash_deduplicacao = ?",
          params = list(id, hash_val)
        )
      }, error = function(e) NULL)

      if (!is.null(existing) && nrow(existing) > 0) {
        resumo <- existing$descricao_resumida[[1]]
        campos_ia <- existing$campos_inferidos_ia[[1]] %||% ""
        if (!is.na(resumo) && nzchar(trimws(resumo)) && !identical(resumo, "Resumo não disponível.") && nzchar(campos_ia)) {
          log_progress(sprintf("Edital '%s' já enriquecido no banco. Recuperando cache...", df$titulo[[i]]), "IA")

          # Carrega o registro completo do banco
          existing_full <- tryCatch({
            DBI::dbGetQuery(conn, "SELECT * FROM oportunidades WHERE id_registro = ?", params = list(existing$id_registro[[1]]))
          }, error = function(e) NULL)

          if (!is.null(existing_full) && nrow(existing_full) > 0) {
            # Atualiza o df com o registro existente no banco
            for (col in names(existing_full)) {
              if (col %in% names(df)) {
                val <- existing_full[[col]][[1]]
                if (!is.null(val) && !is.na(val)) {
                  if (is.numeric(df[[col]])) {
                    df[[col]][[i]] <- as.numeric(val)
                  } else if (is.integer(df[[col]])) {
                    df[[col]][[i]] <- as.integer(val)
                  } else {
                    df[[col]][[i]] <- as.character(val)
                  }
                }
              }
            }
            need_ia <- FALSE
          }
        }
      }
    }

    if (need_ia) {
      to_enrich_indices <- c(to_enrich_indices, i)
    }
  }

  if (length(to_enrich_indices) == 0) {
    df <- df[df$keep_record, ]
    df$keep_record <- NULL
    return(df)
  }

  log_progress(sprintf("Iniciando enriquecimento paralelo de %d edital(is)...", length(to_enrich_indices)), "IA")

  # Prepara prompts
  prompts <- character(length(to_enrich_indices))
  for (idx in seq_along(to_enrich_indices)) {
    i <- to_enrich_indices[[idx]]
    text <- collapse_non_empty(df$titulo[[i]], df$descricao_resumida[[i]], df$descricao_completa[[i]], df$texto_bruto[[i]], sep = "\n")
    current_info <- list(
      titulo_limpo = df$titulo[[i]],
      tipo_oportunidade = df$tipo_oportunidade[[i]],
      status_oportunidade = df$status_oportunidade[[i]],
      idioma = df$idioma[[i]]
    )

    prompts[[idx]] <- paste(
      "Analise o texto bruto do edital fornecido e extraia as informações estruturadas abaixo.",
      "Retorne OBRIGATORIAMENTE um JSON válido com os campos listados.",
      "",
      "CAMPOS OBRIGATÓRIOS:",
      "",
      "e_edital_fomento: Valor booleano (true ou false). Deve ser true apenas se o texto for de fato uma oportunidade principal de fomento, edital, chamada pública, grant, fellowship, bolsa ou convocatória ativa, futura ou mesmo encerrada recentemente. Deve ser false se o texto for apenas uma retificação, alteração, prorrogação de prazo, termo aditivo, errata, resultado de edital existente, ou se for um manual administrativo, notícias gerais, procedimentos de relatórios, membros de comitê, planos estratégicos gerais, relatórios institucionais ou páginas descrevendo linhas de crédito permanentes e serviços de financiamento contínuos (não-editais).",
      "",
      "motivo_descarte: Texto curto descrevendo a razão do descarte se e_edital_fomento for false (ex: 'Manual de cartão de pesquisa', 'Instruções para relatórios', 'Notícia institucional', 'Retificação de edital', 'Guia de linha de crédito permanente'). Se e_edital_fomento for true, este campo deve ser null.",
      "",
      "titulo_limpo: Título do edital limpo, sem caracteres especiais, numerações de seção, ruídos HTML ou abreviações inexplicadas.",
      "",
      "resumo: Síntese informativa do OBJETO CENTRAL de financiamento em 2 a 3 frases.",
      "  REGRAS OBRIGATÓRIAS:",
      "  - Responda implicitamente: O que financia? Para quem? Em quais áreas/temas? Qual o valor/prazo?",
      "  - Escreva como se estivesse descrevendo a oportunidade para um pesquisador que nunca viu o edital.",
      "  - NÃO copie frases do texto bruto.",
      "  - NÃO mencione: menus do site, links, cabeçalhos, siglas não explicadas, linguagem de seção (ex: '1. FINALIDADE 1.1...').",
      "  - EXEMPLO BOM: 'Financia projetos colaborativos de pesquisa entre instituições brasileiras e africanas nas áreas de ciência, tecnologia e inovação. Destinado a ICTs públicas e privadas em parceria formal com instituições africanas. Projetos de até R$ 150.000, com submissão até julho de 2025.'",
      "  - EXEMPLO RUIM: 'DIRETRIZES ESPECÍFICAS DA FAPES CONFAP – 1. FINALIDADE 1.1. Apoio para a manutenção da bolsa Fapes de doutorado...'",
      "",
      "elegibilidade: Quem pode se candidatar. Seja específico (ex: 'Pesquisadores doutores vinculados a ICTs públicas ou privadas', 'Doutorandos com bolsa DAAD aprovada').",
      "",
      "area_tematica: Áreas temáticas ou de conhecimento cobertas pelo edital (ex: 'Ciência e Tecnologia, Cooperação Internacional, Saúde').",
      "",
      "tipo_oportunidade: Categoria do fomento — escolha um: edital, grant, fellowship, bolsa, licitação, convocatória.",
      "",
      "status_oportunidade: aberto, encerrado ou futuro — com base no texto e nas datas encontradas.",
      "",
      "idioma: Código de 2 letras do idioma principal do edital (pt, en, es, fr, de).",
      "",
      "data_limite: Data máxima de submissão no formato AAAA-MM-DD (ou null se não encontrada no texto).",
      "",
      "data_publicacao: Data de publicação/lançamento no formato AAAA-MM-DD (ou null se não encontrada).",
      "",
      "valor_financiado: Valor numérico máximo ou global do financiamento (ex: 150000.00), ou null.",
      "  - IGNORE: números de leis, portarias, CPF, telefone, anos isolados, quantidades de vagas ou itens.",
      "  - Aceite apenas valores monetários explícitos de financiamento, bolsa ou auxílio.",
      "",
      "moeda: Código ISO de 3 letras da moeda (BRL, USD, EUR, GBP), ou null se valor_financiado for null.",
      "",
      "modalidade: Tipo de modalidade de fomento (ex: 'Bolsa de Fixação de Doutores', 'Auxílio Individual à Pesquisa', 'Subvenção Econômica', 'Cooperação Internacional', ou null).",
      "",
      "publico_alvo: Público-alvo da oportunidade (ex: 'Pesquisadores', 'ICTs públicas ou privadas', 'Startups', 'Empresas de grande porte', ou null).",
      "",
      "nivel_academico: Nível acadêmico exigido (ex: 'Pós-Doutorado', 'Doutorado', 'Mestrado', 'Graduação', 'Técnico', ou 'Não aplicável' se não houver exigência acadêmica específica, ou null).",
      "",
      "data_abertura: Data de início das submissões ou abertura das inscrições no formato AAAA-MM-DD (ou null se não encontrada).",
      "",
      "data_encerramento: Data de encerramento do projeto, vigência final das bolsas ou fim absoluto das atividades no formato AAAA-MM-DD (ou null se não encontrada).",
      "",
      "palavras_chave: Entre 5 e 8 termos separados por vírgula que descrevam o TEMA CIENTÍFICO/TECNOLÓGICO central do edital.",
      "  REGRAS ABSOLUTAS:",
      "  - PREFIRA termos compostos e específicos do domínio de pesquisa.",
      "  - PROIBIDO: nomes de instituições (CNPq, FAPES, CAPES, DAAD, Confap, Embrapii), qualquer variação de 'edital', 'chamada pública', 'seleção', 'submissão', 'proposta', 'fomento', 'projeto', 'pesquisa', 'bolsa', 'prazo', 'período', 'processo', 'programa', 'recurso', 'custeio', 'apoio', 'acordo', 'convênio'.",
      "  - PROIBIDO: palavras funcionais e genéricas como 'estar', 'cada', 'através', 'para', 'durante', 'sendo', 'deverá', 'conforme', anos isolados (2024, 2025).",
      "  - CORRETO (exemplos): 'cooperação científica internacional, mobilidade acadêmica, tecnologia da informação, inteligência artificial, saúde pública, transição energética, biotecnologia, desenvolvimento sustentável'",
      "  - INCORRETO (exemplos): 'daad, confap, 2025, doutorado, estar, período, seleção, através, pesquisa, fomento'",
      "",
      "observacoes: Restrições, contrapartidas, exigências específicas ou informações críticas para o pesquisador.",
      "  Exemplos: 'Exige parceria formal com instituição alemã aprovada pelo DAAD', 'Somente para bolsistas já aprovados em seleção prévia'.",
      "",
      "Contexto já extraído (use como ponto de partida, corrija se necessário):",
      jsonlite::toJSON(current_info, auto_unbox = TRUE, null = "null"),
      "",
      "=== TEXTO DO EDITAL ===",
      trim_for_ai(text)
    )
  }

  # Executa em lotes
  batch_size <- as.integer(Sys.getenv("AI_BATCH_SIZE", "3"))
  if (is.na(batch_size) || batch_size <= 0) batch_size <- 3

  batches <- split(seq_along(prompts), ceiling(seq_along(prompts) / batch_size))
  raw_results <- vector("list", length(prompts))

  for (b in seq_along(batches)) {
    batch_idx <- batches[[b]]
    log_progress(sprintf("Processando lote de IA %d/%d (editais %d a %d)...", b, length(batches), to_enrich_indices[batch_idx[1]], to_enrich_indices[batch_idx[length(batch_idx)]]), "IA")

    # Atualiza arquivo de status para mostrar lote
    status_file <- Sys.getenv("COLLECTION_STATUS_FILE")
    if (nzchar(status_file) && file.exists(status_file)) {
      try({
        status_data <- jsonlite::fromJSON(status_file, simplifyVector = FALSE)
        status_data$phase <- "IA"
        status_data$detail <- sprintf("Processando lote de IA %d/%d", b, length(batches))
        jsonlite::write_json(status_data, status_file, auto_unbox = TRUE)
      }, silent = TRUE)
    }

    batch_res <- ai_request_parallel(prompts[batch_idx], log_path = log_path)
    raw_results[batch_idx] <- batch_res

    # Atraso inteligente para Groq (ou OpenRouter se necessário)
    cfg <- get_ai_config()
    if (cfg$provider == "groq" && b < length(batches)) {
      delay <- as.numeric(Sys.getenv("GROQ_RATE_DELAY", "6"))
      if (is.na(delay) || delay < 0) delay <- 6
      if (delay > 0) Sys.sleep(delay)
    } else if (b < length(batches)) {
      Sys.sleep(1) # respiro leve de 1s para outros provedores
    }
  }

  # Atualiza o dataframe com os resultados obtidos
  for (idx in seq_along(to_enrich_indices)) {
    i <- to_enrich_indices[[idx]]
    raw <- raw_results[[idx]]
    if (is.null(raw) || !nzchar(raw)) next

    parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)

    if (!is.null(parsed)) {
      ai <- as.list(parsed)
      verify_enabled <- !identical(tolower(Sys.getenv("AI_VERIFY_METADATA", "true")), "false")
      if (verify_enabled) {
        text <- collapse_non_empty(df$titulo[[i]], df$descricao_resumida[[i]], df$descricao_completa[[i]], df$texto_bruto[[i]], sep = "\n")
        ai <- skill_verify_metadata(ai, text, log_path)
      }

      # Verifica se a IA classificou como nao-edital
      is_edital <- TRUE
      if (!is.null(ai$e_edital_fomento)) {
        val <- ai$e_edital_fomento[[1]]
        if (is.logical(val)) {
          is_edital <- val
        } else if (is.character(val)) {
          is_edital <- !tolower(val) %in% c("false", "f")
        }
      }

      if (!is_edital) {
        df$keep_record[[i]] <- FALSE
        log_progress(sprintf("Descartando edital '%s' via classificação de IA (Motivo: %s)", df$titulo[[i]], ai$motivo_descarte[[1]] %||% "não especificado"), "IA")
        next
      }

      inferred <- character()
      fill_field <- function(field, value, overwrite = FALSE) {
        if (is.null(value) || length(value) == 0) return()
        if (length(value) > 1) {
          value <- paste(vapply(value, as.character, character(1)), collapse = "; ")
        } else {
          value <- as.character(value[[1]])
        }
        if (is.na(value) || !nzchar(trimws(value))) return()
        if (field == "palavras_chave") {
          value <- gsub(",\\s*", "; ", value)
          value <- gsub(";+", ";", value)
        }
        if (!field %in% names(df)) {
          df[[field]] <<- NA_character_
        }
        current <- df[[field]][[i]]
        if (overwrite || is.null(current) || length(current) == 0 || is.na(current) || !nzchar(trimws(as.character(current)))) {
          df[[field]][[i]] <<- value
          inferred <<- unique(c(inferred, field))
        }
      }

      fill_field("titulo", ai$titulo_limpo, overwrite = TRUE)
      fill_field("descricao_resumida", ai$resumo, overwrite = TRUE)
      fill_field("palavras_chave", ai$palavras_chave, overwrite = TRUE)
      fill_field("elegibilidade", ai$elegibilidade)
      fill_field("area_tematica", ai$area_tematica)
      fill_field("tipo_oportunidade", ai$tipo_oportunidade, overwrite = TRUE)
      fill_field("status_oportunidade", ai$status_oportunidade, overwrite = TRUE)
      fill_field("idioma", ai$idioma, overwrite = TRUE)
      fill_field("data_limite", ai$data_limite, overwrite = TRUE)
      fill_field("data_publicacao", ai$data_publicacao, overwrite = TRUE)
      fill_field("observacoes", ai$observacoes)
      fill_field("modalidade", ai$modalidade, overwrite = TRUE)
      fill_field("publico_alvo", ai$publico_alvo, overwrite = TRUE)
      fill_field("nivel_academico", ai$nivel_academico, overwrite = TRUE)
      fill_field("data_abertura", ai$data_abertura, overwrite = TRUE)
      fill_field("data_encerramento", ai$data_encerramento, overwrite = TRUE)

      # Sobrescreve valor_financiado e moeda com os valores extraidos pela IA
      ai_val <- if (!is.null(ai$valor_financiado) && !is.na(ai$valor_financiado)) as.numeric(ai$valor_financiado[[1]]) else NA_real_
      ai_curr <- if (!is.null(ai$moeda) && !is.na(ai$moeda) && nzchar(trimws(ai$moeda[[1]]))) as.character(ai$moeda[[1]]) else NA_character_
      
      if (!identical(df$valor_financiado[[i]], ai_val)) {
        df$valor_financiado[[i]] <- ai_val
        inferred <- c(inferred, "valor_financiado")
      }
      if (!identical(df$moeda[[i]], ai_curr)) {
        df$moeda[[i]] <- ai_curr
        inferred <- c(inferred, "moeda")
      }

      df$campos_inferidos_ia[[i]] <- paste(unique(inferred), collapse = "; ")
    }
  }

  df <- df[df$keep_record, ]
  df$keep_record <- NULL
  df
}

dedupe_records <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(tibble::tibble())
  
  df |>
    dplyr::mutate(
      title_norm = normalize_text(titulo),
      parsed_date = parse_date_safe(data_limite),
      status_priority = dplyr::case_when(
        status_oportunidade == "aberto" ~ 1L,
        status_oportunidade == "futuro" ~ 2L,
        status_oportunidade == "encerrado" ~ 3L,
        TRUE ~ 4L
      ),
      content_len = nchar(dplyr::coalesce(texto_bruto, "")) + nchar(dplyr::coalesce(descricao_resumida, ""))
    ) |>
    dplyr::arrange(
      status_priority,
      dplyr::desc(parsed_date),
      dplyr::desc(content_len)
    ) |>
    dplyr::distinct(entidade, title_norm, .keep_all = TRUE) |>
    dplyr::select(-title_norm, -parsed_date, -status_priority, -content_len)
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

  # Filtrar registros usando a heurística estática
  valid_idx <- vapply(seq_len(nrow(df)), function(i) {
    is_funding_opportunity_heuristics(
      title = df$titulo[[i]],
      description = df$descricao_resumida[[i]],
      url = dplyr::coalesce(df$link_detalhe[[i]], df$link_documento_pdf[[i]], df$link_origem[[i]], ""),
      body_text = df$texto_bruto[[i]]
    )
  }, logical(1))
  df <- df[valid_idx, ]
  
  if (nrow(df) == 0) return(ensure_record_schema(tibble::tibble()))

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

collect_listing_with_pagination <- function(source_row, first_url, max_pages = 5, max_records = 15, use_ai = FALSE, log_path = NULL, page_builder = NULL, follow_details = TRUE) {
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

collect_cnpq <- collect_generic_official
collect_capes <- collect_generic_official
collect_finep <- function(source_row, max_pages, max_records, use_ai, log_path) {
  page_builder <- function(page_no) {
    if (page_no <= 1) return(source_row$url_oportunidades[[1]])
    base_url <- source_row$url_oportunidades[[1]]
    offset <- (page_no - 1) * 10
    if (grepl("\\?", base_url)) {
      sprintf("%s&start=%d", base_url, offset)
    } else {
      sprintf("%s?start=%d", base_url, offset)
    }
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
collect_horizon_europe <- collect_generic_official
collect_erc <- collect_generic_official
collect_fapesb <- collect_generic_official

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

collect_all_sources <- function(conn, source_ids = NULL, max_pages = 5, max_records_per_source = 15, use_ai = FALSE, export_dir = "data_exports", log_path = "logs/funding_collection.log", progress_cb = NULL, do_export = TRUE, status_file = "logs/collection_status.json", modal_log_file = "logs/collection_modal_log.txt") {
  ensure_dir(dirname(log_path))
  log_write(log_path, "INFO", "Início da coleta oficial.")

  # Garante caminhos absolutos e define variáveis de ambiente
  if (!grepl("^(/|[A-Za-z]:)", status_file)) status_file <- file.path(getwd(), status_file)
  if (!grepl("^(/|[A-Za-z]:)", modal_log_file)) modal_log_file <- file.path(getwd(), modal_log_file)
  status_file <- normalizePath(status_file, winslash = "/", mustWork = FALSE)
  modal_log_file <- normalizePath(modal_log_file, winslash = "/", mustWork = FALSE)
  
  Sys.setenv(COLLECTION_STATUS_FILE = status_file)
  Sys.setenv(COLLECTION_MODAL_LOG_FILE = modal_log_file)

  log_file <- modal_log_file
  dir.create(dirname(status_file), recursive = TRUE, showWarnings = FALSE)
  try({
    if (file.exists(status_file)) file.remove(status_file)
    if (file.exists(log_file)) file.remove(log_file)
  }, silent = TRUE)

  sources <- tibble::as_tibble(DBI::dbReadTable(conn, "fontes_financiamento"))

  if (!is.null(source_ids) && length(source_ids) > 0) {
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

run_full_collection_cycle <- function(conn, sources_ids = NULL, max_pages = 5, max_records_per_source = 15, use_ai = FALSE, export_dir = "data_exports", log_path = "logs/funding_collection.log", do_export = TRUE) {
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
