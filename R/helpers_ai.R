# Módulo de Integração com o Agente de IA Multi-Provedor

# Recupera configurações de IA do ambiente
get_ai_config <- function() {
  provider <- Sys.getenv("AI_PROVIDER")
  model <- Sys.getenv("AI_MODEL")
  api_key <- Sys.getenv("AI_API_KEY")
  api_url <- Sys.getenv("AI_API_URL")
  
  # Autodetectar provedor se não estiver configurado explicitamente
  if (!nzchar(provider)) {
    if (nzchar(Sys.getenv("BLUESMINDS_API_KEY"))) {
      provider <- "bluesminds"
    } else if (nzchar(Sys.getenv("GEMINI_API_KEY"))) {
      provider <- "gemini"
    } else if (nzchar(Sys.getenv("OPENAI_API_KEY"))) {
      provider <- "openai"
    } else if (nzchar(Sys.getenv("NVIDIA_API_KEY"))) {
      provider <- "nvidia"
    } else if (nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
      provider <- "anthropic"
    } else if (nzchar(Sys.getenv("GROQ_API_KEY"))) {
      provider <- "groq"
    } else if (nzchar(Sys.getenv("OPENROUTER_API_KEY"))) {
      provider <- "openrouter"
    } else if (nzchar(Sys.getenv("DEEPSEEK_API_KEY"))) {
      provider <- "deepseek"
    } else {
      provider <- "bluesminds"
    }
  }
  
  # Fallback para as chaves específicas do provedor se AI_API_KEY não estiver setada
  if (!nzchar(api_key)) {
    if (provider == "bluesminds") {
      api_key <- Sys.getenv("BLUESMINDS_API_KEY")
    } else if (provider == "gemini") {
      api_key <- Sys.getenv("GEMINI_API_KEY")
    } else if (provider == "openai") {
      api_key <- Sys.getenv("OPENAI_API_KEY")
    } else if (provider == "nvidia") {
      api_key <- Sys.getenv("NVIDIA_API_KEY")
    } else if (provider == "anthropic") {
      api_key <- Sys.getenv("ANTHROPIC_API_KEY")
    } else if (provider == "groq") {
      api_key <- Sys.getenv("GROQ_API_KEY")
    } else if (provider == "openrouter") {
      api_key <- Sys.getenv("OPENROUTER_API_KEY")
    } else if (provider == "deepseek") {
      api_key <- Sys.getenv("DEEPSEEK_API_KEY")
    }
  }
  
  if (!nzchar(api_url)) {
    if (provider == "bluesminds") {
      api_url <- "https://api.bluesminds.com/v1/chat/completions"
    } else if (provider == "openai") {
      api_url <- "https://api.openai.com/v1/chat/completions"
    } else if (provider == "nvidia") {
      api_url <- "https://integrate.api.nvidia.com/v1/chat/completions"
    } else if (provider == "anthropic") {
      api_url <- "https://api.anthropic.com/v1/messages"
    } else if (provider == "groq") {
      api_url <- "https://api.groq.com/openai/v1/chat/completions"
    } else if (provider == "openrouter") {
      api_url <- "https://openrouter.ai/api/v1/chat/completions"
    } else if (provider == "deepseek") {
      api_url <- "https://api.deepseek.com/v1/chat/completions"
    }
  }
  
  if (!nzchar(model)) {
    if (provider == "bluesminds") {
      model <- "moonshotai/kimi-k2.6"
    } else if (provider == "gemini") {
      model <- "gemini-1.5-flash"
    } else if (provider == "openai") {
      model <- "gpt-4o-mini"
    } else if (provider == "nvidia") {
      model <- "meta/llama-3.3-70b-instruct"
    } else if (provider == "anthropic") {
      model <- "claude-3-5-haiku-latest"
    } else if (provider == "groq") {
      model <- "llama-3.3-70b-versatile"
    } else if (provider == "openrouter") {
      model <- "deepseek/deepseek-v4-flash"
    } else if (provider == "deepseek") {
      model <- "deepseek-chat"
    }
  }
  
  list(
    provider = provider,
    model = model,
    api_key = api_key,
    api_url = api_url
  )
}

get_ai_batch_config <- function() {
  cfg <- get_ai_config()
  defaults <- list(
    groq = list(batch_size = 8L, delay_between = 6),
    openai = list(batch_size = 5L, delay_between = 2),
    gemini = list(batch_size = 8L, delay_between = 1),
    anthropic = list(batch_size = 3L, delay_between = 3),
    bluesminds = list(batch_size = 5L, delay_between = 2),
    nvidia = list(batch_size = 5L, delay_between = 2),
    openrouter = list(batch_size = 5L, delay_between = 2),
    deepseek = list(batch_size = 5L, delay_between = 2)
  )
  d <- defaults[[cfg$provider]] %||% list(batch_size = 3L, delay_between = 2)
  d$batch_size <- as.integer(Sys.getenv("AI_BATCH_SIZE", as.character(d$batch_size)))
  d$delay_between <- as.numeric(Sys.getenv("AI_DELAY_BETWEEN_BATCHES", as.character(d$delay_between)))
  if (is.na(d$batch_size) || d$batch_size <= 0L) d$batch_size <- 3L
  if (is.na(d$delay_between) || d$delay_between < 0) d$delay_between <- 2
  d
}


# --- Fallback entre Provedores IA ---

.FALLBACK_ORDER <- c("groq", "openai", "gemini", "anthropic", "nvidia", 
                      "deepseek", "openrouter", "bluesminds")
.KEY_ENV_MAP <- c(
  groq = "GROQ_API_KEY", openai = "OPENAI_API_KEY", gemini = "GEMINI_API_KEY",
  anthropic = "ANTHROPIC_API_KEY", nvidia = "NVIDIA_API_KEY", deepseek = "DEEPSEEK_API_KEY",
  openrouter = "OPENROUTER_API_KEY", bluesminds = "BLUESMINDS_API_KEY"
)

build_ai_fallback_chain <- function() {
  primary <- Sys.getenv("AI_PROVIDER")
  chain <- character()
  if (nzchar(primary) && primary %in% .FALLBACK_ORDER) {
    chain <- primary
  }
  for (p in .FALLBACK_ORDER) {
    if (p %in% chain) next
    key_env <- .KEY_ENV_MAP[[p]]
    if (nzchar(Sys.getenv(key_env))) {
      chain <- c(chain, p)
    }
  }
  chain
}

get_ai_config_for <- function(provider) {
  old_provider <- Sys.getenv("AI_PROVIDER", unset = "")
  Sys.setenv(AI_PROVIDER = provider)
  cfg <- get_ai_config()
  if (nzchar(old_provider)) {
    Sys.setenv(AI_PROVIDER = old_provider)
  } else {
    Sys.unsetenv("AI_PROVIDER")
  }
  cfg
}

# Circuit breaker
.ai_failures <- new.env(parent = emptyenv())

record_ai_failure <- function(provider) {
  key <- paste0(provider, "_failures")
  count <- get0(key, envir = .ai_failures, inherits = FALSE) %||% 0L
  assign(key, count + 1L, envir = .ai_failures)
  if (count + 1L >= 3L) {
    assign(paste0(provider, "_cooldown"), Sys.time() + 300, envir = .ai_failures)
  }
}

is_ai_provider_available <- function(provider) {
  cooldown <- get0(paste0(provider, "_cooldown"), envir = .ai_failures, inherits = FALSE)
  if (!is.null(cooldown) && Sys.time() < cooldown) return(FALSE)
  TRUE
}

reset_ai_provider <- function(provider) {
  try(rm(list = paste0(provider, "_failures"), envir = .ai_failures, inherits = FALSE), silent = TRUE)
  try(rm(list = paste0(provider, "_cooldown"), envir = .ai_failures, inherits = FALSE), silent = TRUE)
}

ai_request_with_fallback <- function(prompt, timeout_sec = 45, retries = 2, log_path = NULL, conn = NULL) {
  chain <- build_ai_fallback_chain()
  chain <- chain[vapply(chain, is_ai_provider_available, logical(1))]
  
  for (provider in chain) {
    cfg <- get_ai_config_for(provider)
    result <- ai_request(prompt, cfg = cfg, timeout_sec = timeout_sec, retries = retries, log_path = log_path, conn = conn)
    if (!is.null(result)) {
      reset_ai_provider(provider)
      return(result)
    }
    record_ai_failure(provider)
    if (!is.null(log_path)) log_write(log_path, "WARN", 
      sprintf("Fallback: provedor %s falhou, tentando próximo", provider))
  }
  NULL
}

ai_available <- function() {
  cfg <- get_ai_config()
  nzchar(cfg$provider) && nzchar(cfg$api_key)
}

ai_healthcheck <- function(timeout_sec = 10) {
  cfg <- get_ai_config()
  if (!nzchar(cfg$provider) || !nzchar(cfg$api_key)) {
    return(list(ok = FALSE, provider = cfg$provider, error = "Chave não configurada"))
  }

  test_prompt <- 'Responda apenas: {"status": "ok"}'
  req <- ai_make_request(test_prompt, cfg = cfg, timeout_sec = timeout_sec)
  if (is.null(req)) {
    return(list(ok = FALSE, provider = cfg$provider, error = "Provedor não suportado"))
  }

  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp)) {
    return(list(ok = FALSE, provider = cfg$provider, error = "Timeout ou erro de rede"))
  }

  status <- tryCatch(httr2::resp_status(resp), error = function(e) 500)
  if (status >= 400) {
    return(list(ok = FALSE, provider = cfg$provider, error = sprintf("HTTP %d", status)))
  }

  list(ok = TRUE, provider = cfg$provider, model = cfg$model)
}

validate_ai_config <- function() {
  cfg <- get_ai_config()
  is_ok <- nzchar(cfg$provider) && nzchar(cfg$api_key)
  if (!is_ok) {
    message("----------------------------------------------------------------------")
    message("AVISO: Nenhuma chave de API de IA (Gemini, OpenAI, Nvidia, Anthropic, Groq, OpenRouter, DeepSeek) configurada!")
    message("O processamento com Inteligência Artificial (IA) estará desativado.")
    message("Para habilitar a IA, configure sua chave no arquivo .Renviron (ex: GEMINI_API_KEY ou OPENAI_API_KEY).")
    message("----------------------------------------------------------------------")
  } else {
    message(sprintf("IA Configurada: Provedor [%s], Modelo [%s]", cfg$provider, cfg$model))
  }
  is_ok
}

trim_for_ai <- function(text, max_chars = NULL) {
  if (is.null(max_chars)) {
    max_chars <- as.numeric(Sys.getenv("AI_MAX_CHARS", "20000"))
    if (is.na(max_chars) || max_chars <= 0) max_chars <- 20000
  }
  text <- normalize_ws(text %||% "")
  if (nchar(text) <= max_chars) return(text)
  substr(text, 1, max_chars)
}

# Prompt de sistema fixo — define a persona e os padrões de qualidade da IA
.AI_SYSTEM_PROMPT <- paste(
  "Você é um especialista sênior em curadoria de editais de fomento científico e tecnológico.",
  "Seu público é PESQUISADORES acadêmicos que buscam financiamento e precisam avaliar rapidamente",
  "se um edital é relevante para sua área. Produza sempre saídas:",
  "(1) OBJETIVAS: sem jargão burocrático ou linguagem administrativa genérica;",
  "(2) INFORMATIVAS: respondendo o que, para quem, em qual área e quando;",
  "(3) ESPECÍFICAS: com termos do domínio científico/tecnológico real do edital, nunca termos genéricos."
)

ai_make_request <- function(prompt, system_prompt = .AI_SYSTEM_PROMPT, cfg = NULL, timeout_sec = 60) {
  if (is.null(cfg)) cfg <- get_ai_config()
  if (!nzchar(cfg$provider) || !nzchar(cfg$api_key)) {
    return(NULL)
  }

  req <- NULL
  if (cfg$provider == "gemini") {
    # Gemini: system instruction separada
    url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", cfg$model, cfg$api_key)
    body <- list(
      contents = list(list(parts = list(list(text = prompt)))),
      generationConfig = list(temperature = 0.1, responseMimeType = "application/json")
    )
    if (nzchar(system_prompt %||% "")) {
      body$systemInstruction <- list(parts = list(list(text = system_prompt)))
    }
    req <- httr2::request(url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(`Content-Type` = "application/json") |>
      httr2::req_body_json(body, auto_unbox = TRUE)
  } else if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds", "nvidia")) {
    # OpenAI-compatível: system message separada
    url <- cfg$api_url
    messages <- list()
    if (nzchar(system_prompt %||% "")) {
      messages <- c(messages, list(list(role = "system", content = system_prompt)))
    }
    messages <- c(messages, list(list(role = "user", content = prompt)))
    req <- httr2::request(url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(
        `Content-Type` = "application/json",
        `Authorization` = sprintf("Bearer %s", cfg$api_key)
      ) |>
      httr2::req_body_json(list(
        model = cfg$model,
        messages = messages,
        temperature = 0.1,
        response_format = list(type = "json_object")
      ), auto_unbox = TRUE)
  } else if (cfg$provider == "anthropic") {
    url <- cfg$api_url
    body <- list(
      model = cfg$model,
      messages = list(list(role = "user", content = prompt)),
      max_tokens = 4000,
      temperature = 0.1
    )
    if (nzchar(system_prompt %||% "")) {
      body$system <- system_prompt
    }
    req <- httr2::request(url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(
        `Content-Type` = "application/json",
        `x-api-key` = cfg$api_key,
        `anthropic-version` = "2023-06-01"
      ) |>
      httr2::req_body_json(body, auto_unbox = TRUE)
  }
  req
}

ai_request <- function(prompt, timeout_sec = 45, retries = 2, log_path = NULL, conn = NULL, cfg = NULL) {
  start_time <- Sys.time()
  if (is.null(cfg)) cfg <- get_ai_config()
  if (!nzchar(cfg$provider) || !nzchar(cfg$api_key)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", "Configuração de IA incompleta ou ausente. IA desabilitada.")
    return(NULL)
  }

  req <- ai_make_request(prompt, cfg = cfg, timeout_sec = timeout_sec)
  if (is.null(req)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Provedor de IA não suportado ou falha ao criar request para: %s", cfg$provider))
    return(NULL)
  }

  # Retry manual com suporte a Retry-After header
  for (attempt in seq_len(retries + 1)) {
    resp <- tryCatch({
      httr2::req_perform(req)
    }, error = function(e) {
      if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Erro de rede/timeout na chamada de IA (tentativa %d/%d): %s", attempt, retries + 1, e$message))
      NULL
    })

    if (is.null(resp)) {
      if (attempt <= retries) Sys.sleep(2^attempt + stats::runif(1, 0, 1))
      next
    }

    status <- tryCatch(httr2::resp_status(resp), error = function(e) 500)

    if (status == 429 && attempt <= retries) {
      retry_after <- tryCatch(httr2::resp_header(resp, "Retry-After"), error = function(e) NULL)
      delay <- if (!is.null(retry_after)) {
        val <- suppressWarnings(as.numeric(retry_after))
        if (!is.na(val) && val > 0) val else 2^attempt + stats::runif(1, 0, 1)
      } else {
        2^attempt + stats::runif(1, 0, 1)
      }
      if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("429 de %s — aguardando %.1fs (tentativa %d/%d)", cfg$provider, delay, attempt, retries + 1))
      Sys.sleep(delay)
      next
    }

    if (status >= 500 && attempt <= retries) {
      Sys.sleep(2^attempt + stats::runif(1, 0, 1))
      next
    }

    txt <- try(httr2::resp_body_string(resp), silent = TRUE)
    if (!inherits(txt, "try-error") && nzchar(txt)) {
      parsed_res <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
      if (inherits(parsed_res, "try-error")) return(NULL)
      
      extracted_text <- NULL
      if (cfg$provider == "gemini") {
        extracted_text <- tryCatch(parsed_res$candidates[[1]]$content$parts[[1]]$text %||% txt, error = function(e) txt)
      } else if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds", "nvidia")) {
        extracted_text <- tryCatch(parsed_res$choices[[1]]$message$content %||% txt, error = function(e) txt)
      } else if (cfg$provider == "anthropic") {
        extracted_text <- tryCatch(parsed_res$content[[1]]$text %||% txt, error = function(e) txt)
      }
      
      if (!is.null(extracted_text) && nzchar(extracted_text)) {
        elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
        if (!is.null(conn)) log_metric(conn, cfg$provider, "ai_request", elapsed, list(provider = cfg$provider, model = cfg$model, status = status))
        return(extracted_text)
      }
    }
  }
  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
  if (!is.null(conn)) log_metric(conn, cfg$provider, "ai_request", elapsed, list(provider = cfg$provider, model = cfg$model, status = "failed"))
  NULL
}

ai_request_parallel <- function(prompts, timeout_sec = 45, log_path = NULL) {
  if (length(prompts) == 0) return(list())
  cfg <- get_ai_config()
  if (!nzchar(cfg$provider) || !nzchar(cfg$api_key)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", "Configuração de IA incompleta ou ausente. IA paralela desabilitada.")
    return(replicate(length(prompts), NULL, simplify = FALSE))
  }

  reqs <- lapply(prompts, function(p) {
    ai_make_request(p, cfg = cfg, timeout_sec = timeout_sec)
  })
  valid_indices <- which(!vapply(reqs, is.null, logical(1)))
  
  if (length(valid_indices) == 0) {
    return(replicate(length(prompts), NULL, simplify = FALSE))
  }

  valid_reqs <- reqs[valid_indices]

  resps <- tryCatch({
    httr2::req_perform_parallel(valid_reqs, on_error = "continue")
  }, error = function(e) {
    if (!is.null(log_path)) log_write(log_path, "ERROR", sprintf("Erro crítico no processamento paralelo do httr2: %s", e$message))
    replicate(length(valid_reqs), structure(list(message = e$message), class = "error"))
  })

  results <- replicate(length(prompts), NULL, simplify = FALSE)
  retry_indices <- integer()

  for (i in seq_along(valid_indices)) {
    orig_idx <- valid_indices[[i]]
    resp <- resps[[i]]

    if (inherits(resp, "httr2_response")) {
      status <- tryCatch(httr2::resp_status(resp), error = function(e) 500)
      if (status == 429) {
        retry_after <- tryCatch(httr2::resp_header(resp, "Retry-After"), error = function(e) NULL)
        delay <- if (!is.null(retry_after)) {
          val <- suppressWarnings(as.numeric(retry_after))
          if (!is.na(val) && val > 0) val else 5
        } else 5
        if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("429 paralelo em %s — retry individual após %.1fs (edital %d)", cfg$provider, delay, orig_idx))
        Sys.sleep(delay)
        retry_indices <- c(retry_indices, orig_idx)
        next
      }

      txt <- try(httr2::resp_body_string(resp), silent = TRUE)
      if (!inherits(txt, "try-error") && nzchar(txt)) {
        parsed_res <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
        if (inherits(parsed_res, "try-error")) next
        extracted_text <- NULL
        if (cfg$provider == "gemini") {
          extracted_text <- tryCatch(parsed_res$candidates[[1]]$content$parts[[1]]$text %||% txt, error = function(e) txt)
        } else if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds", "nvidia")) {
          extracted_text <- tryCatch(parsed_res$choices[[1]]$message$content %||% txt, error = function(e) txt)
        } else if (cfg$provider == "anthropic") {
          extracted_text <- tryCatch(parsed_res$content[[1]]$text %||% txt, error = function(e) txt)
        }
        results[[orig_idx]] <- extracted_text
      }
    } else {
      err_msg <- if (inherits(resp, "error")) resp$message else "Erro desconhecido"
      if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Falha na chamada paralela da IA (edital índice %d): %s", orig_idx, err_msg))
    }
  }

  # Retry individual para 429
  for (orig_idx in retry_indices) {
    retry_resp <- tryCatch(httr2::req_perform(reqs[[orig_idx]]), error = function(e) NULL)
    if (!is.null(retry_resp) && inherits(retry_resp, "httr2_response")) {
      txt <- try(httr2::resp_body_string(retry_resp), silent = TRUE)
      if (!inherits(txt, "try-error") && nzchar(txt)) {
        parsed_res <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
        if (!inherits(parsed_res, "try-error")) {
          extracted_text <- NULL
          if (cfg$provider == "gemini") {
            extracted_text <- tryCatch(parsed_res$candidates[[1]]$content$parts[[1]]$text %||% txt, error = function(e) txt)
          } else if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds", "nvidia")) {
            extracted_text <- tryCatch(parsed_res$choices[[1]]$message$content %||% txt, error = function(e) txt)
          } else if (cfg$provider == "anthropic") {
            extracted_text <- tryCatch(parsed_res$content[[1]]$text %||% txt, error = function(e) txt)
          }
          results[[orig_idx]] <- extracted_text
        }
      }
    }
  }

  results
}

# ── Prompt unificado de extração de metadados (fonte única da verdade) ────────

build_extraction_prompt <- function(text, current_info = list()) {
  paste(
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

# Skill do Agente: Extração Inicial de Metadados
skill_extract_metadata <- function(text, current_info = list(), log_path = NULL, conn = NULL) {
  prompt <- build_extraction_prompt(text, current_info)

  raw <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
  if (is.null(raw)) return(list())

  parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) return(list())

  result <- validate_ai_output(as.list(parsed))
  if (!is.null(log_path) && length(result$warnings) > 0) {
    for (w in result$warnings) {
      log_write(log_path, "WARN", sprintf("Validação IA: %s", w))
    }
  }
  result$output
}

# Skill do Agente: Auditoria de Controle de Qualidade (Evasão de Alucinações)
skill_verify_metadata <- function(metadata, raw_text, log_path = NULL, conn = NULL) {
  if (length(metadata) == 0) return(metadata)

  prompt <- paste(
    "Você é um auditor de qualidade de dados de editais de fomento.",
    "Revise os metadados extraídos e verifique os seguintes pontos:",
    "",
    "1. E_EDITAL_FOMENTO e MOTIVO_DESCARTE: O texto realmente representa um edital de fomento ou oportunidade de financiamento/bolsa principal?",
    "   - Se for uma retificação, aditivo, alteração, prorrogação, resultado de edital, ou se for um manual administrativo, relatório, notícia, ou guia geral sobre linhas de crédito permanentes (não-editais), certifique-se de que 'e_edital_fomento' seja false e 'motivo_descarte' indique a razão claramente (ex: 'Retificação de edital', 'Guia de linha de crédito permanente').",
    "   - Caso seja um edital de fomento real, certifique-se de que 'e_edital_fomento' seja true e 'motivo_descarte' seja null.",
    "",
    "2. RESUMO: O campo 'resumo' descreve claramente o OBJETO DO FINANCIAMENTO (o que financia, para quem, em qual área)?",
    "   - Se o resumo for uma cópia do texto bruto, uma lista de seções (ex: '1. FINALIDADE 1.1...') ou texto de navegação de site, REESCREVA-O de forma sintética e informativa.",
    "   - O resumo deve ter no máximo 3 frases e responder: O que financia? Para quem? Em qual área?",
    "",
    "3. PALAVRAS-CHAVE: O campo 'palavras_chave' contém termos do domínio científico/tecnológico do edital?",
    "   - Remova qualquer palavra que seja: nome de instituição, termo administrativo (edital, seleção, pesquisa, fomento, bolsa, prazo, período), palavra funcional (estar, cada, através, durante, sendo, deverá).",
    "   - Substitua por termos específicos do tema real do edital.",
    "   - Mantenha entre 5 e 8 termos compostos e específicos.",
    "",
    "4. DATA_LIMITE: A data_limite está presente no texto e no formato AAAA-MM-DD?",
    "",
    "5. ELEGIBILIDADE: A elegibilidade está específica (não apenas 'pesquisadores' genérico)?",
    "",
    "Retorne o JSON completo corrigido com todos os campos originais.",
    "",
    "Metadados extraídos para revisão:",
    jsonlite::toJSON(metadata, auto_unbox = TRUE, null = "null"),
    "",
    "=== TEXTO BRUTO DO EDITAL ===",
    trim_for_ai(raw_text, max_chars = 10000)
  )

  raw <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
  if (is.null(raw)) return(metadata)

  parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) return(metadata)
  result <- validate_ai_output(as.list(parsed))
  result$output
}

# Pipeline do Agente: Executa as skills sequencialmente
ai_extract_fields <- function(text, current = list(), log_path = NULL, conn = NULL) {
  if (!ai_available()) return(list())

  # Passo 1: Skill de Extração de Metadados
  extracted <- skill_extract_metadata(text, current, log_path, conn = conn)
  if (length(extracted) == 0) return(list())

  # Passo 2: Skill de Auditoria e Auto-Correção (opcional via AI_VERIFY_METADATA)
  verify_enabled <- !identical(tolower(Sys.getenv("AI_VERIFY_METADATA", "true")), "false")
  if (verify_enabled) {
    extracted <- skill_verify_metadata(extracted, text, log_path, conn = conn)
  }

  extracted
}


# --- Validação de Schema IA ---

.AI_ENUMS <- list(
  tipo_oportunidade = c("edital", "grant", "fellowship", "bolsa", "licitação", "licitacao",
                        "convocatória", "convocatoria", "chamada", "projeto", "programa",
                        "auxílio", "auxilio", "financiamento", "apoio", "incentivo"),
  status_oportunidade = c("aberto", "encerrado", "futuro", "encerrando", "em andamento",
                          "em breve", "suspenso", "cancelado"),
  idioma = c("pt", "en", "es", "fr", "de", "it", "zh", "ja"),
  moeda = c("BRL", "USD", "EUR", "GBP", "CAD", "ARS", "CLP", "COP")
)

normalize_ai_date <- function(value) {
  if (is.null(value) || is.na(value)) return(NA_character_)
  val <- as.character(value)
  if (!nzchar(val) || val %in% c("null", "NULL", "N/A", "n/a", "a definir", "A definir", "a Definir")) {
    return(NA_character_)
  }
  val <- trimws(val)
  d <- tryCatch(lubridate::ymd(val, quiet = TRUE), error = function(e) NA)
  if (!is.na(d)) return(as.character(d))
  d <- tryCatch(lubridate::dmy(val, quiet = TRUE), error = function(e) NA)
  if (!is.na(d)) return(as.character(d))
  d <- tryCatch(lubridate::mdy(val, quiet = TRUE), error = function(e) NA)
  if (!is.na(d)) return(as.character(d))
  NA_character_
}

validate_date_field <- function(value) {
  normalized <- normalize_ai_date(value)
  list(valid = !is.na(normalized), normalized = normalized)
}

validate_numeric_field <- function(value) {
  if (is.null(value) || is.na(value)) return(list(valid = TRUE, normalized = NA_real_))
  val <- as.character(value)
  val <- gsub("[^0-9.,]", "", val)
  val <- gsub(",", ".", val)
  num <- suppressWarnings(as.numeric(val))
  list(valid = !is.na(num) && num >= 0, normalized = num)
}

validate_enum_field <- function(value, allowed) {
  if (is.null(value) || is.na(value)) return(list(valid = TRUE, normalized = NA_character_))
  val <- tolower(trimws(as.character(value)))
  if (!nzchar(val)) return(list(valid = TRUE, normalized = NA_character_))
  # Mapeamento de sinônimos
  synonyms <- list(
    "bolsa" = "bolsa", "scholarship" = "bolsa", "fellowship" = "fellowship",
    "edital" = "edital", "call" = "chamada", "chamada" = "chamada",
    "open" = "aberto", "aberto" = "aberto", "closed" = "encerrado",
    "encerrado" = "encerrado", "upcoming" = "futuro", "futuro" = "futuro",
    "ongoing" = "em andamento", "em andamento" = "em andamento",
    "pt-br" = "pt", "portuguese" = "pt", "english" = "en", "spanish" = "es"
  )
  resolved <- synonyms[[val]] %||% val
  valid <- resolved %in% allowed
  list(valid = valid, normalized = if (valid) resolved else val)
}

validate_language_code <- function(value) {
  validate_enum_field(value, .AI_ENUMS$idioma)
}

validate_keyword_count <- function(value, min_kw = 5, max_kw = 8) {
  if (is.null(value) || is.na(value)) return(list(valid = FALSE, count = 0L))
  kws <- safe_split(as.character(value))
  count <- length(kws)
  list(valid = count >= min_kw && count <= max_kw, count = count, keywords = kws)
}

validate_ai_output <- function(ai_list) {
  if (is.null(ai_list) || length(ai_list) == 0) return(list(valid = TRUE, errors = character(), warnings = character()))

  errors <- character()
  warnings <- character()

  # Validar datas
  for (date_field in c("data_limite", "data_publicacao", "data_abertura", "data_encerramento")) {
    if (!is.null(ai_list[[date_field]])) {
      v <- validate_date_field(ai_list[[date_field]])
      if (!v$valid) {
        warnings <- c(warnings, sprintf("Campo '%s': formato de data inválido ('%s') — aceito como está", date_field, ai_list[[date_field]]))
      } else if (!is.na(v$normalized) && !identical(as.character(ai_list[[date_field]]), v$normalized)) {
        ai_list[[date_field]] <- v$normalized
        warnings <- c(warnings, sprintf("Campo '%s': normalizado de '%s' para '%s'", date_field, ai_list[[date_field]], v$normalized))
      }
    }
  }

  # Validar enums
  enum_validations <- list(
    tipo_oportunidade = .AI_ENUMS$tipo_oportunidade,
    status_oportunidade = .AI_ENUMS$status_oportunidade,
    idioma = .AI_ENUMS$idioma,
    moeda = .AI_ENUMS$moeda
  )
  for (enum_field in names(enum_validations)) {
    if (!is.null(ai_list[[enum_field]])) {
      v <- validate_enum_field(ai_list[[enum_field]], enum_validations[[enum_field]])
      if (!v$valid) {
        warnings <- c(warnings, sprintf("Campo '%s': valor '%s' fora do enum permitido — aceito como está", enum_field, ai_list[[enum_field]]))
      } else if (!is.na(v$normalized) && !identical(tolower(as.character(ai_list[[enum_field]])), v$normalized)) {
        ai_list[[enum_field]] <- v$normalized
      }
    }
  }

  # Validar numérico
  if (!is.null(ai_list$valor_financiado)) {
    v <- validate_numeric_field(ai_list$valor_financiado)
    if (!v$valid) {
      warnings <- c(warnings, sprintf("Campo 'valor_financiado': valor não numérico ('%s') — aceito como está", ai_list$valor_financiado))
    }
  }

  # Validar palavras-chave
  if (!is.null(ai_list$palavras_chave)) {
    v <- validate_keyword_count(ai_list$palavras_chave)
    if (!v$count == 0) {
      warnings <- c(warnings, sprintf("Campo 'palavras_chave': %d termos (esperado 5-8) — aceito como está", v$count))
    }
  }

  list(valid = length(errors) == 0, errors = errors, warnings = warnings, output = ai_list)
}

fix_polyglotr_encoding <- function(s) {
  # Corrige double-encoding causado pelo polyglotr no Windows
  # polyglotr retorna strings com bytes UTF-8 interpretados como Latin-1
  # Esta funcao reverte: UTF-8 chars -> Latin-1 bytes -> UTF-8 chars
  if (is.null(s) || !is.character(s) || length(s) == 0) return(enc2utf8(s))
  vapply(s, function(x) {
    if (is.na(x) || !nzchar(x)) return(x)
    tryCatch({
      bytes <- iconv(x, from = "UTF-8", to = "latin1", toRaw = TRUE)[[1]]
      if (is.null(bytes)) return(enc2utf8(x))
      enc2utf8(rawToChar(bytes))
    }, error = function(e) enc2utf8(x))
  }, character(1), USE.NAMES = FALSE)
}

translate_to_pt_br <- function(records, log_path = NULL) {
  # Traduz titulos e descricoes de fontes EU para pt-br usando polyglotr (Google Translate)
  # Args:
  #   records: tibble com colunas titulo, descricao_resumida, idioma
  #   log_path: caminho para log opcional
  # Returns:
  #   tibble com titulos e descricoes traduzidos
  
  if (is.null(records) || nrow(records) == 0) return(records)
  
  # Verificar se polyglotr esta disponivel
  if (!requireNamespace("polyglotr", quietly = TRUE)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", "Pacote polyglotr nao instalado. Traducao ignorada. Instale com: install.packages('polyglotr')")
    return(records)
  }
  
  # Identificar registros que precisam de traducao (nao sao pt)
  needs_translation <- which(records$idioma != "pt" | is.na(records$idioma))
  
  if (length(needs_translation) == 0) {
    if (!is.null(log_path)) log_write(log_path, "INFO", "Todos os registros ja estao em pt-br. Traducao ignorada.")
    return(records)
  }
  
  if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("Traduzindo %d registros para pt-br via Google Translate...", length(needs_translation)))
  
  translated_count <- 0L
  failed_count <- 0L
  
  for (i in needs_translation) {
    titulo <- records$titulo[[i]]
    
    # Pular se titulo ja esta vazio ou e NA
    if (is.null(titulo) || !nzchar(titulo) || is.na(titulo)) next
    
    # Detectar idioma de origem: polaco se tem caracteres especiais, senao ingles
    source_lang <- if (grepl("[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]", titulo)) "pl" else "en"
    
    # Traduzir titulo com polyglotr (Google Translate, sem API key)
    translated <- tryCatch(
      polyglotr::google_translate(titulo, target_language = "pt", source_language = source_lang),
      error = function(e) {
        if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Falha ao traduzir titulo: %s", e$message))
        NA_character_
      }
    )
    
    if (is.character(translated) && length(translated) == 1 && !is.na(translated) && nzchar(translated)) {
      records$titulo[[i]] <- fix_polyglotr_encoding(translated)
      records$idioma[[i]] <- "pt"
      translated_count <- translated_count + 1L
      
      # Traduzir descricao se existir e for substancial
      descricao <- records$descricao_resumida[[i]]
      if (!is.null(descricao) && !is.na(descricao) && nzchar(descricao) && nchar(descricao) > 50) {
        desc_translated <- tryCatch(
          polyglotr::google_translate(substr(descricao, 1, 500), target_language = "pt", source_language = source_lang),
          error = function(e) NA_character_
        )
        if (is.character(desc_translated) && length(desc_translated) == 1 && !is.na(desc_translated) && nzchar(desc_translated)) {
          records$descricao_resumida[[i]] <- fix_polyglotr_encoding(desc_translated)
        }
      }
    } else {
      failed_count <- failed_count + 1L
    }
    
    # Rate limiting: pausa entre chamadas para nao sobrecarregar a API
    Sys.sleep(0.3)
  }
  
  if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("Traducao concluida. %d/%d registros traduzidos com sucesso (%d falhas).", translated_count, length(needs_translation), failed_count))
  
  records
}
