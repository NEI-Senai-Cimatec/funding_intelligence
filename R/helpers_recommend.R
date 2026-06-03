
read_profile <- function(conn) {
  if (is.null(conn)) return(NULL)
  profile <- DBI::dbGetQuery(conn, "SELECT * FROM perfil_usuario LIMIT 1")
  if (nrow(profile) == 0) return(NULL)
  profile
}

profile_to_lists <- function(profile_row) {
  if (is.null(profile_row) || nrow(profile_row) == 0) return(list())
  list(
    keywords = normalize_text(safe_split(profile_row$palavras_chave_preferidas[[1]])),
    areas = normalize_text(safe_split(profile_row$areas_preferidas[[1]])),
    countries = normalize_text(safe_split(profile_row$paises_preferidos[[1]])),
    funders = normalize_text(safe_split(profile_row$financiadores_preferidos[[1]])),
    types = normalize_text(safe_split(profile_row$tipos_oportunidade_preferidos[[1]])),
    eligibility = normalize_text(safe_split(profile_row$elegibilidade_preferida[[1]]))
  )
}

collect_interest_signature <- function(conn, current_query = "") {
  profile <- read_profile(conn)
  profile_lists <- profile_to_lists(profile)
  history <- if (is.null(conn)) data.frame(query_text = character()) else DBI::dbGetQuery(conn, "SELECT query_text FROM historico_buscas ORDER BY executed_at DESC LIMIT 10")
  tracked <- if (is.null(conn)) data.frame() else DBI::dbGetQuery(conn, "SELECT o.palavras_chave, o.area_tematica, o.entidade FROM editais_rastreados t JOIN oportunidades o ON o.id_registro = t.id_oportunidade")
  history_terms <- unique(unlist(lapply(history$query_text, extract_query_terms)))
  tracked_terms <- unique(c(safe_split(tracked$palavras_chave), safe_split(tracked$area_tematica), tracked$entidade))
  current_terms <- extract_query_terms(current_query)
  list(
    keywords = unique(normalize_text(c(profile_lists$keywords, history_terms, tracked_terms, current_terms))),
    areas = unique(normalize_text(c(profile_lists$areas, safe_split(tracked$area_tematica)))),
    countries = unique(profile_lists$countries),
    funders = unique(normalize_text(c(profile_lists$funders, tracked$entidade))),
    types = unique(profile_lists$types),
    eligibility = unique(profile_lists$eligibility)
  )
}

keyword_overlap_score <- function(text, keywords) {
  keywords <- unique(normalize_text(keywords))
  keywords <- keywords[nzchar(keywords)]
  if (length(keywords) == 0) return(0)
  text <- normalize_text(text)
  hits <- vapply(keywords, function(k) grepl(term_to_pattern(k), text, ignore.case = TRUE, perl = TRUE), logical(1))
  100 * mean(hits)
}

compute_adherence_score <- function(df, conn, current_query = "") {
  if (nrow(df) == 0) return(df)
  signature <- collect_interest_signature(conn, current_query = current_query)
  current_terms <- extract_query_terms(current_query)
  active_keywords <- unique(c(normalize_text(current_terms), signature$keywords))
  text_index <- build_search_text(df, text_cols = c("titulo", "subtitulo", "descricao_resumida", "descricao_completa", "palavras_chave", "area_tematica", "elegibilidade"))
  keyword_scores <- vapply(text_index, keyword_overlap_score, numeric(1), keywords = active_keywords)
  theme_scores <- vapply(seq_len(nrow(df)), function(i) keyword_overlap_score(paste(df$area_tematica[[i]], df$palavras_chave[[i]], collapse = " "), signature$areas), numeric(1))
  funder_scores <- vapply(normalize_text(df$entidade), function(f) ifelse(f %in% signature$funders, 100, 0), numeric(1))
  country_scores <- vapply(normalize_text(df$pais_origem), function(p) ifelse(length(signature$countries) == 0 || p %in% signature$countries, 100, 0), numeric(1))
  eligibility_scores <- vapply(normalize_text(df$elegibilidade), function(e) keyword_overlap_score(e, signature$eligibility), numeric(1))
  total <- 0.40 * keyword_scores + 0.20 * theme_scores + 0.15 * funder_scores + 0.10 * country_scores + 0.15 * eligibility_scores
  df$score_aderencia <- round(total)
  df
}

recommend_opportunities <- function(conn, opportunities_df, current_query = "", top_n = 10) {
  if (nrow(opportunities_df) == 0) return(opportunities_df)
  scored <- compute_adherence_score(opportunities_df, conn, current_query)
  tracked_ids <- if (is.null(conn)) character() else DBI::dbGetQuery(conn, "SELECT id_oportunidade FROM editais_rastreados")$id_oportunidade
  scored |>
    dplyr::filter(!(id_registro %in% tracked_ids), status_oportunidade != "encerrado") |>
    dplyr::arrange(dplyr::desc(score_aderencia), parse_date_safe(data_limite)) |>
    dplyr::slice_head(n = top_n)
}

find_potential_collaborators <- function(conn, current_query = "", top_n = 10) {
  if (is.null(conn)) return(tibble::tibble())
  collaborators <- DBI::dbReadTable(conn, "colaboradores")
  if (nrow(collaborators) == 0) return(collaborators)
  signature <- collect_interest_signature(conn, current_query = current_query)
  interest_terms <- unique(c(signature$keywords, signature$areas, extract_query_terms(current_query)))
  collaborators |>
    dplyr::mutate(similarity = vapply(paste(nome, instituicao, area, palavras_chave), keyword_overlap_score, numeric(1), keywords = interest_terms)) |>
    dplyr::arrange(dplyr::desc(similarity), nome) |>
    dplyr::slice_head(n = top_n)
}
