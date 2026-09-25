app_path <- "app.R"
txt <- readLines(app_path, encoding = "UTF-8", warn = FALSE)

# 1. Update filter_campus choices (remove Todos os Campi, add Sede e Park with logo)
old_choices_1 <- '"<img src=\'logos/logo.png\' height=\'14px\' style=\'vertical-align: middle; margin-right: 4px;\'> Todos os Campi" = "Todos",'
txt <- txt[!grepl(old_choices_1, txt, fixed = TRUE)]

txt <- gsub('"🏭 Park" = "Park"', '"<img src=\'logos/logo.png\' height=\'14px\' style=\'vertical-align: middle; margin-right: 4px;\'> Sede e Park" = "Sede e Park"', txt, fixed = TRUE)
txt <- gsub('"Park"', '"Sede e Park"', txt, fixed = TRUE)

# 2. Update save_search_campus choices
txt <- gsub('c("Todos", "Aeroespacial", "Sertão", "Mar", "Digital", "Sede e Park")', 'c("Aeroespacial", "Sertão", "Mar", "Digital", "Sede e Park")', txt, fixed = TRUE)
txt <- gsub('current_campus <- if (length(input$filter_campus) > 0 && !"Todos" %in% input$filter_campus) input$filter_campus[[1]] else "Todos"', 'current_campus <- if (length(input$filter_campus) > 0) input$filter_campus[[1]] else "Sede e Park"', txt, fixed = TRUE)

# 3. Update filtered_saved_searches
old_filtered <- '    if (length(sel_campi) == 0 || "Todos" %in% sel_campi) {'
new_filtered <- '    if (length(sel_campi) == 0) {'
txt <- gsub(old_filtered, new_filtered, txt, fixed = TRUE)
txt <- gsub('c_val == "Todos" || c_val == "Geral / Multicampi" || is.na(c_val) || ', '', txt, fixed = TRUE)

# 4. Update Buscas salvas tab layout to add "Executar todas as buscas salvas" button
old_tab <- '    bslib::nav_panel(
      "Buscas salvas",
      tags$div(
        style = "min-height: 480px; padding: 0.75rem 0; clear: both;",
        DTOutput("saved_searches_table")
      )
    ),'

new_tab <- '    bslib::nav_panel(
      "Buscas salvas",
      tags$div(
        style = "min-height: 480px; padding: 0.75rem 0; clear: both;",
        tags$div(
          style = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.25rem;",
          tags$h5(style = "margin: 0; color: #004691; font-weight: 700;", "Buscas Salvas por Campus"),
          actionButton("btn_run_all_saved_searches", "Executar todas as buscas salvas", class = "btn-primary", icon = icon("play"))
        ),
        DTOutput("saved_searches_table")
      )
    ),'

txt_str <- paste(txt, collapse = "\n")
txt_str <- gsub(old_tab, new_tab, txt_str, fixed = TRUE)
txt <- strsplit(txt_str, "\n", fixed = TRUE)[[1]]

# 5. Remove Executar button inside Consulta cell in output$saved_searches_table
old_consulta_sprintf <- '            sprintf(
              \'<div style="display: flex; align-items: center; gap: 8px;">
                <div style="max-height: 55px; width: 400px; min-width: 200px; overflow-y: auto; font-size: 0.78rem; font-family: monospace; white-space: pre-wrap; word-break: break-word; background: #f8f9fa; padding: 4px 8px; border-radius: 4px; border: 1px solid #dee2e6; flex-grow: 1;">
                  %s
                </div>
                <button type="button" class="btn btn-sm btn-outline-secondary" style="padding: 2px 8px; font-size: 0.75rem; white-space: nowrap; height: 30px;" onclick="navigator.clipboard.writeText(this.getAttribute(\\\'\'data-query\\\'\')); Shiny.setInputValue(\\\'\'query_copied_notify\\\'; Math.random());" data-query="%s" title="Copiar consulta">
                  <i class="fa-regular fa-copy"></i> Copiar
                </button>
                <button type="button" class="btn btn-sm btn-primary" style="padding: 2px 8px; font-size: 0.75rem; white-space: nowrap; height: 30px;" onclick="Shiny.setInputValue(\\\'\'run_saved_search_id\\\'; %d, {priority: \\\'\'event\\\'\'});" title="Executar esta busca">
                  <i class="fa-solid fa-play"></i> Executar
                </button>
              </div>\',
              q_esc,
              q_esc,
              as.integer(id_val)
            )'

# Replace Consulta cell formatting in saved_searches_table
old_consulta_code <- '          Consulta = vapply(seq_len(dplyr::n()), function(i) {
            id_val <- id[[i]]
            q_esc <- htmltools::htmlEscape(query_text[[i]])
            sprintf(
              \'<div style="display: flex; align-items: center; gap: 8px;">
                <div style="max-height: 55px; width: 400px; min-width: 200px; overflow-y: auto; font-size: 0.78rem; font-family: monospace; white-space: pre-wrap; word-break: break-word; background: #f8f9fa; padding: 4px 8px; border-radius: 4px; border: 1px solid #dee2e6; flex-grow: 1;">
                  %s
                </div>
                <button type="button" class="btn btn-sm btn-outline-secondary" style="padding: 2px 8px; font-size: 0.75rem; white-space: nowrap; height: 30px;" onclick="navigator.clipboard.writeText(this.getAttribute(\'data-query\')); Shiny.setInputValue(\'query_copied_notify\', Math.random());" data-query="%s" title="Copiar consulta">
                  <i class="fa-regular fa-copy"></i> Copiar
                </button>
                <button type="button" class="btn btn-sm btn-primary" style="padding: 2px 8px; font-size: 0.75rem; white-space: nowrap; height: 30px;" onclick="Shiny.setInputValue(\'run_saved_search_id\', %d, {priority: \'event\'});" title="Executar esta busca">
                  <i class="fa-solid fa-play"></i> Executar
                </button>
              </div>\',
              q_esc,
              q_esc,
              as.integer(id_val)
            )
          }, character(1))'

new_consulta_code <- '          Consulta = vapply(query_text, function(q) {
            q_esc <- htmltools::htmlEscape(q)
            sprintf(
              \'<div style="display: flex; align-items: center; gap: 8px;">
                <div style="max-height: 55px; width: 440px; min-width: 220px; overflow-y: auto; font-size: 0.78rem; font-family: monospace; white-space: pre-wrap; word-break: break-word; background: #f8f9fa; padding: 4px 8px; border-radius: 4px; border: 1px solid #dee2e6; flex-grow: 1;">
                  %s
                </div>
                <button type="button" class="btn btn-sm btn-outline-secondary" style="padding: 2px 8px; font-size: 0.75rem; white-space: nowrap; height: 30px;" onclick="navigator.clipboard.writeText(this.getAttribute(\'data-query\')); Shiny.setInputValue(\'query_copied_notify\', Math.random());" data-query="%s" title="Copiar consulta">
                  <i class="fa-regular fa-copy"></i> Copiar
                </button>
              </div>\',
              q_esc,
              q_esc
            )
          }, character(1))'

txt_str <- paste(txt, collapse = "\n")
txt_str <- gsub(old_consulta_code, new_consulta_code, txt_str, fixed = TRUE)

# Add btn_run_all_saved_searches observer in server
btn_run_all_code <- '
  observeEvent(input$btn_run_all_saved_searches, {
    searches <- filtered_saved_searches()
    if (nrow(searches) == 0) {
      showNotification("Nenhuma busca salva encontrada para executar.", type = "warning")
      return()
    }
    combined_query <- paste(sprintf("(%s)", searches$query_text), collapse = " OR ")
    updateTextInput(session, "search_query", value = combined_query)
    execute_search(combined_query, save_history = FALSE)
    if (!is.null(conn)) {
      now_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      for (id_val in searches$id) {
        mark_saved_search_run(conn, id_val)
        idx_match <- which(rv$saved_searches$id == id_val)
        if (length(idx_match) > 0) {
          rv$saved_searches$last_run_at[idx_match] <- now_str
        }
      }
    }
    bslib::nav_select(id = "main_tabs", selected = "Resultados", session = session)
    showNotification("Todas as buscas salvas foram executadas com sucesso!", type = "message", duration = 4)
  })
'

if (!any(grepl("btn_run_all_saved_searches", txt_str, fixed = TRUE))) {
  txt_str <- gsub('  observeEvent(input$run_saved_search_id, {', paste0(btn_run_all_code, '\n  observeEvent(input$run_saved_search_id, {'), txt_str, fixed = TRUE)
}

txt <- strsplit(txt_str, "\n", fixed = TRUE)[[1]]

writeLines(txt, app_path, useBytes = TRUE)
cat("Updated app.R successfully\n")
