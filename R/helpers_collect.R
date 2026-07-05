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


# --- Collector Registry ---
.collector_registry <- new.env(parent = emptyenv())

register_collector <- function(source_id, fn, description = "") {
  assign(source_id, list(fn = fn, description = description), envir = .collector_registry)
}

get_collector <- function(source_id) {
  entry <- get0(source_id, envir = .collector_registry, inherits = FALSE)
  if (is.null(entry)) {
    list(fn = collect_generic_official, description = "Generic HTML scraper")
  } else {
    entry
  }
}

source_dispatch <- function(source_row, max_pages = 5, max_records = 15, use_ai = FALSE, log_path = NULL, conn = NULL) {
  sid <- source_row$id_fonte[[1]]
  collector <- get_collector(sid)
  
  result <- tryCatch(
    collector$fn(source_row, max_pages, max_records, FALSE, log_path),
    error = function(e) {
      log_write(log_path, "ERROR", sprintf("Falha no collector '%s' para %s: %s", 
                collector$description, sid, e$message))
      NULL
    }
  )

  if (isTRUE(use_ai) && !is.null(result$records) && nrow(result$records) > 0) {
    result$records <- enrich_records_parallel(result$records, log_path = log_path, conn = conn)
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
  current_ua <- get_random_ua()
  res <- tryCatch({
    reticulate::py_run_string(sprintf("
def run_playwright_stealth(url):
    from playwright.sync_api import sync_playwright
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                user_agent='%s',
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
"))
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

run_curl <- function(args) {
  curl_bin <- if (.Platform$OS.type == "windows") "curl.exe" else "curl"
  if (.Platform$OS.type == "windows") {
    quoted <- vapply(args, function(a) {
      if (grepl("[&|<>^%]", a) || grepl("\\s", a)) sprintf('"%s"', a) else a
    }, character(1), USE.NAMES = FALSE)
    cmd <- paste(c(curl_bin, quoted), collapse = " ")
    shell(cmd, intern = FALSE)
  } else {
    system2(curl_bin, args, stdout = FALSE, stderr = FALSE)
  }
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

chromote_wait_for_content <- function(session, max_wait = 15, min_wait = 2, check_interval = 0.5) {
  start_time <- Sys.time()
  last_length <- 0L
  stable_count <- 0L
  
  while (as.numeric(Sys.time() - start_time, units = "secs") < max_wait) {
    Sys.sleep(check_interval)
    
    html_length <- tryCatch(
      nchar(session$Runtime$evaluate("document.documentElement.outerHTML")$result$value),
      error = function(e) 0L
    )
    
    if (html_length == last_length && html_length > 0L) {
      stable_count <- stable_count + 1L
      if (stable_count >= 3L) break
    } else {
      stable_count <- 0L
    }
    last_length <- html_length
  }
  
  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
  if (elapsed < min_wait) Sys.sleep(min_wait - elapsed)
  
  invisible(TRUE)
}

safe_request_page <- function(url, log_path = NULL, use_browser_fallback = TRUE, conn = NULL) {
  start_time <- Sys.time()
  .scrape_rate_limiter$wait_if_needed(url)
  if (!is_host_alive(url)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Host offline ou inacessivel: %s. Pulando requisicoes antecipadamente.", url))
    return(list(url = url, html = NULL, text = NA_character_, ok = FALSE, method = "ping_failed"))
  }

  # 1. Tentar httr2 (metodo rapido)
  hdrs <- build_scrape_headers()
  req <- httr2::request(url) |>
    httr2::req_user_agent(hdrs$`User-Agent`) |>
    httr2::req_headers(
      `Accept-Language` = hdrs$`Accept-Language`,
      `Accept` = hdrs$`Accept`,
      `Accept-Encoding` = hdrs$`Accept-Encoding`,
      `Connection` = hdrs$`Connection`,
      `Upgrade-Insecure-Requests` = hdrs$`Upgrade-Insecure-Requests`,
      `Sec-Fetch-Dest` = hdrs$`Sec-Fetch-Dest`,
      `Sec-Fetch-Mode` = hdrs$`Sec-Fetch-Mode`,
      `Sec-Fetch-Site` = hdrs$`Sec-Fetch-Site`,
      `Sec-Fetch-User` = hdrs$`Sec-Fetch-User`,
      `Cache-Control` = hdrs$`Cache-Control`
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
        has_block_signal <- grepl("attention required! \\| cloudflare|cf-challenge|ray id:|checking your browser before accessing|security challenge|access denied", tolower(txt))
        if (!has_block_signal) {
          elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
          if (!is.null(conn)) log_metric(conn, extract_domain(url), "http_latency", elapsed, list(url = url, status = status, method = "httr2", blocked = FALSE))
          return(list(url = url, html = html, text = txt, ok = TRUE, method = "httr2"))
        } else {
          if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("Bloqueio de CDN/CAPTCHA (status %d) detectado via httr2 para %s. Acionando fallbacks...", status, url))
          elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
          if (!is.null(conn)) log_metric(conn, extract_domain(url), "http_latency", elapsed, list(url = url, status = status, method = "httr2", blocked = TRUE))
        }
      }
    }
  }

  # 2. Tentar Playwright (se habilitado/instalado via reticulate)
  if (isTRUE(use_browser_fallback)) {
    pw_res <- safe_request_page_playwright(url, log_path = log_path)
    if (isTRUE(pw_res$ok)) {
      elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
      if (!is.null(conn)) log_metric(conn, extract_domain(url), "http_latency", elapsed, list(url = url, status = 200, method = "playwright", blocked = FALSE))
      return(pw_res)
    }
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
        userAgent = get_random_ua()
      ), silent = TRUE)
      
      try(b$Page$navigate(url), silent = TRUE)
      chromote_wait_for_content(b, 
        max_wait = as.numeric(Sys.getenv("CHROMOTE_MAX_WAIT", "15")),
        min_wait = as.numeric(Sys.getenv("CHROMOTE_MIN_WAIT", "2")),
        check_interval = as.numeric(Sys.getenv("CHROMOTE_CHECK_INTERVAL", "0.5"))
      )
      html_txt <- try(b$Runtime$evaluate("document.documentElement.outerHTML")$result$value, silent = TRUE)
      txt_ok <- !inherits(html_txt, "try-error") && length(html_txt) == 1 && !is.null(html_txt) && !is.na(html_txt) && nzchar(html_txt)
      if (txt_ok) {
        has_block <- grepl("attention required! \\| cloudflare|cf-challenge|ray id:|checking your browser before accessing|security challenge|access denied", tolower(html_txt))
        if (has_block) {
          if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Bloqueio de CDN/CAPTCHA detectado via Chromote para %s.", url))
        } else {
          html <- try(xml2::read_html(html_txt), silent = TRUE)
          if (!inherits(html, "try-error")) {
            elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
            if (!is.null(conn)) log_metric(conn, extract_domain(url), "http_latency", elapsed, list(url = url, status = 200, method = "chromote_stealth", blocked = FALSE))
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
  .scrape_rate_limiter$wait_if_needed(pdf_url)
  tf <- tempfile(fileext = ".pdf")
  hdrs <- build_scrape_headers()
  ok <- try({
    req <- httr2::request(pdf_url) |>
      httr2::req_user_agent(hdrs$`User-Agent`) |>
      httr2::req_headers(
        `Accept` = "application/pdf,*/*",
        `Accept-Language` = hdrs$`Accept-Language`,
        `Accept-Encoding` = hdrs$`Accept-Encoding`
      ) |>
      httr2::req_timeout(20)
    resp <- httr2::req_perform(req, path = tf)
    ct <- httr2::resp_header(resp, "Content-Type") %||% ""
    if (!grepl("pdf|octet-stream", ct, ignore.case = TRUE) && file.exists(tf)) {
      if (file.info(tf)$size < 500) {
        txt_content <- try(readLines(tf, warn = FALSE), silent = TRUE)
        if (!inherits(txt_content, "try-error") && any(grepl("html|login|captcha|cloudflare", txt_content, ignore.case = TRUE))) {
          if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("PDF download retornou HTML/CAPTCHA para %s", pdf_url))
          unlink(tf)
          return(NA_character_)
        }
      }
    }
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

  inferred <- character()
  apply_ai_fields_to_df(ai, record, 1L, inferred)
  record$campos_inferidos_ia <- paste(unique(inferred), collapse = "; ")
  record
}

enrich_records_parallel <- function(df, log_path = NULL, conn = NULL) {
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

  # Prepara prompts (usando função unificada de helpers_ai.R)
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

    prompts[[idx]] <- build_extraction_prompt(text, current_info)
  }

  # Executa em lotes (tamanho adaptativo por provedor)
  batch_cfg <- get_ai_batch_config()
  batch_size <- batch_cfg$batch_size

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

    batch_res <- lapply(prompts[batch_idx], function(p) {
      ai_request_with_fallback(p, log_path = log_path, conn = conn)
    })
    raw_results[batch_idx] <- batch_res

    # Atraso entre lotes (configurável por provedor)
    if (b < length(batches) && batch_cfg$delay_between > 0) {
      Sys.sleep(batch_cfg$delay_between)
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
      apply_ai_fields_to_df(ai, df, i, inferred)
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

finalize_records <- function(df, fonte_oficial = NULL) {
  if (is.null(df) || nrow(df) == 0) return(ensure_record_schema(tibble::tibble()))
  df <- ensure_record_schema(df)

  # Verificar se e fonte EU (HEU/ERC)
  is_eu <- !is.null(fonte_oficial) && fonte_oficial %in% c("horizon_europe", "erc")

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

  # Filtrar para manter apenas editais do ano corrente (Requisito 3)
  current_year_idx <- vapply(seq_len(nrow(df)), function(i) {
    is_current_year_record(
      pub_date_str = df$data_publicacao[[i]],
      limit_date_str = df$data_limite[[i]],
      title = df$titulo[[i]],
      text = df$texto_bruto[[i]],
      is_eu_source = is_eu
    )
  }, logical(1))
  df <- df[current_year_idx, ]
  
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

collect_capes <- function(source_row, max_pages, max_records, use_ai, log_path) {
  base_api <- "https://www.gov.br/capes/++api++/pt-br/@search"
  page_url <- source_row$url_oportunidades[[1]]

  # --- ETAPA 1: Tentar API Plone REST ---
  log_progress("CAPES: Tentando API Plone REST...", "Scraping")
  all_items <- list()
  b_start <- 0L
  page_size <- 50L

  while (length(all_items) < max_records && b_start < max_pages * page_size) {
    url <- sprintf("%s?path=/pt-br/centrais-de-conteudo/editais&sort_on=effective&sort_order=descending&b_start=%d&b_size=%d", base_api, b_start, page_size)
    hdrs <- build_scrape_headers()
    req <- httr2::request(url) |>
      httr2::req_user_agent(hdrs$`User-Agent`) |>
      httr2::req_headers(
        `Accept` = "application/json,*/*",
        `Accept-Language` = hdrs$`Accept-Language`
      ) |>
      httr2::req_timeout(10)
    resp <- tryCatch(httr2::req_perform(req), error = function(e) {
      log_progress(sprintf("CAPES: API Plone falhou: %s", conditionMessage(e)), "Scraping")
      NULL
    })
    if (is.null(resp) || httr2::resp_status(resp) != 200) break

    data <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
    if (is.null(data) || length(data$items) == 0) break

    all_items <- c(all_items, data$items)
    if (is.null(data$batching[["next"]])) break
    b_start <- b_start + page_size
  }

  if (length(all_items) > 0) {
    log_progress(sprintf("CAPES: API Plone retornou %d itens. Filtrando...", length(all_items)), "Scraping")

    filtered <- Filter(function(item) {
      if (item$mime_type != "application/pdf") return(FALSE)
      title <- tolower(item$title %||% "")
      if (nchar(title) < 10) return(FALSE)
      if (grepl("altera|retifica|prorroga|resultado|errata|anexo|ata\\s|lista|planilha|formulario|termo", title)) return(FALSE)
      TRUE
    }, all_items)

    if (length(filtered) > max_records) filtered <- filtered[seq_len(max_records)]

    if (length(filtered) > 0) {
      log_progress(sprintf("CAPES: %d editais válidos após filtro.", length(filtered)), "Scraping")
      recs <- purrr::map_dfr(filtered, function(item) {
        pdf_url <- paste0(item$`@id`, "/@@display-file/file")
        pub_date <- item$effective %||% NA_character_
        if (!is.na(pub_date) && nzchar(pub_date)) {
          pub_date <- as.character(as.Date(substr(pub_date, 1, 10)))
        } else {
          pub_date <- NA_character_
        }
        
        # Download PDF and extract text to get real content
        pdf_txt <- extract_text_from_pdf(pdf_url, log_path = log_path)
        clean_title <- clean_edital_title(item$title %||% basename(item$`@id`))
        summary_txt <- if (!is.na(pdf_txt) && nzchar(pdf_txt)) {
          stringr::str_squish(stringr::str_sub(pdf_txt, 1, 900))
        } else {
          clean_title
        }

        rec <- extract_core_record(
          source_row = source_row,
          input_title = clean_title,
          input_summary = summary_txt,
          input_full_text = pdf_txt %||% clean_title,
          page_url = page_url,
          detail_url = item$`@id`,
          pdf_url = pdf_url,
          page_no = 1L
        )
        if (!is.na(pub_date)) rec$data_publicacao <- pub_date
        rec
      })
      pages_visited <- ceiling(b_start / page_size)
      return(list(records = finalize_records(recs), pages_visited = max(1L, pages_visited), last_url = base_api))
    }
  }

  # --- ETAPA 2: Fallback Playwright ---
  log_progress("CAPES: API Plone indisponível. Usando Playwright...", "Scraping")
  pg <- safe_request_page(page_url, log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    log_progress("CAPES: Playwright também falhou.", "Scraping")
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 0L, last_url = page_url))
  }

  log_progress("CAPES: Playwright renderizou a página. Extraindo candidatos...", "Scraping")
  candidates <- extract_listing_candidates(pg$html, page_url, source_row)
  log_progress(sprintf("CAPES: %d candidatos extraídos via Playwright.", nrow(candidates)), "Scraping")

  if (nrow(candidates) == 0) {
    return(list(records = ensure_record_schema(tibble::tibble()), pages_visited = 1L, last_url = page_url))
  }

  recs <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
    detail_url <- candidates$detail_url[[i]]
    pdf_url <- candidates$pdf_url[[i]]

    detail_bundle <- extract_detail_bundle(
      detail_url = detail_url,
      page_url = page_url,
      pdf_url = pdf_url,
      log_path = log_path
    )

    extract_core_record(
      source_row = source_row,
      input_title = pick_first_nonempty(detail_bundle$detail_title, candidates$candidate_title[[i]]),
      input_summary = pick_first_nonempty(detail_bundle$detail_summary, candidates$candidate_summary[[i]]),
      input_full_text = detail_bundle$full_text,
      page_url = page_url,
      detail_url = detail_url,
      pdf_url = detail_bundle$pdf_url,
      page_no = 1L
    )
  })

  list(records = finalize_records(recs), pages_visited = 1L, last_url = page_url)
}

collect_finep <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta oportunidades da FINEP via API REST pública (Liferay Headless Delivery)
  #' Filtra automaticamente por: situação = Aberta

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[FINEP][%s] %s", level, msg))
  }

  base_url <- "https://www.finep.gov.br/o/c/chamadapublicas"
  page_size <- 250
  all_items <- list()
  page <- 1
  total_count <- NULL

  .log("INFO", "Iniciando coleta FINEP via API REST...")
  
  repeat {
    # Construir URL da página
    url <- sprintf("%s?sort=dataDePublicacao:desc&page=%d&pageSize=%d", base_url, page, page_size)
    
    .log("INFO", sprintf("Buscando página %d: %s", page, url))
    
    # Fazer requisição GET
    response <- tryCatch({
      httr::GET(url, httr::timeout(60))
    }, error = function(e) {
      .log("ERROR", sprintf("Erro na requisição: %s", e$message))
      NULL
    })
    
    if (is.null(response) || httr::status_code(response) != 200) {
      .log("WARN", "Falha na requisição, interrompendo paginação")
      break
    }
    
    # Parsear JSON
    data <- tryCatch({
      httr::content(response, as = "parsed", type = "application/json")
    }, error = function(e) {
      .log("ERROR", sprintf("Erro ao parsear JSON: %s", e$message))
      NULL
    })
    
    if (is.null(data) || is.null(data$items)) {
      .log("WARN", "Resposta vazia ou inválida")
      break
    }
    
    # Atualizar total na primeira página
    if (is.null(total_count)) {
      total_count <- data$totalCount
      .log("INFO", sprintf("Total de registros: %d", total_count))
    }
    
    # Filtrar itens: situação Aberta (inclui ICT e outros públicos)
    filtered_items <- Filter(function(item) {
      # Verificar se situação é aberta
      is_aberta <- !is.null(item$situacao) && item$situacao$key == "aberta"
      is_aberta
    }, data$items)
    
    all_items <- c(all_items, filtered_items)
    
    .log("INFO", sprintf("Página %d: %d itens total, %d filtrados (Aberta)", 
                                         page, length(data$items), length(filtered_items)))
    
    # Verificar se chegou ao fim
    if (length(data$items) < page_size || page >= ceiling(total_count / page_size)) {
      break
    }
    
    # Limite de páginas
    if (page >= max_pages) {
      .log("WARN", sprintf("Limite de %d páginas atingido", max_pages))
      break
    }
    
    page <- page + 1
    
    # Rate limiting
    Sys.sleep(0.5)
  }
  
  .log("INFO", sprintf("Total de itens coletados (Aberta): %d", length(all_items)))
  
  # Limitar ao max_records
  if (length(all_items) > max_records) {
    all_items <- all_items[1:max_records]
    .log("WARN", sprintf("Limitado a %d registros", max_records))
  }
  
  # Converter para tibble no formato esperado
  if (length(all_items) == 0) {
    .log("WARN", "Nenhum item encontrado após filtros")
    return(list(records = tibble::tibble(), pages_visited = as.integer(page - 1L), last_url = NA_character_))
  }
  
  records <- lapply(all_items, function(item) {
    # Montar link de detalhe
    link_detalhe <- sprintf("https://www.finep.gov.br/e/chamada-publica/222684/%d", item$id)
    
    # Extrair datas
    data_publicacao <- if (!is.null(item$dataDePublicacao)) {
      as.character(as.Date(sub("T.*", "", item$dataDePublicacao)))
    } else NA_character_
    
    data_limite <- if (!is.null(item$prazoProposto)) {
      as.character(as.Date(sub("T.*", "", item$prazoProposto)))
    } else NA_character_
    
    # Extrair público alvo
    publico_alvo <- if (length(item$publicoAlvo) > 0) {
      paste(sapply(item$publicoAlvo, function(pa) pa$name), collapse = "; ")
    } else NA_character_
    
    # Extrair tema
    tema <- if (!is.null(item$temaPrincipal) && !is.null(item$temaPrincipal$name)) {
      item$temaPrincipal$name
    } else NA_character_
    
    # Extrair região
    regiao <- if (!is.null(item$regiao) && !is.null(item$regiao$name)) {
      item$regiao$name
    } else NA_character_
    
    # Tipo de oportunidade
    tipo_oportunidade <- if (!is.null(item$tipoDeOportunidade) && !is.null(item$tipoDeOportunidade$name)) {
      item$tipoDeOportunidade$name
    } else NA_character_
    
    # Contrapartida
    contrapartida <- if (!is.null(item$contrapartida) && !is.null(item$contrapartida$name)) {
      item$contrapartida$name
    } else NA_character_
    
    # Criar hash de deduplicação
    hash_input <- paste0(item$titulo, "|", link_detalhe)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")
    
    # Montar registro no schema padrão
    tibble::tibble(
      id_registro = sprintf("finep_%s", substr(hash_dedup, 1, 16)),
      entidade = "FINEP",
      pais_origem = "Brasil",
      titulo = item$titulo,
      subtitulo = NA_character_,
      descricao_resumida = substr(item$descricaoRawText, 1, 500),
      descricao_completa = item$descricaoRawText,
      tipo_oportunidade = tipo_oportunidade,
      modalidade = NA_character_,
      area_tematica = tema,
      palavras_chave = NA_character_,
      elegibilidade = NA_character_,
      publico_alvo = publico_alvo,
      nivel_academico = NA_character_,
      instituicao_financiadora = "Financiadora de Estudos e Projetos - FINEP",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = data_publicacao,
      data_abertura = NA_character_,
      data_limite = data_limite,
      data_encerramento = NA_character_,
      status_oportunidade = "aberto",
      link_origem = "https://www.finep.gov.br/oportunidades",
      link_detalhe = link_detalhe,
      link_documento_pdf = NA_character_,
      idioma = "pt",
      localidade = regiao,
      observacoes = contrapartida,
      texto_bruto = item$descricaoRawText,
      pagina_coletada = 1L,
      fonte_oficial = "finep",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )
  })
  
  df <- dplyr::bind_rows(records)
  
  .log("INFO", sprintf("FINEP: %d registros finais coletados", nrow(df)))
  
  return(list(records = df, pages_visited = as.integer(page - 1L), last_url = url))
}

collect_horizon_europe <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta oportunidades Horizon Europe via API REST pública (EU F&T Portal Search API)
  #' Busca múltiplos termos HORIZON (CL1-CL5, EIC, MSCA, WIDERA)
  #' Usa form-data filter para frameworkProgramme=43108390 + pós-filtro para status != Closed
  #' Foca em chamadas elegíveis para não-membros EU (como Brasil)
  #' NOTA: A API ignora filtros JSON no body — usa form-data + pós-processamento

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[HEU][%s] %s", level, msg))
  }

  api_url <- "https://api.tech.ec.europa.eu/search-api/prod/rest/search"
  all_items <- list()
  seen_ids <- character(0)

  # Query filter para HEU (frameworkProgramme=43108390) via form-data
  heu_query <- '{"bool":{"must":[{"terms":{"frameworkProgramme":["43108390"]}}]}}'

  # Múltiplos termos de busca para cobrir diferentes áreas HEU
  # Usa padrões de callIdentifier que retornam chamadas abertas (status 31094501/31094502)
  # NOTA: Termos genéricos como "HORIZON" retornam FAQ items (SEDIA_FAQ), não tópicos (SEDIA)
  search_terms <- c(
    "HORIZON-EIC-2026-PRIZE",
    "HORIZON-EIC-2026-ACCELERATOR",
    "HORIZON-EIC-2026-PATHFINDER",
    "HORIZON-MSCA-2026-PF",
    "HORIZON-MSCA-2026-DN",
    "HORIZON-MSCA-2026-POSTDOC",
    "HORIZON-MSCA-2026-DOCTORAL",
    "HORIZON-WIDERA-ERC-POC",
    "HORIZON-WIDERA-ERC-ADG",
    "HORIZON-WIDERA-TWINNING",
    "HORIZON-WIDERA-2026-NCP",
    "HORIZON-WIDERA-2026-COFUND",
    "HORIZON-CL3-2026",
    "HORIZON-CL5-2026",
    "HORIZON-CL2-2026",
    "HORIZON-CL4-2026-HUMAN",
    "HORIZON-CL5-2026-ENERGY",
    "HORIZON-CL5-2026-CLIMATE",
    "HORIZON-CL2-2026-CULTURE",
    "HORIZON-CL3-2026-SECURITY",
    "HORIZON-EURATOM-2026"
  )

  .log("INFO", "Iniciando coleta Horizon Europe via API REST...")

  for (term in search_terms) {
    .log("INFO", sprintf("Buscando termo: %s", term))

    search_text <- utils::URLencode(term, reserved = TRUE)
    url <- sprintf("%s?apiKey=SEDIA&text=%s&pageNumber=1&pageSize=100&sortBy=es_SortDate&orderBy=DESC",
                   api_url, search_text)
    tmp_file <- tempfile(fileext = ".json")

    # Usar form-data (--data-urlencode) em vez de JSON body (-d)
    # O JSON body é ignorado pela API; form-data funciona com termos específicos
    curl_args <- c(
      "-s", "--max-time", "60",
      "-X", "POST", url,
      "-H", "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
      "-H", "Referer: https://ec.europa.eu/info/funding-tenders/opportunities/portal/",
      "-H", "Origin: https://ec.europa.eu",
      "-H", "Accept: application/json, text/plain, */*",
      "-H", "Content-Type: application/x-www-form-urlencoded",
      "--data-urlencode", paste0("query=", heu_query),
      "-o", tmp_file
    )

    exit_code <- tryCatch(
      run_curl(curl_args),
      error = function(e) {
        .log("ERROR", sprintf("Erro ao executar curl para '%s': %s", term, e$message))
        1
      }
    )

    # Verificar se o arquivo foi criado
    if (!file.exists(tmp_file) || file.size(tmp_file) == 0) {
      .log("WARN", sprintf("Falha na requisição para '%s' (arquivo não criado)", term))
      next
    }

    data <- tryCatch({
      jsonlite::fromJSON(tmp_file, simplifyVector = FALSE)
    }, error = function(e) {
      .log("ERROR", sprintf("Erro ao parsear JSON para '%s': %s", term, e$message))
      NULL
    })

    if (is.null(data) || is.null(data$results)) {
      .log("WARN", sprintf("Resposta vazia ou inválida para '%s'", term))
      next
    }

    .log("INFO", sprintf("Termo '%s': %d resultados brutos", term, length(data$results)))

    # Pós-filtrar: manter apenas tópicos HEU com status Open/Forthcoming
    n_filtered <- 0
    for (item in data$results) {
      n_filtered <- n_filtered + 1
      md <- item$metadata
      if (is.null(md)) next
      if (is.data.frame(md)) md <- as.list(md)

      # Verificar DATASOURCE = "SEDIA" (topics, não projetos)
      ds <- tryCatch({
        d <- md$DATASOURCE
        if (!is.null(d)) { if (is.list(d)) d[[1]] else d[1] } else NA
      }, error = function(e) NA)
      if (is.na(ds) || ds != "SEDIA") next

      # Verificar frameworkProgramme = 43108390 (Horizon Europe)
      fp <- tryCatch({
        f <- md$frameworkProgramme
        if (!is.null(f)) { if (is.list(f)) f[[1]] else f[1] } else NA
      }, error = function(e) NA)
      if (is.na(fp) || !grepl("43108390", fp)) next

      # Excluir status Closed (31094503)
      st <- tryCatch({
        s <- md$status
        if (!is.null(s)) { if (is.list(s)) s[[1]] else s[1] } else NA
      }, error = function(e) NA)
      if (!is.na(st) && length(st) > 0 && grepl("31094503", st)) next

      all_items <- c(all_items, list(item))
    }

    .log("INFO", sprintf("Termo '%s': %d itens HEU acumulados (brutos)", term, length(all_items)))

    if (length(all_items) >= max_records * 5) break
    Sys.sleep(0.5)
  }

  # Deduplicar por callIdentifier — preferir versão em inglês
  .log("INFO", sprintf("Deduplicando %d itens brutos...", length(all_items)))
  dedup_map <- list()
  for (item in all_items) {
    md <- tryCatch({
      m <- item$metadata
      if (is.null(m)) next
      if (is.data.frame(m)) m <- as.list(m)
      m
    }, error = function(e) NULL)
    if (is.null(md)) next

    call_id <- tryCatch({
      if (!is.null(md$callIdentifier)) {
        v <- md$callIdentifier
        if (is.list(v)) v[[1]] else v[1]
      } else NA_character_
    }, error = function(e) NA_character_)
    if (is.na(call_id) || length(call_id) == 0) next

    titulo <- tryCatch({
      if (!is.null(md$title)) {
        v <- md$title
        if (is.list(v)) v[[1]] else v[1]
      } else ""
    }, error = function(e) "")
    if (length(titulo) == 0) titulo <- ""
    # Detectar se titulo contem caracteres nao-ASCII (indica idioma local, nao ingles)
    is_english <- tryCatch(
      !is.na(titulo) && is.character(titulo) && !grepl("[^\x01-\x7F]", titulo),
      error = function(e) FALSE
    )

    if (is.null(dedup_map[[call_id]])) {
      dedup_map[[call_id]] <- list(item = item, is_english = is_english)
    } else if (is_english && !dedup_map[[call_id]]$is_english) {
      dedup_map[[call_id]] <- list(item = item, is_english = TRUE)
      .log("INFO", sprintf("Substituído '%s' por versão em inglês", call_id))
    }
  }
  all_items <- lapply(dedup_map, function(x) x$item)
  .log("INFO", sprintf("Após deduplicação: %d itens únicos", length(all_items)))

  .log("INFO", sprintf("Total de itens HEU coletados: %d", length(all_items)))

  if (length(all_items) > max_records) {
    all_items <- all_items[1:max_records]
    .log("WARN", sprintf("Limitado a %d registros", max_records))
  }

  if (length(all_items) == 0) {
    .log("WARN", "Nenhum item HEU encontrado")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = api_url))
  }

  # Helper seguro para extrair campo de metadata
  safe_extract <- function(x, default = NA_character_) {
    tryCatch({
      if (is.null(x)) return(default)
      val <- if (is.list(x)) x[[1]] else x[1]
      if (length(val) == 0) return(default)
      if (is.null(val)) return(default)
      if (is.na(val)) return(default)
      as.character(val)
    }, error = function(e) default)
  }

  record_list <- list()
  for (i in seq_along(all_items)) {
    item <- all_items[[i]]
    rec <- tryCatch({
    md <- item$metadata
    # Converter data.frame para lista se necessário
    if (is.data.frame(md)) md <- as.list(md)

    # Extrair campos do metadata
    titulo <- safe_extract(md$title)
    call_id <- safe_extract(md$callIdentifier)
    descricao_html <- safe_extract(md$descriptionByte)

    # Limpar HTML da descrição
    descricao_text <- gsub("<[^>]+>", " ", descricao_html)
    descricao_text <- gsub("&amp;", "&", descricao_text)
    descricao_text <- gsub("&nbsp;", " ", descricao_text)
    descricao_text <- gsub("\\s+", " ", trimws(descricao_text))

    # Datas
    data_abertura <- safe_extract(md$startDate)
    if (!is.na(data_abertura)) {
      data_abertura <- as.character(as.Date(sub("T.*", "", data_abertura)))
    }

    data_limite <- safe_extract(md$deadlineDate)
    if (!is.na(data_limite)) {
      data_limite <- as.character(as.Date(sub("T.*", "", data_limite)))
    }

    # Status
    status_code <- safe_extract(md$status)
    status <- if (!is.na(status_code)) {
      if (grepl("31094501", status_code)) "aberto"
      else if (grepl("31094502", status_code)) "aberto"
      else if (grepl("31094503", status_code)) "encerrado"
      else "desconhecido"
    } else "desconhecido"

    # Programa
    programa <- safe_extract(md$esST_programAbbreviation)

    # Tipo de ação
    tipo_acao <- safe_extract(md$typesOfAction)

    # Budget (extrair do budgetOverview JSON)
    budget <- NA_real_
    budget_raw <- safe_extract(md$budgetOverview)
    if (!is.na(budget_raw)) {
      budget_json <- tryCatch(jsonlite::fromJSON(budget_raw, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(budget_json$budgetTopicActionMap)) {
        for (key in names(budget_json$budgetTopicActionMap)) {
          actions <- budget_json$budgetTopicActionMap[[key]]
          for (act in actions) {
            if (!is.null(act$budgetYearMap)) {
              for (yr in names(act$budgetYearMap)) {
                val <- suppressWarnings(as.numeric(act$budgetYearMap[[yr]]))
                if (!is.na(val)) budget <- val
              }
            }
          }
        }
      }
    }

    # URL de detalhe
    link_detalhe <- safe_extract(md$esST_URL, default = item$url)

    # Hash de deduplicação
    hash_input <- paste0(call_id, "|", titulo)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    # Garantir que descricao_resumida nunca seja NA ou vazia
    resumo_final <- if (!is.na(descricao_text) && nzchar(descricao_text) && nchar(descricao_text) > 10) {
      substr(descricao_text, 1, 500)
    } else {
      titulo  # Fallback: usar o titulo como resumo
    }

    tibble::tibble(
      id_registro = sprintf("heu_%s", substr(hash_dedup, 1, 16)),
      entidade = "Horizon Europe",
      pais_origem = "União Europeia",
      titulo = titulo,
      subtitulo = call_id,
      descricao_resumida = resumo_final,
      descricao_completa = descricao_text,
      tipo_oportunidade = tipo_acao,
      modalidade = NA_character_,
      area_tematica = programa,
      palavras_chave = call_id,
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "European Commission",
      valor_financiado = budget,
      moeda = if (!is.na(budget) && budget > 0) "EUR" else NA_character_,
      data_publicacao = data_abertura,
      data_abertura = data_abertura,
      data_limite = data_limite,
      data_encerramento = NA_character_,
      status_oportunidade = status,
      link_origem = "https://ec.europa.eu/info/funding-tenders/opportunities/portal/",
      link_detalhe = link_detalhe,
      link_documento_pdf = NA_character_,
      idioma = "en",
      localidade = NA_character_,
      observacoes = NA_character_,
      texto_bruto = paste(titulo, descricao_text, sep = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "horizon_europe",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )
    }, error = function(e) {
      .log("WARN", sprintf("Erro ao processar item %d: %s", i, e$message))
      NULL
    })
    if (!is.null(rec)) record_list[[length(record_list) + 1]] <- rec
  }

  if (length(record_list) == 0) {
    .log("WARN", "Nenhum registro válido extraído")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = api_url))
  }

  records <- dplyr::bind_rows(record_list)

  .log("INFO", sprintf("HEU: %d registros finais coletados", nrow(records)))

  result <- list(records = records, pages_visited = length(search_terms), last_url = api_url)
  .log("INFO", sprintf("Retornando lista com %d registros", length(result$records)))
  return(result)
}

collect_erc <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta oportunidades do ERC via API REST pública (EU F&T Portal Search API)
  #' Busca múltiplos termos ("ERC 2026", "ERC StG", "ERC AdG", "ERC PoC", "ERC CoG")
  #' Usa form-data filter para frameworkProgramme=43108390 + pós-filtro para programmeDivision=43108406
  #' NOTA: A API ignora filtros JSON no body — usa form-data + pós-processamento

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[ERC][%s] %s", level, msg))
  }

  api_url <- "https://api.tech.ec.europa.eu/search-api/prod/rest/search"
  all_items <- list()
  seen_ids <- character(0)

  # Query filter para HEU (frameworkProgramme=43108390) via form-data
  heu_query <- '{"bool":{"must":[{"terms":{"frameworkProgramme":["43108390"]}}]}}'

  # Múltiplos termos de busca para cobrir diferentes chamadas ERC
  # "ERC 2026" e "ERC StG 2026" retornam itens CLOSED; os termos abaixo encontram itens abertos
  search_terms <- c("ERC AdG 2026", "ERC PoC 2026")

  .log("INFO", "Iniciando coleta ERC via API REST...")

  for (term in search_terms) {
    .log("INFO", sprintf("Buscando termo: %s", term))

    search_text <- utils::URLencode(term, reserved = TRUE)
    url <- sprintf("%s?apiKey=SEDIA&text=%s&pageNumber=1&pageSize=100&sortBy=es_SortDate&orderBy=DESC",
                   api_url, search_text)
    tmp_file <- tempfile(fileext = ".json")
    on.exit(unlink(tmp_file), add = TRUE)

    # Usar form-data (--data-urlencode) em vez de JSON body (-d)
    # O JSON body é ignorado pela API; form-data funciona com termos específicos
    curl_args <- c(
      "-s", "--max-time", "60",
      "-X", "POST", url,
      "-H", "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
      "-H", "Referer: https://ec.europa.eu/info/funding-tenders/opportunities/portal/",
      "-H", "Origin: https://ec.europa.eu",
      "-H", "Accept: application/json, text/plain, */*",
      "-H", "Content-Type: application/x-www-form-urlencoded",
      "--data-urlencode", paste0("query=", heu_query),
      "-o", tmp_file
    )

    exit_code <- tryCatch(
      run_curl(curl_args),
      error = function(e) {
        .log("ERROR", sprintf("Erro ao executar curl para '%s': %s", term, e$message))
        1
      }
    )

    # Verificar se o arquivo foi criado
    if (!file.exists(tmp_file) || file.size(tmp_file) == 0) {
      .log("WARN", sprintf("Falha na requisição para '%s' (arquivo não criado)", term))
      next
    }

    data <- tryCatch({
      jsonlite::fromJSON(tmp_file, simplifyVector = FALSE)
    }, error = function(e) {
      .log("ERROR", sprintf("Erro ao parsear JSON para '%s': %s", term, e$message))
      NULL
    })

    if (is.null(data) || is.null(data$results)) {
      .log("WARN", sprintf("Resposta vazia ou inválida para '%s'", term))
      next
    }

    .log("INFO", sprintf("Termo '%s': %d resultados brutos", term, length(data$results)))

    # Pós-filtrar: manter apenas tópicos ERC do Horizon Europe
    for (item in data$results) {
      md <- item$metadata
      if (is.null(md)) next
      if (is.data.frame(md)) md <- as.list(md)

      # Verificar DATASOURCE = "SEDIA" (topics, não projetos)
      ds <- md$DATASOURCE
      if (!is.null(ds)) {
        ds_val <- if (is.list(ds)) ds[[1]] else ds[1]
        if (is.na(ds_val) || ds_val != "SEDIA") next
      } else next

      # Verificar frameworkProgramme = 43108390 (Horizon Europe)
      fp <- md$frameworkProgramme
      if (!is.null(fp)) {
        fp_val <- if (is.list(fp)) fp[[1]] else fp[1]
        if (is.na(fp_val) || !grepl("43108390", fp_val)) next
      } else next

      # Verificar programmeDivision contém 43108406 (ERC)
      pd <- md$programmeDivision
      if (!is.null(pd)) {
        pd_vals <- if (is.list(pd)) unlist(pd) else pd
        if (!any(grepl("43108406", pd_vals))) next
      } else next

      # Excluir status Closed (31094503)
      status <- md$status
      if (!is.null(status)) {
        status_val <- if (is.list(status)) status[[1]] else status[1]
        if (!is.na(status_val) && grepl("31094503", status_val)) next
      }

      all_items <- c(all_items, list(item))
    }

    .log("INFO", sprintf("Termo '%s': %d itens ERC acumulados (brutos)", term, length(all_items)))

    if (length(all_items) >= max_records * 5) break
    Sys.sleep(0.5)
  }

  # Deduplicar por callIdentifier — preferir versão em inglês
  .log("INFO", sprintf("Deduplicando %d itens brutos...", length(all_items)))
  dedup_map <- list()
  for (item in all_items) {
    md <- item$metadata
    if (is.null(md)) next
    if (is.data.frame(md)) md <- as.list(md)
    call_id <- if (!is.null(md$callIdentifier)) {
      v <- md$callIdentifier; if (is.list(v)) v[[1]] else v[1]
    } else NA_character_
    if (is.na(call_id)) next

    titulo <- if (!is.null(md$title)) {
      v <- md$title; if (is.list(v)) v[[1]] else v[1]
    } else ""
    # Detectar se titulo contem caracteres nao-ASCII (indica idioma local, nao ingles)
    is_english <- !is.na(titulo) && is.character(titulo) && !grepl("[^\x01-\x7F]", titulo)

    if (is.null(dedup_map[[call_id]])) {
      dedup_map[[call_id]] <- list(item = item, is_english = is_english)
    } else if (is_english && !dedup_map[[call_id]]$is_english) {
      dedup_map[[call_id]] <- list(item = item, is_english = TRUE)
      .log("INFO", sprintf("Substituído '%s' por versão em inglês", call_id))
    }
  }
  all_items <- lapply(dedup_map, function(x) x$item)
  .log("INFO", sprintf("Após deduplicação: %d itens únicos", length(all_items)))

  .log("INFO", sprintf("Total de itens ERC coletados: %d", length(all_items)))

  if (length(all_items) > max_records) {
    all_items <- all_items[1:max_records]
    .log("WARN", sprintf("Limitado a %d registros", max_records))
  }

  if (length(all_items) == 0) {
    .log("WARN", "Nenhum item ERC encontrado")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = api_url))
  }

  records <- purrr::map_dfr(all_items, function(item) {
    md <- item$metadata
    # Converter data.frame para lista se necessário
    if (is.data.frame(md)) md <- as.list(md)

    # Extrair campos do metadata (helper para extrair valor de lista/data.frame)
    extract_field <- function(x, default = NA_character_) {
      if (is.null(x)) return(default)
      val <- if (is.list(x)) x[[1]] else x[1]
      if (is.na(val)) return(default)
      as.character(val)
    }

    # Extrair campos do metadata
    titulo <- extract_field(md$title)
    call_id <- extract_field(md$callIdentifier)
    descricao_html <- extract_field(md$descriptionByte)

    # Limpar HTML da descrição
    descricao_text <- gsub("<[^>]+>", " ", descricao_html)
    descricao_text <- gsub("&amp;", "&", descricao_text)
    descricao_text <- gsub("&nbsp;", " ", descricao_text)
    descricao_text <- gsub("\\s+", " ", trimws(descricao_text))

    # Datas
    data_abertura <- extract_field(md$startDate)
    if (!is.na(data_abertura)) {
      data_abertura <- as.character(as.Date(sub("T.*", "", data_abertura)))
    }

    data_limite <- extract_field(md$deadlineDate)
    if (!is.na(data_limite)) {
      data_limite <- as.character(as.Date(sub("T.*", "", data_limite)))
    }

    # Status
    status_code <- extract_field(md$status)
    status <- if (!is.na(status_code)) {
      if (grepl("31094501", status_code)) "aberto"
      else if (grepl("31094502", status_code)) "aberto"
      else if (grepl("31094503", status_code)) "encerrado"
      else "desconhecido"
    } else "desconhecido"

    # Programa
    programa <- extract_field(md$esST_programAbbreviation)

    # Tipo de ação
    tipo_acao <- extract_field(md$typesOfAction)

    # Budget (extrair do budgetOverview JSON)
    budget <- NA_real_
    budget_raw <- extract_field(md$budgetOverview)
    if (!is.na(budget_raw)) {
      budget_json <- tryCatch(jsonlite::fromJSON(budget_raw, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(budget_json$budgetTopicActionMap)) {
        for (key in names(budget_json$budgetTopicActionMap)) {
          actions <- budget_json$budgetTopicActionMap[[key]]
          for (act in actions) {
            if (!is.null(act$budgetYearMap)) {
              for (yr in names(act$budgetYearMap)) {
                val <- suppressWarnings(as.numeric(act$budgetYearMap[[yr]]))
                if (!is.na(val)) budget <- val
              }
            }
          }
        }
      }
    }

    # URL de detalhe
    link_detalhe <- extract_field(md$esST_URL, default = item$url)

    # Hash de deduplicação
    hash_input <- paste0(call_id, "|", titulo)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    # Garantir que descricao_resumida nunca seja NA ou vazia
    resumo_final <- if (!is.na(descricao_text) && nzchar(descricao_text) && nchar(descricao_text) > 10) {
      substr(descricao_text, 1, 500)
    } else {
      titulo  # Fallback: usar o titulo como resumo
    }

    tibble::tibble(
      id_registro = sprintf("erc_%s", substr(hash_dedup, 1, 16)),
      entidade = "ERC",
      pais_origem = "União Europeia",
      titulo = titulo,
      subtitulo = call_id,
      descricao_resumida = resumo_final,
      descricao_completa = descricao_text,
      tipo_oportunidade = tipo_acao,
      modalidade = NA_character_,
      area_tematica = programa,
      palavras_chave = call_id,
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "European Research Council",
      valor_financiado = budget,
      moeda = if (!is.na(budget) && budget > 0) "EUR" else NA_character_,
      data_publicacao = data_abertura,
      data_abertura = data_abertura,
      data_limite = data_limite,
      data_encerramento = NA_character_,
      status_oportunidade = status,
      link_origem = "https://erc.europa.eu/",
      link_detalhe = link_detalhe,
      link_documento_pdf = NA_character_,
      idioma = "en",
      localidade = NA_character_,
      observacoes = NA_character_,
      texto_bruto = paste(titulo, descricao_text, sep = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "erc",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )
  })

  .log("INFO", sprintf("ERC: %d registros finais coletados", nrow(records)))

  return(list(records = records, pages_visited = length(search_terms), last_url = api_url))
}
collect_fapesb <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta editais abertos da FAPESB via WordPress REST API
  #' Endpoint: /wp-json/wp/v2/posts?categories=11 (Aberto)
  #' NOTA: WordPress REST API fornece dados estruturados, mais confiável que HTML scraping

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[FAPESB][%s] %s", level, msg))
  }

  base_api <- "https://www.fapesb.ba.gov.br/wp-json/wp/v2/posts"
  category_id <- 11L  # Categoria "Aberto"
  page_size <- 10L

  all_items <- list()
  page <- 1L

  repeat {
    .log("INFO", sprintf("Buscando página %d...", page))

    url <- sprintf("%s?categories=%d&per_page=%d&page=%d&_fields=id,title,link,date,excerpt,content",
                   base_api, category_id, page_size, page)

    tmp_file <- tempfile(fileext = ".json")
    on.exit(unlink(tmp_file), add = TRUE)

    # Usar curl cross-platform (shell no Windows, system2 no Linux)
    curl_args <- c("-s", "--max-time", "30",
                   "-H", "User-Agent: FundingIntelligence/1.0",
                   "-o", tmp_file, url)
    
    exit_code <- tryCatch(
      run_curl(curl_args),
      error = function(e) {
        .log("ERROR", sprintf("Erro ao executar curl: %s", e$message))
        1
      }
    )

    # Verificar se o arquivo foi criado
    if (!file.exists(tmp_file) || file.size(tmp_file) == 0) {
      .log("WARN", "Falha na requisição (arquivo não criado), interrompendo paginação")
      break
    }

    data <- tryCatch({
      jsonlite::fromJSON(tmp_file, simplifyVector = FALSE)
    }, error = function(e) {
      .log("ERROR", sprintf("Erro ao parsear JSON: %s", e$message))
      NULL
    })

    if (is.null(data) || length(data) == 0) {
      .log("WARN", "Resposta vazia ou inválida")
      break
    }

    # Verificar se é erro da API (400 = página não existe)
    if (is.list(data) && !is.null(data$code)) {
      .log("INFO", "Fim da paginação (página não encontrada)")
      break
    }

    all_items <- c(all_items, data)
    .log("INFO", sprintf("Página %d: %d itens coletados, %d acumulados", page, length(data), length(all_items)))

    if (length(data) < page_size) break
    if (length(all_items) >= max_records) break
    if (page >= max_pages) {
      .log("WARN", sprintf("Limite de %d páginas atingido", max_pages))
      break
    }

    page <- page + 1L
    Sys.sleep(0.5)
  }

  # Truncar para max_records
  if (length(all_items) > max_records) {
    all_items <- all_items[seq_len(max_records)]
    .log("WARN", sprintf("Limitado a %d registros", max_records))
  }

  if (length(all_items) == 0) {
    .log("WARN", "Nenhum item encontrado")
    return(list(records = tibble::tibble(), pages_visited = as.integer(page - 1L), last_url = base_api))
  }

  # Converter para tibble
  records <- purrr::map_dfr(all_items, function(item) {
    titulo <- gsub("<[^>]+>", "", item$title$rendered)
    # Decodificar entidades HTML
    titulo <- gsub("&#8211;", "–", titulo)
    titulo <- gsub("&#8212;", "—", titulo)
    titulo <- gsub("&#8216;", "'", titulo)
    titulo <- gsub("&#8217;", "'", titulo)
    titulo <- gsub("&#8220;", '"', titulo)
    titulo <- gsub("&#8221;", '"', titulo)
    titulo <- gsub("&amp;", "&", titulo)
    titulo <- gsub("&nbsp;", " ", titulo)
    titulo <- gsub("&#8230;", "...", titulo)
    titulo <- gsub("&hellip;", "...", titulo)
    titulo <- gsub("&#038;", "&", titulo)
    
    link <- item$link
    data_pub <- substr(item$date, 1, 10)

    # Limpar conteúdo HTML
    conteudo_html <- item$content$rendered %||% ""
    conteudo_text <- gsub("<[^>]+>", " ", conteudo_html)
    conteudo_text <- gsub("&amp;", "&", conteudo_text)
    conteudo_text <- gsub("&nbsp;", " ", conteudo_text)
    conteudo_text <- gsub("&#8211;", "–", conteudo_text)
    conteudo_text <- gsub("&#8212;", "—", conteudo_text)
    conteudo_text <- gsub("&hellip;", "...", conteudo_text)
    conteudo_text <- gsub("\\s+", " ", trimws(conteudo_text))

    # Extrair datas do conteúdo (se houver tabela de cronograma)
    data_limite <- NA_character_
    if (nchar(conteudo_text) > 10) {
      # Tentar extrair data no formato DD/MM/AA ou DD/MM/AAAA
      datas <- regmatches(conteudo_text, gregexpr("\\d{2}/\\d{2}/\\d{2,4}", conteudo_text))[[1]]
      if (length(datas) > 0) {
        # Usar a última data encontrada (geralmente é o prazo final)
        data_limite <- utils::tail(datas, 1)
        # Converter para formato ISO
        partes <- strsplit(data_limite, "/")[[1]]
        if (length(partes) == 3) {
          ano <- if (nchar(partes[3]) == 2) paste0("20", partes[3]) else partes[3]
          data_limite <- sprintf("%s-%s-%s", ano, partes[2], partes[1])
        }
      }
    }

    # Hash de deduplicação
    hash_input <- paste0(item$id, "|", titulo)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    tibble::tibble(
      id_registro = sprintf("fapesb_%s", substr(hash_dedup, 1, 16)),
      entidade = "FAPESB",
      pais_origem = "Brasil",
      titulo = titulo,
      subtitulo = NA_character_,
      descricao_resumida = if (nchar(conteudo_text) > 0) substr(conteudo_text, 1, 500) else titulo,
      descricao_completa = if (nchar(conteudo_text) > 0) conteudo_text else titulo,
      tipo_oportunidade = "Edital",
      modalidade = NA_character_,
      area_tematica = NA_character_,
      palavras_chave = "edital",
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "Fundação de Amparo à Pesquisa do Estado da Bahia",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = data_pub,
      data_abertura = data_pub,
      data_limite = data_limite,
      data_encerramento = NA_character_,
      status_oportunidade = "aberto",
      link_origem = "https://www.fapesb.ba.gov.br/",
      link_detalhe = link,
      link_documento_pdf = NA_character_,
      idioma = "pt",
      localidade = "Bahia",
      observacoes = NA_character_,
      texto_bruto = paste(titulo, conteudo_text, sep = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "fapesb",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )
  })

  .log("INFO", sprintf("FAPESB: %d registros finais coletados", nrow(records)))

  return(list(records = records, pages_visited = as.integer(page - 1L), last_url = base_api))
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
    if (is.null(xlsx_df) || !is.data.frame(xlsx_df) || ncol(xlsx_df) == 0 || nrow(xlsx_df) == 0) {
      export_warnings <<- c(export_warnings, "Exportação XLSX ignorada: dataframe vazio ou inválido.")
      if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
    } else {
      # Remover colunas list que writexl não consegue processar
      list_cols <- vapply(xlsx_df, is.list, logical(1))
      if (any(list_cols)) {
        xlsx_df <- xlsx_df[, !list_cols, drop = FALSE]
      }
      if (ncol(xlsx_df) > 0) {
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
      } else {
        export_warnings <<- c(export_warnings, "Exportação XLSX ignorada: nenhuma coluna válida após remoção de list columns.")
        if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
      }
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

    # Override: fontes EU (HEU/ERC) usam mais registros por serem programas plurianuais
    effective_max <- if (sid %in% c("horizon_europe", "erc")) 100L else max_records_per_source

    result <- tryCatch({
      source_dispatch(
        source_row = src,
        max_pages = max_pages,
        max_records = effective_max,
        use_ai = use_ai,
        log_path = log_path,
        conn = conn
      )
    }, error = function(e) {
      log_write(log_path, "ERROR", sprintf("Falha na fonte %s: %s", sid, e$message))
      log_collection(conn, sid, src$metodo_coleta[[1]], "erro", e$message, n_paginas = 0L, n_registros = 0L, url = src$url_oportunidades[[1]])
      NULL
    })

    if (is.null(result)) next

    recs <- tryCatch(finalize_records(result$records, fonte_oficial = sid), error = function(e) {
      log_write(log_path, "ERROR", sprintf("Falha ao finalizar registros da fonte %s: %s", sid, e$message))
      ensure_record_schema(tibble::tibble())
    })
    
    # Traduzir registros EU para pt-br (habilitado por padrao, desabilitar com AI_TRANSLATE_EU=false)
    translate_eu <- identical(tolower(Sys.getenv("AI_TRANSLATE_EU", "true")), "true")
    if (translate_eu && sid %in% c("horizon_europe", "erc") && nrow(recs) > 0) {
      recs <- tryCatch(translate_to_pt_br(recs, log_path = log_path), error = function(e) {
        log_write(log_path, "WARN", sprintf("Falha na traducao para fonte %s: %s", sid, e$message))
        recs
      })
    }
    
    n_inserted <- upsert_opportunities(conn, recs)
    inserted_total <- inserted_total + n_inserted
    log_metric(conn, sid, "source_records", n_inserted, list(source_id = sid, pages = result$pages_visited %||% 0L))
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
    if (i < total) Sys.sleep(1)
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

# Auto-registrar collectors (após definição de todas as funções)
register_collector("capes", collect_capes, "CAPES Plone API + HTML fallback")
register_collector("finep", collect_finep, "FINEP custom pagination")
register_collector("horizon_europe", collect_horizon_europe, "EU F&T Portal REST API (Horizon Europe)")
register_collector("erc", collect_erc, "EU F&T Portal REST API (Horizon Europe/ERC)")
register_collector("fapesb", collect_fapesb, "WordPress REST API (FAPESB)")
