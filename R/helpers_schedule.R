# ─── Cronogramas e datas oficiais (R03 / T09 T10 T14) ────────────────────────
# - data_publicacao  = publicação do edital   (NÃO a data da coleta)
# - data_limite      = fim da etapa de candidatura/submissão (NÃO resultado,
#                      recurso, vigência ou implementação)
# - Retificação oficial mais recente prevalece sobre o original (mesma etapa).
# - Formato local: DD/MM/AAAA (ano de 2 dígitos aceito em cronogramas).
#   Datas ambíguas (mês > 12 em DD/MM) não são adivinhadas: viram NA.
# - Todas as funções são puras e não dependem do relógio.

SCHEDULE_STAGES <- c("submissao_inicio", "submissao_fim", "avaliacao", "resultado_preliminar",
                     "recurso", "resultado_final", "implementacao", "outro")

.MONTHS_PT <- c(janeiro = 1, fevereiro = 2, marco = 3, abril = 4, maio = 5, junho = 6, julho = 7,
                agosto = 8, setembro = 9, outubro = 10, novembro = 11, dezembro = 12)

.MONTHS_ALL <- c(
  janeiro = 1, fevereiro = 2, marco = 3, abril = 4, maio = 5, junho = 6,
  julho = 7, agosto = 8, setembro = 9, outubro = 10, novembro = 11, dezembro = 12,
  jan = 1, fev = 2, mar = 3, abr = 4, mai = 5, jun = 6,
  jul = 7, ago = 8, set = 9, out = 10, nov = 11, dez = 12,
  january = 1, february = 2, march = 3, april = 4, may = 5, june = 6,
  july = 7, august = 8, september = 9, october = 10, november = 11, december = 12,
  feb = 2, apr = 4, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12
)

.mk_date <- function(d, m, y) {
  d <- suppressWarnings(as.integer(d)); m <- suppressWarnings(as.integer(m)); y <- suppressWarnings(as.integer(y))
  if (is.na(d) || is.na(m) || is.na(y)) return(as.Date(NA))
  if (y < 100L) y <- 2000L + y
  if (m < 1L || m > 12L || d < 1L || d > 31L || y < 1990L || y > 2100L) return(as.Date(NA))
  out <- suppressWarnings(as.Date(sprintf("%04d-%02d-%02d", y, m, d)))
  out
}

# Converte um token isolado em Date (DMY ou ISO). Vetorizado.
parse_br_date_token <- function(x) {
  x <- normalize_text(as.character(x %||% NA_character_))
  vapply(seq_along(x), function(i) {
    xi <- x[[i]]
    if (is.na(xi) || !nzchar(xi)) return(NA_real_)
    m <- regmatches(xi, regexec("^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2}|\\d{4})$", xi))[[1]]
    if (length(m) == 4L) return(as.numeric(.mk_date(m[[2]], m[[3]], m[[4]])))
    m <- regmatches(xi, regexec("^(\\d{4})-(\\d{2})-(\\d{2})$", xi))[[1]]
    if (length(m) == 4L) return(as.numeric(.mk_date(m[[4]], m[[3]], m[[2]])))
    m <- regmatches(xi, regexec("^(\\d{1,2})(?:o|\\.)?\\s+de\\s+([a-z]+)\\s+de\\s+(\\d{4})$", xi, perl = TRUE))[[1]]
    if (length(m) == 4L && m[[3]] %in% names(.MONTHS_ALL)) {
      return(as.numeric(.mk_date(m[[2]], .MONTHS_ALL[[m[[3]]]], m[[4]])))
    }
    NA_real_
  }, numeric(1)) |> as.Date(origin = "1970-01-01")
}

# Etapa a partir do rótulo (normalizado). Ordem importa: resultado/recurso antes de "término".
# Suporta termos em português e inglês.
classify_stage_label <- function(label) {
  l <- normalize_text(label %||% "")
  if (!nzchar(l)) return("outro")
  if (grepl("resultado final|resultado definitivo|divulgacao do resultado final|homologacao|final result", l)) return("resultado_final")
  if (grepl("resultado (inicial|preliminar|parcial|provisorio)|classificatorio|preliminary result", l)) return("resultado_preliminar")
  if (grepl("recurso|recursal|interposicao|appeal", l)) return("recurso")
  if (grepl("implementacao|assinatura|outorga|vigencia|inicio das atividades|inicio do projeto|grant agreement", l)) return("implementacao")
  if (grepl("avaliacao|julgamento|analise|selecao dos|evaluation|review", l)) return("avaliacao")
  if (grepl("(inicio|abertura|a partir de|opening date|opens|application opens|call opens|released).*(recebimento|inscri|proposta|submissao|envio|candidatura|proposal|application)|(recebimento|inscri\\w*|submissao|envio|proposal|application).*(inicio|abertura|open|start)", l) &&
      !grepl("termino|encerramento|fim |prazo final|limite|deadline|due|clos", l)) return("submissao_inicio")
  if (grepl("(termino|encerramento|fim |fim$|prazo final|ultimo dia|data limite|limite|prazo para|ate|deadline|due date|closing date|proposals due|application deadline|submission deadline|apply by|cutoff date|closing|submission close).*(recebimento|inscri|proposta|submissao|envio|candidatura|proposal|application)?|(recebimento|inscri\\w*|submissao|envio de propostas|proposals?|applications?).*(ate|deadline|due|closing|cutoff)|\\b(deadline|due date|closing date|proposals due|apply by|due)\\b", l)) return("submissao_fim")
  "outro"
}

.extract_time_after <- function(txt, end_pos) {
  tail <- substr(txt, end_pos + 1L, end_pos + 24L)
  m <- regmatches(tail, regexec("^\\s*(?:,|;|-|as|\u00e0s)?\\s*(\\d{1,2})\\s*(?:h|:)\\s*(\\d{2})?", tail, ignore.case = TRUE, perl = TRUE))[[1]]
  if (length(m) >= 2L && nzchar(m[[2]])) {
    hh <- suppressWarnings(as.integer(m[[2]])); mm <- if (length(m) >= 3L && nzchar(m[[3]])) as.integer(m[[3]]) else 0L
    if (!is.na(hh) && hh <= 23L && !is.na(mm) && mm <= 59L) return(sprintf("%02d:%02d", hh, mm))
  }
  NA_character_
}

# Extrai eventos rotulados (etapa, data, hora, trecho).
# Suporta formatos: DD/MM/AAAA, DD.MM.AAAA, ISO (AAAA-MM-DD), datas textuais em PT e EN.
extract_labeled_events <- function(text) {
  txt <- as.character(text %||% "")
  if (length(txt) != 1L || is.na(txt) || !nzchar(txt)) {
    return(data.frame(etapa = character(), data = as.Date(character()), hora = character(), trecho = character(),
                      stringsAsFactors = FALSE))
  }
  txt <- gsub("\u00a0", " ", txt, fixed = TRUE)
  flat <- gsub("[ \t]*\r?\n[ \t]*", " ", txt)
  flat <- gsub(" {2,}", "  ", flat)
  
  rows <- list()
  
  # 1. Regex para datas com separador (/ ou .)
  re_dmy <- "(?:(\\d{1,2})\\s*(?:\u00e0|a|ate|at\u00e9|-)\\s*)?(\\d{1,2})[/.](\\d{1,2})[/.](\\d{4}|\\d{2})(?!\\d)"
  locs <- gregexpr(re_dmy, flat, perl = TRUE)[[1]]
  if (length(locs) > 0L && locs[[1]] != -1L) {
    lens <- attr(locs, "match.length")
    prev_end <- 0L
    for (k in seq_along(locs)) {
      st <- locs[[k]]; en <- st + lens[[k]] - 1L
      tok <- substr(flat, st, en)
      label <- trimws(substr(flat, max(prev_end + 1L, st - 200L), st - 1L))
      mm <- regmatches(tok, regexec(re_dmy, tok, perl = TRUE))[[1]]
      d_end <- .mk_date(mm[[3]], mm[[4]], mm[[5]])
      d_start <- if (nzchar(mm[[2]])) .mk_date(mm[[2]], mm[[4]], mm[[5]]) else as.Date(NA)
      prev_end <- en
      if (is.na(d_end)) next
      etapa <- classify_stage_label(label)
      hora <- .extract_time_after(flat, en)
      if (!is.na(d_start)) {
        rows[[length(rows) + 1L]] <- data.frame(etapa = etapa, data = d_start, hora = NA_character_,
                                                trecho = substr(paste(label, tok), 1L, 240L), stringsAsFactors = FALSE)
      }
      rows[[length(rows) + 1L]] <- data.frame(etapa = etapa, data = d_end, hora = hora,
                                              trecho = substr(paste(label, tok), 1L, 240L), stringsAsFactors = FALSE)
    }
  }

  # 2. Regex para formato ISO (AAAA-MM-DD)
  re_iso <- "(?<!\\d)(\\d{4})-(\\d{2})-(\\d{2})(?!\\d)"
  locs_iso <- gregexpr(re_iso, flat, perl = TRUE)[[1]]
  if (length(locs_iso) > 0L && locs_iso[[1]] != -1L) {
    lens <- attr(locs_iso, "match.length")
    for (k in seq_along(locs_iso)) {
      st <- locs_iso[[k]]; en <- st + lens[[k]] - 1L
      tok <- substr(flat, st, en)
      label <- trimws(substr(flat, max(1L, st - 200L), st - 1L))
      mm <- regmatches(tok, regexec(re_iso, tok, perl = TRUE))[[1]]
      d <- .mk_date(mm[[4]], mm[[3]], mm[[2]])
      if (is.na(d)) next
      etapa <- classify_stage_label(label)
      hora <- .extract_time_after(flat, en)
      rows[[length(rows) + 1L]] <- data.frame(etapa = etapa, data = d, hora = hora,
                                              trecho = substr(paste(label, tok), 1L, 240L), stringsAsFactors = FALSE)
    }
  }

  # 3. Regex para datas textuais em PT (Ex: 15 de novembro de 2026)
  re_txt_pt <- "(?<!\\d)(\\d{1,2})(?:o|\\.)?\\s+de\\s+([a-zç]+)\\s+de\\s+(\\d{4})(?!\\d)"
  locs_pt <- gregexpr(re_txt_pt, flat, perl = TRUE, ignore.case = TRUE)[[1]]
  if (length(locs_pt) > 0L && locs_pt[[1]] != -1L) {
    lens <- attr(locs_pt, "match.length")
    for (k in seq_along(locs_pt)) {
      st <- locs_pt[[k]]; en <- st + lens[[k]] - 1L
      tok <- substr(flat, st, en)
      label <- trimws(substr(flat, max(1L, st - 200L), st - 1L))
      mm <- regmatches(tok, regexec(re_txt_pt, tok, perl = TRUE, ignore.case = TRUE))[[1]]
      m_name <- tolower(mm[[3]])
      if (m_name %in% names(.MONTHS_ALL)) {
        d <- .mk_date(mm[[2]], .MONTHS_ALL[[m_name]], mm[[4]])
        if (!is.na(d)) {
          etapa <- classify_stage_label(label)
          hora <- .extract_time_after(flat, en)
          rows[[length(rows) + 1L]] <- data.frame(etapa = etapa, data = d, hora = hora,
                                                  trecho = substr(paste(label, tok), 1L, 240L), stringsAsFactors = FALSE)
        }
      }
    }
  }

  # 4. Regex para datas textuais em EN (Ex: November 15, 2026 e 15 November 2026)
  re_txt_en_mdy <- "\\b([a-z]+)\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})(?!\\d)"
  locs_en1 <- gregexpr(re_txt_en_mdy, flat, perl = TRUE, ignore.case = TRUE)[[1]]
  if (length(locs_en1) > 0L && locs_en1[[1]] != -1L) {
    lens <- attr(locs_en1, "match.length")
    for (k in seq_along(locs_en1)) {
      st <- locs_en1[[k]]; en <- st + lens[[k]] - 1L
      tok <- substr(flat, st, en)
      label <- trimws(substr(flat, max(1L, st - 200L), st - 1L))
      mm <- regmatches(tok, regexec(re_txt_en_mdy, tok, perl = TRUE, ignore.case = TRUE))[[1]]
      m_name <- tolower(mm[[2]])
      if (m_name %in% names(.MONTHS_ALL)) {
        d <- .mk_date(mm[[3]], .MONTHS_ALL[[m_name]], mm[[4]])
        if (!is.na(d)) {
          etapa <- classify_stage_label(label)
          hora <- .extract_time_after(flat, en)
          rows[[length(rows) + 1L]] <- data.frame(etapa = etapa, data = d, hora = hora,
                                                  trecho = substr(paste(label, tok), 1L, 240L), stringsAsFactors = FALSE)
        }
      }
    }
  }

  re_txt_en_dmy <- "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+([a-z]+),?\\s+(\\d{4})(?!\\d)"
  locs_en2 <- gregexpr(re_txt_en_dmy, flat, perl = TRUE, ignore.case = TRUE)[[1]]
  if (length(locs_en2) > 0L && locs_en2[[1]] != -1L) {
    lens <- attr(locs_en2, "match.length")
    for (k in seq_along(locs_en2)) {
      st <- locs_en2[[k]]; en <- st + lens[[k]] - 1L
      tok <- substr(flat, st, en)
      label <- trimws(substr(flat, max(1L, st - 200L), st - 1L))
      mm <- regmatches(tok, regexec(re_txt_en_dmy, tok, perl = TRUE, ignore.case = TRUE))[[1]]
      m_name <- tolower(mm[[3]])
      if (m_name %in% names(.MONTHS_ALL)) {
        d <- .mk_date(mm[[2]], .MONTHS_ALL[[m_name]], mm[[4]])
        if (!is.na(d)) {
          etapa <- classify_stage_label(label)
          hora <- .extract_time_after(flat, en)
          rows[[length(rows) + 1L]] <- data.frame(etapa = etapa, data = d, hora = hora,
                                                  trecho = substr(paste(label, tok), 1L, 240L), stringsAsFactors = FALSE)
        }
      }
    }
  }

  if (length(rows) == 0L) {
    return(data.frame(etapa = character(), data = as.Date(character()), hora = character(), trecho = character(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

# Data de publicação explícita ("Publicado em 31/10/2024").
extract_publication_date <- function(text) {
  t <- as.character(text %||% "")
  if (length(t) != 1L || is.na(t)) return(as.Date(NA))
  m <- regmatches(t, regexec("(?i)publica(?:d[oa]|\u00e7\u00e3o|cao)\\s*(?:em|:|no dia|dia)?\\s*(\\d{1,2}/\\d{1,2}/\\d{2,4})", t, perl = TRUE))[[1]]
  if (length(m) == 2L) return(parse_br_date_token(m[[2]]))
  as.Date(NA)
}

# Resolve vários documentos (original + retificações) em um cronograma único.
#   docs: lista de list(events = data.frame, retificado = logical, nome = chr, ordem = int)
#         Quanto maior `ordem`, mais recente. Retificações prevalecem por etapa.
#   now : POSIXct usado apenas para escolher a rodada corrente quando houver mais de uma.
resolve_schedule <- function(docs, now = NULL) {
  empty <- list(data_publicacao = as.Date(NA), data_abertura = as.Date(NA), data_limite = NA_character_,
                eventos = data.frame(), rodadas = data.frame(), retificacao_aplicada = FALSE,
                multiplas_rodadas = FALSE, fonte_prazo = NA_character_)
  if (length(docs) == 0L) return(empty)
  ord <- order(vapply(docs, function(d) as.integer(d$ordem %||% 1L), integer(1)))
  docs <- docs[ord]
  merged <- list()
  retif <- FALSE
  for (d in docs) {
    ev <- d$events
    if (is.null(ev) || nrow(ev) == 0L) next
    stages <- unique(ev$etapa)
    if (isTRUE(d$retificado)) retif <- TRUE
    for (st in stages) {
      merged[[st]] <- cbind(ev[ev$etapa == st, , drop = FALSE], doc = d$nome %||% NA_character_,
                            retificado = isTRUE(d$retificado), stringsAsFactors = FALSE)
    }
  }
  if (length(merged) == 0L) return(empty)
  eventos <- do.call(rbind, merged); rownames(eventos) <- NULL

  ini <- if (!is.null(merged$submissao_inicio)) sort(merged$submissao_inicio$data) else as.Date(character())
  fim_df <- merged$submissao_fim
  fim <- if (!is.null(fim_df)) fim_df[order(fim_df$data), , drop = FALSE] else NULL
  nrod <- if (is.null(fim)) 0L else nrow(fim)
  multiplas <- nrod > 1L && length(ini) > 1L

  nw <- if (is.null(now)) NULL else as.Date(lubridate::with_tz(as.POSIXct(now, tz = STATUS_TZ), STATUS_TZ))
  rodadas <- data.frame()
  chosen_fim <- if (nrod >= 1L) fim[nrod, , drop = FALSE] else NULL
  chosen_ini <- if (length(ini)) ini[[length(ini)]] else as.Date(NA)
  if (multiplas) {
    n <- min(length(ini), nrod)
    rodadas <- data.frame(rodada = seq_len(n), inicio = ini[seq_len(n)], fim = fim$data[seq_len(n)])
    if (!is.null(nw)) {
      cur <- which(rodadas$inicio <= nw & rodadas$fim >= nw)
      nxt <- which(rodadas$inicio > nw)
      idx <- if (length(cur)) cur[[1]] else if (length(nxt)) nxt[[1]] else n
      chosen_fim <- fim[idx, , drop = FALSE]
      chosen_ini <- rodadas$inicio[[idx]]
    }
  } else if (length(ini) == 1L) {
    chosen_ini <- ini[[1]]
  }
  dl <- NA_character_
  if (!is.null(chosen_fim) && nrow(chosen_fim) == 1L) {
    dl <- format(chosen_fim$data, "%Y-%m-%d")
    if (!is.na(chosen_fim$hora)) dl <- paste(dl, chosen_fim$hora)
  }
  # Publicação: início do recebimento do documento ORIGINAL (não-retificado) quando existir.
  orig <- eventos[eventos$etapa == "submissao_inicio" & !eventos$retificado, , drop = FALSE]
  pub <- if (nrow(orig)) min(orig$data) else as.Date(NA)
  list(data_publicacao = pub, data_abertura = chosen_ini, data_limite = dl, eventos = eventos,
       rodadas = rodadas, retificacao_aplicada = retif, multiplas_rodadas = multiplas,
       fonte_prazo = if (!is.null(chosen_fim) && nrow(chosen_fim)) chosen_fim$doc else NA_character_)
}

# Datas contextuais seguras para o extrator genérico (Q05): apenas FIM de submissão
# rotulado. Nunca usa máximo global, "final" isolado, resultado ou atualização de página.
extract_submission_deadline_strict <- function(text) {
  ev <- extract_labeled_events(text)
  if (nrow(ev) == 0L) return(as.Date(NA))
  fim <- ev[ev$etapa == "submissao_fim", , drop = FALSE]
  if (nrow(fim) == 0L) return(as.Date(NA))
  max(fim$data)
}
