# ─── Motor de Status Derivado (Fonte Única da Verdade) ────────────────────────
# Contrato (openspec/changes/brazilian-sources-data-integrity, R03/R04):
#  - O estado operacional de INSCRIÇÃO é sempre DERIVADO a cada render; nunca é
#    lido do campo congelado `status_oportunidade`.
#  - O estado OFICIAL informado pela fonte (`status_oficial`) é um insumo separado.
#  - Funções puras com relógio injetável (`today` Date ou `now` POSIXct).
#  - Referência de fuso: America/Sao_Paulo. Prazo sem hora encerra no fim do dia.
#  - Texto livre (`texto_bruto`) NÃO é evidência de estado: menus e rodapés contêm
#    "aberto"/"encerrado". O parâmetro é mantido apenas por compatibilidade.
#
# Precedência:
#   1. cancelado / suspenso / encerrado oficial (aplicável à submissão)
#   2. abertura futura                       -> em_breve
#   3. prazo confiável já vencido            -> encerrado
#   4. janela de encerramento (<= 14 dias)   -> encerrando
#   5. prazo futuro, aberto oficial ou fluxo contínuo declarado -> aberto
#   6. caso contrário                        -> desconhecido (sem badge verde)
#   Conflito (oficial "aberto" com prazo vencido) -> desconhecido + conflito.

STATUS_TZ <- "America/Sao_Paulo"
STATUS_URGENT_DAYS <- 14L
STATUS_ENUM <- c("aberto", "encerrando", "em_breve", "encerrado", "em_julgamento",
                 "suspenso", "cancelado", "desconhecido")

status_today <- function() {
  as.Date(lubridate::with_tz(Sys.time(), STATUS_TZ))
}

status_now <- function() {
  lubridate::with_tz(Sys.time(), STATUS_TZ)
}

# Normaliza o estado oficial da fonte para o enum interno (NA se ausente/desconhecido).
normalize_status_oficial <- function(x) {
  x <- tolower(trimws(as.character(x %||% NA_character_)))
  x <- chartr("áàâãéêíóôõúç", "aaaaeeiooouc", x)
  x <- gsub("[ -]+", "_", x)
  out <- rep(NA_character_, length(x))
  out[grepl("^(cancelad|revogad|anulad)", x)] <- "cancelado"
  out[grepl("^(suspens|suspend)", x)] <- "suspenso"
  out[grepl("^(encerrad|inscricoes_encerradas|fechad|closed|concluid|finalizad|expirad)", x)] <- "encerrado"
  out[grepl("^(em_julgamento|julgamento|em_avaliacao|resultado)", x)] <- "em_julgamento"
  out[grepl("^(em_breve|futur|upcoming|previst)", x)] <- "em_breve"
  out[grepl("^(aberto|aberta|open|inscricoes_abertas|em_andamento_inscricoes)", x)] <- "aberto"
  out
}

# Instante-limite: usa a hora publicada quando existir; senão, fim do dia (23:59:59).
parse_deadline_instant <- function(x) {
  x <- as.character(x %||% NA_character_)
  out <- as.POSIXct(rep(NA_real_, length(x)), origin = "1970-01-01", tz = STATUS_TZ)
  for (i in seq_along(x)) {
    xi <- trimws(x[[i]])
    if (is.na(xi) || !nzchar(xi)) next
    has_time <- grepl("[0-9]{1,2}:[0-9]{2}", xi)
    if (has_time) {
      p <- suppressWarnings(lubridate::ymd_hms(xi, quiet = TRUE, tz = STATUS_TZ))
      if (is.na(p)) p <- suppressWarnings(lubridate::ymd_hm(xi, quiet = TRUE, tz = STATUS_TZ))
      if (is.na(p)) p <- suppressWarnings(lubridate::dmy_hms(xi, quiet = TRUE, tz = STATUS_TZ))
      if (is.na(p)) p <- suppressWarnings(lubridate::dmy_hm(xi, quiet = TRUE, tz = STATUS_TZ))
      if (!is.na(p)) { out[[i]] <- p; next }
    }
    d <- parse_date_safe(xi)
    if (length(d) && !is.na(d[[1]])) {
      out[[i]] <- as.POSIXct(paste0(format(d[[1]], "%Y-%m-%d"), " 23:59:59"), tz = STATUS_TZ)
    }
  }
  out
}

parse_opening_instant <- function(x) {
  x <- as.character(x %||% NA_character_)
  out <- as.POSIXct(rep(NA_real_, length(x)), origin = "1970-01-01", tz = STATUS_TZ)
  for (i in seq_along(x)) {
    xi <- trimws(x[[i]])
    if (is.na(xi) || !nzchar(xi)) next
    if (grepl("[0-9]{1,2}:[0-9]{2}", xi)) {
      p <- suppressWarnings(lubridate::ymd_hms(xi, quiet = TRUE, tz = STATUS_TZ))
      if (is.na(p)) p <- suppressWarnings(lubridate::ymd_hm(xi, quiet = TRUE, tz = STATUS_TZ))
      if (is.na(p)) p <- suppressWarnings(lubridate::dmy_hm(xi, quiet = TRUE, tz = STATUS_TZ))
      if (!is.na(p)) { out[[i]] <- p; next }
    }
    d <- parse_date_safe(xi)
    if (length(d) && !is.na(d[[1]])) {
      out[[i]] <- as.POSIXct(paste0(format(d[[1]], "%Y-%m-%d"), " 00:00:00"), tz = STATUS_TZ)
    }
  }
  out
}

.resolve_now <- function(today = NULL, now = NULL) {
  if (!is.null(now)) return(lubridate::with_tz(as.POSIXct(now, tz = STATUS_TZ), STATUS_TZ))
  if (!is.null(today)) {
    return(as.POSIXct(paste0(format(as.Date(today), "%Y-%m-%d"), " 00:00:00"), tz = STATUS_TZ))
  }
  status_now()
}

# Resolvedor completo: retorna estado + conflito + motivo (para auditoria/UI).
resolve_submission_status <- function(data_limite = NA, data_abertura = NA, status_oficial = NA,
                                      fluxo_continuo = FALSE, today = NULL, now = NULL) {
  nw <- .resolve_now(today, now)
  off <- normalize_status_oficial(status_oficial)[[1]]
  dl <- parse_deadline_instant(data_limite)[[1]]
  ab <- parse_opening_instant(data_abertura)[[1]]
  conflito <- FALSE
  mk <- function(st, motivo, conf = conflito) list(status = st, conflito = conf, motivo = motivo)

  if (!is.na(off) && off %in% c("cancelado", "suspenso")) return(mk(off, "oficial"))
  if (!is.na(off) && off == "encerrado") {
    conf <- !is.na(dl) && dl > nw
    return(mk("encerrado", if (conf) "oficial_prevalece_sobre_prazo_futuro" else "oficial", conf))
  }
  if (!is.na(off) && off == "em_julgamento") return(mk("em_julgamento", "oficial"))
  if (!is.na(ab) && ab > nw) return(mk("em_breve", "abertura_futura"))
  if (!is.na(off) && off == "em_breve" && (is.na(dl) || dl > nw) && is.na(ab)) {
    return(mk("em_breve", "oficial"))
  }
  if (!is.na(dl)) {
    if (dl < nw) {
      if (!is.na(off) && off == "aberto") {
        return(list(status = "desconhecido", conflito = TRUE, motivo = "oficial_aberto_com_prazo_vencido"))
      }
      return(mk("encerrado", "prazo_vencido"))
    }
    dias <- as.numeric(difftime(as.POSIXct(format(dl, "%Y-%m-%d"), tz = STATUS_TZ),
                                as.POSIXct(format(nw, "%Y-%m-%d"), tz = STATUS_TZ), units = "days"))
    if (!is.na(dias) && dias <= STATUS_URGENT_DAYS) return(mk("encerrando", "janela_de_encerramento"))
    return(mk("aberto", "prazo_futuro"))
  }
  if (!is.na(off) && off == "aberto") return(mk("aberto", "oficial"))
  if (isTRUE(fluxo_continuo)) return(mk("aberto", "fluxo_continuo_declarado"))
  mk("desconhecido", "sem_evidencia")
}

derive_status_one <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL,
                              status_oficial = NA, fluxo_continuo = FALSE, now = NULL) {
  resolve_submission_status(data_limite, data_abertura, status_oficial, fluxo_continuo, today, now)$status
}

.recycle <- function(x, n) {
  if (length(x) == 0L) x <- NA
  rep_len(x, n)
}

derive_status <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL,
                          status_oficial = NA, fluxo_continuo = FALSE, now = NULL) {
  n <- max(length(data_limite), length(data_abertura), length(status_oficial),
           length(fluxo_continuo), 1L)
  if (length(data_limite) == 0L && length(data_abertura) == 0L) n <- 1L
  dl <- .recycle(as.character(data_limite), n)
  ab <- .recycle(as.character(data_abertura), n)
  so <- .recycle(as.character(status_oficial), n)
  fc <- .recycle(as.logical(fluxo_continuo), n)
  fc[is.na(fc)] <- FALSE
  vapply(seq_len(n), function(i) {
    derive_status_one(dl[[i]], ab[[i]], today = today, status_oficial = so[[i]],
                      fluxo_continuo = fc[[i]], now = now)
  }, character(1))
}

derive_status_vec <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL,
                              status_oficial = NA, fluxo_continuo = FALSE, now = NULL) {
  derive_status(data_limite = data_limite, data_abertura = data_abertura, texto_bruto = texto_bruto,
                today = today, status_oficial = status_oficial, fluxo_continuo = fluxo_continuo, now = now)
}

# Conveniência: aplica o resolvedor único a um data.frame de oportunidades.
derive_status_df <- function(df, today = NULL, now = NULL) {
  if (is.null(df) || nrow(df) == 0L) return(character())
  col <- function(nm) if (nm %in% names(df)) df[[nm]] else rep(NA, nrow(df))
  derive_status(col("data_limite"), col("data_abertura"), today = today,
                status_oficial = col("status_oficial"), fluxo_continuo = col("fluxo_continuo"), now = now)
}

# Contagem de urgentes (14 dias) para KPI — deriva, nunca lê coluna congelada.
count_urgent_status <- function(data_limite = NA, data_abertura = NA, texto_bruto = "", today = NULL,
                                status_oficial = NA) {
  st <- derive_status(data_limite, data_abertura, today = today, status_oficial = status_oficial)
  sum(st %in% "encerrando", na.rm = TRUE)
}

# Rótulo amigável para o enum da UI (derivado).
status_display_label <- function(status) {
  labels <- c(
    "aberto" = "Aberto",
    "encerrando" = "Encerrando",
    "em_breve" = "Em breve",
    "encerrado" = "Encerrado",
    "em_julgamento" = "Em julgamento",
    "suspenso" = "Suspenso",
    "cancelado" = "Cancelado",
    "desconhecido" = "A verificar"
  )
  out <- unname(labels[status])
  out[is.na(out)] <- tools::toTitleCase(as.character(status)[is.na(out)])
  out
}
