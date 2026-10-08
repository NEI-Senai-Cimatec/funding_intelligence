# ─── Contratos de validação (openspec: brazilian-sources-data-integrity) ─────
# Separa: aquisição -> descoberta -> extração -> VALIDAÇÃO DE DOMÍNIO ->
#         estado -> classificação temática -> enriquecimento -> persistência.
#
#  * classify_acquisition()    R06  erro TLS / intersticial / bloqueio / login /
#                                   CAPTCHA / manutenção / SPA vazia / conteúdo
#  * classify_scope_type()     R01  fomento, bolsa, aceleração, CPSI, consultoria,
#                                   concurso de cargo, compra comum, crédito genérico...
#  * validate_opportunity()    R01  validado | a_verificar | rejeitado | quarentena
#  * infer_campus_candidates() R05  campus com fronteira de palavra e justificativa
#  * stable_opportunity_id()   R07  identidade estável (sem prazo, sem data de coleta)
#  * make_provenance()         R02  proveniência por campo
#
# Todas as funções são puras (sem rede, sem banco) para permitir teste offline.

VALIDATOR_VERSION <- "br-integrity-1.0"
VALIDATION_STATES <- c("validado", "a_verificar", "rejeitado", "quarentena")

# ─── Aquisição (R06 / T05 / T06) ──────────────────────────────────────────────

ACQUISITION_KINDS <- c("conteudo", "tls_error", "browser_interstitial", "blocked", "login",
                       "captcha", "maintenance", "spa_shell", "empty", "http_error", "network_error")

.visible_text_head <- function(html_text, n = 4000L) {
  x <- as.character(html_text %||% "")
  if (length(x) != 1L || is.na(x)) return("")
  x <- gsub("(?is)<(script|style|noscript|svg)[^>]*>.*?</\\1>", " ", x, perl = TRUE)
  x <- gsub("(?s)<!--.*?-->", " ", x, perl = TRUE)
  x <- gsub("<[^>]+>", " ", x, perl = TRUE)
  x <- gsub("&nbsp;", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x, perl = TRUE)
  substr(trimws(x), 1L, n)
}

.html_title <- function(html_text) {
  m <- regmatches(html_text, regexec("(?is)<title[^>]*>(.*?)</title>", html_text, perl = TRUE))[[1]]
  if (length(m) >= 2L) trimws(gsub("\\s+", " ", m[[2]])) else ""
}

# Classifica o que foi adquirido. HTTP 200 e HTML longo NÃO bastam para "conteudo".
classify_acquisition <- function(html_text = NA_character_, http_status = 200L, error = NA_character_) {
  mk <- function(kind, reason) list(kind = kind, ok = identical(kind, "conteudo"), reason = reason)
  err <- normalize_text(error %||% "")
  if (nzchar(err)) {
    if (grepl("ssl|tls|certificate|certificado|cert_|handshake", err)) return(mk("tls_error", error))
    return(mk("network_error", error))
  }
  st <- suppressWarnings(as.integer(http_status %||% NA_integer_))
  if (!is.na(st) && st >= 400L) {
    kind <- if (st %in% c(401L, 403L, 429L)) "blocked" else "http_error"
    return(mk(kind, sprintf("HTTP %d", st)))
  }
  txt <- as.character(html_text %||% "")
  if (length(txt) != 1L || is.na(txt) || !nzchar(trimws(txt))) return(mk("empty", "corpo vazio"))

  title <- normalize_text(.html_title(txt))
  head_txt <- normalize_text(.visible_text_head(txt, 1500L))
  both <- paste(title, head_txt)

  if (grepl("sua conexao nao e particular|your connection is not private|privacy error|err_cert_|net::err|nao e possivel fazer uma conexao segura|certificate (has )?expired|certificado .* expirou", both)) {
    return(mk("browser_interstitial", "intersticial de segurança/certificado do navegador"))
  }
  if (grepl("attention required|just a moment|checking your browser|verificando seu navegador|access denied|acesso negado|request blocked|you have been blocked|forbidden", title) ||
      grepl("checking your browser before accessing|ray id:|cf-challenge|enable javascript and cookies to continue", both)) {
    return(mk("blocked", "página de bloqueio/WAF"))
  }
  if (grepl("captcha|recaptcha|hcaptcha|nao sou um robo|i am not a robot", paste(title, head_txt)) &&
      nchar(head_txt) < 1200L) {
    return(mk("captcha", "desafio CAPTCHA"))
  }
  if (grepl("em manutencao|site em manutencao|under maintenance|temporarily unavailable|servico indisponivel|service unavailable", paste(title, substr(head_txt, 1, 400)))) {
    return(mk("maintenance", "manutenção/indisponibilidade"))
  }
  has_pw_field <- grepl("type=[\"']password[\"']", txt, ignore.case = TRUE)
  if (has_pw_field && nchar(head_txt) < 800L &&
      grepl("login|entrar|acesso restrito|sign in|faca login|autenticacao", paste(title, head_txt))) {
    return(mk("login", "página de login"))
  }
  # SPA sem conteúdo renderizado (ex.: SIGITEC): raiz vazia e quase nenhum texto
  has_root <- grepl("<div[^>]+id=[\"'](root|app|__next)[\"'][^>]*>\\s*</div>", txt, ignore.case = TRUE, perl = TRUE)
  if (has_root && nchar(head_txt) < 120L) {
    return(mk("spa_shell", "SPA sem conteúdo renderizado: requer render ou API"))
  }
  if (nchar(head_txt) < 40L) return(mk("empty", "sem texto visível"))
  mk("conteudo", "ok")
}

# ─── Resultado estruturado por fonte (R06) ────────────────────────────────────
SOURCE_RESULT_STATES <- c("sucesso", "vazio_confirmado", "parcial", "erro_rede", "erro_tls",
                          "bloqueio", "erro_parser", "erro_persistencia")

make_source_diagnostics <- function(state, n_candidatos = 0L, n_aceitos = 0L, n_rejeitados = 0L,
                                    motivos_rejeicao = character(), http_status = NA_integer_,
                                    url_final = NA_character_, redirecionamentos = 0L,
                                    latencia_s = NA_real_, mensagem = NA_character_, truncado = FALSE,
                                    paginas = 0L, extras = list()) {
  stopifnot(state %in% SOURCE_RESULT_STATES)
  c(list(
    state = state, n_candidatos = as.integer(n_candidatos), n_aceitos = as.integer(n_aceitos),
    n_rejeitados = as.integer(n_rejeitados),
    motivos_rejeicao = as.list(table(motivos_rejeicao)), http_status = http_status,
    url_final = url_final, redirecionamentos = as.integer(redirecionamentos),
    latencia_s = latencia_s, mensagem = mensagem, truncado = isTRUE(truncado),
    paginas = as.integer(paginas)
  ), extras)
}

acquisition_to_state <- function(kind) {
  switch(kind,
    tls_error = "erro_tls", browser_interstitial = "erro_tls", network_error = "erro_rede",
    http_error = "erro_rede", blocked = "bloqueio", captcha = "bloqueio", login = "bloqueio",
    maintenance = "erro_rede", spa_shell = "erro_parser", empty = "erro_parser", "sucesso")
}

# ─── Tipologia/escopo (R01) ───────────────────────────────────────────────────

SCOPE_TYPES <- c("fomento", "bolsa", "aceleracao", "cpsi", "consultoria", "evento", "concurso_cargo",
                 "compra_comum", "credito_generico", "institucional", "navegacao", "intersticial",
                 "sintetico", "indeterminado")

# Decisão por tipo (documentada em design.md): TRUE = no escopo; "revisar" = a_verificar
SCOPE_DECISION <- c(fomento = "validar", bolsa = "validar", aceleracao = "validar", cpsi = "validar",
                    consultoria = "revisar", evento = "revisar", concurso_cargo = "rejeitar",
                    compra_comum = "rejeitar", credito_generico = "rejeitar",
                    institucional = "rejeitar", navegacao = "rejeitar", intersticial = "rejeitar",
                    sintetico = "quarentena", indeterminado = "revisar")

# Títulos fabricados pelos coletores antigos (Q02). Identificação por conteúdo + prefixo de id.
SYNTHETIC_TITLES <- c(
  "chamada p&d anp/shell - descarbonizacao e tecnologias submarinas (rov/auv)",
  "chamada publica uniespaco - pesquisa em satelites, vants e sensoriamento remoto",
  "edital dcta/fab - pesquisa em propulsao aeroespacial, radares e vants",
  "edital fundeci - inovacao para convivencia com o semiarido, agro 4.0 e hidrogenio verde",
  "chamada embrapa - bioeconomia, agrotech e inovacao para o sertao"
)

.NAV_TITLES <- c("imprensa", "acessibilidade", "bndes data", "mapa do site", "busca", "para voce",
                 "para empresas", "poder publico", "internet banking bnb", "onde atuamos", "conhecimento",
                 "efetividade", "aviso", "destaques principais com rolagem de tela", "desenvolvimento sustentavel",
                 "solicite seu financiamento", "pesquisa", "dados de pesquisa", "portfolios de projetos",
                 "politica de inovacao", "cultura", "etene", "produtos e servicos", "sobre o banco",
                 "fale conosco", "ouvidoria", "transparencia", "licitacoes", "consulta a operacoes do bndes",
                 "moedas contratuais - bndes", "servicos e informacoes do brasil", "bndes 2026",
                 "bndes - brazilian development bank", "bndes mpme - consulta de operacoes indiretas",
                 "credenciamento de maquinas, equipamentos, sistemas e componentes")

.NAV_HOSTS <- "(instagram|youtube|youtu\\.be|facebook|twitter|x\\.com|linkedin|flickr|tiktok|whatsapp|t\\.me|spotify)\\."

.INTERSTITIAL_TITLES <- c("sua conexao nao e particular", "your connection is not private", "privacy error",
                          "attention required! | cloudflare", "just a moment...", "access denied",
                          "403 forbidden", "404 not found", "pagina nao encontrada", "erro 404")

.RE_INNOVATION <- "pesquisa|desenvolvimento|inovac|inovador|\\bp&d|\\bpd&i|\\bpdi\\b|tecnolog|startup|projeto|solucao inovadora|ciencia|cientific|prototip|acelerac"
.RE_CPSI <- "\\bcpsi\\b|contrato publico de solucao inovadora|contratacao de (teste de )?solucao inovadora|teste de solucao inovadora|desafio bndes|lei complementar n.? ?182"
.RE_CALL_MARKER <- "\\bedital\\b|\\bchamada\\b|chamamento|selecao|processo seletivo|\\bcpsi\\b|\\bdesafio\\b|\\bcall for\\b|programa de aceleracao|subvencao|\\bbolsas?\\b"
.RE_BUY <- "\\bpregao\\b|\\blicitacao\\b|dispensa de licitacao|tomada de precos|concorrencia|registro de precos|\\bsrp\\b|aquisicao de|contratacao de empresa|ar condicionado|material de consumo|servicos? de (limpeza|vigilancia|manutencao)"
.RE_CREDIT <- "internet banking|microcredito|credito rural|credito pessoal|emprestimo|financiamento|cartao|crediamigo|agroamigo|\\bfne\\b|conta corrente|seguros?\\b|investimentos?\\b|consorcio"

classify_scope_type <- function(titulo = "", descricao = "", url = "", fonte_oficial = "") {
  t <- normalize_text(titulo %||% "")
  d <- normalize_text(substr(as.character(descricao %||% ""), 1L, 800L))
  u <- tolower(as.character(url %||% ""))
  td <- paste(t, d)

  if (t %in% SYNTHETIC_TITLES) return("sintetico")
  if (t %in% .INTERSTITIAL_TITLES || grepl("sua conexao nao e particular|privacy error", t)) return("intersticial")
  if (nzchar(u) && grepl(.NAV_HOSTS, u) && !grepl("worldlabs", u)) return("navegacao")
  if (t %in% .NAV_TITLES) return("navegacao")
  if (grepl("mapa do site|^busca\\b|acessibilidade|internet banking|politica de privacidade", t)) return("navegacao")

  is_cpsi <- grepl(.RE_CPSI, td)
  if (grepl("concurso publico|provimento de cargo|cargo efetivo|concurso de cargo", t) && !is_cpsi) return("concurso_cargo")
  if (is_cpsi) return("cpsi")
  has_innov <- grepl(.RE_INNOVATION, td)
  if (grepl("consultor(ia)?\\b.*pessoa fisica|pessoa fisica.*consultor|consultoria tecnica|contratacao de consultor", td)) return("consultoria")
  if (grepl("expositor|pavilhao|participacao em evento|congresso internacional|international astronautical", td)) return("evento")
  if (grepl(.RE_BUY, t) && !grepl("pesquisa e desenvolvimento|\\bp&d|solucao inovadora|chamada publica de pesquisa", td)) return("compra_comum")
  if (grepl("aceleracao|acelera ", td) && grepl("startup", td) && grepl(.RE_CALL_MARKER, td)) return("aceleracao")
  if (grepl("\\bbolsas?\\b", t)) return("bolsa")
  if (grepl(.RE_CREDIT, td) && !has_innov) return("credito_generico")
  if (grepl(.RE_CALL_MARKER, td) && has_innov) return("fomento")
  if (grepl(.RE_CALL_MARKER, t)) return("indeterminado")
  # Sem marcador de chamada no título, palavras como "desenvolvimento"/"pesquisa" NÃO bastam:
  # páginas institucionais ("Desenvolvimento Regional", "Dados de pesquisa") não são oportunidades.
  if (nzchar(t) && !grepl(.RE_CALL_MARKER, td)) return("institucional")
  "indeterminado"
}

# Decisão de validação por registro (R01). `evidencia_chamada = TRUE` é afirmado por
# adaptadores dedicados que extraíram o item de uma listagem/card estruturado de chamadas.
validate_opportunity <- function(titulo = "", descricao = "", url = "", fonte_oficial = "",
                                 evidencia_chamada = FALSE, tipo_escopo = NA_character_,
                                 id_registro = "", now = NULL) {
  tipo <- if (!is.na(tipo_escopo) && nzchar(tipo_escopo)) tipo_escopo else
    classify_scope_type(titulo, descricao, url, fonte_oficial)
  if (grepl("^anpshell_", id_registro %||% "")) tipo <- "sintetico"
  decisao <- unname(SCOPE_DECISION[tipo])
  if (is.na(decisao)) decisao <- "revisar"
  estado <- switch(decisao, validar = "validado", revisar = "a_verificar",
                   rejeitar = "rejeitado", quarentena = "quarentena")
  motivo <- sprintf("tipo=%s", tipo)
  if (estado == "validado" && !isTRUE(evidencia_chamada)) {
    estado <- "a_verificar"
    motivo <- sprintf("tipo=%s;sem_evidencia_estruturada_de_chamada", tipo)
  }
  if (estado == "validado" && !nzchar(trimws(titulo %||% ""))) {
    estado <- "a_verificar"; motivo <- "sem_titulo"
  }
  if (estado == "validado" && !nzchar(trimws(url %||% ""))) {
    estado <- "a_verificar"; motivo <- sprintf("tipo=%s;sem_fonte_verificavel", tipo)
  }
  list(
    validacao_status = estado,
    validacao_motivo = motivo,
    validacao_evidencia = substr(paste(titulo %||% "", "|", url %||% ""), 1L, 400L),
    validacao_versao = VALIDATOR_VERSION,
    validacao_em = format(if (is.null(now)) Sys.time() else now, "%Y-%m-%d %H:%M:%S"),
    tipo_escopo = tipo
  )
}

# Aplica validate_opportunity a um data.frame e anexa as colunas de validação.
apply_validation <- function(df, evidencia_chamada = FALSE, now = NULL) {
  if (is.null(df) || nrow(df) == 0L) return(df)
  ev <- rep_len(evidencia_chamada, nrow(df))
  tipo_col <- if ("tipo_escopo" %in% names(df)) df$tipo_escopo else rep(NA_character_, nrow(df))
  res <- lapply(seq_len(nrow(df)), function(i) {
    validate_opportunity(
      titulo = df$titulo[[i]] %||% "", descricao = df$descricao_resumida[[i]] %||% "",
      url = df$link_detalhe[[i]] %||% df$link_origem[[i]] %||% "",
      fonte_oficial = df$fonte_oficial[[i]] %||% "", evidencia_chamada = ev[[i]],
      tipo_escopo = tipo_col[[i]], id_registro = df$id_registro[[i]] %||% "", now = now)
  })
  for (nm in c("validacao_status", "validacao_motivo", "validacao_evidencia", "validacao_versao",
               "validacao_em", "tipo_escopo")) {
    df[[nm]] <- vapply(res, function(r) as.character(r[[nm]]), character(1))
  }
  df
}

# Universo público: itens validados + legados sem avaliação (compatibilidade pré-saneamento).
# Itens a_verificar/rejeitado/quarentena ficam em opportunities_review.
filter_validated <- function(df) {
  if (is.null(df) || nrow(df) == 0L || !"validacao_status" %in% names(df)) return(df)
  df[is.na(df$validacao_status) | df$validacao_status == "validado", , drop = FALSE]
}

# ─── Campus e aderência temática (R05 / T18 / T19) ────────────────────────────
# Evidência = termos no OBJETO (título/descrição/área/palavras-chave verificadas).
# Fonte/entidade/financiador, rodapé e menus NÃO são evidência de tema.
# Siglas curtas (IA, AI, CTA...) exigem fronteira de palavra; IA/AI também exigem caixa alta
# no texto original para não casar "aí"/"ia" em português.

CAMPUS_RULES <- list(
  "Aeroespacial" = "\\b(aeroespaci\\w*|aeronautic\\w*|espaciais?|satelites?|vants?|drones?|propulsao|avionica|radares?|evtol|lancadores?|foguetes?|orbitas?|aerospace|hipersonic\\w*|forca aerea|dcta|ieav|cta|iae|sensoriamento remoto)\\b",
  "Sertão" = "\\b(agricultura|agropecuari\\w*|agronegocio|agroindustri\\w*|agrotech|agro 4\\.0|pecuaria|irrigacao|semiarido|caatinga|bioeconomia|recursos hidricos|hidrogenio verde|energia solar|energia eolica|biomassa|bacia do sao francisco|residuos solidos|convivencia com o semiarido)\\b",
  "Mar" = "\\b(maritim\\w*|naval|navais|oceanic\\w*|subaquatic\\w*|offshore|submarin\\w*|oceanos?|economia azul|portuari\\w*|navios?|rov|auv)\\b",
  "Digital" = "\\b(inteligencia artificial|ciberseguranca|iot|internet das coisas|software|ciencia de dados|inteligencia de dados|analise de dados|computacao|cidades inteligentes|hpc|supercomputacao|hardware|machine learning|aprendizado de maquina|quantic\\w*|blockchain|chatbot)\\b",
  "Sede e Park" = "\\b(manufatura|industria 4\\.0|nanotecnologia|materiais avancados|novos materiais|petroquimica|automotiv\\w*|eletromobilidade|processos industriais|embrapii|quimica verde)\\b"
)
CAMPUS_CASE_SENSITIVE_RULES <- list("Digital" = "\\b(IA|AI)\\b")

# Retorna data.frame(campus, evidencias) com uma linha por campus justificado.
infer_campus_candidates <- function(titulo = "", descricao = "", area_tematica = "", palavras_chave = "") {
  orig <- paste(titulo %||% "", descricao %||% "", area_tematica %||% "", palavras_chave %||% "", collapse = " ")
  norm <- normalize_text(orig)
  rows <- list()
  for (cp in names(CAMPUS_RULES)) {
    m <- regmatches(norm, gregexpr(CAMPUS_RULES[[cp]], norm, perl = TRUE))[[1]]
    if (cp %in% names(CAMPUS_CASE_SENSITIVE_RULES)) {
      m2 <- regmatches(orig, gregexpr(CAMPUS_CASE_SENSITIVE_RULES[[cp]], orig, perl = TRUE))[[1]]
      m <- c(m, m2)
    }
    m <- unique(m[nzchar(m)])
    if (length(m)) rows[[length(rows) + 1L]] <- data.frame(campus = cp, evidencias = paste(m, collapse = "; "),
                                                           stringsAsFactors = FALSE)
  }
  if (length(rows) == 0L) return(data.frame(campus = character(), evidencias = character(), stringsAsFactors = FALSE))
  do.call(rbind, rows)
}

# ─── Identidade estável (R07 / T20) ───────────────────────────────────────────
# Não inclui prazo, data de coleta nem título quando houver identificador oficial.

.URL_TRACKING_PARAMS <- c("utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "fbclid",
                          "gclid", "mc_cid", "mc_eid", "_ga", "jsessionid", "redirect",
                          "_com_liferay_asset_publisher_web_portlet_assetpublisherportlet_instance_l4rfxmc5nhcw_redirect")

canonical_url <- function(url) {
  u <- as.character(url %||% NA_character_)
  if (length(u) != 1L || is.na(u) || !nzchar(u)) return(NA_character_)
  u <- sub("#.*$", "", trimws(u))
  parts <- strsplit(u, "\\?", fixed = FALSE)[[1]]
  base <- tolower(sub("/+$", "", parts[[1]]))
  base <- sub("^http://", "https://", base)
  base <- sub("^https://www\\.", "https://", base)
  if (length(parts) < 2L) return(base)
  qs <- strsplit(paste(parts[-1], collapse = "?"), "&", fixed = TRUE)[[1]]
  keep <- qs[nzchar(qs)]
  keys <- tolower(sub("=.*$", "", keep))
  keep <- keep[!keys %in% .URL_TRACKING_PARAMS & !grepl("redirect$", keys) & !grepl("^(p_p_|_?p_r_p_(?!assetentryid))", keys, perl = TRUE)]
  if (length(keep) == 0L) return(base)
  paste0(base, "?", paste(sort(keep), collapse = "&"))
}

stable_opportunity_id <- function(source_id, call_id = NA_character_, url = NA_character_, title = NA_character_) {
  src <- as.character(source_id)
  key <- if (!is.na(call_id) && nzchar(trimws(call_id))) {
    paste("call", normalize_text(call_id))
  } else if (!is.na(canonical_url(url))) {
    paste("url", canonical_url(url))
  } else {
    paste("title", normalize_text(title))
  }
  h <- digest::digest(paste(src, key, sep = "||"), algo = "xxhash64")
  paste0(sanitize_id(src), "_", substr(h, 1L, 16L))
}

# Extrai identificador oficial de chamada (ex.: "IEAv-C0002/2024", "CPSI Nº 001/2026").
extract_call_id <- function(title) {
  t <- as.character(title %||% "")
  if (length(t) != 1L || is.na(t)) return(NA_character_)
  t <- gsub("\u00a0", " ", t, fixed = TRUE)
  m <- regmatches(t, regexec("(?i)(cpsi|edital|chamada|preg[aã]o)[^0-9]{0,40}?([A-Za-z]*-?[A-Za-z]*[0-9]+)\\s*/\\s*(20[0-9]{2})", t, perl = TRUE))[[1]]
  if (length(m) < 4L) return(NA_character_)
  kind <- toupper(normalize_text(m[[2]]))
  sprintf("%s-%s/%s", kind, toupper(m[[3]]), m[[4]])
}

# ─── Proveniência por campo (R02) ─────────────────────────────────────────────
PROVENANCE_KINDS <- c("oficial", "inferencia", "sugestao_ia")

make_provenance <- function(campo, valor = NA, url = NA_character_, trecho = NA_character_,
                            metodo = "html", tipo = "oficial", coletado_em = NULL) {
  stopifnot(tipo %in% PROVENANCE_KINDS)
  list(campo = campo, valor = if (length(valor) && !is.na(valor[[1]])) as.character(valor[[1]]) else NA_character_,
       url = as.character(url %||% NA_character_), trecho = substr(as.character(trecho %||% NA_character_), 1L, 300L),
       metodo = metodo, tipo = tipo,
       coletado_em = format(coletado_em %||% Sys.time(), "%Y-%m-%d %H:%M:%S"))
}

provenance_to_json <- function(entries) {
  entries <- Filter(function(e) !is.null(e) && !is.na(e$valor), entries)
  if (length(entries) == 0L) return(NA_character_)
  as.character(jsonlite::toJSON(entries, auto_unbox = TRUE, na = "null"))
}
