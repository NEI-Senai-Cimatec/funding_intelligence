# helpers_taxonomy.R
# Camada canônica de categorização de tipo_oportunidade.
#
# O valor bruto coletado/gerado pela IA é preservado em
# `tipo_oportunidade_original`; o filtro e a UI usam
# `tipo_oportunidade_categoria` (slug ASCII estável).

categorias_tipo_oportunidade <- function() {
  c(
    edital_chamada = "Editais, Chamadas e Apoio",
    bolsa_fellowship = "Bolsas e Fellowships",
    premio = "Prêmios",
    licitacao_contratacao = "Licitações e Contratações",
    outros = "Outros"
  )
}

# Formato esperado pelo Shiny: nomes = labels exibidos, valores = slugs.
categorias_tipo_oportunidade_choices <- function() {
  cats <- categorias_tipo_oportunidade()
  out <- names(cats)
  names(out) <- unname(cats)
  out
}

.normalizar_tipo_chave <- function(x) {
  x <- normalize_text(x)
  x <- gsub("[_/\\-]+", " ", x, perl = TRUE)
  x <- gsub("\\s+", " ", x, perl = TRUE)
  trimws(x)
}

.tipo_oportunidade_genericos <- c(
  "", "oportunidade", "outros", "outro", "programa", "projeto",
  "desconhecido", "nao informado", "nao classificado", "n a", "na", "null"
)

# Mapa explícito dos valores conhecidos (chaves já normalizadas).
.tipo_oportunidade_mapa <- c(
  # Slugs canônicos (idempotência; chaves já passam pela normalização)
  "edital chamada" = "edital_chamada",
  "bolsa fellowship" = "bolsa_fellowship",
  "premio" = "premio",
  "licitacao contratacao" = "licitacao_contratacao",
  "outros" = "outros",

  # Editais, chamadas e apoio
  "edital" = "edital_chamada",
  "edital (grant opportunity)" = "edital_chamada",
  "edital de fomento para pesquisa em supercondutores" = "edital_chamada",
  "chamada" = "edital_chamada",
  "chamada publica" = "edital_chamada",
  "convocatoria" = "edital_chamada",
  "convocatoria publica" = "edital_chamada",
  "grant" = "edital_chamada",
  "grant opportunity" = "edital_chamada",
  "nofo" = "edital_chamada",
  "notice of funding opportunity" = "edital_chamada",
  "call for proposals" = "edital_chamada",
  "call for applications" = "edital_chamada",
  "subvencao" = "edital_chamada",
  "nao reembolsavel" = "edital_chamada",
  "auxilio" = "edital_chamada",
  "apoio institucional" = "edital_chamada",
  "financiamento" = "edital_chamada",
  "incentivo" = "edital_chamada",

  # Bolsas e fellowships
  "bolsa" = "bolsa_fellowship",
  "bolsa estudo" = "bolsa_fellowship",
  "bolsa pesquisa" = "bolsa_fellowship",
  "fellowship" = "bolsa_fellowship",
  "scholarship" = "bolsa_fellowship",
  "msca" = "bolsa_fellowship",
  "horizon tma msca cofund doctoral programme" = "bolsa_fellowship",
  "horizon tma msca cofund postdoctoral programme" = "bolsa_fellowship",
  "horizon tma msca postdoctoral fellowships global fellowships" = "bolsa_fellowship",

  # Prêmios
  "award" = "premio",
  "prize" = "premio",

  # Licitações e contratações
  "licitacao" = "licitacao_contratacao",
  "contratacao" = "licitacao_contratacao",
  "consultoria" = "licitacao_contratacao",
  "tender" = "licitacao_contratacao",
  "procurement" = "licitacao_contratacao",

  # Outros
  "guia de notificacoes sistema de comunicacao" = "outros"
)

.inferir_categoria_por_titulo <- function(titulo) {
  titulo <- .normalizar_tipo_chave(titulo)
  if (!nzchar(titulo)) {
    return(NA_character_)
  }

  if (grepl("\\bpremio\\b|\\baward\\b|\\bprize\\b", titulo, perl = TRUE)) {
    return("premio")
  }
  if (grepl("msca|fellowship|scholarship|\\bbolsa\\b|doctoral programme|postdoctoral", titulo, perl = TRUE)) {
    return("bolsa_fellowship")
  }
  if (grepl("licita|contratacao|consultoria|tender|procurement", titulo, perl = TRUE)) {
    return("licitacao_contratacao")
  }
  if (grepl("subven|nao reembols|auxilio|\\bapoio\\b|financiamento|incentivo", titulo, perl = TRUE)) {
    return("edital_chamada")
  }
  if (grepl("\\bedital\\b|\\bchamada\\b|convoc|\\bgrant\\b|call for|nof(o|a)|notice of funding", titulo, perl = TRUE)) {
    return("edital_chamada")
  }

  NA_character_
}

#' Categoriza um tipo de oportunidade e informa a origem da decisão.
#'
#' @param tipo Valor bruto de `tipo_oportunidade`.
#' @param titulo Título do registro (usado quando o tipo é nulo/genérico).
#' @param fonte Fonte oficial (usada como último fallback antes de "outros").
#' @return list(categoria, origem), em que origem é "bruto", "override",
#'   "titulo", "fonte" ou "outros".
categorizar_tipo_oportunidade_detalhado <- function(tipo = NA_character_,
                                                    titulo = NA_character_,
                                                    fonte = NA_character_) {
  tipo_key <- .normalizar_tipo_chave(tipo)
  titulo_key <- .normalizar_tipo_chave(titulo)
  fonte_key <- .normalizar_tipo_chave(fonte)

  # Overrides pontuais para rótulos visivelmente incorretos na origem.
  if (identical(tipo_key, "apoio institucional") &&
      nzchar(titulo_key) &&
      grepl("\\bpremio\\b", titulo_key, perl = TRUE)) {
    return(list(categoria = "premio", origem = "override"))
  }
  if (identical(tipo_key, "grant") &&
      nzchar(titulo_key) &&
      grepl("msca|cofund", titulo_key, perl = TRUE)) {
    return(list(categoria = "bolsa_fellowship", origem = "override"))
  }

  if (nzchar(tipo_key) && tipo_key %in% names(.tipo_oportunidade_mapa)) {
    return(list(categoria = unname(.tipo_oportunidade_mapa[[tipo_key]]), origem = "bruto"))
  }

  # Só inferimos por título/fonte quando o tipo está ausente ou é genérico.
  # Valores livres desconhecidos não são adivinhados: vão para "outros".
  if (tipo_key %in% .tipo_oportunidade_genericos) {
    categoria_titulo <- .inferir_categoria_por_titulo(titulo_key)
    if (!is.na(categoria_titulo)) {
      return(list(categoria = categoria_titulo, origem = "titulo"))
    }
    if (fonte_key %in% c("horizon europe", "horizon_europe", "quantum", "erc")) {
      return(list(categoria = "edital_chamada", origem = "fonte"))
    }
  }

  list(categoria = "outros", origem = "outros")
}

categorizar_tipo_oportunidade <- function(tipo = NA_character_,
                                          titulo = NA_character_,
                                          fonte = NA_character_) {
  categorizar_tipo_oportunidade_detalhado(tipo, titulo, fonte)$categoria
}

categorizar_tipo_oportunidade_vec <- function(tipo,
                                              titulo = NA_character_,
                                              fonte = NA_character_) {
  n <- length(tipo)
  if (n == 0L) {
    return(character())
  }
  tipo <- as.character(tipo)
  titulo <- if (is.null(titulo)) rep(NA_character_, n) else rep_len(as.character(titulo), n)
  fonte <- if (is.null(fonte)) rep(NA_character_, n) else rep_len(as.character(fonte), n)

  vapply(
    seq_len(n),
    function(i) categorizar_tipo_oportunidade(tipo[[i]], titulo[[i]], fonte[[i]]),
    character(1)
  )
}

mapear_tipos_para_categorias <- function(x) {
  x <- x %||% character()
  if (length(x) == 0L) {
    return(character())
  }
  unique(categorizar_tipo_oportunidade_vec(x))
}

rotulo_categoria_tipo <- function(x) {
  if (is.null(x) || length(x) == 0L || all(is.na(x))) {
    return("Outros")
  }
  x <- as.character(x[[1]])
  cats <- categorias_tipo_oportunidade()
  label <- unname(cats[x])
  if (length(label) == 1L && !is.na(label)) label else x
}

rotulo_categoria_tipo_vec <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(character())
  }
  vapply(x, rotulo_categoria_tipo, character(1))
}
