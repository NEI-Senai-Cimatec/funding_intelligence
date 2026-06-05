# Configura biblioteca local para contornar problemas de permissões de escrita globais
local_libs <- file.path(getwd(), "R_libs")
if (!dir.exists(local_libs)) dir.create(local_libs, showWarnings = FALSE)
.libPaths(c(local_libs, .libPaths()))

required_packages <- c(
  "shiny", "bslib", "DT", "dplyr", "tidyr", "purrr", "stringr", "stringi", "lubridate",
  "ggplot2", "plotly", "DBI", "RSQLite", "jsonlite", "digest", "htmltools",
  "rvest", "xml2", "httr2", "tibble", "tools", "readr", "writexl", "janitor",
  "glue", "progress", "pdftools", "polite", "callr", "shinycssloaders"
)

install_missing_packages <- function(pkgs) {
  if (length(pkgs) == 0) return(invisible(TRUE))

  repos <- getOption("repos")
  if (is.null(repos) || identical(unname(repos[["CRAN"]]), "@CRAN@") || is.na(repos[["CRAN"]])) {
    options(repos = c(CRAN = "https://cloud.r-project.org"))
  }

  message("Instalando pacotes ausentes em R_libs: ", paste(pkgs, collapse = ", "))

  for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      tryCatch(
        install.packages(pkg, dependencies = TRUE, lib = local_libs),
        error = function(e) {
          message(sprintf("Falha ao instalar o pacote '%s': %s", pkg, e$message))
        }
      )
    }
  }

  invisible(TRUE)
}

missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  install_missing_packages(missing_packages)
}

missing_after_install <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_after_install) > 0) {
  stop(
    sprintf(
      paste0(
        "Não foi possível carregar/instalar todos os pacotes necessários. ",
        "Instale manualmente e tente novamente: %s"
      ),
      paste(missing_after_install, collapse = ", ")
    ),
    call. = FALSE
  )
}

invisible(lapply(required_packages, library, character.only = TRUE))
# callr::r_bg() é usado para execução em background (sem future)

get_app_dir <- function() {
  ofiles <- character(0)
  for (i in rev(seq_len(sys.nframe()))) {
    fr <- sys.frame(i)
    if (exists("ofile", envir = fr, inherits = FALSE)) {
      candidate <- get("ofile", envir = fr, inherits = FALSE)
      if (is.character(candidate) && length(candidate) == 1 && nzchar(candidate)) {
        ofiles <- c(ofiles, candidate)
      }
    }
  }
  if (length(ofiles) > 0) {
    return(dirname(normalizePath(ofiles[[1]], winslash = "/", mustWork = FALSE)))
  }
  if (file.exists(file.path(getwd(), "app.R"))) {
    return(normalizePath(getwd(), winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

app_dir <- get_app_dir()
app_file <- function(...) file.path(app_dir, ...)

if (!exists("ensure_dir", mode = "function")) {
  ensure_dir <- function(path) {
    if (is.null(path) || !nzchar(path)) return(invisible(FALSE))
    if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
    invisible(dir.exists(path))
  }
}

safe_source <- function(path) {
  full_path <- app_file(path)
  out <- try(source(full_path, local = TRUE, encoding = "UTF-8"), silent = TRUE)
  if (inherits(out, "try-error")) {
    warning(sprintf("Não foi possível carregar %s. O app seguirá com fallbacks quando possível.", full_path), call. = FALSE)
  }
  invisible(out)
}

safe_source("R/helpers_utils.R")
safe_source("R/helpers_db.R")
safe_source("R/helpers_text.R")
safe_source("R/helpers_ai.R")
safe_source("R/helpers_recommend.R")
safe_source("R/helpers_collect.R")

db_path <- app_file("funding_intelligence.sqlite")
export_dir <- app_file("data_exports")
log_path <- app_file("logs", "funding_collection.log")
ensure_dir(export_dir)
ensure_dir(dirname(log_path))

try(init_database(db_path), silent = TRUE)
conn <- tryCatch(get_db_connection(db_path), error = function(e) NULL)
onStop(function() {
  if (!is.null(conn) && DBI::dbIsValid(conn)) DBI::dbDisconnect(conn)
})

build_sidebar <- function() {
  bslib::sidebar(
    open = "closed",
    width = 0,
    tags$div(style = "display:none;")
  )
}

ui <- bslib::page_sidebar(
  fillable = FALSE,
  title = tags$div(
    class = "app-header",
    tags$div(
      class = "logo-container",
      tags$img(src = "senai_cimatec.jpg", height = "36px", alt = "SENAI CIMATEC")
    ),
    tags$div(
      class = "app-title-main",
      h2("Funding Intelligence Hub"),
      p("Busca booleana, monitoramento de editais e recomendação a partir do banco local.")
    )
  ),
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly", primary = "#004691", secondary = "#0f172a"),
  sidebar = build_sidebar(),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
    tags$script("
      Shiny.addCustomMessageHandler('scroll-logs', function(message) {
        setTimeout(function() {
          var log_elem = document.getElementById('modal_log_text');
          if (log_elem) {
            log_elem.parentElement.scrollTop = log_elem.parentElement.scrollHeight;
          }
        }, 50);
      });
    ")
  ),

  bslib::card(
    class = "search-card",
    bslib::layout_columns(
      col_widths = c(5, 3, 1, 1, 1, 1),
      textInput("search_query", "Barra de busca principal", value = "", placeholder = "Ex.: (health OR medical devices) AND innovation NOT veterinary"),
      radioButtons("region_filter", "Região das fontes", choices = c("Brasileiras", "Europeias", "Ambas"), selected = "Ambas", inline = TRUE),
      actionButton("btn_search", "Buscar", class = "btn-primary action-top"),
      actionButton("btn_advanced", "Busca avançada", class = "btn-outline-primary action-top"),
      actionButton("btn_save_search", "Salvar busca", class = "btn-outline-secondary action-top"),
      actionButton("btn_collect_official", "Atualizar base", class = "btn-success action-top")
    )
  ),

  bslib::layout_column_wrap(
    width = 1 / 4,
    bslib::value_box(title = "Registros visíveis", value = textOutput("total_editais")),
    bslib::value_box(title = "Fontes ativas", value = textOutput("total_fontes")),
    bslib::value_box(title = "Urgentes (14 dias)", value = textOutput("total_urgentes")),
    bslib::value_box(title = "Última coleta", value = textOutput("ultima_coleta"))
  ),

  bslib::navset_card_tab(
    id = "main_tabs",
    bslib::nav_panel(
      "Resultados",
      bslib::card(
        bslib::layout_columns(
          col_widths = c(4, 4, 4),
          uiOutput("collection_status_ui"),
          uiOutput("source_counter_ui"),
          uiOutput("export_status_ui")
        )
      ),
      shinycssloaders::withSpinner(DTOutput("results_table"), type = 6, color = "#004691")
    ),
    bslib::nav_panel(
      "Por financiador",
      bslib::layout_columns(
        col_widths = c(7, 5),
        bslib::card(plotlyOutput("funders_plot", height = 360)),
        bslib::card(
          selectInput("selected_funder", "Instituição financiadora", choices = NULL),
          uiOutput("funder_profile")
        )
      ),
      DTOutput("funders_table")
    ),
    bslib::nav_panel(
      "Buscas salvas",
      DTOutput("saved_searches_table")
    ),
    bslib::nav_panel(
      "Editais rastreados",
      bslib::layout_columns(
        col_widths = c(8, 4),
        DTOutput("tracked_table"),
        tags$div(
          bslib::card(
            h5("Atualizar rastreamento"),
            selectInput("tracked_status_input", "Status", choices = c("avaliar", "prioritário", "submetido", "descartado"), selected = "avaliar"),
            textAreaInput("tracked_notes_input", "Observações", width = "100%", rows = 6),
            actionButton("btn_update_tracked", "Salvar atualização", class = "btn-primary w-100 mb-2"),
            actionButton("btn_remove_tracked", "Remover da lista", class = "btn-outline-danger w-100")
          ),
          bslib::card(
            h5("Potenciais Parceiros (CIMATEC)"),
            uiOutput("tracked_partners_ui")
          )
        )
      )
    ),
    bslib::nav_panel(
      "Recomendados para mim",
      bslib::layout_columns(
        col_widths = c(8, 4),
        bslib::card(DTOutput("recommended_table")),
        bslib::card(uiOutput("profile_summary"))
      ),
      bslib::card(h4("Colaboradores potenciais por tema"), DTOutput("collaborators_table"))
    ),
    bslib::nav_panel(
      "Logs",
      DTOutput("logs_table")
    )
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(
    opportunities = tibble::tibble(),
    sources = tibble::tibble(),
    saved_searches = tibble::tibble(),
    tracked = tibble::tibble(),
    history = tibble::tibble(),
    profile = tibble::tibble(),
    collaborators = tibble::tibble(),
    logs = tibble::tibble(),
    current_query = "",
    advanced_filters = list(),
    last_collect_summary = list(msg = "Base pronta.", n = 0L, exports = NULL),
    selected_tracked_id = NULL,
    collecting = FALSE
  )

  refresh_data <- function(notify = FALSE) {
    data <- tryCatch(
      {
        if (is.null(conn)) stop("Conexão SQLite indisponível.", call. = FALSE)
        read_app_data(conn)
      },
      error = function(e) {
        if (isTRUE(notify)) showNotification(paste("Falha ao carregar a base:", e$message), type = "error", duration = 8)
        fallback_app_data()
      }
    )
    rv$opportunities <- tibble::as_tibble(data$opportunities)
    rv$sources <- tibble::as_tibble(data$sources)
    rv$saved_searches <- tibble::as_tibble(data$saved_searches)
    rv$tracked <- tibble::as_tibble(data$tracked)
    rv$history <- tibble::as_tibble(data$history)
    rv$profile <- tibble::as_tibble(data$profile)
    rv$collaborators <- tibble::as_tibble(data$collaborators)
    rv$logs <- tibble::as_tibble(data$logs)
    invisible(TRUE)
  }

  refresh_data()

  # Reactive values para rastreamento de progresso de coleta
  progress_rv <- reactiveValues(
    step = 0,
    total = 1,
    percentage = 0,
    detail = "Iniciando...",
    phase = "Scraping",
    logs = "",
    status = "idle"
  )

  # Leitor reativo de status/logs da coleta em segundo plano (polling a cada 1.5s)
  observe({
    req(progress_rv$status %in% c("running", "done", "error"))
    
    # Polling contínuo enquanto status == running
    if (progress_rv$status == "running") {
      invalidateLater(1500, session)
    }
    
    status_file <- app_file("logs", "collection_status.json")
    log_file <- app_file("logs", "collection_modal_log.txt")
    
    # Ler arquivo de status JSON
    if (file.exists(status_file)) {
      status_data <- tryCatch(jsonlite::fromJSON(status_file, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(status_data)) {
        progress_rv$step <- status_data$step %||% 0
        progress_rv$total <- status_data$total %||% 1
        progress_rv$percentage <- status_data$percentage %||% 0
        progress_rv$detail <- status_data$detail %||% ""
        progress_rv$phase <- status_data$phase %||% "Scraping"
        if (identical(status_data$status, "done")) {
          progress_rv$status <- "done"
        } else if (identical(status_data$status, "error")) {
          progress_rv$status <- "error"
        }
      }
    }
    
    # Ler arquivo de log de texto
    if (file.exists(log_file)) {
      log_lines <- tryCatch(readLines(log_file, warn = FALSE), error = function(e) character())
      progress_rv$logs <- paste(log_lines, collapse = "\n")
      session$sendCustomMessage("scroll-logs", list())
    }
    
    # Detectar quando o processo background terminou
    proc <- rv$bg_process
    if (!is.null(proc) && !proc$is_alive()) {
      result <- tryCatch(proc$get_result(), error = function(e) e)
      rv$bg_process <- NULL
      
      if (inherits(result, "error") || inherits(result, "simpleError")) {
        # Falha na coleta
        removeNotification("bg_collect_notif")
        rv$collecting <- FALSE
        updateActionButton(session, "btn_collect_official", label = "Atualizar base")
        progress_rv$status <- "error"
        progress_rv$detail <- paste("Erro na coleta:", conditionMessage(result))
        log_progress(paste("Erro fatal:", conditionMessage(result)), "Erro")
        showNotification(paste("Falha na coleta em segundo plano:", conditionMessage(result)), type = "error", duration = 10)
      } else {
        # Coleta finalizada com sucesso
        removeNotification("bg_collect_notif")
        rv$collecting <- FALSE
        updateActionButton(session, "btn_collect_official", label = "Atualizar base")
        progress_rv$status <- "done"
        progress_rv$percentage <- 100
        progress_rv$detail <- "Coleta concluída com sucesso!"
        rv$last_collect_summary <- result
        refresh_data(notify = TRUE)
        
        base_msg <- sprintf(
          "Coleta concluida. %s registros inseridos/atualizados nesta rodada; %s registros totais na base; %s fonte(s) processadas.",
          result$inserted_now %||% 0L,
          result$n_records %||% 0L,
          result$sources_processed %||% 0L
        )
        showNotification(base_msg, type = "message", duration = 10)
        
        if (length(result$export_warnings %||% character()) > 0) {
          showNotification(paste(result$export_warnings, collapse = " | "), type = "warning", duration = 12)
        }
        
        check_and_alert_failures(rv$bg_start_time)
      }
    }
  })

  # Renderizadores dinâmicos para o modal de progresso
  output$progress_detail_text <- renderText(progress_rv$detail)
  
  output$progress_bar_ui <- renderUI({
    pct <- progress_rv$percentage
    color_class <- if (progress_rv$phase == "IA") "bg-info" else "bg-primary"
    if (progress_rv$status == "done") color_class <- "bg-success"
    if (progress_rv$status == "error") color_class <- "bg-danger"
    
    tags$div(
      class = sprintf("progress-bar progress-bar-striped progress-bar-animated %s", color_class),
      style = sprintf("width: %d%%; font-weight: bold; color: white; height: 25px; line-height: 25px; transition: width 0.3s ease;", pct),
      sprintf("%d%%", pct)
    )
  })
  
  output$progress_phase_badge <- renderUI({
    phase <- progress_rv$phase
    badge_style <- "background-color: #004691; color: white; padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 0.85rem;"
    if (phase == "IA") {
      badge_style <- "background-color: #0ea5e9; color: white; padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 0.85rem;"
    } else if (phase == "Concluído") {
      badge_style <- "background-color: #22c55e; color: white; padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 0.85rem;"
    }
    tags$span(style = badge_style, sprintf("Fase Atual: %s", phase))
  })
  
  output$modal_log_text <- renderText(progress_rv$logs)
  
  output$progress_modal_footer <- renderUI({
    if (progress_rv$status %in% c("done", "error")) {
      actionButton("btn_close_progress_modal", "Concluir", class = "btn-success")
    } else {
      tagList(
        actionButton("btn_minimize_progress_modal", "Minimizar (Rodar em 2º Plano)", class = "btn-outline-secondary"),
        modalButton("Fechar")
      )
    }
  })

  show_progress_modal <- function() {
    showModal(modalDialog(
      title = span(style = "font-weight: bold; color: #004691; display: flex; align-items: center; gap: 8px;", 
                   "🔄 Atualização da Base de Dados"),
      easyClose = TRUE,
      size = "l",
      tags$div(
        class = "progress-container",
        style = "margin-bottom: 20px; border-bottom: 1px solid #e2e8f0; padding-bottom: 15px;",
        tags$h5(style = "color: #0f172a; margin-bottom: 12px; font-weight: 500;", textOutput("progress_detail_text")),
        tags$div(
          class = "progress",
          style = "height: 25px; margin-bottom: 12px; background-color: #f1f5f9; border-radius: 6px; overflow: hidden;",
          uiOutput("progress_bar_ui")
        ),
        uiOutput("progress_phase_badge")
      ),
      tags$div(
        style = "margin-top: 15px;",
        tags$h6(style = "color: #475569; font-weight: 600; margin-bottom: 8px;", "Log de Execução em Tempo Real:"),
        tags$pre(
          style = "height: 250px; overflow-y: auto; background-color: #0f172a; color: #38bdf8; border: 1px solid #1e293b; border-radius: 6px; padding: 12px; font-family: 'Courier New', monospace; font-size: 0.85rem; white-space: pre-wrap; margin-bottom: 0;",
          textOutput("modal_log_text")
        ),
      ),
      footer = uiOutput("progress_modal_footer")
    ))
  }

  observeEvent(input$btn_close_progress_modal, {
    removeModal()
    progress_rv$status <- "idle"
  })
  
  observeEvent(input$btn_minimize_progress_modal, {
    removeModal()
    showNotification("Coleta continua em execução em segundo plano.", type = "message")
  })

  # Validação de API Key no startup do Shiny
  observe({
    key_ok <- validate_ai_config()
    if (!key_ok) {
      showNotification(
        "Aviso de IA Desativada: Nenhuma chave de API de IA (Gemini, OpenAI, Anthropic, Groq, OpenRouter, DeepSeek, Bluesminds) foi configurada. O enriquecimento e auditoria de editais com IA estarão desativados. Consulte o README.md para obter instruções de configuração.",
        type = "warning",
        duration = NULL,
        id = "ai_missing_warning"
      )
    }
  })

  # Função para exibir modal de alerta de falha de conexão/bloqueio
  show_failed_sources_modal <- function(failed_sids) {
    if (length(failed_sids) == 0) return()
    
    failed_info <- rv$sources |> dplyr::filter(id_fonte %in% failed_sids)
    if (nrow(failed_info) == 0) return()
    
    showModal(modalDialog(
      title = span(style = "color: #dc2626; font-weight: bold;", "⚠️ Alerta de Bloqueio / Falha na Coleta"),
      easyClose = TRUE,
      size = "m",
      p("A coleta automática das seguintes agências encontrou problemas técnicos (como CAPTCHAs ou bloqueios de IP):"),
      tags$ul(
        lapply(seq_len(nrow(failed_info)), function(i) {
          tags$li(
            style = "margin-bottom: 8px;",
            tags$strong(failed_info$sigla[[i]]), " — ", failed_info$nome_fonte[[i]], " ",
            tags$a(href = failed_info$url_oportunidades[[i]], target = "_blank", class = "btn btn-sm btn-outline-primary", "Busca Manual ↗")
          )
        })
      ),
      p(style = "font-style: italic; color: #64748b; margin-top: 15px;",
        "Orientação: Recomendamos abrir os links acima para verificar e coletar manualmente as oportunidades nesses portais."),
      footer = modalButton("Fechar")
    ))
  }

  check_and_alert_failures <- function(since_time) {
    req(conn)
    query <- "SELECT DISTINCT fonte FROM logs_coleta WHERE status_execucao = 'erro' AND data_execucao >= ?"
    failed_sids <- tryCatch({
      DBI::dbGetQuery(conn, query, params = list(as.character(since_time)))$fonte
    }, error = function(e) character())
    
    if (length(failed_sids) > 0) {
      show_failed_sources_modal(failed_sids)
    }
  }

  observe({
    opps <- filtered_results()
    funder_choices <- sort(unique(opps$entidade))
    updateSelectInput(session, "selected_funder", choices = funder_choices, selected = if (length(funder_choices) > 0) funder_choices[[1]] else "")
  })

  build_filters_json <- function() {
    jsonlite::toJSON(
      list(
        query = rv$current_query,
        advanced = rv$advanced_filters
      ),
      auto_unbox = TRUE,
      null = "null"
    )
  }

  execute_search <- function(query_text, save_history = TRUE) {
    query_text <- stringr::str_squish(query_text %||% "")
    if (nzchar(query_text)) {
      parsed <- tryCatch(parse_boolean_query(query_text), error = function(e) e)
      if (inherits(parsed, "error")) {
        showNotification(parsed$message, type = "error", duration = 8)
        return(invisible(FALSE))
      }
    }
    
    # Se for busca ativa (save_history = TRUE), aciona a coleta dinâmica de fontes correspondentes
    if (isTRUE(save_history) && !is.null(conn)) {
      start_time <- Sys.time()
      region <- input$region_filter
      available_sources <- rv$sources |> dplyr::filter(!(.data$id_fonte %in% c("facepe")))
      if (region == "Brasileiras") {
        available_sources <- available_sources |> dplyr::filter(pais == "Brasil")
      } else if (region == "Europeias") {
        available_sources <- available_sources |> dplyr::filter(pais %in% c("União Europeia", "Alemanha", "Reino Unido", "Suécia", "Bélgica", "França", "Suíça", "Europa", "Itália", "Espanha", "Holanda"))
      } else {
        available_sources <- available_sources |> dplyr::filter(pais == "Brasil" | pais %in% c("União Europeia", "Alemanha", "Reino Unido", "Suécia", "Bélgica", "França", "Suíça", "Europa", "Itália", "Espanha", "Holanda"))
      }
      
      source_ids_to_collect <- available_sources$id_fonte
      
      if (length(source_ids_to_collect) > 0) {
        shiny::withProgress(message = "Pesquisando novas oportunidades na web...", value = 0, {
          progress_cb_shiny <- function(step, total, detail) {
            shiny::setProgress(value = step / total, detail = detail)
          }
          
          tryCatch({
            collect_all_sources(
              conn = conn,
              source_ids = source_ids_to_collect,
              max_pages = 1L,
              max_records_per_source = 3L,
              use_ai = FALSE, # Sem IA na busca dinâmica rápida
              export_dir = export_dir,
              log_path = log_path,
              progress_cb = progress_cb_shiny,
              do_export = FALSE
            )
          }, error = function(e) {
            # Ignora erros de scraping para seguir a busca
          })
        })
        
        # Alerta se houver falhas durante a busca sob demanda
        check_and_alert_failures(start_time)
      }
    }
    
    # Atualiza a base de dados na UI
    refresh_data()
    
    rv$current_query <- query_text
    if (save_history && !is.null(conn)) save_search_record(conn, rv$current_query, build_filters_json())
    invisible(TRUE)
  }

  observeEvent(input$btn_search, {
    execute_search(input$search_query)
  })

  observeEvent(input$btn_advanced, {
    opps <- rv$opportunities
    showModal(modalDialog(
      title = "Busca avançada",
      easyClose = TRUE,
      size = "l",
      bslib::layout_columns(
        col_widths = c(6, 6),
        textInput("adv_required_terms", "Termos obrigatórios", value = rv$advanced_filters$required_terms %||% ""),
        textInput("adv_optional_terms", "Termos opcionais", value = rv$advanced_filters$optional_terms %||% ""),
        textInput("adv_exclude_terms", "Termos a excluir", value = rv$advanced_filters$exclude_terms %||% ""),
        textInput("adv_exact_phrase", "Frase exata", value = rv$advanced_filters$exact_phrase %||% ""),
        selectInput("adv_idioma", "Idioma", choices = c("Todos", sort(unique(opps$idioma))), selected = rv$advanced_filters$idioma %||% "Todos"),
        selectizeInput("adv_country", "País/região", choices = sort(unique(opps$pais_origem)), multiple = TRUE, selected = rv$advanced_filters$pais %||% character(0)),
        selectizeInput("adv_type", "Tipo de oportunidade", choices = sort(unique(opps$tipo_oportunidade)), multiple = TRUE, selected = rv$advanced_filters$tipo %||% character(0)),
        selectizeInput("adv_area", "Área temática", choices = sort(unique(opps$area_tematica)), multiple = TRUE, selected = rv$advanced_filters$area_tematica %||% character(0)),
        selectizeInput("adv_funder", "Financiador", choices = sort(unique(opps$entidade)), multiple = TRUE, selected = rv$advanced_filters$financiador %||% character(0)),
        textInput("adv_eligibility", "Elegibilidade institucional", value = rv$advanced_filters$elegibilidade %||% ""),
        textInput("adv_maturity", "Nível de maturidade da pesquisa", value = rv$advanced_filters$maturidade %||% ""),
        dateRangeInput("adv_deadline", "Prazo de submissão", start = Sys.Date() - 365, end = Sys.Date() + 365)
      ),
      footer = tagList(modalButton("Cancelar"), actionButton("btn_apply_advanced", "Aplicar", class = "btn-primary"))
    ))
  })

  observeEvent(input$btn_apply_advanced, {
    query_built <- build_advanced_query(
      required_terms = input$adv_required_terms,
      optional_terms = input$adv_optional_terms,
      exclude_terms = input$adv_exclude_terms,
      exact_phrase = input$adv_exact_phrase
    )

    rv$advanced_filters <- list(
      required_terms = input$adv_required_terms,
      optional_terms = input$adv_optional_terms,
      exclude_terms = input$adv_exclude_terms,
      exact_phrase = input$adv_exact_phrase,
      idioma = input$adv_idioma,
      pais = input$adv_country,
      tipo = input$adv_type,
      area_tematica = input$adv_area,
      financiador = input$adv_funder,
      elegibilidade = input$adv_eligibility,
      maturidade = input$adv_maturity,
      deadline_range = input$adv_deadline
    )

    updateTextInput(session, "search_query", value = query_built)
    removeModal()
    execute_search(query_built)
  })

  observeEvent(input$btn_save_search, {
    showModal(modalDialog(
      title = "Salvar busca atual",
      textInput("save_search_name", "Nome da busca", value = paste0("Busca ", format(Sys.time(), "%d/%m %H:%M"))),
      checkboxInput("save_search_alert", "Preparar alerta semanal", value = TRUE),
      footer = tagList(modalButton("Cancelar"), actionButton("confirm_save_search", "Salvar", class = "btn-primary"))
    ))
  })

  observeEvent(input$confirm_save_search, {
    req(conn)
    payload <- jsonlite::toJSON(rv$advanced_filters, auto_unbox = TRUE, null = "null")
    save_named_search(conn, input$save_search_name %||% "Busca sem nome", input$search_query %||% "", payload, as.integer(isTRUE(input$save_search_alert)))
    removeModal()
    refresh_data()
    showNotification("Busca salva com sucesso.", type = "message")
  })

  observeEvent(input$btn_collect_official, {
    if (isTRUE(rv$collecting)) {
      show_progress_modal()
      return()
    }
    region <- input$region_filter
    available_sources <- rv$sources |> dplyr::filter(!(.data$id_fonte %in% c("facepe")))
    
    if (region == "Brasileiras") {
      available_sources <- available_sources |> dplyr::filter(pais == "Brasil")
    } else if (region == "Europeias") {
      available_sources <- available_sources |> dplyr::filter(pais %in% c("União Europeia", "Alemanha", "Reino Unido", "Suécia", "Bélgica", "França", "Suíça", "Europa", "Itália", "Espanha", "Holanda"))
    } else {
      available_sources <- available_sources |> dplyr::filter(pais == "Brasil" | pais %in% c("União Europeia", "Alemanha", "Reino Unido", "Suécia", "Bélgica", "França", "Suíça", "Europa", "Itália", "Espanha", "Holanda"))
    }
    
    choices <- stats::setNames(available_sources$id_fonte, paste0(available_sources$sigla, " — ", available_sources$nome_fonte))
    default_sel <- available_sources$id_fonte
    
    showModal(modalDialog(
      title = "Atualizar base a partir das fontes oficiais",
      easyClose = TRUE,
      size = "l",
      p("A coleta parte diretamente das URLs oficiais cadastradas, percorre paginação quando detectada e enriquece os metadados via IA quando a IA estiver configurada."),
      selectizeInput("collect_sources", "Fontes a coletar", choices = choices, selected = default_sel, multiple = TRUE),
      bslib::layout_columns(
        col_widths = c(4, 4, 4),
        numericInput("collect_max_pages", "Máx. páginas por fonte", value = 5, min = 1, max = 50),
        numericInput("collect_max_records", "Máx. registros por fonte", value = 50, min = 1, max = 500),
        checkboxInput("collect_use_ai", "Usar IA para enriquecimento", value = ai_available())
      ),
      checkboxInput("collect_export", "Salvar CSV, RDS e XLSX ao final", value = TRUE),
      footer = tagList(modalButton("Cancelar"), actionButton("confirm_collect_official", "Executar coleta", class = "btn-success"))
    ))
  })

  observeEvent(input$confirm_collect_official, {
    req(conn)
    removeModal()

    if (isTRUE(rv$collecting)) {
      showNotification("A coleta de dados ja esta em andamento em segundo plano.", type = "warning")
      return()
    }

    # Inicializa as variáveis de progresso e exibe o modal
    progress_rv$step <- 0
    progress_rv$total <- length(input$collect_sources)
    progress_rv$percentage <- 0
    progress_rv$detail <- "Iniciando processamento das fontes..."
    progress_rv$phase <- "Scraping"
    progress_rv$logs <- "Inicializando...\n"
    progress_rv$status <- "running"
    
    show_progress_modal()

    # Limpa arquivos de logs anteriores para evitar mostrar lixo
    status_file <- app_file("logs", "collection_status.json")
    log_file <- app_file("logs", "collection_modal_log.txt")
    try({
      if (file.exists(status_file)) file.remove(status_file)
      if (file.exists(log_file)) file.remove(log_file)
    }, silent = TRUE)

    rv$collecting <- TRUE
    rv$bg_start_time <- Sys.time()
    updateActionButton(session, "btn_collect_official", label = "Coletando...")
    showNotification("Coleta iniciada. Acompanhe pelo modal de progresso.", type = "message", id = "bg_collect_notif", duration = 8)

    # Parametros para o processo filho (passados explicitamente como args)
    bg_args <- list(
      app_dir_bg      = app_dir,
      source_ids_bg   = input$collect_sources,
      max_pages_bg    = input$collect_max_pages,
      max_records_bg  = input$collect_max_records,
      use_ai_bg       = isTRUE(input$collect_use_ai),
      export_dir_bg   = export_dir,
      log_path_bg     = log_path,
      do_export_bg    = isTRUE(input$collect_export),
      db_path_bg      = db_path,
      status_file_bg  = normalizePath(status_file, winslash = "/", mustWork = FALSE),
      log_file_bg     = normalizePath(log_file, winslash = "/", mustWork = FALSE),
      ai_env_vars     = list(
        GEMINI_API_KEY    = Sys.getenv("GEMINI_API_KEY"),
        OPENAI_API_KEY    = Sys.getenv("OPENAI_API_KEY"),
        ANTHROPIC_API_KEY = Sys.getenv("ANTHROPIC_API_KEY"),
        GROQ_API_KEY      = Sys.getenv("GROQ_API_KEY"),
        OPENROUTER_API_KEY= Sys.getenv("OPENROUTER_API_KEY"),
        DEEPSEEK_API_KEY  = Sys.getenv("DEEPSEEK_API_KEY"),
        AI_PROVIDER       = Sys.getenv("AI_PROVIDER"),
        AI_MODEL          = Sys.getenv("AI_MODEL"),
        AI_API_KEY        = Sys.getenv("AI_API_KEY"),
        AI_API_URL        = Sys.getenv("AI_API_URL")
      )
    )

    message(sprintf("[callr] Lançando processo background. Parent PID: %d", Sys.getpid()))

    # Executa a coleta em um processo R completamente separado via callr::r_bg()
    rv$bg_process <- callr::r_bg(
      func = function(app_dir_bg, source_ids_bg, max_pages_bg, max_records_bg,
                      use_ai_bg, export_dir_bg, log_path_bg, do_export_bg,
                      db_path_bg, status_file_bg, log_file_bg, ai_env_vars) {
        
        # Configura biblioteca local no processo filho
        local_libs_bg <- file.path(app_dir_bg, "R_libs")
        if (dir.exists(local_libs_bg)) {
          .libPaths(c(local_libs_bg, .libPaths()))
        }

        # Carrega pacotes essenciais
        for (pkg in c("DBI", "RSQLite", "jsonlite", "digest", "dplyr", "purrr",
                      "stringr", "httr2", "rvest", "xml2", "lubridate", "tibble",
                      "readr", "writexl")) {
          library(pkg, character.only = TRUE)
        }

        # Configura variáveis de ambiente de IA
        for (name in names(ai_env_vars)) {
          val <- ai_env_vars[[name]]
          if (nzchar(val)) {
            args <- list(val)
            names(args) <- name
            do.call(Sys.setenv, args)
          }
        }

        # Carrega os helpers do app
        source(file.path(app_dir_bg, "R", "helpers_utils.R"), local = TRUE, encoding = "UTF-8")
        source(file.path(app_dir_bg, "R", "helpers_db.R"),    local = TRUE, encoding = "UTF-8")
        source(file.path(app_dir_bg, "R", "helpers_text.R"),  local = TRUE, encoding = "UTF-8")
        source(file.path(app_dir_bg, "R", "helpers_ai.R"),    local = TRUE, encoding = "UTF-8")
        source(file.path(app_dir_bg, "R", "helpers_collect.R"),local = TRUE, encoding = "UTF-8")

        # Conexão SQLite própria do processo filho
        bg_conn <- DBI::dbConnect(RSQLite::SQLite(), db_path_bg)
        on.exit(DBI::dbDisconnect(bg_conn), add = TRUE)

        collect_all_sources(
          conn               = bg_conn,
          source_ids         = source_ids_bg,
          max_pages          = max_pages_bg,
          max_records_per_source = max_records_bg,
          use_ai             = use_ai_bg,
          export_dir         = export_dir_bg,
          log_path           = log_path_bg,
          do_export          = do_export_bg,
          progress_cb        = NULL,
          status_file        = status_file_bg,
          modal_log_file     = log_file_bg
        )
      },
      args = bg_args,
      supervise = TRUE
    )
  })

  base_results <- reactive({
    df <- rv$opportunities
    if (nrow(df) == 0) return(df)
    query <- rv$current_query
    if (nzchar(query)) {
      df <- tryCatch(apply_boolean_search(df, query, text_cols = c("titulo", "subtitulo", "descricao_resumida", "descricao_completa", "palavras_chave", "area_tematica", "elegibilidade")), error = function(e) df)
    }
    df <- apply_structured_filters(df, rv$advanced_filters)
    compute_adherence_score(df, conn, query)
  })

  filtered_results <- reactive({
    df <- base_results()
    if (nrow(df) == 0) return(df)
    
    # Filtro regional
    region <- input$region_filter
    if (region == "Brasileiras") {
      df <- df |> dplyr::filter(pais_origem == "Brasil")
    } else if (region == "Europeias") {
      df <- df |> dplyr::filter(pais_origem %in% c("União Europeia", "Alemanha", "Reino Unido", "Suécia", "Bélgica", "França", "Suíça", "Europa", "Itália", "Espanha", "Holanda"))
    } else {
      # Ambas (Mantém brasileiras e europeias)
      df <- df |> dplyr::filter(pais_origem == "Brasil" | pais_origem %in% c("União Europeia", "Alemanha", "Reino Unido", "Suécia", "Bélgica", "França", "Suíça", "Europa", "Itália", "Espanha", "Holanda"))
    }
    
    dplyr::arrange(df, dplyr::desc(score_aderencia), parse_date_safe(data_limite))
  })

  output$total_editais <- renderText(nrow(filtered_results()))
  output$total_fontes <- renderText(if (nrow(filtered_results()) == 0) 0 else dplyr::n_distinct(filtered_results()$entidade))
  output$total_urgentes <- renderText(sum(days_to_deadline(filtered_results()$data_limite) <= 14 & days_to_deadline(filtered_results()$data_limite) >= 0, na.rm = TRUE))
  output$ultima_coleta <- renderText({
    if (nrow(rv$logs) == 0) return("-")
    latest <- max(parse_datetime_safe(rv$logs$data_execucao), na.rm = TRUE)
    if (!is.finite(as.numeric(latest))) return("-")
    format(latest, "%d/%m/%Y %H:%M")
  })

  output$collection_status_ui <- renderUI({
    tags$div(class = "mini-kpi", h5("Coleta"), p(rv$last_collect_summary$msg %||% "Base pronta."))
  })
  output$source_counter_ui <- renderUI({
    tags$div(class = "mini-kpi", h5("Fontes"), p(sprintf("%s fontes configuradas", nrow(rv$sources))))
  })
  output$export_status_ui <- renderUI({
    exp <- rv$last_collect_summary$exports
    warn <- rv$last_collect_summary$export_warnings %||% character()
    msg <- if (is.null(exp) || length(exp) == 0) "Ainda sem exportações na sessão" else paste(basename(exp), collapse = " | ")
    tags$div(class = "mini-kpi", h5("Exportação"), p(msg), if (length(warn) > 0) tags$small(style = "color:#a15c00; display:block;", paste(warn, collapse = " | ")))
  })

  output$results_table <- renderDT({
    df <- filtered_results()
    if (nrow(df) == 0) {
      shown <- tibble::tibble(
        ID = character(), Título = character(), Financiador = character(), País = character(),
        Prazo = character(), Tipo = character(), Área = character(), Resumo = character(),
        `Palavras-chave` = character(), Score = character(), Status = character(), Link = character(), Rastrear = character()
      )
    } else {
      shown <- df |>
        dplyr::mutate(
          Prazo = format_date_br(data_limite),
          Status = vapply(status_oportunidade, badge_status_html, character(1)),
          Score = vapply(score_aderencia, score_bar_html, character(1)),
          Link = vapply(dplyr::coalesce(link_detalhe, link_origem), link_html, character(1), label = "Abrir"),
          Rastrear = vapply(id_registro, make_click_button, character(1), label = "Rastrear")
        ) |>
        dplyr::transmute(
          ID = id_registro,
          Título = titulo,
          Financiador = entidade,
          País = pais_origem,
          Prazo,
          Tipo = tipo_oportunidade,
          Área = area_tematica,
          Resumo = stringr::str_trunc(descricao_resumida, 180),
          `Palavras-chave` = palavras_chave,
          Score,
          Status,
          Link,
          Rastrear
        )
    }
    DT::datatable(shown, escape = FALSE, options = list(pageLength = 10, scrollX = TRUE, language = list(emptyTable = "Nenhum resultado encontrado.")))
  }, server = FALSE)

  observeEvent(input$row_action, {
    rv$selected_tracked_id <- input$row_action$id
    if (!is.null(conn)) track_opportunity(conn, input$row_action$id, status_usuario = "avaliar", observacoes = "")
    refresh_data()
    showNotification("Edital adicionado à lista de rastreamento.", type = "message")
  })

  output$funders_plot <- renderPlotly({
    df <- filtered_results() |>
      dplyr::count(entidade, sort = TRUE) |>
      dplyr::slice_head(n = 15)
    p <- ggplot2::ggplot(df, ggplot2::aes(x = reorder(entidade, n), y = n)) +
      ggplot2::geom_col() +
      ggplot2::coord_flip() +
      ggplot2::labs(x = NULL, y = "Editais", title = "Top financiadores")
    plotly::ggplotly(p)
  })

  output$funders_table <- renderDT({
    df <- filtered_results() |>
      dplyr::count(entidade, pais_origem, tipo_oportunidade, sort = TRUE, name = "n_editais")
    DT::datatable(df, options = list(pageLength = 10, scrollX = TRUE))
  }, server = FALSE)

  output$funder_profile <- renderUI({
    req(input$selected_funder)
    info <- rv$sources |> dplyr::filter(sigla == input$selected_funder | nome_fonte == input$selected_funder | id_fonte == input$selected_funder)
    if (nrow(info) == 0) {
      stats <- filtered_results() |> dplyr::filter(entidade == input$selected_funder)
      if (nrow(stats) == 0) return(tags$p("Sem informações adicionais."))
      return(tags$div(h5(input$selected_funder), p(sprintf("%s oportunidade(s) na base filtrada.", nrow(stats)))))
    }
    tags$div(
      h5(info$nome_fonte[[1]]),
      p(sprintf("País: %s", info$pais[[1]])),
      p(sprintf("Categoria: %s", info$categoria[[1]])),
      p(sprintf("Método de coleta: %s", info$metodo_coleta[[1]])),
      HTML(link_html(info$url_oportunidades[[1]], "Página oficial"))
    )
  })

  output$themes_plot <- renderPlotly({
    df <- simple_keyword_frequency(filtered_results(), top_n = 20)
    p <- ggplot2::ggplot(df, ggplot2::aes(x = reorder(term, n), y = n)) +
      ggplot2::geom_col() +
      ggplot2::coord_flip() +
      ggplot2::labs(x = NULL, y = "Frequência", title = "Principais termos")
    plotly::ggplotly(p)
  })

  output$theme_funder_plot <- renderPlotly({
    df <- filtered_results() |>
      dplyr::count(area_tematica, entidade, sort = TRUE) |>
      dplyr::slice_head(n = 20)
    p <- ggplot2::ggplot(df, ggplot2::aes(x = entidade, y = n, text = area_tematica)) +
      ggplot2::geom_col() +
      ggplot2::coord_flip() +
      ggplot2::labs(x = NULL, y = "Registros", title = "Temas por financiador")
    plotly::ggplotly(p, tooltip = c("x", "y", "text"))
  })

  output$keywords_table <- renderDT({
    DT::datatable(simple_keyword_frequency(filtered_results(), top_n = 50), options = list(pageLength = 10))
  })

  output$saved_searches_table <- renderDT({
    df <- rv$saved_searches
    if (nrow(df) == 0) {
      shown <- tibble::tibble(id = integer(), nome_busca = character(), query_text = character(), alerta_ativo = integer(), created_at = character(), last_run_at = character())
    } else {
      shown <- df |>
        dplyr::select(id, nome_busca, query_text, alerta_ativo, created_at, last_run_at)
    }
    DT::datatable(shown, escape = FALSE, options = list(pageLength = 10, scrollX = TRUE, language = list(emptyTable = "Nenhuma busca salva.")), selection = "single")
  }, server = FALSE)

  observeEvent(input$saved_searches_table_rows_selected, {
    idx <- input$saved_searches_table_rows_selected
    if (length(idx) == 1) {
      row <- rv$saved_searches[idx, , drop = FALSE]
      updateTextInput(session, "search_query", value = row$query_text[[1]])
      execute_search(row$query_text[[1]], save_history = FALSE)
      if (!is.null(conn)) mark_saved_search_run(conn, row$id[[1]])
      refresh_data()
    }
  })

  output$tracked_table <- renderDT({
    if (nrow(rv$tracked) == 0) {
      df <- tibble::tibble(id = character(), Título = character(), Financiador = character(), Prazo = character(), Status = character(), Observações = character())
    } else {
      df <- rv$tracked |>
        dplyr::left_join(rv$opportunities, by = c("id_oportunidade" = "id_registro")) |>
        dplyr::transmute(id = id_oportunidade, Título = titulo, Financiador = entidade, Prazo = format_date_br(data_limite), Status = status_usuario, Observações = observacoes.x)
    }
    DT::datatable(df, options = list(pageLength = 8, scrollX = TRUE, language = list(emptyTable = "Nenhum edital rastreado.")), selection = "single")
  }, server = FALSE)

  observeEvent(input$tracked_table_rows_selected, {
    idx <- input$tracked_table_rows_selected
    if (length(idx) == 1 && nrow(rv$tracked) >= idx) {
      rv$selected_tracked_id <- rv$tracked$id_oportunidade[[idx]]
      updateSelectInput(session, "tracked_status_input", selected = rv$tracked$status_usuario[[idx]])
      updateTextAreaInput(session, "tracked_notes_input", value = rv$tracked$observacoes[[idx]] %||% "")
    } else {
      rv$selected_tracked_id <- NULL
    }
  })

  output$tracked_partners_ui <- renderUI({
    opp_id <- rv$selected_tracked_id
    if (is.null(opp_id) || !nzchar(opp_id)) {
      return(tags$p(style = "color: #64748b; font-style: italic;", 
                    "Selecione um edital na tabela ao lado para visualizar os parceiros internos recomendados."))
    }
    
    partners <- recommend_partners_for_opportunity(conn, opp_id, top_n = 5)
    
    if (nrow(partners) == 0) {
      return(tags$p(style = "color: #64748b; font-style: italic;", 
                    "Nenhum pesquisador compatível encontrado para este edital."))
    }
    
    # Renderizar lista de parceiros
    partner_items <- lapply(seq_len(nrow(partners)), function(i) {
      p <- partners[i, ]
      
      # Barra de progresso visual para afinidade
      affinity_bar <- tags$div(
        class = "score-wrap",
        style = "margin-top: 5px; margin-bottom: 8px;",
        tags$div(
          class = "score-bar",
          tags$div(
            class = "score-bar-fill",
            style = sprintf("width: %d%%;", p$score_afinidade)
          )
        ),
        tags$div(
          class = "score-label",
          sprintf("Afinidade: %d%%", p$score_afinidade)
        )
      )
      
      tags$div(
        style = "border-bottom: 1px solid #f1f5f9; padding-bottom: 10px; margin-bottom: 10px;",
        tags$h6(style = "margin-bottom: 2px; color: #004691; font-weight: 600;", p$nome),
        tags$p(style = "font-size: 0.8rem; color: #64748b; margin-bottom: 4px;", 
               tags$strong("Email: "), tags$a(href = paste0("mailto:", p$email), p$email), " | ", tags$strong("Inst: "), p$instituicao),
        affinity_bar,
        if (nzchar(p$termos_correspondentes)) {
          tags$p(style = "font-size: 0.75rem; margin-bottom: 4px; color: #0f172a;",
                 tags$strong("Termos correspondentes: "), 
                 tags$span(style = "background-color: #eff6ff; color: #1e40af; padding: 2px 6px; border-radius: 4px; font-family: monospace; font-size: 0.7rem;", p$termos_correspondentes))
        },
        if (nzchar(p$projetos_passados)) {
          tags$p(style = "font-size: 0.75rem; color: #475569; margin-bottom: 0;",
                 tags$strong("Projetos passados: "), p$projetos_passados)
        }
      )
    })
    
    tags$div(partner_items)
  })

  observeEvent(input$btn_update_tracked, {
    req(conn, rv$selected_tracked_id)
    update_tracked_opportunity(conn, rv$selected_tracked_id, input$tracked_status_input, input$tracked_notes_input %||% "")
    refresh_data()
    showNotification("Rastreamento atualizado.", type = "message")
  })

  observeEvent(input$btn_remove_tracked, {
    req(conn, rv$selected_tracked_id)
    delete_tracked_opportunity(conn, rv$selected_tracked_id)
    rv$selected_tracked_id <- NULL
    refresh_data()
    showNotification("Item removido da lista de rastreamento.", type = "message")
  })

  output$recommended_table <- renderDT({
    df <- recommend_opportunities(conn, filtered_results(), rv$current_query, top_n = 15)
    if (nrow(df) == 0) {
      shown <- tibble::tibble(Título = character(), Financiador = character(), Score = numeric(), Prazo = character(), Tipo = character(), Link = character())
    } else {
      shown <- df |>
        dplyr::mutate(Link = vapply(dplyr::coalesce(link_detalhe, link_origem), link_html, character(1), label = "Abrir")) |>
        dplyr::transmute(Título = titulo, Financiador = entidade, Score = score_aderencia, Prazo = format_date_br(data_limite), Tipo = tipo_oportunidade, Link)
    }
    DT::datatable(shown, escape = FALSE, options = list(pageLength = 10, scrollX = TRUE, language = list(emptyTable = "Nenhuma recomendação disponível.")))
  }, server = FALSE)

  output$profile_summary <- renderUI({
    tags$div(
      h5("Usuário"),
      p(tags$strong("Instituição: "), "SENAI CIMATEC"),
      p(tags$strong("Palavras-chave: "), "quântica; tecnologia quântica; comunicação quântica; sensores quânticos; computação quântica"),
      p(tags$strong("Áreas: "), "Tecnologias Quânticas; Comunicação Quântica; Sensores Quânticos; Computação Quântica")
    )
  })

  output$collaborators_table <- renderDT({
    df <- find_potential_collaborators(conn, rv$current_query, top_n = 15)
    if (nrow(df) == 0) {
      shown <- tibble::tibble(
        Nome = character(),
        Instituição = character(),
        País = character(),
        Área = character(),
        `Palavras-chave` = character(),
        Similarity = character(),
        Email = character()
      )
    } else {
      if ("similarity" %in% names(df)) df$similarity <- sprintf("%.2f", round(as.numeric(df$similarity), 2))
      shown <- df |>
        dplyr::transmute(
          Nome = nome,
          Instituição = instituicao,
          País = pais,
          Área = area,
          `Palavras-chave` = palavras_chave,
          Similarity = similarity,
          Email = email
        )
    }
    DT::datatable(shown, options = list(pageLength = 10, scrollX = TRUE, language = list(emptyTable = "Nenhum colaborador potencial encontrado.")))
  }, server = FALSE)

  output$logs_table <- renderDT({
    DT::datatable(rv$logs |> dplyr::arrange(dplyr::desc(parse_datetime_safe(data_execucao))), options = list(pageLength = 15, scrollX = TRUE))
  }, server = FALSE)
}

shiny::shinyApp(ui, server)
