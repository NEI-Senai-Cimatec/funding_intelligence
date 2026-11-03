# R/helpers_report.R — Geração de relatórios de editais abertos por aderência

format_pt_date_long <- function(d_str) {
  if (is.null(d_str) || is.na(d_str) || !nzchar(as.character(d_str %||% ""))) {
    return("A verificar / Não informado")
  }
  d_clean <- as.character(d_str)[[1]]
  d <- tryCatch(as.Date(d_clean), error = function(e) NA)
  if (is.na(d)) {
    # Tenta padrão brasileiro DD/MM/YYYY
    d <- tryCatch(as.Date(d_clean, format = "%d/%m/%Y"), error = function(e) NA)
  }
  if (is.na(d)) return(d_clean)
  
  months_pt <- c(
    "janeiro", "fevereiro", "março", "abril", "maio", "junho",
    "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"
  )
  m_idx <- as.integer(format(d, "%m"))
  sprintf("%d de %s de %s", as.integer(format(d, "%d")), months_pt[m_idx], format(d, "%Y"))
}

format_budget_display <- function(val, moeda = "BRL", texto = "") {
  # 1. Se houver valor numérico positivo estruturado
  if (!is.null(val) && !is.na(val) && is.numeric(val) && val > 0) {
    curr <- toupper(as.character(moeda %||% "BRL")[[1]])
    sym <- switch(curr, "EUR" = "€", "USD" = "US$", "BRL" = "R$", "R$")
    formatted_num <- format(val, big.mark = ".", decimal.mark = ",", scientific = FALSE)
    
    # Texto descritivo por extenso aproximado para milhões/mil
    extenso <- ""
    if (val >= 1e9) {
      bi <- round(val / 1e9, 2)
      extenso <- sprintf(" (%s bilhões de %s)", gsub("\\.", ",", as.character(bi)), if (curr == "EUR") "euros" else if (curr == "USD") "dólares" else "reais")
    } else if (val >= 1e6) {
      mi <- round(val / 1e6, 2)
      extenso <- sprintf(" (%s milhões de %s)", gsub("\\.", ",", as.character(mi)), if (curr == "EUR") "euros" else if (curr == "USD") "dólares" else "reais")
    } else if (val >= 1e3) {
      mil <- round(val / 1e3, 1)
      extenso <- sprintf(" (%s mil %s)", gsub("\\.", ",", as.character(mil)), if (curr == "EUR") "euros" else if (curr == "USD") "dólares" else "reais")
    }
    
    return(sprintf("%s %s%s", sym, formatted_num, extenso))
  }
  
  # 2. Busca trechos de orçamento no texto bruto ou descrição
  if (!is.null(texto) && !is.na(texto) && nzchar(as.character(texto)[[1]])) {
    txt <- as.character(texto)[[1]]
    patterns <- c(
      "(R\\$|€|US\\$)\\s*[0-9]+[0-9.,]*\\s*(milhões|mil|milhoes|bilhões|bilhoes)?(?:\\s*\\([^)]+\\))?",
      "(?:orçamento|recursos|valor global|aporte)\\s*(?:de|estimado em|total de)?\\s*(R\\$|€|US\\$)?[0-9]+[0-9.,]*\\s*(milhões|mil|milhoes|bilhões)?"
    )
    for (pat in patterns) {
      m <- regmatches(txt, regexpr(pat, txt, ignore.case = TRUE))
      if (length(m) > 0 && nzchar(m[[1]])) {
        clean_m <- trimws(m[[1]])
        if (nchar(clean_m) >= 4) return(clean_m)
      }
    }
  }
  
  "Consulte o edital para detalhes do orçamento e limites de financiamento."
}

clean_opportunity_text <- function(txt, max_chars = 600L) {
  if (is.null(txt) || is.na(txt) || !nzchar(as.character(txt %||% ""))) {
    return("Consulte os detalhes da chamada no link oficial de acesso.")
  }
  # Remove tags HTML
  t <- gsub("<[^>]+>", " ", as.character(txt)[[1]])
  # Remove quebras de linha múltiplas e espaços extras
  t <- gsub("[\r\n\t]+", " ", t)
  t <- gsub("\\s+", " ", trimws(t))
  
  if (nchar(t) > max_chars) {
    t <- paste0(substr(t, 1L, max_chars - 3L), "...")
  }
  t
}

generate_single_report_item <- function(row, idx = 1L) {
  # Nome do Edital
  tit <- as.character(row$titulo %||% "Edital sem título")[[1]]
  id_chamada <- as.character(row$id_chamada %||% "")[[1]]
  entidade <- as.character(row$entidade %||% row$instituicao_financiadora %||% "")[[1]]
  
  # Monta título contextualizado se aplicável
  edital_nome <- tit
  if (nzchar(id_chamada) && !grepl(id_chamada, tit, fixed = TRUE)) {
    edital_nome <- paste0(id_chamada, " ", edital_nome)
  }
  if (nzchar(entidade) && !grepl(entidade, edital_nome, ignore.case = TRUE)) {
    edital_nome <- paste0(edital_nome, " ", entidade)
  }

  # Tipo de oportunidade
  tipo_raw <- tolower(as.character(row$tipo_oportunidade %||% "financiamento")[[1]])
  tipo <- switch(tipo_raw,
    "grant" = "Financiamento / Subvenção Internacional",
    "fellowship" = "Bolsa de Pesquisa e Capacitação",
    "bolsa" = "Bolsa",
    "edital" = "Chamada Pública / Financiamento",
    "subvencao" = "Subvenção Econômica",
    "premio" = "Prêmio / Reconhecimento",
    tools::toTitleCase(as.character(row$tipo_oportunidade %||% "Financiamento")[[1]])
  )

  # País de origem
  pais_raw <- as.character(row$pais_origem %||% "Brasil")[[1]]
  if (grepl("União Europeia|Europa|Alemanha", pais_raw, ignore.case = TRUE) && nzchar(entidade)) {
    pais_fmt <- sprintf("%s (%s)", pais_raw, entidade)
  } else {
    pais_fmt <- pais_raw
  }

  # Prazo limite de submissão
  prazo_raw <- as.character(row$data_limite %||% row$data_encerramento %||% "")[[1]]
  is_fluxo <- identical(row$fluxo_continuo[[1]], 1L) || identical(row$fluxo_continuo[[1]], 1) || identical(row$fluxo_continuo[[1]], "1")
  
  if (is_fluxo) {
    prazo_fmt <- "Fluxo Contínuo (inscrições permanentemente abertas)"
  } else {
    prazo_fmt <- format_pt_date_long(prazo_raw)
    if (grepl("Europa|União Europeia", pais_raw, ignore.case = TRUE)) {
      prazo_fmt <- paste0(prazo_fmt, " [até 17h00 (horário de Bruxelas)]")
    } else if (grepl("Brasil", pais_raw, ignore.case = TRUE)) {
      prazo_fmt <- paste0(prazo_fmt, " [até 23h59 (horário de Brasília)]")
    }
  }

  # Área temática
  area_raw <- as.character(row$area_tematica %||% "")[[1]]
  area <- if (nzchar(area_raw)) area_raw else "Multidisciplinar / Inovação Tecnológica"

  # Resumo
  resumo_raw <- row$descricao_resumida[[1]] %||% row$descricao_completa[[1]] %||% row$texto_bruto[[1]] %||% ""
  resumo <- clean_opportunity_text(resumo_raw, max_chars = 550L)

  # Orçamento estimado
  orcamento <- format_budget_display(row$valor_financiado[[1]], row$moeda[[1]], row$texto_bruto[[1]])

  # Link de acesso
  link_url <- as.character(row$link_detalhe[[1]] %||% row$link_origem[[1]] %||% row$link_documento_pdf[[1]] %||% "#")
  link_label <- if (nzchar(entidade)) entidade else "Portal Oficial do Edital"

  list(
    idx = idx,
    id_registro = row$id_registro[[1]] %||% paste0("rec_", idx),
    score = round(as.numeric(row$score_aderencia[[1]] %||% 0)),
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
    df$derived_status <- derive_status_df(df)
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

  # Garante score de aderência
  if (!"score_aderencia" %in% names(open_df)) {
    open_df$score_aderencia <- 0
  }

  # Ordena pelos editais com maiores aderências e prazo de encerramento mais próximo
  if ("data_limite" %in% names(open_df)) {
    open_df <- open_df |>
      dplyr::arrange(dplyr::desc(score_aderencia), parse_date_safe(data_limite))
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

  # Formatação em texto simples conforme padrão solicitado pelo usuário
  text_blocks <- vapply(items, function(it) {
    sprintf(
"%d:\n\nEdital: %s\n\nTipo de oportunidade: %s\n\nPaís de origem: %s\n\nPrazo limite de submissão: %s\n\nÁrea temática: %s\n\nResumo: %s\n\nOrçamento estimado: %s\n\nLink de acesso: %s (%s)",
      it$idx,
      it$edital,
      it$tipo,
      it$pais,
      it$prazo,
      it$area,
      it$resumo,
      it$orcamento,
      it$link_label,
      it$link_url
    )
  }, character(1))

  full_text <- paste(text_blocks, collapse = "\n\n\n")

  # Formatação Markdown
  md_blocks <- vapply(items, function(it) {
    sprintf(
"### %d. %s\n\n* **Tipo de oportunidade:** %s\n* **País de origem:** %s\n* **Prazo limite de submissão:** %s\n* **Área temática:** %s\n* **Orçamento estimado:** %s\n* **Link de acesso:** [%s](%s)\n\n**Resumo:**\n%s\n",
      it$idx,
      it$edital,
      it$tipo,
      it$pais,
      it$prazo,
      it$area,
      it$orcamento,
      it$link_label,
      it$link_url,
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
