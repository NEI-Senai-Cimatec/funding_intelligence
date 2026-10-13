# ─── Agendador Autônomo em Background para Posit Connect ──────────────────────
# Executa a busca de editais semanalmente sem depender do painel do Connect.
# Configuração padrão: Toda terça-feira às 14:15 (Horário de Brasília), recorrente sem fim.

.auto_scheduler_bg_process <- NULL
.auto_scheduler_initialized <- FALSE

get_last_successful_collection_time <- function(conn) {
  tryCatch({
    if (DBI::dbExistsTable(conn, "logs_coleta")) {
      res <- DBI::dbGetQuery(
        conn,
        "SELECT data_execucao FROM logs_coleta WHERE status_execucao = 'sucesso' ORDER BY data_execucao DESC LIMIT 1"
      )
      if (nrow(res) > 0 && !is.na(res$data_execucao[[1]])) {
        return(lubridate::as_datetime(res$data_execucao[[1]]))
      }
    }
    NULL
  }, error = function(e) NULL)
}

is_collection_due <- function(target_wday = 3, target_hour = 14, target_minute = 15) {
  # wday no lubridate: 1=Dom, 2=Seg, 3=Ter, 4=Qua, 5=Qui, 6=Sex, 7=Sáb
  # 3 = Terça-feira
  now_brt <- tryCatch(
    lubridate::with_tz(Sys.time(), tzone = "America/Sao_Paulo"),
    error = function(e) Sys.time()
  )
  
  current_wday <- lubridate::wday(now_brt)
  days_since_target <- (current_wday - target_wday) %% 7
  
  # Data/hora de referência da última terça-feira às 14:15
  target_dt <- lubridate::floor_date(now_brt - lubridate::days(days_since_target), "day") +
    lubridate::hours(target_hour) + lubridate::minutes(target_minute)
  
  # Se o horário alvo de hoje ainda não chegou, a referência é a semana anterior
  if (now_brt < target_dt) {
    target_dt <- target_dt - lubridate::weeks(1)
  }
  
  # Conecta ao banco de dados para checar a última coleta bem-sucedida
  conn <- tryCatch(conectar_banco("funding_intelligence.sqlite"), error = function(e) NULL)
  if (is.null(conn)) return(FALSE)
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  
  last_success <- get_last_successful_collection_time(conn)
  if (is.null(last_success)) {
    # Nenhuma coleta com sucesso registrada no banco -> precisa rodar
    return(TRUE)
  }
  
  last_success_brt <- tryCatch(
    lubridate::with_tz(last_success, tzone = "America/Sao_Paulo"),
    error = function(e) last_success
  )
  
  # Se a última coleta de sucesso foi antes do prazo alvo da semana atual, está devendo!
  return(last_success_brt < target_dt)
}

trigger_background_collection_daemon <- function(app_dir = getwd()) {
  # Se já houver um processo em execução, não inicia outro
  if (!is.null(.auto_scheduler_bg_process) && .auto_scheduler_bg_process$is_alive()) {
    message("[Agendador] Coleta já está em andamento. Aguardando finalização.")
    return(invisible(FALSE))
  }
  
  message(sprintf("[Agendador] Disparando coleta automática recorrente em background às %s...", format(Sys.time(), "%H:%M:%S")))
  
  db_url <- Sys.getenv("DATABASE_URL")
  gemini_key <- Sys.getenv("GEMINI_API_KEY")
  nvidia_key <- Sys.getenv("NVIDIA_API_KEY")
  ai_prov <- Sys.getenv("AI_PROVIDER")
  ai_mod <- Sys.getenv("AI_MODEL")
  proxy_url <- Sys.getenv("EU_API_PROXY_URL")
  
  p <- tryCatch({
    callr::r_bg(
      func = function(dir, envs) {
        setwd(dir)
        for (n in names(envs)) {
          if (nzchar(envs[[n]])) {
            args <- list(envs[[n]])
            names(args) <- n
            do.call(Sys.setenv, args)
          }
        }
        source("tools/auto_collect.R")
        main_auto_collect(test_mode = FALSE)
      },
      args = list(
        dir = app_dir,
        envs = list(
          DATABASE_URL = db_url,
          GEMINI_API_KEY = gemini_key,
          NVIDIA_API_KEY = nvidia_key,
          AI_PROVIDER = ai_prov,
          AI_MODEL = ai_mod,
          EU_API_PROXY_URL = proxy_url
        )
      ),
      stdout = "",
      stderr = "",
      supervise = TRUE
    )
  }, error = function(e) {
    message(sprintf("[Agendador] Falha ao lançar processo: %s", e$message))
    NULL
  })
  
  if (!is.null(p)) {
    .auto_scheduler_bg_process <<- p
    message(sprintf("[Agendador] Processo PID %d lançado com sucesso.", p$get_pid()))
    return(invisible(TRUE))
  }
  invisible(FALSE)
}

init_auto_scheduler_daemon <- function(check_interval_sec = 120) {
  if (isTRUE(.auto_scheduler_initialized)) return(invisible(NULL))
  .auto_scheduler_initialized <<- TRUE
  
  heartbeat <- function() {
    tryCatch({
      if (is_collection_due(target_wday = 3, target_hour = 14, target_minute = 15)) {
        trigger_background_collection_daemon()
      }
    }, error = function(e) {
      message(sprintf("[Agendador] Erro no ciclo de checagem: %s", e$message))
    })
    
    # Reagenda o próximo ciclo para sempre (indefinidamente)
    later::later(heartbeat, check_interval_sec)
  }
  
  # Primeira verificação 15 segundos após carregar o app
  later::later(heartbeat, 15)
  message("[Agendador] Daemon interno de coleta recorrente ATIVADO (Terças-feiras às 14:15 BRT, sem fim).")
}
