# R/helpers_reports.R
# Módulo de Geradores do Boletim Semanal e Revisão Mensal de Oportunidades

#' Extrai o link mais específico e direto para o edital/oportunidade
get_effective_edital_link <- function(row) {
  link_d <- if ("link_detalhe" %in% names(row)) row$link_detalhe[[1]] %||% "" else ""
  link_o <- if ("link_origem" %in% names(row)) row$link_origem[[1]] %||% "" else ""

  link_d <- trimws(as.character(link_d))
  link_o <- trimws(as.character(link_o))

  is_invalid <- function(l) {
    !nzchar(l) || is.na(l) || grepl("linkedin\\.com|facebook\\.com|instagram\\.com|youtube\\.com|/sobre|/about|/contato", l, ignore.case = TRUE)
  }

  if (!is_invalid(link_d)) return(link_d)
  if (!is_invalid(link_o)) return(link_o)

  if (nzchar(link_d) && !is.na(link_d)) return(link_d)
  if (nzchar(link_o) && !is.na(link_o)) return(link_o)

  "https://www.google.com"
}

#' Gera o Boletim Semanal de Oportunidades (últimos 7 dias)
#' @param conn Conexão com o banco de dados
#' @param reference_date Data de referência (default: hoje)
#' @return Lista contendo metadados, tibble dos registros, texto markdown e HTML
generate_weekly_bulletin <- function(conn, reference_date = Sys.Date()) {
  if (is.character(reference_date)) reference_date <- as.Date(reference_date)
  
  # Data de corte: 7 dias atrás (segunda-feira anterior)
  start_date <- reference_date - 7
  
  opps <- filter_validated(tibble::as_tibble(read_table(conn, "oportunidades")))
  if (nrow(opps) == 0) {
    return(list(title = "Boletim Semanal de Oportunidades", count = 0, opps = tibble::tibble(), markdown = "Nenhum registro encontrado.", html = "<p>Nenhum registro encontrado.</p>"))
  }
  
  # Derivar status dinamicamente
  opps$derived_status <- derive_status_df(opps)
  
  # Filtrar oportunidades coletadas nos últimos 7 dias OU com prazo nos próximos 14 dias
  opps_filtered <- opps |>
    dplyr::filter(
      (parse_date_safe(data_hora_coleta) >= start_date) |
      (parse_date_safe(data_publicacao) >= start_date) |
      (derived_status == "encerrando")
    ) |>
    dplyr::filter(derived_status != "encerrado")
  
  if (nrow(opps_filtered) == 0) {
    # Fallback para exibir todas as abertas mais recentes
    opps_filtered <- opps |>
      dplyr::filter(derived_status != "encerrado") |>
      dplyr::arrange(dplyr::desc(parse_date_safe(data_publicacao))) |>
      dplyr::slice_head(n = 15)
  }
  
  # Garantir avaliação naval/offshore em todos os registros
  if (!"aderencia_naval_nivel" %in% names(opps_filtered)) opps_filtered$aderencia_naval_nivel <- NA_character_
  if (!"aderencia_naval_justificativa" %in% names(opps_filtered)) opps_filtered$aderencia_naval_justificativa <- NA_character_
  if (!"ideia_projeto_consorcio" %in% names(opps_filtered)) opps_filtered$ideia_projeto_consorcio <- NA_character_

  for (i in seq_len(nrow(opps_filtered))) {
    if (is.na(opps_filtered$aderencia_naval_nivel[[i]]) || !nzchar(opps_filtered$aderencia_naval_nivel[[i]] %||% "")) {
      eval_res <- evaluate_naval_offshore_adherence(
        titulo = opps_filtered$titulo[[i]],
        descricao = opps_filtered$descricao_resumida[[i]],
        texto_bruto = opps_filtered$texto_bruto[[i]],
        entidade = opps_filtered$entidade[[i]],
        use_ai = FALSE
      )
      opps_filtered$aderencia_naval_nivel[[i]] <- eval_res$aderencia_naval_nivel %||% "Baixa"
      opps_filtered$aderencia_naval_justificativa[[i]] <- eval_res$aderencia_naval_justificativa %||% ""
      opps_filtered$ideia_projeto_consorcio[[i]] <- eval_res$ideia_projeto_consorcio %||% NA_character_
    }
  }
  
  # Ordenar por aderência naval e prazo limite
  opps_filtered <- opps_filtered |>
    dplyr::mutate(
      naval_rank = dplyr::case_when(
        aderencia_naval_nivel == "Muito alta" ~ 1,
        aderencia_naval_nivel == "Alta" ~ 2,
        aderencia_naval_nivel == "Média" ~ 3,
        TRUE ~ 4
      )
    ) |>
    dplyr::arrange(naval_rank, parse_date_safe(data_limite))
  
  # Formatação Markdown
  md <- sprintf("# 📰 BOLETIM SEMANAL DE OPORTUNIDADES — RADAR DE FOMENTO\n\n")
  md <- paste0(md, sprintf("**Período de Referência:** %s a %s\n", format(start_date, "%d/%m/%Y"), format(reference_date, "%d/%m/%Y")))
  md <- paste0(md, sprintf("**Total de Oportunidades Identificadas no Período:** %d\n\n", nrow(opps_filtered)))
  md <- paste0(md, "---\n\n## 🎯 Destaques com Alta Aderência ao Núcleo Naval & Offshore de PD&I\n\n")
  
  high_adherence <- opps_filtered |> dplyr::filter(aderencia_naval_nivel %in% c("Muito alta", "Alta"))
  if (nrow(high_adherence) > 0) {
    for (i in seq_len(nrow(high_adherence))) {
      row <- high_adherence[i, ]
      eff_link <- get_effective_edital_link(row)
      md <- paste0(md, sprintf("### ⚓ [%s] %s\n", row$aderencia_naval_nivel, row$titulo))
      md <- paste0(md, sprintf("- **Instituição / Financiador:** %s\n", row$entidade))
      md <- paste0(md, sprintf("- **Prazo Limite:** %s\n", format_date_br(row$data_limite)))
      md <- paste0(md, sprintf("- **Conexão Naval/Offshore:** %s\n", row$aderencia_naval_justificativa %||% "N/A"))
      if (!is.null(row$ideia_projeto_consorcio) && !is.na(row$ideia_projeto_consorcio) && nzchar(row$ideia_projeto_consorcio)) {
        md <- paste0(md, sprintf("- **💡 Ideia de Projeto & Consórcio Recomendado:** %s\n", row$ideia_projeto_consorcio))
      }
      md <- paste0(md, sprintf("- **Link Oficial:** [%s](%s)\n\n", eff_link, eff_link))
    }
  } else {
    md <- paste0(md, "_Nenhuma oportunidade de alta aderência registrada nesta semana._\n\n")
  }
  
  md <- paste0(md, "--- \n\n## 📋 Todas as Chamadas e Editais do Período\n\n")
  for (i in seq_len(nrow(opps_filtered))) {
    row <- opps_filtered[i, ]
    eff_link <- get_effective_edital_link(row)
    md <- paste0(md, sprintf("1. **[%s](%s)** (%s) — Prazo: %s | Aderência Naval: **%s**\n", row$titulo, eff_link, row$entidade, format_date_br(row$data_limite), row$aderencia_naval_nivel %||% "N/A"))
  }
  
  # Formatação HTML estilizada
  html <- sprintf("
  <div style='font-family: system-ui, sans-serif; color: #0f172a; max-width: 900px; margin: 0 auto; padding: 20px; background: #ffffff; border-radius: 8px;'>
    <div style='border-bottom: 3px solid #004691; padding-bottom: 15px; margin-bottom: 20px;'>
      <h1 style='color: #004691; margin: 0; font-size: 1.75rem;'>📰 BOLETIM SEMANAL DE OPORTUNIDADES</h1>
      <p style='color: #64748b; margin: 5px 0 0 0;'>Radar da Inovação — Núcleo Naval & Offshore de PD&I | %s a %s</p>
    </div>
    <div style='background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 15px; margin-bottom: 25px;'>
      <strong>Total de Oportunidades no Período:</strong> %d editais e chamadas identificadas
    </div>
    <h2 style='color: #004691; font-size: 1.3rem; border-left: 4px solid #004691; padding-left: 10px;'>🎯 Oportunidades com Alta Aderência Naval & Offshore</h2>
  ", format(start_date, "%d/%m/%Y"), format(reference_date, "%d/%m/%Y"), nrow(opps_filtered))
  
  if (nrow(high_adherence) > 0) {
    for (i in seq_len(nrow(high_adherence))) {
      row <- high_adherence[i, ]
      eff_link <- get_effective_edital_link(row)
      badge_bg <- if (identical(row$aderencia_naval_nivel, "Muito alta")) "#15803d" else "#16a34a"
      html <- paste0(html, sprintf("
        <div style='border: 1px solid #cbd5e1; border-radius: 8px; padding: 16px; margin-bottom: 16px; background: #ffffff;'>
          <div style='display: flex; justify-content: space-between; align-items: flex-start;'>
            <h3 style='margin: 0 0 8px 0; color: #0f172a; font-size: 1.1rem;'>%s</h3>
            <span style='background: %s; color: white; font-size: 0.75rem; font-weight: bold; padding: 3px 8px; border-radius: 12px;'>Aderência %s</span>
          </div>
          <p style='margin: 4px 0; font-size: 0.9rem; color: #475569;'><strong>Financiador:</strong> %s | <strong>Prazo Limite:</strong> %s</p>
          <p style='margin: 8px 0; font-size: 0.9rem; color: #334155;'>%s</p>
          %s
          <p style='margin: 10px 0 0 0;'><a href='%s' target='_blank' style='color: #004691; font-weight: bold; text-decoration: none;'>Acessar Edital Oficial &rarr;</a></p>
        </div>
      ", row$titulo, badge_bg, row$aderencia_naval_nivel, row$entidade, format_date_br(row$data_limite),
      row$aderencia_naval_justificativa %||% "",
      if (!is.null(row$ideia_projeto_consorcio) && !is.na(row$ideia_projeto_consorcio) && nzchar(row$ideia_projeto_consorcio)) sprintf("<div style='background: #f0fdf4; border-left: 3px solid #16a34a; padding: 10px; margin-top: 10px; font-size: 0.85rem; color: #166534;'><strong>💡 Ideia de Projeto / Consórcio:</strong> %s</div>", row$ideia_projeto_consorcio) else "",
      eff_link
      ))
    }
  } else {
    html <- paste0(html, "<p style='color: #64748b;'><em>Nenhuma oportunidade de alta aderência registrada nesta semana.</em></p>")
  }
  
  html <- paste0(html, "</div>")
  
  list(
    title = "Boletim Semanal de Oportunidades",
    period = sprintf("%s a %s", format(start_date, "%d/%m/%Y"), format(reference_date, "%d/%m/%Y")),
    count = nrow(opps_filtered),
    opps = opps_filtered,
    markdown = md,
    html = html
  )
}

#' Gera a Revisão Mensal de Oportunidades (Mês Anterior + Abertas no Mês Corrente)
#' @param conn Conexão com o banco de dados
#' @param reference_date Data de referência (default: hoje)
#' @return Lista contendo metadados, tibble dos registros, texto markdown e HTML
generate_monthly_review <- function(conn, reference_date = Sys.Date()) {
  if (is.character(reference_date)) reference_date <- as.Date(reference_date)
  
  # Determinar o mês anterior completo
  current_month_first <- as.Date(format(reference_date, "%Y-%m-01"))
  prev_month_end <- current_month_first - 1
  prev_month_start <- as.Date(format(prev_month_end, "%Y-%m-01"))
  
  opps <- filter_validated(tibble::as_tibble(read_table(conn, "oportunidades")))
  if (nrow(opps) == 0) {
    return(list(title = "Revisão Mensal de Oportunidades", count = 0, opps = tibble::tibble(), markdown = "Nenhum registro encontrado.", html = "<p>Nenhum registro encontrado.</p>"))
  }
  
  opps$derived_status <- derive_status_df(opps)
  
  # Oportunidades do mês anterior ou ainda abertas no mês corrente
  opps_monthly <- opps |>
    dplyr::filter(
      (parse_date_safe(data_publicacao) >= prev_month_start & parse_date_safe(data_publicacao) <= prev_month_end) |
      (derived_status %in% c("aberto", "encerrando"))
    )
  
  if (nrow(opps_monthly) == 0) {
    opps_monthly <- opps |> dplyr::filter(derived_status != "encerrado")
  }
  
  # Garantir avaliação naval
  if (!"aderencia_naval_nivel" %in% names(opps_monthly)) opps_monthly$aderencia_naval_nivel <- NA_character_
  if (!"aderencia_naval_justificativa" %in% names(opps_monthly)) opps_monthly$aderencia_naval_justificativa <- NA_character_
  if (!"ideia_projeto_consorcio" %in% names(opps_monthly)) opps_monthly$ideia_projeto_consorcio <- NA_character_

  for (i in seq_len(nrow(opps_monthly))) {
    if (is.na(opps_monthly$aderencia_naval_nivel[[i]]) || !nzchar(opps_monthly$aderencia_naval_nivel[[i]] %||% "")) {
      eval_res <- evaluate_naval_offshore_adherence(
        titulo = opps_monthly$titulo[[i]],
        descricao = opps_monthly$descricao_resumida[[i]],
        texto_bruto = opps_monthly$texto_bruto[[i]],
        entidade = opps_monthly$entidade[[i]],
        use_ai = FALSE
      )
      opps_monthly$aderencia_naval_nivel[[i]] <- eval_res$aderencia_naval_nivel %||% "Baixa"
      opps_monthly$aderencia_naval_justificativa[[i]] <- eval_res$aderencia_naval_justificativa %||% ""
      opps_monthly$ideia_projeto_consorcio[[i]] <- eval_res$ideia_projeto_consorcio %||% NA_character_
    }
  }
  
  opps_monthly <- opps_monthly |>
    dplyr::mutate(
      naval_rank = dplyr::case_when(
        aderencia_naval_nivel == "Muito alta" ~ 1,
        aderencia_naval_nivel == "Alta" ~ 2,
        aderencia_naval_nivel == "Média" ~ 3,
        TRUE ~ 4
      )
    ) |>
    dplyr::arrange(naval_rank, parse_date_safe(data_limite))
  
  month_name <- format(prev_month_start, "%B de %Y")
  
  # Markdown
  md <- sprintf("# 📊 REVISÃO MENSAL DE OPORTUNIDADES — %s\n\n", toupper(month_name))
  md <- paste0(md, sprintf("**Mês Calendário Analisado:** %s a %s\n", format(prev_month_start, "%d/%m/%Y"), format(prev_month_end, "%d/%m/%Y")))
  md <- paste0(md, sprintf("**Total de Oportunidades Mapeadas:** %d\n\n", nrow(opps_monthly)))
  md <- paste0(md, "## 🌊 Panorama do Núcleo Naval & Offshore de PD&I\n\n")
  
  high_adherence <- opps_monthly |> dplyr::filter(aderencia_naval_nivel %in% c("Muito alta", "Alta"))
  if (nrow(high_adherence) > 0) {
    for (i in seq_len(nrow(high_adherence))) {
      row <- high_adherence[i, ]
      eff_link <- get_effective_edital_link(row)
      md <- paste0(md, sprintf("### 🚢 %s (%s)\n", row$titulo, row$entidade))
      md <- paste0(md, sprintf("- **Aderência Naval:** %s\n", row$aderencia_naval_nivel))
      md <- paste0(md, sprintf("- **Prazo Limite:** %s\n", format_date_br(row$data_limite)))
      md <- paste0(md, sprintf("- **Análise Objetiva:** %s\n", row$aderencia_naval_justificativa %||% "N/A"))
      if (!is.null(row$ideia_projeto_consorcio) && !is.na(row$ideia_projeto_consorcio) && nzchar(row$ideia_projeto_consorcio)) {
        md <- paste0(md, sprintf("- **💡 Consórcio / Projeto:** %s\n", row$ideia_projeto_consorcio))
      }
      md <- paste0(md, sprintf("- **Link Oficial:** [%s](%s)\n\n", eff_link, eff_link))
    }
  } else {
    md <- paste0(md, "_Nenhuma oportunidade de alta aderência registrada para este mês._\n\n")
  }
  
  # HTML
  html <- sprintf("
  <div style='font-family: system-ui, sans-serif; color: #0f172a; max-width: 900px; margin: 0 auto; padding: 20px; background: #ffffff; border-radius: 8px;'>
    <div style='border-bottom: 3px solid #004691; padding-bottom: 15px; margin-bottom: 20px;'>
      <h1 style='color: #004691; margin: 0; font-size: 1.75rem;'>📊 REVISÃO MENSAL DE OPORTUNIDADES</h1>
      <p style='color: #64748b; margin: 5px 0 0 0;'>Balanço Consolidado de Fomento | Mês: %s</p>
    </div>
    <div style='background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 15px; margin-bottom: 25px;'>
      <strong>Total de Oportunidades Mapeadas no Mês:</strong> %d editais e chamadas ativas
    </div>
    <h2 style='color: #004691; font-size: 1.3rem;'>⚓ Oportunidades Estratégicas para o Núcleo Naval & Offshore</h2>
  ", month_name, nrow(opps_monthly))
  
  if (nrow(high_adherence) > 0) {
    for (i in seq_len(nrow(high_adherence))) {
      row <- high_adherence[i, ]
      eff_link <- get_effective_edital_link(row)
      html <- paste0(html, sprintf("
        <div style='border: 1px solid #cbd5e1; border-radius: 8px; padding: 16px; margin-bottom: 16px;'>
          <h3 style='margin: 0 0 8px 0; color: #004691;'>%s</h3>
          <p style='margin: 4px 0; font-size: 0.9rem;'><strong>Instituição:</strong> %s | <strong>Prazo:</strong> %s | <strong>Aderência:</strong> %s</p>
          <p style='margin: 8px 0; font-size: 0.9rem;'>%s</p>
          %s
          <p style='margin: 10px 0 0 0;'><a href='%s' target='_blank' style='color: #004691; font-weight: bold; text-decoration: none;'>Acessar Edital Oficial &rarr;</a></p>
        </div>
      ", row$titulo, row$entidade, format_date_br(row$data_limite), row$aderencia_naval_nivel,
      row$aderencia_naval_justificativa %||% "",
      if (!is.null(row$ideia_projeto_consorcio) && !is.na(row$ideia_projeto_consorcio) && nzchar(row$ideia_projeto_consorcio)) sprintf("<div style='background: #f0fdf4; border-left: 3px solid #16a34a; padding: 8px; font-size: 0.85rem;'><strong>💡 Projeto/Consórcio:</strong> %s</div>", row$ideia_projeto_consorcio) else "",
      eff_link
      ))
    }
  }
  
  html <- paste0(html, "</div>")
  
  list(
    title = sprintf("Revisão Mensal de Oportunidades — %s", month_name),
    period = sprintf("%s a %s", format(prev_month_start, "%d/%m/%Y"), format(prev_month_end, "%d/%m/%Y")),
    count = nrow(opps_monthly),
    opps = opps_monthly,
    markdown = md,
    html = html
  )
}
