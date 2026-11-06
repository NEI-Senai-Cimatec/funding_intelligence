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
      # Prazo já expirado: o edital está encerrado para submissões.
      conf <- !is.na(off) && off == "aberto"
      return(mk("encerrado", if (conf) "prazo_vencido_prevalece_sobre_oficial" else "prazo_vencido", conf))
    }
    dias <- as.numeric(difftime(as.POSIXct(format(dl, "%Y-%m-%d"), tz = STATUS_TZ),
                                as.POSIXct(format(nw, "%Y-%m-%d"), tz = STATUS_TZ), units = "days"))
    if (!is.na(dias) && dias <= STATUS_URGENT_DAYS) return(mk("encerrando", "janela_de_encerramento"))
    return(mk("aberto", "prazo_futuro"))
  }
  if (isTRUE(fluxo_continuo)) return(mk("aberto", "fluxo_continuo"))
  if (!is.na(off) && off %in% c("aberto", "encerrando")) return(mk("aberto", "oficial"))
  if (!is.na(off) && off == "em_breve") return(mk("em_breve", "oficial"))
  if (!is.na(off) && off == "encerrado") return(mk("encerrado", "oficial"))
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
  
  # Coalesce status_oficial com status_oportunidade para garantir que o status
  # levantado pelos coletores seja considerado mesmo se status_oficial for NA
  so_raw <- if ("status_oficial" %in% names(df) && "status_oportunidade" %in% names(df)) {
    dplyr::coalesce(as.character(col("status_oficial")), as.character(col("status_oportunidade")))
  } else if ("status_oficial" %in% names(df)) {
    as.character(col("status_oficial"))
  } else if ("status_oportunidade" %in% names(df)) {
    as.character(col("status_oportunidade"))
  } else rep(NA_character_, nrow(df))
  
  # Auto-detecção de fluxo contínuo
  fc <- col("fluxo_continuo")
  comb <- paste(col("titulo") %||% "", col("descricao_resumida") %||% "",
                col("observacoes") %||% "", col("texto_bruto") %||% "")
  is_fc_txt <- grepl("\\b(fluxo cont[ií]nuo|submiss[aã]o cont[ií]nua|inscri[cç][oõ]es cont[ií]nuas|continuous submission|open continuously|accepted at any time|submit(ted)? at any time|rolling basis|sem prazo limite|permanente|ao longo do ano)\\b", comb, ignore.case = TRUE)
  fc <- dplyr::coalesce(as.logical(fc), is_fc_txt)
  
  # Tentativa de extração contextual de prazo para registros sem data_limite
  dl_col <- as.character(col("data_limite"))
  missing_dl <- which(is.na(dl_col) | !nzchar(trimws(dl_col)))
  if (length(missing_dl) > 0) {
    for (idx in missing_dl) {
      if (!isTRUE(fc[[idx]])) {
        txt_i <- comb[[idx]]
        if (nzchar(trimws(txt_i))) {
          extracted_d <- tryCatch(extract_submission_deadline_strict(txt_i), error = function(e) as.Date(NA))
          if (!is.na(extracted_d)) {
            dl_col[[idx]] <- as.character(extracted_d)
          }
        }
      }
    }
  }

  derive_status(dl_col, col("data_abertura"), today = today,
                status_oficial = so_raw, fluxo_continuo = fc, now = now)
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
    "desconhecido" = "Desconhecido"
  )
  out <- unname(labels[status])
  # Guarda: em algumas versões do R, toTitleCase(character(0)) devolve list(),
  # o que transformava `out` em lista e quebrava a tabela de resultados.
  miss <- is.na(out)
  if (any(miss)) out[miss] <- as.character(tools::toTitleCase(as.character(status)[miss]))
  out
}

# Chave numérica de ordenação para Status:
# 1. Aberto / Encerrando -> 2. Em breve -> 3. Desconhecido / A verificar -> 4. Encerrado
status_sort_rank <- function(status) {
  if (length(status) == 0) return(integer(0))
  s <- tolower(trimws(as.character(status)))
  s[is.na(s) | !nzchar(s)] <- "desconhecido"
  dplyr::case_when(
    s == "aberto" ~ 10L,
    s == "encerrando" ~ 11L,
    s %in% c("em_breve", "em breve") ~ 20L,
    s %in% c("desconhecido", "a verificar", "a_verificar") ~ 30L,
    s == "encerrado" ~ 40L,
    TRUE ~ 50L
  )
}

# Chave numérica de ordenação para Data (Ano -> Mês -> Dia como inteiro YYYYMMDD).
# Datas ausentes recebem 99999999L para ficarem sempre ao final.
date_sort_key_ymd <- function(x) {
  if (length(x) == 0) return(integer(0))
  d <- parse_date_safe(x)
  out <- rep(99999999L, length(d))
  ok <- !is.na(d)
  if (any(ok)) {
    out[ok] <- suppressWarnings(as.integer(format(d[ok], "%Y%m%d")))
    out[is.na(out)] <- 99999999L
  }
  out
}
