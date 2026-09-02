log_progress <- function(detail, phase = "Scraping") {
  try(
    {
      log_file <- Sys.getenv("COLLECTION_MODAL_LOG_FILE")
      if (!nzchar(log_file)) {
        log_file <- file.path(getwd(), "logs", "collection_modal_log.txt")
      }
      log_line <- sprintf("[%s] [%s] %s", format(Sys.time(), "%H:%M:%S"), phase, detail)
      cat(log_line, "\n", file = log_file, append = TRUE)
    },
    silent = TRUE
  )
}

detect_next_page <- function(html, current_url) {
  nodes <- rvest::html_nodes(html, "a")
  if (length(nodes) == 0) {
    return(NA_character_)
  }

  hrefs <- rvest::html_attr(nodes, "href")
  texts <- tolower(rvest::html_text(nodes, trim = TRUE))
  rels <- tolower(rvest::html_attr(nodes, "rel"))

  valid <- !is.na(hrefs) & nzchar(hrefs)
  if (!any(valid)) {
    return(NA_character_)
  }

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
      log_write(log_path, "ERROR", sprintf(
        "Falha no collector '%s' para %s: %s",
        collector$description, sid, e$message
      ))
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
  res <- tryCatch(
    {
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
    },
    error = function(e) {
      if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Erro de execucao Playwright: %s", e$message))
      list(ok = FALSE)
    }
  )
  res
}

eu_api_request <- function(url, body_data, timeout_sec = 60, log_path = NULL, languages = '["en"]') {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[EU-API][%s] %s", level, msg))
  }
  .modal <- function(msg) {
    try(log_progress(msg, "Scraping"), silent = TRUE)
  }

  first_error <- NULL
  set_error <- function(msg) {
    if (is.null(first_error)) first_error <<- msg
  }

  encoded_body <- paste0(
    "query=", URLencode(body_data, reserved = TRUE),
    "&languages=", URLencode(languages, reserved = TRUE),
    "&displayLanguage=", URLencode("en", reserved = TRUE)
  )
  user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

  do_curl_r <- function(ssl_verify) {
    h <- curl::new_handle()
    curl::handle_setheaders(h,
      "User-Agent" = user_agent,
      "Referer" = "https://ec.europa.eu/info/funding-tenders/opportunities/portal/",
      "Origin" = "https://ec.europa.eu",
      "Accept" = "application/json, text/plain, */*",
      "Content-Type" = "application/x-www-form-urlencoded"
    )
    curl::handle_setopt(h,
      customrequest = "POST",
      postfields = encoded_body,
      timeout = as.integer(timeout_sec),
      ssl_verifypeer = as.integer(ssl_verify),
      followlocation = TRUE
    )
    r <- curl::curl_fetch_memory(url, handle = h)
    if (r$status_code >= 400L || length(r$content) == 0) {
      return(NULL)
    }
    jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE)
  }

  do_curl_cli <- function() {
    curl_bin <- if (.Platform$OS.type == "windows") "curl.exe" else "curl"
    curl_path <- tryCatch(Sys.which(curl_bin), error = function(e) "")
    if (!nzchar(curl_path)) {
      set_error("curl CLI nao encontrado no PATH")
      return(NULL)
    }
    tmp <- tempfile(fileext = ".json")
    tmp_err <- tempfile(fileext = ".stderr")
    on.exit(
      {
        unlink(tmp)
        unlink(tmp_err)
      },
      add = TRUE
    )
    args <- c(
      "-s", "--max-time", as.character(timeout_sec),
      "-X", "POST", url,
      "-H", paste0("User-Agent: ", user_agent),
      "-H", "Referer: https://ec.europa.eu/info/funding-tenders/opportunities/portal/",
      "-H", "Origin: https://ec.europa.eu",
      "-H", "Accept: application/json, text/plain, */*",
      "-H", "Content-Type: application/x-www-form-urlencoded",
      "--data-urlencode", paste0("query=", body_data),
      "--data-urlencode", paste0("languages=", languages),
      "--data-urlencode", "displayLanguage=en",
      "-o", tmp, "-w", "%{http_code}"
    )
    exit <- tryCatch(
      {
        if (.Platform$OS.type == "windows") {
          quoted <- vapply(args, function(a) if (grepl("[&|<>^%\\s]", a)) shQuote(a) else a, character(1))
          cmd <- paste(c(curl_bin, quoted), collapse = " ")
          output <- shell(paste(cmd, "2>", shQuote(tmp_err)), intern = TRUE)
          http_code <- suppressWarnings(as.integer(output[length(output)]))
          if (is.na(http_code)) 1L else http_code
        } else {
          system2(curl_bin, args, stdout = tmp_err, stderr = tmp_err)
        }
      },
      error = function(e) {
        set_error(sprintf("curl CLI erro: %s", e$message))
        1
      }
    )
    cli_out <- tryCatch(readLines(tmp_err, warn = FALSE), error = function(e) character())
    cli_err <- paste(cli_out, collapse = " | ")
    if (nzchar(cli_err)) set_error(paste0("curl CLI: ", substr(cli_err, 1, 200)))
    if (exit != 0 || !file.exists(tmp) || file.size(tmp) == 0) {
      set_error(paste0("curl CLI exit=", exit, " size=", if (file.exists(tmp)) file.size(tmp) else 0))
      return(NULL)
    }
    jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  }

  for (attempt in 1:2) {
    resp <- tryCatch(do_curl_r(ssl_verify = 1L), error = function(e) {
      set_error(e$message)
      .log("WARN", sprintf("curl SSL tentativa %d: %s", attempt, e$message))
      NULL
    })
    if (!is.null(resp)) {
      return(resp)
    }
    if (attempt < 2) Sys.sleep(1)
  }

  for (attempt in 1:2) {
    resp <- tryCatch(do_curl_r(ssl_verify = 0L), error = function(e) {
      set_error(e$message)
      .log("WARN", sprintf("curl noSSL tentativa %d: %s", attempt, e$message))
      NULL
    })
    if (!is.null(resp)) {
      return(resp)
    }
    if (attempt < 2) Sys.sleep(1)
  }

  resp <- tryCatch(do_curl_cli(), error = function(e) {
    set_error(e$message)
    .log("WARN", sprintf("curl CLI: %s", e$message))
    NULL
  })
  if (!is.null(resp)) {
    return(resp)
  }

  err_detail <- if (!is.null(first_error)) substr(first_error, 1, 120) else "motivo desconhecido"
  .modal(sprintf("AVISO: EU API falhou - %s", err_detail))
  .log("WARN", sprintf("Todas as tentativas falharam. Ultimo erro: %s", err_detail))
  NULL
}

get_eu_api_base_url <- function() {
  worker_url <- Sys.getenv("EU_API_PROXY_URL", unset = "")
  if (nzchar(worker_url)) {
    return(worker_url)
  }
  "https://api.tech.ec.europa.eu/search-api/prod/rest"
}

is_host_alive <- function(url) {
  tryCatch(
    {
      req <- httr2::request(url) |>
        httr2::req_method("POST") |>
        httr2::req_headers(
          "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
          "Referer" = "https://ec.europa.eu/info/funding-tenders/opportunities/portal/",
          "Origin" = "https://ec.europa.eu",
          "Accept" = "application/json, text/plain, */*",
          "Content-Type" = "application/x-www-form-urlencoded"
        ) |>
        httr2::req_body_form("apiKey" = "SEDIA", "text" = "test", "pageNumber" = "1", "pageSize" = "1") |>
        httr2::req_timeout(8)
      httr2::req_perform(req)
      TRUE
    },
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("Could not resolve host|Could not resolve hostname|Timeout was reached|Connection refused|Failed to connect|schannel|server closed abruptly|missing close_notify", msg, ignore.case = TRUE)) {
        return(FALSE)
      }
      TRUE
    }
  )
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

  resp <- tryCatch(
    {
      httr2::req_perform(req)
    },
    error = function(e) {
      if (!is.null(e$response)) {
        return(e$response)
      }
      e
    }
  )

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
    if (length(one) == 0 || is.na(one)) {
      return(FALSE)
    }
    txt <- normalize_text(substr(one, 1, 5000))
    if (!nzchar(txt)) {
      return(FALSE)
    }
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
    "nota-de-esclarecimento", "anexo",
    "facebook.com/sharer", "facebook.com/share",
    "twitter.com/share", "twitter.com/intent",
    "linkedin.com/share", "api.whatsapp.com/send",
    "b_start:int=", "b_start%3Aint%3D"
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
    "prorrogacoes", "termo aditivo", "errata", "gabarito",
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
  if (grepl("fapes 20 anos", t_norm) ||
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
  if (is.null(html)) {
    return(NA_character_)
  }
  h1 <- try(rvest::html_element(html, "h1"), silent = TRUE)
  title_1 <- if (!inherits(h1, "try-error")) safe_html_text(h1) else NA_character_
  if (!is.na(title_1) && nzchar(title_1)) {
    return(title_1)
  }

  og <- try(rvest::html_element(html, "meta[property='og:title']"), silent = TRUE)
  title_og <- if (!inherits(og, "try-error")) safe_attr(og, "content") else NA_character_
  if (!is.na(title_og) && nzchar(title_og)) {
    return(normalize_ws(title_og))
  }

  ttl <- try(rvest::html_element(html, "title"), silent = TRUE)
  title_tag <- if (!inherits(ttl, "try-error")) safe_html_text(ttl) else NA_character_
  if (!is.na(title_tag) && nzchar(title_tag)) {
    return(title_tag)
  }
  NA_character_
}

extract_page_summary <- function(html, max_chars = 1200) {
  if (is.null(html)) {
    return(NA_character_)
  }
  nodes <- try(rvest::html_elements(html, "main p, article p, .content p, .entry-content p, .post-content p, body p"), silent = TRUE)
  if (inherits(nodes, "try-error") || length(nodes) == 0) {
    body <- try(rvest::html_element(html, "body"), silent = TRUE)
    txt <- if (!inherits(body, "try-error")) safe_html_text(body) else NA_character_
    if (is.na(txt) || !nzchar(txt)) {
      return(NA_character_)
    }
    return(stringr::str_squish(stringr::str_sub(txt, 1, max_chars)))
  }
  txt <- vapply(nodes, safe_html_text, character(1))
  txt <- txt[!is.na(txt) & nzchar(txt)]
  if (length(txt) == 0) {
    return(NA_character_)
  }
  stringr::str_squish(stringr::str_sub(paste(txt, collapse = " "), 1, max_chars))
}

extract_candidate_links <- function(html, base_url, source_id) {
  anchors <- try(rvest::html_elements(html, "a[href]"), silent = TRUE)
  if (inherits(anchors, "try-error") || length(anchors) == 0) {
    return(tibble::tibble())
  }

  hrefs <- rvest::html_attr(anchors, "href")
  abs_urls <- vapply(hrefs, function(h) resolve_url(base_url, h), character(1))

  valid <- !is.na(abs_urls) & nzchar(abs_urls)
  if (!any(valid)) {
    return(tibble::tibble())
  }

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
  if (is.null(html)) {
    return(tibble::tibble())
  }

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
      if (is.na(raw_txt) || nchar(raw_txt) < 40) {
        return(tibble::tibble())
      }

      anchors <- try(rvest::html_elements(node, "a[href]"), silent = TRUE)
      if (inherits(anchors, "try-error") || length(anchors) == 0) {
        return(tibble::tibble())
      }

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
      if (!isTRUE(keep)) {
        return(tibble::tibble())
      }

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

extract_detail_bundle <- function(detail_url = NA_character_, page_url = NA_character_, pdf_url = NA_character_, log_path = NULL, use_browser_fallback = TRUE) {
  out <- list(
    detail_title = NA_character_,
    detail_subtitle = NA_character_,
    detail_summary = NA_character_,
    full_text = NA_character_,
    pdf_url = pdf_url
  )

  if (!is.na(detail_url) && nzchar(detail_url)) {
    det <- safe_request_page(detail_url, log_path = log_path, use_browser_fallback = use_browser_fallback)
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
  ok <- try(
    {
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
    },
    silent = TRUE
  )
  if (inherits(ok, "try-error") || !file.exists(tf)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Falha ao baixar PDF %s", pdf_url))
    return(NA_character_)
  }
  txt <- try(pdftools::pdf_text(tf), silent = TRUE)
  unlink(tf)
  if (inherits(txt, "try-error")) {
    return(NA_character_)
  }
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
    try(
      {
        status_data <- jsonlite::fromJSON(status_file, simplifyVector = FALSE)
        status_data$phase <- "IA"
        status_data$detail <- sprintf("Enriquecendo dados via IA para edital: %s", record$titulo[[1]])
        jsonlite::write_json(status_data, status_file, auto_unbox = TRUE)
      },
      silent = TRUE
    )
  }
  text <- collapse_non_empty(record$titulo, record$descricao_resumida, record$descricao_completa, record$texto_bruto, sep = "\n")
  ai <- ai_extract_fields(
    text,
    current = as.list(record[1, c("titulo", "tipo_oportunidade", "status_oportunidade", "idioma")]),
    log_path = log_path
  )
  if (length(ai) == 0) {
    return(record)
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
    log_progress(sprintf("Descartando edital '%s' via classificação de IA (Motivo: %s)", record$titulo[[1]], ai$motivo_descarte[[1]] %||% "não especificado"), "IA")
    return(tibble::tibble())
  }

  inferred <- character()
  apply_ai_fields_to_df(ai, record, 1L, inferred)
  record$campos_inferidos_ia <- paste(unique(inferred), collapse = "; ")
  record
}

enrich_records_parallel <- function(df, log_path = NULL, conn = NULL) {
  if (is.null(df) || nrow(df) == 0) {
    return(df)
  }

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
      on.exit({
        if (!is.null(conn) && DBI::dbIsValid(conn)) DBI::dbDisconnect(conn)
      })
    }
  }

  to_enrich_indices <- integer()

  for (i in seq_len(nrow(df))) {
    need_ia <- TRUE
    if (!is.null(conn) && DBI::dbIsValid(conn)) {
      id <- df$id_registro[[i]]
      hash_val <- df$hash_deduplicacao[[i]]

      existing <- tryCatch(
        {
          DBI::dbGetQuery(
            conn,
            "SELECT id_registro, descricao_resumida, campos_inferidos_ia FROM oportunidades WHERE id_registro = ? OR hash_deduplicacao = ?",
            params = list(id, hash_val)
          )
        },
        error = function(e) NULL
      )

      if (!is.null(existing) && nrow(existing) > 0) {
        resumo <- existing$descricao_resumida[[1]]
        campos_ia <- existing$campos_inferidos_ia[[1]] %||% ""
        if (!is.na(resumo) && nzchar(trimws(resumo)) && !identical(resumo, "Resumo não disponível.") && nzchar(campos_ia)) {
          log_progress(sprintf("Edital '%s' já enriquecido no banco. Recuperando cache...", df$titulo[[i]]), "IA")

          # Carrega o registro completo do banco
          existing_full <- tryCatch(
            {
              DBI::dbGetQuery(conn, "SELECT * FROM oportunidades WHERE id_registro = ?", params = list(existing$id_registro[[1]]))
            },
            error = function(e) NULL
          )

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
      try(
        {
          status_data <- jsonlite::fromJSON(status_file, simplifyVector = FALSE)
          status_data$phase <- "IA"
          status_data$detail <- sprintf("Processando lote de IA %d/%d", b, length(batches))
          jsonlite::write_json(status_data, status_file, auto_unbox = TRUE)
        },
        silent = TRUE
      )
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
      # Blindagem: IA pode retornar array de 6-8 objetos (simplifyVector=TRUE -> data.frame) — normaliza para primeiro registro
      if (is.data.frame(parsed) && nrow(parsed) > 0) {
        if (nrow(parsed) > 1 && !is.null(log_path)) {
          log_write(log_path, "WARN", sprintf("IA retornou array de %d registros para '%s' — usando apenas o primeiro.", nrow(parsed), substr(df$titulo[[i]], 1, 50)))
        }
        parsed <- as.list(parsed[1, , drop = FALSE])
        # Desembrulha colunas data.frame que viraram vetores de 1
        parsed <- lapply(parsed, function(v) if (length(v) == 1) v[[1]] else v)
      } else if (is.list(parsed) && !is.data.frame(parsed)) {
        # Se algum campo é vetor/array (ex: palavras_chave com 6-8 termos como array), colapsa em string
        # (fill_ai_field já colapsa, mas valor_financiado/moeda precisam escalar — já blindados em apply_ai_fields_to_df)
        # Apenas loga para observabilidade
        array_fields <- names(parsed)[vapply(parsed, function(v) length(v) > 1 && is.character(v), logical(1))]
        if (length(array_fields) > 0 && !is.null(log_path)) {
          # Não loga a cada edital para não poluir; apenas quando array suspeito de resposta múltipla
          if (any(vapply(parsed[array_fields], length, integer(1)) >= 6)) {
            log_write(log_path, "WARN", sprintf("IA retornou campos array %s para '%s' — campos serão normalizados.", paste(array_fields, collapse=","), substr(df$titulo[[i]], 1, 40)))
          }
        }
      }
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
  if (is.null(df) || nrow(df) == 0) {
    return(tibble::tibble())
  }

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
  if (is.null(df) || nrow(df) == 0) {
    return(ensure_record_schema(tibble::tibble()))
  }
  df <- ensure_record_schema(df)

  # Verificar se e fonte internacional (HEU/ERC/DAAD)
  is_eu <- !is.null(fonte_oficial) && (fonte_oficial %in% c("horizon_europe", "erc", "daad"))

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

  if (nrow(df) == 0) {
    return(ensure_record_schema(tibble::tibble()))
  }

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

  if (nrow(df) == 0) {
    return(ensure_record_schema(tibble::tibble()))
  }

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

collect_cnpq <- function(source_row, max_pages, max_records, use_ai, log_path) {
  buscar_url <- "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas"
  submissao_url <- "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao"
  pages_seen <- character()
  all_candidates <- list()

  log_progress("CNPq: Iniciando coleta customizada (Busca_abertas + abertas-para-submissao)...", "Scraping")

  # Extrator otimizado para paginas CNPq Plone
  extract_cnpq_listing <- function(html, base_url) {
    results <- tibble::tibble(
      title = character(), summary = character(), detail_url = character(),
      pdf_url = character(), source_text = character()
    )

    # Caminho 1: div.item blocks (abertas-para-submissao)
    items <- try(rvest::html_elements(html, "div.item"), silent = TRUE)
    if (!inherits(items, "try-error") && length(items) > 0) {
      for (node in items) {
        heading <- try(rvest::html_element(node, "h2.headline a, h2 a.summary"), silent = TRUE)
        if (inherits(heading, "try-error") || is.null(heading)) next
        title_txt <- safe_html_text(heading)
        if (is.na(title_txt) || !nzchar(title_txt)) next
        href <- rvest::html_attr(heading, "href")
        detail <- if (!is.na(href) && nzchar(href)) resolve_url(base_url, href) else NA_character_
        body_txt <- safe_html_text(node)
        pdfs <- try(rvest::html_elements(node, "a[href$='.pdf']"), silent = TRUE)
        pdf_url <- NA_character_
        if (!inherits(pdfs, "try-error") && length(pdfs) > 0) {
          pdf_hrefs <- rvest::html_attr(pdfs, "href")
          pdf_abs <- vapply(pdf_hrefs, function(h) resolve_url(base_url, h), character(1))
          pdf_url <- pdf_abs[[1]]
        }
        if (!is.na(detail) || !is.na(pdf_url)) {
          results <- dplyr::bind_rows(results, tibble::tibble(
            title = title_txt, summary = stringr::str_squish(stringr::str_sub(body_txt %||% "", 1, 700)),
            detail_url = detail, pdf_url = pdf_url, source_text = body_txt
          ))
        }
      }
    }

    # Caminho 2: article.contenttype-document blocks (Busca_abertas)
    articles <- try(rvest::html_elements(html, "article.contenttype-document"), silent = TRUE)
    if (!inherits(articles, "try-error") && length(articles) > 0) {
      for (node in articles) {
        heading <- try(rvest::html_element(node, "h2.tileHeadline a, h2 a"), silent = TRUE)
        if (inherits(heading, "try-error") || is.null(heading)) next
        title_txt <- safe_html_text(heading)
        if (is.na(title_txt) || !nzchar(title_txt)) next
        href <- rvest::html_attr(heading, "href")
        detail <- if (!is.na(href) && nzchar(href)) resolve_url(base_url, href) else NA_character_
        body_txt <- safe_html_text(node)
        if (!is.na(detail)) {
          results <- dplyr::bind_rows(results, tibble::tibble(
            title = title_txt, summary = stringr::str_squish(stringr::str_sub(body_txt %||% "", 1, 700)),
            detail_url = detail, pdf_url = NA_character_, source_text = body_txt
          ))
        }
      }
    }

    # Deduplicate by detail_url
    if (nrow(results) > 0 && !all(is.na(results$detail_url))) {
      results <- results[!is.na(results$detail_url), ]
      results <- results |> dplyr::distinct(detail_url, .keep_all = TRUE)
    }
    results
  }

  # --- ETAPA 1: Scraping de abertas-para-submissao (conteudo rico) ---
  log_progress("CNPq: Buscando abertas-para-submissao (conteudo rico)...", "Scraping")
  pg_sub <- safe_request_page(submissao_url, log_path = log_path, use_browser_fallback = FALSE)
  if (isTRUE(pg_sub$ok) && !is.null(pg_sub$html)) {
    pages_seen <- c(pages_seen, submissao_url)
    cands_sub <- try(extract_cnpq_listing(pg_sub$html, submissao_url), silent = TRUE)
    if (!inherits(cands_sub, "try-error") && nrow(cands_sub) > 0) {
      log_progress(sprintf("CNPq: abertas-para-submissao: %d chamadas encontradas.", nrow(cands_sub)), "Scraping")
      all_candidates <- c(all_candidates, list(cands_sub))
    }
  }

  # --- ETAPA 2: Scraping de Busca_abertas com paginacao b_start:int ---
  log_progress("CNPq: Buscando Busca_abertas (paginacao)...", "Scraping")
  page_no <- 0L
  b_size <- 5L
  consecutive_empty <- 0L

  while (page_no <= max_pages) {
    b_start <- page_no * b_size
    page_url <- if (page_no == 0L) buscar_url else sprintf("%s?b_start:int=%d", buscar_url, b_start)
    if (page_url %in% pages_seen) break
    pages_seen <- c(pages_seen, page_url)

    pg <- safe_request_page(page_url, log_path = log_path, use_browser_fallback = FALSE)
    if (!isTRUE(pg$ok) || is.null(pg$html)) break

    cands <- try(extract_cnpq_listing(pg$html, page_url), silent = TRUE)
    if (inherits(cands, "try-error") || nrow(cands) == 0) {
      consecutive_empty <- consecutive_empty + 1L
      if (consecutive_empty >= 2L) break
      page_no <- page_no + 1L
      next
    }
    consecutive_empty <- 0L

    log_progress(sprintf("CNPq: Busca_abertas pagina %d (b_start=%d): %d chamadas.", page_no + 1L, b_start, nrow(cands)), "Scraping")
    all_candidates <- c(all_candidates, list(cands))
    page_no <- page_no + 1L
  }

  # --- Consolidar e deduplicar ---
  if (length(all_candidates) == 0) {
    log_progress("CNPq: Nenhum candidato encontrado.", "Scraping")
    return(list(records = finalize_records(tibble::tibble()), pages_visited = length(pages_seen), last_url = submissao_url))
  }

  combined <- dplyr::bind_rows(all_candidates) |>
    dplyr::filter(!is.na(detail_url) | !is.na(pdf_url)) |>
    dplyr::distinct(dplyr::coalesce(detail_url, pdf_url), .keep_all = TRUE)

  if (nrow(combined) > max_records) combined <- combined[seq_len(max_records), , drop = FALSE]
  log_progress(sprintf("CNPq: %d chamadas unicas finais.", nrow(combined)), "Scraping")

  # --- Buscar detalhes (limitado) ---
  detail_cache <- new.env(parent = emptyenv())
  detail_count <- 0L
  max_details <- as.integer(Sys.getenv("CNPQ_MAX_DETAIL_FETCHES", "10"))

  for (i in seq_len(nrow(combined))) {
    if (detail_count >= max_details) break
    det_url <- combined$detail_url[[i]]
    if (is.na(det_url) || !nzchar(det_url)) next
    detail_count <- detail_count + 1L
    det <- tryCatch(
      extract_detail_bundle(detail_url = det_url, page_url = buscar_url, log_path = log_path, use_browser_fallback = FALSE),
      error = function(e) list(detail_title = NA_character_, detail_subtitle = NA_character_, detail_summary = NA_character_, full_text = NA_character_, pdf_url = NA_character_)
    )
    assign(det_url, det, envir = detail_cache)
  }

  # --- Converter em registros ---
  page_records <- purrr::map_dfr(seq_len(nrow(combined)), function(i) {
    one <- combined[i, , drop = FALSE]
    det_url <- one$detail_url[[1]]
    det <- if (!is.na(det_url) && exists(det_url %||% "", envir = detail_cache)) {
      get(det_url, envir = detail_cache)
    } else {
      list(detail_title = NA_character_, detail_subtitle = NA_character_, detail_summary = NA_character_, full_text = NA_character_, pdf_url = one$pdf_url[[1]])
    }
    detail_summ <- pick_first_nonempty(det$detail_summary, one$summary[[1]])
    detail_full <- pick_first_nonempty(det$full_text, one$source_text[[1]])
    detail_pdf <- pick_first_nonempty(det$pdf_url, one$pdf_url[[1]])

    raw_for_dates <- paste(det$detail_summary %||% "", det$full_text %||% "", one$source_text[[1]] %||% "", sep = " ")
    insc_dates <- extract_inscricoes_dates(raw_for_dates)

    rec <- extract_core_record(
      source_row = source_row,
      input_title = pick_first_nonempty(det$detail_title, one$title[[1]]),
      input_subtitle = det$detail_subtitle,
      input_summary = detail_summ,
      input_full_text = detail_full,
      page_url = buscar_url,
      detail_url = det_url,
      pdf_url = detail_pdf,
      page_no = 1L
    )
    if (!is.na(insc_dates$data_abertura)) rec$data_abertura <- insc_dates$data_abertura
    if (!is.na(insc_dates$data_limite)) {
      rec$data_limite <- insc_dates$data_limite
    }
    rec$tipo_oportunidade <- infer_type_from_text(paste(rec$titulo, rec$texto_bruto))
    rec
  })

  list(
    records = finalize_records(page_records),
    pages_visited = length(pages_seen),
    last_url = buscar_url
  )
}

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
      if (item$mime_type != "application/pdf") {
        return(FALSE)
      }
      title <- tolower(item$title %||% "")
      if (nchar(title) < 10) {
        return(FALSE)
      }
      if (grepl("altera|retifica|prorroga|resultado|errata|anexo|ata\\s|lista|planilha|formulario|termo", title)) {
        return(FALSE)
      }
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
    response <- tryCatch(
      {
        httr::GET(url, httr::timeout(60))
      },
      error = function(e) {
        .log("ERROR", sprintf("Erro na requisição: %s", e$message))
        NULL
      }
    )

    if (is.null(response) || httr::status_code(response) != 200) {
      .log("WARN", "Falha na requisição, interrompendo paginação")
      break
    }

    # Parsear JSON
    data <- tryCatch(
      {
        httr::content(response, as = "parsed", type = "application/json")
      },
      error = function(e) {
        .log("ERROR", sprintf("Erro ao parsear JSON: %s", e$message))
        NULL
      }
    )

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

    .log("INFO", sprintf(
      "Página %d: %d itens total, %d filtrados (Aberta)",
      page, length(data$items), length(filtered_items)
    ))

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
    } else {
      NA_character_
    }

    data_limite <- if (!is.null(item$prazoProposto)) {
      as.character(as.Date(sub("T.*", "", item$prazoProposto)))
    } else {
      NA_character_
    }

    # Extrair público alvo
    publico_alvo <- if (length(item$publicoAlvo) > 0) {
      paste(sapply(item$publicoAlvo, function(pa) pa$name), collapse = "; ")
    } else {
      NA_character_
    }

    # Extrair tema
    tema <- if (!is.null(item$temaPrincipal) && !is.null(item$temaPrincipal$name)) {
      item$temaPrincipal$name
    } else {
      NA_character_
    }

    # Extrair região
    regiao <- if (!is.null(item$regiao) && !is.null(item$regiao$name)) {
      item$regiao$name
    } else {
      NA_character_
    }

    # Tipo de oportunidade
    tipo_oportunidade <- if (!is.null(item$tipoDeOportunidade) && !is.null(item$tipoDeOportunidade$name)) {
      item$tipoDeOportunidade$name
    } else {
      NA_character_
    }

    # Contrapartida
    contrapartida <- if (!is.null(item$contrapartida) && !is.null(item$contrapartida$name)) {
      item$contrapartida$name
    } else {
      NA_character_
    }

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

  api_url <- paste0(get_eu_api_base_url(), "/search")
  all_items <- list()
  seen_ids <- character(0)

  # Pre-flight: verificar conectividade com a API EU antes do loop
  if (!is_host_alive(api_url)) {
    .log("WARN", "API EU inacessivel (DNS/rede/schannel). Pulando coleta HEU.")
    try(log_progress("AVISO: API EU inacessivel - pulando HEU", "Scraping"), silent = TRUE)
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = api_url))
  }

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
    url <- sprintf(
      "%s?apiKey=SEDIA&text=%s&pageNumber=1&pageSize=100&sortBy=es_SortDate&orderBy=DESC",
      api_url, search_text
    )

    data <- tryCatch(eu_api_request(url, heu_query, 60, log_path), error = function(e) {
      .log("ERROR", sprintf("Erro ao executar request para '%s': %s", term, e$message))
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
      ds <- tryCatch(
        {
          d <- md$DATASOURCE
          if (!is.null(d)) {
            if (is.list(d)) d[[1]] else d[1]
          } else {
            NA
          }
        },
        error = function(e) NA
      )
      if (is.na(ds) || ds != "SEDIA") next

      # Verificar frameworkProgramme = 43108390 (Horizon Europe)
      fp <- tryCatch(
        {
          f <- md$frameworkProgramme
          if (!is.null(f)) {
            if (is.list(f)) f[[1]] else f[1]
          } else {
            NA
          }
        },
        error = function(e) NA
      )
      if (is.na(fp) || !grepl("43108390", fp)) next

      # Excluir status Closed (31094503)
      st <- tryCatch(
        {
          s <- md$status
          if (!is.null(s)) {
            if (is.list(s)) s[[1]] else s[1]
          } else {
            NA
          }
        },
        error = function(e) NA
      )
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
    md <- tryCatch(
      {
        m <- item$metadata
        if (is.null(m)) next
        if (is.data.frame(m)) m <- as.list(m)
        m
      },
      error = function(e) NULL
    )
    if (is.null(md)) next

    call_id <- tryCatch(
      {
        if (!is.null(md$callIdentifier)) {
          v <- md$callIdentifier
          if (is.list(v)) v[[1]] else v[1]
        } else {
          NA_character_
        }
      },
      error = function(e) NA_character_
    )
    if (is.na(call_id) || length(call_id) == 0) next

    titulo <- tryCatch(
      {
        if (!is.null(md$title)) {
          v <- md$title
          if (is.list(v)) v[[1]] else v[1]
        } else {
          ""
        }
      },
      error = function(e) ""
    )
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
    tryCatch(
      {
        if (is.null(x)) {
          return(default)
        }
        val <- if (is.list(x)) x[[1]] else x[1]
        if (length(val) == 0) {
          return(default)
        }
        if (is.null(val)) {
          return(default)
        }
        if (is.na(val)) {
          return(default)
        }
        as.character(val)
      },
      error = function(e) default
    )
  }

  record_list <- list()
  for (i in seq_along(all_items)) {
    item <- all_items[[i]]
    rec <- tryCatch(
      {
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
          if (grepl("31094501", status_code)) {
            "aberto"
          } else if (grepl("31094502", status_code)) {
            "aberto"
          } else if (grepl("31094503", status_code)) {
            "encerrado"
          } else {
            "desconhecido"
          }
        } else {
          "desconhecido"
        }

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
          titulo # Fallback: usar o titulo como resumo
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
      },
      error = function(e) {
        .log("WARN", sprintf("Erro ao processar item %d: %s", i, e$message))
        NULL
      }
    )
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

  api_url <- paste0(get_eu_api_base_url(), "/search")
  all_items <- list()
  seen_ids <- character(0)

  # Pre-flight: verificar conectividade com a API EU antes do loop
  if (!is_host_alive(api_url)) {
    .log("WARN", "API EU inacessivel (DNS/rede/schannel). Pulando coleta ERC.")
    try(log_progress("AVISO: API EU inacessivel - pulando ERC", "Scraping"), silent = TRUE)
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = api_url))
  }

  # Query filter para HEU (frameworkProgramme=43108390) via form-data
  heu_query <- '{"bool":{"must":[{"terms":{"frameworkProgramme":["43108390"]}}]}}'

  # Múltiplos termos de busca para cobrir diferentes chamadas ERC
  # "ERC 2026" e "ERC StG 2026" retornam itens CLOSED; os termos abaixo encontram itens abertos
  search_terms <- c("ERC AdG 2026", "ERC PoC 2026")

  .log("INFO", "Iniciando coleta ERC via API REST...")

  for (term in search_terms) {
    .log("INFO", sprintf("Buscando termo: %s", term))

    search_text <- utils::URLencode(term, reserved = TRUE)
    url <- sprintf(
      "%s?apiKey=SEDIA&text=%s&pageNumber=1&pageSize=100&sortBy=es_SortDate&orderBy=DESC",
      api_url, search_text
    )

    data <- tryCatch(eu_api_request(url, heu_query, 60, log_path), error = function(e) {
      .log("ERROR", sprintf("Erro ao executar request para '%s': %s", term, e$message))
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
      } else {
        next
      }

      # Verificar frameworkProgramme = 43108390 (Horizon Europe)
      fp <- md$frameworkProgramme
      if (!is.null(fp)) {
        fp_val <- if (is.list(fp)) fp[[1]] else fp[1]
        if (is.na(fp_val) || !grepl("43108390", fp_val)) next
      } else {
        next
      }

      # Verificar programmeDivision contém 43108406 (ERC)
      pd <- md$programmeDivision
      if (!is.null(pd)) {
        pd_vals <- if (is.list(pd)) unlist(pd) else pd
        if (!any(grepl("43108406", pd_vals))) next
      } else {
        next
      }

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
      v <- md$callIdentifier
      if (is.list(v)) v[[1]] else v[1]
    } else {
      NA_character_
    }
    if (is.na(call_id)) next

    titulo <- if (!is.null(md$title)) {
      v <- md$title
      if (is.list(v)) v[[1]] else v[1]
    } else {
      ""
    }
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
      if (is.null(x)) {
        return(default)
      }
      val <- if (is.list(x)) x[[1]] else x[1]
      if (is.na(val)) {
        return(default)
      }
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
      if (grepl("31094501", status_code)) {
        "aberto"
      } else if (grepl("31094502", status_code)) {
        "aberto"
      } else if (grepl("31094503", status_code)) {
        "encerrado"
      } else {
        "desconhecido"
      }
    } else {
      "desconhecido"
    }

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
      titulo # Fallback: usar o titulo como resumo
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
# ---------------------------------------------------------------------------
# FAPESB — Extração de prazo final a partir do texto do edital (PDF ou HTML)
# ---------------------------------------------------------------------------

.extract_deadline_from_cronograma_section <- function(txt) {
  txt <- txt %||% ""
  if (nchar(txt) < 20) return(NA_character_)
  lines <- strsplit(txt, "\n")[[1]]
  lower <- tolower(lines)
  cronograma_idx <- grep("cronograma", lower, fixed = TRUE)
  if (length(cronograma_idx) == 0) {
    return(.extract_deadline_generic(txt))
  }
  start <- cronograma_idx[1]
  window_end <- min(length(lines), start + 40L)
  window_lines <- lines[start:window_end]
  window_lower <- lower[start:window_end]
  sub_kw <- c(
    "submiss", "envio da proposta", "envio de proposta", "envio de propostas",
    "postagem", "preenchimento e envio", "preenchimento",
    "inscricao", "inscricao", "encaminhamento",
    "data final", "prazo final", "prazo limite", "data limite"
  )
  for (kw in sub_kw) {
    kw_hits <- grep(kw, window_lower, fixed = TRUE)
    for (h in kw_hits) {
      line_window <- window_lines[h]
      dates <- extract_dates_from_text(line_window)
      dates <- dates[!is.na(dates)]
      dates <- dates[as.numeric(dates - Sys.Date()) >= -30]
      if (length(dates) > 0) {
        return(format(max(dates), "%Y-%m-%d"))
      }
    }
  }
  all_dates <- extract_dates_from_text(paste(window_lines, collapse = " "))
  all_dates <- all_dates[!is.na(all_dates)]
  future_dates <- all_dates[as.numeric(all_dates - Sys.Date()) >= -7]
  if (length(future_dates) > 0) {
    return(format(min(future_dates), "%Y-%m-%d"))
  }
  NA_character_
}

.extract_deadline_generic <- function(txt) {
  txt <- txt %||% ""
  if (nchar(txt) < 20) return(NA_character_)
  lines <- strsplit(txt, "\n")[[1]]
  lower <- tolower(lines)
  kw_priority <- c(
    "data final de postagem",
    "prazo final", "prazo limite",
    "envio da proposta", "envio de propostas",
    "submissao de propostas", "submissao",
    "preenchimento e envio", "preenchimento",
    "encaminhamento da proposta", "encaminhamento",
    "data limite", "data final",
    "periodo de submissao", "periodo de inscricao"
  )
  for (kw in kw_priority) {
    hits <- grep(kw, lower, fixed = TRUE)
    if (length(hits) == 0) next
    for (h in hits) {
      window_start <- max(1L, h - 2L)
      window_end <- min(length(lines), h + 3L)
      window_txt <- paste(lines[window_start:window_end], collapse = " ")
      # If the keyword says the deadline is in the cronograma (image), skip - let vision LLM handle it
      if (grepl("indicad[ao] no cronograma|conforme cronograma|apresentad[ao] no cronograma", window_txt, ignore.case = TRUE)) {
        next
      }
      dates <- extract_dates_from_text(window_txt)
      dates <- dates[!is.na(dates)]
      if (length(dates) > 0) {
        return(format(max(dates), "%Y-%m-%d"))
      }
    }
  }
  # Fallback: find dates near deadline keywords only, not near publication/signing keywords
  neg_kw <- c("publica", "assinatura", "salvador", "comunicado", "errata", "retifica")
  all_dates <- extract_dates_from_text(txt)
  all_dates <- all_dates[!is.na(all_dates)]
  future <- all_dates[as.numeric(all_dates - Sys.Date()) >= -30]
  if (length(future) > 0) {
    lines <- strsplit(txt, "\n")[[1]]
    lower <- tolower(lines)
    valid_dates <- character(0)
    pt_months <- c(janeiro="01",fevereiro="02",marco="03",abril="04",maio="05",junho="06",
                   julho="07",agosto="08",setembro="09",outubro="10",novembro="11",dezembro="12")
    for (d in future) {
      d_num <- as.integer(format(d, "%d"))
      d_month_num <- as.integer(format(d, "%m"))
      d_year <- format(d, "%Y")
      pt_month <- names(pt_months)[match(d_month_num, as.integer(pt_months))]
      patterns <- c(
        format(d, "%d/%m/%Y"),
        format(d, "%d.%m.%Y"),
        format(d, "%Y-%m-%d"),
        paste(d_num, "de", pt_month, "de", d_year)
      )
      date_lines <- integer(0)
      for (pat in patterns) {
        hits <- grep(gsub("/", "[./]", pat), lower, fixed = FALSE)
        date_lines <- c(date_lines, hits)
      }
      date_lines <- unique(date_lines)
      near_neg <- FALSE
      for (dl in date_lines) {
        w_start <- max(1L, dl - 2L)
        w_end <- min(length(lower), dl + 2L)
        window <- paste(lower[w_start:w_end], collapse = " ")
        if (any(grepl(neg_kw, window, fixed = TRUE))) {
          near_neg <- TRUE
          break
        }
      }
      if (!near_neg) valid_dates <- c(valid_dates, as.character(d))
    }
    if (length(valid_dates) > 0) {
      return(format(max(as.Date(valid_dates)), "%Y-%m-%d"))
    }
  }
  if (length(all_dates) > 0) {
    return(format(max(all_dates), "%Y-%m-%d"))
  }
  NA_character_
}

# ---------------------------------------------------------------------------
# FAPESB — Extração de prazo a partir do PDF do edital
# ---------------------------------------------------------------------------

.extract_fapesb_prazo_from_pdf <- function(pdf_url, log_path = NULL) {
  pdf_txt <- try(extract_text_from_pdf(pdf_url, log_path = log_path), silent = TRUE)
  if (!inherits(pdf_txt, "try-error") && !is.na(pdf_txt) && nchar(pdf_txt) > 50) {
    deadline <- .extract_deadline_from_cronograma_section(pdf_txt)
    if (!is.na(deadline)) {
      return(list(data_limite = deadline, link_documento_pdf = pdf_url))
    }
  }
  if (requireNamespace("tesseract", quietly = TRUE)) {
    tf <- try({
      req <- httr2::request(pdf_url) |>
        httr2::req_user_agent("FundingIntelligence/1.0") |>
        httr2::req_timeout(30)
      resp <- httr2::req_perform(req)
      path <- tempfile(fileext = ".pdf")
      writeBin(httr2::resp_body_raw(resp), path)
      ocr_txt <- try(pdftools::pdf_ocr_text(path, language = "por"), silent = TRUE)
      unlink(path)
      if (inherits(ocr_txt, "try-error") || length(ocr_txt) == 0) NULL else paste(ocr_txt, collapse = "\n")
    }, silent = TRUE)
    if (!is.null(tf) && !inherits(tf, "try-error") && nzchar(tf) && nchar(tf) > 50) {
      deadline <- .extract_deadline_from_cronograma_section(tf)
      if (!is.na(deadline)) {
        return(list(data_limite = deadline, link_documento_pdf = pdf_url))
      }
    }
  }
  list(data_limite = NA_character_, link_documento_pdf = NA_character_)
}

# ---------------------------------------------------------------------------
# FAPESB — Extração de prazo via visão LLM (imagem do cronograma)
# ---------------------------------------------------------------------------

.extract_fapesb_prazo_from_image_llm <- function(detail_html, detail_url, log_path = NULL) {
  html <- tryCatch(xml2::read_html(detail_html), error = function(e) NULL)
  if (is.null(html)) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  all_imgs <- rvest::html_elements(html, "img")
  if (length(all_imgs) == 0) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  cronograma_img <- NULL
  for (img in all_imgs) {
    alt <- tolower(rvest::html_attr(img, "alt") %||% "")
    title <- tolower(rvest::html_attr(img, "title") %||% "")
    src <- rvest::html_attr(img, "src") %||% ""
    if (grepl("imagem do edital|cronograma|cronogram", alt, fixed = FALSE) ||
        grepl("imagem do edital|cronograma|cronogram", title, fixed = FALSE) ||
        grepl("cronograma|cronogram|edital", src, ignore.case = TRUE)) {
      cronograma_img <- src
      break
    }
  }
  if (is.null(cronograma_img)) {
    for (img in all_imgs) {
      src <- rvest::html_attr(img, "src") %||% ""
      if (nzchar(src) && !grepl("logo|icon|favicon|avatar|badge|button", src, ignore.case = TRUE)) {
        cronograma_img <- src
        break
      }
    }
  }
  if (is.null(cronograma_img) || !nzchar(cronograma_img)) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  img_url <- resolve_url(detail_url, cronograma_img)
  if (is.na(img_url) || !nzchar(img_url)) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  img_bytes <- try({
    req <- httr2::request(img_url) |>
      httr2::req_user_agent("FundingIntelligence/1.0") |>
      httr2::req_timeout(15)
    resp <- httr2::req_perform(req)
    httr2::resp_body_raw(resp)
  }, silent = TRUE)
  if (inherits(img_bytes, "try-error") || length(img_bytes) == 0) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  if (length(img_bytes) > 1.5e6) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  mime <- "image/png"
  if (length(img_bytes) >= 3) {
    hdr <- rawToChar(img_bytes[1:min(4, length(img_bytes))], useBytes = TRUE)
    if (grepl("PNG", hdr, fixed = TRUE)) mime <- "image/png"
    else if (grepl("\\xff\\xd8\\xff", hdr, fixed = FALSE)) mime <- "image/jpeg"
    else if (grepl("GIF", hdr, fixed = TRUE)) mime <- "image/gif"
  }
  b64 <- base64enc::base64encode(img_bytes)
  prompt <- paste(
    "Esta imagem mostra a tabela de CRONOGRAMA de um edital da FAPESB.",
    "Identifique a data final para envio/preenchimento/postagem da proposta.",
    "Responda SOMENTE com a data no formato YYYY-MM-DD.",
    "Se nao encontrar nenhuma data de submissao, responda: null"
  )
  resp_text <- try(ai_request_vision(prompt, b64, mime = mime, log_path = log_path), silent = TRUE)
  if (inherits(resp_text, "try-error") || is.null(resp_text) || !nzchar(resp_text)) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  resp_clean <- trimws(resp_text)
  date_match <- regmatches(resp_clean, regexpr("\\d{4}-\\d{2}-\\d{2}", resp_clean))
  if (length(date_match) == 0 || !nzchar(date_match)) {
    br_match <- regmatches(resp_clean, regexpr("\\d{2}/\\d{2}/\\d{4}", resp_clean))
    if (length(br_match) > 0 && nzchar(br_match)) {
      partes <- strsplit(br_match, "/")[[1]]
      date_match <- sprintf("%s-%s-%s", partes[3], partes[2], partes[1])
    } else {
      return(list(data_limite = NA_character_, observacoes = NA_character_))
    }
  }
  parsed <- try(lubridate::ymd(date_match), silent = TRUE)
  if (inherits(parsed, "try-error") || is.na(parsed)) {
    return(list(data_limite = NA_character_, observacoes = NA_character_))
  }
  list(data_limite = format(parsed, "%Y-%m-%d"),
       observacoes = sprintf("Prazo extraido via visao LLM da imagem: %s", img_url))
}

.fetch_fapesb_category_page <- function(year, log_path = NULL) {
  cat_url <- "https://www.fapesb.ba.gov.br/category/edital/"
  resp <- try(safe_request_page(cat_url, log_path = log_path, use_browser_fallback = TRUE), silent = TRUE)
  if (inherits(resp, "try-error") || is.null(resp) || is.null(resp$html)) {
    if (!is.null(log_path)) log_write(log_path, "ERROR", "FAPESB: falha ao buscar pagina de categoria")
    return(NULL)
  }
  html <- resp$html
  year_str <- as.character(year)
  selected_btn <- rvest::html_element(html, "button.selecionado")
  selected_year <- rvest::html_attr(selected_btn, "value") %||% ""
  if (selected_year != year_str) {
    post_resp <- try({
      req <- httr2::request(cat_url) |>
        httr2::req_user_agent("FundingIntelligence/1.0") |>
        httr2::req_body_form(ano_filtro = year_str, ofsubmitted = "1") |>
        httr2::req_timeout(30)
      httr2::req_perform(req)
    }, silent = TRUE)
    if (!inherits(post_resp, "try-error") && httr2::resp_status(post_resp) == 200) {
      post_txt <- httr2::resp_body_string(post_resp)
      html <- try(xml2::read_html(post_txt), silent = TRUE)
      if (inherits(html, "try-error")) {
        if (!is.null(log_path)) log_write(log_path, "WARN", "FAPESB: falha ao parsear POST ano_filtro")
        return(resp$html)
      }
    }
  }
  html
}

.parse_fapesb_category_items <- function(html, year, log_path = NULL) {
  items_nodes <- rvest::html_elements(html, "#tab1 .edital-item")
  year_str <- as.character(year)
  parsed <- lapply(items_nodes, function(node) {
    title_node <- rvest::html_element(node, ".edital-title a")
    if (is.null(title_node) || inherits(title_node, "xml_missing")) return(NULL)
    href <- rvest::html_attr(title_node, "href") %||% ""
    titulo <- trimws(rvest::html_text2(title_node))
    if (!nzchar(href)) return(NULL)
    titulo_lower <- tolower(titulo)
    if (grepl("errata|retifica|prorrog", titulo_lower, fixed = FALSE)) return(NULL)
    contains_year <- grepl(year_str, titulo, fixed = TRUE)
    contains_prev <- grepl(as.character(year - 1L), titulo, fixed = TRUE)
    if (contains_prev && !contains_year) return(NULL)
    resumo_node <- rvest::html_element(node, "p")
    resumo <- if (!is.null(resumo_node) && !inherits(resumo_node, "xml_missing")) {
      trimws(rvest::html_text2(resumo_node))
    } else ""
    tibble::tibble(link_detalhe = href, titulo = titulo, resumo = resumo)
  })
  parsed <- Filter(Negate(is.null), parsed)
  if (length(parsed) == 0) return(tibble::tibble(link_detalhe = character(0), titulo = character(0), resumo = character(0)))
  dplyr::bind_rows(parsed)
}

.extract_fapesb_prazo_from_detail <- function(detail_html, detail_url, log_path = NULL) {
  html <- tryCatch(xml2::read_html(detail_html), error = function(e) NULL)
  if (is.null(html)) {
    return(list(data_limite = NA_character_, link_documento_pdf = NA_character_, observacoes = NA_character_, status = "html_parse_error"))
  }
  corpo_nodes <- tryCatch(
    rvest::html_elements(html, "#content .content-area, main#main article, #main .edital-item, .site-content article, .site-content #content"),
    error = function(e) NULL
  )
  if (is.null(corpo_nodes) || length(corpo_nodes) == 0) {
    corpo_nodes <- rvest::html_elements(html, "body")
  }
  corpo_html <- paste(vapply(corpo_nodes, as.character, character(1)), collapse = "\n")
  corpo_text <- gsub("<[^>]+>", " ", corpo_html)
  corpo_text <- gsub("&amp;", "&", corpo_text)
  corpo_text <- gsub("&nbsp;", " ", corpo_text)
  corpo_text <- gsub("\\s+", " ", trimws(corpo_text))
  data_limite <- NA_character_
  link_pdf <- NA_character_
  status <- "no_match"
  if (nchar(corpo_text) > 10) {
    data_limite <- .extract_deadline_from_cronograma_section(corpo_text)
  }
  if (!is.na(data_limite)) {
    parsed <- try(lubridate::ymd(data_limite), silent = TRUE)
    if (!inherits(parsed, "try-error") && !is.na(parsed)) {
      diff_days <- as.numeric(parsed - Sys.Date())
      if (diff_days >= 0 && diff_days <= 730) {
        if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("FAPESB prazo extraido via regex: %s", data_limite))
        return(list(data_limite = data_limite, link_documento_pdf = NA_character_, observacoes = NA_character_, status = "regex"))
      }
    }
  }
  data_limite <- NA_character_
  if (nchar(corpo_html) > 0) {
    link_pdf_node <- rvest::html_element(html, "a.link-pdf, a[class*='link-pdf']")
    if (!is.null(link_pdf_node) && !inherits(link_pdf_node, "xml_missing")) {
      link_pdf <- rvest::html_attr(link_pdf_node, "href")
    }
    if (is.na(link_pdf) || !nzchar(link_pdf)) {
      pdf_links <- try(extract_pdf_links(html, detail_url), silent = TRUE)
      if (!inherits(pdf_links, "try-error") && length(pdf_links) > 0) {
        edital_links <- pdf_links[grepl("edital|EDITAL", basename(pdf_links), ignore.case = FALSE)]
        link_pdf <- if (length(edital_links) > 0) edital_links[1] else pdf_links[1]
      }
    }
    if (!is.na(link_pdf) && nzchar(link_pdf)) {
      link_pdf <- resolve_url(detail_url, link_pdf)
      pdf_result <- try(.extract_fapesb_prazo_from_pdf(link_pdf, log_path), silent = TRUE)
      if (!inherits(pdf_result, "try-error") && !is.na(pdf_result$data_limite)) {
        if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("FAPESB prazo extraido via PDF: %s (%s)", pdf_result$data_limite, link_pdf))
        return(list(data_limite = pdf_result$data_limite, link_documento_pdf = link_pdf, observacoes = NA_character_, status = "pdf"))
      }
    }
  }
  vision_result <- try(.extract_fapesb_prazo_from_image_llm(corpo_html, detail_url, log_path), silent = TRUE)
  if (!inherits(vision_result, "try-error") && !is.na(vision_result$data_limite)) {
    if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("FAPESB prazo extraido via visao LLM: %s", vision_result$data_limite))
    return(list(data_limite = vision_result$data_limite, link_documento_pdf = NA_character_, observacoes = vision_result$observacoes %||% NA_character_, status = "vision_llm"))
  }
  if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("FAPESB: nenhuma estrategia extraiu prazo para %s", detail_url))
  list(data_limite = data_limite, link_documento_pdf = NA_character_, observacoes = NA_character_, status = status)
}

collect_fapesb <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta editais abertos da FAPESB via pagina de categoria (scraping HTML)
  #' URL: https://www.fapesb.ba.gov.br/category/edital/ (default = ano corrente, Abertos)
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[FAPESB][%s] %s", level, msg))
  }
  year <- as.integer(format(Sys.Date(), "%Y"))
  cat_url <- "https://www.fapesb.ba.gov.br/category/edital/"
  .log("INFO", sprintf("Coletando FAPESB via categoria (ano=%d, status=Abertos)...", year))
  html <- try(.fetch_fapesb_category_page(year, log_path), silent = TRUE)
  if (inherits(html, "try-error") || is.null(html)) {
    .log("ERROR", "Falha ao buscar pagina de categoria FAPESB")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = cat_url))
  }
  items <- try(.parse_fapesb_category_items(html, year, log_path), silent = TRUE)
  if (inherits(items, "try-error")) {
    .log("ERROR", "Falha ao parsear itens da categoria FAPESB")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = cat_url))
  }
  items <- head(items, max_records)
  n_items <- nrow(items)
  .log("INFO", sprintf("FAPESB: %d editais abertos em %d", n_items, year))
  if (n_items == 0) {
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = cat_url))
  }
  all_items <- list()
  for (i in seq_len(n_items)) {
    it <- items[i, ]
    .log("INFO", sprintf("[%d/%d] %s", i, n_items, substr(it$titulo, 1, 70)))
    hash_input <- paste0(it$link_detalhe, "|", it$titulo)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")
    detail <- try(safe_request_page(it$link_detalhe, log_path = log_path, use_browser_fallback = TRUE), silent = TRUE)
    if (inherits(detail, "try-error") || is.null(detail) || is.null(detail$html)) {
      .log("WARN", sprintf("Falha ao buscar detalhe: %s", it$link_detalhe))
      all_items[[i]] <- tibble::tibble(
        id_registro = sprintf("fapesb_%s", substr(hash_dedup, 1, 16)),
        entidade = "FAPESB", pais_origem = "Brasil",
        titulo = it$titulo, subtitulo = NA_character_,
        descricao_resumida = it$resumo, descricao_completa = it$resumo,
        tipo_oportunidade = "Edital", modalidade = NA_character_,
        area_tematica = NA_character_, palavras_chave = "edital",
        elegibilidade = NA_character_, publico_alvo = NA_character_,
        nivel_academico = NA_character_,
        instituicao_financiadora = "Fundacao de Amparo a Pesquisa do Estado da Bahia",
        valor_financiado = NA_real_, moeda = NA_character_,
        data_publicacao = NA_character_, data_abertura = NA_character_,
        data_limite = NA_character_, data_encerramento = NA_character_,
        status_oportunidade = "aberto",
        link_origem = cat_url, link_detalhe = it$link_detalhe,
        link_documento_pdf = NA_character_,
        idioma = "pt", localidade = "Bahia",
        observacoes = sprintf("Resumo: %s", it$resumo),
        texto_bruto = it$titulo, pagina_coletada = 1L,
        fonte_oficial = "fapesb",
        data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        hash_deduplicacao = hash_dedup, campos_inferidos_ia = NA_character_
      )
      next
    }
    detail_html_str <- detail$text %||% as.character(detail$html)
    prazo <- try(.extract_fapesb_prazo_from_detail(detail_html_str, it$link_detalhe, log_path), silent = TRUE)
    if (inherits(prazo, "try-error")) {
      prazo <- list(data_limite = NA_character_, link_documento_pdf = NA_character_, observacoes = NA_character_, status = "error")
    }
    corpo_nodes <- tryCatch(
      rvest::html_elements(detail$html, "#content .content-area, main#main article, #main .edital-item, .site-content article"),
      error = function(e) NULL
    )
    corpo_html_str <- if (!is.null(corpo_nodes) && length(corpo_nodes) > 0) {
      paste(vapply(corpo_nodes, as.character, character(1)), collapse = "\n")
    } else detail_html_str
    corpo_text <- gsub("<[^>]+>", " ", corpo_html_str)
    corpo_text <- gsub("\\s+", " ", trimws(corpo_text))
    if (nchar(corpo_text) > 1500) corpo_text <- substr(corpo_text, 1, 1500)
    obs_parts <- c(
      if (!is.na(prazo$observacoes) && nzchar(prazo$observacoes)) prazo$observacoes,
      if (nchar(it$resumo) > 0) sprintf("Resumo: %s", substr(it$resumo, 1, 400)),
      sprintf("Status extracao: %s", prazo$status %||% "unknown")
    )
    obs <- paste(obs_parts, collapse = " | ")
    Sys.sleep(0.5)
    all_items[[i]] <- tibble::tibble(
      id_registro = sprintf("fapesb_%s", substr(hash_dedup, 1, 16)),
      entidade = "FAPESB", pais_origem = "Brasil",
      titulo = it$titulo, subtitulo = NA_character_,
      descricao_resumida = if (nchar(corpo_text) > 0) substr(corpo_text, 1, 500) else it$titulo,
      descricao_completa = if (nchar(corpo_text) > 0) corpo_text else it$titulo,
      tipo_oportunidade = "Edital", modalidade = NA_character_,
      area_tematica = NA_character_, palavras_chave = "edital",
      elegibilidade = NA_character_, publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "Fundacao de Amparo a Pesquisa do Estado da Bahia",
      valor_financiado = NA_real_, moeda = NA_character_,
      data_publicacao = NA_character_, data_abertura = NA_character_,
      data_limite = prazo$data_limite, data_encerramento = NA_character_,
      status_oportunidade = "aberto",
      link_origem = cat_url, link_detalhe = it$link_detalhe,
      link_documento_pdf = prazo$link_documento_pdf,
      idioma = "pt", localidade = "Bahia",
      observacoes = obs,
      texto_bruto = paste(it$titulo, corpo_text, sep = "\n\n"),
      pagina_coletada = 1L, fonte_oficial = "fapesb",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup, campos_inferidos_ia = NA_character_
    )
  }
  records <- dplyr::bind_rows(all_items)
  .log("INFO", sprintf("FAPESB: %d registros finais coletados", nrow(records)))
  return(list(records = records, pages_visited = 1L, last_url = cat_url))
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

  tryCatch(
    {
      readr::write_csv(clean_df, csv_path, na = "")
      export_paths <- c(export_paths, csv_path)
    },
    error = function(e) {
      export_warnings <<- c(export_warnings, paste0("Falha ao exportar CSV: ", e$message))
      if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
    }
  )

  tryCatch(
    {
      saveRDS(clean_df, rds_path)
      export_paths <- c(export_paths, rds_path)
    },
    error = function(e) {
      export_warnings <<- c(export_warnings, paste0("Falha ao exportar RDS: ", e$message))
      if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
    }
  )

  tryCatch(
    {
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
            if (!is.character(clean_df[[nm]])) {
              return(FALSE)
            }
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
    },
    error = function(e) {
      export_warnings <<- c(export_warnings, paste0("Falha ao exportar XLSX: ", e$message))
      if (!is.null(log_path)) log_write(log_path, "WARN", export_warnings[[length(export_warnings)]])
    }
  )

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
  try(
    {
      if (file.exists(status_file)) file.remove(status_file)
      if (file.exists(log_file)) file.remove(log_file)
    },
    silent = TRUE
  )

  # Limpar erros antigos de logs_coleta para evitar falsos positivos no modal de alerta
  tryCatch(
    {
      DBI::dbExecute(conn, "DELETE FROM logs_coleta WHERE status_execucao = 'erro'")
      log_write(log_path, "INFO", "Logs de erro antigos removidos de logs_coleta.")
    },
    error = function(e) {
      log_write(log_path, "WARN", sprintf("Falha ao limpar logs de erro: %s", e$message))
    }
  )

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
    effective_max <- if (sid %in% c("horizon_europe", "erc", "quantum")) 100L else max_records_per_source

    result <- tryCatch(
      {
        source_dispatch(
          source_row = src,
          max_pages = max_pages,
          max_records = effective_max,
          use_ai = use_ai,
          log_path = log_path,
          conn = conn
        )
      },
      error = function(e) {
        log_write(log_path, "ERROR", sprintf("Falha na fonte %s: %s", sid, e$message))
        log_collection(conn, sid, src$metodo_coleta[[1]], "erro", e$message, n_paginas = 0L, n_registros = 0L, url = src$url_oportunidades[[1]])
        NULL
      }
    )

    if (is.null(result)) next

    recs <- tryCatch(finalize_records(result$records, fonte_oficial = result$source_id %||% sid), error = function(e) {
      log_write(log_path, "ERROR", sprintf("Falha ao finalizar registros da fonte %s: %s", sid, e$message))
      ensure_record_schema(tibble::tibble())
    })

    # Traduzir registros EU para pt-br (habilitado por padrao, desabilitar com AI_TRANSLATE_EU=false)
    translate_eu <- identical(tolower(Sys.getenv("AI_TRANSLATE_EU", "true")), "true")
    is_eu_source <- sid %in% c("horizon_europe", "erc")
    if (translate_eu && is_eu_source && nrow(recs) > 0) {
      recs <- tryCatch(translate_to_pt_br(recs, log_path = log_path), error = function(e) {
        log_write(log_path, "WARN", sprintf("Falha na traducao para fonte %s: %s", sid, e$message))
        recs
      })
    }

    n_inserted <- tryCatch(upsert_opportunities(conn, recs), error = function(e) {
      log_write(log_path, "ERROR", sprintf("Falha ao inserir registros da fonte %s: %s", sid, e$message))
      0L
    })
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

  if (inserted_total == 0L) {
    status_data <- list(
      step = total,
      total = total,
      percentage = 100,
      detail = "Coleta finalizada — nenhum registro novo nesta rodada. Verifique filtros/ano ou logs.",
      phase = "Atenção",
      timestamp = as.character(Sys.time()),
      status = "warning"
    )
    try(jsonlite::write_json(status_data, status_file, auto_unbox = TRUE), silent = TRUE)
    log_progress("Coleta finalizada — nenhum registro novo nesta rodada.", "Atenção")
    log_write(log_path, "WARN", sprintf("Coleta finalizada sem novos registros: %s fonte(s) processadas, %s registros na base.", processed, nrow(final_df)))
  } else {
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
  }

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
    source_ids = source_ids,
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

collect_sigitec <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta oportunidades da Petrobras SIGITEC via API REST pública
  #' API retorna todos os registros de uma vez (sem paginação)
  #' Detalhes via endpoint público por ID

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[SIGITEC][%s] %s", level, msg))
  }

  base_url <- "https://sigitec-competitividade.petrobras.com.br"
  listing_url <- paste0(base_url, "/v2/ms-authorization/opportunity/getAllPublicOpportunities")
  detail_base <- paste0(base_url, "/v2/ms-authorization/opportunity/public-opportunity/")

  .log("INFO", "Iniciando coleta SIGITEC Petrobras via API REST...")

  # Pre-flight: verificar conectividade
  if (!is_host_alive(listing_url)) {
    .log("WARN", "API SIGITEC inacessivel. Pulando coleta.")
    try(log_progress("AVISO: API SIGITEC inacessivel - pulando", "Scraping"), silent = TRUE)
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = listing_url))
  }

  # ETAPA 1: Buscar listing completo
  .log("INFO", "Buscando listing de oportunidades...")
  user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

  req <- httr2::request(listing_url) |>
    httr2::req_user_agent(user_agent) |>
    httr2::req_headers(
      `Accept` = "application/json, text/plain, */*",
      `Accept-Language` = "pt-BR,pt;q=0.9,en;q=0.8",
      `Referer` = paste0(base_url, "/v2/public/opportunities"),
      `Origin` = base_url
    ) |>
    httr2::req_timeout(30) |>
    httr2::req_retry(max_tries = 3, backoff = function(x) 2^x)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) {
    .log("ERROR", sprintf("Falha ao buscar listing: %s", e$message))
    NULL
  })

  if (is.null(resp) || httr2::resp_status(resp) != 200) {
    .log("WARN", "Listing retornou erro. Tentando fallback Playwright...")
    return(collect_sigitec_fallback(source_row, max_records, log_path))
  }

  all_items <- tryCatch(httr2::resp_body_json(resp), error = function(e) {
    .log("ERROR", sprintf("Falha ao parsear JSON: %s", e$message))
    NULL
  })

  if (is.null(all_items) || length(all_items) == 0) {
    .log("WARN", "Listing vazio.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = listing_url))
  }

  .log("INFO", sprintf("Listing retornou %d registros total.", length(all_items)))

  # Filtrar apenas status "A" (Aberta)
  open_items <- Filter(function(x) identical(x$status, "A"), all_items)
  .log("INFO", sprintf("Registros com status Aberto: %d", length(open_items)))

  if (length(open_items) == 0) {
    .log("WARN", "Nenhuma oportunidade aberta encontrada.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = listing_url))
  }

  # Limitar a max_records
  if (length(open_items) > max_records) {
    open_items <- open_items[seq_len(max_records)]
    .log("WARN", sprintf("Limitado a %d registros.", max_records))
  }

  # ETAPA 2: Buscar detalhes de cada oportunidade
  .log("INFO", sprintf("Buscando detalhes de %d oportunidades...", length(open_items)))

  records <- list()
  detail_failures <- 0L

  for (i in seq_along(open_items)) {
    item <- open_items[[i]]
    item_id <- item$id

    # Rate limiting: 0.5s entre requests
    if (i > 1) Sys.sleep(0.5)

    # Buscar detalhe
    detail_url <- paste0(detail_base, item_id)
    detail_req <- httr2::request(detail_url) |>
      httr2::req_user_agent(user_agent) |>
      httr2::req_headers(
        `Accept` = "application/json, text/plain, */*",
        `Referer` = paste0(base_url, "/v2/public/opportunities"),
        `Origin` = base_url
      ) |>
      httr2::req_timeout(15) |>
      httr2::req_retry(max_tries = 2)

    detail_resp <- tryCatch(httr2::req_perform(detail_req), error = function(e) NULL)

    detail <- NULL
    if (!is.null(detail_resp) && httr2::resp_status(detail_resp) == 200) {
      detail <- tryCatch(httr2::resp_body_json(detail_resp), error = function(e) NULL)
    }

    if (is.null(detail)) {
      detail_failures <- detail_failures + 1L
      .log("WARN", sprintf("Detalhe falhou para ID %d, usando dados do listing.", item_id))
      detail <- item  # Fallback para dados do listing
    }

    # Mapear campos para schema do banco
    number_op <- detail$numberOP %||% item$numberOP %||% ""
    title_op <- detail$titleOP %||% item$titleOP %||% ""
    titulo <- if (nzchar(as.character(number_op))) {
      sprintf("OP%d - %s", number_op, title_op)
    } else {
      as.character(title_op)
    }

    # Datas
    deadline_raw <- detail$deadlineSubmissionOfProposal %||% item$deadlineSubmissionOfProposal %||% NA_character_
    deadline <- if (!is.na(deadline_raw) && nzchar(deadline_raw)) {
      as.character(as.Date(substr(deadline_raw, 1, 10)))
    } else {
      NA_character_
    }

    pub_raw <- detail$publicationDate %||% item$publicationDate %||% NA_character_
    pub_date <- if (!is.na(pub_raw) && nzchar(pub_raw)) {
      as.character(as.Date(substr(pub_raw, 1, 10)))
    } else {
      NA_character_
    }

    # Descrição
    objective <- detail$objective %||% item$objective %||% ""
    challenge <- detail$challenge %||% item$challenge %||% ""
    description <- if (nzchar(as.character(challenge))) {
      paste0("Desafio: ", challenge, "\n\nObjetivo: ", objective)
    } else {
      as.character(objective)
    }

    # Área temática
    theme <- detail$theme %||% item$theme %||% ""
    sub_theme <- detail$subTheme %||% item$subTheme %||% ""
    area_tematica <- if (nzchar(as.character(sub_theme))) {
      paste0(theme, " - ", sub_theme)
    } else if (nzchar(as.character(theme))) {
      as.character(theme)
    } else {
      detail$area %||% item$area %||% NA_character_
    }

    # TRL/CRL (valores já vem com prefixo "TRL"/"CRL" da API)
    trl <- detail$intendedTrl %||% item$intendedTrl %||% ""
    crl <- detail$intendedCrl %||% item$intendedCrl %||% ""
    nivel_tech <- if (nzchar(as.character(trl)) && nzchar(as.character(crl))) {
      paste0(trl, " / ", crl)
    } else if (nzchar(as.character(trl))) {
      as.character(trl)
    } else if (nzchar(as.character(crl))) {
      as.character(crl)
    } else {
      NA_character_
    }

    # Expectativas
    expected_solution <- detail$expectedSolution %||% item$expectedSolution %||% ""
    expected_detail <- detail$expectedSolutionDetail %||% item$expectedSolutionDetail %||% ""
    observacoes <- if (nzchar(as.character(expected_solution)) && nzchar(as.character(expected_detail))) {
      paste0("Solução esperada: ", expected_solution, ". ", expected_detail)
    } else if (nzchar(as.character(expected_solution))) {
      paste0("Solução esperada: ", expected_solution)
    } else if (nzchar(as.character(expected_detail))) {
      as.character(expected_detail)
    } else {
      NA_character_
    }

    # Status
    status_map <- c("A" = "aberto", "J" = "julgamento", "F" = "finalizado", "C" = "cancelado")
    status_db <- unname(status_map[detail$status %||% item$status %||% "A"])
    if (is.na(status_db)) status_db <- "aberto"

    # Link de detalhe (URL pública do React)
    link_detalhe <- paste0(base_url, "/v2/public/opportunity/", item_id)

    # Hash de deduplicação
    hash_input <- paste0(titulo, "|", link_detalhe)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    # Montar registro
    rec <- tibble::tibble(
      id_registro = sprintf("sigitec_%s", substr(hash_dedup, 1, 16)),
      entidade = "PETROBRAS",
      pais_origem = "Brasil",
      titulo = titulo,
      subtitulo = NA_character_,
      descricao_resumida = substr(as.character(description), 1, 500),
      descricao_completa = as.character(description),
      tipo_oportunidade = "edital",
      modalidade = "competitividade",
      area_tematica = as.character(area_tematica),
      palavras_chave = detail$area %||% item$area %||% NA_character_,
      elegibilidade = detail$commitment %||% item$commitment %||% NA_character_,
      publico_alvo = "ICT, empresas",
      nivel_academico = nivel_tech,
      instituicao_financiadora = "Petrobras",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = pub_date,
      data_abertura = NA_character_,
      data_limite = deadline,
      data_encerramento = NA_character_,
      status_oportunidade = status_db,
      link_origem = paste0(base_url, "/v2/public/opportunities"),
      link_detalhe = link_detalhe,
      link_documento_pdf = NA_character_,
      idioma = "pt",
      localidade = "Brasil",
      observacoes = observacoes,
      texto_bruto = paste(collapse_non_empty(titulo, description, area_tematica, observacoes), collapse = "\n"),
      pagina_coletada = 1L,
      fonte_oficial = "sigitec",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )

    records[[i]] <- rec

    if (i %% 10 == 0) {
      .log("INFO", sprintf("Progresso: %d/%d detalhes coletados.", i, length(open_items)))
    }
  }

  # Combinar registros
  if (length(records) == 0) {
    .log("WARN", "Nenhum registro coletado.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = listing_url))
  }

  df <- dplyr::bind_rows(records)

  if (detail_failures > 0) {
    .log("WARN", sprintf("Falhas no detalhe: %d/%d (usados dados do listing).", detail_failures, length(open_items)))
  }

  .log("INFO", sprintf("SIGITEC: %d registros finais coletados (%d abertos de %d total).", nrow(df), length(open_items), length(all_items)))

  list(records = df, pages_visited = 1L, last_url = listing_url)
}

collect_sigitec_fallback <- function(source_row, max_records, log_path) {
  #' Fallback: Playwright para renderizar SPA e extrair dados do DOM
  #' Usado quando a API REST retorna erro

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[SIGITEC-FB][%s] %s", level, msg))
  }

  .log("INFO", "Tentando fallback via Playwright...")

  page_url <- source_row$url_oportunidades[[1]]
  pg <- safe_request_page_playwright(page_url, log_path = log_path)

  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", "Playwright falhou. Tentando Chromote...")
    pg <- safe_request_page(page_url, log_path = log_path, use_browser_fallback = TRUE)
  }

  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("ERROR", "Todos os métodos de rendering falharam.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = page_url))
  }

  .log("INFO", "Página renderizada. Extraindo candidatos do DOM...")

  # Usar extract_listing_candidates genérica
  candidates <- extract_listing_candidates(pg$html, page_url, source_row)

  if (nrow(candidates) == 0) {
    .log("WARN", "Nenhum candidato extraído do DOM.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = page_url))
  }

  # Limitar a max_records
  if (nrow(candidates) > max_records) {
    candidates <- candidates[seq_len(max_records), ]
  }

  .log("INFO", sprintf("Fallback: %d candidatos extraídos.", nrow(candidates)))

  # Converter candidatos para schema padrao
  recs <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
    cand <- candidates[i, ]
    hash_input <- paste0(cand$candidate_title, "|", cand$detail_url %||% cand$detail_url)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    tibble::tibble(
      id_registro = sprintf("sigitec_%s", substr(hash_dedup, 1, 16)),
      entidade = "PETROBRAS",
      pais_origem = "Brasil",
      titulo = cand$candidate_title,
      subtitulo = NA_character_,
      descricao_resumida = substr(cand$candidate_summary %||% cand$candidate_title, 1, 500),
      descricao_completa = cand$candidate_summary %||% cand$candidate_title,
      tipo_oportunidade = "edital",
      modalidade = "competitividade",
      area_tematica = NA_character_,
      palavras_chave = NA_character_,
      elegibilidade = NA_character_,
      publico_alvo = "ICT, empresas",
      nivel_academico = NA_character_,
      instituicao_financiadora = "Petrobras",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = NA_character_,
      data_encerramento = NA_character_,
      status_oportunidade = "aberto",
      link_origem = page_url,
      link_detalhe = as.character(cand$detail_url %||% NA_character_),
      link_documento_pdf = as.character(cand$pdf_url %||% NA_character_),
      idioma = "pt",
      localidade = "Brasil",
      observacoes = NA_character_,
      texto_bruto = cand$candidate_summary %||% cand$candidate_title,
      pagina_coletada = 1L,
      fonte_oficial = "sigitec",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )
  })

  list(records = recs, pages_visited = 1L, last_url = page_url)
}

collect_undp <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta oportunidades da UNDP Brasil via componente externo (JSON)
  #' Dados vêm de public-components.undp.org como JavaScript com JSON embutido
  #' Detalhes via procurement-notices.undp.org (HTML estático)

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[UNDP][%s] %s", level, msg))
  }

  component_url <- "https://public-components.undp.org/?comp=proc_notices&cty_id_c=BRA&style_type=table"
  detail_base <- "https://procurement-notices.undp.org/view_negotiation.cfm?nego_id="

  .log("INFO", "Iniciando coleta UNDP Brasil via componente externo...")

  # Pre-flight: verificar conectividade
  if (!is_host_alive(component_url)) {
    .log("WARN", "Componente UNDP inacessivel. Pulando coleta.")
    try(log_progress("AVISO: Componente UNDP inacessivel - pulando", "Scraping"), silent = TRUE)
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = component_url))
  }

  # ETAPA 1: Buscar componente externo (retorna JavaScript com JSON)
  .log("INFO", "Buscando componente de dados...")
  user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

  req <- httr2::request(component_url) |>
    httr2::req_user_agent(user_agent) |>
    httr2::req_headers(
      `Accept` = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      `Accept-Language` = "pt-BR,pt;q=0.9,en;q=0.8",
      `Referer` = "https://www.undp.org/pt/brazil/licitacoes"
    ) |>
    httr2::req_timeout(20) |>
    httr2::req_retry(max_tries = 3, backoff = function(x) 2^x)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) {
    .log("ERROR", sprintf("Falha ao buscar componente: %s", e$message))
    NULL
  })

  if (is.null(resp) || httr2::resp_status(resp) != 200) {
    .log("WARN", "Componente retornou erro.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = component_url))
  }

  js_text <- tryCatch(httr2::resp_body_string(resp, encoding = "UTF-8"), error = function(e) {
    .log("ERROR", sprintf("Falha ao ler resposta: %s", e$message))
    NULL
  })

  if (is.null(js_text) || !nzchar(js_text)) {
    .log("WARN", "Resposta vazia do componente.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = component_url))
  }

  # ETAPA 2: Extrair JSON do JavaScript
  .log("INFO", "Parseando JSON do componente JavaScript...")

  # Encontrar o início do JSON: padrão = callback_name({"recordcount":
  json_start_pattern <- '\\(\\{"recordcount":'
  json_match <- regmatches(js_text, regexpr(json_start_pattern, js_text))

  if (length(json_match) == 0 || !nzchar(json_match)) {
    .log("WARN", "Padrão JSON não encontrado na resposta do componente.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = component_url))
  }

  # Encontrar posição do início do JSON (após o parêntese)
  json_start_idx <- regexpr('\\(\\{', js_text)
  json_start <- attr(json_start_idx, "match.length") - 1 + as.integer(json_start_idx)

  # Encontrar o fechamento correspondente do JSON (contar chaves)
  depth <- 0L
  json_end <- json_start
  chars <- strsplit(js_text, "")[[1]]
  for (i in json_start:length(chars)) {
    if (chars[i] == "{") depth <- depth + 1L
    if (chars[i] == "}") {
      depth <- depth - 1L
      if (depth == 0L) {
        json_end <- i
        break
      }
    }
  }

  json_str <- paste(chars[json_start:json_end], collapse = "")

  # Parsear JSON
  parsed <- tryCatch(jsonlite::fromJSON(json_str, simplifyVector = FALSE), error = function(e) {
    .log("ERROR", sprintf("Falha ao parsear JSON: %s", e$message))
    NULL
  })

  if (is.null(parsed) || is.null(parsed$recordcount) || parsed$recordcount == 0) {
    .log("WARN", "JSON vazio ou sem registros.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = component_url))
  }

  n_records <- parsed$recordcount
  data <- parsed$data
  .log("INFO", sprintf("Componente retornou %d registros.", n_records))

  # Limitar a max_records
  if (n_records > max_records) {
    n_records <- max_records
    .log("WARN", sprintf("Limitado a %d registros.", max_records))
  }

  # ETAPA 3: Processar cada registro
  records <- list()
  detail_failures <- 0L

  for (i in seq_len(n_records)) {
    title_raw <- data$title[[i]] %||% ""
    notice_id <- data$notice_id[[i]] %||% ""
    link <- data$link[[i]] %||% ""
    posted <- data$posted_d[[i]] %||% ""
    deadline <- data$deadline[[i]] %||% ""
    area <- data$area_desc[[i]] %||% ""
    duty_station <- data$duty_station[[i]] %||% ""

    # Limpar título: remover " - UNDP - BRAZIL" do final
    titulo <- gsub("\\s*-\\s*UNDP\\s*-\\s*BRAZIL\\s*$", "", title_raw, ignore.case = TRUE)
    titulo <- trimws(titulo)

    # Converter datas
    data_publicacao <- tryCatch({
      d <- as.Date(substr(posted, 1, 10))
      as.character(d)
    }, error = function(e) NA_character_)

    data_limite <- tryCatch({
      d <- as.Date(substr(deadline, 1, 10))
      as.character(d)
    }, error = function(e) NA_character_)

    # Extrair nego_id do link
    nego_id <- sub(".*nego_id=(\\d+).*", "\\1", link)

    # Buscar detalhe (HTML estático)
    detail_text <- ""
    detail_url <- paste0(detail_base, nego_id)

    if (nzchar(nego_id)) {
      if (i > 1) Sys.sleep(0.3)

      detail_req <- httr2::request(detail_url) |>
        httr2::req_user_agent(user_agent) |>
        httr2::req_timeout(15) |>
        httr2::req_retry(max_tries = 2)

      detail_resp <- tryCatch(httr2::req_perform(detail_req), error = function(e) NULL)

      if (!is.null(detail_resp) && httr2::resp_status(detail_resp) == 200) {
        detail_html <- tryCatch(httr2::resp_body_string(detail_resp, encoding = "UTF-8"), error = function(e) NULL)
        if (!is.null(detail_html) && nzchar(detail_html)) {
          detail_text <- .parse_undp_detail(detail_html)
          if (i == 1) .log("INFO", "Detalhe parseado com sucesso.")
        }
      } else {
        detail_failures <- detail_failures + 1L
      }
    }

    # Descrição: usar Introduction do detalhe ou título
    descricao <- if (nzchar(detail_text$introduction)) {
      detail_text$introduction
    } else {
      titulo
    }

    # Montar registro
    hash_input <- paste0(titulo, "|", detail_url)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    rec <- tibble::tibble(
      id_registro = sprintf("undp_%s", substr(hash_dedup, 1, 16)),
      entidade = "UNDP",
      pais_origem = "Brasil",
      titulo = titulo,
      subtitulo = detail_text$procurement_process %||% NA_character_,
      descricao_resumida = substr(descricao, 1, 500),
      descricao_completa = descricao,
      tipo_oportunidade = "licitacao",
      modalidade = detail_text$procurement_process %||% NA_character_,
      area_tematica = if (identical(area, "OTHER")) "Multitemático" else area,
      palavras_chave = NA_character_,
      elegibilidade = NA_character_,
      publico_alvo = "Empresas, consultores",
      nivel_academico = NA_character_,
      instituicao_financiadora = "United Nations Development Programme",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = data_publicacao,
      data_abertura = NA_character_,
      data_limite = data_limite,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = data_limite, text = titulo)[[1]],
      link_origem = "https://www.undp.org/pt/brazil/licitacoes",
      link_detalhe = detail_url,
      link_documento_pdf = NA_character_,
      idioma = "pt",
      localidade = "Brasil",
      observacoes = paste(collapse_non_empty(
        detail_text$office %||% "",
        detail_text$contact %||% ""
      ), collapse = " | "),
      texto_bruto = paste(collapse_non_empty(titulo, descricao, detail_text$office, detail_text$contact), collapse = "\n"),
      pagina_coletada = 1L,
      fonte_oficial = "undp",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )

    records[[i]] <- rec

    if (i %% 5 == 0) {
      .log("INFO", sprintf("Progresso: %d/%d registros processados.", i, n_records))
    }
  }

  if (length(records) == 0) {
    .log("WARN", "Nenhum registro coletado.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = component_url))
  }

  df <- dplyr::bind_rows(records)

  if (detail_failures > 0) {
    .log("WARN", sprintf("Falhas no detalhe: %d/%d (usados dados do listing).", detail_failures, n_records))
  }

  .log("INFO", sprintf("UNDP: %d registros finais coletados.", nrow(df)))

  list(records = df, pages_visited = 1L, last_url = component_url)
}

.parse_undp_detail <- function(html_text) {
  #' Parseia a página de detalhe UNDP (HTML estático)
  #' Extrai campos estruturados: procurement process, office, deadline, etc.

  result <- list(
    procurement_process = NA_character_,
    office = NA_character_,
    deadline_text = NA_character_,
    published_on = NA_character_,
    reference_number = NA_character_,
    contact = NA_character_,
    introduction = NA_character_
  )

  # Limpar HTML para texto
  clean <- gsub("<[^>]+>", " ", html_text)
  clean <- gsub("\\s+", " ", clean)
  clean <- trimws(clean)

  # Extrair campos por padrão de rótulo
  extract_field <- function(label, text) {
    pattern <- paste0(label, "\\s+(.+?)(?=\\s+(?:Office|Deadline|Published|Reference|Contact|Introduction|This specific|$))")
    m <- regmatches(text, regexpr(pattern, text, perl = TRUE))
    if (length(m) > 0 && nzchar(m)) {
      val <- sub(paste0("^", label, "\\s+"), "", m)
      trimws(val)
    } else {
      NA_character_
    }
  }

  # Procurement Process
  pp_match <- regmatches(clean, regexpr("Procurement Process\\s+(.+?)(?=\\s+Office)", clean, perl = TRUE))
  if (length(pp_match) > 0) result$procurement_process <- trimws(sub("^Procurement Process\\s+", "", pp_match))

  # Office
  off_match <- regmatches(clean, regexpr("Office\\s+(.+?)(?=\\s+Deadline)", clean, perl = TRUE))
  if (length(off_match) > 0) result$office <- trimws(sub("^Office\\s+", "", off_match))

  # Deadline
  dl_match <- regmatches(clean, regexpr("Deadline\\s+(.+?)(?=\\s+Published)", clean, perl = TRUE))
  if (length(dl_match) > 0) result$deadline_text <- trimws(sub("^Deadline\\s+", "", dl_match))

  # Published on
  pub_match <- regmatches(clean, regexpr("Published on\\s+(.+?)(?=\\s+Reference)", clean, perl = TRUE))
  if (length(pub_match) > 0) result$published_on <- trimws(sub("^Published on\\s+", "", pub_match))

  # Reference Number
  ref_match <- regmatches(clean, regexpr("Reference Number\\s+(.+?)(?=\\s+Contact)", clean, perl = TRUE))
  if (length(ref_match) > 0) result$reference_number <- trimws(sub("^Reference Number\\s+", "", ref_match))

  # Contact
  cnt_match <- regmatches(clean, regexpr("Contact\\s+(.+?)(?=\\s+This specific|$)", clean, perl = TRUE))
  if (length(cnt_match) > 0) result$contact <- trimws(sub("^Contact\\s+", "", cnt_match))

  # Introduction (texto após "Introduction")
  intro_idx <- regexpr("Introduction\\s", clean)
  if (intro_idx > 0) {
    intro_start <- as.integer(intro_idx) + attr(intro_idx, "match.length")
    intro_text <- substr(clean, intro_start, nchar(clean))
    # Cortar em截máx 2000 chars
    if (nchar(intro_text) > 2000) intro_text <- substr(intro_text, 1, 2000)
    result$introduction <- trimws(intro_text)
  }

  result
}

# --- EMBRAPII Collector ---
collect_embrapii <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta chamadas públicas da EMBRAPII via parsing HTML estático.
  #' Strategy: fetch transparency page → parse div listing → follow detail links → parse schedule + docs.

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[EMBRAPII][%s] %s", level, msg))
  }

  .log("INFO", "Iniciando coleta EMBRAPII (embrapii.org.br/transparencia/).")
  try(log_progress("Iniciando coleta EMBRÁPII", "INICIO"), silent = TRUE)

  user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"
  base_url <- "https://embrapii.org.br"
  transparency_url <- paste0(base_url, "/transparencia/")

  # 1. Fetch transparency page
  req <- httr2::request(transparency_url) |>
    httr2::req_user_agent(user_agent) |>
    httr2::req_timeout(20) |>
    httr2::req_retry(max_tries = 3)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp) || httr2::resp_status(resp) != 200) {
    .log("ERROR", "Falha ao acessar pagina de transparencia EMBRAPII.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = transparency_url))
  }

  html_text <- httr2::resp_body_string(resp, encoding = "UTF-8")
  html <- rvest::read_html(html_text)

  # 2. Parse chamadas listing from #chamadas section
  chamadas_section <- rvest::html_node(html, "#chamadas")
  if (is.null(chamadas_section) || inherits(chamadas_section, "xml_missing")) {
    .log("WARN", "Secao #chamadas nao encontrada. Tentando listagem alternativa.")
    chamadas_section <- rvest::html_node(html, ".listagem-chamadas-publicas")
    if (is.null(chamadas_section) || inherits(chamadas_section, "xml_missing")) {
      .log("ERROR", "Nenhuma listagem de chamadas encontrada.")
      return(list(records = tibble::tibble(), pages_visited = 1L, last_url = transparency_url))
    }
  }

  # Extract all chamada items with URLs
  items <- rvest::html_nodes(chamadas_section, ".single-item-listagem, .single-chamada-publica")
  if (length(items) == 0) {
    .log("WARN", "Nenhum item de chamada encontrado na listagem.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = transparency_url))
  }

  titles_raw <- character(length(items))
  urls_raw <- character(length(items))
  years_raw <- character(length(items))

  for (i in seq_along(items)) {
    item <- items[[i]]
    # Title: try .title-single-item-listagem first, then .title-single-chamada-publica
    title_node <- rvest::html_node(item, ".title-single-item-listagem, .title-single-chamada-publica")
    titles_raw[i] <- if (!is.null(title_node) && !inherits(title_node, "xml_missing")) {
      trimws(rvest::html_text(title_node, trim = TRUE))
    } else {
      ""
    }
    # URL: first <a> with href containing chamadas-publicas
    links <- rvest::html_nodes(item, "a[href*='chamadas-publicas']")
    urls_raw[i] <- if (length(links) > 0) {
      rvest::html_attr(links[[1]], "href")
    } else {
      ""
    }
    # Year from data-year attribute
    years_raw[i] <- rvest::html_attr(item, "data-year") %||% ""
  }

  # Filter: keep only items with valid URLs
  valid <- nzchar(urls_raw) & nzchar(titles_raw)
  titles_raw <- titles_raw[valid]
  urls_raw <- urls_raw[valid]
  years_raw <- years_raw[valid]

  # Deduplicate by URL (chamadas appear twice in DOM)
  dedup <- !duplicated(urls_raw)
  titles_raw <- titles_raw[dedup]
  urls_raw <- urls_raw[dedup]
  years_raw <- years_raw[dedup]

  n_chamadas <- length(urls_raw)
  .log("INFO", sprintf("Encontradas %d chamadas unicas na pagina de transparencia.", n_chamadas))
  try(log_progress(sprintf("Encontradas %d chamadas unicas", n_chamadas), "LISTING"), silent = TRUE)

  if (n_chamadas == 0) {
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = transparency_url))
  }

  # 3. Fetch detail pages and build records
  records <- vector("list", n_chamadas)
  detail_failures <- 0L

  for (i in seq_len(n_chamadas)) {
    titulo <- titles_raw[[i]]
    detail_url <- urls_raw[[i]]
    year_val <- years_raw[[i]]

    if (i > 1) Sys.sleep(0.4)

    detail_html_text <- NULL
    detail_req <- httr2::request(detail_url) |>
      httr2::req_user_agent(user_agent) |>
      httr2::req_timeout(15) |>
      httr2::req_retry(max_tries = 2)

    detail_resp <- tryCatch(httr2::req_perform(detail_req), error = function(e) NULL)

    if (!is.null(detail_resp) && httr2::resp_status(detail_resp) == 200) {
      detail_html_text <- tryCatch(httr2::resp_body_string(detail_resp, encoding = "UTF-8"), error = function(e) NULL)
    } else {
      detail_failures <- detail_failures + 1L
    }

    # Parse detail page
    detail <- list(
      descricao = NA_character_,
      modalidade = NA_character_,
      publico_alvo = NA_character_,
      data_abertura = NA_character_,
      data_limite = NA_character_,
      docs = character(0)
    )

    if (!is.null(detail_html_text) && nzchar(detail_html_text)) {
      detail <- .parse_embrapii_detail(detail_html_text)
      if (i == 1) .log("INFO", "Detalhe parseado com sucesso (primeira chamada).")
    }

    # Description: use parsed or fallback to title
    descricao <- if (!is.na(detail$descricao) && nzchar(detail$descricao)) {
      detail$descricao
    } else {
      titulo
    }

    # Build record
    hash_input <- paste0(titulo, "|", detail_url)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    # Determine publication year from data-year or current year
    pub_year <- if (!is.na(year_val) && nzchar(year_val) && year_val != "0") {
      year_val
    } else {
      format(Sys.time(), "%Y")
    }

    records[[i]] <- tibble::tibble(
      id_registro = sprintf("embrapii_%s", substr(hash_dedup, 1, 16)),
      entidade = "EMBRAPII",
      pais_origem = "Brasil",
      titulo = titulo,
      subtitulo = detail$modalidade %||% NA_character_,
      descricao_resumida = substr(descricao, 1, 500),
      descricao_completa = descricao,
      tipo_oportunidade = "chamada_publica",
      modalidade = detail$modalidade %||% NA_character_,
      area_tematica = NA_character_,
      palavras_chave = NA_character_,
      elegibilidade = NA_character_,
      publico_alvo = detail$publico_alvo %||% NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "EMBRAPII",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = NA_character_,
      data_abertura = detail$data_abertura %||% NA_character_,
      data_limite = detail$data_limite %||% NA_character_,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = detail$data_limite, text = titulo)[[1]],
      link_origem = transparency_url,
      link_detalhe = detail_url,
      link_documento_pdf = if (length(detail$docs) > 0) detail$docs[[1]] else NA_character_,
      idioma = "pt",
      localidade = "Brasil",
      observacoes = paste(collapse_non_empty(detail$publico_alvo, detail$modalidade), collapse = " | "),
      texto_bruto = paste(collapse_non_empty(titulo, descricao, detail$publico_alvo, detail$modalidade), collapse = "\n"),
      pagina_coletada = 1L,
      fonte_oficial = "embrapii",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )

    if (i %% 10 == 0) {
      .log("INFO", sprintf("Progresso: %d/%d chamadas processadas.", i, n_chamadas))
      try(log_progress(sprintf("Progresso: %d/%d", i, n_chamadas), "PROGRESSO"), silent = TRUE)
    }
  }

  if (length(records) == 0) {
    .log("WARN", "Nenhum registro coletado.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = transparency_url))
  }

  df <- dplyr::bind_rows(records)

  if (detail_failures > 0) {
    .log("WARN", sprintf("Falhas no detalhe: %d/%d (usados dados do listing).", detail_failures, n_chamadas))
  }

  .log("INFO", sprintf("EMBRAPII: %d registros finais coletados.", nrow(df)))
  try(log_progress(sprintf("EMBRAPII: %d registros coletados", nrow(df)), "FIM"), silent = TRUE)

  list(records = df, pages_visited = 1L + as.integer(detail_failures > 0), last_url = transparency_url)
}


.parse_embrapii_detail <- function(html_text) {
  #' Parseia pagina de detalhe EMBRAPII (HTML estatico).
  #' Extrai: descricao, modalidade, publico_alvo, cronograma, documentos.

  result <- list(
    descricao = NA_character_,
    modalidade = NA_character_,
    publico_alvo = NA_character_,
    data_abertura = NA_character_,
    data_limite = NA_character_,
    docs = character(0)
  )

  html <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(html)) return(result)

  # Description: chamadas-publicas-content paragraphs
  content_node <- rvest::html_node(html, ".chamadas-publicas-content")
  if (!is.null(content_node) && !inherits(content_node, "xml_missing")) {
    paragraphs <- rvest::html_nodes(content_node, "p")
    if (length(paragraphs) > 0) {
      desc_parts <- vapply(paragraphs, function(p) trimws(rvest::html_text(p, trim = TRUE)), character(1))
      desc_parts <- desc_parts[nzchar(desc_parts) & desc_parts != "\u00a0"]
      if (length(desc_parts) > 0) {
        result$descricao <- paste(desc_parts, collapse = "\n\n")
      }
    }
  }

  # Fallback description from og:description
  if (is.na(result$descricao) || !nzchar(result$descricao)) {
    og_desc <- rvest::html_node(html, "meta[property='og:description']")
    if (!is.null(og_desc) && !inherits(og_desc, "xml_missing")) {
      result$descricao <- rvest::html_attr(og_desc, "content")
    }
  }

  # Schedule table: extract dates from cronograma
  schedule_table <- rvest::html_node(html, "table.table-striped")
  if (!is.null(schedule_table) && !inherits(schedule_table, "xml_missing")) {
    rows <- rvest::html_nodes(schedule_table, "tr")
    for (row in rows) {
      cells <- rvest::html_nodes(row, "td, th")
      if (length(cells) >= 2) {
        activity <- tolower(trimws(rvest::html_text(cells[[1]], trim = TRUE)))
        deadline_text <- trimws(rvest::html_text(cells[[2]], trim = TRUE))

        # Extract inscription period (data_abertura and data_limite)
        if (grepl("inscri", activity, ignore.case = TRUE) ||
            grepl("submiss", activity, ignore.case = TRUE) ||
            grepl("proposta", activity, ignore.case = TRUE)) {
          dates <- .extract_date_range(deadline_text)
          if (!is.na(dates$start)) result$data_abertura <- dates$start
          if (!is.na(dates$end)) result$data_limite <- dates$end
        }

        # Extract deadline (prazo limte, encerramento)
        if (grepl("prazo|encerramento|final|resultado", activity, ignore.case = TRUE) && is.na(result$data_limite)) {
          dates <- .extract_date_range(deadline_text)
          if (!is.na(dates$end)) result$data_limite <- dates$end
          if (!is.na(dates$start) && is.na(result$data_abertura)) result$data_abertura <- dates$start
        }
      }
    }
  }

  # Fallback: look for dates in full text if no schedule found
  if (is.na(result$data_limite)) {
    full_text <- rvest::html_text(html, trim = TRUE)
    # Look for "inscrições" or "submissão" followed by date range
    inscricao_match <- regmatches(full_text, regexpr("(?:inscri[çc][õo]es?|submiss[ãa]o|propostas?)\\s+(?:de\\s+)?(?:\\d{2}/\\d{2}/\\d{4}|\\d{2}\\s+de\\s+\\w+\\s+de\\s+\\d{4})\\s+(?:a[à]\\s+)?(?:\\d{2}/\\d{2}/\\d{4}|\\d{2}\\s+de\\s+\\w+\\s+de\\s+\\d{4})", full_text, ignore.case = TRUE, perl = TRUE))
    if (length(inscricao_match) > 0) {
      dates <- .extract_date_range(inscricao_match)
      if (!is.na(dates$start)) result$data_abertura <- dates$start
      if (!is.na(dates$end)) result$data_limite <- dates$end
    }
  }

  # Modalidade: look for "Chamada Pública", "Chamada Interna", "Edital"
  full_text <- rvest::html_text(html, trim = TRUE)
  mod_match <- regmatches(full_text, regexpr("Chamada\\s+(?:P[uú]blica|Interna)[^\\n]*", full_text, ignore.case = TRUE))
  if (length(mod_match) > 0) {
    result$modalidade <- trimws(mod_match)
  } else {
    # Fallback from page title
    title_node <- rvest::html_node(html, "h1")
    if (!is.null(title_node) && !inherits(title_node, "xml_missing")) {
      result$modalidade <- trimws(rvest::html_text(title_node, trim = TRUE))
    }
  }

  # Publico alvo: look for "Unidades", "Centros de Competência", "ICTs", "Empresas"
  if (grepl("unidade|centro de compet|credenciado", result$descricao, ignore.case = TRUE)) {
    result$publico_alvo <- "Unidades e Centros de Competência Embrapii"
  } else if (grepl("icts|instituto de pesquisa|universidade", result$descricao, ignore.case = TRUE)) {
    result$publico_alvo <- "ICTs (Instituições de Ciência e Tecnologia)"
  } else if (grepl("empresa|ind[uú]stria", result$descricao, ignore.case = TRUE)) {
    result$publico_alvo <- "Empresas"
  }

  # PDF documents
  pdf_links <- rvest::html_nodes(html, "a[href$='.pdf']")
  if (length(pdf_links) > 0) {
    result$docs <- rvest::html_attr(pdf_links, "href")
  }

  result
}


.extract_date_range <- function(text) {
  #' Extrai datas de um texto no formato "DD/MM a DD/MM/YYYY" ou "DD/MM/YYYY a DD/MM/YYYY"
  #' Retorna lista com start e end (character ISO ou NA)

  result <- list(start = NA_character_, end = NA_character_)

  if (is.na(text) || !nzchar(text)) return(result)

  # Format 1: DD/MM/YYYY a DD/MM/YYYY (full dates on both sides)
  m <- regmatches(text, regexpr("([0-9]{2}/[0-9]{2}/[0-9]{4})\\s*a\\s*([0-9]{2}/[0-9]{2}/[0-9]{4})", text, perl = TRUE))
  if (length(m) > 0) {
    parts <- strsplit(m, "\\s*a\\s*")[[1]]
    result$start <- .parse_br_date(parts[1])
    result$end <- .parse_br_date(parts[2])
    return(result)
  }

  # Format 2: DD/MM a DD/MM/YYYY (year only on second date)
  m <- regmatches(text, regexpr("([0-9]{2}/[0-9]{2})\\s*a\\s*([0-9]{2}/[0-9]{2}/[0-9]{4})", text, perl = TRUE))
  if (length(m) > 0) {
    parts <- strsplit(m, "\\s*a\\s*")[[1]]
    # First date: DD/MM, need to extract year from second date
    year2 <- sub(".*/([0-9]{4})", "\\1", parts[2])
    result$start <- .parse_br_date(paste0(parts[1], "/", year2))
    result$end <- .parse_br_date(parts[2])
    return(result)
  }

  # Format 3: Single DD/MM/YYYY
  m <- regmatches(text, regexpr("[0-9]{2}/[0-9]{2}/[0-9]{4}", text, perl = TRUE))
  if (length(m) > 0) {
    result$end <- .parse_br_date(m)
    return(result)
  }

  # Format 4: "DD de mês de YYYY"
  months_pt <- c("janeiro", "fevereiro", "março", "abril", "maio", "junho",
                 "julho", "agosto", "setembro", "outubro", "novembro", "dezembro")
  month_pattern <- paste(months_pt, collapse = "|")
  m <- regmatches(text, regexpr(paste0("[0-9]{1,2}\\s+de\\s+(", month_pattern, ")\\s+de\\s+[0-9]{4}"), text, ignore.case = TRUE, perl = TRUE))
  if (length(m) > 0) {
    result$end <- .parse_pt_date(m)
    return(result)
  }

  result
}


.parse_br_date <- function(d) {
  #' Converte DD/MM/YYYY para YYYY-MM-DD
  if (is.na(d) || !nzchar(d)) return(NA_character_)
  parts <- strsplit(d, "/")[[1]]
  if (length(parts) != 3) return(NA_character_)
  sprintf("%s-%s-%s", parts[3], parts[2], parts[1])
}


.parse_pt_date <- function(d) {
  #' Converte "DD de mês de YYYY" para YYYY-MM-DD
  if (is.na(d) || !nzchar(d)) return(NA_character_)
  months_map <- c(janeiro="01", fevereiro="02", março="03", abril="04",
                  maio="05", junho="06", julho="07", agosto="08",
                  setembro="09", outubro="10", novembro="11", dezembro="12")
  m <- regmatches(d, regexpr("([0-9]{1,2})\\s+de\\s+(\\w+)\\s+de\\s+([0-9]{4})", d, perl = TRUE))
  if (length(m) == 0) return(NA_character_)
  day <- sub("([0-9]{1,2})\\s+de\\s+.*", "\\1", m)
  month_name <- sub(".*de\\s+(\\w+)\\s+de.*", "\\1", tolower(m))
  year <- sub(".*de\\s+([0-9]{4})", "\\1", m)
  month_num <- months_map[[month_name]]
  if (is.null(month_num)) return(NA_character_)
  sprintf("%s-%s-%02d", year, as.integer(month_num), as.integer(day))
}


# --- DAAD Brasil Collector (Híbrido: JSON catálogo + HTML scraping) ---

.parse_daad_date <- function(d) {
  #' Converte DD.MM.YYYY para YYYY-MM-DD
  if (is.na(d) || !nzchar(trimws(d))) return(NA_character_)
  d <- trimws(d)
  parts <- strsplit(d, "\\.")[[1]]
  if (length(parts) == 3 && nchar(parts[1]) <= 2 && nchar(parts[2]) <= 2 && nchar(parts[3]) == 4) {
    return(sprintf("%s-%s-%02d", parts[3], parts[2], as.integer(parts[1])))
  }
  NA_character_
}

.parse_daad_json <- function(js_text) {
  #' Faz parse do arquivo scholarships.js (formato TAFFY JS) e retorna data.frame.
  #' Filtra apenas bolsas com Brazil (origin=48) no catálogo.
  #'
  #' O arquivo tem formato: var scholarships = TAFFY([{...}, {...}, ...]);
  #' Extraímos o array JSON e parseamos com jsonlite.

  if (is.null(js_text) || !nzchar(js_text)) {
    return(list(scholarships = tibble::tibble(), reference = list()))
  }

  # Extrair o array JSON do wrapper TAFFY
  json_match <- regmatches(js_text, regexpr("TAFFY\\(\\[.*\\]\\)", js_text, perl = TRUE))
  if (length(json_match) == 0) {
    return(list(scholarships = tibble::tibble(), reference = list()))
  }

  json_str <- sub("^TAFFY\\(", "", sub("\\)$", "", json_match))

  scholarships <- tryCatch(
    jsonlite::fromJSON(json_str, simplifyVector = FALSE),
    error = function(e) {
      message(sprintf("[DAAD JSON] Erro ao parsear scholarships: %s", e$message))
      list()
    }
  )

  if (length(scholarships) == 0) {
    return(list(scholarships = tibble::tibble(), reference = list()))
  }

  # Tabelas de referência (IDs para nomes)
  ref_urls <- list(
    status = "https://www2.daad.de/bundles/daadstipendiendatenbanklsh/data/a/js/status.js",
    intentions = "https://www2.daad.de/bundles/daadstipendiendatenbanklsh/data/a/js/intentions.js",
    subjectgroups = "https://www2.daad.de/bundles/daadstipendiendatenbanklsh/data/a/js/subjectgroups.js"
  )

  ref <- list()
  for (nm in names(ref_urls)) {
    ref_text <- tryCatch({
      req <- httr2::request(ref_urls[[nm]]) |>
        httr2::req_user_agent(get_random_ua()) |>
        httr2::req_timeout(10) |>
        httr2::req_retry(max_tries = 2)
      resp <- httr2::req_perform(req)
      httr2::resp_body_string(resp, encoding = "UTF-8")
    }, error = function(e) NULL)

    if (!is.null(ref_text)) {
      ref_match <- regmatches(ref_text, regexpr("TAFFY\\(\\[.*\\]\\)", ref_text, perl = TRUE))
      if (length(ref_match) > 0) {
        ref_json <- sub("^TAFFY\\(", "", sub("\\)$", "", ref_match))
        ref[[nm]] <- tryCatch(jsonlite::fromJSON(ref_json, simplifyVector = FALSE), error = function(e) list())
      }
    }
  }

  # Converter para data.frame
  Brazil_id <- 48L
  records <- vector("list", length(scholarships))
  n_brazil <- 0L

  for (i in seq_along(scholarships)) {
    s <- scholarships[[i]]

    # Filtrar: origin deve conter Brazil (48)
    origins <- as.integer(s$origin %||% integer(0))
    if (!(Brazil_id %in% origins)) next

    n_brazil <- n_brazil + 1L

    # Mapear status para nomes
    status_ids <- as.integer(s$status %||% integer(0))
    status_names <- vapply(status_ids, function(sid) {
      found <- Filter(function(x) x$id == sid, ref$status %||% list())
      if (length(found) > 0) found[[1]]$nameEn else as.character(sid)
    }, character(1))

    # Mapear intentions para nomes
    intent_ids <- as.integer(s$intentions %||% integer(0))
    intent_names <- vapply(intent_ids, function(iid) {
      found <- Filter(function(x) x$id == iid, ref$intentions %||% list())
      if (length(found) > 0) found[[1]]$nameEn else as.character(iid)
    }, character(1))

    # Mapear subjectGrps para nomes
    sg_codes <- s$subjectGrps %||% character(0)
    sg_names <- vapply(sg_codes, function(sc) {
      found <- Filter(function(x) x$code == sc, ref$subjectgroups %||% list())
      if (length(found) > 0) found[[1]]$nameEn else sc
    }, character(1))

    # Tipo de programa
    prog_type <- as.integer(s$programmtypId %||% 7L)
    type_label <- switch(as.character(prog_type),
      "3" = "mobility/short-term",
      "5" = "country-cooperation",
      "7" = "general",
      "unknown"
    )

    records[[n_brazil]] <- tibble::tibble(
      daad_id = as.integer(s$id %||% 0L),
      sap_objid = as.integer(s$sapObjid %||% 0L),
      sap_progid = as.integer(s$sapProgid %||% 0L),
      name_en = as.character(s$nameEn %||% ""),
      name_de = as.character(s$nameDe %||% ""),
      langname_en = as.character(s$langnameEn %||% ""),
      programmname_en = as.character(s$programmnameEn %||% ""),
      is_daad = as.integer(s$isDaad %||% 0L),
      is_move = as.integer(s$isMove %||% 0L),
      programmtyp_id = prog_type,
      programmtyp_label = type_label,
      status_ids = paste(status_ids, collapse = ","),
      status_names = paste(status_names, collapse = "; "),
      origin_ids = paste(origins, collapse = ","),
      origin_names = "Brazil",
      intent_ids = paste(intent_ids, collapse = ","),
      intent_names = paste(intent_names, collapse = "; "),
      subject_groups = paste(sg_names, collapse = "; "),
      introduction_en = as.character(s$introduction$en %||% ""),
      introduction_de = as.character(s$introduction$de %||% "")
    )
  }

  if (n_brazil == 0) {
    return(list(scholarships = tibble::tibble(), reference = ref))
  }

  records <- records[seq_len(n_brazil)]
  df <- dplyr::bind_rows(records)

  list(scholarships = df, reference = ref)
}

.parse_daad_listing <- function(html) {
  #' Parseia uma página de listing do DAAD Brasil.
  #' Retorna tibble com: titulo, url_detalhe, daad_id, descricao, status, areas, prazo.

  items <- rvest::html_nodes(html, "li.c-scholarship-list__item")
  if (length(items) == 0) {
    return(tibble::tibble(
      titulo = character(0), url_detalhe = character(0), daad_id = integer(0),
      descricao = character(0), status = character(0), areas = character(0),
      prazo = character(0)
    ))
  }

  n <- length(items)
  titulo <- character(n)
  url_detalhe <- character(n)
  daad_id <- integer(n)
  descricao <- character(n)
  status <- character(n)
  areas <- character(n)
  prazo <- character(n)

  for (i in seq_len(n)) {
    item <- items[[i]]

    # Título
    title_node <- rvest::html_node(item, "h3 > a")
    titulo[i] <- if (!is.null(title_node) && !inherits(title_node, "xml_missing")) {
      trimws(rvest::html_text(title_node, trim = TRUE))
    } else {
      ""
    }

    # URL detalhe + extrair detail_to_show (DAAD ID)
    link_node <- rvest::html_node(item, "a.o-more-link")
    href <- if (!is.null(link_node) && !inherits(link_node, "xml_missing")) {
      rvest::html_attr(link_node, "href")
    } else {
      ""
    }
    url_detalhe[i] <- resolve_url("https://www.daad-brasil.org/pt/bolsas/busca/", href)

    # Extrair detail_to_show da URL do título (que tem o ID)
    title_link <- rvest::html_node(item, "h3 > a")
    title_href <- if (!is.null(title_link) && !inherits(title_link, "xml_missing")) {
      rvest::html_attr(title_link, "href")
    } else {
      ""
    }
    id_match <- regmatches(title_href, regexpr("detail_to_show=([0-9]+)", title_href))
    daad_id[i] <- if (length(id_match) > 0) {
      as.integer(sub("detail_to_show=", "", id_match))
    } else {
      0L
    }

    # Descrição
    desc_node <- rvest::html_node(item, "p.u-size-teaser")
    descricao[i] <- if (!is.null(desc_node) && !inherits(desc_node, "xml_missing")) {
      trimws(rvest::html_text(desc_node, trim = TRUE))
    } else {
      ""
    }

    # Status (applicant types) - do dl.c-scholarship-list__info
    info_node <- rvest::html_node(item, "dl.c-scholarship-list__info")
    if (!is.null(info_node) && !inherits(info_node, "xml_missing")) {
      dts <- rvest::html_nodes(info_node, "dt")
      dds <- rvest::html_nodes(info_node, "dd")
      for (j in seq_along(dts)) {
        dt_text <- trimws(rvest::html_text(dts[[j]], trim = TRUE))
        if (grepl("Status", dt_text, ignore.case = TRUE) && j <= length(dds)) {
          li_nodes <- rvest::html_nodes(dds[[j]], "li")
          status[i] <- paste(vapply(li_nodes, function(li) trimws(rvest::html_text(li, trim = TRUE)), character(1)), collapse = "; ")
        }
        if (grepl("Prazo|deadline", dt_text, ignore.case = TRUE) && j <= length(dds)) {
          prazo[i] <- trimws(rvest::html_text(dds[[j]], trim = TRUE))
        }
      }
    }

    # Áreas temáticas (data-scholarships-tooltip)
    tooltip_node <- rvest::html_node(item, "button[data-scholarships-tooltip]")
    if (!is.null(tooltip_node) && !inherits(tooltip_node, "xml_missing")) {
      tooltip_html <- rvest::html_attr(tooltip_node, "data-scholarships-tooltip")
      if (!is.na(tooltip_html) && nzchar(tooltip_html)) {
        tooltip_doc <- tryCatch(rvest::read_html(paste0("<div>", tooltip_html, "</div>")), error = function(e) NULL)
        if (!is.null(tooltip_doc)) {
          li_nodes <- rvest::html_nodes(tooltip_doc, "li")
          areas[i] <- paste(vapply(li_nodes, function(li) trimws(rvest::html_text(li, trim = TRUE)), character(1)), collapse = "; ")
        }
      }
    }
  }

  tibble::tibble(
    titulo = titulo,
    url_detalhe = url_detalhe,
    daad_id = daad_id,
    descricao = descricao,
    status = status,
    areas = areas,
    prazo = prazo
  )
}

.parse_daad_detail <- function(html) {
  #' Parseia a página de detalhe de uma bolsa DAAD Brasil.
  #' Extrai: objetivo, elegibilidade, valor, duração, processo de inscrição.

  result <- list(
    objetivo = NA_character_,
    elegibilidade = NA_character_,
    valor = NA_character_,
    valor_mensal = NA_real_,
    duracao = NA_character_,
    processo_inscricao = NA_character_,
    contato = NA_character_
  )

  # O conteúdo do detalhe está em seções dentro de um container
  # Cada seção tem um heading (h2/h3/h4) seguido de parágrafos
  content_text <- rvest::html_text(html, trim = TRUE)

  # Objetivo / Objective
  obj_match <- regmatches(content_text, regexpr("(?:Objective|Objetivo)\\s+(.+?)(?=Who can apply|Quem pode|What can funded|O que|Duration|Duração|Value|Valor|Selection|Seleção|Application|Inscrição|$)", content_text, ignore.case = TRUE, perl = TRUE))
  if (length(obj_match) > 0) {
    result$objetivo <- trimws(sub("^(Objective|Objetivo)\\s+", "", obj_match))
  }

  # Elegibilidade / Who can apply
  elig_match <- regmatches(content_text, regexpr("(?:Who can apply\\?|Quem pode se candidatar\\?)\\s+(.+?)(?=What can funded|O que|Duration|Duração|Value|Valor|Selection|Seleção|Application|Inscrição|$)", content_text, ignore.case = TRUE, perl = TRUE))
  if (length(elig_match) > 0) {
    result$elegibilidade <- trimws(sub("^(Who can apply\\?|Quem pode se candidatar\\?)\\s+", "", elig_match))
  }

  # Valor / Value
  val_match <- regmatches(content_text, regexpr("(?:Value|Valor)\\s+(.+?)(?=Selection|Seleção|Application|Inscrição|$)", content_text, ignore.case = TRUE, perl = TRUE))
  if (length(val_match) > 0) {
    result$valor <- trimws(sub("^(Value|Valor)\\s+", "", val_match))
    # Extrair valor mensal em euros
    euro_match <- regmatches(result$valor, regexpr("([0-9.,]+)\\s*euros?|EUR\\s*([0-9.,]+)", result$valor, ignore.case = TRUE))
    if (length(euro_match) > 0) {
      num_str <- regmatches(euro_match, regexpr("[0-9.,]+", euro_match))
      num_str <- gsub(",", "", num_str)
      result$valor_mensal <- suppressWarnings(as.numeric(num_str))
    }
  }

  # Duração / Duration
  dur_match <- regmatches(content_text, regexpr("(?:Duration of the funding|Duração do financiamento)\\s+(.+?)(?=Value|Valor|Selection|Seleção|Application|Inscrição|$)", content_text, ignore.case = TRUE, perl = TRUE))
  if (length(dur_match) > 0) {
    result$duracao <- trimws(sub("^(Duration of the funding|Duração do financiamento)\\s+", "", dur_match))
  }

  # Processo de inscrição / Application
  app_match <- regmatches(content_text, regexpr("(?:Application|Como se candidatar|Processo de inscri[çc][ãa]o)\\s+(.+?)(?=Contact|Contato|$)", content_text, ignore.case = TRUE, perl = TRUE))
  if (length(app_match) > 0) {
    result$processo_inscricao <- trimws(sub("^(Application|Como se candidatar|Processo de inscri[çc][ãa]o)\\s+", "", app_match))
  }

  # Contato
  contact_match <- regmatches(content_text, regexpr("(?:Contact|Contato)\\s+(.+?)(?=$)", content_text, ignore.case = TRUE, perl = TRUE))
  if (length(contact_match) > 0) {
    result$contato <- trimws(sub("^(Contact|Contato)\\s+", "", contact_match))
  }

  result
}

collect_daad <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coletor híbrido DAAD Brasil: JSON catálogo global + HTML scraping detalhe.
  #'
  #' Fluxo:
  #' 1. Baixa scholarships.js do DAAD Alemanha (JSON público, ~700KB)
  #' 2. Filtra bolsas com origin=48 (Brasil)
  #' 3. Faz scraping do listing do DAAD Brasil (17 páginas)
  #' 4. Para cada bolsa, busca página de detalhe
  #' 5. Merge JSON + scraping → registros finais

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[DAAD][%s] %s", level, msg))
  }

  .log("INFO", "Iniciando coleta DAAD Brasil (híbrido JSON + scraping).")
  try(log_progress("Iniciando coleta DAAD Brasil", "INICIO"), silent = TRUE)

  user_agent <- get_random_ua()
  base_url <- "https://www.daad-brasil.org/pt/bolsas/busca/"

  # =========================================================================
  # FASE 1: Baixar catálogo global do DAAD Alemanha (JSON)
  # =========================================================================
  .log("INFO", "Fase 1: Baixando catálogo global DAAD (scholarships.js).")
  try(log_progress("Baixando catálogo global DAAD", "FASE1"), silent = TRUE)

  json_url <- "https://www2.daad.de/bundles/daadstipendiendatenbanklsh/data/a/js/scholarships.js"
  json_req <- httr2::request(json_url) |>
    httr2::req_user_agent(user_agent) |>
    httr2::req_timeout(30) |>
    httr2::req_retry(max_tries = 3)

  json_resp <- tryCatch(httr2::req_perform(json_req), error = function(e) NULL)
  if (is.null(json_resp) || httr2::resp_status(json_resp) != 200) {
    .log("ERROR", "Falha ao baixar scholarships.js do DAAD Alemanha.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = json_url))
  }

  js_text <- httr2::resp_body_string(json_resp, encoding = "UTF-8")
  .log("INFO", sprintf("scholarships.js baixado: %d caracteres.", nchar(js_text)))

  json_result <- .parse_daad_json(js_text)
  catalog_df <- json_result$scholarships

  if (nrow(catalog_df) == 0) {
    .log("WARN", "Nenhuma bolsa Brasil encontrada no catálogo global.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = json_url))
  }

  .log("INFO", sprintf("Catálogo global: %d bolsas Brasil extraídas de 162 totais.", nrow(catalog_df)))

  # =========================================================================
  # FASE 2: Scraping do listing do DAAD Brasil (17 páginas)
  # =========================================================================
  .log("INFO", "Fase 2: Fazendo scraping do listing DAAD Brasil.")
  try(log_progress("Scraping listing DAAD Brasil", "FASE2"), silent = TRUE)

  listing_all <- tibble::tibble(
    titulo = character(0), url_detalhe = character(0), daad_id = integer(0),
    descricao = character(0), status = character(0), areas = character(0),
    prazo = character(0)
  )

  pages_visited <- 0L
  max_listing_pages <- min(max_pages, 20L)

  for (pg in seq_len(max_listing_pages)) {
    page_url <- paste0(base_url, "?type=a&q=&status=0&subject=0&onlydaad=0&detail_to_show=0&target=48&origin=48&pg=1&tab=&intention=&pg=", pg)

    page_req <- httr2::request(page_url) |>
      httr2::req_user_agent(user_agent) |>
      httr2::req_timeout(20) |>
      httr2::req_retry(max_tries = 2)

    page_resp <- tryCatch(httr2::req_perform(page_req), error = function(e) NULL)
    if (is.null(page_resp) || httr2::resp_status(page_resp) != 200) {
      .log("WARN", sprintf("Falha ao acessar página %d do listing.", pg))
      break
    }

    page_html_text <- httr2::resp_body_string(page_resp, encoding = "UTF-8")
    page_html <- rvest::read_html(page_html_text)
    pages_visited <- pages_visited + 1L

    # Verificar se há itens nesta página
    items <- rvest::html_nodes(page_html, "li.c-scholarship-list__item")
    if (length(items) == 0) {
      .log("INFO", sprintf("Página %d: nenhum item encontrado. Fim da paginação.", pg))
      break
    }

    listing_page <- .parse_daad_listing(page_html)
    listing_all <- dplyr::bind_rows(listing_all, listing_page)

    .log("INFO", sprintf("Página %d: %d itens extraídos (total: %d).", pg, nrow(listing_page), nrow(listing_all)))
    try(log_progress(sprintf("Página %d: %d itens (total: %d)", pg, nrow(listing_page), nrow(listing_all)), "FASE2"), silent = TRUE)

    if (pg < max_listing_pages) Sys.sleep(0.5)
  }

  .log("INFO", sprintf("Listing completo: %d itens de %d páginas.", nrow(listing_all), pages_visited))

  # =========================================================================
  # FASE 3: Merge JSON catálogo + listing Brasil
  # =========================================================================
  .log("INFO", "Fase 3: Mergeando catálogo JSON com listing Brasil.")
  try(log_progress("Mergeando JSON + listing", "FASE3"), silent = TRUE)

  # Criar mapa: daad_id do JSON ↔ daad_id do listing
  merged_records <- vector("list", nrow(catalog_df))
  n_skipped <- 0L

  for (i in seq_len(nrow(catalog_df))) {
    cat_row <- catalog_df[i, ]

    # Match por daad_id (detail_to_show do listing = sap_objid ou sap_progid do JSON)
    match_idx <- which(
      listing_all$daad_id == cat_row$sap_objid |
      listing_all$daad_id == cat_row$sap_progid |
      listing_all$daad_id == cat_row$daad_id
    )

    # Fallback: match por título (case-insensitive, parcial)
    if (length(match_idx) == 0) {
      title_pattern <- tolower(substr(cat_row$name_en, 1, 30))
      match_idx <- which(grepl(title_pattern, tolower(listing_all$titulo), fixed = TRUE))
    }

    # Pular bolsas sem correspondência no listing do Brasil
    # (existem apenas no catálogo global da Alemanha, sem detalhe válido)
    if (length(match_idx) == 0) {
      n_skipped <- n_skipped + 1L
      next
    }

    # Dados do listing (sempre encontrado após filtro acima)
    listing_row <- listing_all[match_idx[[1]], ]

    titulo_final <- if (nzchar(listing_row$titulo)) {
      listing_row$titulo
    } else {
      cat_row$name_en
    }

    descricao_final <- if (nzchar(listing_row$descricao)) {
      listing_row$descricao
    } else {
      cat_row$introduction_en
    }

    # Prazo: converter DD.MM.YYYY → YYYY-MM-DD
    prazo_raw <- if (nzchar(listing_row$prazo)) listing_row$prazo else NA_character_
    # O prazo pode conter múltiplas datas separadas por <br> ou newline
    prazo_clean <- gsub("<[^>]+>", " ", prazo_raw)
    prazo_clean <- gsub("\\s+", " ", prazo_clean)
    # Extrair primeira data no formato DD.MM.YYYY
    date_matches <- regmatches(prazo_clean, regexpr("[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}", prazo_clean))
    data_limite <- if (length(date_matches) > 0) .parse_daad_date(date_matches[[1]]) else NA_character_

    hash_input <- paste0(titulo_final, "|", cat_row$daad_id)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    # Link detalhe (sempre do listing Brasil)
    link_detalhe <- listing_row$url_detalhe

    # Inferir nível acadêmico do status
    nivel_academico <- NA_character_
    if (grepl("Doctoral|PhD|Doutorando", cat_row$status_names, ignore.case = TRUE)) {
      nivel_academico <- "doutorado"
    } else if (grepl("Graduate|Graduado|Masters", cat_row$status_names, ignore.case = TRUE)) {
      nivel_academico <- "mestrado"
    } else if (grepl("Postdoc|Pós-doutorado", cat_row$status_names, ignore.case = TRUE)) {
      nivel_academico <- "pós-doutorado"
    } else if (grepl("Undergrad|Estudante", cat_row$status_names, ignore.case = TRUE)) {
      nivel_academico <- "graduação"
    } else if (grepl("Faculty|Professor", cat_row$status_names, ignore.case = TRUE)) {
      nivel_academico <- "professor"
    }

    # Inferir tipo de oportunidade
    tipo_oportunidade <- "bolsa_estudo"
    if (grepl("research|pesquisa", cat_row$intent_names, ignore.case = TRUE)) {
      tipo_oportunidade <- "bolsa_pesquisa"
    } else if (grepl("study|estudo", cat_row$intent_names, ignore.case = TRUE)) {
      tipo_oportunidade <- "bolsa_estudo"
    } else if (grepl("internship|estágio", cat_row$intent_names, ignore.case = TRUE)) {
      tipo_oportunidade = "estágio"
    }

    # Instituição financiadora
    instituicao <- if (cat_row$is_daad == 1L) "DAAD" else cat_row$programmname_en

    merged_records[[i]] <- tibble::tibble(
      id_registro = sprintf("daad_%s", substr(hash_dedup, 1, 16)),
      entidade = "DAAD",
      pais_origem = "Alemanha",
      titulo = titulo_final,
      subtitulo = cat_row$langname_en,
      descricao_resumida = substr(descricao_final, 1, 500),
      descricao_completa = cat_row$introduction_en,
      tipo_oportunidade = tipo_oportunidade,
      modalidade = cat_row$programmtyp_label,
      area_tematica = cat_row$subject_groups,
      palavras_chave = NA_character_,
      elegibilidade = NA_character_,
      publico_alvo = cat_row$status_names,
      nivel_academico = nivel_academico,
      instituicao_financiadora = instituicao,
      valor_financiado = NA_real_,
      moeda = "EUR",
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = data_limite,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = data_limite, text = titulo_final)[[1]],
      link_origem = base_url,
      link_detalhe = link_detalhe,
      link_documento_pdf = NA_character_,
      idioma = "en",
      localidade = "Alemanha",
      observacoes = paste(collapse_non_empty(
        cat_row$status_names,
        cat_row$intent_names,
        cat_row$programmtyp_label,
        if (cat_row$is_daad == 1L) "Programa DAAD" else "Programa externo",
        if (cat_row$is_move == 1L) "Mobilidade" else NULL
      ), collapse = " | "),
      texto_bruto = paste(collapse_non_empty(titulo_final, descricao_final, cat_row$status_names, cat_row$subject_groups, cat_row$introduction_en), collapse = "\n"),
      pagina_coletada = pages_visited,
      fonte_oficial = "daad",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )
  }

  # Remover registros NULL (bolsas sem match no Brasil)
  merged_records <- merged_records[!vapply(merged_records, is.null, logical(1))]

  if (n_skipped > 0) {
    .log("INFO", sprintf("Fase 3: %d bolsas descartadas (sem correspondência no listing Brasil).", n_skipped))
    try(log_progress(sprintf("%d bolsas descartadas (sem match Brasil)", n_skipped), "FASE3"), silent = TRUE)
  }
  .log("INFO", sprintf("Fase 3: %d registros mergeados (JSON + listing Brasil).", length(merged_records)))

  # =========================================================================
  # FASE 4: Scraping de detalhes (apenas para bolsas com listing encontrado)
  # =========================================================================
  .log("INFO", "Fase 4: Buscando páginas de detalhe.")
  try(log_progress("Buscando detalhes das bolsas", "FASE4"), silent = TRUE)

  detail_failures <- 0L
  n_details <- min(max_records, length(merged_records))

  for (i in seq_len(n_details)) {
    rec <- merged_records[[i]]
    detail_url <- rec$link_detalhe

    # Só buscar detalhe se tiver link do Brasil
    if (!grepl("daad-brasil\\.org", detail_url, ignore.case = TRUE)) next

    if (i > 1) Sys.sleep(0.4)

    detail_req <- httr2::request(detail_url) |>
      httr2::req_user_agent(user_agent) |>
      httr2::req_timeout(15) |>
      httr2::req_retry(max_tries = 2)

    detail_resp <- tryCatch(httr2::req_perform(detail_req), error = function(e) NULL)

    if (!is.null(detail_resp) && httr2::resp_status(detail_resp) == 200) {
      detail_html_text <- tryCatch(httr2::resp_body_string(detail_resp, encoding = "UTF-8"), error = function(e) NULL)
      if (!is.null(detail_html_text) && nzchar(detail_html_text)) {
        detail_html <- rvest::read_html(detail_html_text)
        detail <- .parse_daad_detail(detail_html)

        # Validar: se todos os campos principais são NA, a página era vazia/genérica
        if (all(is.na(c(detail$objetivo, detail$elegibilidade, detail$valor, detail$duracao)))) {
          detail_failures <- detail_failures + 1L
          next
        }

        # Enriquecer registro com dados do detalhe
        if (!is.na(detail$valor_mensal) && !is.null(detail$valor_mensal)) {
          merged_records[[i]]$valor_financiado <- detail$valor_mensal
        }
        if (!is.na(detail$elegibilidade) && nzchar(detail$elegibilidade)) {
          merged_records[[i]]$elegibilidade <- substr(detail$elegibilidade, 1, 2000)
        }
        if (!is.na(detail$objetivo) && nzchar(detail$objetivo)) {
          merged_records[[i]]$descricao_completa <- paste(
            collapse_non_empty(merged_records[[i]]$descricao_completa, detail$objetivo),
            collapse = "\n\n"
          )
        }
        # Atualizar texto_bruto com dados do detalhe
        merged_records[[i]]$texto_bruto <- paste(collapse_non_empty(
          merged_records[[i]]$titulo,
          merged_records[[i]]$descricao_resumida,
          detail$objetivo,
          detail$elegibilidade,
          detail$valor,
          detail$processo_inscricao
        ), collapse = "\n")
      }
    } else {
      detail_failures <- detail_failures + 1L
    }

    if (i %% 10 == 0) {
      .log("INFO", sprintf("Progresso detalhes: %d/%d.", i, n_details))
      try(log_progress(sprintf("Detalhes: %d/%d", i, n_details), "FASE4"), silent = TRUE)
    }
  }

  if (detail_failures > 0) {
    .log("WARN", sprintf("Falhas no detalhe: %d/%d (usados dados do listing/catálogo).", detail_failures, n_details))
  }

  # =========================================================================
  # FASE 5: Finalização
  # =========================================================================
  .log("INFO", "Fase 5: Preparando registros.")
  try(log_progress("Preparando registros", "FASE5"), silent = TRUE)

  df <- dplyr::bind_rows(merged_records)
  df <- ensure_record_schema(df)

  .log("INFO", sprintf("DAAD Brasil: %d registros finais coletados.", nrow(df)))
  try(log_progress(sprintf("DAAD Brasil: %d registros finais", nrow(df)), "FIM"), silent = TRUE)

  list(records = df, pages_visited = pages_visited + 1L, last_url = base_url)
}


# Auto-registrar collectors (após definição de todas as funções)
register_collector("capes", collect_capes, "CAPES Plone API + HTML fallback")
register_collector("finep", collect_finep, "FINEP custom pagination")
register_collector("horizon_europe", collect_horizon_europe, "EU F&T Portal REST API (Horizon Europe)")
register_collector("erc", collect_erc, "EU F&T Portal REST API (Horizon Europe/ERC)")
register_collector("fapesb", collect_fapesb, "WordPress REST API (FAPESB)")
register_collector("sigitec", collect_sigitec, "Petrobras SIGITEC API REST + Playwright fallback")
register_collector("undp", collect_undp, "UNDP Procurement Notices - componente externo JSON")
register_collector("embrapii", collect_embrapii, "EMBRAPII Chamadas Publicas - HTML estatico + detalhe")
register_collector("daad", collect_daad, "DAAD Brasil - Híbrido: JSON catálogo global + HTML scraping detalhe")

# --- EU Quantum Technologies Collector ---
collect_quantum <- function(source_row, max_pages, max_records, use_ai, log_path) {
  #' Coleta oportunidades de tecnologias quânticas via API REST pública (EU F&T Portal Search API)
  #' Estratégia: múltiplos termos de busca (callIdentifiers + keywords)
  #' Pós-filtros: DATASOURCE=SEDIA + frameworkProgramme=43108390 + status Open
  #' NOTA: A API ignora filtros JSON no body — usa pós-processamento

  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[QUANTUM][%s] %s", level, msg))
  }

  api_url <- paste0(get_eu_api_base_url(), "/search")
  all_items <- list()

  # Pre-flight: verificar conectividade com a API EU
  if (!is_host_alive(api_url)) {
    .log("WARN", "API EU inacessivel. Pulando coleta QUANTUM.")
    try(log_progress("AVISO: API EU inacessivel - pulando QUANTUM", "Scraping"), silent = TRUE)
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = api_url))
  }

  # Query filter (a API ignora, mas mantém por consistência com HEU/ERC)
  heu_query <- '{"bool":{"must":[{"terms":{"frameworkProgramme":["43108390"]}}]}}'

  # Múltiplos termos de busca: callIdentifiers específicos quantum + keywords genéricas
  # callIdentifiers retornam resultados HEU diretamente; keywords capturam quantum em qualquer HEU
  search_terms <- c(
    "HORIZON-JU-EUROHPC-2026",     # Programme euroHPC (quantum computing, QEC, QML)
    "HORIZON-JU-SNS-2022",         # Smart Networks and Services (quantum communication)
    "HORIZON-CL4-2026-HUMAN",      # Cluster 4 Digital/Industrial (quantum technologies)
    "quantum",                     # Fallback: busca genérica
    "quantum computing",
    "quantum communication",
    "quantum sensors",
    "quantum technology"
  )

  .log("INFO", "Iniciando coleta EU Quantum Technologies via API REST...")

  for (term in search_terms) {
    .log("INFO", sprintf("Buscando termo: '%s'", term))

    search_text <- utils::URLencode(term, reserved = TRUE)
    url <- sprintf(
      "%s?apiKey=SEDIA&text=%s&pageNumber=1&pageSize=100&sortBy=es_SortDate&orderBy=DESC",
      api_url, search_text
    )

    data <- tryCatch(eu_api_request(url, heu_query, 60, log_path), error = function(e) {
      .log("ERROR", sprintf("Erro ao executar request para '%s': %s", term, e$message))
      NULL
    })

    if (is.null(data) || is.null(data$results)) {
      .log("WARN", sprintf("Resposta vazia ou invalida para '%s'", term))
      next
    }

    .log("INFO", sprintf("Termo '%s': %d resultados brutos", term, length(data$results)))

    # Pós-filtrar: DATASOURCE=SEDIA + frameworkProgramme=HEU + status Open
    for (item in data$results) {
      md <- item$metadata
      if (is.null(md)) next
      if (is.data.frame(md)) md <- as.list(md)

      # FILTRO 1: DATASOURCE == "SEDIA" (topics, não FAQs/profiles/projects)
      ds <- tryCatch({
        d <- md$DATASOURCE
        if (!is.null(d)) { if (is.list(d)) d[[1]] else d[1] } else { NA }
      }, error = function(e) NA)
      if (is.na(ds) || ds != "SEDIA") next

      # FILTRO 2: frameworkProgramme == "43108390" (Horizon Europe)
      fp <- tryCatch({
        f <- md$frameworkProgramme
        if (!is.null(f)) { if (is.list(f)) f[[1]] else f[1] } else { NA }
      }, error = function(e) NA)
      if (is.na(fp) || !grepl("43108390", fp)) next

      # FILTRO 3: status != CLOSED (31094503)
      st <- tryCatch({
        s <- md$status
        if (!is.null(s)) { if (is.list(s)) s[[1]] else s[1] } else { NA }
      }, error = function(e) NA)
      if (!is.na(st) && length(st) > 0 && grepl("31094503", st)) next

      all_items <- c(all_items, list(item))
    }

    .log("INFO", sprintf("Termo '%s': %d itens HEU quantum acumulados", term, length(all_items)))

    if (length(all_items) >= max_records * 3) break
    Sys.sleep(0.5)
  }

  # Deduplicar por callIdentifier — preferir versão em inglês
  # Itens sem callIdentifier usam fallback key (título truncado)
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
      } else { NA_character_ }
    }, error = function(e) NA_character_)

    # Fallback key para itens sem callIdentifier
    if (is.na(call_id) || length(call_id) == 0) {
      titulo_fallback <- tryCatch({
        t <- md$title
        if (!is.null(t)) { if (is.list(t)) t[[1]] else t[1] } else { "" }
      }, error = function(e) "")
      call_id <- paste0("ref_", substr(titulo_fallback, 1, 60))
    }

    titulo <- tryCatch({
      if (!is.null(md$title)) {
        v <- md$title
        if (is.list(v)) v[[1]] else v[1]
      } else { "" }
    }, error = function(e) "")
    if (length(titulo) == 0) titulo <- ""
    is_english <- tryCatch(
      !is.na(titulo) && is.character(titulo) && !grepl("[^\x01-\x7F]", titulo),
      error = function(e) FALSE
    )

    if (is.null(dedup_map[[call_id]])) {
      dedup_map[[call_id]] <- list(item = item, is_english = is_english)
    } else if (is_english && !dedup_map[[call_id]]$is_english) {
      dedup_map[[call_id]] <- list(item = item, is_english = TRUE)
    }
  }
  all_items <- lapply(dedup_map, function(x) x$item)
  .log("INFO", sprintf("Apos deduplicacao: %d itens unicos", length(all_items)))

  if (length(all_items) > max_records) {
    all_items <- all_items[1:max_records]
    .log("WARN", sprintf("Limitado a %d registros", max_records))
  }

  if (length(all_items) == 0) {
    .log("WARN", "Nenhum item quantum encontrado")
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
      if (is.data.frame(md)) md <- as.list(md)

      titulo <- safe_extract(md$title)
      call_id <- safe_extract(md$callIdentifier)
      descricao_html <- safe_extract(md$descriptionByte)

      descricao_text <- gsub("<[^>]+>", " ", descricao_html)
      descricao_text <- gsub("&amp;", "&", descricao_text)
      descricao_text <- gsub("&nbsp;", " ", descricao_text)
      descricao_text <- gsub("\\s+", " ", trimws(descricao_text))

      data_abertura <- safe_extract(md$startDate)
      if (!is.na(data_abertura)) data_abertura <- as.character(as.Date(sub("T.*", "", data_abertura)))

      data_limite <- safe_extract(md$deadlineDate)
      if (!is.na(data_limite)) data_limite <- as.character(as.Date(sub("T.*", "", data_limite)))

      status_code <- safe_extract(md$status)
      status <- if (!is.na(status_code)) {
        if (grepl("31094501|31094502", status_code)) "aberto"
        else if (grepl("31094503", status_code)) "encerrado"
        else "desconhecido"
      } else { "desconhecido" }

      programa <- safe_extract(md$esST_programAbbreviation)
      tipo_acao <- safe_extract(md$typesOfAction)

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

      link_detalhe <- safe_extract(md$esST_URL, default = item$url)

      hash_input <- paste0(call_id, "|", titulo)
      hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

      resumo_final <- if (!is.na(descricao_text) && nzchar(descricao_text) && nchar(descricao_text) > 10) {
        substr(descricao_text, 1, 500)
      } else { titulo }

      tibble::tibble(
        id_registro = sprintf("quantum_%s", substr(hash_dedup, 1, 16)),
        entidade = "EU Quantum Technologies",
        pais_origem = "Uniao Europeia",
        titulo = titulo,
        subtitulo = call_id,
        descricao_resumida = resumo_final,
        descricao_completa = descricao_text,
        tipo_oportunidade = tipo_acao,
        modalidade = NA_character_,
        area_tematica = "Quantum Technologies",
        palavras_chave = paste("quantum", call_id),
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
        observacoes = "Capturado via busca por keyword quantum no EU F&T Portal (HEU)",
        texto_bruto = paste(titulo, descricao_text, sep = "\n\n"),
        pagina_coletada = 1L,
        fonte_oficial = "quantum",
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
    .log("WARN", "Nenhum registro valido extraido")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = api_url))
  }

  records <- dplyr::bind_rows(record_list)

  .log("INFO", sprintf("QUANTUM: %d registros finais coletados", nrow(records)))

  result <- list(records = records, pages_visited = length(search_terms), last_url = api_url)
  .log("INFO", sprintf("Retornando lista com %d registros", length(result$records)))
  return(result)
}

register_collector("quantum", collect_quantum, "EU F&T Portal REST API - Multi-keyword quantum + filtros HEU")

# --- Humboldt Foundation Collector (HTML scraping) ---

normalize_humboldt_country <- function(from_where) {
  txt <- tolower(trimws(from_where %||% ""))
  if (!nzchar(txt)) return("Internacional")
  if (grepl("brazil", txt)) return("Brasil")
  if (grepl("germany", txt)) return("Alemanha")
  if (grepl("non-european.*developing|developing.*transition", txt)) return("Internacional (países em desenvolvimento)")
  if (grepl("all countries|all nations", txt)) return("Internacional")
  if (grepl("developing countries", txt)) return("Internacional (países em desenvolvimento)")
  from_where
}

infer_humboldt_status <- function(detail_text) {
  txt <- tolower(detail_text %||% "")
  if (grepl("closing date.*elapsed|not currently possible to apply|unfortunately.*not.*apply", txt)) return("encerrado")
  if (grepl("next application round|next round.*opens|application round.*scheduled", txt)) return("futuro")
  "aberto"
}

extract_humboldt_listing <- function(html, base_url, program_type) {
  cards <- try(rvest::html_elements(html, "article.teaser"), silent = TRUE)
  if (inherits(cards, "try-error") || length(cards) == 0) {
    return(tibble::tibble())
  }

  records <- purrr::map_dfr(seq_along(cards), function(i) {
    card <- cards[[i]]

    title_node <- rvest::html_node(card, ".teaser__headline, h3")
    title <- if (!is.null(title_node) && !inherits(title_node, "xml_missing")) {
      trimws(rvest::html_text(title_node, trim = TRUE))
    } else { "" }

    if (!nzchar(title)) return(tibble::tibble())

    text_node <- rvest::html_node(card, ".teaser__text")
    text_html <- if (!is.null(text_node) && !inherits(text_node, "xml_missing")) {
      rvest::html_text(text_node, trim = TRUE)
    } else { "" }

    for_whom <- ""
    from_where <- ""
    for_what <- ""
    if (grepl("For whom:", text_html, fixed = TRUE)) {
      for_whom <- sub(".*For whom:\\s*", "", text_html)
      for_whom <- sub("\\s*From where:.*", "", for_whom)
      for_whom <- trimws(for_whom)
    }
    if (grepl("From where:", text_html, fixed = TRUE)) {
      from_where <- sub(".*From where:\\s*", "", text_html)
      from_where <- sub("\\s*For what:.*", "", from_where)
      from_where <- trimws(from_where)
    }
    if (grepl("For what:", text_html, fixed = TRUE)) {
      for_what <- sub(".*For what:\\s*", "", text_html)
      for_what <- trimws(for_what)
    }

    link_node <- rvest::html_node(card, "a[href]")
    detail_href <- if (!is.null(link_node) && !inherits(link_node, "xml_missing")) {
      rvest::html_attr(link_node, "href")
    } else { "" }
    detail_url <- if (nzchar(detail_href)) {
      resolve_url(base_url, detail_href)
    } else { NA_character_ }

    tibble::tibble(
      listing_title = title,
      for_whom = for_whom,
      from_where_raw = from_where,
      for_what = for_what,
      detail_url = detail_url,
      program_type = program_type
    )
  })

  records
}

extract_humboldt_detail <- function(detail_url, log_path = NULL) {
  if (is.na(detail_url) || !nzchar(detail_url)) {
    return(list(title = NA_character_, description = NA_character_, status_text = ""))
  }

  pg <- tryCatch({
    hdrs <- build_scrape_headers()
    req <- httr2::request(detail_url) |>
      httr2::req_user_agent(hdrs$`User-Agent`) |>
      httr2::req_timeout(15) |>
      httr2::req_retry(max_tries = 2)
    resp <- httr2::req_perform(req)
    txt <- httr2::resp_body_string(resp, encoding = "UTF-8")
    list(ok = TRUE, html = rvest::read_html(txt), text = txt)
  }, error = function(e) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Humboldt detail falhou: %s", e$message))
    list(ok = FALSE, html = NULL, text = "")
  })

  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    return(list(title = NA_character_, description = NA_character_, status_text = ""))
  }

  h1_node <- rvest::html_node(pg$html, "h1.headline")
  title <- if (!is.null(h1_node) && !inherits(h1_node, "xml_missing")) {
    trimws(rvest::html_text(h1_node, trim = TRUE))
  } else { NA_character_ }

  content_nodes <- try(rvest::html_elements(pg$html, ".article-content__block--text .text"), silent = TRUE)
  desc_parts <- character()
  if (!inherits(content_nodes, "try-error") && length(content_nodes) > 0) {
    for (node in utils::head(content_nodes, 3)) {
      txt <- trimws(rvest::html_text(node, trim = TRUE))
      if (nzchar(txt) && nchar(txt) > 20) {
        desc_parts <- c(desc_parts, txt)
      }
    }
  }
  description <- if (length(desc_parts) > 0) {
    paste(desc_parts, collapse = "\n\n")
  } else { NA_character_ }

  status_text <- tolower(pg$text)
  if (grepl("closing date.*elapsed|not currently possible to apply", status_text)) {
    status_text <- "closing date has elapsed"
  } else if (grepl("next application round|next round.*opens", status_text)) {
    status_text <- "next application round"
  } else {
    status_text <- ""
  }

  list(title = title, description = description, status_text = status_text)
}

collect_humboldt <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[HUMBOLDT][%s] %s", level, msg))
  }

  .log("INFO", "Iniciando coleta Alexander von Humboldt Foundation.")
  try(log_progress("Iniciando coleta Humboldt", "Scraping"), silent = TRUE)

  base_url <- "https://www.humboldt-foundation.de"
  listing_base <- "/en/apply/sponsorship-programmes/programmes-a-to-z"
  user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

  # Fetch fellowships listing
  .log("INFO", "Buscando fellowships...")
  all_listings <- tibble::tibble()

  for (filter_param in c("schollarships", "award")) {
    listing_url <- paste0(base_url, listing_base, "?tx_rsmavhcontent_programmes[controller]=Programmes&tx_rsmavhcontent_programmes[filterBy]=", filter_param)
    program_type <- if (filter_param == "schollarships") "fellowship" else "award"

    resp <- tryCatch({
      req <- httr2::request(listing_url) |>
        httr2::req_user_agent(user_agent) |>
        httr2::req_timeout(20) |>
        httr2::req_retry(max_tries = 3)
      httr2::req_perform(req)
    }, error = function(e) {
      .log("WARN", sprintf("Falha ao buscar listing %s: %s", filter_param, e$message))
      NULL
    })

    if (is.null(resp) || httr2::resp_status(resp) != 200) next

    html_text <- httr2::resp_body_string(resp, encoding = "UTF-8")
    html <- rvest::read_html(html_text)

    listing_df <- extract_humboldt_listing(html, base_url, program_type)
    if (nrow(listing_df) > 0) {
      .log("INFO", sprintf("Filter '%s': %d programas encontrados.", filter_param, nrow(listing_df)))
      all_listings <- dplyr::bind_rows(all_listings, listing_df)
    }
    Sys.sleep(1)
  }

  if (nrow(all_listings) == 0) {
    .log("WARN", "Nenhum programa encontrado no listing.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = listing_url))
  }

  # Deduplicate by listing title
  all_listings <- all_listings |> dplyr::distinct(listing_title, .keep_all = TRUE)
  .log("INFO", sprintf("Total de %d programas únicos após dedup.", nrow(all_listings)))

  if (nrow(all_listings) > max_records) {
    all_listings <- all_listings[seq_len(max_records), ]
  }

  # Fetch detail pages
  records <- list()
  detail_failures <- 0L

  for (i in seq_len(nrow(all_listings))) {
    row <- all_listings[i, , drop = FALSE]
    detail_url <- row$detail_url[[1]]

    if (i > 1) Sys.sleep(0.5)

    detail <- extract_humboldt_detail(detail_url, log_path)
    if (is.na(detail$title) || !nzchar(detail$title)) {
      detail$title <- row$listing_title[[1]]
    }
    if (is.na(detail$description) || !nzchar(detail$description)) {
      detail$description <- row$for_what[[1]]
    }

    status <- infer_humboldt_status(detail$status_text)
    country <- normalize_humboldt_country(row$from_where_raw[[1]])

    titulo <- detail$title
    detail_text <- paste(collapse_non_empty(titulo, detail$description, row$for_whom[[1]], row$from_where_raw[[1]]), collapse = "\n")
    hash_input <- paste0(titulo, "|", detail_url)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    rec <- tibble::tibble(
      id_registro = sprintf("humboldt_%s", substr(hash_dedup, 1, 16)),
      entidade = "Alexander von Humboldt Foundation",
      pais_origem = "Alemanha",
      titulo = titulo,
      subtitulo = NA_character_,
      descricao_resumida = substr(detail$description %||% row$for_what[[1]], 1, 500),
      descricao_completa = detail$description %||% detail_text,
      tipo_oportunidade = row$program_type[[1]],
      modalidade = if (row$program_type[[1]] == "fellowship") "bolsa" else "prêmio",
      area_tematica = NA_character_,
      palavras_chave = NA_character_,
      elegibilidade = row$for_whom[[1]],
      publico_alvo = row$for_whom[[1]],
      nivel_academico = NA_character_,
      instituicao_financiadora = "Alexander von Humboldt Foundation",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = NA_character_,
      data_encerramento = NA_character_,
      status_oportunidade = status,
      link_origem = paste0(base_url, listing_base),
      link_detalhe = as.character(detail_url),
      link_documento_pdf = NA_character_,
      idioma = "en",
      localidade = row$from_where_raw[[1]],
      observacoes = row$for_what[[1]],
      texto_bruto = detail_text,
      pagina_coletada = 1L,
      fonte_oficial = "humboldt",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = ""
    )

    records[[i]] <- rec

    if (i %% 5 == 0) {
      .log("INFO", sprintf("Progresso: %d/%d detalhes coletados.", i, nrow(all_listings)))
    }
  }

  if (length(records) == 0) {
    .log("WARN", "Nenhum registro coletado.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = listing_url))
  }

  df <- dplyr::bind_rows(records)
  .log("INFO", sprintf("HUMBOLDT: %d registros finais coletados.", nrow(df)))

  list(records = df, pages_visited = 2L, last_url = listing_url)
}

register_collector("humboldt", collect_humboldt, "Alexander von Humboldt Foundation HTML scraper")
register_collector("cnpq", collect_cnpq, "CNPq custom scraper: Busca_abertas + abertas-para-submissao + Plone Search API fallback")

# --- World Bank Collectors ---

collect_world_bank_excel <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[WORLD_BANK_EXCEL][%s] %s", level, msg))
  }

  .log("INFO", "Excel export is client-side JavaScript; using API as data source.")
  try(log_progress("Iniciando coleta World Bank Excel (via API)", "Scraping"), silent = TRUE)

  # Excel export is done client-side via JavaScript (ExcelJS)
  # We use the API directly as the data source
  collect_world_bank_api(source_row, max_pages, max_records, use_ai, log_path)
}

collect_world_bank_html <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[WORLD_BANK_HTML][%s] %s", level, msg))
  }

  .log("INFO", "Iniciando coleta World Bank via HTML (fallback com Playwright).")
  try(log_progress("Iniciando coleta World Bank HTML", "Scraping"), silent = TRUE)

  listing_url <- "https://projects.worldbank.org/pt/projects-operations/opportunities?project_ctry_name_exact=Brazil"
  detail_base <- "https://projects.worldbank.org/pt/projects-operations/procurement-detail"

  # Use Playwright to render JavaScript
  result <- safe_request_page_playwright(listing_url, log_path)

  if (!result$ok) {
    .log("WARN", "Playwright failed for HTML listing.")
    return(list(records = tibble::tibble(), pages_visited = 0L, last_url = listing_url))
  }

  html <- result$html

  # Extract notice IDs from the rendered page
  # The page uses Angular procurement-search component
  # Look for links to detail pages
  links <- rvest::html_nodes(html, "a[href*='procurement-detail']")
  if (length(links) == 0) {
    # Fallback: look for any links with OP pattern
    all_links <- rvest::html_nodes(html, "a")
    hrefs <- rvest::html_attr(all_links, "href")
    op_pattern <- grepl("OP\\d{8}", hrefs)
    links <- all_links[op_pattern]
  }

  if (length(links) == 0) {
    .log("WARN", "Nenhum link de detail encontrado no HTML.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = listing_url))
  }

  records <- list()
  seen_ids <- character()

  for (i in seq_len(min(length(links), max_records))) {
    link <- links[[i]]
    href <- rvest::html_attr(link, "href")

    # Extract notice ID from URL
    notice_id <- sub(".*?(OP\\d{8}).*", "\\1", href)
    if (is.na(notice_id) || !nzchar(notice_id)) next
    if (notice_id %in% seen_ids) next
    seen_ids <- c(seen_ids, notice_id)

    # Get title from link text or nearby elements
    titulo <- rvest::html_text(link, trim = TRUE)
    if (!nzchar(titulo)) {
      # Try to get title from parent row
      parent_row <- rvest::html_parent(link)
      titulo <- rvest::html_text(parent_row, trim = TRUE)
    }
    if (!nzchar(titulo)) titulo <- notice_id

    # Resolve URL
    detail_url <- if (grepl("^https?://", href)) {
      href
    } else {
      paste0("https://projects.worldbank.org", href)
    }

    hash_input <- paste0("World Bank", "||", notice_id, "||", titulo)
    hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

    rec <- tibble::tibble(
      id_registro = sprintf("wb_%s", substr(hash_dedup, 1, 16)),
      entidade = "World Bank",
      pais_origem = "Brazil",
      titulo = titulo,
      subtitulo = NA_character_,
      descricao_resumida = substr(titulo, 1, 500),
      descricao_completa = titulo,
      tipo_oportunidade = NA_character_,
      modalidade = NA_character_,
      area_tematica = NA_character_,
      palavras_chave = NA_character_,
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "World Bank",
      valor_financiado = NA_real_,
      moeda = NA_character_,
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = NA_character_,
      data_encerramento = NA_character_,
      status_oportunidade = "aberto",
      link_origem = listing_url,
      link_detalhe = detail_url,
      link_documento_pdf = NA_character_,
      idioma = "pt",
      localidade = "Brazil",
      observacoes = NA_character_,
      texto_bruto = titulo,
      pagina_coletada = 1L,
      fonte_oficial = "world_bank",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = ""
    )

    records[[length(records) + 1]] <- rec
  }

  if (length(records) == 0) {
    .log("WARN", "Nenhum registro extraído do HTML.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = listing_url))
  }

  df <- dplyr::bind_rows(records)
  .log("INFO", sprintf("WORLD_BANK_HTML: %d registros extraídos.", nrow(df)))

  list(records = df, pages_visited = 1L, last_url = listing_url)
}

collect_world_bank_api <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[WORLD_BANK_API][%s] %s", level, msg))
  }

  .log("INFO", "Iniciando coleta World Bank via Procurement Notices API.")
  try(log_progress("Iniciando coleta World Bank API", "Scraping"), silent = TRUE)

  api_base <- "https://search.worldbank.org/api/v2/procnotices"
  detail_base <- "https://projects.worldbank.org/pt/projects-operations/procurement-detail"
  user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

  all_records <- list()
  offset <- 0L
  rows_per_page <- 50L
  pages_visited <- 0L

  repeat {
    if (length(all_records) >= max_records) break
    if (pages_visited >= max_pages) break

    api_url <- sprintf(
      "%s?format=json&fl=id,submission_deadline_date,bid_description,project_ctry_name,project_name,notice_type,notice_status,notice_lang_name,submission_date,noticedate&os=%d&rows=%d&apilang=en&project_ctry_name_exact=Brazil",
      api_base, offset, rows_per_page
    )

    .log("INFO", sprintf("Buscando API offset=%d...", offset))
    resp <- tryCatch({
      req <- httr2::request(api_url) |>
        httr2::req_user_agent(user_agent) |>
        httr2::req_timeout(30) |>
        httr2::req_retry(max_tries = 3)
      httr2::req_perform(req)
    }, error = function(e) {
      .log("WARN", sprintf("Falha na API: %s", e$message))
      NULL
    })

    if (is.null(resp)) break

    status <- httr2::resp_status(resp)
    if (status == 429L) {
      .log("WARN", "Rate limited by API. Waiting 60 seconds...")
      Sys.sleep(60)
      next
    }
    if (status != 200L) break

    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
    if (is.null(body)) break

    num_found <- as.integer(body$total %||% 0L)
    notices <- body$procnotices %||% list()

    if (length(notices) == 0) break

    pages_visited <- pages_visited + 1L

    for (notice in notices) {
      if (length(all_records) >= max_records) break

      notice_id <- notice$id %||% NA_character_
      titulo <- notice$bid_description %||% NA_character_
      if (is.na(titulo) || !nzchar(titulo)) next

      project_name <- notice$project_name %||% NA_character_
      notice_type <- notice$notice_type %||% NA_character_
      noticedate <- notice$noticedate %||% NA_character_
      deadline <- notice$submission_deadline_date %||% NA_character_
      country <- notice$project_ctry_name %||% "Brazil"
      notice_status <- notice$notice_status %||% NA_character_
      lang <- notice$notice_lang_name %||% "Portuguese"

      # Parse deadline date (format: 2026-07-22T00:00:00Z)
      data_limite <- NA_character_
      if (!is.na(deadline) && nzchar(deadline)) {
        data_limite <- tryCatch({
          parsed <- as.POSIXct(deadline, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
          format(parsed, "%Y-%m-%d")
        }, error = function(e) deadline)
      }

      # Map notice status to Portuguese
      status_map <- c(
        "Published" = "aberto",
        "Closed" = "encerrado",
        "Cancelled" = "encerrado",
        "Active" = "aberto"
      )
      status_oportunidade <- status_map[notice_status] %||% "aberto"

      # Build detail URL
      detail_url <- if (!is.na(notice_id) && nzchar(notice_id)) {
        sprintf("%s/%s", detail_base, notice_id)
      } else {
        NA_character_
      }

      hash_input <- paste0("World Bank", "||", notice_id, "||", titulo)
      hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

      rec <- tibble::tibble(
        id_registro = sprintf("wb_%s", substr(hash_dedup, 1, 16)),
        entidade = "World Bank",
        pais_origem = country,
        titulo = titulo,
        subtitulo = project_name,
        descricao_resumida = substr(titulo, 1, 500),
        descricao_completa = titulo,
        tipo_oportunidade = notice_type,
        modalidade = notice_type,
        area_tematica = NA_character_,
        palavras_chave = NA_character_,
        elegibilidade = NA_character_,
        publico_alvo = NA_character_,
        nivel_academico = NA_character_,
        instituicao_financiadora = "World Bank",
        valor_financiado = NA_real_,
        moeda = NA_character_,
        data_publicacao = noticedate,
        data_abertura = NA_character_,
        data_limite = data_limite,
        data_encerramento = NA_character_,
        status_oportunidade = status_oportunidade,
        link_origem = api_url,
        link_detalhe = detail_url,
        link_documento_pdf = NA_character_,
        idioma = tolower(substr(lang, 1, 2)),
        localidade = "Brazil",
        observacoes = NA_character_,
        texto_bruto = paste(collapse_non_empty(titulo, project_name, notice_type), collapse = "\n"),
        pagina_coletada = as.integer(pages_visited),
        fonte_oficial = "world_bank",
        data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        hash_deduplicacao = hash_dedup,
        campos_inferidos_ia = ""
      )

      all_records[[length(all_records) + 1]] <- rec
    }

    if (num_found <= offset + rows_per_page) break
    offset <- offset + rows_per_page
  }

  if (length(all_records) == 0) {
    .log("WARN", "Nenhum registro retornado pela API.")
    return(list(records = tibble::tibble(), pages_visited = pages_visited, last_url = api_base))
  }

  df <- dplyr::bind_rows(all_records)
  .log("INFO", sprintf("WORLD_BANK_API: %d registros extraídos.", nrow(df)))

  list(records = df, pages_visited = pages_visited, last_url = api_base)
}

collect_world_bank <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[WORLD_BANK][%s] %s", level, msg))
  }

  .log("INFO", "Iniciando coleta World Bank (cascade: API -> Excel -> HTML).")
  try(log_progress("Iniciando coleta World Bank", "Scraping"), silent = TRUE)

  base_url <- "https://projects.worldbank.org/pt/projects-operations/opportunities?project_ctry_name_exact=Brazil"

  # Tier 1: API (most reliable - direct access to procurement notices)
  .log("INFO", "Tentativa 1: Procurement Notices API...")
  result_api <- tryCatch(
    collect_world_bank_api(source_row, max_pages, max_records, use_ai, log_path),
    error = function(e) {
      .log("WARN", sprintf("API collector failed: %s", e$message))
      NULL
    }
  )

  if (!is.null(result_api) && nrow(result_api$records) > 0) {
    .log("INFO", sprintf("API coleta bem-sucedida: %d registros.", nrow(result_api$records)))
    return(result_api)
  }

  # Tier 2: Excel (calls API internally)
  .log("INFO", "Tentativa 2: Excel (via API)...")
  result_excel <- tryCatch(
    collect_world_bank_excel(source_row, max_pages, max_records, use_ai, log_path),
    error = function(e) {
      .log("WARN", sprintf("Excel collector failed: %s", e$message))
      NULL
    }
  )

  if (!is.null(result_excel) && nrow(result_excel$records) > 0) {
    .log("INFO", sprintf("Excel coleta bem-sucedida: %d registros.", nrow(result_excel$records)))
    return(result_excel)
  }

  # Tier 3: HTML with Playwright (JavaScript rendering)
  .log("INFO", "Tentativa 3: HTML com Playwright...")
  result_html <- tryCatch(
    collect_world_bank_html(source_row, max_pages, max_records, use_ai, log_path),
    error = function(e) {
      .log("WARN", sprintf("HTML collector failed: %s", e$message))
      NULL
    }
  )

  if (!is.null(result_html) && nrow(result_html$records) > 0) {
    .log("INFO", sprintf("HTML coleta bem-sucedida: %d registros.", nrow(result_html$records)))
    return(result_html)
  }

  # All methods failed
  .log("WARN", "Todos os métodos de coleta falharam. Retornando vazio.")
  list(records = tibble::tibble(), pages_visited = 0L, last_url = base_url)
}

register_collector("world_bank", collect_world_bank, "World Bank: Excel download + HTML scraping + Projects API fallback")

# --- US Sources Proxy Helper (generalizes EU_API_PROXY_URL) ---
get_us_proxy_url <- function(target_url) {
  worker <- Sys.getenv("EU_API_PROXY_URL", unset = "")
  if (!nzchar(worker)) return(target_url)
  worker <- sub("/+$", "", worker)
  # If target is EU API, keep original behavior (worker + path)
  if (grepl("api\\.tech\\.ec\\.europa\\.eu", target_url, ignore.case = TRUE)) {
    return(target_url)
  }
  # Generic proxy fallback: worker?url=TARGET (supports Cloudflare Worker that forwards ?url)
  # Also try worker/proxy?url= pattern if first fails (handled by caller trying both)
  paste0(worker, "?url=", utils::URLencode(target_url, reserved = TRUE))
}

safe_request_page_us <- function(url, log_path = NULL, conn = NULL) {
  # Wrapper that tries direct request, then proxy fallback if EU_API_PROXY_URL is set
  res <- safe_request_page(url, log_path = log_path, conn = conn)
  if (isTRUE(res$ok)) return(res)
  proxy_base <- Sys.getenv("EU_API_PROXY_URL", unset = "")
  if (!nzchar(proxy_base)) return(res)
  # Try proxy URL
  proxy_url <- get_us_proxy_url(url)
  if (identical(proxy_url, url)) return(res)
  # Only attempt proxy if original failure was block/network
  try(log_write(log_path, "INFO", sprintf("Tentando via proxy EU_API_PROXY_URL para %s", url)), silent = TRUE)
  res_proxy <- tryCatch(safe_request_page(proxy_url, log_path = log_path, conn = conn), error = function(e) list(ok = FALSE))
  if (isTRUE(res_proxy$ok)) {
    # Override url to original for downstream resolve
    res_proxy$url <- url
    return(res_proxy)
  }
  res
}

# ---------------------------------------------------------------------------
#  Grants.gov - Public Diplomacy (CFDA 19.040) - Hybrid API + HTML
# ---------------------------------------------------------------------------
collect_grants_gov <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[GRANTS_GOV][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta Grants.gov (CFDA 19.040 - Public Diplomacy).")
  try(log_progress("Iniciando coleta Grants.gov", "Scraping"), silent = TRUE)

  base_search_url <- source_row$url_oportunidades[[1]] %||% "https://simpler.grants.gov/search"
  # Fallback base if catalog not updated
  if (is.na(base_search_url) || !nzchar(base_search_url)) base_search_url <- "https://simpler.grants.gov/search"

  # --- Tier 1: Tentar API interna Simpler Grants.gov (POST JSON) ---
  api_endpoints <- c(
    "https://simpler.grants.gov/api/opportunities/search",
    "https://simpler.grants.gov/api/v1/opportunities/search",
    "https://simpler.grants.gov/api/search",
    "https://simpler.grants.gov/search/api/search"
  )

  api_records <- list()
  api_success <- FALSE
  for (api_url in api_endpoints) {
    .log("INFO", sprintf("Tentando API Grants.gov: %s", api_url))
    .scrape_rate_limiter$wait_if_needed(api_url)

    # Payload filtrando CFDA 19.040 e keywords Public Diplomacy
    payload <- list(
      pagination = list(page_offset = 1, page_size = min(25L, max_records), sort_order = list(list(order_by = "opportunity_number", sort_direction = "descending"))),
      filters = list(
        opportunity_status = list(one_of = c("posted", "forecasted", "archived")),
        assistance_listing_number = list(one_of = c("19.040", "19.04")),
        funding_instrument = list(one_of = c("grant", "cooperative agreement")),
        search_text = list(one_of = c("public diplomacy", "Public Diplomacy Programs", "people-to-people", "American expertise"))
      )
    )
    # Alternative flat payload for older endpoints
    payload_alt <- list(
      filters = list(cfda = "19.040", status = "posted", query = "public diplomacy"),
      pagination = list(page = 1, pageSize = 25)
    )

    body_json <- jsonlite::toJSON(payload, auto_unbox = TRUE)
    body_alt <- jsonlite::toJSON(payload_alt, auto_unbox = TRUE)

    for (body_try in list(body_json, body_alt)) {
      hdrs <- build_scrape_headers()
      req <- httr2::request(api_url) |>
        httr2::req_user_agent(hdrs$`User-Agent`) |>
        httr2::req_headers(
          `Accept` = "application/json, text/plain, */*",
          `Content-Type` = "application/json",
          `Accept-Language` = "en-US,en;q=0.9",
          `Origin` = "https://simpler.grants.gov",
          `Referer` = "https://simpler.grants.gov/search"
        ) |>
        httr2::req_body_raw(body_try, type = "application/json") |>
        httr2::req_timeout(20) |>
        httr2::req_retry(max_tries = 1)

      resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
      if (is.null(resp) || httr2::resp_status(resp) >= 400) {
        # Try via proxy if direct blocked
        proxy_base <- Sys.getenv("EU_API_PROXY_URL", unset = "")
        if (nzchar(proxy_base)) {
          proxy_url <- get_us_proxy_url(api_url)
          req_p <- httr2::request(proxy_url) |>
            httr2::req_user_agent(hdrs$`User-Agent`) |>
            httr2::req_headers(`Accept` = "application/json", `Content-Type` = "application/json") |>
            httr2::req_body_raw(body_try, type = "application/json") |>
            httr2::req_timeout(20)
          resp <- tryCatch(httr2::req_perform(req_p), error = function(e) NULL)
        }
      }
      if (is.null(resp) || httr2::resp_status(resp) >= 400) next

      data <- tryCatch(httr2::resp_body_json(resp, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(data)) {
        txt <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
        data <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
      }
      if (is.null(data)) next

      # Extract opportunities array - handle multiple response shapes
      opps <- NULL
      if (!is.null(data$data$opportunities)) opps <- data$data$opportunities
      else if (!is.null(data$data)) opps <- data$data
      else if (!is.null(data$opportunities)) opps <- data$opportunities
      else if (!is.null(data$hits)) opps <- data$hits
      else if (!is.null(data$results)) opps <- data$results

      if (is.null(opps) || length(opps) == 0) next

      .log("INFO", sprintf("Grants.gov API retornou %d oportunidades brutas", length(opps)))

      # Filter for CFDA 19.040 if not already
      filtered <- Filter(function(o) {
        cfda <- tryCatch({
          if (!is.null(o$assistance_listings)) paste(o$assistance_listings, collapse = " ")
          else if (!is.null(o$cfda_numbers)) paste(o$cfda_numbers, collapse = " ")
          else if (!is.null(o$cfda)) as.character(o$cfda)
          else ""
        }, error = function(e) "")
        grepl("19\\.0?40", cfda) || grepl("19\\.040", jsonlite::toJSON(o, auto_unbox = TRUE))
      }, opps)

      # If filter removes all, keep all (search already filtered)
      if (length(filtered) == 0) filtered <- opps

      for (opp in filtered) {
        if (length(api_records) >= max_records) break
        opp_id <- opp$opportunity_id %||% opp$opportunity_number %||% opp$id %||% NA_character_
        titulo <- opp$opportunity_title %||% opp$title %||% opp$opportunityTitle %||% NA_character_
        if (is.na(titulo) || !nzchar(titulo)) next
        agency <- opp$agency_name %||% opp$agency %||% opp$top_level_agency_name %||% "U.S. Department of State"
        desc <- opp$summary %||% opp$description %||% opp$opportunity_description %||% titulo
        close_date <- opp$close_date %||% opp$closing_date %||% opp$closeDate %||% opp$deadline %||% NA_character_
        post_date <- opp$post_date %||% opp$posted_date %||% opp$open_date %||% opp$postedDate %||% NA_character_
        opp_num <- opp$opportunity_number %||% opp_id %||% ""
        detail_url <- if (!is.na(opp_id) && nzchar(opp_id)) sprintf("https://simpler.grants.gov/opportunity/%s", opp_id) else base_search_url
        cfda_str <- tryCatch({
          if (!is.null(opp$assistance_listings)) paste(vapply(opp$assistance_listings, function(x) if (is.list(x)) x$assistance_listing_number %||% x[[1]] else as.character(x), character(1)), collapse = "; ")
          else "19.040"
        }, error = function(e) "19.040")

        # Parse USD date MM/DD/YYYY
        data_limite <- tryCatch(as.character(parse_date_safe(close_date)), error = function(e) NA_character_)
        data_pub <- tryCatch(as.character(parse_date_safe(post_date)), error = function(e) NA_character_)
        # If close_date is still NA, try extract from text
        if (is.na(data_limite) || !nzchar(data_limite)) {
          dates_txt <- extract_dates_from_text(paste(titulo, desc, close_date))
          if (length(dates_txt) > 0) data_limite <- as.character(max(dates_txt, na.rm = TRUE))
        }

        hash_input <- paste0("Grants.gov", "||", opp_num, "||", titulo)
        hash_dedup <- digest::digest(hash_input, algo = "xxhash64")

        rec <- tibble::tibble(
          id_registro = sprintf("grants_gov_%s", substr(hash_dedup, 1, 16)),
          entidade = "Grants.gov",
          pais_origem = "Estados Unidos",
          titulo = as.character(titulo),
          subtitulo = as.character(agency),
          descricao_resumida = substr(as.character(desc), 1, 500),
          descricao_completa = as.character(desc),
          tipo_oportunidade = "grant",
          modalidade = NA_character_,
          area_tematica = "Public Diplomacy",
          palavras_chave = paste(c("public diplomacy", "people-to-people ties", "American expertise", "cultural exchange", cfda_str), collapse = "; "),
          elegibilidade = NA_character_,
          publico_alvo = NA_character_,
          nivel_academico = NA_character_,
          instituicao_financiadora = "U.S. Department of State",
          valor_financiado = NA_real_,
          moeda = "USD",
          data_publicacao = data_pub,
          data_abertura = NA_character_,
          data_limite = data_limite,
          data_encerramento = NA_character_,
          status_oportunidade = classify_status(deadline = data_limite, text = titulo)[[1]],
          link_origem = base_search_url,
          link_detalhe = detail_url,
          link_documento_pdf = NA_character_,
          idioma = "en",
          localidade = NA_character_,
          observacoes = sprintf("CFDA %s - NOFO/AP via simpler.grants.gov. Opportunity Number: %s. Sazonal set-nov.", cfda_str, opp_num),
          texto_bruto = paste(collapse_non_empty(titulo, desc, cfda_str), collapse = "\n\n"),
          pagina_coletada = 1L,
          fonte_oficial = "grants_gov",
          data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          hash_deduplicacao = hash_dedup,
          campos_inferidos_ia = NA_character_
        )
        api_records[[length(api_records) + 1]] <- rec
      }
      if (length(api_records) > 0) {
        api_success <- TRUE
        break
      }
    }
    if (api_success) break
  }

  if (api_success && length(api_records) > 0) {
    df <- dplyr::bind_rows(api_records)
    .log("INFO", sprintf("Grants.gov API: %d registros finais coletados.", nrow(df)))
    return(list(records = df, pages_visited = 1L, last_url = base_search_url))
  }

  # --- Tier 2: HTML scraping fallback ---
  .log("INFO", "Grants.gov API falhou ou vazia. Tentando HTML scraping com Playwright fallback.")
  # Build search URL with CFDA 19.040 filter and public diplomacy query
  search_urls <- c(
    paste0(base_search_url, "?status=posted&fundingInstrumentType=grant&assistanceListingNumber=19.040&searchText=public%20diplomacy"),
    paste0(base_search_url, "?query=public%20diplomacy&cfda=19.040"),
    base_search_url
  )

  all_records <- tibble::tibble()
  pages_visited <- 0L
  last_url <- base_search_url

  for (search_url in search_urls) {
    if (nrow(all_records) >= max_records) break
    .log("INFO", sprintf("Grants.gov HTML: buscando %s", search_url))
    pg <- safe_request_page_us(search_url, log_path = log_path)
    pages_visited <- pages_visited + 1L
    last_url <- search_url

    if (!isTRUE(pg$ok) || is.null(pg$html)) {
      .log("WARN", sprintf("Falha ao carregar %s", search_url))
      next
    }

    # Custom extractor for Simpler Grants.gov (Next.js SSR)
    nodes <- try(rvest::html_elements(pg$html, "a[href*='/opportunity/'], .search-result, [data-testid='opportunity'], article, .card"), silent = TRUE)
    candidates <- tryCatch({
      if (!inherits(nodes, "try-error") && length(nodes) > 0) {
        purrr::map_dfr(seq_along(nodes), function(i) {
          node <- nodes[[i]]
          href <- tryCatch(rvest::html_attr(node, "href"), error = function(e) NA_character_)
          if (is.na(href) || !nzchar(href)) {
            a <- try(rvest::html_element(node, "a[href*='/opportunity/']"), silent = TRUE)
            href <- if (!inherits(a, "try-error")) rvest::html_attr(a, "href") else NA_character_
          }
          abs_url <- if (!is.na(href) && nzchar(href)) resolve_url(search_url, href) else NA_character_
          txt <- safe_html_text(node)
          if (is.na(txt) || nchar(txt) < 20) return(tibble::tibble())
          # Must contain 19.040 or public diplomacy signal or look like opportunity
          if (!grepl("19\\.040|public diplomacy|opportunity|NOFO|assistance listing", txt, ignore.case = TRUE) &&
              !grepl("19\\.040|public diplomacy", abs_url %||% "", ignore.case = TRUE)) {
            # Still allow if node is inside search results container
            if (!grepl("opportunity|grant|diplomacy", txt, ignore.case = TRUE)) return(tibble::tibble())
          }
          title <- tryCatch({
            h <- rvest::html_element(node, "h2, h3, .opportunity-title, [class*='title']")
            t <- safe_html_text(h)
            if (!is.na(t) && nzchar(t)) t else stringr::str_sub(txt, 1, 140)
          }, error = function(e) stringr::str_sub(txt, 1, 140))

          tibble::tibble(
            title = title,
            summary = stringr::str_sub(txt, 1, 700),
            detail_url = abs_url,
            source_text = txt
          )
        })
      } else tibble::tibble()
    }, error = function(e) tibble::tibble())

    # Fallback to generic extractor if custom found nothing
    if (nrow(candidates) == 0) {
      gen <- tryCatch(extract_listing_candidates(pg$html, search_url, source_row), error = function(e) tibble::tibble())
      if (nrow(gen) > 0) {
        candidates <- gen |> dplyr::transmute(title = title, summary = summary, detail_url = detail_url, source_text = source_text)
      }
    }

    if (nrow(candidates) == 0) next

    # Deduplicate and limit
    candidates <- candidates |>
      dplyr::filter(!is.na(title) | !is.na(detail_url)) |>
      dplyr::distinct(detail_url, .keep_all = TRUE)
    if (nrow(candidates) > (max_records - nrow(all_records))) {
      candidates <- candidates[seq_len(max_records - nrow(all_records)), ]
    }

    # Convert to records
    for (i in seq_len(nrow(candidates))) {
      one <- candidates[i, ]
      # Try to fetch detail for deadline
      bundle <- list(detail_title = one$title[[1]], detail_summary = one$summary[[1]], full_text = one$source_text[[1]], pdf_url = NA_character_)
      if (!is.na(one$detail_url[[1]]) && nzchar(one$detail_url[[1]])) {
        bundle <- tryCatch(extract_detail_bundle(detail_url = one$detail_url[[1]], page_url = search_url, log_path = log_path), error = function(e) bundle)
      }
      rec_title <- pick_first_nonempty(bundle$detail_title, one$title[[1]])
      raw_for_dates <- paste(bundle$detail_summary %||% "", bundle$full_text %||% "", one$source_text[[1]] %||% "", collapse = " ")
      dates <- extract_dates_from_text(raw_for_dates)
      deadline <- if (length(dates) > 0 && any(!is.na(dates))) as.character(max(dates, na.rm = TRUE)) else NA_character_
      # Prefer explicit close date in text
      if (grepl("close|deadline|closing date", raw_for_dates, ignore.case = TRUE) && !is.na(deadline)) {
        # keep
      }

      hash_dedup <- digest::digest(paste0(rec_title, one$detail_url[[1]] %||% search_url), algo = "xxhash64")
      rec <- tibble::tibble(
        id_registro = sprintf("grants_gov_%s", substr(hash_dedup, 1, 16)),
        entidade = "Grants.gov",
        pais_origem = "Estados Unidos",
        titulo = rec_title,
        subtitulo = NA_character_,
        descricao_resumida = substr(pick_first_nonempty(bundle$detail_summary, one$summary[[1]]), 1, 500),
        descricao_completa = bundle$full_text %||% one$source_text[[1]],
        tipo_oportunidade = "grant",
        modalidade = NA_character_,
        area_tematica = "Public Diplomacy",
        palavras_chave = "public diplomacy; people-to-people ties; American expertise; 19.040",
        elegibilidade = NA_character_,
        publico_alvo = NA_character_,
        nivel_academico = NA_character_,
        instituicao_financiadora = "U.S. Department of State",
        valor_financiado = NA_real_,
        moeda = "USD",
        data_publicacao = NA_character_,
        data_abertura = NA_character_,
        data_limite = deadline,
        data_encerramento = NA_character_,
        status_oportunidade = classify_status(deadline = deadline, text = rec_title)[[1]],
        link_origem = search_url,
        link_detalhe = one$detail_url[[1]] %||% search_url,
        link_documento_pdf = bundle$pdf_url,
        idioma = "en",
        localidade = NA_character_,
        observacoes = "CFDA 19.040 Public Diplomacy Programs. NOFO/AP via simpler.grants.gov (HTML fallback).",
        texto_bruto = paste(collapse_non_empty(rec_title, bundle$full_text, one$source_text[[1]]), collapse = "\n\n"),
        pagina_coletada = 1L,
        fonte_oficial = "grants_gov",
        data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        hash_deduplicacao = hash_dedup,
        campos_inferidos_ia = NA_character_
      )
      all_records <- dplyr::bind_rows(all_records, rec)
      if (nrow(all_records) >= max_records) break
    }
    if (nrow(all_records) >= max_records) break
    # Try next page if available
    next_url <- tryCatch(detect_next_page(pg$html, search_url), error = function(e) NA_character_)
    if (!is.na(next_url) && nzchar(next_url) && pages_visited < max_pages) {
      search_urls <- c(search_urls, next_url)
    }
  }

  if (nrow(all_records) == 0) {
    .log("WARN", "Grants.gov: Nenhum registro encontrado após API + HTML scraping. Retornando vazio (sem FOA ativa ou bloqueio WAF).")
    return(list(records = tibble::tibble(), pages_visited = pages_visited, last_url = last_url))
  }

  df <- finalize_records(all_records, fonte_oficial = "grants_gov")
  # If finalize filtered all (e.g., old year), return raw (US sources should be more permissive for future)
  if (nrow(df) == 0 && nrow(all_records) > 0) {
    .log("WARN", "Grants.gov: finalize_records filtrou todos. Retornando registros brutos com deduplicacao simples.")
    df <- dedupe_records(all_records)
  }
  .log("INFO", sprintf("Grants.gov HTML: %d registros finais coletados.", nrow(df)))
  list(records = df, pages_visited = pages_visited, last_url = last_url)
}
register_collector("grants_gov", collect_grants_gov, "Grants.gov: Hybrid API + HTML scraping (CFDA 19.040 Public Diplomacy)")

# ---------------------------------------------------------------------------
#  DOE ASCR - Advanced Scientific Computing Research (Favorito)
# ---------------------------------------------------------------------------
collect_doe_ascr <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[DOE_ASCR][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta DOE ASCR (HPC, Quantum, AI for Science).")
  try(log_progress("Iniciando coleta DOE ASCR", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://science.osti.gov/ascr/Funding-Opportunities"
  if (is.na(base_url) || !nzchar(base_url)) base_url <- "https://science.osti.gov/ascr/Funding-Opportunities"

  # Try DOE OSTI API first (if available)
  osti_api_url <- "https://www.osti.gov/api/v1/records?search=ASCR+funding+opportunity&sort=publication_date%20desc&rows=20"
  api_records <- list()
  api_tried <- FALSE
  api_ok <- FALSE
  try({
    .log("INFO", "Tentando OSTI API fallback...")
    .scrape_rate_limiter$wait_if_needed(osti_api_url)
    req <- httr2::request(osti_api_url) |>
      httr2::req_user_agent(get_random_ua()) |>
      httr2::req_timeout(15)
    resp <- httr2::req_perform(req)
    if (httr2::resp_status(resp) == 200) {
      api_tried <- TRUE
      txt <- httr2::resp_body_string(resp)
      data <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(data) && length(data) > 0) {
        # OSTI returns XML/JSON hybrid; if we get here, log but don't rely
        .log("INFO", sprintf("OSTI API retornou %d itens (nao estruturado como FOA). Usando como enriquecimento apenas.", length(data)))
      }
    }
  }, silent = TRUE)

  # Main: HTML scraping of ASCR Funding Opportunities page
  pg <- safe_request_page_us(base_url, log_path = log_path)
  pages_visited <- 1L
  last_url <- base_url

  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", sprintf("Falha ao carregar DOE ASCR %s. Tentando via science.energy.gov espelho.", base_url))
    alt_url <- "https://science.energy.gov/ascr/funding-opportunities/"
    pg2 <- safe_request_page_us(alt_url, log_path = log_path)
    if (isTRUE(pg2$ok) && !is.null(pg2$html)) {
      pg <- pg2
      last_url <- alt_url
    } else {
      .log("WARN", "DOE ASCR: pagina inicial inacessivel. Retornando vazio.")
      return(list(records = tibble::tibble(), pages_visited = pages_visited, last_url = last_url))
    }
  }

  # Extract funding opportunities from page blocks
  # ASCR page structure: headings for FY2026 etc., links to FOA PDFs or pages
  candidates <- tryCatch({
    blocks <- rvest::html_elements(pg$html, "article, .field--item, .view-content, .content, main, .region-content")
    # More targeted: find all links that look like FOAs
    links <- rvest::html_elements(pg$html, "a[href]")
    hrefs <- rvest::html_attr(links, "href")
    texts <- rvest::html_text(links, trim = TRUE)
    # Filter for funding opportunity signals
    keep_idx <- grepl("funding|opportunity|FOA|solicitation|continuation|FY2026|ASCR|HPC|quantum|computational|AI for science", texts, ignore.case = TRUE) |
                grepl("funding|opportunity|FOA|solicitation", hrefs, ignore.case = TRUE)
    if (any(keep_idx, na.rm = TRUE)) {
      links <- links[keep_idx]
      hrefs <- hrefs[keep_idx]
      texts <- texts[keep_idx]
    }
    # Also include headings as candidates
    headings <- rvest::html_elements(pg$html, "h1, h2, h3, h4")
    heading_texts <- rvest::html_text(headings, trim = TRUE)
    # Combine
    tibble_list <- list()
    for (i in seq_along(links)) {
      href <- hrefs[[i]]
      title <- texts[[i]]
      if (is.na(title) || nchar(trimws(title)) < 10) next
      # Skip nav/footer boilerplate
      if (grepl("home|contact|privacy|accessibility|search", title, ignore.case = TRUE) && nchar(title) < 30) next
      abs_url <- resolve_url(base_url, href)
      # Find container text for context
      parent <- tryCatch(rvest::html_parent(links[[i]]), error = function(e) NULL)
      ctx <- tryCatch(safe_html_text(parent), error = function(e) "")
      # Must have funding signal
      if (!text_has_funding_signal(c(title, ctx))[[1]] && !grepl("funding|opportunity|FOA", title, ignore.case = TRUE)) {
        # Allow if it's clearly a FOA link (contains .pdf or funding)
        if (!grepl("\\.pdf|funding|solicitation", href, ignore.case = TRUE)) next
      }
      tibble_list[[length(tibble_list) + 1]] <- tibble::tibble(
        title = stringr::str_squish(title),
        summary = stringr::str_squish(paste(title, ctx, collapse = " ") |> stringr::str_sub(1, 700)),
        detail_url = abs_url,
        pdf_url = if (grepl("\\.pdf", href, ignore.case = TRUE)) abs_url else NA_character_,
        source_text = ctx
      )
    }
    if (length(tibble_list) > 0) dplyr::bind_rows(tibble_list) else tibble::tibble()
  }, error = function(e) tibble::tibble())

  # Fallback to generic extractor if custom found nothing
  if (nrow(candidates) == 0) {
    gen <- tryCatch(extract_listing_candidates(pg$html, base_url, source_row), error = function(e) tibble::tibble())
    if (nrow(gen) > 0) {
      candidates <- gen |>
        dplyr::transmute(title = title, summary = summary, detail_url = detail_url, pdf_url = pdf_url, source_text = source_text) |>
        dplyr::filter(grepl("funding|opportunity|FOA|ASCR|HPC|quantum", title, ignore.case = TRUE) | !is.na(pdf_url))
    }
  }

  # If still empty, the page itself may BE the opportunity (single FOA - FY2026 Continuation)
  if (nrow(candidates) == 0) {
    page_title <- extract_meta_title(pg$html)
    page_summary <- extract_page_summary(pg$html, max_chars = 1200)
    full_text <- tryCatch({
      nodes <- rvest::html_elements(pg$html, "main p, article p, .field--item p, .content p, body p")
      txts <- vapply(nodes, safe_html_text, character(1))
      paste(txts[!is.na(txts)], collapse = "\n")
    }, error = function(e) page_summary %||% "")
    # Check if page is indeed a funding opportunity
    if (grepl("Funding Opportunity|FOA|FY2026|ASCR|Advanced Scientific Computing", paste(page_title, page_summary, full_text), ignore.case = TRUE)) {
      candidates <- tibble::tibble(
        title = page_title %||% "DOE ASCR Funding Opportunities - FY2026 Continuation of Solicitation",
        summary = page_summary %||% "DOE Office of Science ASCR Funding Opportunities including FY2026 Continuation of Solicitation for HPC, quantum computing, computational science and AI for Science.",
        detail_url = base_url,
        pdf_url = tryCatch(extract_pdf_links(pg$html, base_url)[[1]], error = function(e) NA_character_),
        source_text = full_text
      )
    }
  }

  if (nrow(candidates) == 0) {
    .log("WARN", "DOE ASCR: nenhuma oportunidade detectada na pagina. Retornando vazio.")
    return(list(records = tibble::tibble(), pages_visited = pages_visited, last_url = last_url))
  }

  # Deduplicate and limit
  candidates <- candidates |>
    dplyr::mutate(canonical = dplyr::coalesce(detail_url, pdf_url, title)) |>
    dplyr::distinct(canonical, .keep_all = TRUE) |>
    dplyr::select(-canonical)
  if (nrow(candidates) > max_records) candidates <- candidates[seq_len(max_records), ]

  .log("INFO", sprintf("DOE ASCR: %d candidatos extraidos.", nrow(candidates)))

  records <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
    one <- candidates[i, ]
    # Fetch detail if needed for deadline/value
    bundle <- list(detail_title = one$title[[1]], detail_summary = one$summary[[1]], full_text = one$source_text[[1]], pdf_url = one$pdf_url[[1]])
    if (!is.na(one$detail_url[[1]]) && nzchar(one$detail_url[[1]]) && !identical(one$detail_url[[1]], base_url)) {
      # Only fetch if detail is different page and looks like FOA
      if (grepl("energy\\.gov|science\\.osti\\.gov|osti\\.gov", one$detail_url[[1]])) {
        b <- tryCatch(extract_detail_bundle(detail_url = one$detail_url[[1]], page_url = base_url, log_path = log_path), error = function(e) bundle)
        if (!is.na(b$detail_title) && nzchar(b$detail_title)) bundle <- b
      }
    }
    # Also try to get PDF text if present
    if (!is.na(bundle$pdf_url) && nzchar(bundle$pdf_url)) {
      # Already handled inside extract_detail_bundle
    }

    rec_title <- pick_first_nonempty(bundle$detail_title, one$title[[1]])
    rec_summary <- pick_first_nonempty(bundle$detail_summary, one$summary[[1]])
    rec_full <- pick_first_nonempty(bundle$full_text, one$source_text[[1]])

    raw <- paste(rec_title, rec_summary, rec_full, collapse = " ")
    # Extract USD dates - look for close/deadline near date
    dates <- extract_dates_from_text(raw)
    deadline <- NA_character_
    if (length(dates) > 0) {
      # Prefer date near deadline keywords
      if (grepl("close|deadline|due date|closing date", raw, ignore.case = TRUE)) {
        # Take the latest future date
        future <- dates[dates >= Sys.Date() - 30]
        if (length(future) > 0) deadline <- as.character(max(future, na.rm = TRUE))
        else deadline <- as.character(max(dates, na.rm = TRUE))
      } else {
        # For FY2026 Continuation, known date is 2026-09-30
        if (grepl("FY2026|Continuation of Solicitation", raw, ignore.case = TRUE)) {
          deadline <- "2026-09-30"
        } else {
          deadline <- as.character(max(dates, na.rm = TRUE))
        }
      }
    }
    # Explicit FY2026 fallback
    if ((is.na(deadline) || !nzchar(deadline)) && grepl("FY2026", rec_title, ignore.case = TRUE)) {
      deadline <- "2026-09-30"
    }

    money <- parse_money_text(raw)
    hash_dedup <- digest::digest(paste0(rec_title, one$detail_url[[1]] %||% base_url), algo = "xxhash64")
    area <- if (grepl("quantum", raw, ignore.case = TRUE)) "Quantum Computing; HPC; Advanced Computing"
            else if (grepl("HPC|high performance", raw, ignore.case = TRUE)) "High Performance Computing; Computational Science"
            else if (grepl("AI for science|artificial intelligence", raw, ignore.case = TRUE)) "AI for Science; Computational Science"
            else "Advanced Scientific Computing; HPC; Quantum"

    tibble::tibble(
      id_registro = sprintf("doe_ascr_%s", substr(hash_dedup, 1, 16)),
      entidade = "DOE ASCR",
      pais_origem = "Estados Unidos",
      titulo = rec_title,
      subtitulo = NA_character_,
      descricao_resumida = substr(rec_summary %||% rec_full, 1, 500),
      descricao_completa = rec_full,
      tipo_oportunidade = "grant",
      modalidade = NA_character_,
      area_tematica = area,
      palavras_chave = "HPC; quantum computing; computational science; AI for science; advanced computing",
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "U.S. Department of Energy - Office of Science",
      valor_financiado = money$value,
      moeda = money$currency %||% "USD",
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = deadline,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = deadline, text = rec_title)[[1]],
      link_origem = base_url,
      link_detalhe = one$detail_url[[1]] %||% base_url,
      link_documento_pdf = bundle$pdf_url,
      idioma = "en",
      localidade = NA_character_,
      observacoes = "DOE ASCR Funding Opportunities. Inclui FY2026 Continuation of Solicitation (fecha 30/09/2026). Parcerias potenciais com DOE National Laboratories.",
      texto_bruto = paste(collapse_non_empty(rec_title, rec_full), collapse = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "doe_ascr",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash_dedup,
      campos_inferidos_ia = NA_character_
    )
  })

  df <- finalize_records(records, fonte_oficial = "doe_ascr")
  if (nrow(df) == 0 && nrow(records) > 0) {
    # For DOE ASCR, FY2026 items may be filtered by current year heuristic (but should pass due to 2026)
    # Keep raw with dedupe as fallback
    .log("WARN", "DOE ASCR: finalize filtrou todos. Retornando com deduplicacao simples.")
    df <- dedupe_records(records)
  }
  .log("INFO", sprintf("DOE ASCR: %d registros finais coletados.", nrow(df)))
  list(records = df, pages_visited = pages_visited, last_url = last_url)
}
register_collector("doe_ascr", collect_doe_ascr, "DOE ASCR: HTML scraping + OSTI API fallback (HPC, Quantum, AI)")

# ---------------------------------------------------------------------------
#  NSF International Collaboration (OISE)
# ---------------------------------------------------------------------------
collect_nsf_international <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[NSF_INT][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta NSF International Collaboration (OISE).")
  try(log_progress("Iniciando coleta NSF International", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://www.nsf.gov/oise/international-collaborations"
  res <- collect_listing_with_pagination(
    source_row = source_row,
    first_url = base_url,
    max_pages = max_pages,
    max_records = max_records,
    use_ai = FALSE,
    log_path = log_path
  )
  # Post-process to ensure US metadata
  if (!is.null(res$records) && nrow(res$records) > 0) {
    res$records <- res$records |>
      dplyr::mutate(
        entidade = "NSF OISE",
        pais_origem = "Estados Unidos",
        instituicao_financiadora = "National Science Foundation - Office of International Science and Engineering",
        area_tematica = dplyr::coalesce(area_tematica, "International Collaboration; Global Research"),
        palavras_chave = dplyr::coalesce(palavras_chave, "international collaboration; global research; NSF OISE"),
        moeda = dplyr::coalesce(moeda, "USD"),
        idioma = "en",
        fonte_oficial = "nsf_international",
        id_registro = paste0("nsf_international_", substr(hash_deduplicacao, 1, 16))
      )
    .log("INFO", sprintf("NSF International: %d registros finais.", nrow(res$records)))
  } else {
    .log("WARN", "NSF International: nenhum registro via listing. Tentando generico.")
    pg <- safe_request_page_us(base_url, log_path = log_path)
    if (isTRUE(pg$ok) && !is.null(pg$html)) {
      rec <- extract_core_record(
        source_row = source_row,
        input_title = extract_meta_title(pg$html) %||% "NSF International Collaborations - OISE",
        input_summary = extract_page_summary(pg$html),
        input_full_text = extract_page_summary(pg$html, max_chars = 3000),
        page_url = base_url,
        detail_url = NA_character_,
        pdf_url = NA_character_,
        page_no = 1L
      )
      rec$entidade <- "NSF OISE"
      rec$pais_origem <- "Estados Unidos"
      rec$fonte_oficial <- "nsf_international"
      rec$idioma <- "en"
      rec$moeda <- "USD"
      rec$hash_deduplicacao <- digest::digest(paste0(rec$titulo, base_url), algo = "xxhash64")
      rec$id_registro <- paste0("nsf_international_", substr(rec$hash_deduplicacao, 1, 16))
      res <- list(records = finalize_records(rec, fonte_oficial = "nsf_international"), pages_visited = 1L, last_url = base_url)
    }
  }
  res
}
register_collector("nsf_international", collect_nsf_international, "NSF OISE: HTML scraping International Collaborations")

# ---------------------------------------------------------------------------
#  NSF QISE International Supplements (DCL)
# ---------------------------------------------------------------------------
collect_nsf_qise <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[NSF_QISE][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta NSF QISE International Supplements.")
  try(log_progress("Iniciando coleta NSF QISE", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://www.nsf.gov/funding/opportunities/dcl-international-collaboration-supplements-quantum-information"
  pg <- safe_request_page_us(base_url, log_path = log_path)
  pages_visited <- 1L

  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", "NSF QISE: pagina inacessivel.")
    return(list(records = tibble::tibble(), pages_visited = pages_visited, last_url = base_url))
  }

  title <- extract_meta_title(pg$html)
  summary <- extract_page_summary(pg$html, max_chars = 1200)
  full_text <- tryCatch({
    nodes <- rvest::html_elements(pg$html, "main p, article p, .content p, body p")
    txts <- vapply(nodes, safe_html_text, character(1))
    paste(txts[!is.na(txts)], collapse = "\n")
  }, error = function(e) summary %||% "")

  raw <- paste(title, summary, full_text, collapse = "\n")
  # DCL is supplements to active awards - no fixed deadline, "at any time"
  dates <- extract_dates_from_text(raw)
  deadline <- NA_character_
  if (length(dates) > 0) {
    # Look for supplement deadline
    deadline <- as.character(max(dates, na.rm = TRUE))
  }
  # If DCL says "at any time" or "supplement requests accepted", treat as aberto sem deadline fixa
  status <- if (grepl("at any time|accepted at any time|supplement.*request", raw, ignore.case = TRUE)) "aberto" else classify_status(deadline = deadline, text = title)[[1]]

  hash_dedup <- digest::digest(paste0(title %||% base_url, base_url), algo = "xxhash64")
  rec <- tibble::tibble(
    id_registro = sprintf("nsf_qise_%s", substr(hash_dedup, 1, 16)),
    entidade = "NSF QISE",
    pais_origem = "Estados Unidos",
    titulo = title %||% "NSF DCL: International Collaboration Supplements in Quantum Information Science and Engineering",
    subtitulo = NA_character_,
    descricao_resumida = substr(summary %||% full_text, 1, 500),
    descricao_completa = full_text,
    tipo_oportunidade = "grant",
    modalidade = "supplement",
    area_tematica = "Quantum Information Science and Engineering; QISE; Quantum Computing",
    palavras_chave = "quantum information; QISE; quantum computing; international collaboration; NSF supplement",
    elegibilidade = "Researchers with active NSF awards (supplement). Brazil eligible but not priority.",
    publico_alvo = "NSF awardees",
    nivel_academico = NA_character_,
    instituicao_financiadora = "National Science Foundation",
    valor_financiado = NA_real_,
    moeda = "USD",
    data_publicacao = NA_character_,
    data_abertura = NA_character_,
    data_limite = deadline,
    data_encerramento = NA_character_,
    status_oportunidade = status,
    link_origem = base_url,
    link_detalhe = base_url,
    link_documento_pdf = tryCatch(extract_pdf_links(pg$html, base_url)[[1]], error = function(e) NA_character_),
    idioma = "en",
    localidade = NA_character_,
    observacoes = "Brasil não está entre os prioritários, mas pode ser considerado. Supplements para awards NSF ativos adicionarem dimensão internacional em QISE. Ver DCL para países prioritários.",
    texto_bruto = paste(collapse_non_empty(title, full_text), collapse = "\n\n"),
    pagina_coletada = 1L,
    fonte_oficial = "nsf_qise",
    data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    hash_deduplicacao = hash_dedup,
    campos_inferidos_ia = NA_character_
  )

  df <- finalize_records(rec, fonte_oficial = "nsf_qise")
  if (nrow(df) == 0) df <- dedupe_records(rec)
  .log("INFO", sprintf("NSF QISE: %d registros finais.", nrow(df)))
  list(records = df, pages_visited = pages_visited, last_url = base_url)
}
register_collector("nsf_qise", collect_nsf_qise, "NSF QISE: HTML scraping DCL QISE International Supplements")

# ---------------------------------------------------------------------------
#  NSF CISE - Directorate for Computer & Information Science and Engineering
# ---------------------------------------------------------------------------
collect_nsf_cise <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[NSF_CISE][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta NSF CISE (Computing, AI, HPC).")
  try(log_progress("Iniciando coleta NSF CISE", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://www.nsf.gov/funding/find-by-directorate"
  # NSF funding API (non-public but used by frontend)
  api_urls <- c(
    "https://www.nsf.gov/api/v1/funding/search?directorate=CISE&page=1&pageSize=25",
    "https://www.nsf.gov/funding/api/search?directorate=CISE",
    "https://api.nsf.gov/services/v1/awards.json?keyword=CISE&printFields=id,title,fundsObligatedAmt,awardTitle,date&offset=0"
  )

  api_records <- list()
  for (api_url in api_urls) {
    .log("INFO", sprintf("Tentando NSF API: %s", api_url))
    .scrape_rate_limiter$wait_if_needed(api_url)
    hdrs <- build_scrape_headers()
    req <- httr2::request(api_url) |>
      httr2::req_user_agent(hdrs$`User-Agent`) |>
      httr2::req_headers(`Accept` = "application/json, text/plain, */*") |>
      httr2::req_timeout(15)
    resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
    if (is.null(resp) || httr2::resp_status(resp) >= 400) next
    data <- tryCatch(httr2::resp_body_json(resp, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(data) || length(data) == 0) next
    # Check if response is funding opportunities (not awards)
    items <- NULL
    if (!is.null(data$fundingOpportunities)) items <- data$fundingOpportunities
    else if (!is.null(data$opportunities)) items <- data$opportunities
    else if (!is.null(data$response$docs)) items <- data$response$docs
    else if (!is.null(data$results)) items <- data$results
    if (is.null(items) || length(items) == 0) next
    .log("INFO", sprintf("NSF API CISE retornou %d itens", length(items)))
    for (it in items) {
      if (length(api_records) >= max_records) break
      ttl <- it$title %||% it$name %||% it$awardTitle %||% NA_character_
      if (is.na(ttl) || !nzchar(ttl)) next
      # Filter for CISE relevance
      if (!grepl("comput|AI|software|system|HPC|cyber|information", paste(ttl, it$description %||% "", collapse = " "), ignore.case = TRUE)) next
      desc <- it$description %||% it$ synopsis %||% ttl
      det_url <- it$url %||% it$link %||% sprintf("https://www.nsf.gov/funding/opportunities/%s", it$id %||% "")
      deadline <- it$deadline %||% it$dueDate %||% NA_character_
      dates <- extract_dates_from_text(paste(ttl, desc, deadline))
      dl <- if (length(dates) > 0) as.character(max(dates, na.rm = TRUE)) else tryCatch(as.character(parse_date_safe(deadline)), error = function(e) NA_character_)
      hash <- digest::digest(paste0(ttl, det_url), algo = "xxhash64")
      api_records[[length(api_records) + 1]] <- tibble::tibble(
        id_registro = sprintf("nsf_cise_%s", substr(hash, 1, 16)),
        entidade = "NSF CISE",
        pais_origem = "Estados Unidos",
        titulo = ttl,
        subtitulo = it$directorate %||% "CISE",
        descricao_resumida = substr(desc, 1, 500),
        descricao_completa = desc,
        tipo_oportunidade = "grant",
        modalidade = NA_character_,
        area_tematica = "Computer Science; AI; Cybersecurity; HPC; Information Science",
        palavras_chave = "computing; AI; cybersecurity; HPC; software; systems",
        elegibilidade = NA_character_,
        publico_alvo = NA_character_,
        nivel_academico = NA_character_,
        instituicao_financiadora = "National Science Foundation - CISE",
        valor_financiado = suppressWarnings(as.numeric(it$fundsObligatedAmt %||% NA_character_)),
        moeda = "USD",
        data_publicacao = NA_character_,
        data_abertura = NA_character_,
        data_limite = dl,
        data_encerramento = NA_character_,
        status_oportunidade = classify_status(deadline = dl, text = ttl)[[1]],
        link_origem = base_url,
        link_detalhe = det_url,
        link_documento_pdf = NA_character_,
        idioma = "en",
        localidade = NA_character_,
        observacoes = "NSF CISE: computação, AI, cybersecurity, software, systems, HPC. Oportunidade para identificar PIs/universidades americanas para projetos conjuntos com QuIIN.",
        texto_bruto = paste(collapse_non_empty(ttl, desc), collapse = "\n\n"),
        pagina_coletada = 1L,
        fonte_oficial = "nsf_cise",
        data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        hash_deduplicacao = hash,
        campos_inferidos_ia = NA_character_
      )
    }
    if (length(api_records) > 0) break
  }

  if (length(api_records) > 0) {
    df <- dplyr::bind_rows(api_records) |> finalize_records(fonte_oficial = "nsf_cise")
    if (nrow(df) == 0) df <- dedupe_records(dplyr::bind_rows(api_records))
    .log("INFO", sprintf("NSF CISE API: %d registros finais.", nrow(df)))
    return(list(records = df, pages_visited = 1L, last_url = base_url))
  }

  # Fallback: HTML scraping find-by-directorate filtered for CISE
  .log("INFO", "NSF CISE API falhou. Tentando HTML scraping diretorate CISE.")
  pg <- safe_request_page_us(base_url, log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", "NSF CISE: pagina inacessivel.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = base_url))
  }
  # Find CISE links
  links <- tryCatch(rvest::html_elements(pg$html, "a[href]"), error = function(e) list())
  hrefs <- vapply(links, function(a) rvest::html_attr(a, "href") %||% "", character(1))
  texts <- vapply(links, function(a) safe_html_text(a) %||% "", character(1))
  # Filter for CISE or funding opportunity links
  keep <- grepl("CISE|computer.*information|funding.*opportunit", texts, ignore.case = TRUE) |
          grepl("cise|funding/opportunit", hrefs, ignore.case = TRUE)
  if (!any(keep, na.rm = TRUE)) {
    # Generic fallback to listing pagination
    res <- collect_listing_with_pagination(source_row, base_url, max_pages, max_records, FALSE, log_path)
    if (!is.null(res$records) && nrow(res$records) > 0) {
      res$records <- res$records |>
        dplyr::mutate(entidade = "NSF CISE", pais_origem = "Estados Unidos", instituicao_financiadora = "National Science Foundation - CISE", area_tematica = dplyr::coalesce(area_tematica, "CISE; Computing; AI"), moeda = dplyr::coalesce(moeda, "USD"), idioma = "en", fonte_oficial = "nsf_cise", id_registro = paste0("nsf_cise_", substr(hash_deduplicacao, 1, 16)))
      return(res)
    }
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = base_url))
  }
  candidates <- tibble::tibble(title = texts[keep], href = hrefs[keep]) |>
    dplyr::filter(nchar(title) > 10) |>
    dplyr::mutate(detail_url = vapply(href, function(h) resolve_url(base_url, h), character(1))) |>
    dplyr::distinct(detail_url, .keep_all = TRUE)
  if (nrow(candidates) > max_records) candidates <- candidates[seq_len(max_records), ]

  records <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
    one <- candidates[i, ]
    bundle <- tryCatch(extract_detail_bundle(detail_url = one$detail_url[[1]], page_url = base_url, log_path = log_path), error = function(e) list(detail_title = one$title[[1]], detail_summary = NA_character_, full_text = NA_character_, pdf_url = NA_character_))
    ttl <- pick_first_nonempty(bundle$detail_title, one$title[[1]])
    raw <- paste(ttl, bundle$full_text %||% "", collapse = " ")
    dates <- extract_dates_from_text(raw)
    dl <- if (length(dates) > 0) as.character(max(dates, na.rm = TRUE)) else NA_character_
    hash <- digest::digest(paste0(ttl, one$detail_url[[1]]), algo = "xxhash64")
    tibble::tibble(
      id_registro = sprintf("nsf_cise_%s", substr(hash, 1, 16)),
      entidade = "NSF CISE",
      pais_origem = "Estados Unidos",
      titulo = ttl,
      subtitulo = NA_character_,
      descricao_resumida = substr(bundle$detail_summary %||% raw, 1, 500),
      descricao_completa = bundle$full_text %||% raw,
      tipo_oportunidade = "grant",
      modalidade = NA_character_,
      area_tematica = "CISE; Computing; AI; Cybersecurity; HPC",
      palavras_chave = "computing; AI; cybersecurity; HPC; software",
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "National Science Foundation - CISE",
      valor_financiado = NA_real_,
      moeda = "USD",
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = dl,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = dl, text = ttl)[[1]],
      link_origem = base_url,
      link_detalhe = one$detail_url[[1]],
      link_documento_pdf = bundle$pdf_url,
      idioma = "en",
      localidade = NA_character_,
      observacoes = "NSF CISE funding via directorate page. Para identificar PIs/universidades para projetos conjuntos.",
      texto_bruto = paste(collapse_non_empty(ttl, bundle$full_text), collapse = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "nsf_cise",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash,
      campos_inferidos_ia = NA_character_
    )
  })
  df <- finalize_records(records, fonte_oficial = "nsf_cise")
  if (nrow(df) == 0 && nrow(records) > 0) df <- dedupe_records(records)
  .log("INFO", sprintf("NSF CISE: %d registros finais.", nrow(df)))
  list(records = df, pages_visited = 1L, last_url = base_url)
}
register_collector("nsf_cise", collect_nsf_cise, "NSF CISE: Hybrid API + HTML directorate filtering")

# ---------------------------------------------------------------------------
#  DOE Quantum Genesis Initiative (single-page monitor - no fake if no FOA)
# ---------------------------------------------------------------------------
collect_doe_quantum_genesis <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[DOE_QGENESIS][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta DOE Quantum Genesis Initiative.")
  try(log_progress("Iniciando coleta DOE Quantum Genesis", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://www.energy.gov/science/articles/energy-department-announces-initiative-create-and-deploy-worlds-first"
  pg <- safe_request_page_us(base_url, log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", "DOE Quantum Genesis: pagina inacessivel. Retornando vazio (monitorar futuras FOAs).")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = base_url))
  }
  # Check if page contains actual funding opportunity listing
  links <- tryCatch(rvest::html_elements(pg$html, "a[href*='funding'], a[href*='opportunity'], a[href*='FOA']"), error = function(e) list())
  has_foa <- length(links) > 0 && any(grepl("funding|opportunity|FOA", vapply(links, function(a) safe_html_text(a) %||% "", character(1)), ignore.case = TRUE), na.rm = TRUE)
  # Also check text for solicitation signals
  page_text <- tryCatch(paste(vapply(rvest::html_elements(pg$html, "p"), safe_html_text, character(1)), collapse = " "), error = function(e) "")
  has_foa <- has_foa || grepl("Funding Opportunity Announcement|FOA|solicitation|apply now|deadline.*202", page_text, ignore.case = TRUE)

  if (!has_foa) {
    .log("INFO", "DOE Quantum Genesis: pagina institucional sem FOA ativa detectada. Retornando vazio conforme regra (nao criar registro informativo).")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = base_url))
  }
  # If FOA found, extract as opportunity
  candidates <- tryCatch(extract_listing_candidates(pg$html, base_url, source_row), error = function(e) tibble::tibble())
  if (nrow(candidates) == 0) {
    title <- extract_meta_title(pg$html)
    candidates <- tibble::tibble(title = title, summary = extract_page_summary(pg$html), detail_url = base_url, pdf_url = NA_character_, source_text = page_text)
  }
  if (nrow(candidates) > max_records) candidates <- candidates[seq_len(max_records), ]
  records <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
    one <- candidates[i, ]
    bundle <- tryCatch(extract_detail_bundle(detail_url = one$detail_url[[1]], page_url = base_url, log_path = log_path), error = function(e) list(detail_title = one$title[[1]], detail_summary = one$summary[[1]], full_text = one$source_text[[1]], pdf_url = one$pdf_url[[1]]))
    ttl <- pick_first_nonempty(bundle$detail_title, one$title[[1]])
    hash <- digest::digest(paste0(ttl, one$detail_url[[1]]), algo = "xxhash64")
    raw <- paste(ttl, bundle$full_text %||% "", collapse = " ")
    dates <- extract_dates_from_text(raw)
    dl <- if (length(dates) > 0) as.character(max(dates, na.rm = TRUE)) else NA_character_
    tibble::tibble(
      id_registro = sprintf("doe_quantum_genesis_%s", substr(hash, 1, 16)),
      entidade = "DOE Quantum Genesis",
      pais_origem = "Estados Unidos",
      titulo = ttl,
      subtitulo = NA_character_,
      descricao_resumida = substr(bundle$detail_summary %||% one$summary[[1]], 1, 500),
      descricao_completa = bundle$full_text %||% one$source_text[[1]],
      tipo_oportunidade = "grant",
      modalidade = NA_character_,
      area_tematica = "Quantum Computing; Fault-Tolerant Quantum",
      palavras_chave = "quantum genesis; fault-tolerant quantum; quantum computing; DOE",
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "U.S. Department of Energy",
      valor_financiado = NA_real_,
      moeda = "USD",
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = dl,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = dl, text = ttl)[[1]],
      link_origem = base_url,
      link_detalhe = one$detail_url[[1]],
      link_documento_pdf = bundle$pdf_url,
      idioma = "en",
      localidade = NA_character_,
      observacoes = "DOE Quantum Genesis Initiative - fault-tolerant quantum computer até 2028. Anunciada jun/2026.",
      texto_bruto = paste(collapse_non_empty(ttl, bundle$full_text), collapse = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "doe_quantum_genesis",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash,
      campos_inferidos_ia = NA_character_
    )
  })
  df <- finalize_records(records, fonte_oficial = "doe_quantum_genesis")
  if (nrow(df) == 0 && nrow(records) > 0) df <- dedupe_records(records)
  .log("INFO", sprintf("DOE Quantum Genesis: %d registros finais.", nrow(df)))
  list(records = df, pages_visited = 1L, last_url = base_url)
}
register_collector("doe_quantum_genesis", collect_doe_quantum_genesis, "DOE Quantum Genesis: single-page monitor (no fake if no FOA)")

# ---------------------------------------------------------------------------
#  DOE Genesis Mission (single-page monitor - no fake if no FOA)
# ---------------------------------------------------------------------------
collect_doe_genesis <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[DOE_GENESIS][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta DOE Genesis Mission.")
  try(log_progress("Iniciando coleta DOE Genesis", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://www.energy.gov/genesis"
  pg <- safe_request_page_us(base_url, log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", "DOE Genesis: pagina inacessivel. Retornando vazio.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = base_url))
  }
  links <- tryCatch(rvest::html_elements(pg$html, "a[href*='funding'], a[href*='opportunity'], a[href*='FOA'], a[href*='genesis']"), error = function(e) list())
  hrefs <- tryCatch(vapply(links, function(a) rvest::html_attr(a, "href") %||% "", character(1)), error = function(e) character())
  has_foa <- any(grepl("funding|opportunity|FOA|solicitation", hrefs, ignore.case = TRUE), na.rm = TRUE)
  page_text <- tryCatch(paste(vapply(rvest::html_elements(pg$html, "p"), safe_html_text, character(1)), collapse = " "), error = function(e) "")
  has_foa <- has_foa || grepl("Funding Opportunity|FOA|Precedente.*Japão|US\\$1B|Japan.*partnership", page_text, ignore.case = TRUE)

  if (!has_foa) {
    # Check for sub-links that might contain opportunities
    sub_links <- hrefs[grepl("genesis", hrefs, ignore.case = TRUE)]
    sub_links <- unique(vapply(sub_links, function(h) resolve_url(base_url, h), character(1)))
    sub_links <- sub_links[!is.na(sub_links) & nzchar(sub_links) & sub_links != base_url]
    found_foa_sub <- FALSE
    if (length(sub_links) > 0) {
      for (sl in head(sub_links, 3)) {
        spg <- safe_request_page_us(sl, log_path = log_path)
        if (isTRUE(spg$ok) && !is.null(spg$html)) {
          stxt <- tryCatch(paste(vapply(rvest::html_elements(spg$html, "p"), safe_html_text, character(1)), collapse = " "), error = function(e) "")
          if (grepl("funding|opportunity|FOA", stxt, ignore.case = TRUE)) { found_foa_sub <- TRUE; break }
        }
      }
    }
    if (!found_foa_sub) {
      .log("INFO", "DOE Genesis: pagina institucional sem FOA ativa. Retornando vazio conforme regra.")
      return(list(records = tibble::tibble(), pages_visited = 1L, last_url = base_url))
    }
  }
  candidates <- tryCatch(extract_listing_candidates(pg$html, base_url, source_row), error = function(e) tibble::tibble())
  if (nrow(candidates) == 0) {
    title <- extract_meta_title(pg$html)
    candidates <- tibble::tibble(title = title, summary = extract_page_summary(pg$html), detail_url = base_url, pdf_url = NA_character_, source_text = page_text)
  }
  if (nrow(candidates) > max_records) candidates <- candidates[seq_len(max_records), ]
  records <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
    one <- candidates[i, ]
    bundle <- tryCatch(extract_detail_bundle(detail_url = one$detail_url[[1]], page_url = base_url, log_path = log_path), error = function(e) list(detail_title = one$title[[1]], detail_summary = one$summary[[1]], full_text = one$source_text[[1]], pdf_url = one$pdf_url[[1]]))
    ttl <- pick_first_nonempty(bundle$detail_title, one$title[[1]])
    hash <- digest::digest(paste0(ttl, one$detail_url[[1]]), algo = "xxhash64")
    raw <- paste(ttl, bundle$full_text %||% "", collapse = " ")
    dates <- extract_dates_from_text(raw)
    dl <- if (length(dates) > 0) as.character(max(dates, na.rm = TRUE)) else NA_character_
    tibble::tibble(
      id_registro = sprintf("doe_genesis_%s", substr(hash, 1, 16)),
      entidade = "DOE Genesis",
      pais_origem = "Estados Unidos",
      titulo = ttl,
      subtitulo = NA_character_,
      descricao_resumida = substr(bundle$detail_summary %||% one$summary[[1]], 1, 500),
      descricao_completa = bundle$full_text %||% one$source_text[[1]],
      tipo_oportunidade = "grant",
      modalidade = NA_character_,
      area_tematica = "AI; Advanced Computing; Quantum; Scientific Discovery",
      palavras_chave = "genesis mission; AI; advanced computing; quantum; DOE",
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "U.S. Department of Energy",
      valor_financiado = NA_real_,
      moeda = "USD",
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = dl,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = dl, text = ttl)[[1]],
      link_origem = base_url,
      link_detalhe = one$detail_url[[1]],
      link_documento_pdf = bundle$pdf_url,
      idioma = "en",
      localidade = NA_character_,
      observacoes = "DOE Genesis Mission: AI + advanced computing + quantum. Precedente parceria EUA-Japão US$1B.",
      texto_bruto = paste(collapse_non_empty(ttl, bundle$full_text), collapse = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "doe_genesis",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash,
      campos_inferidos_ia = NA_character_
    )
  })
  df <- finalize_records(records, fonte_oficial = "doe_genesis")
  if (nrow(df) == 0 && nrow(records) > 0) df <- dedupe_records(records)
  .log("INFO", sprintf("DOE Genesis: %d registros finais.", nrow(df)))
  list(records = df, pages_visited = 1L, last_url = base_url)
}
register_collector("doe_genesis", collect_doe_genesis, "DOE Genesis: single-page monitor (no fake if no FOA)")

# ---------------------------------------------------------------------------
#  NSF NQNI - National Quantum Nanotechnology Infrastructure (nsf26-505)
# ---------------------------------------------------------------------------
collect_nsf_nqni <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[NSF_NQNI][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta NSF NQNI (nsf26-505).")
  try(log_progress("Iniciando coleta NSF NQNI", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://www.nsf.gov/funding/opportunities/nqni-national-quantum-nanotechnology-infrastructure/nsf26-505/solicitation"
  pg <- safe_request_page_us(base_url, log_path = log_path)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", "NSF NQNI: pagina inacessivel.")
    return(list(records = tibble::tibble(), pages_visited = 1L, last_url = base_url))
  }
  title <- extract_meta_title(pg$html) %||% "NSF NQNI - National Quantum Nanotechnology Infrastructure (nsf26-505)"
  summary <- extract_page_summary(pg$html, max_chars = 1200)
  full_text <- tryCatch({
    nodes <- rvest::html_elements(pg$html, "main p, article p, .content p, .field--item p, body p")
    txts <- vapply(nodes, safe_html_text, character(1))
    paste(txts[!is.na(txts)], collapse = "\n")
  }, error = function(e) summary %||% "")

  # Try to extract budget and deadline from text
  # Look for US$100M and deadline patterns
  raw <- paste(title, summary, full_text, collapse = "\n")
  # Try PDF link for nsf26-505
  pdf_links <- tryCatch(extract_pdf_links(pg$html, base_url), error = function(e) character())
  nqni_pdf <- pdf_links[grepl("nsf26-505|nqni", pdf_links, ignore.case = TRUE)]
  if (length(nqni_pdf) == 0) nqni_pdf <- pdf_links[1]
  pdf_text <- NA_character_
  if (length(nqni_pdf) > 0 && !is.na(nqni_pdf[[1]])) {
    pdf_text <- tryCatch(extract_text_from_pdf(nqni_pdf[[1]], log_path = log_path), error = function(e) NA_character_)
    if (!is.na(pdf_text) && nzchar(pdf_text)) {
      full_text <- paste(full_text, pdf_text, sep = "\n\n")
      raw <- paste(raw, pdf_text, collapse = "\n")
    }
  }
  dates <- extract_dates_from_text(raw)
  deadline <- NA_character_
  if (length(dates) > 0) {
    # Prefer dates near deadline/due date keywords
    # Find date closest to deadline language
    lines <- strsplit(raw, "\n")[[1]]
    for (ln in lines) {
      if (grepl("deadline|due date|closing date|full proposal|letter of intent", ln, ignore.case = TRUE)) {
        d2 <- extract_dates_from_text(ln)
        if (length(d2) > 0 && any(!is.na(d2))) {
          deadline <- as.character(max(d2, na.rm = TRUE))
          break
        }
      }
    }
    if (is.na(deadline)) deadline <- as.character(max(dates, na.rm = TRUE))
  }
  money <- parse_money_text(raw)
  # Override if not found but known budget is 100M
  if (is.na(money$value) || money$value < 1e6) {
    if (grepl("100M|100 million|\\$100,000,000", raw, ignore.case = TRUE)) {
      money$value <- 100000000
      money$currency <- "USD"
    }
  }

  hash_dedup <- digest::digest(paste0(title, base_url), algo = "xxhash64")
  rec <- tibble::tibble(
    id_registro = sprintf("nsf_nqni_%s", substr(hash_dedup, 1, 16)),
    entidade = "NSF NQNI",
    pais_origem = "Estados Unidos",
    titulo = title,
    subtitulo = "nsf26-505",
    descricao_resumida = substr(summary %||% full_text, 1, 500),
    descricao_completa = full_text,
    tipo_oportunidade = "grant",
    modalidade = "infrastructure",
    area_tematica = "Quantum Nanotechnology Infrastructure; Quantum; Nanotechnology",
    palavras_chave = "quantum nanotechnology; NQNI; infrastructure; quantum; nsf26-505",
    elegibilidade = "US universities and institutions (infrastructure). Identificar universidades receptoras como parceiros potenciais.",
    publico_alvo = "US universities",
    nivel_academico = NA_character_,
    instituicao_financiadora = "National Science Foundation",
    valor_financiado = money$value,
    moeda = money$currency %||% "USD",
    data_publicacao = NA_character_,
    data_abertura = NA_character_,
    data_limite = deadline,
    data_encerramento = NA_character_,
    status_oportunidade = classify_status(deadline = deadline, text = title)[[1]],
    link_origem = base_url,
    link_detalhe = base_url,
    link_documento_pdf = if (length(nqni_pdf) > 0) nqni_pdf[[1]] else NA_character_,
    idioma = "en",
    localidade = NA_character_,
    observacoes = "Rede nacional de infraestrutura quântica até US$100M (nsf26-505). Identificar universidades receptoras da infraestrutura como parceiros potenciais.",
    texto_bruto = paste(collapse_non_empty(title, full_text), collapse = "\n\n"),
    pagina_coletada = 1L,
    fonte_oficial = "nsf_nqni",
    data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    hash_deduplicacao = hash_dedup,
    campos_inferidos_ia = NA_character_
  )
  df <- finalize_records(rec, fonte_oficial = "nsf_nqni")
  if (nrow(df) == 0) df <- dedupe_records(rec)
  .log("INFO", sprintf("NSF NQNI: %d registros finais.", nrow(df)))
  list(records = df, pages_visited = 1L, last_url = base_url)
}
register_collector("nsf_nqni", collect_nsf_nqni, "NSF NQNI: solicitation + PDF parsing (nsf26-505, US$100M)")

# ---------------------------------------------------------------------------
#  DARPA Quantum Benchmarking Initiative (QBI) - Playwright Stealth
# ---------------------------------------------------------------------------
collect_darpa_quantum_benchmarking <- function(source_row, max_pages, max_records, use_ai, log_path) {
  .log <- function(level, msg) {
    if (!is.null(log_path)) log_write(log_path, level, msg)
    message(sprintf("[DARPA_QBI][%s] %s", level, msg))
  }
  .log("INFO", "Iniciando coleta DARPA Quantum Benchmarking Initiative.")
  try(log_progress("Iniciando coleta DARPA QBI", "Scraping"), silent = TRUE)

  base_url <- source_row$url_oportunidades[[1]] %||% "https://www.darpa.mil/research/programs/quantum-benchmarking-initiative"
  pg <- safe_request_page_us(base_url, log_path = log_path)
  pages_visited <- 1L
  last_url <- base_url

  # If blocked, try Playwright explicitly (safe_request_page already does cascade, but log)
  if (!isTRUE(pg$ok) || is.null(pg$html)) {
    .log("WARN", "DARPA QBI: pagina bloqueada/inacessivel via httr2. Tentando Playwright Stealth explicito.")
    pg2 <- safe_request_page_playwright(base_url, log_path = log_path)
    if (isTRUE(pg2$ok)) {
      pg <- pg2
    } else {
      # Try alternative DARPA URL pattern
      alt_url <- "https://www.darpa.mil/program/quantum-benchmarking-initiative"
      pg3 <- safe_request_page_us(alt_url, log_path = log_path)
      if (isTRUE(pg3$ok)) {
        pg <- pg3
        last_url <- alt_url
      } else {
        .log("WARN", "DARPA QBI: todas as tentativas falharam (WAF bloqueou). Retornando vazio.")
        return(list(records = tibble::tibble(), pages_visited = pages_visited, last_url = last_url))
      }
    }
  }

  title <- extract_meta_title(pg$html) %||% "DARPA Quantum Benchmarking Initiative"
  summary <- extract_page_summary(pg$html, max_chars = 1200)
  full_text <- tryCatch({
    nodes <- rvest::html_elements(pg$html, "main p, article p, .content p, .program-description p, body p")
    txts <- vapply(nodes, safe_html_text, character(1))
    paste(txts[!is.na(txts)], collapse = "\n")
  }, error = function(e) summary %||% "")

  # DARPA QBI may list performer teams or BAA links - try to extract those as separate records
  links <- tryCatch(rvest::html_elements(pg$html, "a[href]"), error = function(e) list())
  hrefs <- tryCatch(vapply(links, function(a) rvest::html_attr(a, "href") %||% "", character(1)), error = function(e) character())
  texts <- tryCatch(vapply(links, function(a) safe_html_text(a) %||% "", character(1)), error = function(e) character())
  # Filter for program-relevant links (performers, BAA, solicitation, teams)
  keep <- grepl("quantum|benchmarking|BAA|solicitation|performer|team|university|company", texts, ignore.case = TRUE) |
          grepl("quantum|benchmarking|BAA", hrefs, ignore.case = TRUE)
  candidates <- tibble::tibble()
  if (any(keep, na.rm = TRUE) && sum(keep, na.rm = TRUE) > 1) {
    # Create candidates for performer/team links but keep main page as primary
    # Deduplicate
    cand_links <- unique(vapply(which(keep), function(i) resolve_url(base_url, hrefs[[i]]), character(1)))
    cand_links <- cand_links[!is.na(cand_links) & nzchar(cand_links)]
    # Limit to first few
    cand_links <- head(cand_links, min(5, max_records - 1))
    # Add main page as first candidate
    candidates <- tibble::tibble(
      title = c(title, texts[keep][seq_along(cand_links)]),
      summary = c(summary, rep(page_text <- paste(full_text, collapse = " ") |> stringr::str_sub(1, 700), length(cand_links))),
      detail_url = c(base_url, cand_links),
      source_text = c(full_text, rep(full_text, length(cand_links)))
    )
  }

  if (nrow(candidates) == 0) {
    # Single record from main page
    raw <- paste(title, summary, full_text, collapse = "\n")
    dates <- extract_dates_from_text(raw)
    dl <- if (length(dates) > 0) as.character(max(dates, na.rm = TRUE)) else NA_character_
    hash <- digest::digest(paste0(title, base_url), algo = "xxhash64")
    rec <- tibble::tibble(
      id_registro = sprintf("darpa_qbi_%s", substr(hash, 1, 16)),
      entidade = "DARPA QBI",
      pais_origem = "Estados Unidos",
      titulo = title,
      subtitulo = NA_character_,
      descricao_resumida = substr(summary %||% full_text, 1, 500),
      descricao_completa = full_text,
      tipo_oportunidade = "grant",
      modalidade = "program",
      area_tematica = "Quantum Benchmarking; Quantum Computing Architecture",
      palavras_chave = "quantum benchmarking; quantum computing; DARPA; architecture evaluation",
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "Defense Advanced Research Projects Agency (DARPA)",
      valor_financiado = NA_real_,
      moeda = "USD",
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = dl,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = dl, text = title)[[1]],
      link_origem = base_url,
      link_detalhe = base_url,
      link_documento_pdf = tryCatch(extract_pdf_links(pg$html, base_url)[[1]], error = function(e) NA_character_),
      idioma = "en",
      localidade = NA_character_,
      observacoes = "DARPA Quantum Benchmarking Initiative: frontier tech evaluation of quantum computing architectures. Para identificar empresas e pesquisadores americanos avançados.",
      texto_bruto = paste(collapse_non_empty(title, full_text), collapse = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "darpa_quantum_benchmarking",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash,
      campos_inferidos_ia = NA_character_
    )
    df <- finalize_records(rec, fonte_oficial = "darpa_quantum_benchmarking")
    if (nrow(df) == 0) df <- dedupe_records(rec)
    .log("INFO", sprintf("DARPA QBI: %d registros finais.", nrow(df)))
    return(list(records = df, pages_visited = pages_visited, last_url = last_url))
  }

  if (nrow(candidates) > max_records) candidates <- candidates[seq_len(max_records), ]
  records <- purrr::map_dfr(seq_len(nrow(candidates)), function(i) {
    one <- candidates[i, ]
    # For main page vs sub-links, try detail fetch for sub-links
    bundle <- list(detail_title = one$title[[1]], detail_summary = one$summary[[1]], full_text = one$source_text[[1]], pdf_url = NA_character_)
    if (!identical(one$detail_url[[1]], base_url) && !is.na(one$detail_url[[1]])) {
      b <- tryCatch(extract_detail_bundle(detail_url = one$detail_url[[1]], page_url = base_url, log_path = log_path), error = function(e) bundle)
      if (!is.na(b$detail_title) && nzchar(b$detail_title)) bundle <- b
    }
    ttl <- pick_first_nonempty(bundle$detail_title, one$title[[1]])
    raw2 <- paste(ttl, bundle$full_text %||% "", collapse = " ")
    dates2 <- extract_dates_from_text(raw2)
    dl2 <- if (length(dates2) > 0) as.character(max(dates2, na.rm = TRUE)) else NA_character_
    hash2 <- digest::digest(paste0(ttl, one$detail_url[[1]]), algo = "xxhash64")
    tibble::tibble(
      id_registro = sprintf("darpa_qbi_%s", substr(hash2, 1, 16)),
      entidade = "DARPA QBI",
      pais_origem = "Estados Unidos",
      titulo = ttl,
      subtitulo = NA_character_,
      descricao_resumida = substr(bundle$detail_summary %||% one$summary[[1]], 1, 500),
      descricao_completa = bundle$full_text %||% one$source_text[[1]],
      tipo_oportunidade = "grant",
      modalidade = "program",
      area_tematica = "Quantum Benchmarking; Quantum Computing",
      palavras_chave = "quantum benchmarking; DARPA QBI; quantum architecture",
      elegibilidade = NA_character_,
      publico_alvo = NA_character_,
      nivel_academico = NA_character_,
      instituicao_financiadora = "DARPA",
      valor_financiado = NA_real_,
      moeda = "USD",
      data_publicacao = NA_character_,
      data_abertura = NA_character_,
      data_limite = dl2,
      data_encerramento = NA_character_,
      status_oportunidade = classify_status(deadline = dl2, text = ttl)[[1]],
      link_origem = base_url,
      link_detalhe = one$detail_url[[1]],
      link_documento_pdf = bundle$pdf_url,
      idioma = "en",
      localidade = NA_character_,
      observacoes = "DARPA QBI program page.",
      texto_bruto = paste(collapse_non_empty(ttl, bundle$full_text), collapse = "\n\n"),
      pagina_coletada = 1L,
      fonte_oficial = "darpa_quantum_benchmarking",
      data_hora_coleta = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      hash_deduplicacao = hash2,
      campos_inferidos_ia = NA_character_
    )
  })
  df <- finalize_records(records, fonte_oficial = "darpa_quantum_benchmarking")
  if (nrow(df) == 0 && nrow(records) > 0) df <- dedupe_records(records)
  .log("INFO", sprintf("DARPA QBI: %d registros finais.", nrow(df)))
  list(records = df, pages_visited = pages_visited, last_url = last_url)
}
register_collector("darpa_quantum_benchmarking", collect_darpa_quantum_benchmarking, "DARPA QBI: HTML scraping with Playwright Stealth")

