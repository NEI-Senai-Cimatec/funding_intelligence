
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

# Tokens proibidos nos chips/score (BUG-04/MH-01): anos, números, siglas sem semântica
.banned_match_tokens <- c(
  "2022", "2023", "2024", "2025", "2026", "2027", "2028", "2029", "2030",
  "cnpq", "capes", "finep", "fapesb", "fapes", "confap", "daad", "embrapii",
  "erc", "undp", "petrobras", "sigitec", "humboldt", "nsf", "doe", "horizon"
)

is_semantic_token <- function(term) {
  t <- normalize_text(term)
  nzchar(t) && !(t %in% .banned_match_tokens) && !grepl("^\\d+$", t)
}

# Termos da assinatura presentes no texto do registro (para chips explicáveis)
matched_keywords <- function(signature, text, keywords_extra = NULL) {
  if (is.null(signature) || length(signature) == 0) {
    return(character())
  }
  terms <- unique(normalize_text(c(signature$keywords %||% character(), keywords_extra %||% character())))
  terms <- terms[nzchar(terms) & vapply(terms, is_semantic_token, logical(1))]
  if (length(terms) == 0) return(character())
  norm_txt <- normalize_text(text)
  terms[vapply(terms, function(k) {
    pat <- tryCatch(term_to_pattern(k), error = function(e) "")
    nzchar(pat) && grepl(pat, norm_txt, ignore.case = TRUE, perl = TRUE)
  }, logical(1))]
}

compute_adherence_score <- function(df, conn, current_query = "", signature = NULL) {
  if (nrow(df) == 0) return(df)
  if (is.null(signature)) signature <- collect_interest_signature(conn, current_query = current_query)
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

recommend_opportunities <- function(conn, opportunities_df, current_query = "", top_n = 10, signature = NULL) {
  if (nrow(opportunities_df) == 0) return(opportunities_df)
  scored <- compute_adherence_score(opportunities_df, conn, current_query, signature = signature)
  tracked_ids <- if (is.null(conn)) character() else DBI::dbGetQuery(conn, "SELECT id_oportunidade FROM editais_rastreados")$id_oportunidade
  # BUG-01/11: recomendações usam status DERIVADO (nunca o campo congelado)
  scored$derived_status <- derive_status_vec(scored$data_limite, scored$data_abertura, scored$texto_bruto)
  scored |>
    dplyr::filter(!(id_registro %in% tracked_ids), derived_status != "encerrado") |>
    dplyr::select(-derived_status) |>
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

recommend_partners_for_opportunity <- function(conn, opportunity_id, top_n = 5) {
  if (is.null(conn) || is.na(opportunity_id) || !nzchar(opportunity_id)) {
    return(tibble::tibble())
  }
  
  opp <- DBI::dbGetQuery(
    conn, 
    "SELECT titulo, descricao_resumida, palavras_chave, area_tematica FROM oportunidades WHERE id_registro = ?",
    params = list(opportunity_id)
  )
  
  if (nrow(opp) == 0) return(tibble::tibble())
  
  researchers <- DBI::dbGetQuery(conn, "SELECT id, nome, email, instituicao, expertise FROM pesquisadores_vencedores")
  if (nrow(researchers) == 0) return(tibble::tibble())
  
  projects <- DBI::dbGetQuery(conn, "SELECT pesquisador_id, titulo_projeto, palavras_chave FROM projetos_aprovados")
  
  opp_text <- paste(opp$titulo[[1]], opp$descricao_resumida[[1]], opp$palavras_chave[[1]], opp$area_tematica[[1]], collapse = " ")
  
  scores <- purrr::map_dfr(seq_len(nrow(researchers)), function(i) {
    res_id <- researchers$id[[i]]
    res_name <- researchers$nome[[i]]
    res_email <- researchers$email[[i]]
    res_inst <- researchers$instituicao[[i]]
    res_exp <- researchers$expertise[[i]]
    
    res_projects <- projects |> dplyr::filter(pesquisador_id == res_id)
    proj_keywords <- paste(res_projects$palavras_chave, collapse = "; ")
    proj_titles <- paste(res_projects$titulo_projeto, collapse = " | ")
    
    all_terms <- unique(normalize_text(c(
      safe_split(res_exp),
      safe_split(proj_keywords)
    )))
    all_terms <- all_terms[nzchar(all_terms)]
    
    score <- if (length(all_terms) > 0) {
      keyword_overlap_score(opp_text, all_terms)
    } else {
      0
    }
    
    matched_terms <- character()
    if (length(all_terms) > 0) {
      norm_opp_text <- normalize_text(opp_text)
      matched_terms <- all_terms[vapply(all_terms, function(t) {
        pat <- tryCatch(term_to_pattern(t), error = function(e) "")
        if (!nzchar(pat)) return(FALSE)
        grepl(pat, norm_opp_text, ignore.case = TRUE, perl = TRUE)
      }, logical(1))]
    }
    matched_str <- paste(unique(matched_terms), collapse = "; ")
    
    tibble::tibble(
      id = res_id,
      nome = res_name,
      email = res_email,
      instituicao = res_inst,
      score_afinidade = round(score),
      projetos_passados = proj_titles,
      termos_correspondentes = matched_str
    )
  })
  
  scores |>
    dplyr::arrange(dplyr::desc(score_afinidade), nome) |>
    dplyr::slice_head(n = top_n)
}

