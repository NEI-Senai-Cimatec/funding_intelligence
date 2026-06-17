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

ai_available <- function() {
  cfg <- get_ai_config()
  nzchar(cfg$provider) && nzchar(cfg$api_key)
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

ai_request <- function(prompt, timeout_sec = 45, retries = 2, log_path = NULL) {
  cfg <- get_ai_config()
  if (!nzchar(cfg$provider) || !nzchar(cfg$api_key)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", "Configuração de IA incompleta ou ausente. IA desabilitada.")
    return(NULL)
  }

  req <- ai_make_request(prompt, cfg = cfg, timeout_sec = timeout_sec)
  if (is.null(req)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Provedor de IA não suportado ou falha ao criar request para: %s", cfg$provider))
    return(NULL)
  }

  # Configurar retries nativos do httr2 com backoff exponencial + jitter
  req <- req |>
    httr2::req_retry(
      max_tries = retries + 1,
      backoff = function(i) 2^i + stats::runif(1, 0, 1),
      is_transient = function(resp) {
        if (inherits(resp, "error")) return(TRUE)
        status <- tryCatch(httr2::resp_status(resp), error = function(e) 500)
        status == 429 || status >= 500
      }
    )

  resp <- tryCatch({
    httr2::req_perform(req)
  }, error = function(e) {
    if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Erro de rede/timeout na chamada de IA: %s", e$message))
    NULL
  })

  if (is.null(resp)) return(NULL)

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
      return(extracted_text)
    }
  }
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
    req <- ai_make_request(p, cfg = cfg, timeout_sec = timeout_sec)
    if (!is.null(req)) {
      req <- req |>
        httr2::req_retry(
          max_tries = 5,
          backoff = function(i) 2^i + stats::runif(1, 0, 1),
          is_transient = function(resp) {
            if (inherits(resp, "error")) return(TRUE)
            status <- tryCatch(httr2::resp_status(resp), error = function(e) 500)
            status == 429 || status >= 500
          }
        )
    }
    req
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

  for (i in seq_along(valid_indices)) {
    orig_idx <- valid_indices[[i]]
    resp <- resps[[i]]

    if (inherits(resp, "httr2_response")) {
      txt <- try(httr2::resp_body_string(resp), silent = TRUE)
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
    } else {
      err_msg <- if (inherits(resp, "error")) resp$message else "Erro desconhecido"
      if (!is.null(log_path)) log_write(log_path, "WARN", sprintf("Falha na chamada paralela da IA (edital índice %d): %s", orig_idx, err_msg))
    }
  }

  results
}

# Skill do Agente: Extração Inicial de Metadados
skill_extract_metadata <- function(text, current_info = list(), log_path = NULL) {
  prompt <- paste(
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
