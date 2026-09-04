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
      model <- "google/diffusiongemma-26b-a4b-it"
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

translate_to_pt_br <- function(records, log_path = NULL) {
  # Traduz titulos e descricoes de fontes EU para pt-br usando polyglotr (Google Translate)
  # Args:
  #   records: tibble com colunas titulo, descricao_resumida, idioma
  #   log_path: caminho para log opcional
  # Returns:
  #   tibble com titulos e descricoes traduzidos

  if (is.null(records) || nrow(records) == 0) {
    return(records)
  }

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
