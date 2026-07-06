# Configura biblioteca local para contornar problemas de permissões de escrita globais
local_libs <- file.path(getwd(), "R_libs")
if (!dir.exists(local_libs)) dir.create(local_libs, showWarnings = FALSE)
.libPaths(c(local_libs, .libPaths()))

required_packages <- c(
  "shiny", "bslib", "DT", "dplyr", "tidyr", "purrr", "stringr", "stringi", "lubridate",
  "ggplot2", "plotly", "DBI", "RSQLite", "jsonlite", "digest", "htmltools",
  "rvest", "xml2", "httr", "httr2", "tibble", "tools", "readr", "writexl", "janitor",
  "glue", "progress", "pdftools", "polite", "callr", "shinycssloaders", "googledrive"
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

is_posit_connect <- nzchar(Sys.getenv("CONNECT_SERVER")) || nzchar(Sys.getenv("CONNECT_API_KEY"))
if (!is_posit_connect) {
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0) {
    install_missing_packages(missing_packages)
  }
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

library(janitor)
library(polite)
invisible(lapply(required_packages, library, character.only = TRUE))
# callr::r_bg() é usado para execução em background (sem future)
.GlobalEnv$.global_scraping_active <- FALSE

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
  out <- try(source(full_path, local = parent.frame(), encoding = "UTF-8"), silent = TRUE)
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
safe_source("R/helpers_drive.R")

# Registra a pasta logos como recurso estático do Shiny
shiny::addResourcePath("logos", app_file("logos"))

db_path <- app_file("funding_intelligence.sqlite")
export_dir <- app_file("data_exports")
log_path <- app_file("logs", "funding_collection.log")
ensure_dir(export_dir)
ensure_dir(dirname(log_path))

# Baixa a base de dados atualizada do Google Drive, se configurado
try(drive_download_db(db_path), silent = TRUE)

try(init_database(db_path), silent = TRUE)
conn <- tryCatch(get_db_connection(db_path), error = function(e) NULL)
onStop(function() {
  if (!is.null(conn) && DBI::dbIsValid(conn)) DBI::dbDisconnect(conn)
  # Sincroniza a base local com o Google Drive ao fechar a aplicação
  try(drive_upload_db(db_path), silent = TRUE)
})

# Rodar testes automaticamente no startup (se configurado)
if (identical(Sys.getenv("RUN_STARTUP_TESTS"), "true") && requireNamespace("testthat", quietly = TRUE)) {
  tryCatch({
    test_dir <- file.path(getwd(), "tests", "testthat")
    if (dir.exists(test_dir)) {
      test_results <- testthat::test_dir(test_dir, reporter = "summary")
      n_failed <- sum(vapply(test_results, function(r) r$failed, integer(1)) > 0)
      if (n_failed > 0) {
        warning(sprintf("Startup tests: %d teste(s) falhou(s)", n_failed))
      } else {
        message("Startup tests: todos os testes passaram")
      }
    }
  }, error = function(e) {
    message(sprintf("Startup tests: erro ao executar testes - %s", e$message))
  })
}

build_sidebar <- function() {
  bslib::sidebar(
    title = tags$div(
      style = "display: flex; align-items: center; gap: 8px; font-weight: 700; color: #004691;",
      tags$i(class = "fa fa-filter"), "Filtros Rápidos"
    ),
    open = "desktop",
    width = 320,
    selectizeInput(
      "filter_funder", 
      label = tags$span(tags$i(class = "fa fa-university"), " Financiador"),
      choices = NULL, 
      multiple = TRUE, 
      options = list(placeholder = "Todos os financiadores")
    ),
    selectizeInput(
      "filter_area", 
      label = tags$span(tags$i(class = "fa fa-laptop-code"), " Área Temática"),
      choices = NULL, 
      multiple = TRUE, 
      options = list(placeholder = "Todas as áreas")
    ),
    selectizeInput(
      "filter_status", 
      label = tags$span(tags$i(class = "fa fa-info-circle"), " Status"),
      choices = NULL, 
      multiple = TRUE, 
      options = list(placeholder = "Todos os status")
    ),
    selectizeInput(
      "filter_type", 
      label = tags$span(tags$i(class = "fa fa-tags"), " Tipo de Oportunidade"),
      choices = NULL, 
      multiple = TRUE, 
      options = list(placeholder = "Todos os tipos")
    ),
    selectizeInput(
      "filter_language", 
      label = tags$span(tags$i(class = "fa fa-language"), " Idioma"),
      choices = NULL, 
      multiple = TRUE, 
      options = list(placeholder = "Todos os idiomas")
    ),
    tags$hr(style = "margin: 1rem 0; border-color: #cbd5e1;"),
    actionButton(
      "btn_clear_filters", 
      "Limpar Filtros", 
      class = "btn-outline-secondary w-100", 
      icon = icon("redo")
    )
  )
}

ui <- bslib::page_sidebar(
  fillable = FALSE,
  title = tags$div(
    class = "app-header",
    tags$div(
      style = "display: flex; align-items: center; gap: 1.5rem;",
      tags$div(
        class = "logo-container",
        tags$img(src = "senai_cimatec.jpg", height = "36px", alt = "SENAI CIMATEC")
      ),
      tags$div(
        class = "app-title-main",
        h2("QuIIN - QFunding Intelligence Hub"),
        p("Busca booleana, monitoramento de editais e recomendação a partir do banco local.")
      )
    ),
    uiOutput("header_status")
  ),
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly", primary = "#004691", secondary = "#0f172a"),
  sidebar = build_sidebar(),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = paste0("styles.css?v=", as.integer(Sys.time()))),
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
      textInput(
        "search_query", 
        label = tags$span(
          "Barra de busca principal ",
          tags$span(
            style = "cursor: pointer; color: #004691; margin-left: 4px;",
            onclick = "Shiny.setInputValue('click_search_help', Math.random(), {priority: 'event'})",
            tags$i(class = "fa fa-question-circle")
          )
        ),
        value = "", 
        placeholder = "Ex.: (health OR medical devices) AND innovation NOT veterinary"
      ),
      radioButtons("region_filter", "Região das fontes", choices = c("Brasileiras", "Europeias", "Ambas"), selected = "Ambas", inline = TRUE),
      actionButton("btn_search", "Buscar", class = "btn-primary action-top", icon = icon("search")),
      actionButton("btn_advanced", "Busca avançada", class = "btn-outline-primary action-top", icon = icon("sliders-h")),
      actionButton("btn_save_search", "Salvar busca", class = "btn-outline-secondary action-top", icon = icon("bookmark")),
      actionButton("btn_collect_official", "Atualizar base", class = "btn-success action-top", icon = icon("sync"))
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
  ),
  
  tags$footer(
    class = "app-footer-centered",
    style = "background-color: #E9E9E9; color: #64748b; border-top: 4px solid #004691; box-shadow: 0 -4px 20px rgba(0, 0, 0, 0.05); padding: 2.5rem 2rem 2rem 2rem; margin-top: 3rem; text-align: center; border-radius: 12px 12px 0 0;",
    tags$div(
      style = "text-align: center; margin-bottom: 15px;",
      tags$img(src = "logos/logos.png", style = "max-height: 90px; width: auto; display: block; margin: 0 auto 10px auto;", alt = "Logo QuIIN")
    ),
    tags$div(
      class = "footer-top-centered",
      tags$p(
        style = "color: #334155; font-size: 0.95rem; margin: 0; display: flex; align-items: center; justify-content: center; gap: 0.5rem;",
        tags$i(class = "fa fa-map-marker-alt", style = "color: #004691;"), " SENAI CIMATEC – Salvador, Bahia"
      )
    ),
    tags$hr(class = "footer-divider", style = "border-top: 1px solid #e2e8f0; margin: 1.25rem auto; max-width: 1200px; opacity: 0.8;"),
    tags$div(
      class = "footer-bottom-centered",
      tags$p(
        style = "color: #64748b; font-size: 0.8rem; margin: 0.4rem 0; display: flex; align-items: center; justify-content: center; gap: 0.5rem;",
        tags$i(class = "fa-solid fa-atom", style = "color: #004691;"), " QuIIN • Associação tecnológica"
      ),
      tags$p(
        style = "color: #64748b; font-size: 0.8rem; margin: 0.4rem 0; display: flex; align-items: center; justify-content: center; gap: 0.5rem;",
        "Curador responsável: David Franco Regalado, Ítalo Ferreira da Silva e João Carlos Pereira Passos."
      ),
      tags$p(
        style = "color: #64748b; font-size: 0.8rem; margin: 0.4rem 0; display: flex; align-items: center; justify-content: center; gap: 0.5rem;",
        "Responsável técnico: Mabel Diz Marques Mota"
      ),
      tags$p(
        style = "color: #475569; font-size: 0.85rem; margin: 0.4rem 0; display: flex; align-items: center; justify-content: center; gap: 0.5rem;",
        sprintf("© %s Núcleo de Economia Industrial – SENAI CIMATEC. Transformando conhecimento econômico em vantagem competitiva.", format(Sys.Date(), "%Y"))
      )
    )
  )
)

server <- function(input, output, session) {
  # Referência local de sessão para rastreamento de processos Callr
  bg_proc_ref <- NULL

  # Cleanup automático ao fechar a sessão do navegador
  session$onSessionEnded(function() {
    if (!is.null(bg_proc_ref) && bg_proc_ref$is_alive()) {
      message(sprintf("[callr] Sessão encerrada. Matando processo background ativo (PID: %d)", bg_proc_ref$get_pid()))
      try(bg_proc_ref$kill(), silent = TRUE)
    }
    # Libera o semáforo global se fomos nós que iniciamos a coleta
    if (isTRUE(isolate(rv$collecting))) {
      .GlobalEnv$.global_scraping_active <- FALSE
    }
  })

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
    collecting = FALSE,
    drive_status = "idle"
  )

  # Wrapper para upload seguro no Google Drive com atualização de status visual
  safe_drive_upload <- function() {
    rv$drive_status <- "uploading"
    shiny::withProgress(message = "Sincronizando com Google Drive...", {
      tryCatch({
        drive_upload_db(db_path)
        rv$drive_status <- "idle"
      }, error = function(e) {
        rv$drive_status <- "error"
        showNotification(paste("Erro ao sincronizar com Google Drive:", e$message), type = "error")
        rv$drive_status <- "idle"
      })
    })
  }

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
      .GlobalEnv$.global_scraping_active <- FALSE
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
        progress_rv$detail <- "Coleta concluída! Sincronizando com o Google Drive..."
        
        # Sincroniza a base coletada com o Google Drive, se configurado
        safe_drive_upload()
        
        progress_rv$detail <- "Sincronização com Google Drive concluída!"
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
        "Aviso de IA Desativada: Nenhuma chave de API de IA (Gemini, OpenAI, Nvidia, Anthropic, Groq, OpenRouter, DeepSeek, Bluesminds) foi configurada. O enriquecimento e auditoria de editais com IA estarão desativados. Consulte o README.md para obter instruções de configuração.",
        type = "warning",
        duration = NULL,
        id = "ai_missing_warning"
      )
    } else {
      ai_health <- tryCatch(ai_healthcheck(), error = function(e) list(ok = FALSE, error = e$message))
      if (!isTRUE(ai_health$ok)) {
        showNotification(
          paste("Aviso: IA indisponível —", ai_health$error, ". Enriquecimento desativado."),
          type = "warning", duration = NULL, id = "ai_health_warning"
        )
      } else {
        message(sprintf("IA saudável: %s (%s)", ai_health$provider, ai_health$model))
      }
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
    
    # Atualiza a base de dados na UI para sincronismo
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
    safe_drive_upload()
  })

  observeEvent(input$btn_collect_official, {
    if (isTRUE(rv$collecting)) {
      show_progress_modal()
      return()
    }
    region <- input$region_filter
    available_sources <- rv$sources
    
    if (region == "Brasileiras") {
      available_sources <- available_sources |> dplyr::filter(pais == "Brasil")
    } else if (region == "Europeias") {
      available_sources <- available_sources |> dplyr::filter(pais %in% c("União Europeia"))
    } else {
      available_sources <- available_sources
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
        numericInput("collect_max_records", "Máx. registros por fonte", value = 15, min = 1, max = 500),
        checkboxInput("collect_use_ai", "Usar IA para enriquecimento", value = ai_available())
      ),
      checkboxInput("collect_export", "Salvar CSV, RDS e XLSX ao final", value = TRUE),
      footer = tagList(modalButton("Cancelar"), actionButton("confirm_collect_official", "Executar coleta", class = "btn-success"))
    ))
  })

  observeEvent(input$confirm_collect_official, {
    req(conn)
    removeModal()

    if (isTRUE(rv$collecting) || isTRUE(.GlobalEnv$.global_scraping_active)) {
      showNotification("A coleta de dados já está em andamento em segundo plano por outro processo.", type = "warning")
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
    .GlobalEnv$.global_scraping_active <- TRUE
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
        BLUESMINDS_API_KEY= Sys.getenv("BLUESMINDS_API_KEY"),
        GEMINI_API_KEY    = Sys.getenv("GEMINI_API_KEY"),
        OPENAI_API_KEY    = Sys.getenv("OPENAI_API_KEY"),
        NVIDIA_API_KEY    = Sys.getenv("NVIDIA_API_KEY"),
        ANTHROPIC_API_KEY = Sys.getenv("ANTHROPIC_API_KEY"),
        GROQ_API_KEY      = Sys.getenv("GROQ_API_KEY"),
        OPENROUTER_API_KEY= Sys.getenv("OPENROUTER_API_KEY"),
        DEEPSEEK_API_KEY  = Sys.getenv("DEEPSEEK_API_KEY"),
        AI_PROVIDER       = Sys.getenv("AI_PROVIDER"),
        AI_MODEL          = Sys.getenv("AI_MODEL"),
        AI_API_KEY        = Sys.getenv("AI_API_KEY"),
        AI_API_URL        = Sys.getenv("AI_API_URL"),
        EU_API_PROXY_URL  = Sys.getenv("EU_API_PROXY_URL")
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
      stdout = file.path(app_dir, "logs", "collection_stdout.log"),
      stderr = file.path(app_dir, "logs", "collection_stderr.log"),
      supervise = TRUE
    )
    bg_proc_ref <<- rv$bg_process
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
      df <- df |> dplyr::filter(pais_origem %in% c("União Europeia"))
    } else {
      # Ambas (Mantém brasileiras e europeias)
      df <- df |> dplyr::filter(pais_origem == "Brasil" | pais_origem %in% c("União Europeia"))
    }

    # Filtros Rápidos do Sidebar
    if (length(input$filter_funder) > 0) {
      df <- df |> dplyr::filter(entidade %in% input$filter_funder)
    }
    if (length(input$filter_area) > 0) {
      df <- df |> dplyr::filter(area_tematica %in% input$filter_area)
    }
    if (length(input$filter_status) > 0) {
      df <- df |> dplyr::filter(status_oportunidade %in% input$filter_status)
    }
    if (length(input$filter_type) > 0) {
      df <- df |> dplyr::filter(tipo_oportunidade %in% input$filter_type)
    }
    if (length(input$filter_language) > 0) {
      df <- df |> dplyr::filter(idioma %in% input$filter_language)
    }
    
    dplyr::arrange(df, dplyr::desc(score_aderencia), parse_date_safe(data_limite))
  })

  # Atualizador dinâmico de escolhas dos filtros no sidebar
  observe({
    opps <- rv$opportunities
    req(nrow(opps) > 0)
    
    # Financiador
    funder_choices <- sort(unique(opps$entidade))
    updateSelectizeInput(session, "filter_funder", choices = funder_choices, selected = input$filter_funder)
    
    # Área Temática
    area_choices <- sort(unique(opps$area_tematica[!is.na(opps$area_tematica) & opps$area_tematica != ""]))
    updateSelectizeInput(session, "filter_area", choices = area_choices, selected = input$filter_area)
    
    # Status
    status_choices <- sort(unique(opps$status_oportunidade[!is.na(opps$status_oportunidade) & opps$status_oportunidade != ""]))
    status_display <- setNames(status_choices, tools::toTitleCase(status_choices))
    updateSelectizeInput(session, "filter_status", choices = status_display, selected = input$filter_status)
    
    # Tipo de Oportunidade
    type_choices <- sort(unique(opps$tipo_oportunidade[!is.na(opps$tipo_oportunidade) & opps$tipo_oportunidade != ""]))
    updateSelectizeInput(session, "filter_type", choices = type_choices, selected = input$filter_type)
    
    # Idioma
    lang_choices <- sort(unique(opps$idioma[!is.na(opps$idioma) & opps$idioma != ""]))
    lang_display <- setNames(lang_choices, toupper(lang_choices))
    updateSelectizeInput(session, "filter_language", choices = lang_display, selected = input$filter_language)
  })

  # Evento para limpar todos os filtros rápidos do sidebar
  observeEvent(input$btn_clear_filters, {
    updateSelectizeInput(session, "filter_funder", selected = character(0))
    updateSelectizeInput(session, "filter_area", selected = character(0))
    updateSelectizeInput(session, "filter_status", selected = character(0))
    updateSelectizeInput(session, "filter_type", selected = character(0))
    updateSelectizeInput(session, "filter_language", selected = character(0))
  })

  # Renderizador de status persistente no header da aplicação
  output$header_status <- renderUI({
    status_info <- if (isTRUE(rv$drive_status == "uploading")) {
      list(icon = "sync fa-spin status-syncing", label = "Sincronizando GDrive...", class = "status-syncing")
    } else if (isTRUE(progress_rv$status == "running")) {
      list(icon = "robot fa-spin status-active", label = "Coleta Ativa (Background)", class = "status-active")
    } else {
      list(icon = "check-circle status-success", label = "Base Sincronizada", class = "status-success")
    }
    
    tags$button(
      id = "btn_header_status",
      class = sprintf("btn header-status-widget %s", status_info$class),
      onclick = "Shiny.setInputValue('click_header_status', Math.random(), {priority: 'event'})",
      tags$i(class = sprintf("fa fa-%s", status_info$icon)),
      tags$span(class = "status-label", style = "margin-left: 6px;", status_info$label)
    )
  })

  # Clique no status do header abre o modal se houver coleta rodando
  observeEvent(input$click_header_status, {
    if (progress_rv$status == "running" || progress_rv$status == "done" || progress_rv$status == "error") {
      show_progress_modal()
    } else {
      showNotification("A base local está atualizada e sincronizada com o Google Drive.", type = "message")
    }
  })

  # Exibe modal informativo de sintaxe de busca
  observeEvent(input$click_search_help, {
    showModal(modalDialog(
      title = span(style = "font-weight: bold; color: #004691; display: flex; align-items: center; gap: 6px;", 
                   tags$i(class = "fa fa-lightbulb text-warning"), "Guia de Busca Booleana"),
      easyClose = TRUE,
      p("A barra de busca suporta termos e expressões complexas utilizando operadores booleanos:"),
      tags$ul(
        tags$li(tags$strong("AND:"), " Ambos os termos devem estar presentes. Ex: ", tags$code("saúde AND tecnologia")),
        tags$li(tags$strong("OR:"), " Pelo menos um dos termos deve estar presente. Ex: ", tags$code("computação OR eletrônica")),
        tags$li(tags$strong("NOT:"), " Exclui termos indesejados. Ex: ", tags$code("inovação NOT veterinária")),
        tags$li(tags$strong("Aspas (\" \"):"), " Busca exata. Ex: ", tags$code("\"inteligência artificial\"")),
        tags$li(tags$strong("Parênteses (( )):"), " Organiza a prioridade. Ex: ", tags$code("(sensores OR robótica) AND saúde"))
      ),
      p(style = "color: #64748b; font-size: 0.85rem; margin-top: 10px;", "Aviso: Operadores lógicos (AND, OR, NOT) devem ser escritos em maiúsculo."),
      footer = modalButton("Entendi")
    ))
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
        ID = character(),
        Título = character(),
        Financiador = factor(),
        `Aderência <i class='fa fa-info-circle text-info' title='Afinidade semântica calculada dinamicamente com base nos termos de busca.'></i>` = character(),
        Prazo = character(),
        Status = factor(),
        Ações = character()
      )
    } else {
      shown <- df |>
        dplyr::mutate(
          Aderência = vapply(score_aderencia, score_bar_html, character(1)),
          Prazo = format_date_br(data_limite),
          Status = as.factor(tools::toTitleCase(tolower(status_oportunidade))),
          Financiador = as.factor(entidade),
          Título = stringr::str_trunc(titulo, 90),
          Ações = vapply(id_registro, make_actions_html, character(1))
        ) |>
        dplyr::transmute(
          ID = id_registro,
          Título,
          Financiador,
          `Aderência <i class='fa fa-info-circle text-info' title='Afinidade semântica calculada dinamicamente com base nos termos de busca.'></i>` = Aderência,
          Prazo,
          Status,
          Ações
        )
    }
    DT::datatable(
      shown, 
      escape = FALSE, 
      rownames = FALSE,
      filter = "none", 
      options = list(
        pageLength = 10, 
        scrollX = TRUE, 
        searching = FALSE,
        language = list(emptyTable = "Nenhum resultado encontrado."),
        columnDefs = list(
          list(targets = 0, visible = FALSE),
          list(
            targets = 5,
            render = DT::JS("
              function(data, type, row, meta) {
                if (type === 'display') {
                  var status = (data || 'Indefinido').toLowerCase();
                  var cls = 'badge-soft-neutral';
                  if (status === 'aberto') cls = 'badge-soft-open';
                  else if (status === 'encerrando') cls = 'badge-soft-warning';
                  else if (status === 'em breve') cls = 'badge-soft-info';
                  else if (status === 'encerrado') cls = 'badge-soft-closed';
                  return \"<span class='status-badge \" + cls + \"'>\" + data + \"</span>\";
                }
                return data;
              }
            ")
          ),
          list(targets = c(0, 6), searchable = FALSE, orderable = FALSE)
        )
      )
    )
  }, server = FALSE)

  observeEvent(input$row_action, {
    rv$selected_tracked_id <- input$row_action$id
    if (!is.null(conn)) track_opportunity(conn, input$row_action$id, status_usuario = "avaliar", observacoes = "")
    refresh_data()
    showNotification("Edital adicionado à lista de rastreamento.", type = "message")
    safe_drive_upload()
  })

  observeEvent(input$row_view, {
    req(input$row_view$id)
    opp <- rv$opportunities |> dplyr::filter(id_registro == input$row_view$id)
    if (nrow(opp) == 0) return()
    
    # Calcular aderência dinâmica com base no termo buscado
    dynamic_score <- calculate_dynamic_adherence(
      query = rv$current_query,
      keywords = opp$palavras_chave[[1]],
      summary = opp$descricao_resumida[[1]],
      title = opp$titulo[[1]],
      subtitle = opp$subtitulo[[1]],
      default_score = opp$score_aderencia[[1]] %||% 0
    )
    
    # Exibir Modal Dialog com detalhes estruturados
    showModal(modalDialog(
      title = tags$div(
        style = "display: flex; justify-content: space-between; align-items: center; width: 100%;",
        tags$h3(style = "margin: 0; color: #004691; font-weight: 800; font-size: 1.4rem; white-space: normal; line-height: 1.3; text-align: left;", opp$titulo[[1]]),
        tags$button(
          type = "button",
          class = "btn-close",
          `data-bs-dismiss` = "modal",
          `aria-label` = "Close",
          style = "margin-left: 15px;"
        )
      ),
      size = "l",
      easyClose = TRUE,
      footer = modalButton("Fechar"),
      
      # Modal Body
      tags$div(
        style = "padding: 15px 0; font-family: 'Inter', sans-serif;",
        
        # Financiador e Subtítulo
        tags$div(
          style = "margin-bottom: 25px; border-left: 4px solid #e30613; padding-left: 15px;",
          tags$span(style = "font-size: 0.85rem; text-transform: uppercase; font-weight: 700; color: #e30613; letter-spacing: 0.5px;", "Entidade Financiadora"),
          tags$h4(style = "margin: 2px 0 0 0; color: #0f172a; font-weight: 700; font-size: 1.2rem;", opp$entidade[[1]]),
          if (!is.na(opp$subtitulo[[1]]) && nzchar(opp$subtitulo[[1]])) {
            tags$div(style = "font-style: italic; margin-top: 5px; font-size: 0.95rem; color: #475569;", opp$subtitulo[[1]])
          }
        ),

        # 2-Column Responsive Layout
        tags$div(
          class = "row",
          # Coluna Esquerda (7 colunas)
          tags$div(
            class = "col-md-7", style = "margin-bottom: 20px;",
            # Score de Aderência e Palavras-chave
            tags$div(
              style = "margin-bottom: 25px; background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; padding: 15px;",
              tags$h5(style = "color: #1e40af; font-weight: 700; margin-bottom: 12px; font-size: 1rem; text-transform: uppercase; letter-spacing: 0.5px;", "Análise de Afinidade (IA)"),
              tags$div(
                style = "margin-bottom: 10px;",
                tags$strong("Aderência Geral:"),
                HTML(score_bar_html(dynamic_score))
              ),
              tags$div(
                style = "margin-bottom: 10px;",
                tags$strong("Palavras-chave Identificadas:"),
                tags$div(
                  style = "margin-top: 8px; display: flex; flex-wrap: wrap; gap: 6px;",
                  HTML(paste0(
                    vapply(safe_split(opp$palavras_chave[[1]]), function(kw) {
                      sprintf("<span class='status-badge badge-soft-info' style='text-transform: none; font-size: 0.7rem;'>%s</span>", htmltools::htmlEscape(kw))
                    }, character(1)),
                    collapse = ""
                  ))
                )
              )
            ),
            # Objeto de Financiamento (Resumo da IA)
            tags$div(
              style = "margin-bottom: 25px; background: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.02);",
              tags$h5(style = "color: #004691; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; font-weight: 700; font-size: 1.1rem; text-transform: uppercase; letter-spacing: 0.5px;", "Objeto de Financiamento"),
              tags$div(
                style = "font-size: 0.95rem; line-height: 1.7; color: #1e293b; white-space: pre-wrap; text-align: justify;",
                {
                  resumo <- opp$descricao_resumida[[1]]
                  if (is.null(resumo) || is.na(resumo) || !nzchar(trimws(resumo)) || identical(resumo, "Resumo não disponível.")) {
                    "Resumo não disponível. Acesse o portal de origem para mais detalhes."
                  } else {
                    resumo
                  }
                }
              )
            ),
            # Links de Referência
            tags$div(
              style = "margin-bottom: 25px;",
              tags$h5(style = "color: #004691; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; font-weight: 700; font-size: 1.1rem; text-transform: uppercase; letter-spacing: 0.5px;", "Documentos e Links Oficiais"),
              tags$div(
                style = "margin-top: 10px; display: flex; flex-direction: column; gap: 8px; font-size: 0.95rem;",
                if (!is.na(opp$link_origem[[1]]) && nzchar(opp$link_origem[[1]])) {
                  tags$div(tags$strong("Portal da Oportunidade: "), tags$a(href = opp$link_origem[[1]], target = "_blank", style = "color: #004691; font-weight: 600;", "Acessar Portal de Origem ↗"))
                },
                if (!is.na(opp$link_detalhe[[1]]) && nzchar(opp$link_detalhe[[1]])) {
                  tags$div(tags$strong("Página de Detalhes: "), tags$a(href = opp$link_detalhe[[1]], target = "_blank", style = "color: #004691; font-weight: 600;", "Acessar Edital Completo ↗"))
                },
                if (!is.na(opp$link_documento_pdf[[1]]) && nzchar(opp$link_documento_pdf[[1]])) {
                  tags$div(tags$strong("Documento de Diretrizes (PDF): "), tags$a(href = opp$link_documento_pdf[[1]], target = "_blank", style = "color: #e30613; font-weight: 600;", "Baixar Edital em PDF 📥"))
                }
              )
            )
          ),
          
          # Coluna Direita (5 colunas)
          tags$div(
            class = "col-md-5", style = "margin-bottom: 20px;",
            # Destaque de Elegibilidade (Vermelho/Laranja claro)
            tags$div(
              style = "margin-bottom: 20px; background: #fff7ed; border: 1px solid #fed7aa; border-radius: 8px; padding: 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.02);",
              tags$h5(style = "color: #c2410c; margin-top: 0; margin-bottom: 12px; font-weight: 700; font-size: 1rem; text-transform: uppercase; letter-spacing: 0.5px; display: flex; align-items: center; gap: 6px;", 
                       tags$i(class = "fa fa-user-shield"), "Elegibilidade"),
              tags$div(
                style = "font-size: 0.95rem; font-weight: 700; color: #7c2d12; line-height: 1.5; white-space: pre-wrap;",
                opp$elegibilidade[[1]] %||% "Não especificada."
              )
            ),
            # Ficha Técnica Rápida
            tags$div(
              style = "background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px;",
              tags$h5(style = "color: #475569; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; font-weight: 700; font-size: 1rem; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 15px; margin-top: 0;", "Ficha Rápida"),
              tags$div(
                style = "display: flex; flex-direction: column; gap: 15px;",
                tags$div(
                  tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Prazo Limite"),
                  tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", format_date_br(opp$data_limite[[1]]))
                ),
                tags$div(
                  tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Área Temática"),
                  tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", opp$area_tematica[[1]] %||% "-")
                ),
                tags$div(
                  tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Tipo de Oportunidade"),
                  tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", opp$tipo_oportunidade[[1]] %||% "-")
                ),
                if (!is.na(opp$modalidade[[1]]) && nzchar(opp$modalidade[[1]])) {
                  tags$div(
                    tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Modalidade de Fomento"),
                    tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", opp$modalidade[[1]])
                  )
                },
                if (!is.na(opp$publico_alvo[[1]]) && nzchar(opp$publico_alvo[[1]])) {
                  tags$div(
                    tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Público-Alvo"),
                    tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", opp$publico_alvo[[1]])
                  )
                },
                if (!is.na(opp$nivel_academico[[1]]) && nzchar(opp$nivel_academico[[1]])) {
                  tags$div(
                    tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Nível Acadêmico"),
                    tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", opp$nivel_academico[[1]])
                  )
                },
                if (!is.na(opp$data_abertura[[1]]) && nzchar(opp$data_abertura[[1]])) {
                  tags$div(
                    tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Data de Abertura"),
                    tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", format_date_br(opp$data_abertura[[1]]))
                  )
                },
                if (!is.na(opp$data_encerramento[[1]]) && nzchar(opp$data_encerramento[[1]])) {
                  tags$div(
                    tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Data de Encerramento"),
                    tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", format_date_br(opp$data_encerramento[[1]]))
                  )
                },
                tags$div(
                  tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "País de Origem"),
                  tags$div(style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;", opp$pais_origem[[1]] %||% "-")
                ),
                tags$div(
                  tags$div(style = "font-size: 0.8rem; color: #64748b; font-weight: 600; text-transform: uppercase;", "Orçamento Estimado"),
                  tags$div(
                    style = "font-size: 0.95rem; font-weight: 700; color: #0f172a;",
                    if (!is.na(opp$valor_financiado[[1]])) {
                      paste(opp$moeda[[1]] %||% "", format(opp$valor_financiado[[1]], big.mark = ".", decimal.mark = ","))
                    } else {
                      "Ver documentação oficial"
                    }
                  )
                )
              )
            )
          )
        ),
        
        # Texto Bruto Coletado (Auditoria) - Colapsável
        tags$div(
          style = "margin-top: 25px; margin-bottom: 10px;",
          tags$h5(
            style = "color: #64748b; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; font-weight: 700; font-size: 1rem; text-transform: uppercase; letter-spacing: 0.5px; display: flex; justify-content: space-between; align-items: center;",
            "Conteúdo Bruto (Auditoria)",
            tags$button(
              id = "toggle_raw_text_btn",
              class = "btn btn-sm btn-outline-secondary",
              style = "padding: 2px 8px; font-size: 0.75rem;",
              onclick = "var x = document.getElementById('modal_raw_text_div'); if(x.style.display === 'none'){x.style.display = 'block'; this.innerText = 'Ocultar Texto';}else{x.style.display = 'none'; this.innerText = 'Mostrar Texto';}",
              "Mostrar Texto"
            )
          ),
          tags$div(
            id = "modal_raw_text_div",
            style = "display: none; max-height: 200px; overflow-y: auto; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 12px; font-family: monospace; font-size: 0.8rem; white-space: pre-wrap; color: #475569; margin-top: 10px;",
            opp$texto_bruto[[1]] %||% "Nenhum texto bruto disponível para este edital."
          )
        )
      )
    ))
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
    safe_drive_upload()
  })

  observeEvent(input$btn_remove_tracked, {
    req(conn, rv$selected_tracked_id)
    delete_tracked_opportunity(conn, rv$selected_tracked_id)
    rv$selected_tracked_id <- NULL
    refresh_data()
    showNotification("Item removido da lista de rastreamento.", type = "message")
    safe_drive_upload()
  })

  output$recommended_table <- renderDT({
    df <- recommend_opportunities(conn, filtered_results(), rv$current_query, top_n = 15)
    if (nrow(df) == 0) {
      shown <- tibble::tibble(Título = character(), Financiador = factor(), Score = numeric(), Prazo = character(), Tipo = factor(), Link = character(), Visualizar = character())
    } else {
      shown <- df |>
        dplyr::mutate(
          Link = vapply(dplyr::coalesce(link_detalhe, link_origem), link_html, character(1), label = "Abrir"),
          Visualizar = vapply(id_registro, make_view_button, character(1)),
          Financiador = as.factor(entidade),
          Tipo = as.factor(tools::toTitleCase(tolower(dplyr::coalesce(tipo_oportunidade, "não especificado"))))
        ) |>
        dplyr::transmute(Título = titulo, Financiador, Score = score_aderencia, Prazo = format_date_br(data_limite), Tipo, Link, Visualizar)
    }
    DT::datatable(
      shown, 
      escape = FALSE, 
      rownames = FALSE,
      filter = "top", 
      options = list(
        pageLength = 10, 
        scrollX = TRUE, 
        language = list(emptyTable = "Nenhuma recomendação disponível."),
        columnDefs = list(
          list(targets = c(0, 2, 3, 5, 6), searchable = FALSE)
        )
      )
    )
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
