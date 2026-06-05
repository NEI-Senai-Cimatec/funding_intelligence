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
    } else if (provider == "anthropic") {
      model <- "claude-3-5-haiku-latest"
    } else if (provider == "groq") {
      model <- "llama-3.3-70b-versatile"
    } else if (provider == "openrouter") {
      model <- "google/gemini-2.5-flash"
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

ai_available <- function() {
  cfg <- get_ai_config()
  nzchar(cfg$provider) && nzchar(cfg$api_key)
}

validate_ai_config <- function() {
  cfg <- get_ai_config()
  is_ok <- nzchar(cfg$provider) && nzchar(cfg$api_key)
  if (!is_ok) {
    message("----------------------------------------------------------------------")
    message("AVISO: Nenhuma chave de API de IA (Gemini, OpenAI, Anthropic, Groq, OpenRouter, DeepSeek) configurada!")
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
    max_chars <- as.numeric(Sys.getenv("AI_MAX_CHARS", "6000"))
    if (is.na(max_chars) || max_chars <= 0) max_chars <- 6000
  }
  text <- normalize_ws(text %||% "")
  if (nchar(text) <= max_chars) return(text)
  substr(text, 1, max_chars)
}

ai_request <- function(prompt, timeout_sec = 45, retries = 2, log_path = NULL) {
  cfg <- get_ai_config()
  if (!nzchar(cfg$provider) || !nzchar(cfg$api_key)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", "Configuração de IA incompleta ou ausente. IA desabilitada.")
    return(NULL)
  }

  # Atraso inteligente para evitar Rate Limits de Tokens por Minuto (TPM) na Groq (plano gratuito)
  if (cfg$provider == "groq") {
    delay <- as.numeric(Sys.getenv("GROQ_RATE_DELAY", "6"))
    if (is.na(delay) || delay < 0) delay <- 6
    if (delay > 0) Sys.sleep(delay)
  }

  req <- NULL
  
  if (cfg$provider == "gemini") {
    url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", cfg$model, cfg$api_key)
    req <- httr2::request(url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(`Content-Type` = "application/json") |>
      httr2::req_body_json(list(
        contents = list(list(parts = list(list(text = prompt)))),
        generationConfig = list(temperature = 0.1, responseMimeType = "application/json")
      ), auto_unbox = TRUE)
  } else if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds")) {
    url <- cfg$api_url
    req <- httr2::request(url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(
        `Content-Type` = "application/json",
        `Authorization` = sprintf("Bearer %s", cfg$api_key)
      ) |>
      httr2::req_body_json(list(
        model = cfg$model,
        messages = list(list(role = "user", content = prompt)),
        temperature = 0.1,
        response_format = list(type = "json_object")
      ), auto_unbox = TRUE)
  } else if (cfg$provider == "anthropic") {
    url <- cfg$api_url
    req <- httr2::request(url) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_headers(
        `Content-Type` = "application/json",
        `x-api-key` = cfg$api_key,
        `anthropic-version` = "2023-06-01"
      ) |>
      httr2::req_body_json(list(
        model = cfg$model,
        messages = list(list(role = "user", content = prompt)),
        max_tokens = 4000,
        temperature = 0.1
      ), auto_unbox = TRUE)
  } else {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Provedor de IA não suportado: %s", cfg$provider))
    return(NULL)
  }

  for (i in seq_len(retries + 1)) {
    resp <- tryCatch({
      httr2::req_perform(req)
    }, error = function(e) {
      if (!is.null(e$response) && httr2::resp_status(e$response) == 429) {
        structure(e, is_429 = TRUE)
      } else {
        e
      }
    })
    
    if (!inherits(resp, "error")) {
      txt <- try(httr2::resp_body_string(resp), silent = TRUE)
      if (!inherits(txt, "try-error") && nzchar(txt)) {
        parsed_res <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
        if (inherits(parsed_res, "try-error")) next
        
        extracted_text <- NULL
        if (cfg$provider == "gemini") {
          extracted_text <- tryCatch(parsed_res$candidates[[1]]$content$parts[[1]]$text %||% txt, error = function(e) txt)
        } else if (cfg$provider %in% c("openai", "groq", "openrouter", "deepseek", "bluesminds")) {
          extracted_text <- tryCatch(parsed_res$choices[[1]]$message$content %||% txt, error = function(e) txt)
        } else if (cfg$provider == "anthropic") {
          extracted_text <- tryCatch(parsed_res$content[[1]]$text %||% txt, error = function(e) txt)
        }
        
        if (!is.null(extracted_text) && nzchar(extracted_text)) {
          return(extracted_text)
        }
      }
    } else {
      if (isTRUE(attr(resp, "is_429"))) {
        if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Rate limit (429) atingido na Groq. Aguardando 15s antes da tentativa %d...", i + 1))
        Sys.sleep(15)
      } else {
        Sys.sleep(min(6, i * 2))
      }
    }
  }
  if (!is.null(log_path)) log_write(log_path, "WARN", "Falha ao consultar IA após tentativas.")
  NULL
}

# Skill do Agente: Extração Inicial de Metadados
skill_extract_metadata <- function(text, current_info = list(), log_path = NULL) {
  prompt <- paste(
    "Você é um agente especialista em extração de dados de editais de fomento.",
    "Analise o texto bruto do edital fornecido e extraia as seguintes informações estruturadas.",
    "Retorne OBRIGATORIAMENTE um JSON válido com os seguintes campos:",
    "- titulo_limpo: Título do edital sem caracteres especiais ou abreviações confusas.",
    "- resumo: Um resumo conciso das metas e escopo do edital (máximo 3 parágrafos).",
    "- elegibilidade: Quem pode se candidatar (ex: ICTs, startups, pesquisadores individuais).",
    "- area_tematica: Principais áreas de conhecimento englobadas.",
    "- tipo_oportunidade: Categoria do fomento (ex: edital, grant, fellowship, licitação).",
    "- status_oportunidade: Status atual (aberto, encerrado, futuro).",
    "- idioma: Idioma oficial do edital (pt, en, etc.).",
    "- data_limite: Data máxima de submissão no formato AAAA-MM-DD (ou null se indefinida).",
    "- data_publicacao: Data de publicação no formato AAAA-MM-DD (ou null).",
    "- palavras_chave: Exatamente 5 palavras-chave ou termos separados por vírgula que caracterizam o edital.",
    "- observacoes: Qualquer detalhe ou restrição relevante do edital.",
    "",
    "Contexto primário conhecido:", jsonlite::toJSON(current_info, auto_unbox = TRUE, null = "null"),
    "",
    "Texto do Edital:", trim_for_ai(text)
  )

  raw <- ai_request(prompt, log_path = log_path)
  if (is.null(raw)) return(list())

  parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) return(list())
  as.list(parsed)
}

# Skill do Agente: Auditoria de Controle de Qualidade (Evasão de Alucinações)
skill_verify_metadata <- function(metadata, raw_text, log_path = NULL) {
  if (length(metadata) == 0) return(metadata)

  prompt <- paste(
    "Você é um auditor de controle de qualidade de IA.",
    "Sua tarefa é verificar se as informações extraídas de um edital condizem com o texto original do edital.",
    "Analise as informações abaixo e verifique se há contradições ou 'alucinações' em relação ao texto bruto fornecido.",
    "Preste atenção especial à data_limite e à elegibilidade.",
    "Corrija os valores se necessário e retorne o JSON final corrigido.",
    "",
    "Informações extraídas preliminares:", jsonlite::toJSON(metadata, auto_unbox = TRUE, null = "null"),
    "",
    "Texto bruto do Edital:", trim_for_ai(raw_text)
  )

  raw <- ai_request(prompt, log_path = log_path)
  if (is.null(raw)) return(metadata)

  parsed <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) return(metadata)
  as.list(parsed)
}

# Pipeline do Agente: Executa as skills sequencialmente
ai_extract_fields <- function(text, current = list(), log_path = NULL) {
  if (!ai_available()) return(list())

  # Passo 1: Skill de Extração de Metadados
  extracted <- skill_extract_metadata(text, current, log_path)
  if (length(extracted) == 0) return(list())

  # Passo 2: Skill de Auditoria e Auto-Correção (opcional via AI_VERIFY_METADATA)
  verify_enabled <- !identical(tolower(Sys.getenv("AI_VERIFY_METADATA", "true")), "false")
  if (verify_enabled) {
    extracted <- skill_verify_metadata(extracted, text, log_path)
  }

  extracted
}
