# ─── Motor de Status Derivado (Fonte Única da Verdade) ────────────────────────
# Corrige BUG-01/05/11: o status é rederivado a cada render a partir de
# data_limite / data_abertura, nunca lido do campo congelado status_oportunidade.

status_today <- function() {
  # Data de referência no fuso do Brasil (America/Sao_Paulo), conforme DoD.
  as.Date(lubridate::with_tz(Sys.time(), "America/Sao_Paulo"))
}

derive_status_one <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL) {
  hoje <- if (!is.null(today)) as.Date(today) else status_today()
  dl <- parse_date_safe(data_limite)
  if (length(dl) > 1L) dl <- dl[[1L]]
  ab <- parse_date_safe(data_abertura)
  if (length(ab) > 1L) ab <- ab[[1L]]
  txt <- as.character(texto_bruto %||% "")
  txt <- if (length(txt) > 1L) txt[[1L]] else txt

  if (!is.na(dl)) {
    diff_days <- as.integer(dl - hoje)
    if (!is.na(diff_days) && diff_days < 0) return("encerrado")
    if (!is.na(diff_days) && diff_days <= 14) return("encerrando")
    if (!is.na(ab) && ab > hoje) return("em_breve")
    return("aberto")
  }

  # Fallback heurístico para texto
  txt_norm <- normalize_text(txt)
  if (grepl("encerrad|closed|expired|finalizad", txt_norm)) return("encerrado")
  if (grepl("open|abert|ongoing|em andamento", txt_norm)) return("aberto")
  if (grepl("coming soon|em breve|upcoming", txt_norm)) return("em_breve")
  "desconhecido"
}

derive_status <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL) {
  n <- max(length(data_limite), length(data_abertura), length(texto_bruto), 1L)
  dl <- rep_len(parse_date_safe(data_limite), n)
  ab <- rep_len(parse_date_safe(data_abertura), n)
  txt <- rep_len(as.character(texto_bruto %||% ""), n)
  vapply(seq_len(n), function(i) {
    derive_status_one(dl[[i]], ab[[i]], txt[[i]], today = today)
  }, character(1))
}

derive_status_vec <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL) {
  derive_status(data_limite = data_limite, data_abertura = data_abertura, texto_bruto = texto_bruto, today = today)
}

# Contagem de urgentes (14 dias) para KPI — deriva, nunca lê coluna congelada.
count_urgent_status <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL) {
  st <- derive_status(data_limite, data_abertura, texto_bruto, today = today)
  sum(st %in% "encerrando", na.rm = TRUE)
}

# Rótulo amigável para o enum da UI (derivado).
status_display_label <- function(status) {
  labels <- c(
    "aberto" = "Aberto",
    "encerrando" = "Encerrando",
    "em_breve" = "Em breve",
    "encerrado" = "Encerrado",
    "desconhecido" = "Desconhecido"
  )
  unname(labels[status] %||% tools::toTitleCase(status %||% "Desconhecido"))
}
