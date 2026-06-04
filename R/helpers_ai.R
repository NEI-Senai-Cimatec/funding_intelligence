# Módulo de Integração com o Agente de IA (Gemini)

gemini_available <- function() nzchar(Sys.getenv("GEMINI_API_KEY"))

validate_gemini_api_key <- function() {
  key_exists <- gemini_available()
  if (!key_exists) {
    message("----------------------------------------------------------------------")
    message("AVISO: A variável de ambiente GEMINI_API_KEY não foi encontrada!")
    message("O processamento com Inteligência Artificial (IA) estará desativado.")
    message("Para habilitar a IA, configure sua chave no arquivo .Renviron:")
    message("GEMINI_API_KEY=\"sua_chave_aqui\"")
    message("----------------------------------------------------------------------")
  }
  key_exists
}

trim_for_ai <- function(text, max_chars = 12000) {
  text <- normalize_ws(text %||% "")
  if (nchar(text) <= max_chars) return(text)
  substr(text, 1, max_chars)
}

gemini_request <- function(prompt, model = "gemini-1.5-flash", timeout_sec = 45, retries = 2, log_path = NULL) {
  key <- Sys.getenv("GEMINI_API_KEY")
  if (!nzchar(key)) {
    if (!is.null(log_path)) log_write(log_path, "WARN", "GEMINI_API_KEY ausente. IA desabilitada para esta execução.")
    return(NULL)
  }

  url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", model, key)
  req <- httr2::request(url) |>
    httr2::req_method("POST") |>
    httr2::req_timeout(timeout_sec) |>
    httr2::req_headers(`Content-Type` = "application/json") |>
    httr2::req_body_json(list(
      contents = list(list(parts = list(list(text = prompt)))),
      generationConfig = list(temperature = 0.1, responseMimeType = "application/json")
    ), auto_unbox = TRUE)

  for (i in seq_len(retries + 1)) {
    resp <- try(httr2::req_perform(req), silent = TRUE)
    if (!inherits(resp, "try-error")) {
      txt <- try(httr2::resp_body_string(resp), silent = TRUE)
      if (!inherits(txt, "try-error") && nzchar(txt)) return(txt)
    }
    Sys.sleep(min(6, i * 2))
  }
  if (!is.null(log_path)) log_write(log_path, "WARN", "Falha ao consultar Gemini após tentativas.")
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

  raw <- gemini_request(prompt, model = "gemini-1.5-flash", log_path = log_path)
  if (is.null(raw)) return(list())

  parsed_outer <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed_outer)) return(list())
  candidate_text <- tryCatch(parsed_outer$candidates[[1]]$content$parts[[1]]$text %||% raw, error = function(e) raw)
  parsed <- tryCatch(jsonlite::fromJSON(candidate_text, simplifyVector = TRUE), error = function(e) NULL)
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

  raw <- gemini_request(prompt, model = "gemini-1.5-flash", log_path = log_path)
  if (is.null(raw)) return(metadata)

  parsed_outer <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed_outer)) return(metadata)
  candidate_text <- tryCatch(parsed_outer$candidates[[1]]$content$parts[[1]]$text %||% raw, error = function(e) raw)
  parsed <- tryCatch(jsonlite::fromJSON(candidate_text, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) return(metadata)
  as.list(parsed)
}

# Pipeline do Agente: Executa as skills sequencialmente
ai_extract_fields <- function(text, current = list(), log_path = NULL) {
  if (!gemini_available()) return(list())

  # Passo 1: Skill de Extração de Metadados
  extracted <- skill_extract_metadata(text, current, log_path)
  if (length(extracted) == 0) return(list())

  # Passo 2: Skill de Auditoria e Auto-Correção
  verified <- skill_verify_metadata(extracted, text, log_path)

  verified
}
