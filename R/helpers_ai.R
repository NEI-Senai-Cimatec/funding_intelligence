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
      model <- "poolside/laguna-xs-2.1"
    } else if (provider == "anthropic") {
      model <- "claude-3-5-haiku-latest"
    } else if (provider == "groq") {
      model <- "llama-3.3-70b-versatile"
    } else if (provider == "openrouter") {
      model <- "liquid/lfm-2.5-2.6b:free"
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

.FALLBACK_ORDER <- c(
  "groq", "openai", "gemini", "anthropic", "nvidia",
  "deepseek", "openrouter", "bluesminds"
)
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
  if (!is.null(cooldown) && Sys.time() < cooldown) {
    return(FALSE)
  }
  TRUE
}

reset_ai_provider <- function(provider) {
  # exists-guard: rm() em binding ausente emitia warning "object '..._failures' not found"
  if (exists(paste0(provider, "_failures"), envir = .ai_failures, inherits = FALSE)) {
    rm(list = paste0(provider, "_failures"), envir = .ai_failures, inherits = FALSE)
  }
  if (exists(paste0(provider, "_cooldown"), envir = .ai_failures, inherits = FALSE)) {
    rm(list = paste0(provider, "_cooldown"), envir = .ai_failures, inherits = FALSE)
  }
  invisible(NULL)
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
    if (!is.null(log_path)) {
      log_write(
        log_path, "WARN",
        sprintf("Fallback: provedor %s falhou, tentando próximo", provider)
      )
    }
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

# trim_for_ai agora vive em helpers_text.R (corrige BUG-09: preserva prazos no fim)

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
    # Gemini: system instruction separada — chave SEMPRE em header (BUG-10)
    url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", cfg$model)
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
      httr2::req_headers(
        `Content-Type` = "application/json",
        `x-goog-api-key` = cfg$api_key
      ) |>
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

# Chamada de IA com suporte a imagens (multimodal/vision)
ai_request_vision <- function(prompt, image_b64, mime = "image/png",
                              timeout_sec = 60, retries = 1,
                              log_path = NULL, conn = NULL) {
  cfg <- get_ai_config()
  if (!nzchar(cfg$provider) || !nzchar(cfg$api_key)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", "ai_request_vision: configuracao de IA ausente.")
    return(NULL)
  }

  # Gemini nao suporta images via generateContent com data URI nestes provedores
  if (cfg$provider == "gemini") {
    if (!is.null(log_path)) {
      log_write(
        log_path, "WARN",
        sprintf("ai_request_vision: provedor %s nao suporta vision neste contexto. Ignorando.", cfg$provider)
      )
    }
    return(NULL)
  }

  data_uri <- sprintf("data:%s;base64,%s", mime, image_b64)

  user_content <- list(
    list(type = "text", text = prompt),
    list(type = "image_url", image_url = list(url = data_uri))
  )

  req <- NULL
  if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds", "nvidia")) {
    messages <- list(list(role = "user", content = user_content))
    req <- httr2::request(cfg$api_url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(
        `Content-Type` = "application/json",
        `Authorization` = sprintf("Bearer %s", cfg$api_key)
      ) |>
      httr2::req_body_json(list(
        model = cfg$model,
        messages = messages,
        max_tokens = 1024,
        temperature = 0.1
      ), auto_unbox = TRUE)
  } else if (cfg$provider == "anthropic") {
    anthropic_content <- list(
      list(type = "image", source = list(
        type = "base64",
        media_type = mime,
        data = image_b64
      )),
      list(type = "text", text = prompt)
    )
    body <- list(
      model = cfg$model,
      messages = list(list(role = "user", content = anthropic_content)),
      max_tokens = 1024,
      temperature = 0.1
    )
    req <- httr2::request(cfg$api_url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(
        `Content-Type` = "application/json",
        `x-api-key` = cfg$api_key,
        `anthropic-version` = "2023-06-01"
      ) |>
      httr2::req_body_json(body, auto_unbox = TRUE)
  }

  if (is.null(req)) {
    if (!is.null(log_path)) {
      log_write(
        log_path, "WARN",
        sprintf("ai_request_vision: provedor %s nao suportado para vision.", cfg$provider)
      )
    }
    return(NULL)
  }

  start_time <- Sys.time()
  for (attempt in seq_len(retries + 1)) {
    resp <- tryCatch(httr2::req_perform(req), error = function(e) {
      if (!is.null(log_path)) {
        log_write(
          log_path, "WARN",
          sprintf("ai_request_vision: erro de rede (tentativa %d/%d): %s", attempt, retries + 1, e$message)
        )
      }
      NULL
    })

    if (is.null(resp)) {
      if (attempt <= retries) Sys.sleep(2^attempt + stats::runif(1, 0, 1))
      next
    }

    status <- tryCatch(httr2::resp_status(resp), error = function(e) 500L)

    if (status == 429L && attempt <= retries) {
      retry_after <- tryCatch(httr2::resp_header(resp, "Retry-After"), error = function(e) NULL)
      delay <- if (!is.null(retry_after)) {
        val <- suppressWarnings(as.numeric(retry_after))
        if (!is.na(val) && val > 0) val else 2^attempt
      } else {
        2^attempt + stats::runif(1, 0, 1)
      }
      if (!is.null(log_path)) {
        log_write(
          log_path, "WARN",
          sprintf("ai_request_vision: 429 — aguardando %.1fs (tentativa %d/%d)", delay, attempt, retries + 1)
        )
      }
      Sys.sleep(delay)
      next
    }

    if (status >= 500L && attempt <= retries) {
      Sys.sleep(2^attempt + stats::runif(1, 0, 1))
      next
    }

    txt <- try(httr2::resp_body_string(resp), silent = TRUE)
    if (!inherits(txt, "try-error") && nzchar(txt)) {
      parsed_res <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
      if (inherits(parsed_res, "try-error")) {
        return(NULL)
      }

      extracted <- NULL
      if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds", "nvidia")) {
        extracted <- tryCatch(parsed_res$choices[[1]]$message$content %||% txt, error = function(e) txt)
      } else if (cfg$provider == "anthropic") {
        extracted <- tryCatch(parsed_res$content[[1]]$text %||% txt, error = function(e) txt)
      }

      if (!is.null(extracted) && nzchar(extracted)) {
        elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
        if (!is.null(conn)) {
          log_metric(
            conn, cfg$provider, "ai_request_vision", elapsed,
            list(provider = cfg$provider, model = cfg$model, status = status)
          )
        }
        return(extracted)
      }
    }
  }

  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
  if (!is.null(conn)) {
    log_metric(
      conn, cfg$provider, "ai_request_vision", elapsed,
      list(provider = cfg$provider, model = cfg$model, status = "failed")
    )
  }
  NULL
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
    resp <- tryCatch(
      {
        httr2::req_perform(req)
      },
      error = function(e) {
        if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Erro de rede/timeout na chamada de IA (tentativa %d/%d): %s", attempt, retries + 1, e$message))
        NULL
      }
    )

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
      if (inherits(parsed_res, "try-error")) {
        return(NULL)
      }

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
  if (length(prompts) == 0) {
    return(list())
  }
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

  resps <- tryCatch(
    {
      httr2::req_perform_parallel(valid_reqs, on_error = "continue")
    },
    error = function(e) {
      if (!is.null(log_path)) log_write(log_path, "ERROR", sprintf("Erro crítico no processamento paralelo do httr2: %s", e$message))
      replicate(length(valid_reqs), structure(list(message = e$message), class = "error"))
    }
  )

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
        } else {
          5
        }
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

# Contrato v2 (BUG-07): sem status_oportunidade (status é derivado por regra
# temporal), com valor_estimado/moeda, exatamente 5 palavras-chave, objeto de
# confiança e auto-auditoria. Regras R1-R5 obrigatórias.
# Raw string r"(...)" — R 4.0+: permite newlines sem sequências de escape.
AI_ENRICHMENT_PROMPT <- r"(PAPEL: Você é um auditor extrator de metadados de editais de fomento. Extraia SOMENTE o que o texto evidencia.

TAREFA: Analise o TEXTO DO EDITAL e retorne APENAS um JSON válido, sem markdown, com este schema exato:

{
  "titulo_limpo": "string ou null",
  "resumo": "string (máximo 3 frases) ou null",
  "elegibilidade": "string ou null",
  "area_tematica": "string ou null",
  "tipo_oportunidade": "enum [edital, chamada, grant, fellowship, bolsa, subvencao, premio, licitacao] ou null",
  "idioma": "enum [pt, en, es] ou null",
  "data_limite": "AAAA-MM-DD ou null",
  "data_publicacao": "AAAA-MM-DD ou null",
  "valor_estimado": "number ou null",
  "moeda": "enum [BRL, USD, EUR, GBP, CAD] ou null",
  "palavras_chave": "array de exatamente 5 strings ou null",
  "observacoes": "string ou null",
  "confianca": {
    "titulo_limpo": "0.0 a 1.0",
    "data_limite": "0.0 a 1.0",
    "valor_estimado": "0.0 a 1.0",
    "palavras_chave": "0.0 a 1.0"
  }
}

REGRAS ESTRITAS:
R1. NUNCA INVENTE. Sem evidência clara no texto -> null (e confiança 0.0).
R2. data_limite = data EXPLICITAMENTE ligada a "submissão", "proposta", "inscrição", "prazo final". IGNORE datas de rodapé, "última atualização", "resultados", "eventos", "divulgação". Se houver prazos por lote/fase, retorne o MAIS TARDIO.
R3. status_oportunidade NÃO é campo seu: o sistema deriva status por regra temporal. NÃO retorne status.
R4. palavras_chave: exatamente 5 termos específicos do domínio (ex: "inteligência artificial", "biotecnologia"). PROIBIDO: anos (2022, 2026), números, siglas de agência (CNPq, FAPESB), tokens genéricos do título sem semântica.
R5. Cite evidência: para cada campo não-nulo, guarde internamente o trecho do texto que o sustenta. Use essa evidência na auto-auditoria.

AUTO-AUDITORIA (antes de emitir o JSON):
A1. Verifique R1-R5.
A2. Se violação encontrada, corrija ANTES de emitir.
A3. O JSON final deve ser parseável por jsonlite::fromJSON.

FEW-SHOT EXEMPLO:
Entrada: "... As propostas deverão ser submetidas até 15 de outubro de 2026. O orçamento global é de R$ 2.000.000,00. Podem participar ICTs e empresas brasileiras ..."
Saída: {
  "titulo_limpo": "Edital de Fomento à Inovação 2026",
  "resumo": "Edital para financiamento de projetos de inovação em ICTs e empresas brasileiras. Orçamento de R$ 2 milhões. Prazo de submissão: 15 de outubro de 2026.",
  "elegibilidade": "ICTs e empresas brasileiras",
  "area_tematica": "Inovação tecnológica",
  "tipo_oportunidade": "edital",
  "idioma": "pt",
  "data_limite": "2026-10-15",
  "data_publicacao": null,
  "valor_estimado": 2000000,
  "moeda": "BRL",
  "palavras_chave": ["inovação", "ict", "empresa", "financiamento", "tecnologia"],
  "observacoes": null,
  "confianca": {
    "titulo_limpo": 0.95,
    "data_limite": 0.98,
    "valor_estimado": 0.99,
    "palavras_chave": 0.90
  }
}
)"

# Indicador legado (e_edital_fomento) mantido para retorno de descarte:
build_extraction_prompt <- function(text, current_info = list()) {
  paste(
    AI_ENRICHMENT_PROMPT,
    "COMO CLASSIFICAR DESCARTE: retorne um JSON adicional com os campos",
    "e_edital_fomento (boolean) e motivo_descarte (string ou null) apenas quando o texto",
    "NÃO for um edital/grant/chamada/fellowship/bolsa principal",
    "(ex: retificação, errata, prorrogação, resultado, manual administrativo, notícia)",
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
  if (is.null(raw)) {
    return(list())
  }

  parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) {
    return(list())
  }

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
  if (length(metadata) == 0) {
    return(metadata)
  }

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
  if (is.null(raw)) {
    return(metadata)
  }

  parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) {
    return(metadata)
  }
  result <- validate_ai_output(as.list(parsed))
  result$output
}

# Pipeline do Agente: Executa as skills sequencialmente
ai_extract_fields <- function(text, current = list(), log_path = NULL, conn = NULL) {
  if (!ai_available()) {
    return(list())
  }

  # Passo 1: Skill de Extração de Metadados
  extracted <- skill_extract_metadata(text, current, log_path, conn = conn)
  if (length(extracted) == 0) {
    return(list())
  }

  # Passo 2: Skill de Auditoria e Auto-Correção (opcional via AI_VERIFY_METADATA)
  verify_enabled <- !identical(tolower(Sys.getenv("AI_VERIFY_METADATA", "true")), "false")
  if (verify_enabled) {
    extracted <- skill_verify_metadata(extracted, text, log_path, conn = conn)
  }

  extracted
}


# --- Validação de Schema IA ---

.AI_ENUMS <- list(
  tipo_oportunidade = c(
    "edital", "grant", "fellowship", "bolsa", "licitação", "licitacao",
    "convocatória", "convocatoria", "chamada", "projeto", "programa",
    "auxílio", "auxilio", "financiamento", "apoio", "incentivo"
  ),
  status_oportunidade = c(
    "aberto", "encerrado", "futuro", "encerrando", "em andamento",
    "em breve", "suspenso", "cancelado"
  ),
  idioma = c("pt", "en", "es", "fr", "de", "it", "zh", "ja"),
  moeda = c("BRL", "USD", "EUR", "GBP", "CAD", "ARS", "CLP", "COP")
)

normalize_ai_date <- function(value) {
  if (is.null(value) || length(value) == 0) {
    return(NA_character_)
  }
  # Blindagem: IA pode retornar array (length 6-8) — pega apenas primeiro elemento
  v1 <- value[[1]]
  if (is.na(v1)) {
    return(NA_character_)
  }
  val <- as.character(v1)
  if (!nzchar(val) || val %in% c("null", "NULL", "N/A", "n/a", "a definir", "A definir", "a Definir")) {
    return(NA_character_)
  }
  val <- trimws(val)
  d <- tryCatch(lubridate::ymd(val, quiet = TRUE), error = function(e) NA)
  if (!is.na(d)) {
    return(as.character(d))
  }
  d <- tryCatch(lubridate::dmy(val, quiet = TRUE), error = function(e) NA)
  if (!is.na(d)) {
    return(as.character(d))
  }
  d <- tryCatch(lubridate::mdy(val, quiet = TRUE), error = function(e) NA)
  if (!is.na(d)) {
    return(as.character(d))
  }
  NA_character_
}

validate_date_field <- function(value) {
  normalized <- normalize_ai_date(value)
  list(valid = !is.na(normalized), normalized = normalized)
}

validate_numeric_field <- function(value) {
  if (is.null(value) || length(value) == 0) {
    return(list(valid = TRUE, normalized = NA_real_))
  }
  v1 <- value[[1]]
  if (is.na(v1)) {
    return(list(valid = TRUE, normalized = NA_real_))
  }
  val <- as.character(v1)
  val <- gsub("[^0-9.,]", "", val)
  val <- gsub(",", ".", val)
  num <- suppressWarnings(as.numeric(val))
  list(valid = !is.na(num) && num >= 0, normalized = num)
}

validate_enum_field <- function(value, allowed) {
  if (is.null(value) || length(value) == 0) {
    return(list(valid = TRUE, normalized = NA_character_))
  }
  v1 <- value[[1]]
  if (is.na(v1)) {
    return(list(valid = TRUE, normalized = NA_character_))
  }
  val <- tolower(trimws(as.character(v1)))
  if (!nzchar(val)) {
    return(list(valid = TRUE, normalized = NA_character_))
  }
  # Mapeamento de sinônimos (inclui nacionalidades por extenso)
  synonyms <- list(
    "bolsa" = "bolsa", "scholarship" = "bolsa", "fellowship" = "fellowship",
    "edital" = "edital", "call" = "chamada", "chamada" = "chamada",
    "open" = "aberto", "aberto" = "aberto", "closed" = "encerrado",
    "encerrado" = "encerrado", "upcoming" = "futuro", "futuro" = "futuro",
    "ongoing" = "em andamento", "em andamento" = "em andamento",
    "pt-br" = "pt", "portuguese" = "pt", "português" = "pt", "portugues" = "pt", "pt_bR" = "pt",
    "english" = "en", "inglês" = "en", "ingles" = "en", "en-us" = "en",
    "spanish" = "es", "espanhol" = "es", "espanh" = "es",
    "french" = "fr", "francês" = "fr", "français" = "fr",
    "german" = "de", "alemão" = "de", "alemao" = "de",
    "italian" = "it", "italiano" = "it",
    "chinese" = "zh", "chinês" = "zh", "chines" = "zh",
    "japanese" = "ja", "japonês" = "ja", "japones" = "ja"
  )
  resolved <- synonyms[[val]] %||% val
  valid <- resolved %in% allowed
  list(valid = valid, normalized = if (valid) resolved else val)
}

validate_language_code <- function(value) {
  validate_enum_field(value, .AI_ENUMS$idioma)
}

validate_keyword_count <- function(value, min_kw = 5, max_kw = 8) {
  if (is.null(value) || length(value) == 0) {
    return(list(valid = FALSE, count = 0L))
  }
  # Se IA retornou array, colapsa em string antes de contar
  v_str <- if (length(value) > 1) paste(as.character(value), collapse = ", ") else as.character(value[[1]])
  if (is.na(v_str)) {
    return(list(valid = FALSE, count = 0L))
  }
  kws <- safe_split(v_str)
  count <- length(kws)
  list(valid = count >= min_kw && count <= max_kw, count = count, keywords = kws)
}

validate_ai_output <- function(ai_list) {
  if (is.null(ai_list) || length(ai_list) == 0) {
    return(list(valid = TRUE, errors = character(), warnings = character()))
  }

  errors <- character()
  warnings <- character()

  # Validar datas — blindado contra array (usa [[1]])
  for (date_field in c("data_limite", "data_publicacao", "data_abertura", "data_encerramento")) {
    if (!is.null(ai_list[[date_field]]) && length(ai_list[[date_field]]) > 0) {
      val1 <- ai_list[[date_field]][[1]]
      v <- validate_date_field(val1)
      if (!v$valid) {
        warnings <- c(warnings, sprintf("Campo '%s': formato de data inválido ('%s') — aceito como está", date_field, val1))
      } else if (!is.na(v$normalized) && !identical(as.character(val1), v$normalized)) {
        ai_list[[date_field]] <- v$normalized
        warnings <- c(warnings, sprintf("Campo '%s': normalizado de '%s' para '%s'", date_field, val1, v$normalized))
      } else {
        ai_list[[date_field]] <- v$normalized
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
    if (!is.null(ai_list[[enum_field]]) && length(ai_list[[enum_field]]) > 0) {
      val1 <- ai_list[[enum_field]][[1]]
      v <- validate_enum_field(val1, enum_validations[[enum_field]])
      if (!v$valid) {
        warnings <- c(warnings, sprintf("Campo '%s': valor '%s' fora do enum permitido — aceito como está", enum_field, val1))
      } else if (!is.na(v$normalized) && !identical(tolower(as.character(val1)), v$normalized)) {
        ai_list[[enum_field]] <- v$normalized
      } else {
        ai_list[[enum_field]] <- v$normalized
      }
    }
  }

  # Validar numérico — usa [[1]] blindado (array de IA)
  if (!is.null(ai_list$valor_financiado) && length(ai_list$valor_financiado) > 0) {
    vf1 <- ai_list$valor_financiado[[1]]
    if (!is.na(vf1)) {
      v <- validate_numeric_field(vf1)
      if (!v$valid) {
        warnings <- c(warnings, sprintf("Campo 'valor_financiado': valor não numérico ('%s') — aceito como está", vf1))
      }
    }
  }

  # Validar palavras-chave — só alerta se FORA da faixa esperada (5-8)
  if (!is.null(ai_list$palavras_chave) && length(ai_list$palavras_chave) > 0) {
    v <- validate_keyword_count(ai_list$palavras_chave)
    if (!isTRUE(v$valid) && v$count != 0) {
      warnings <- c(warnings, sprintf("Campo 'palavras_chave': %d termos (esperado 5-8) — aceito como está", v$count))
    }
  }

  list(valid = length(errors) == 0, errors = errors, warnings = warnings, output = ai_list)
}

# ─── Validação estrita de schema da IA (BUG-07) ────────────────────────────────
# Retorna list(valid, errors, data): campos inválidos são NULADOS (forçando
# fallback heurístico) e o erro concreto é auditado pelo chamador.

.ascii_kw <- function(x) normalize_text(x %||% "")

validate_ai_schema <- function(parsed_json) {
  if (is.null(parsed_json) || length(parsed_json) == 0L) {
    return(list(valid = FALSE, errors = c("resposta vazia"), data = list()))
  }
  if (is.data.frame(parsed_json)) {
    parsed_json <- as.list(parsed_json[1, , drop = FALSE])
    parsed_json <- lapply(parsed_json, function(v) if (length(v) == 1L) v[[1]] else v)
  }
  if (!is.list(parsed_json)) {
    parsed_json <- as.list(parsed_json)
  }
  errors <- character()
  data <- parsed_json

  # R3: status_oportunidade nunca é campo da IA
  data$status_oportunidade <- NULL

  enums <- list(
    tipo_oportunidade = c("edital", "chamada", "grant", "fellowship", "bolsa", "subvencao", "premio", "licitacao", "subvenção", "prêmio", "licitação"),
    idioma = c("pt", "en", "es"),
    moeda = c("BRL", "USD", "EUR", "GBP", "CAD")
  )
  for (f in names(enums)) {
    v <- data[[f]]
    if (!is.null(v) && length(v) > 0L && !is.na(v[[1L]]) && nzchar(trimws(as.character(v[[1L]])))) {
      val_raw <- trimws(as.character(v[[1L]]))
      # Case-insensitive: moeda pode chegar "eur"/"Usd" e idiom "PT"
      if (!(tolower(val_raw) %in% tolower(enums[[f]]))) {
        errors <- c(errors, sprintf("campo '%s' fora do enum: %s", f, val_raw))
        data[[f]] <- NULL
      } else {
        data[[f]] <- val_raw
      }
    }
  }

  # Palavras-chave: exatamente 5; token years/números/agências são removidos
  agency_tokens <- tolower(c(
    "cnpq", "capes", "finep", "fapesb", "fapes", "confap", "daad", "embrapii",
    "horizon europe", "erc", "undp", "petrobras", "sigitec", "world bank",
    "banco mundial", "humboldt", "nsf", "doe", "economia", "mdic"
  ))
  if (!is.null(data$palavras_chave) && length(data$palavras_chave) > 0L) {
    v_str <- if (length(data$palavras_chave) > 1L) {
      paste(as.character(data$palavras_chave), collapse = ", ")
    } else {
      as.character(data$palavras_chave[[1L]])
    }
    kws <- safe_split(v_str)
    kws <- kws[!grepl("^\\d{1,4}$|^\\d{4}$", .ascii_kw(kws))]
    kws <- kws[!(.ascii_kw(kws) %in% agency_tokens)]
    if (length(kws) != 5L) {
      errors <- c(errors, "palavras_chave deve ter 5 itens")
    }
    if (length(kws) == 0L) kws <- c(kws, "não inferido")
    data$palavras_chave <- paste(kws, collapse = "; ")
  } else {
    errors <- c(errors, "palavras_chave ausente")
    data$palavras_chave <- NULL
  }

  # Datas: formato ISO verificável
  for (f in c("data_limite", "data_publicacao")) {
    v <- data[[f]]
    if (!is.null(v) && length(v) > 0L && !is.na(v[[1L]]) && nzchar(trimws(as.character(v[[1L]])))) {
      d <- parse_date_safe(as.character(v[[1L]]))
      if (is.na(d[[1L]])) {
        errors <- c(errors, sprintf("campo '%s' em formato inválido", f))
        data[[f]] <- NULL
      } else {
        data[[f]] <- as.character(d[[1L]])
      }
    }
  }

  list(valid = length(errors) == 0L, errors = errors, data = data)
}

# ─── Fallback heurístico obrigatório (corrige BUG-02) ─────────────────────────
# Preenche APENAS campos vazios com as inferências locais já testadas.

apply_heuristic_fallback <- function(record) {
  if (is.null(record)) {
    return(record)
  }
  if (!is.list(record) && !is.data.frame(record)) {
    record <- as.list(record)
  }
  txt <- paste(
    as.character(record$titulo %||% ""),
    as.character(record$descricao_resumida %||% ""),
    as.character(record$descricao_completa %||% ""),
    as.character(record$texto_bruto %||% ""),
    collapse = " "
  )
  txt <- normalize_ws(txt)

  field_empty <- function(field) {
    v <- record[[field]]
    is.null(v) || length(v) == 0L || any(is.na(v)) || !nzchar(trimws(as.character(v[[1L]] %||% "")))
  }

  inferred <- character()
  remember <- function(field, value) {
    if (!is.na(value) && nzchar(trimws(as.character(value)))) {
      record[[field]] <<- as.character(value)
      inferred <<- unique(c(inferred, field))
    }
  }

  if (field_empty("tipo_oportunidade")) remember("tipo_oportunidade", infer_type_from_text(txt))
  if (field_empty("idioma")) remember("idioma", infer_language_simple(txt)[[1L]])
  if (field_empty("area_tematica")) remember("area_tematica", infer_area_from_text_one(txt))
  if (field_empty("palavras_chave")) remember("palavras_chave", extract_keywords_simple(txt))
  if (field_empty("data_limite")) {
    ctx <- extract_dates_contextual(txt)
    if (length(ctx) > 0L) remember("data_limite", as.character(max(ctx)))
  }
  if (field_empty("valor_financiado")) {
    money <- parse_money_text(txt)
    if (!is.null(money) && !is.na(money$value)) {
      record$valor_financiado[[1L]] <- money$value
      inferred <- unique(c(inferred, "valor_financiado"))
      if (field_empty("moeda") && !is.na(money$currency)) remember("moeda", money$currency)
    }
  }

  if (length(inferred) > 0L) {
    prev <- record$campos_inferidos_ia %||% ""
    record$campos_inferidos_ia <- paste(c(safe_split(prev), inferred), collapse = "; ")
  }
  record
}

# ─── Redação de chaves para logs (segurança, BUG-10) ──────────────────────────

redact_keys_in_text <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(x)
  }
  vapply(as.character(x), function(one) {
    if (is.na(one) || !nzchar(one)) {
      return(one)
    }
    # Cobre "?key=ABCD", "x-goog-api-key: ABC", "Authorization: Bearer x", "api_key":"..." etc
    one <- gsub("(?i)(\\?|&)key=[^&\\s\"']+", "\\1key=<REDACTED>", one, perl = TRUE)
    one <- gsub("(?i)(x-goog-api-key\\s*[:=]\\s*)[^\\s\"']+", "\\1<REDACTED>", one, perl = TRUE)
    one <- gsub("(?i)(authorization\\s*[:=]\\s*bearer\\s+)[^\\s\"',]+", "\\1<REDACTED>", one, perl = TRUE)
    one <- gsub("(?i)(api[_\\-]?key\\s*[:=]\\s*)[^\\s\"',]+", "\\1<REDACTED>", one, perl = TRUE)
    one
  }, character(1), USE.NAMES = FALSE)
}

# ─── Token-bucket rate limiter por provedor (MELHORIA-05) ─────────────────────

TokenBucketRateLimiter <- R6::R6Class("TokenBucketRateLimiter",
  public = list(
    capacity = 60,
    refill_rate = 1,
    tokens = 60,
    last_refill = NULL,
    initialize = function(capacity = 60L, refill_rate = 1.0) {
      self$capacity <- capacity
      self$refill_rate <- refill_rate
      self$tokens <- capacity
      self$last_refill <- Sys.time()
    },
    acquire = function(units = 1L, max_wait = 120) {
      started <- Sys.time()
      repeat {
        now <- Sys.time()
        self$tokens <- min(self$capacity, self$tokens + as.numeric(now - self$last_refill, units = "secs") * self$refill_rate)
        self$last_refill <- now
        if (self$tokens >= units) {
          self$tokens <- self$tokens - units
          return(TRUE)
        }
        if (as.numeric(Sys.time() - started, units = "secs") >= max_wait) {
          return(FALSE)
        }
        # aguarda tempo suficiente até a próxima unidade
        need <- units - self$tokens
        Sys.sleep(max(0.05, need / self$refill_rate))
      }
    }
  )
)

.ai_provider_limiters <- new.env(parent = emptyenv())

ai_rate_limiter_for <- function(provider = NULL) {
  if (is.null(provider) || !nzchar(provider)) {
    provider <- tryCatch(get_ai_config()$provider, error = function(e) "unknown")
  }
  lim <- get0(provider, envir = .ai_provider_limiters, inherits = FALSE)
  if (is.null(lim)) {
    cfg <- switch(provider,
      gemini = list(capacity = 60L, refill = 1.0),
      groq = list(capacity = 120L, refill = 2.0),
      deepseek = list(capacity = 60L, refill = 1.0),
      list(capacity = 30L, refill = 0.5)
    )
    lim <- TokenBucketRateLimiter$new(capacity = cfg$capacity, refill_rate = cfg$refill)
    assign(provider, lim, envir = .ai_provider_limiters)
  }
  lim
}

fix_polyglotr_encoding <- function(s) {
  # Corrige double-encoding causado pelo polyglotr no Windows
  # No Linux (UTF-8 nativo), polyglotr retorna strings corretas — apenas garante encoding
  if (is.null(s) || !is.character(s) || length(s) == 0) {
    return(enc2utf8(s))
  }
  if (.Platform$OS.type != "windows") {
    return(enc2utf8(s))
  }
  vapply(s, function(x) {
    if (is.na(x) || !nzchar(x)) {
      return(x)
    }
    tryCatch(
      {
        bytes <- iconv(x, from = "UTF-8", to = "latin1", toRaw = TRUE)[[1]]
        if (is.null(bytes)) {
          return(enc2utf8(x))
        }
        enc2utf8(rawToChar(bytes))
      },
      error = function(e) enc2utf8(x)
    )
  }, character(1), USE.NAMES = FALSE)
}

google_translate_text_pt <- function(text, source_lang = "en") {
  text <- as.character(text %||% "")
  if (!nzchar(trimws(text))) return(NA_character_)

  # 1) Endpoint HTTP direto do Google Translate (nao exige pacote polyglotr)
  res_http <- tryCatch({
    req <- httr2::request("https://translate.googleapis.com/translate_a/single") |>
      httr2::req_url_query(
        client = "gtx",
        sl = source_lang,
        tl = "pt",
        dt = "t",
        q = text
      ) |>
      httr2::req_timeout(8)
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_string(resp, encoding = "UTF-8")
    parsed <- jsonlite::fromJSON(body, simplifyVector = FALSE)
    if (is.list(parsed) && length(parsed) >= 1 && is.list(parsed[[1]])) {
      parts <- vapply(parsed[[1]], function(seg) {
        if (is.list(seg) && length(seg) >= 1 && !is.null(seg[[1]])) as.character(seg[[1]]) else ""
      }, character(1))
      out <- paste0(parts, collapse = "")
      if (nzchar(trimws(out))) return(fix_polyglotr_encoding(out))
    }
    NA_character_
  }, error = function(e) NA_character_)

  if (!is.na(res_http) && nzchar(res_http)) {
    return(res_http)
  }

  # 2) Fallback via polyglotr se estiver instalado
  if (requireNamespace("polyglotr", quietly = TRUE)) {
    res_poly <- tryCatch(
      polyglotr::google_translate(text, target_language = "pt", source_language = source_lang),
      error = function(e) NA_character_
    )
    if (is.character(res_poly) && length(res_poly) == 1 && !is.na(res_poly) && nzchar(res_poly)) {
      return(fix_polyglotr_encoding(res_poly))
    }
  }

  NA_character_
}

clean_humboldt_summary_text <- function(desc_resumida, desc_completa = "") {
  raw <- if (nzchar(trimws(as.character(desc_completa %||% "")))) {
    as.character(desc_completa)
  } else {
    as.character(desc_resumida %||% "")
  }
  if (!nzchar(trimws(raw))) return("")
  # Remove blocos duplicados de "Hint ... Maximum number of applications received..." no topo
  cleaned <- gsub("(?s)^\\s*Hint\\s+.*?(?=\\n\\n[A-Z][a-zA-Z0-9 ()-]+\\n)", "", raw, perl = TRUE)
  cleaned <- gsub("\\bHint\\s+", "", cleaned, perl = TRUE)
  cleaned <- stringr::str_squish(cleaned)
  if (!nzchar(cleaned)) cleaned <- stringr::str_squish(as.character(desc_resumida %||% ""))
  substr(cleaned, 1, 900)
}

.humboldt_pt_catalog <- list(
  "humboldt research fellowship" = list(
    descricao_resumida = "Bolsa de pesquisa na Alemanha (Humboldt Research Fellowship) destinada a pesquisadores de pós-doutorado e pesquisadores experientes de todas as nacionalidades e áreas do conhecimento. O programa integra a iniciativa Global Minds Initiative Germany do Ministério Federal de Pesquisa, Tecnologia e Espaço da Alemanha (BMFTR), oferecendo suporte individualizado e financiamento para estadias de pesquisa de longa duração em cooperação com instituições anfitriãs alemãs. Nota: o limite máximo de candidaturas da rodada atual foi atingido; a próxima chamada abrirá em 15 de novembro de 2026.",
    elegibilidade = "Pesquisadores de pós-doutorado (até 4 anos após o doutorado) e pesquisadores experientes (até 12 anos após o doutorado) de todas as áreas.",
    publico_alvo = "Pesquisadores de pós-doutorado e pesquisadores experientes"
  ),
  "international climate protection fellowship" = list(
    descricao_resumida = "Bolsa Internacional de Proteção Climática da Fundação Alexander von Humboldt para futuros líderes e pesquisadores de pós-doutorado oriundos de países em desenvolvimento e emergentes não europeus (incluindo o Brasil). Apoia projetos de pesquisa aplicada ou acadêmica na Alemanha (12 a 24 meses) voltados ao combate às mudanças climáticas, estratégias de adaptação, preservação de ecossistemas e biodiversidade, uso sustentável dos oceanos e eficiência de recursos naturais. Concede até 15 bolsas anuais para líderes práticos e até 5 para pós-doutorandos.",
    elegibilidade = "Futuros líderes e pesquisadores de pós-doutorado de países em desenvolvimento ou emergentes com atuação em proteção climática e sustentabilidade.",
    publico_alvo = "Pesquisadores de pós-doutorado e especialistas/líderes em clima e sustentabilidade"
  ),
  "henriette herz scouting programme" = list(
    descricao_resumida = "Programa Henriette Herz Scouting da Fundação Alexander von Humboldt para recrutamento ativo de talentos científicos internacionais. Permite que professores e líderes de grupos de pesquisa na Alemanha atuem como 'scouts' para indicar diretamente até três jovens pesquisadores internacionais de excelência (sendo a primeira indicação destinada a pesquisadoras mulheres) para bolsas Humboldt Research Fellowship, ampliando a diversidade e a rede internacional de cooperação científica.",
    elegibilidade = "Professores (juniores ou titulares) e líderes de grupos de pesquisa com rede internacional consolidada atuando em instituições alemãs.",
    publico_alvo = "Professores, líderes de grupos de pesquisa e jovens pesquisadores internacionais"
  ),
  "japan society for the promotion of science (jsps) research fellowship" = list(
    descricao_resumida = "Bolsa de pesquisa JSPS (Sociedade Japonesa para a Promoção da Ciência) em parceria com a Fundação Alexander von Humboldt, voltada a pesquisadores de pós-doutorado altamente qualificados da Alemanha para realização de estadias de pesquisa em universidades e institutos japoneses em qualquer área do conhecimento. Conta com duas modalidades: curta duração (1 a 12 meses) e padrão (12 a 24 meses), incluindo bolsa mensal de 362.000 ienes, auxílio-instalação e passagens.",
    elegibilidade = "Pesquisadores de pós-doutorado vinculados a instituições de pesquisa da Alemanha em cooperação com anfitrião acadêmico no Japão.",
    publico_alvo = "Pesquisadores de pós-doutorado"
  ),
  "georg forster research fellowship" = list(
    descricao_resumida = "Bolsa de Pesquisa Georg Forster para o Desenvolvimento Sustentável, concedida pela Fundação Alexander von Humboldt a pesquisadores de pós-doutorado e pesquisadores experientes de países em desenvolvimento e emergentes (incluindo o Brasil) com qualificações acima da média. Apoia projetos em todas as disciplinas que contribuam para o alcance dos 17 Objetivos de Desenvolvimento Sustentável (ODS) da ONU em parceria com instituições na Alemanha. Nota: o programa passa por reformulação orçamentária para novas candidaturas, mantendo-se ativo o suporte aos bolsistas vigentes.",
    elegibilidade = "Pesquisadores de pós-doutorado e pesquisadores experientes de países em desenvolvimento e emergentes com foco nos ODS/desenvolvimento sustentável.",
    publico_alvo = "Pesquisadores de pós-doutorado e pesquisadores experientes"
  ),
  "alexander von humboldt professorship" = list(
    descricao_resumida = "Cátedra Alexander von Humboldt (Alexander von Humboldt Professorship), o mais valioso prêmio de pesquisa da Alemanha. Com financiamento da Global Minds Initiative Germany do Ministério Federal de Pesquisa, Tecnologia e Espaço (BMFTR), concede até 10 milhões de euros por até sete anos (incluindo 20% para custos administrativos) para que universidades alemãs recrutem pesquisadores líderes mundiais residentes no exterior para estabelecer grupos de pesquisa de fronteira na Alemanha.",
    elegibilidade = "Pesquisadores líderes internacionais de excelência indicados por universidades e instituições de pesquisa alemãs.",
    publico_alvo = "Pesquisadores seniores de liderança internacional e universidades"
  ),
  "capes-humboldt research fellowship" = list(
    descricao_resumida = "Programa de Bolsas de Pesquisa CAPES-Humboldt, parceria entre a CAPES e a Fundação Alexander von Humboldt voltada exclusivamente a pesquisadores do Brasil (pós-doutorandos e pesquisadores experientes) de todas as áreas do conhecimento para realização de estadias de pesquisa na Alemanha. Oferece suporte individualizado, financiamento integral de estadia e inserção na rede internacional de cooperação científica Humboldt.",
    elegibilidade = "Pesquisadores brasileiros ou residentes no Brasil em nível de pós-doutorado ou pesquisador experiente.",
    publico_alvo = "Pesquisadores de pós-doutorado e pesquisadores experientes do Brasil"
  ),
  "feodor lynen research fellowship" = list(
    descricao_resumida = "Bolsa de Pesquisa Feodor Lynen da Fundação Alexander von Humboldt para pesquisadores de pós-doutorado (6 a 24 meses) e pesquisadores experientes (6 a 18 meses, divisíveis em até 3 estadias) da Alemanha realizarem projetos de pesquisa no exterior junto a anfitriões membros da Rede Humboldt em todo o mundo (inclusive em ICTs e universidades brasileiras).",
    elegibilidade = "Pesquisadores de pós-doutorado e pesquisadores experientes da Alemanha em colaboração com anfitriões internacionais da Rede Humboldt.",
    publico_alvo = "Pesquisadores de pós-doutorado e pesquisadores experientes"
  ),
  "georg forster research award" = list(
    descricao_resumida = "Prêmio de Pesquisa Georg Forster concedido anualmente pela Fundação Alexander von Humboldt, com financiamento do Ministério Federal de Cooperação Econômica e Desenvolvimento da Alemanha (BMZ), a pesquisadores de renome internacional de países em desenvolvimento e emergentes em reconhecimento à relevância de sua trajetória acadêmica e impacto para o desenvolvimento sustentável.",
    elegibilidade = "Pesquisadores de renome internacional oriundos de países em desenvolvimento e emergentes indicados por acadêmicos na Alemanha.",
    publico_alvo = "Pesquisadores seniores internacionalmente reconhecidos"
  ),
  "humboldt research professorship" = list(
    descricao_resumida = "Programa Humboldt Research Professorship da Fundação Alexander von Humboldt (Global Minds Initiative Germany / BMFTR). Permite que pesquisadores internacionais de ponta conduzam pesquisas inovadoras e liderem grupos internacionais de trabalho em universidades e institutos alemães em formatos flexíveis (como cátedras compartilhadas ou cooperação laboratório a laboratório), sem necessidade de abandonar seu vínculo institucional no país de origem.",
    elegibilidade = "Pesquisadores internacionais de alto nível indicados por universidades ou instituições de pesquisa da Alemanha.",
    publico_alvo = "Pesquisadores líderes internacionais e instituições de pesquisa"
  ),
  "nstc (taiwan) research fellowships for researchers from germany" = list(
    descricao_resumida = "Bolsa de pesquisa do Conselho Nacional de Ciência e Tecnologia de Taiwan (NSTC) em cooperação com a Fundação Alexander von Humboldt, destinada a pós-doutorandos e pesquisadores experientes da Alemanha para estadias de pesquisa de 3 a 12 meses em Taiwan em qualquer área do conhecimento, com bolsa mensal de 85.000 NTD e suporte de reintegração.",
    elegibilidade = "Pesquisadores de pós-doutorado e pesquisadores experientes vinculados a instituições alemãs.",
    publico_alvo = "Pesquisadores de pós-doutorado e pesquisadores experientes"
  ),
  "hezekiah wardwell fellowship" = list(
    descricao_resumida = "Bolsa Hezekiah Wardwell da Fundação Alexander von Humboldt destinada a jovens músicos e musicólogos talentosos da Espanha para realização de estudos avançados ou aperfeiçoamento por um a dois semestres em academias de música ou conservatórios na Alemanha (bolsa mensal de 900 euros mais auxílio-viagem).",
    elegibilidade = "Jovens músicos e musicólogos qualificados da Espanha.",
    publico_alvo = "Músicos e musicólogos"
  ),
  "philipp schwartz initiative" = list(
    descricao_resumida = "Iniciativa Philipp Schwartz da Fundação Alexander von Humboldt e do Ministério das Relações Exteriores da Alemanha. Concede bolsas e financiamento para que universidades e instituições de pesquisa alemãs acolham pesquisadores estrangeiros submetidos a ameaças graves e contínuas em seus países de origem, permitindo a continuidade de suas atividades científicas em segurança (previsão de até 35 bolsas com início em janeiro de 2027).",
    elegibilidade = "Pesquisadores em situação de risco em seus países de origem indicados por universidades e instituições anfitriãs na Alemanha.",
    publico_alvo = "Pesquisadores em situação de risco e instituições acadêmicas anfitriãs"
  ),
  "carl-zeiss-humboldt research award" = list(
    descricao_resumida = "Prêmio de Pesquisa Carl-Zeiss-Humboldt, concedido anualmente pela Fundação Alexander von Humboldt com financiamento da Fundação Carl Zeiss. Destina-se a pesquisadores de destaque internacional nas áreas de Ciência, Tecnologia, Engenharia e Matemática (STEM) que desejem colaborar com instituições nos estados alemães de Baden-Württemberg, Renânia-Palatinado e Turíngia. O prêmio é de 100.000 euros, com até 50.000 euros adicionais para custos da cooperação científica.",
    elegibilidade = "Pesquisadores internacionalmente reconhecidos nas áreas de STEM (Ciência, Tecnologia, Engenharia e Matemática).",
    publico_alvo = "Pesquisadores seniores das áreas de STEM"
  ),
  "fraunhofer-bessel research award" = list(
    descricao_resumida = "Prêmio de Pesquisa Fraunhofer-Bessel, concedido conjuntamente pela Fundação Alexander von Humboldt e pela Sociedade Fraunhofer (até três prêmios anuais de 45.000 euros). Reconhece cientistas de destaque internacional que atuam em pesquisa aplicada no exterior e viabiliza estadias de pesquisa de 6 a 12 meses em institutos Fraunhofer na Alemanha para projetos conjuntos de inovação e pesquisa aplicada.",
    elegibilidade = "Pesquisadores reconhecidos internacionalmente com atuação destacada em pesquisa aplicada fora da Alemanha.",
    publico_alvo = "Pesquisadores de pesquisa aplicada e desenvolvimento tecnológico"
  ),
  "philipp franz von siebold award" = list(
    descricao_resumida = "Prêmio Philipp Franz von Siebold da Fundação Alexander von Humboldt, patrocinado pela Presidência da República Federal da Alemanha (valor de 80.000 euros). Reconhece pesquisadores japoneses de renome em todas as áreas do conhecimento e financia estadias de pesquisa colaborativa de 6 a 12 meses em instituições alemãs.",
    elegibilidade = "Pesquisadores japoneses de alto reconhecimento científico e acadêmico.",
    publico_alvo = "Pesquisadores seniores do Japão"
  ),
  "friedrich wilhelm bessel research award" = list(
    descricao_resumida = "Prêmio de Pesquisa Friedrich Wilhelm Bessel da Fundação Alexander von Humboldt (cerca de 20 prêmios anuais financiados pelo Ministério Federal de Educação e Pesquisa da Alemanha). Reconhece cientistas internacionalmente renomados residentes fora da Alemanha por suas realizações científicas excepcionais e os convida a conduzir projetos de pesquisa colaborativa de longo prazo com especialistas em instituições alemãs.",
    elegibilidade = "Pesquisadores internacionalmente reconhecidos residentes fora da Alemanha.",
    publico_alvo = "Pesquisadores reconhecidos internacionalmente"
  ),
  "humboldt research award" = list(
    descricao_resumida = "Prêmio de Pesquisa Humboldt (Humboldt Research Award), concedido anualmente pela Fundação Alexander von Humboldt (até 100 prêmios por ano) a pesquisadores líderes internacionais de todas as áreas do conhecimento residentes no exterior, em reconhecimento ao conjunto de sua obra acadêmica e científica, incluindo convite para conduzir projetos de pesquisa em cooperação com especialistas na Alemanha.",
    elegibilidade = "Pesquisadores líderes internacionais de todas as áreas do conhecimento residentes fora da Alemanha.",
    publico_alvo = "Pesquisadores líderes reconhecidos internacionalmente"
  )
)

normalize_humboldt_records_pt <- function(df) {
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0L) return(df)
  if (!all(c("entidade", "titulo", "descricao_resumida") %in% names(df))) return(df)

  is_humboldt <- grepl("humboldt", as.character(df$entidade %||% ""), ignore.case = TRUE) |
    grepl("^humboldt_", as.character(df$id_registro %||% ""), ignore.case = TRUE)
  if (!any(is_humboldt)) return(df)

  idxs <- which(is_humboldt)
  for (i in idxs) {
    t_key <- tolower(stringr::str_squish(as.character(df$titulo[[i]] %||% "")))
    entry <- .humboldt_pt_catalog[[t_key]]
    if (!is.null(entry)) {
      df$descricao_resumida[[i]] <- entry$descricao_resumida
      if ("descricao_completa" %in% names(df)) {
        df$descricao_completa[[i]] <- entry$descricao_resumida
      }
      if ("elegibilidade" %in% names(df)) {
        df$elegibilidade[[i]] <- entry$elegibilidade
      }
      if ("publico_alvo" %in% names(df)) {
        df$publico_alvo[[i]] <- entry$publico_alvo
      }
      if ("idioma" %in% names(df)) {
        df$idioma[[i]] <- "pt"
      }
    } else {
      # Caso surja algum novo edital da Humboldt que não esteja no catálogo e ainda esteja em inglês
      desc_cur <- as.character(df$descricao_resumida[[i]] %||% "")
      looks_en <- grepl("\\b(the|and|with|for|research|fellowship|award|applications?)\\b", desc_cur, ignore.case = TRUE)
      if (looks_en) {
        cleaned <- clean_humboldt_summary_text(
          desc_cur,
          if ("descricao_completa" %in% names(df)) df$descricao_completa[[i]] else ""
        )
        tr <- google_translate_text_pt(cleaned, source_lang = "en")
        if (!is.na(tr) && nzchar(tr)) {
          df$descricao_resumida[[i]] <- tr
          if ("idioma" %in% names(df)) df$idioma[[i]] <- "pt"
        }
      }
    }
  }
  df
}

translate_to_pt_br <- function(records, log_path = NULL) {
  # Traduz titulos e descricoes de fontes internacionais para pt-br via Google Translate HTTP / polyglotr
  if (is.null(records) || nrow(records) == 0) {
    return(records)
  }

  # Primeiro aplica normalizacao curada para registros da Alexander von Humboldt Foundation
  records <- tryCatch(normalize_humboldt_records_pt(records), error = function(e) records)

  # Identificar registros que ainda precisam de traducao (nao sao pt)
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
    descricao <- records$descricao_resumida[[i]]

    if ((is.null(titulo) || !nzchar(titulo) || is.na(titulo)) &&
        (is.null(descricao) || !nzchar(descricao) || is.na(descricao))) {
      next
    }

    source_lang <- if (grepl("[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]", paste(titulo, descricao))) "pl" else "en"
    any_ok <- FALSE

    if (!is.null(titulo) && !is.na(titulo) && nzchar(titulo)) {
      translated <- google_translate_text_pt(titulo, source_lang = source_lang)
      if (!is.na(translated) && nzchar(translated)) {
        records$titulo[[i]] <- translated
        any_ok <- TRUE
      }
    }

    if (!is.null(descricao) && !is.na(descricao) && nzchar(descricao) && nchar(descricao) > 20) {
      desc_clean <- clean_humboldt_summary_text(
        descricao,
        if ("descricao_completa" %in% names(records)) records$descricao_completa[[i]] else ""
      )
      desc_translated <- google_translate_text_pt(substr(desc_clean, 1, 1200), source_lang = source_lang)
      if (!is.na(desc_translated) && nzchar(desc_translated)) {
        records$descricao_resumida[[i]] <- desc_translated
        any_ok <- TRUE
      }
    }

    if ("elegibilidade" %in% names(records)) {
      eleg <- records$elegibilidade[[i]]
      if (!is.null(eleg) && !is.na(eleg) && nzchar(eleg)) {
        eleg_tr <- google_translate_text_pt(substr(eleg, 1, 500), source_lang = source_lang)
        if (!is.na(eleg_tr) && nzchar(eleg_tr)) records$elegibilidade[[i]] <- eleg_tr
      }
    }

    if (any_ok) {
      records$idioma[[i]] <- "pt"
      translated_count <- translated_count + 1L
    } else {
      failed_count <- failed_count + 1L
    }

    Sys.sleep(0.25)
  }

  if (!is.null(log_path)) log_write(log_path, "INFO", sprintf("Traducao concluida. %d/%d registros traduzidos com sucesso (%d falhas).", translated_count, length(needs_translation), failed_count))

  records
}

# ─── Utilitários da heurística de aderência por campus ──────────────────────
adherence_heuristic_text <- function(titulo, descricao) {
  clean <- function(x) {
    x <- as.character(x %||% "")
    x[is.na(x) | x %in% c("NA", "NULL")] <- ""
    paste(x, collapse = " ")
  }
  adherence_norm_cached(paste(clean(titulo), clean(descricao)))
}

# Texto normalizado em cache (os 6 núcleos avaliam o mesmo edital)
.adh_text_cache <- new.env(parent = emptyenv())
adherence_norm_cached <- function(x) {
  x <- paste(as.character(x %||% ""), collapse = " ")
  if (nchar(x) > 20000L) return(tolower(normalize_text(x)))
  key <- digest::digest(x, algo = "xxhash64")
  hit <- .adh_text_cache[[key]]
  if (!is.null(hit)) return(hit)
  if (length(ls(.adh_text_cache)) > 20000L) rm(list = ls(.adh_text_cache), envir = .adh_text_cache)
  out <- tolower(normalize_text(x))
  .adh_text_cache[[key]] <- out
  out
}

# Casa palavra-chave respeitando início de palavra (radicais como "oceanograf"
# continuam funcionando) e palavra inteira para siglas curtas ("rov", "gas", "ti"),
# evitando falsos positivos como "rov" em "improve" ou "gas" em "gastos".
# Padrões das listas de palavras-chave são normalizados uma única vez (cache):
# antes eram renormalizados a cada edital x núcleo, o que deixava a carga lenta.
.adh_pattern_cache <- new.env(parent = emptyenv())
adherence_kw_patterns <- function(kws) {
  key <- paste(kws, collapse = "\r")
  hit <- .adh_pattern_cache[[key]]
  if (!is.null(hit)) return(hit)
  kws_n <- unique(tolower(normalize_text(kws)))
  kws_n <- kws_n[nzchar(kws_n)]
  esc <- gsub("([.^$|()\\[\\]{}*+?\\\\])", "\\\\\\1", kws_n, perl = TRUE)
  pats <- ifelse(nchar(kws_n) <= 4L,
                 paste0("(?<![a-z0-9])", esc, "(?![a-z0-9])"),
                 paste0("(?<![a-z0-9])", esc))
  out <- list(kws = kws_n, pats = pats)
  .adh_pattern_cache[[key]] <- out
  out
}

adherence_kw_hits <- function(kws, norm_text) {
  if (!length(kws) || !nzchar(norm_text)) return(FALSE)
  length(adherence_kw_matches(kws, norm_text)) > 0L
}

# ─── Pontuação única de aderência por núcleo (0–100) ──────────────────────────
# Regra explicável, a MESMA para os 6 núcleos (as listas de palavras-chave não mudam):
#   +15 por termo distinto encontrado (até 4 termos = 60)
#   +15 por área temática adicional do núcleo (até 2 extras = 30)
#   +20 se algum termo aparece no TÍTULO (evidência forte)
#   +10 se a combinação estratégica do núcleo estiver presente
# Faixas: Baixa < 30 ≤ Média < 55 ≤ Alta < 75 ≤ Muito alta.
# Uma única palavra solta no resumo (ex.: "descarbonização") vale 15 = Baixa.
ADHERENCE_LEVEL_CUTS <- c(media = 30, alta = 55, muito_alta = 75)

adherence_kw_matches <- function(kws, norm_text) {
  if (!length(kws) || !nzchar(norm_text %||% "")) return(character())
  kp <- adherence_kw_patterns(kws)
  if (!length(kp$kws)) return(character())
  kp$kws[stringi::stri_detect_regex(norm_text, kp$pats)]
}

adherence_level_from_score <- function(score) {
  if (is.na(score)) return("Baixa")
  if (score >= ADHERENCE_LEVEL_CUTS[["muito_alta"]]) "Muito alta"
  else if (score >= ADHERENCE_LEVEL_CUTS[["alta"]]) "Alta"
  else if (score >= ADHERENCE_LEVEL_CUTS[["media"]]) "Média"
  else "Baixa"
}

adherence_score_from_kws <- function(groups, norm_text, titulo = "", combo = FALSE) {
  matched <- lapply(groups, adherence_kw_matches, norm_text = norm_text)
  terms <- unique(unlist(matched, use.names = FALSE))
  # "startup" e "startups" contam como um termo só
  if (length(terms) > 1L) {
    terms <- terms[!vapply(terms, function(t) { o <- setdiff(terms, t); any(nchar(o) < nchar(t) & startsWith(t, o)) }, logical(1))]
  }
  n_terms <- length(terms)
  n_groups <- sum(lengths(matched) > 0L)
  title_norm <- adherence_norm_cached(titulo)
  in_title <- n_terms > 0L && length(adherence_kw_matches(unlist(matched, use.names = FALSE), title_norm)) > 0L
  score <- 15 * min(n_terms, 4L) + 15 * min(max(n_groups - 1L, 0L), 2L) +
    ifelse(in_title, 20, 0) + ifelse(isTRUE(combo) && n_groups >= 2L, 10, 0)
  score <- min(100, score)
  list(score = score, nivel = adherence_level_from_score(score), termos = terms,
       n_terms = n_terms, n_groups = n_groups, in_title = in_title)
}

# Justificativas geradas pela heurística antiga (salvas no banco) — devem ser recalculadas
ADHERENCE_HEURISTIC_PATTERN <- "^(Oportunidade com menção isolada|Oportunidade com forte aderência direta|Oportunidade relevante|Oportunidade tangencial|Oportunidade sem conexão|Forte aderência direta|Oportunidade com aderência|Oportunidade com potencial)"

# ─── Avaliador de Aderência Científico-Tecnológica: Núcleo Naval & Offshore de PD&I ───────

PROMPT_NAVAL_OFFSHORE <- "
Você é um especialista sênior em fomento de PD&I para o setor Naval, Marítimo e Offshore.
Avalie a seguinte oportunidade de fomento para um núcleo de Pesquisa, Desenvolvimento e Inovação (PD&I) focado nas seguintes áreas tecnológicas:
1. ROV / AUV / USV (Veículos Operados Remotamente, Submarinos Autônomos, Superfície Não-Tripulada);
2. Engenharia Naval e Oceânica (Hidrodinâmica, Estruturas Navais, Materiais e Descarbonização Embarcada);
3. Energia Marítima (Petróleo & Gás Offshore, Eólica Offshore, Energia das Ondas/Marés, Hidrogênio Verde Marítimo);
4. Portos & Logística Marítima (Infraestrutura Portuária, Calado Líquido, Automação de Terminais);
5. Inteligência Artificial Marítima (Inspeção Subaquática por Visão Computacional, Navegação Autônoma, Gêmeos Digitais);
6. Defesa & Marinha do Brasil (Vigilância da Amazônia Azul, Defesa Marítima, Tecnologias Duplas/Dual-Use);
7. Infraestrutura de Ensaio (Tanques de Provas, Bacias de Ondas, Túneis de Vento/Cavitação, Laboratórios de Qualificação).

Retorne EXCLUSIVAMENTE um objeto JSON válido no seguinte formato:
{
  \"aderencia_naval_nivel\": \"Muito alta\" | \"Alta\" | \"Média\" | \"Baixa\",
  \"aderencia_naval_justificativa\": \"Explicação objetiva de 1 a 3 frases sobre por que o edital se conecta ou não com o Núcleo Naval/Offshore.\",
  \"ideia_projeto_consorcio\": \"Sugestão prática de conceito de projeto de PD&I e estrutura de consórcio/parceiros recomendados (ex: ICT + Petrobras + Marinha + EMBRAPII + SENAI CIMATEC). Retorne null se a aderência for Média ou Baixa.\"
}

=== OPORTUNIDADE ===
"

evaluate_naval_offshore_adherence <- function(titulo, descricao, texto_bruto = "", entidade = "", use_ai = TRUE, log_path = NULL, conn = NULL) {
  full_text <- paste(titulo %||% "", descricao %||% "", texto_bruto %||% "", entidade %||% "")
  # Heurística: SOMENTE título + resumo (o texto bruto traz menus/rodapés que geram falsos positivos)
  norm_text <- adherence_heuristic_text(titulo, descricao)
  
  # 1. Avaliação via IA se disponível
  if (use_ai && ai_available()) {
    prompt <- paste0(PROMPT_NAVAL_OFFSHORE, trim_for_ai(full_text, max_chars = 6000))
    raw_resp <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
    if (!is.null(raw_resp)) {
      parsed <- tryCatch(jsonlite::fromJSON(raw_resp, simplifyVector = TRUE), error = function(e) NULL)
      if (!is.null(parsed) && !is.null(parsed$aderencia_naval_nivel)) {
        return(list(
          aderencia_naval_nivel = parsed$aderencia_naval_nivel,
          aderencia_naval_justificativa = parsed$aderencia_naval_justificativa %||% "Oportunidade analisada pela IA com conexão ao setor naval.",
          ideia_projeto_consorcio = parsed$ideia_projeto_consorcio
        ))
      }
    }
  }
  
  # 2. Fallback Heurístico Determinístico
  kw_rov <- c("rov", "auv", "usv", "submarino", "subaquatic", "veiculo autonomo", "subsea", "robotica submarina", "drone maritimo")
  kw_naval <- c("naval", "oceanic", "oceanograf", "embarcac", "embarcação", "casco", "estabilidade naval", "hidrodinamica", "maritim", "propulsao")
  kw_energia <- c("offshore", "petroleo", "gas", "eolica offshore", "wind offshore", "ondas", "mares", "descarbonizacao", "hidrogenio verde", "riser", "fpso")
  kw_portos <- c("porto", "portuar", "dragagem", "calado", "terminal maritim", "logistica maritim")
  kw_ia <- c("inteligencia artificial", "visao computacional", "gemeo digital", "digital twin", "navegacao autonoma", "manutencao preditiva")
  kw_defesa <- c("marinha", "amazonia azul", "defesa maritima", "sisgaaz", "prosub", "vigilancia maritim", "dupla finalidade", "dual-use")
  kw_ensaio <- c("tanque de provas", "bacia de ondas", "tunel de cavitacao", "ensaio", "laboratorio de qualificacao", "bancada de testes")
  
  check_hits <- function(kws) adherence_kw_hits(kws, norm_text)
  
  hits_rov <- check_hits(kw_rov)
  hits_naval <- check_hits(kw_naval)
  hits_energia <- check_hits(kw_energia)
  hits_portos <- check_hits(kw_portos)
  hits_ia <- check_hits(kw_ia)
  hits_defesa <- check_hits(kw_defesa)
  hits_ensaio <- check_hits(kw_ensaio)
  
  total_hits <- sum(c(hits_rov, hits_naval, hits_energia, hits_portos, hits_ia, hits_defesa, hits_ensaio))
  
  found_areas <- character()
  if (hits_rov) found_areas <- c(found_areas, "ROV/AUV/USV")
  if (hits_naval) found_areas <- c(found_areas, "Engenharia Naval e Oceânica")
  if (hits_energia) found_areas <- c(found_areas, "Energia Marítima & Offshore")
  if (hits_portos) found_areas <- c(found_areas, "Portos & Logística Marítima")
  if (hits_ia) found_areas <- c(found_areas, "Inteligência Artificial Marítima")
  if (hits_defesa) found_areas <- c(found_areas, "Defesa & Marinha do Brasil")
  if (hits_ensaio) found_areas <- c(found_areas, "Infraestrutura de Ensaio")
  
  adh <- adherence_score_from_kws(list(kw_rov, kw_naval, kw_energia, kw_portos, kw_ia, kw_defesa, kw_ensaio), norm_text, titulo, combo = ((hits_rov && hits_energia)))
  if (identical(adh$nivel, "Muito alta")) {
    nivel <- "Muito alta"
    justificativa <- sprintf("Oportunidade com forte aderência direta ao Núcleo Naval & Offshore nas áreas: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Desenvolver solução avançada em %s. Consórcio Recomendado: Núcleo Naval CIMATEC + Petrobras/Shell + Unidade EMBRAPII + Marinha do Brasil.", found_areas[[1]])
  } else if (identical(adh$nivel, "Alta")) {
    nivel <- "Alta"
    justificativa <- sprintf("Oportunidade relevante conectando-se a temas estratégicos navais: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Aplicação tecnológica em %s. Consórcio Recomendado: ICT parceira + Empresa do setor Marítimo/Offshore + SENAI CIMATEC.", found_areas[[1]])
  } else if (identical(adh$nivel, "Média")) {
    nivel <- "Média"
    justificativa <- sprintf("Oportunidade tangencial com interface potencial na área de %s.", found_areas[[1]])
    ideia <- NULL
  } else {
    nivel <- "Baixa"
    justificativa <- if (length(found_areas)) sprintf("Oportunidade com menção isolada a %s (%s), insuficiente para aderência ao núcleo.", found_areas[[1]], paste(adh$termos, collapse = ", ")) else "Oportunidade sem conexão direta identificada com o ecossistema de PD&I Naval e Offshore."
    ideia <- NULL
  }
  
  list(
    aderencia_naval_nivel = nivel,
    aderencia_naval_score = adh$score,
    aderencia_naval_justificativa = justificativa,
    ideia_projeto_consorcio = ideia
  )
}

# ─── Avaliador de Aderência Científico-Tecnológica: CIMATEC Sertão ───────────────────────

PROMPT_SERTAO <- "
Você é um especialista sênior em fomento de PD&I para o Semiárido, Agrotech, Recursos Hídricos e Energias Renováveis.
Avalie a seguinte oportunidade de fomento para o campus SENAI CIMATEC Sertão, focado nas seguintes áreas tecnológicas:
1. Agricultura de Precisão & Agrotech (drones agrícolas, sensores de solo, automação de colheita/plantio);
2. Recursos Hídricos, Irrigação & Dessalinização (reúso de água, segurança hídrica, microirrigação, gestão de bacias);
3. Energias Renováveis no Semiárido (energia solar fotovoltaica, eólica onshore, hidrogênio verde, biomassa);
4. Bioeconomia da Caatinga & Biotecnologia Agrícola (produtos da flora nativa, biopesticidas, biofertilizantes);
5. Pecuária Conectada & Sanidade Animal (rastreabilidade animal, nutrição resiliente, caprinovinocultura);
6. Convivência com o Semiárido & Clima (mitigação de secas, tecnologias sociais hídricas, alertas agroclimáticos);
7. Agroindústria & Cadeias Produtivas Regionais (processamento de alimentos, embalagens ativas, agregação de valor local).

Retorne EXCLUSIVAMENTE um objeto JSON válido no seguinte formato:
{
  \"aderencia_sertao_nivel\": \"Muito alta\" | \"Alta\" | \"Média\" | \"Baixa\",
  \"aderencia_sertao_justificativa\": \"Explicação objetiva de 1 a 3 frases sobre por que o edital se conecta ou não com o CIMATEC Sertão.\",
  \"ideia_projeto_sertao\": \"Sugestão prática de conceito de projeto de PD&I e consórcio recomendado (ex: ICT + Cooperativa/Empresa Agro + EMBRAPII + CIMATEC Sertão). Retorne null se a aderência for Média ou Baixa.\"
}

=== OPORTUNIDADE ===
"

evaluate_sertao_adherence <- function(titulo, descricao, texto_bruto = "", entidade = "", use_ai = TRUE, log_path = NULL, conn = NULL) {
  full_text <- paste(titulo %||% "", descricao %||% "", texto_bruto %||% "", entidade %||% "")
  # Heurística: SOMENTE título + resumo (o texto bruto traz menus/rodapés que geram falsos positivos)
  norm_text <- adherence_heuristic_text(titulo, descricao)
  
  if (use_ai && ai_available()) {
    prompt <- paste0(PROMPT_SERTAO, trim_for_ai(full_text, max_chars = 6000))
    raw_resp <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
    if (!is.null(raw_resp)) {
      parsed <- tryCatch(jsonlite::fromJSON(raw_resp, simplifyVector = TRUE), error = function(e) NULL)
      if (!is.null(parsed) && !is.null(parsed$aderencia_sertao_nivel)) {
        return(list(
          aderencia_sertao_nivel = parsed$aderencia_sertao_nivel,
          aderencia_sertao_justificativa = parsed$aderencia_sertao_justificativa %||% "Oportunidade analisada pela IA com conexão ao CIMATEC Sertão.",
          ideia_projeto_sertao = parsed$ideia_projeto_sertao %||% NA_character_
        ))
      }
    }
  }
  
  kw_agro <- c("agricultur", "agronegoc", "agrotech", "lavoura", "safra", "colheita", "solo", "semeadura", "cultivo", "precisao agricola", "fazenda")
  kw_hidro <- c("hidric", "agua", "irrigacao", "irrigad", "dessalinizacao", "poco", "bacia hidrografica", "seca", "semiarido", "semi-arido", "escassez hidrica")
  kw_energia <- c("solar", "fotovoltaic", "eolica", "renovavel", "hidrogenio verde", "h2v", "biomassa", "geracao distribuida", "transicao energetica")
  kw_bio <- c("caatinga", "bioeconomia", "biotecnologia agricola", "biofertilizante", "biopesticida", "flora nativa", "semente crioula")
  kw_pecuaria <- c("pecuaria", "caprino", "ovino", "gado", "rebanho", "sanidade animal", "pastagem", "zootecnia", "leite")
  kw_agroind <- c("agroindustria", "processamento de alimentos", "cadeia produtiva", "beneficiamento de frutas", "cooperativa agricola", "agrifood")
  
  check_hits <- function(kws) adherence_kw_hits(kws, norm_text)
  
  hits_agro <- check_hits(kw_agro)
  hits_hidro <- check_hits(kw_hidro)
  hits_energia <- check_hits(kw_energia)
  hits_bio <- check_hits(kw_bio)
  hits_pecuaria <- check_hits(kw_pecuaria)
  hits_agroind <- check_hits(kw_agroind)
  
  total_hits <- sum(c(hits_agro, hits_hidro, hits_energia, hits_bio, hits_pecuaria, hits_agroind))
  
  found_areas <- character()
  if (hits_agro) found_areas <- c(found_areas, "Agricultura de Precisão & Agrotech")
  if (hits_hidro) found_areas <- c(found_areas, "Recursos Hídricos & Irrigação")
  if (hits_energia) found_areas <- c(found_areas, "Energias Renováveis no Semiárido")
  if (hits_bio) found_areas <- c(found_areas, "Bioeconomia da Caatinga")
  if (hits_pecuaria) found_areas <- c(found_areas, "Pecuária Conectada")
  if (hits_agroind) found_areas <- c(found_areas, "Agroindústria & Cadeias Regionais")
  
  adh <- adherence_score_from_kws(list(kw_agro, kw_hidro, kw_energia, kw_bio, kw_pecuaria, kw_agroind), norm_text, titulo, combo = ((hits_agro && hits_hidro) || (hits_hidro && hits_energia)))
  if (identical(adh$nivel, "Muito alta")) {
    nivel <- "Muito alta"
    justificativa <- sprintf("Forte aderência direta às prioridades do CIMATEC Sertão nas áreas: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Solução tecnológica integrada em %s. Consórcio Recomendado: CIMATEC Sertão + EMBRAPA / CODEVASF + Produtores Locais / Empresas do Semiárido + Unidade EMBRAPII.", found_areas[[1]])
  } else if (identical(adh$nivel, "Alta")) {
    nivel <- "Alta"
    justificativa <- sprintf("Oportunidade relevante alinhada aos eixos temáticos do Sertão: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Desenvolvimento aplicado em %s. Consórcio Recomendado: CIMATEC Sertão + Cooperativa Agrícola / Empresa Regional + Agência de Fomento.", found_areas[[1]])
  } else if (identical(adh$nivel, "Média")) {
    nivel <- "Média"
    justificativa <- sprintf("Oportunidade com aderência tangencial em %s.", found_areas[[1]])
    ideia <- NA_character_
  } else {
    nivel <- "Baixa"
    justificativa <- if (length(found_areas)) sprintf("Oportunidade com menção isolada a %s (%s), insuficiente para aderência ao núcleo.", found_areas[[1]], paste(adh$termos, collapse = ", ")) else "Oportunidade sem conexão direta identificada com as áreas focais do CIMATEC Sertão."
    ideia <- NA_character_
  }
  
  list(
    aderencia_sertao_nivel = nivel,
    aderencia_sertao_score = adh$score,
    aderencia_sertao_justificativa = justificativa,
    ideia_projeto_sertao = ideia
  )
}

# ─── Avaliador de Aderência Científico-Tecnológica: CIMATEC Aeroespacial ─────────────────

PROMPT_AEROESPACIAL <- "
Você é um especialista sênior em fomento de PD&I para o setor Aeroespacial, Defesa, VANTs e Tecnologias Espaciais.
Avalie a seguinte oportunidade de fomento para o campus SENAI CIMATEC Aeroespacial, focado nas seguintes áreas:
1. VANTs, Drones & Sistemas Não-Tripulados (autonomia, sensoriamento remoto, controle, enxames);
2. Satélites, Cargas Úteis & Aplicações Espaciais (CubeSats, nanossatélites, observação da Terra, telemetria);
3. Propulsão Aeroespacial & Lançadores (motores-foguete, combustíveis verdes, Centro de Lançamento de Alcântara);
4. Aviônica, Sensores, Radares & Guerra Eletrônica (sistemas embarcados de bordo, optrônica, RF, detecção);
5. eVTOL & Mobilidade Aérea Avançada (veículos elétricos aéreos urbanos, gestão de espaço aéreo não-tripulado);
6. Materiais Compostos & Estruturas Aeronáuticas (fibras de carbono, ligas leves, aerodinâmica e ensaios estruturais);
7. Defesa Nacional & Forças Armadas (FAB, DCTA, Marinha, Exército, tecnologias duplas/dual-use e soberania).

Retorne EXCLUSIVAMENTE um objeto JSON válido no seguinte formato:
{
  \"aderencia_aero_nivel\": \"Muito alta\" | \"Alta\" | \"Média\" | \"Baixa\",
  \"aderencia_aero_justificativa\": \"Explicação objetiva de 1 a 3 frases sobre a conexão com o CIMATEC Aeroespacial.\",
  \"ideia_projeto_aero\": \"Sugestão prática de conceito de projeto e consórcio (ex: ICT + Embraer/FAB/DCTA + EMBRAPII + CIMATEC Aeroespacial). Retorne null se aderência for Média ou Baixa.\"
}

=== OPORTUNIDADE ===
"

evaluate_aero_adherence <- function(titulo, descricao, texto_bruto = "", entidade = "", use_ai = TRUE, log_path = NULL, conn = NULL) {
  full_text <- paste(titulo %||% "", descricao %||% "", texto_bruto %||% "", entidade %||% "")
  # Heurística: SOMENTE título + resumo (o texto bruto traz menus/rodapés que geram falsos positivos)
  norm_text <- adherence_heuristic_text(titulo, descricao)
  
  if (use_ai && ai_available()) {
    prompt <- paste0(PROMPT_AEROESPACIAL, trim_for_ai(full_text, max_chars = 6000))
    raw_resp <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
    if (!is.null(raw_resp)) {
      parsed <- tryCatch(jsonlite::fromJSON(raw_resp, simplifyVector = TRUE), error = function(e) NULL)
      if (!is.null(parsed) && !is.null(parsed$aderencia_aero_nivel)) {
        return(list(
          aderencia_aero_nivel = parsed$aderencia_aero_nivel,
          aderencia_aero_justificativa = parsed$aderencia_aero_justificativa %||% "Oportunidade analisada pela IA com conexão ao CIMATEC Aeroespacial.",
          ideia_projeto_aero = parsed$ideia_projeto_aero %||% NA_character_
        ))
      }
    }
  }
  
  kw_vant <- c("vant", "drone", "rpas", "aeronave nao tripulada", "uav", "voo autonomo", "enxame de drones")
  kw_espaco <- c("satelite", "cubesat", "nanossatelite", "espacial", "carga util", "payload", "orbita", "astronom", "astrofisic", "alcantara", "inpe", "aeb")
  kw_propulsao <- c("propulsao", "foguete", "lancador", "motor aeronautico", "combustao", "empuxo")
  kw_avionica <- c("avionica", "radar", "sensor embarcado", "telemetria", "navegacao aerea", "guerra eletronica", "optronica")
  kw_evtol <- c("evtol", "mobilidade aerea", "aeroespacial", "aeronautic", "aeronave", "aviao", "helicoptero", "asa fixa", "rotativo")
  kw_materiais <- c("compostos aeronauticos", "fibra de carbono", "aeroestrutura", "aerodinamica", "fuselagem", "ensaio em voo")
  kw_defesa <- c("defesa", "forca aerea", "fab", "dcta", "militar", "forcas armadas", "soberania aeroespacial", "dual-use")
  
  check_hits <- function(kws) adherence_kw_hits(kws, norm_text)
  
  hits_vant <- check_hits(kw_vant)
  hits_espaco <- check_hits(kw_espaco)
  hits_propulsao <- check_hits(kw_propulsao)
  hits_avionica <- check_hits(kw_avionica)
  hits_evtol <- check_hits(kw_evtol)
  hits_materiais <- check_hits(kw_materiais)
  hits_defesa <- check_hits(kw_defesa)
  
  total_hits <- sum(c(hits_vant, hits_espaco, hits_propulsao, hits_avionica, hits_evtol, hits_materiais, hits_defesa))
  
  found_areas <- character()
  if (hits_vant) found_areas <- c(found_areas, "VANTs & Drones")
  if (hits_espaco) found_areas <- c(found_areas, "Satélites & Espaço")
  if (hits_propulsao) found_areas <- c(found_areas, "Propulsão Aeroespacial")
  if (hits_avionica) found_areas <- c(found_areas, "Aviônica & Radares")
  if (hits_evtol) found_areas <- c(found_areas, "eVTOL & Aviação Avançada")
  if (hits_materiais) found_areas <- c(found_areas, "Materiais Aeronáuticos")
  if (hits_defesa) found_areas <- c(found_areas, "Defesa & Forças Armadas")
  
  adh <- adherence_score_from_kws(list(kw_vant, kw_espaco, kw_propulsao, kw_avionica, kw_evtol, kw_materiais, kw_defesa), norm_text, titulo, combo = ((hits_vant && hits_defesa) || (hits_espaco && hits_propulsao)))
  if (identical(adh$nivel, "Muito alta")) {
    nivel <- "Muito alta"
    justificativa <- sprintf("Forte aderência direta às competências do CIMATEC Aeroespacial nas áreas: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Solução de ponta em %s. Consórcio Recomendado: CIMATEC Aeroespacial + Indústria Aeroespacial/Defesa + Força Aérea (FAB/DCTA) + Unidade EMBRAPII.", found_areas[[1]])
  } else if (identical(adh$nivel, "Alta")) {
    nivel <- "Alta"
    justificativa <- sprintf("Oportunidade relevante alinhada a temas aeroespaciais: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Desenvolvimento de tecnologia aplicada em %s. Consórcio Recomendado: CIMATEC Aeroespacial + Empresa de Base Tecnológica + Agência Espacial/Setorial.", found_areas[[1]])
  } else if (identical(adh$nivel, "Média")) {
    nivel <- "Média"
    justificativa <- sprintf("Oportunidade com potencial aderência em %s.", found_areas[[1]])
    ideia <- NA_character_
  } else {
    nivel <- "Baixa"
    justificativa <- if (length(found_areas)) sprintf("Oportunidade com menção isolada a %s (%s), insuficiente para aderência ao núcleo.", found_areas[[1]], paste(adh$termos, collapse = ", ")) else "Oportunidade sem conexão direta identificada com o setor Aeroespacial e de Defesa."
    ideia <- NA_character_
  }
  
  list(
    aderencia_aero_nivel = nivel,
    aderencia_aero_score = adh$score,
    aderencia_aero_justificativa = justificativa,
    ideia_projeto_aero = ideia
  )
}

# ─── Avaliador de Aderência Científico-Tecnológica: CIMATEC Digital ──────────────────────

PROMPT_DIGITAL <- "
Você é um especialista sênior em fomento de PD&I para TIC, Inteligência Artificial, Cibersegurança e HPC.
Avalie a seguinte oportunidade de fomento para o campus SENAI CIMATEC Digital, focado nas seguintes áreas:
1. Inteligência Artificial & Machine Learning (LLMs, visão computacional, aprendizado profundo, IA generativa);
2. Cibersegurança & Defesa Cibernética (criptografia, auditoria, segurança de redes e infraestruturas críticas);
3. Computação de Alto Desempenho (HPC) & Supercomputação (clusters, processamento massivo, GPUs, nuvem científica);
4. Tecnologias Quânticas & Sensores Quânticos (algoritmos quânticos, comunicações quânticas, pós-quântica);
5. Internet das Coisas (IoT) & Redes Avançadas (5G/6G, sensores inteligentes, telemetria em tempo real);
6. Gêmeos Digitais & Cidades Inteligentes (simulações dinâmicas, mobilidade urbana inteligente, smart cities);
7. Engenharia de Software Crítico & Governança de Dados (plataformas distribuídas, confiabilidade, ética em IA).

Retorne EXCLUSIVAMENTE um objeto JSON válido no seguinte formato:
{
  \"aderencia_digital_nivel\": \"Muito alta\" | \"Alta\" | \"Média\" | \"Baixa\",
  \"aderencia_digital_justificativa\": \"Explicação objetiva de 1 a 3 frases sobre a conexão com o CIMATEC Digital.\",
  \"ideia_projeto_digital\": \"Sugestão prática de conceito de projeto e consórcio (ex: ICT + Big Tech/Empresa de Software + EMBRAPII + CIMATEC Digital). Retorne null se aderência for Média ou Baixa.\"
}

=== OPORTUNIDADE ===
"

evaluate_digital_adherence <- function(titulo, descricao, texto_bruto = "", entidade = "", use_ai = TRUE, log_path = NULL, conn = NULL) {
  full_text <- paste(titulo %||% "", descricao %||% "", texto_bruto %||% "", entidade %||% "")
  # Heurística: SOMENTE título + resumo (o texto bruto traz menus/rodapés que geram falsos positivos)
  norm_text <- adherence_heuristic_text(titulo, descricao)
  
  if (use_ai && ai_available()) {
    prompt <- paste0(PROMPT_DIGITAL, trim_for_ai(full_text, max_chars = 6000))
    raw_resp <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
    if (!is.null(raw_resp)) {
      parsed <- tryCatch(jsonlite::fromJSON(raw_resp, simplifyVector = TRUE), error = function(e) NULL)
      if (!is.null(parsed) && !is.null(parsed$aderencia_digital_nivel)) {
        return(list(
          aderencia_digital_nivel = parsed$aderencia_digital_nivel,
          aderencia_digital_justificativa = parsed$aderencia_digital_justificativa %||% "Oportunidade analisada pela IA com conexão ao CIMATEC Digital.",
          ideia_projeto_digital = parsed$ideia_projeto_digital %||% NA_character_
        ))
      }
    }
  }
  
  kw_ia <- c("inteligencia artificial", "machine learning", "deep learning", "aprendizado de maquina", "redes neurais", "visao computacional", "processamento de linguagem natural", "llm", "ia generativa")
  kw_cyber <- c("ciberseguranca", "cyber", "seguranca da informacao", "criptografia", "defesa cibernetica", "vulnerabilidade", "malware", "lgpd", "privacidade de dados")
  kw_hpc <- c("supercomput", "hpc", "alto desempenho", "cluster", "gpu", "processamento paralelo", "computacao em nuvem", "cloud computing", "ogbon")
  kw_quant <- c("quantica", "quantum", "pos-quantica", "algoritmo quantico", "computacao quantica")
  kw_iot <- c("iot", "internet das coisas", "sensores inteligentes", "5g", "6g", "conectividade avancada", "telemetria digital")
  kw_software <- c("software", "banco de dados", "big data", "analytics", "gemeo digital", "digital twin", "plataforma digital", "transformacao digital", "ti", "tic")
  
  check_hits <- function(kws) adherence_kw_hits(kws, norm_text)
  
  hits_ia <- check_hits(kw_ia)
  hits_cyber <- check_hits(kw_cyber)
  hits_hpc <- check_hits(kw_hpc)
  hits_quant <- check_hits(kw_quant)
  hits_iot <- check_hits(kw_iot)
  hits_software <- check_hits(kw_software)
  
  total_hits <- sum(c(hits_ia, hits_cyber, hits_hpc, hits_quant, hits_iot, hits_software))
  
  found_areas <- character()
  if (hits_ia) found_areas <- c(found_areas, "Inteligência Artificial & ML")
  if (hits_cyber) found_areas <- c(found_areas, "Cibersegurança & Defesa Cibernética")
  if (hits_hpc) found_areas <- c(found_areas, "HPC & Supercomputação")
  if (hits_quant) found_areas <- c(found_areas, "Tecnologias Quânticas")
  if (hits_iot) found_areas <- c(found_areas, "IoT & Conectividade 5G/6G")
  if (hits_software) found_areas <- c(found_areas, "Software & Gêmeos Digitais")
  
  adh <- adherence_score_from_kws(list(kw_ia, kw_cyber, kw_hpc, kw_quant, kw_iot, kw_software), norm_text, titulo, combo = ((hits_ia && hits_hpc) || (hits_ia && hits_cyber)))
  if (identical(adh$nivel, "Muito alta")) {
    nivel <- "Muito alta"
    justificativa <- sprintf("Forte aderência direta ao ecossistema do CIMATEC Digital nas áreas: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Plataforma avançada de %s. Consórcio Recomendado: CIMATEC Digital (Supercomputador Ogbon) + Empresa de Tecnologia / Telecom + Unidade EMBRAPII.", found_areas[[1]])
  } else if (identical(adh$nivel, "Alta")) {
    nivel <- "Alta"
    justificativa <- sprintf("Oportunidade relevante alinhada aos eixos de TIC e inovação digital: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Solução tecnológica em %s. Consórcio Recomendado: CIMATEC Digital + Startup / Empresa Usuária + Fomento à Inovação Tecnológica.", found_areas[[1]])
  } else if (identical(adh$nivel, "Média")) {
    nivel <- "Média"
    justificativa <- sprintf("Oportunidade com aderência digital pontual em %s.", found_areas[[1]])
    ideia <- NA_character_
  } else {
    nivel <- "Baixa"
    justificativa <- if (length(found_areas)) sprintf("Oportunidade com menção isolada a %s (%s), insuficiente para aderência ao núcleo.", found_areas[[1]], paste(adh$termos, collapse = ", ")) else "Oportunidade sem conexão direta identificada com temas de TIC e tecnologia digital."
    ideia <- NA_character_
  }
  
  list(
    aderencia_digital_nivel = nivel,
    aderencia_digital_score = adh$score,
    aderencia_digital_justificativa = justificativa,
    ideia_projeto_digital = ideia
  )
}

# ─── Avaliador de Aderência Científico-Tecnológica: CIMATEC Park & Sede ─────────────────

PROMPT_PARK <- "
Você é um especialista sênior em fomento de PD&I para Manufatura Avançada, Materiais, Eletromobilidade, Química e Indústria 4.0.
Avalie a seguinte oportunidade de fomento para o SENAI CIMATEC Park & Sede (Piatã e Camaçari), focado nas seguintes áreas:
1. Manufatura Avançada & Robótica Industrial (automação 4.0, mecatrônica, linhas inteligentes, soldagem avançada);
2. Materiais Avançados, Nanotecnologia & Polímeros (grafeno, compósitos, síntese e caracterização de novos materiais);
3. Eletromobilidade, Baterias & Indústria Automotiva (veículos elétricos, células de bateria, powertrain, testes veiculares);
4. Química Verde, Biocombustíveis & Petroquímica (processos sustentáveis, catalisadores, transição química, biorrefinarias);
5. Saúde 4.0 & Dispositivos Médicos (biotecnologia médica, próteses, equipamentos biomédicos, ensaios pré-clínicos);
6. Mineração Sustentável, Metalurgia & Siderurgia (descarbonização, aço verde, beneficiamento mineral);
7. Eficiência Energética Industrial & Descarbonização de Plantas (recuperação de energia, CCUS, transição industrial).

Retorne EXCLUSIVAMENTE um objeto JSON válido no seguinte formato:
{
  \"aderencia_park_nivel\": \"Muito alta\" | \"Alta\" | \"Média\" | \"Baixa\",
  \"aderencia_park_justificativa\": \"Explicação objetiva de 1 a 3 frases sobre a conexão com o CIMATEC Park & Sede.\",
  \"ideia_projeto_park\": \"Sugestão prática de conceito de projeto e consórcio (ex: ICT + Montadora/Indústria Química + EMBRAPII + CIMATEC Park). Retorne null se aderência for Média ou Baixa.\"
}

=== OPORTUNIDADE ===
"

evaluate_park_adherence <- function(titulo, descricao, texto_bruto = "", entidade = "", use_ai = TRUE, log_path = NULL, conn = NULL) {
  full_text <- paste(titulo %||% "", descricao %||% "", texto_bruto %||% "", entidade %||% "")
  # Heurística: SOMENTE título + resumo (o texto bruto traz menus/rodapés que geram falsos positivos)
  norm_text <- adherence_heuristic_text(titulo, descricao)
  
  if (use_ai && ai_available()) {
    prompt <- paste0(PROMPT_PARK, trim_for_ai(full_text, max_chars = 6000))
    raw_resp <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
    if (!is.null(raw_resp)) {
      parsed <- tryCatch(jsonlite::fromJSON(raw_resp, simplifyVector = TRUE), error = function(e) NULL)
      if (!is.null(parsed) && !is.null(parsed$aderencia_park_nivel)) {
        return(list(
          aderencia_park_nivel = parsed$aderencia_park_nivel,
          aderencia_park_justificativa = parsed$aderencia_park_justificativa %||% "Oportunidade analisada pela IA com conexão ao CIMATEC Park & Sede.",
          ideia_projeto_park = parsed$ideia_projeto_park %||% NA_character_
        ))
      }
    }
  }
  
  kw_manuf <- c("manufatura", "robotica", "automacao industrial", "usinagem", "conformacao", "fabrica inteligente", "industria 4.0", "mecatronica", "soldagem")
  kw_materiais <- c("nanomateriais", "polimeros", "compositos", "grafeno", "metalurgia", "ligas metalicas", "materiais avancados", "caracterizacao de materiais")
  kw_auto <- c("automotivo", "veiculo eletrico", "eletromobilidade", "bateria", "powertrain", "combustao", "celula de combustivel", "veicular")
  kw_quimica <- c("quimica verde", "petroquimica", "biocombustivel", "catalisador", "biorrefinaria", "etanol", "biodiesel", "quimica fina")
  kw_saude <- c("dispositivo medico", "equipamentos medicos", "farmaceutic", "saude 4.0", "protese", "biomedic", "ensaio clinico")
  kw_mineracao <- c("mineracao", "rejeitos", "siderurgia", "metalurgic", "aco verde", "beneficiamento mineral")
  kw_energia_ind <- c("descarbonizacao industrial", "eficiencia energetica", "transicao industrial", "captura de carbono", "ccus", "calor residual")
  
  check_hits <- function(kws) adherence_kw_hits(kws, norm_text)
  
  hits_manuf <- check_hits(kw_manuf)
  hits_materiais <- check_hits(kw_materiais)
  hits_auto <- check_hits(kw_auto)
  hits_quimica <- check_hits(kw_quimica)
  hits_saude <- check_hits(kw_saude)
  hits_mineracao <- check_hits(kw_mineracao)
  hits_energia_ind <- check_hits(kw_energia_ind)
  
  total_hits <- sum(c(hits_manuf, hits_materiais, hits_auto, hits_quimica, hits_saude, hits_mineracao, hits_energia_ind))
  
  found_areas <- character()
  if (hits_manuf) found_areas <- c(found_areas, "Manufatura Avançada & Robótica")
  if (hits_materiais) found_areas <- c(found_areas, "Materiais Avançados & Nanotecnologia")
  if (hits_auto) found_areas <- c(found_areas, "Eletromobilidade & Automotivo")
  if (hits_quimica) found_areas <- c(found_areas, "Química Verde & Biocombustíveis")
  if (hits_saude) found_areas <- c(found_areas, "Saúde 4.0 & Dispositivos Médicos")
  if (hits_mineracao) found_areas <- c(found_areas, "Mineração & Siderurgia Sustentável")
  if (hits_energia_ind) found_areas <- c(found_areas, "Eficiência Energética Industrial")
  
  adh <- adherence_score_from_kws(list(kw_manuf, kw_materiais, kw_auto, kw_quimica, kw_saude, kw_mineracao, kw_energia_ind), norm_text, titulo, combo = ((hits_manuf && hits_materiais) || (hits_auto && hits_materiais)))
  if (identical(adh$nivel, "Muito alta")) {
    nivel <- "Muito alta"
    justificativa <- sprintf("Forte aderência direta à infraestrutura de ponta do CIMATEC Park & Sede nas áreas: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Planta piloto ou protótipo industrial em %s. Consórcio Recomendado: CIMATEC Park + Indústria Âncora do Polo + EMBRAPII + Finep/BNDES.", found_areas[[1]])
  } else if (identical(adh$nivel, "Alta")) {
    nivel <- "Alta"
    justificativa <- sprintf("Oportunidade relevante alinhada à matriz industrial e laboratórios do Park: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Desenvolvimento de processo/produto em %s. Consórcio Recomendado: CIMATEC Park + Empresa Parceira + Linha de Fomento Industrial.", found_areas[[1]])
  } else if (identical(adh$nivel, "Média")) {
    nivel <- "Média"
    justificativa <- sprintf("Oportunidade com potencial sinergia em %s.", found_areas[[1]])
    ideia <- NA_character_
  } else {
    nivel <- "Baixa"
    justificativa <- if (length(found_areas)) sprintf("Oportunidade com menção isolada a %s (%s), insuficiente para aderência ao núcleo.", found_areas[[1]], paste(adh$termos, collapse = ", ")) else "Oportunidade sem conexão direta identificada com as linhas industriais do CIMATEC Park & Sede."
    ideia <- NA_character_
  }
  
  list(
    aderencia_park_nivel = nivel,
    aderencia_park_score = adh$score,
    aderencia_park_justificativa = justificativa,
    ideia_projeto_park = ideia
  )
}

# ─── Avaliador de Aderência Científico-Tecnológica: Startups & Inovação Aberta ───

PROMPT_STARTUPS <- "
Você é um especialista sênior em ecossistemas de inovação, fomento a Startups, Deep Techs, Inovação Aberta e Venture Capital.
Avalie a seguinte oportunidade de fomento para o ecossistema de Startups & MPEs do SENAI CIMATEC, focado nas seguintes áreas:
1. Startups de Base Tecnológica & Deep Techs (hard tech, biotecnologia, nanotecnologia, novos materiais, IA aplicada);
2. Aceleração, Incubação & Escalonamento (Scale-ups, programas de aceleração, ideação à tração);
3. Inovação Aberta & Desafios Corporativos (Open Innovation, parcerias ICT + Startups + Grandes Empresas);
4. Venture Capital, Capital Semente & Investimento Anjo (rodadas de investimento, corporate venture capital - CVC);
5. Micro e Pequenas Empresas (MPEs) Inovadoras & Spin-offs Acadêmicas (PIPE FAPESP, Centelha, Catalisa ICT, Sebrae, Tecnova);
6. Prototipagem Ágil, MVPs & Validação de Mercado (Living Labs, sandboxes regulatórios, PoCs, validação tecnológica);
7. Internacionalização de Startups & Soft Landing (programas globais, missões internacionais, expansão de mercado).

Retorne EXCLUSIVAMENTE um objeto JSON válido no seguinte formato:
{
  \"aderencia_startups_nivel\": \"Muito alta\" | \"Alta\" | \"Média\" | \"Baixa\",
  \"aderencia_startups_justificativa\": \"Explicação objetiva de 1 a 3 frases sobre a conexão com o ecossistema de Startups e Inovação Aberta.\",
  \"ideia_projeto_startups\": \"Sugestão prática de conceito de projeto/programa (ex: Startup Deep Tech + SENAI CIMATEC + Grande Empresa Âncora + Fomento PIPE/Centelha). Retorne null se aderência for Média ou Baixa.\"
}

=== OPORTUNIDADE ===
"

evaluate_startups_adherence <- function(titulo, descricao, texto_bruto = "", entidade = "", use_ai = TRUE, log_path = NULL, conn = NULL) {
  full_text <- paste(titulo %||% "", descricao %||% "", texto_bruto %||% "", entidade %||% "")
  # Heurística: SOMENTE título + resumo (o texto bruto traz menus/rodapés que geram falsos positivos)
  norm_text <- adherence_heuristic_text(titulo, descricao)
  
  if (use_ai && ai_available()) {
    prompt <- paste0(PROMPT_STARTUPS, trim_for_ai(full_text, max_chars = 6000))
    raw_resp <- ai_request_with_fallback(prompt, log_path = log_path, conn = conn)
    if (!is.null(raw_resp)) {
      parsed <- tryCatch(jsonlite::fromJSON(raw_resp, simplifyVector = TRUE), error = function(e) NULL)
      if (!is.null(parsed) && !is.null(parsed$aderencia_startups_nivel)) {
        return(list(
          aderencia_startups_nivel = parsed$aderencia_startups_nivel,
          aderencia_startups_justificativa = parsed$aderencia_startups_justificativa %||% "Oportunidade analisada pela IA com conexão ao ecossistema de Startups e Inovação Aberta.",
          ideia_projeto_startups = parsed$ideia_projeto_startups %||% NA_character_
        ))
      }
    }
  }
  
  kw_deeptech <- c("deeptech", "deep tech", "base tecnologica", "spin-off", "spinoff", "patente", "hardtech", "transferencia de tecnologia", "propriedade intelectual")
  kw_aceleracao <- c("startup", "startups", "aceleracao", "incubacao", "incubadora", "aceleradora", "scale-up", "scaleup", "tracionamento", "mentoria", "pitch", "demoday", "demo day")
  kw_open_innov <- c("inovacao aberta", "open innovation", "desafio corporativo", "corporate venture", "cvc", "matchmaking", "co-criacao", "desafios de inovacao")
  kw_investimento <- c("venture capital", "capital semente", "seed", "investimento anjo", "investidor anjo", "equity", "rodada de investimento", "fundo de investimento", "anjo")
  kw_mpe_programas <- c("mpe", "mpe inovadora", "microempresa", "pequeno porte", "pequena empresa", "catalisa", "pipe", "centelha", "sinapse", "tecnova", "sebrae", "finep startup")
  kw_mvp_labs <- c("mvp", "prototipagem", "living lab", "sandbox", "poc", "prova de conceito", "validacao de mercado", "ambiente de teste")
  kw_internacional <- c("internacionalizacao", "soft landing", "missao internacional", "expansao global", "mercado global")
  
  check_hits <- function(kws) adherence_kw_hits(kws, norm_text)
  
  hits_deeptech <- check_hits(kw_deeptech)
  hits_aceleracao <- check_hits(kw_aceleracao)
  hits_open_innov <- check_hits(kw_open_innov)
  hits_investimento <- check_hits(kw_investimento)
  hits_mpe <- check_hits(kw_mpe_programas)
  hits_mvp <- check_hits(kw_mvp_labs)
  hits_internacional <- check_hits(kw_internacional)
  
  total_hits <- sum(c(hits_deeptech, hits_aceleracao, hits_open_innov, hits_investimento, hits_mpe, hits_mvp, hits_internacional))
  
  found_areas <- character()
  if (hits_deeptech) found_areas <- c(found_areas, "Startups de Base Tecnológica & Deep Techs")
  if (hits_aceleracao) found_areas <- c(found_areas, "Aceleração, Incubação & Escalonamento")
  if (hits_open_innov) found_areas <- c(found_areas, "Inovação Aberta & Desafios Corporativos")
  if (hits_investimento) found_areas <- c(found_areas, "Venture Capital & Investimento Anjo")
  if (hits_mpe) found_areas <- c(found_areas, "MPEs Inovadoras & Spin-offs")
  if (hits_mvp) found_areas <- c(found_areas, "Prototipagem Ágil & Validação de Mercado (PoC/MVP)")
  if (hits_internacional) found_areas <- c(found_areas, "Internacionalização de Startups")
  
  adh <- adherence_score_from_kws(list(kw_deeptech, kw_aceleracao, kw_open_innov, kw_investimento, kw_mpe_programas, kw_mvp_labs, kw_internacional), norm_text, titulo, combo = ((hits_aceleracao && (hits_mpe || hits_open_innov)) || (hits_deeptech && hits_aceleracao)))
  if (identical(adh$nivel, "Muito alta")) {
    nivel <- "Muito alta"
    justificativa <- sprintf("Forte aderência direta a programas de aceleração, venture e apoio a Startups/MPEs nas áreas: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Programa de aceleração tecnológica ou PoC em %s. Consórcio Recomendado: Startup Inovadora + SENAI CIMATEC + Grande Empresa Parceira + Fomento Sebrae/Finep.", found_areas[[1]])
  } else if (identical(adh$nivel, "Alta")) {
    nivel <- "Alta"
    justificativa <- sprintf("Oportunidade relevante para o ecossistema de Startups e empresas emergentes: %s.", paste(found_areas, collapse = ", "))
    ideia <- sprintf("Projeto: Desenvolvimento de MVP/solução inovadora em %s. Consórcio Recomendado: Startup de Base Tecnológica + SENAI CIMATEC + Linha de Subvenção.", found_areas[[1]])
  } else if (identical(adh$nivel, "Média")) {
    nivel <- "Média"
    justificativa <- sprintf("Oportunidade com potencial sinergia para Startups em %s.", found_areas[[1]])
    ideia <- NA_character_
  } else {
    nivel <- "Baixa"
    justificativa <- if (length(found_areas)) sprintf("Oportunidade com menção isolada a %s (%s), insuficiente para aderência ao núcleo.", found_areas[[1]], paste(adh$termos, collapse = ", ")) else "Oportunidade sem conexão direta identificada com fomento a Startups ou inovação aberta."
    ideia <- NA_character_
  }
  
  list(
    aderencia_startups_nivel = nivel,
    aderencia_startups_score = adh$score,
    aderencia_startups_justificativa = justificativa,
    ideia_projeto_startups = ideia
  )
}




# ─── Núcleos e campus: fonte única de verdade ─────────────────────────────────
# O campus exibido/filtrado passa a ser DERIVADO dos níveis de aderência dos núcleos,
# com a mesma régua usada nas abas: um edital pertence a um campus quando a aderência
# ao núcleo correspondente é "Média" ou superior. Assim, a aba, o selo de campus e
# o nível nunca se contradizem, e registros antigos são recalculados a cada carga.
NUCLEUS_CAMPUS_MAP <- c(naval = "Mar", sertao = "Sertão", aero = "Aeroespacial",
                        digital = "Digital", park = "Sede e Park", startups = "Startups")
CAMPUS_MIN_LEVEL <- c("Média", "Alta", "Muito alta")

.nucleus_evaluators <- function() {
  list(
    naval = list(fn = evaluate_naval_offshore_adherence, ideia = "ideia_projeto_consorcio"),
    sertao = list(fn = evaluate_sertao_adherence, ideia = "ideia_projeto_sertao"),
    aero = list(fn = evaluate_aero_adherence, ideia = "ideia_projeto_aero"),
    digital = list(fn = evaluate_digital_adherence, ideia = "ideia_projeto_digital"),
    park = list(fn = evaluate_park_adherence, ideia = "ideia_projeto_park"),
    startups = list(fn = evaluate_startups_adherence, ideia = "ideia_projeto_startups")
  )
}

ensure_nucleus_levels <- function(df) {
  if (is.null(df) || nrow(df) == 0L) return(df)
  col <- function(nm) if (nm %in% names(df)) as.character(df[[nm]]) else rep(NA_character_, nrow(df))
  evs <- .nucleus_evaluators()
  for (n in names(evs)) {
    lv <- paste0("aderencia_", n, "_nivel"); js <- paste0("aderencia_", n, "_justificativa")
    sc <- paste0("aderencia_", n, "_score"); id <- evs[[n]]$ideia
    lv_v <- col(lv); js_v <- col(js); id_v <- col(id)
    sc_v <- if (sc %in% names(df)) suppressWarnings(as.numeric(df[[sc]])) else rep(NA_real_, nrow(df))
    redo <- is.na(lv_v) | !nzchar(lv_v) | grepl(ADHERENCE_HEURISTIC_PATTERN, js_v %||% "")
    redo[is.na(redo)] <- TRUE
    for (i in which(redo)) {
      r <- evs[[n]]$fn(titulo = df$titulo[[i]], descricao = df$descricao_resumida[[i]] %||% "",
                       entidade = df$entidade[[i]] %||% "", use_ai = FALSE)
      lv_v[[i]] <- r[[paste0("aderencia_", n, "_nivel")]] %||% "Baixa"
      js_v[[i]] <- r[[paste0("aderencia_", n, "_justificativa")]] %||% ""
      sc_v[[i]] <- r[[paste0("aderencia_", n, "_score")]] %||% NA_real_
      id_v[[i]] <- r[[id]] %||% NA_character_
    }
    df[[lv]] <- lv_v; df[[js]] <- js_v; df[[sc]] <- sc_v; df[[id]] <- id_v
  }
  df
}

derive_campus_from_levels <- function(df) {
  if (is.null(df) || nrow(df) == 0L) return(character())
  vapply(seq_len(nrow(df)), function(i) {
    cps <- NUCLEUS_CAMPUS_MAP[vapply(names(NUCLEUS_CAMPUS_MAP), function(n) {
      v <- df[[paste0("aderencia_", n, "_nivel")]][[i]]
      !is.null(v) && !is.na(v) && v %in% CAMPUS_MIN_LEVEL
    }, logical(1))]
    if (length(cps)) paste(unname(cps), collapse = "; ") else NA_character_
  }, character(1))
}
