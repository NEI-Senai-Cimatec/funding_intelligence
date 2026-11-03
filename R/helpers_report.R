# R/helpers_report.R — Geração de relatórios de editais abertos por aderência e campus
# SENAI CIMATEC – Núcleo de Economia Industrial (NEI)

safe_report_val <- function(row, col_name, default = "") {
  if (is.null(row) || nrow(row) == 0L || !col_name %in% names(row)) return(default)
  v <- row[[col_name]]
  if (is.null(v) || length(v) == 0L || is.na(v[[1]]) || !nzchar(as.character(v[[1]]))) return(default)
  as.character(v[[1]])
}

format_pt_date_long <- function(d_str, pais = "") {
  if (is.null(d_str) || length(d_str) == 0L || is.na(d_str[[1]]) || !nzchar(as.character(d_str[[1]]))) {
    return("A verificar / Não informado")
  }
  d_clean <- trimws(as.character(d_str[[1]]))
  if (identical(d_clean, "NA") || !nzchar(d_clean)) {
    return("A verificar / Não informado")
  }

  d <- tryCatch(as.Date(d_clean), error = function(e) NA)
  if (is.na(d)) {
    d <- tryCatch(as.Date(d_clean, format = "%d/%m/%Y"), error = function(e) NA)
  }
  if (is.na(d)) {
    d <- tryCatch(as.Date(d_clean, format = "%Y/%m/%d"), error = function(e) NA)
  }
  
  if (is.na(d)) {
    base_date <- d_clean
  } else {
    months_pt <- c(
      "janeiro", "fevereiro", "março", "abril", "maio", "junho",
      "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"
    )
    m_idx <- as.integer(format(d, "%m"))
    base_date <- sprintf("%d de %s de %s", as.integer(format(d, "%d")), months_pt[m_idx], format(d, "%Y"))
  }

  pais_check <- tolower(as.character(pais %||% ""))
  if (grepl("união europeia|uniao europeia|europa|eurohpc|bruxelas|alemanha", pais_check)) {
    paste0(base_date, " [até 17h00 (horário de Bruxelas)]")
  } else if (grepl("brasil|brasília|brasilia", pais_check) || !nzchar(pais_check)) {
    paste0(base_date, " [até 23h59 (horário de Brasília)]")
  } else if (grepl("estados unidos|eua|usa|washington", pais_check)) {
    paste0(base_date, " [até 17h00 (horário de Washington / ET)]")
  } else {
    base_date
  }
}

format_budget_display <- function(val, moeda = "BRL", texto = "") {
  # 1. Se houver valor numérico positivo estruturado
  if (!is.null(val) && length(val) > 0L && !is.na(val[[1]])) {
    num_val <- suppressWarnings(as.numeric(val[[1]]))
    if (!is.na(num_val) && num_val > 0) {
      curr <- toupper(as.character(moeda %||% "BRL")[[1]])
      sym <- switch(curr, "EUR" = "€", "USD" = "US$", "BRL" = "R$", "R$")
      formatted_num <- format(round(num_val, 2), big.mark = ".", decimal.mark = ",", scientific = FALSE)
      
      extenso <- ""
      if (num_val >= 1e9) {
        bi <- round(num_val / 1e9, 2)
        extenso <- sprintf(" (%s bilhões de %s)", gsub("\\.", ",", as.character(bi)), if (curr == "EUR") "euros" else if (curr == "USD") "dólares" else "reais")
      } else if (num_val >= 1e6) {
        mi <- round(num_val / 1e6, 2)
        extenso <- sprintf(" (%s milhões de %s)", gsub("\\.", ",", as.character(mi)), if (curr == "EUR") "euros" else if (curr == "USD") "dólares" else "reais")
      } else if (num_val >= 1e3) {
        mil <- round(num_val / 1e3, 1)
        extenso <- sprintf(" (%s mil %s)", gsub("\\.", ",", as.character(mil)), if (curr == "EUR") "euros" else if (curr == "USD") "dólares" else "reais")
      }
      
      return(sprintf("%s %s%s", sym, formatted_num, extenso))
    }
  }
  
  # 2. Busca trechos de orçamento no texto bruto ou descrição
  if (!is.null(texto) && length(texto) > 0L && !is.na(texto[[1]])) {
    txt <- as.character(texto[[1]])
    if (nzchar(txt)) {
      patterns <- c(
        "(R\\$|€|US\\$)\\s*[0-9]+[0-9.,]*\\s*(milhões|mil|milhoes|bilhões|bilhoes)?(?:\\s*\\([^)]+\\))?",
        "(?:orçamento|recursos|valor global|aporte)\\s*(?:de|estimado em|total de)?\\s*(R\\$|€|US\\$)?[0-9]+[0-9.,]*\\s*(milhões|mil|milhoes|bilhões)?"
      )
      for (pat in patterns) {
        m <- regmatches(txt, regexpr(pat, txt, ignore.case = TRUE))
        if (length(m) > 0L && !is.na(m[[1]]) && nzchar(m[[1]])) {
          clean_m <- trimws(m[[1]])
          if (nchar(clean_m) >= 4) return(clean_m)
        }
      }
    }
  }
  
  "Consulte o edital para detalhes do orçamento e limites de financiamento."
}

clean_opportunity_text <- function(txt, max_chars = 600L) {
  if (is.null(txt) || length(txt) == 0L || is.na(txt[[1]]) || !nzchar(as.character(txt[[1]]))) {
    return("Consulte os detalhes da chamada no link oficial de acesso.")
  }
  t <- gsub("<[^>]+>", " ", as.character(txt[[1]]))
  t <- gsub("[\r\n\t]+", " ", t)
  t <- gsub("\\s+", " ", trimws(t))
  
  if (identical(t, "NA") || !nzchar(t)) {
    return("Consulte os detalhes da chamada no link oficial de acesso.")
  }
  
  if (nchar(t) > max_chars) {
    t <- paste0(substr(t, 1L, max_chars - 3L), "...")
  }
  t
}

generate_single_report_item <- function(row, idx = 1L) {
  # 1. Nome do Edital
  tit <- safe_report_val(row, "titulo", "Edital sem título")
  id_chamada <- safe_report_val(row, "id_chamada", "")
  entidade <- safe_report_val(row, "entidade", safe_report_val(row, "instituicao_financiadora", ""))
  
  edital_nome <- tit
  if (nzchar(id_chamada) && !grepl(id_chamada, edital_nome, fixed = TRUE)) {
    edital_nome <- paste0(id_chamada, " ", edital_nome)
  }
  if (nzchar(entidade) && !grepl(entidade, edital_nome, fixed = TRUE)) {
    edital_nome <- paste0(edital_nome, " ", entidade)
  }

  # 2. Tipo de oportunidade
  tipo_raw <- tolower(safe_report_val(row, "tipo_oportunidade", "financiamento"))
  tipo <- if (grepl("grant|coopera|internacional", tipo_raw)) {
    "Financiamento Cooperação Internacional"
  } else if (grepl("bolsa|fellowship", tipo_raw)) {
    "Bolsa"
  } else if (grepl("subvenc", tipo_raw)) {
    "Subvenção Econômica"
  } else if (grepl("premio|award", tipo_raw)) {
    "Prêmio / Reconhecimento"
  } else if (grepl("licita", tipo_raw)) {
    "Licitação / Encomenda Tecnológica"
  } else {
    "Financiamento"
  }

  # 3. País de origem
  pais_val <- safe_report_val(row, "pais_origem", "")
  if (!nzchar(pais_val)) {
    comb_info <- paste(tit, entidade, safe_report_val(row, "link_origem", ""))
    if (grepl("horizon|eurohpc|cordis|união europeia|uniao europeia|europa", comb_info, ignore.case = TRUE)) {
      pais_val <- "União Europeia"
    } else if (grepl("humboldt", comb_info, ignore.case = TRUE)) {
      pais_val <- "Alemanha"
    } else if (grepl("doe|energy\\.gov|nsf|nih|genesis", comb_info, ignore.case = TRUE)) {
      pais_val <- "Estados Unidos"
    } else {
      pais_val <- "Brasil"
    }
  }

  pais_fmt <- pais_val
  if (grepl("União Europeia|Europa", pais_val, ignore.case = TRUE)) {
    if (grepl("EuroHPC", entidade, ignore.case = TRUE)) {
      pais_fmt <- "União Europeia (EuroHPC JU)"
    } else if (nzchar(entidade)) {
      pais_fmt <- sprintf("União Europeia (%s)", entidade)
    } else {
      pais_fmt <- "União Europeia"
    }
  } else if (grepl("Alemanha", pais_val, ignore.case = TRUE) && grepl("Humboldt", entidade, ignore.case = TRUE)) {
    pais_fmt <- "Alemanha (Alexander von Humboldt Foundation)"
  }

  # 4. Prazo limite de submissão
  prazo_raw <- safe_report_val(row, "data_limite", safe_report_val(row, "data_encerramento", ""))
  is_fluxo <- FALSE
  if ("fluxo_continuo" %in% names(row)) {
    fc <- row$fluxo_continuo[[1]]
    is_fluxo <- isTRUE(fc == 1 || fc == "1" || fc == TRUE)
  }
  
  if (is_fluxo) {
    prazo_fmt <- "Fluxo Contínuo (inscrições permanentemente abertas)"
  } else {
    prazo_fmt <- format_pt_date_long(prazo_raw, pais_fmt)
  }

  # 5. Área temática
  area_raw <- safe_report_val(row, "area_tematica", "")
  area <- if (nzchar(area_raw) && !identical(area_raw, "NA")) {
    area_raw
  } else {
    "Multidisciplinar / Inovação Tecnológica"
  }

  # 6. Resumo
  resumo_raw <- safe_report_val(row, "descricao_resumida", safe_report_val(row, "descricao_completa", safe_report_val(row, "texto_bruto", "")))
  resumo <- clean_opportunity_text(resumo_raw, max_chars = 550L)

  # 7. Orçamento estimado
  val_fin <- if ("valor_financiado" %in% names(row)) row$valor_financiado[[1]] else NULL
  moeda_val <- safe_report_val(row, "moeda", "BRL")
  txt_bruto <- safe_report_val(row, "texto_bruto", resumo_raw)
  orcamento <- format_budget_display(val_fin, moeda_val, txt_bruto)

  # 8. Link de acesso
  link_url <- safe_report_val(row, "link_detalhe", safe_report_val(row, "link_origem", safe_report_val(row, "link_documento_pdf", "")))
  link_label <- if (nzchar(entidade)) {
    entidade
  } else if (grepl("horizon|eurohpc", tit, ignore.case = TRUE)) {
    "Horizon HPC"
  } else if (grepl("cnpq|capes", tit, ignore.case = TRUE)) {
    "CNPQ/CAPES"
  } else {
    "Portal Oficial do Edital"
  }

  score_val <- 0
  if ("score_aderencia" %in% names(row)) {
    s <- row$score_aderencia[[1]]
    if (!is.null(s) && !is.na(s)) score_val <- round(as.numeric(s))
  }

  list(
    idx = idx,
    id_registro = safe_report_val(row, "id_registro", paste0("rec_", idx)),
    score = score_val,
    edital = edital_nome,
    tipo = tipo,
    pais = pais_fmt,
    prazo = prazo_fmt,
    area = area,
    resumo = resumo,
    orcamento = orcamento,
    link_url = link_url,
    link_label = link_label
  )
}

generate_adherence_report <- function(opportunities_df, max_items = 4L) {
  if (is.null(opportunities_df) || nrow(opportunities_df) == 0L) {
    return(list(
      count = 0L,
      items = list(),
      text = "Nenhum edital aberto encontrado para o filtro selecionado.",
      markdown = "### Nenhum edital aberto encontrado para o filtro selecionado."
    ))
  }

  df <- opportunities_df

  # Garante status derivado atualizado
  if (!"derived_status" %in% names(df)) {
    if (exists("derive_status_df", mode = "function")) {
      df$derived_status <- derive_status_df(df)
    } else {
      df$derived_status <- "aberto"
    }
  }

  # Filtra EXCLUSIVAMENTE editais abertos no momento da geração
  open_df <- df |> dplyr::filter(derived_status %in% c("aberto", "encerrando"))

  if (nrow(open_df) == 0L) {
    return(list(
      count = 0L,
      items = list(),
      text = "Nenhum edital com status 'Aberto' encontrado para o filtro selecionado no momento da geração.",
      markdown = "### Nenhum edital com status 'Aberto' encontrado para o filtro selecionado."
    ))
  }

  # Garante score de aderência numérico
  if (!"score_aderencia" %in% names(open_df)) {
    open_df$score_aderencia <- 0
  } else {
    open_df$score_aderencia <- suppressWarnings(as.numeric(open_df$score_aderencia %||% 0))
    open_df$score_aderencia[is.na(open_df$score_aderencia)] <- 0
  }

  # Ordena pelos editais com maiores aderências (score desc) e prazo de encerramento mais próximo
  if ("data_limite" %in% names(open_df) && exists("parse_date_safe", mode = "function")) {
    parsed_dl <- parse_date_safe(open_df$data_limite)
    # Substitui NAs por data distante para não priorizar datas nulas antes de datas válidas
    parsed_dl[is.na(parsed_dl)] <- as.Date("2099-12-31")
    open_df$tmp_dl_sort <- parsed_dl
    open_df <- open_df |>
      dplyr::arrange(dplyr::desc(score_aderencia), tmp_dl_sort)
  } else {
    open_df <- open_df |>
      dplyr::arrange(dplyr::desc(score_aderencia))
  }

  # Seleciona até 4 oportunidades
  selected_df <- open_df |> dplyr::slice_head(n = as.integer(max_items))
  n_selected <- nrow(selected_df)

  items <- lapply(seq_len(n_selected), function(i) {
    generate_single_report_item(selected_df[i, , drop = FALSE], idx = i)
  })

  # Formatação em texto simples conforme padrão exato solicitado pelo usuário
  text_blocks <- vapply(items, function(it) {
    link_str <- if (nzchar(it$link_url) && !identical(it$link_url, "#")) {
      sprintf("%s (%s)", it$link_label, it$link_url)
    } else {
      it$link_label
    }

    sprintf(
"%d:\n\nEdital: %s\n\nTipo de oportunidade: %s\n\nPaís de origem: %s\n\nPrazo limite de submissão: %s\n\nÁrea temática: %s\n\nResumo: %s\n\nOrçamento estimado: %s\n\nLink de acesso: %s",
      it$idx,
      it$edital,
      it$tipo,
      it$pais,
      it$prazo,
      it$area,
      it$resumo,
      it$orcamento,
      link_str
    )
  }, character(1))

  full_text <- paste(text_blocks, collapse = "\n\n\n")

  # Formatação Markdown
  md_blocks <- vapply(items, function(it) {
    link_md <- if (nzchar(it$link_url) && !identical(it$link_url, "#")) {
      sprintf("[%s](%s)", it$link_label, it$link_url)
    } else {
      it$link_label
    }

    sprintf(
"### %d. %s\n\n* **Tipo de oportunidade:** %s\n* **País de origem:** %s\n* **Prazo limite de submissão:** %s\n* **Área temática:** %s\n* **Orçamento estimado:** %s\n* **Link de acesso:** %s\n\n**Resumo:**\n%s\n",
      it$idx,
      it$edital,
      it$tipo,
      it$pais,
      it$prazo,
      it$area,
      it$orcamento,
      link_md,
      it$resumo
    )
  }, character(1))

  full_md <- paste(md_blocks, collapse = "\n---\n\n")

  list(
    count = n_selected,
    items = items,
    text = full_text,
    markdown = full_md
  )
}
