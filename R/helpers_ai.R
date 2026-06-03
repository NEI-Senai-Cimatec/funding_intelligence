
gemini_available <- function() nzchar(Sys.getenv("GEMINI_API_KEY"))

trim_for_ai <- function(text, max_chars = 12000) {
  text <- normalize_ws(text %||% "")
  if (nchar(text) <= max_chars) return(text)
  substr(text, 1, max_chars)
}

gemini_request <- function(prompt, model = "gemini-2.0-flash-lite", timeout_sec = 45, retries = 2, log_path = NULL) {
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

ai_extract_fields <- function(text, current = list(), log_path = NULL) {
  if (!gemini_available()) return(list())
  prompt <- paste(
    "Você receberá um trecho de edital ou oportunidade de financiamento.",
    "Responda SOMENTE em JSON válido com os campos:",
    "titulo_limpo, resumo, elegibilidade, area_tematica, tipo_oportunidade, status_oportunidade, idioma, data_limite, data_publicacao, observacoes.",
    "Não invente informações. Use null quando não souber.",
    "Contexto parcial já extraído:", jsonlite::toJSON(current, auto_unbox = TRUE, null = "null"),
    "Texto:", trim_for_ai(text)
  )
  raw <- gemini_request(prompt, log_path = log_path)
  if (is.null(raw)) return(list())

  parsed_outer <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed_outer)) return(list())
  candidate_text <- tryCatch(parsed_outer$candidates[[1]]$content$parts[[1]]$text %||% raw, error = function(e) raw)
  parsed <- tryCatch(jsonlite::fromJSON(candidate_text, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(parsed)) return(list())
  as.list(parsed)
}
