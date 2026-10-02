# ─── Módulo de Autenticação e Controle de Acesso (Supabase Auth) ───────────────
# Suporta autenticação via Supabase GoTrue REST API com controle de permissões (RBAC)
# Desenvolvedores / Diretoria: Acesso total (inclui 'Atualizar base', 'Buscas salvas', 'Editais rastreados', 'Logs')
# Usuários normais: Visualização e busca de editais ('Resultados', 'Por financiador')

`%||%` <- function(a, b) if (is.null(a)) b else a

# Obtém as configurações do Supabase a partir das variáveis de ambiente
supabase_get_config <- function() {
  url <- Sys.getenv("SUPABASE_URL", "")
  key <- Sys.getenv("SUPABASE_ANON_KEY", Sys.getenv("SUPABASE_KEY", ""))
  dev_emails_str <- Sys.getenv("SUPABASE_DEV_EMAILS", Sys.getenv("ADMIN_EMAILS", ""))
  
  dev_emails <- unlist(strsplit(dev_emails_str, "[,; ]+"))
  dev_emails <- tolower(trimws(dev_emails))
  dev_emails <- dev_emails[nzchar(dev_emails)]
  
  raw_url <- trimws(url)
  clean_url <- sub("/rest/v1/?$", "", raw_url, ignore.case = TRUE)
  clean_url <- sub("/+$", "", clean_url)
  
  list(
    url = clean_url,
    anon_key = trimws(key),
    dev_emails = dev_emails,
    is_configured = nzchar(clean_url) && nzchar(key)
  )
}

# Verifica se o Supabase está configurado no ambiente
supabase_is_configured <- function() {
  cfg <- supabase_get_config()
  isTRUE(cfg$is_configured)
}

# Autentica o usuário com email e senha na API REST do Supabase
supabase_authenticate <- function(email, password, conn = NULL) {
  email <- trimws(as.character(email %||% ""))
  password <- as.character(password %||% "")
  
  if (!nzchar(email) || !nzchar(password)) {
    return(list(
      success = FALSE,
      message = "Por favor, informe tanto o e-mail quanto a senha."
    ))
  }
  
  cfg <- supabase_get_config()
  
  if (!isTRUE(cfg$is_configured)) {
    return(list(
      success = FALSE,
      message = paste0(
        "Configuração do Supabase ausente. Defina SUPABASE_URL e SUPABASE_ANON_KEY no arquivo .Renviron ",
        "para habilitar a autenticação na plataforma."
      )
    ))
  }
  
  endpoint <- paste0(cfg$url, "/auth/v1/token?grant_type=password")
  
  resp <- tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = cfg$anon_key,
        "Content-Type" = "application/json"
      ) |>
      httr2::req_body_json(list(email = email, password = password)) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(15) |>
      httr2::req_perform()
  }, error = function(e) {
    return(list(
      success = FALSE,
      message = sprintf("Não foi possível conectar ao servidor de autenticação Supabase: %s", e$message)
    ))
  })
  
  if (is.list(resp) && !inherits(resp, "httr2_response")) {
    return(resp)
  }
  
  status <- httr2::resp_status(resp)
  body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
  body_json <- tryCatch(jsonlite::fromJSON(body_text, simplifyVector = FALSE), error = function(e) NULL)
  
  if (status == 200 && !is.null(body_json$access_token)) {
    user <- body_json$user %||% list(email = email)
    access_tok <- body_json$access_token
    
    # Opção 3: Obtém a permissão do usuário diretamente na tabela 'public.perfis' do Supabase
    is_dev <- supabase_is_dev_or_diretoria(user, access_token = access_tok, conn = conn)
    user$cargo <- if (isTRUE(is_dev)) "diretoria" else "leitor"
    
    return(list(
      success = TRUE,
      access_token = access_tok,
      refresh_token = body_json$refresh_token,
      user = user,
      is_dev = is_dev,
      cargo = user$cargo,
      message = "Autenticação realizada com sucesso."
    ))
  }
  
  # Tratamento amigável de erros retornados pelo Supabase
  raw_msg <- body_json$msg %||% body_json$error_description %||% body_json$message %||% ""
  
  err_msg <- if (grepl("invalid login credentials|invalid_grant|invalid password", tolower(raw_msg))) {
    "E-mail ou senha incorretos. Por favor, verifique suas credenciais."
  } else if (grepl("email not confirmed", tolower(raw_msg))) {
    "E-mail cadastrado, porém ainda não confirmado no Supabase. Verifique sua caixa de entrada."
  } else if (grepl("too many requests|rate limit", tolower(raw_msg))) {
    "Muitas tentativas consecutivas de login. Aguarde alguns instantes e tente novamente."
  } else if (nzchar(raw_msg)) {
    raw_msg
  } else {
    sprintf("Falha na autenticação (Código HTTP %s).", status)
  }
  
  list(
    success = FALSE,
    message = err_msg,
    status_code = status
  )
}

# Cadastra um novo usuário no Supabase Auth
supabase_sign_up <- function(email, password) {
  email <- tolower(trimws(as.character(email %||% "")))
  password <- as.character(password %||% "")
  
  if (!nzchar(email) || !nzchar(password)) {
    return(list(
      success = FALSE,
      message = "Por favor, preencha o e-mail institucional e defina uma senha."
    ))
  }
  
  if (nchar(password) < 6) {
    return(list(
      success = FALSE,
      message = "A senha deve ter no mínimo 6 caracteres."
    ))
  }
  
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) {
    return(list(
      success = FALSE,
      message = "Configuração do Supabase ausente. Defina SUPABASE_URL e SUPABASE_ANON_KEY no arquivo .Renviron."
    ))
  }
  
  endpoint <- paste0(cfg$url, "/auth/v1/signup")
  
  resp <- tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = cfg$anon_key,
        "Content-Type" = "application/json"
      ) |>
      httr2::req_body_json(list(email = email, password = password)) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(15) |>
      httr2::req_perform()
  }, error = function(e) {
    return(list(
      success = FALSE,
      message = sprintf("Não foi possível conectar ao servidor Supabase: %s", e$message)
    ))
  })
  
  if (is.list(resp) && !inherits(resp, "httr2_response")) {
    return(resp)
  }
  
  status <- httr2::resp_status(resp)
  body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
  body_json <- tryCatch(jsonlite::fromJSON(body_text, simplifyVector = FALSE), error = function(e) NULL)
  
  if (status %in% c(200, 201)) {
    user <- body_json$user %||% body_json
    has_token <- !is.null(body_json$access_token) && nzchar(as.character(body_json$access_token))
    access_tok <- if (has_token) body_json$access_token else NULL
    refresh_tok <- if (has_token) body_json$refresh_token else NULL
    
    msg <- if (has_token) {
      "Conta criada com sucesso! Acesso concedido como Leitor."
    } else {
      "Conta criada com sucesso! Caso a confirmação de e-mail esteja ativada no seu Supabase, verifique sua caixa de entrada antes de entrar."
    }
    
    return(list(
      success = TRUE,
      user = user,
      access_token = access_tok,
      refresh_token = refresh_tok,
      auto_login = has_token,
      message = msg
    ))
  }
  
  raw_msg <- body_json$msg %||% body_json$error_description %||% body_json$message %||% ""
  
  err_msg <- if (grepl("already registered|user already exists|email already in use", tolower(raw_msg))) {
    "Este e-mail já está cadastrado no sistema. Por favor, acesse a aba 'Entrar' para fazer login."
  } else if (grepl("at least 6 characters|weak_password", tolower(raw_msg))) {
    "A senha deve conter no mínimo 6 caracteres."
  } else if (grepl("valid email|invalid email", tolower(raw_msg))) {
    "Por favor, informe um endereço de e-mail institucional válido."
  } else if (grepl("signups not allowed", tolower(raw_msg))) {
    "Novos cadastros públicos estão desabilitados na configuração do projeto Supabase."
  } else if (nzchar(raw_msg)) {
    raw_msg
  } else {
    sprintf("Não foi possível concluir o cadastro (Código HTTP %s).", status)
  }
  
  list(
    success = FALSE,
    message = err_msg,
    status_code = status
  )
}

# Encerra a sessão no Supabase (logout)
supabase_sign_out <- function(access_token) {
  if (is.null(access_token) || !nzchar(access_token)) return(invisible(FALSE))
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) return(invisible(FALSE))
  
  endpoint <- paste0(cfg$url, "/auth/v1/logout")
  tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = cfg$anon_key,
        "Authorization" = paste("Bearer", access_token)
      ) |>
      httr2::req_method("POST") |>
      httr2::req_timeout(8) |>
      httr2::req_perform()
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

# ─── Sessão Persistente (Validação e Renovação de Token) ───────────────────────

# Obtém os dados do usuário a partir de um access_token JWT válido
supabase_get_user <- function(access_token) {
  if (is.null(access_token) || !nzchar(as.character(access_token))) {
    return(list(success = FALSE, message = "Token de acesso não fornecido."))
  }
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) {
    return(list(success = FALSE, message = "Configuração do Supabase ausente."))
  }
  
  endpoint <- paste0(cfg$url, "/auth/v1/user")
  resp <- tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = cfg$anon_key,
        "Authorization" = paste("Bearer", access_token)
      ) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(8) |>
      httr2::req_perform()
  }, error = function(e) NULL)
  
  if (is.null(resp)) return(list(success = FALSE, message = "Falha de rede ao validar sessão."))
  
  status <- httr2::resp_status(resp)
  if (status == 200) {
    body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
    body_json <- tryCatch(jsonlite::fromJSON(body_text, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(body_json) && !is.null(body_json$email)) {
      return(list(success = TRUE, user = body_json))
    }
  }
  
  list(success = FALSE, status_code = status)
}

# Renova o par de tokens (access e refresh) usando um refresh_token válido
supabase_refresh_session <- function(refresh_token) {
  if (is.null(refresh_token) || !nzchar(as.character(refresh_token))) {
    return(list(success = FALSE, message = "Refresh token ausente."))
  }
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) {
    return(list(success = FALSE, message = "Configuração do Supabase ausente."))
  }
  
  endpoint <- paste0(cfg$url, "/auth/v1/token?grant_type=refresh_token")
  resp <- tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = cfg$anon_key,
        "Content-Type" = "application/json"
      ) |>
      httr2::req_body_json(list(refresh_token = as.character(refresh_token))) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(10) |>
      httr2::req_perform()
  }, error = function(e) NULL)
  
  if (is.null(resp)) return(list(success = FALSE, message = "Falha de rede ao renovar sessão."))
  
  status <- httr2::resp_status(resp)
  if (status == 200) {
    body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
    body_json <- tryCatch(jsonlite::fromJSON(body_text, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(body_json$access_token)) {
      return(list(
        success = TRUE,
        access_token = body_json$access_token,
        refresh_token = body_json$refresh_token %||% refresh_token,
        user = body_json$user
      ))
    }
  }
  
  list(success = FALSE, status_code = status)
}

# Restaura uma sessão a partir de dados salvos no localStorage (access_token / refresh_token)
supabase_restore_session <- function(session_data, conn = NULL) {
  if (!is.list(session_data)) return(list(success = FALSE))
  access_tok <- as.character(session_data$access_token %||% "")
  refresh_tok <- as.character(session_data$refresh_token %||% "")
  cached_user <- session_data$user
  
  # 1. Tenta validar o access_token atual na API GoTrue do Supabase
  user_res <- if (nzchar(access_tok)) {
    supabase_get_user(access_tok)
  } else {
    list(success = FALSE)
  }
  
  if (isTRUE(user_res$success)) {
    user <- user_res$user
    is_dev <- supabase_is_dev_or_diretoria(user, access_token = access_tok, conn = conn)
    user$cargo <- if (isTRUE(is_dev)) "diretoria" else "leitor"
    return(list(
      success = TRUE,
      user = user,
      access_token = access_tok,
      refresh_token = refresh_tok,
      is_dev = is_dev,
      updated = FALSE
    ))
  }
  
  # 2. Se o access_token expirou, renova silenciosamente usando o refresh_token
  if (nzchar(refresh_tok)) {
    ref_res <- supabase_refresh_session(refresh_tok)
    if (isTRUE(ref_res$success)) {
      user <- ref_res$user %||% cached_user
      is_dev <- supabase_is_dev_or_diretoria(user, access_token = ref_res$access_token, conn = conn)
      user$cargo <- if (isTRUE(is_dev)) "diretoria" else "leitor"
      return(list(
        success = TRUE,
        user = user,
        access_token = ref_res$access_token,
        refresh_token = ref_res$refresh_token,
        is_dev = is_dev,
        updated = TRUE
      ))
    }
  }
  
  list(success = FALSE)
}

# ─── Opção 3: Consulta de Permissões na Tabela 'public.perfis' do Supabase ───────

# Consulta a role/cargo do usuário diretamente na tabela 'public.perfis' do Supabase via REST API
supabase_get_user_role_from_db <- function(user, access_token = NULL) {
  if (is.null(user)) return(NULL)
  
  user_id <- as.character(user$id %||% "")
  user_email <- tolower(trimws(as.character(user$email %||% "")))
  
  if (!nzchar(user_id) && !nzchar(user_email)) return(NULL)
  
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) return(NULL)
  
  endpoint <- paste0(cfg$url, "/rest/v1/perfis")
  
  headers <- list(
    "apikey" = cfg$anon_key,
    "Accept" = "application/json"
  )
  if (!is.null(access_token) && nzchar(access_token)) {
    headers[["Authorization"]] <- paste("Bearer", access_token)
  }
  
  query_params <- if (nzchar(user_id)) {
    list(id = paste0("eq.", user_id), select = "cargo")
  } else {
    list(email = paste0("eq.", user_email), select = "cargo")
  }
  
  resp <- tryCatch({
    req <- httr2::request(endpoint) |>
      httr2::req_headers(!!!headers) |>
      httr2::req_url_query(!!!query_params) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(5)
    
    httr2::req_perform(req)
  }, error = function(e) NULL)
  
  if (is.null(resp)) return(NULL)
  
  status <- httr2::resp_status(resp)
  if (status >= 200 && status < 300) {
    body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
    body_json <- tryCatch(jsonlite::fromJSON(body_text, simplifyVector = TRUE), error = function(e) NULL)
    
    if (is.data.frame(body_json) && nrow(body_json) > 0 && "cargo" %in% names(body_json)) {
      cargo_val <- tolower(trimws(as.character(body_json$cargo[[1]] %||% "")))
      if (nzchar(cargo_val)) return(cargo_val)
    } else if (is.list(body_json) && length(body_json) > 0) {
      first_item <- body_json[[1]]
      if (is.list(first_item) && !is.null(first_item$cargo)) {
        cargo_val <- tolower(trimws(as.character(first_item$cargo %||% "")))
        if (nzchar(cargo_val)) return(cargo_val)
      }
    }
  }
  
  NULL
}

# Consulta todos os perfis cadastrados no Supabase (para visualização no painel de gestão)
supabase_get_all_profiles <- function(access_token = NULL) {
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) return(tibble::tibble())
  
  endpoint <- paste0(cfg$url, "/rest/v1/perfis")
  headers <- list(
    "apikey" = cfg$anon_key,
    "Accept" = "application/json"
  )
  if (!is.null(access_token) && nzchar(access_token)) {
    headers[["Authorization"]] <- paste("Bearer", access_token)
  }
  
  resp <- tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(!!!headers) |>
      httr2::req_url_query(select = "id,email,cargo,criado_em", order = "email.asc") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(5) |>
      httr2::req_perform()
  }, error = function(e) NULL)
  
  if (is.null(resp)) return(tibble::tibble())
  
  status <- httr2::resp_status(resp)
  if (status >= 200 && status < 300) {
    body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
    body_df <- tryCatch(jsonlite::fromJSON(body_text, simplifyDataFrame = TRUE), error = function(e) NULL)
    if (is.data.frame(body_df)) {
      return(tibble::as_tibble(body_df))
    }
  }
  
  tibble::tibble()
}

# Determina se o usuário autenticado possui credenciais de Desenvolvedor / Diretoria
supabase_is_dev_or_diretoria <- function(user, access_token = NULL, conn = NULL) {
  if (is.null(user)) return(FALSE)
  
  dev_roles <- c("diretoria", "dev", "developer", "desenvolvedor", "admin", "administrator", "administrador", "curador", "coordenacao", "coordenador")
  
  # 1. Se o objeto de usuário já possui o cargo resolvido em cache de sessão
  if (!is.null(user$cargo) && nzchar(user$cargo)) {
    cargo_clean <- tolower(trimws(as.character(user$cargo)))
    if (cargo_clean %in% dev_roles) return(TRUE)
    if (cargo_clean %in% c("leitor", "usuario", "user", "viewer", "pesquisador")) return(FALSE)
  }
  
  email <- tolower(trimws(as.character(user$email %||% "")))
  
  # 2. Verifica se o e-mail está na lista de dev_emails configurada no .Renviron (Super-rápido / 0ms)
  cfg <- supabase_get_config()
  if (nzchar(email) && length(cfg$dev_emails) > 0 && email %in% cfg$dev_emails) {
    return(TRUE)
  }
  
  # 3. Consulta à tabela 'public.perfis' do Supabase via REST API (Opção 3)
  sb_role <- tryCatch({
    supabase_get_user_role_from_db(user, access_token = access_token)
  }, error = function(e) NULL)
  
  if (!is.null(sb_role) && nzchar(sb_role)) {
    if (sb_role %in% dev_roles) {
      return(TRUE)
    }
    if (sb_role %in% c("leitor", "usuario", "user", "viewer", "pesquisador")) {
      return(FALSE)
    }
  }
  
  # 4. Fallback: Verifica na tabela local SQLite de permissões (user_permissions)
  if (!is.null(conn)) {
    db_role <- tryCatch({
      res <- DBI::dbGetQuery(conn, "SELECT role FROM user_permissions WHERE lower(email) = lower(?)", params = list(email))
      if (nrow(res) > 0) tolower(trimws(res$role[[1]])) else ""
    }, error = function(e) "")
    if (db_role %in% dev_roles) {
      return(TRUE)
    }
  }
  
  # 5. Fallback: Verifica a role no app_metadata do Supabase
  app_role <- tolower(trimws(as.character(user$app_metadata$role %||% "")))
  if (nzchar(app_role) && app_role %in% dev_roles) {
    return(TRUE)
  }
  
  # 6. Fallback: Verifica a role no user_metadata do Supabase
  user_role <- tolower(trimws(as.character(user$user_metadata$role %||% "")))
  if (nzchar(user_role) && user_role %in% dev_roles) {
    return(TRUE)
  }
  
  # 7. Fallback: Verifica flags booleanas em user_metadata / app_metadata
  is_admin_flag <- isTRUE(user$user_metadata$is_admin) || isTRUE(user$user_metadata$is_dev) ||
                   isTRUE(user$app_metadata$is_admin) || isTRUE(user$app_metadata$is_dev)
  if (is_admin_flag) {
    return(TRUE)
  }
  
  FALSE
}

# Retorna a descrição amigável do nível de acesso
get_user_role_label <- function(user, is_dev = NULL, conn = NULL, access_token = NULL) {
  if (is.null(user)) return("Não autenticado")
  if (is.null(is_dev)) is_dev <- supabase_is_dev_or_diretoria(user, access_token = access_token, conn = conn)
  
  if (isTRUE(is_dev)) {
    "Diretoria"
  } else {
    "Leitor / Pesquisador"
  }
}

# Garante que as tabelas de auditoria e de permissões existam no banco SQLite
ensure_auth_db_table <- function(conn) {
  if (is.null(conn)) return(invisible(FALSE))
  tryCatch({
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS user_access_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        email TEXT,
        role TEXT,
        action TEXT,
        details TEXT,
        timestamp TEXT DEFAULT (datetime('now', 'localtime'))
      )
    ")
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS user_permissions (
        email TEXT PRIMARY KEY,
        role TEXT DEFAULT 'usuario',
        updated_at TEXT
      )
    ")
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

# Salva ou atualiza a permissão de um usuário no SQLite
set_user_permission <- function(conn, email, role = "usuario") {
  if (is.null(conn) || !nzchar(trimws(email %||% ""))) return(invisible(FALSE))
  email <- tolower(trimws(email))
  role <- tolower(trimws(role))
  now_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  tryCatch({
    DBI::dbExecute(
      conn,
      "INSERT INTO user_permissions (email, role, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(email) DO UPDATE SET role = excluded.role, updated_at = excluded.updated_at",
      params = list(email, role, now_str)
    )
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

# Remove uma permissão customizada da tabela local
remove_user_permission <- function(conn, email) {
  if (is.null(conn) || !nzchar(trimws(email %||% ""))) return(invisible(FALSE))
  email <- tolower(trimws(email))
  tryCatch({
    DBI::dbExecute(conn, "DELETE FROM user_permissions WHERE lower(email) = lower(?)", params = list(email))
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

# Obtém a lista de todas as permissões cadastradas no SQLite
get_user_permissions <- function(conn) {
  if (is.null(conn)) return(tibble::tibble(email = character(), role = character(), updated_at = character()))
  tryCatch({
    res <- DBI::dbGetQuery(conn, "SELECT email, role, updated_at FROM user_permissions ORDER BY email ASC")
    tibble::as_tibble(res)
  }, error = function(e) tibble::tibble(email = character(), role = character(), updated_at = character()))
}

# Registra uma ação de auditoria de usuário no banco de dados SQLite ou PostgreSQL
log_user_access <- function(conn, user, action, details = "") {
  if (is.null(conn)) return(invisible(FALSE))
  
  user_id <- as.character(user$id %||% "anônimo")
  email <- as.character(user$email %||% "anônimo")
  is_dev <- if (!is.null(user$cargo)) {
    isTRUE(tolower(trimws(as.character(user$cargo))) %in% c("diretoria", "dev", "developer", "desenvolvedor", "admin", "administrador", "curador"))
  } else {
    supabase_is_dev_or_diretoria(user, conn = conn)
  }
  role <- if (isTRUE(is_dev)) "diretoria/dev" else "usuario"
  now_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  tryCatch({
    db_exec(
      conn,
      "INSERT INTO user_access_logs (user_id, email, role, action, details, timestamp) VALUES (?, ?, ?, ?, ?, ?)",
      params = list(user_id, email, role, as.character(action), as.character(details %||% ""), now_str)
    )
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

# Obtém os registros recentes de auditoria de acesso
get_user_access_logs <- function(conn, limit = 200) {
  if (is.null(conn)) return(tibble::tibble())
  tryCatch({
    res <- db_qry(
      conn,
      sprintf("SELECT id, timestamp, email, role, action, details FROM user_access_logs ORDER BY id DESC LIMIT %d", as.integer(limit))
    )
    tibble::as_tibble(res)
  }, error = function(e) tibble::tibble())
}

# Renderiza a tela de login em tela cheia (Overlay que bloqueia visualização de editais)
render_login_overlay <- function(error_msg = NULL, success_msg = NULL, initial_mode = "login") {
  cfg <- supabase_get_config()
  
  htmltools::tags$div(
    id = "auth_overlay_root",
    class = "auth-overlay-backdrop",
    htmltools::tags$div(
      class = "auth-card",
      
      # Cabeçalho com logo do SENAI CIMATEC
      htmltools::tags$div(
        class = "auth-header",
        htmltools::tags$img(src = "senai_cimatec.jpg", class = "auth-logo-img", alt = "SENAI CIMATEC"),
        htmltools::tags$h2(class = "auth-title", "Radar da Inovação"),
        htmltools::tags$p(class = "auth-subtitle", "Plataforma de Inteligência de Fomento à P&D+I")
      ),
      
      # Alerta se o Supabase não estiver configurado no .Renviron
      if (!isTRUE(cfg$is_configured)) {
        htmltools::tags$div(
          class = "auth-alert auth-alert-warning",
          htmltools::tags$i(class = "fa fa-exclamation-triangle", style = "margin-top: 2px;"),
          htmltools::tags$div(
            htmltools::tags$strong("Configuração do Supabase pendente:"),
            htmltools::tags$br(),
            "Defina as variáveis ", htmltools::tags$code("SUPABASE_URL"), " e ", htmltools::tags$code("SUPABASE_ANON_KEY"),
            " no arquivo ", htmltools::tags$code(".Renviron"), " e reinicie a aplicação."
          )
        )
      },
      
      # Mensagem de sucesso (ex.: conta criada)
      if (!is.null(success_msg) && nzchar(success_msg)) {
        htmltools::tags$div(
          class = "auth-alert auth-alert-success",
          htmltools::tags$i(class = "fa fa-circle-check", style = "margin-top: 2px;"),
          htmltools::tags$div(success_msg)
        )
      },
      
      # Mensagem de erro de autenticação ou cadastro (se houver)
      if (!is.null(error_msg) && nzchar(error_msg)) {
        htmltools::tags$div(
          class = "auth-alert auth-alert-danger",
          htmltools::tags$i(class = "fa fa-circle-exclamation", style = "margin-top: 2px;"),
          htmltools::tags$div(error_msg)
        )
      },
      
      # Alternador de Abas (Entrar vs Criar Conta)
      htmltools::tags$div(
        class = "auth-tabs-nav",
        htmltools::tags$button(
          id = "auth_tab_login",
          type = "button",
          class = if (identical(initial_mode, "signup")) "auth-tab-btn" else "auth-tab-btn active",
          `data-mode` = "login",
          onclick = "window.switchAuthTab && window.switchAuthTab('login')",
          htmltools::tags$i(class = "fa fa-right-to-bracket"),
          htmltools::tags$span("Entrar")
        ),
        htmltools::tags$button(
          id = "auth_tab_signup",
          type = "button",
          class = if (identical(initial_mode, "signup")) "auth-tab-btn active" else "auth-tab-btn",
          `data-mode` = "signup",
          onclick = "window.switchAuthTab && window.switchAuthTab('signup')",
          htmltools::tags$i(class = "fa fa-user-plus"),
          htmltools::tags$span("Criar Conta")
        )
      ),
      
      # Estado de Restauração de Sessão (Visível quando restaurando sessão salva no localStorage)
      htmltools::tags$div(
        id = "auth_restoring_state",
        style = "display: none; text-align: center; padding: 2rem 1rem;",
        htmltools::tags$i(class = "fa fa-circle-notch fa-spin", style = "font-size: 2.2rem; color: #004691; margin-bottom: 1rem;"),
        htmltools::tags$h4(style = "color: #0f172a; font-size: 1.15rem; font-weight: 700; margin-bottom: 0.5rem;", "Restaurando sua sessão..."),
        htmltools::tags$p(style = "color: #64748b; font-size: 0.85rem; margin: 0;", "Validando credenciais salvas no navegador.")
      ),
      
      # ─── Formulário 1: Login ───────────────────────────────────────────────
      htmltools::tags$div(
        id = "auth_form_login",
        style = if (identical(initial_mode, "signup")) "display: none;" else "display: block;",
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "E-mail institucional:"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-envelope auth-input-icon"),
            shiny::tags$input(
              id = "login_email",
              type = "email",
              class = "auth-input",
              placeholder = "seu.email@fieb.org.br",
              autocomplete = "username"
            )
          )
        ),
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "Senha:"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-lock auth-input-icon"),
            shiny::tags$input(
              id = "login_password",
              type = "password",
              class = "auth-input",
              placeholder = "••••••••",
              autocomplete = "current-password",
              style = "padding-right: 2.5rem;"
            ),
            htmltools::tags$button(
              type = "button",
              class = "btn-toggle-pwd",
              `data-target` = "login_password",
              style = "position: absolute; right: 0.75rem; background: none; border: none; color: #94a3b8; cursor: pointer; padding: 4px;",
              title = "Mostrar/ocultar senha",
              htmltools::tags$i(class = "fa fa-eye")
            )
          )
        ),
        
        # Alerta de erro dinâmico instantâneo via JavaScript
        htmltools::tags$div(
          id = "auth_login_error_box",
          class = "auth-alert auth-alert-danger",
          style = "display: none; margin-bottom: 1rem;",
          htmltools::tags$i(class = "fa fa-circle-exclamation", style = "margin-top: 2px;"),
          htmltools::tags$div(id = "auth_login_error_text", "")
        ),
        
        htmltools::tags$button(
          id = "btn_login_submit",
          type = "button",
          class = "auth-btn-primary",
          onclick = "window.submitLoginForm && window.submitLoginForm()",
          htmltools::tags$i(class = "fa fa-right-to-bracket", style = "margin-right: 8px;"),
          htmltools::tags$span("Entrar na Plataforma")
        ),
        
        htmltools::tags$div(
          style = "text-align: center; margin-top: 1rem; font-size: 0.8rem; color: #64748b;",
          "Ainda não tem uma conta? ",
          htmltools::tags$a(
            href = "#",
            style = "color: #004691; font-weight: 600; text-decoration: none;",
            onclick = "window.switchAuthTab && window.switchAuthTab('signup'); return false;",
            "Cadastre-se aqui"
          )
        )
      ),
      
      # ─── Formulário 2: Cadastro / Criar Conta ──────────────────────────────
      htmltools::tags$div(
        id = "auth_form_signup",
        style = if (identical(initial_mode, "signup")) "display: block;" else "display: none;",
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "E-mail institucional:"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-envelope auth-input-icon"),
            shiny::tags$input(
              id = "signup_email",
              type = "email",
              class = "auth-input",
              placeholder = "seu.email@fieb.org.br",
              autocomplete = "email"
            )
          )
        ),
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "Criar senha (mínimo 6 caracteres):"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-lock auth-input-icon"),
            shiny::tags$input(
              id = "signup_password",
              type = "password",
              class = "auth-input",
              placeholder = "••••••••",
              autocomplete = "new-password",
              style = "padding-right: 2.5rem;"
            ),
            htmltools::tags$button(
              type = "button",
              class = "btn-toggle-pwd",
              `data-target` = "signup_password",
              style = "position: absolute; right: 0.75rem; background: none; border: none; color: #94a3b8; cursor: pointer; padding: 4px;",
              title = "Mostrar/ocultar senha",
              htmltools::tags$i(class = "fa fa-eye")
            )
          )
        ),
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "Confirmar senha:"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-check-double auth-input-icon"),
            shiny::tags$input(
              id = "signup_password_confirm",
              type = "password",
              class = "auth-input",
              placeholder = "••••••••",
              autocomplete = "new-password",
              style = "padding-right: 2.5rem;"
            ),
            htmltools::tags$button(
              type = "button",
              class = "btn-toggle-pwd",
              `data-target` = "signup_password_confirm",
              style = "position: absolute; right: 0.75rem; background: none; border: none; color: #94a3b8; cursor: pointer; padding: 4px;",
              title = "Mostrar/ocultar senha",
              htmltools::tags$i(class = "fa fa-eye")
            )
          )
        ),
        
        htmltools::tags$div(
          style = "font-size: 0.75rem; color: #64748b; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 0.5rem 0.75rem; margin-bottom: 1.25rem;",
          htmltools::tags$i(class = "fa fa-info-circle", style = "color: #004691; margin-right: 4px;"),
          "Novos cadastros recebem permissão de ",
          htmltools::tags$strong("Leitor"),
          " para consulta e pesquisa de editais."
        ),
        
        # Alerta de erro dinâmico de cadastro instantâneo via JavaScript
        htmltools::tags$div(
          id = "auth_signup_error_box",
          class = "auth-alert auth-alert-danger",
          style = "display: none; margin-bottom: 1rem;",
          htmltools::tags$i(class = "fa fa-circle-exclamation", style = "margin-top: 2px;"),
          htmltools::tags$div(id = "auth_signup_error_text", "")
        ),
        
        htmltools::tags$button(
          id = "btn_signup_submit",
          type = "button",
          class = "auth-btn-primary",
          style = "background: #0284c7;",
          onclick = "window.submitSignupForm && window.submitSignupForm()",
          htmltools::tags$i(class = "fa fa-user-check", style = "margin-right: 8px;"),
          htmltools::tags$span("Cadastrar e Criar Conta")
        ),
        
        htmltools::tags$div(
          style = "text-align: center; margin-top: 1rem; font-size: 0.8rem; color: #64748b;",
          "Já possui uma conta? ",
          htmltools::tags$a(
            href = "#",
            style = "color: #004691; font-weight: 600; text-decoration: none;",
            onclick = "$('.auth-tab-btn[data-mode=\"login\"]').click(); return false;",
            "Faça login aqui"
          )
        )
      ),
      
      # Rodapé Informativo
      htmltools::tags$div(
        class = "auth-footer",
        htmltools::tags$p(style = "margin: 0 0 4px 0;", "Apenas usuários autorizados podem visualizar os editais e chamadas de fomento."),
        htmltools::tags$p(style = "margin: 0; color: #64748b;", "SENAI CIMATEC – Núcleo de Economia Industrial (NEI)")
      )
    )
  )
}

# Renderiza a barra de usuário no header (com status de sincronização, badge de permissão e botão sair)
render_header_user_bar <- function(user, is_dev = FALSE, drive_status = "idle", scraping_status = "idle") {
  if (is.null(user)) return(NULL)
  
  # Status do GDrive e Scraping
  status_info <- if (isTRUE(drive_status == "uploading")) {
    list(icon = "sync fa-spin status-syncing", label = "Sincronizando GDrive...", class = "status-syncing")
  } else if (isTRUE(scraping_status == "running")) {
    list(icon = "robot fa-spin status-active", label = "Coleta Ativa", class = "status-active")
  } else {
    list(icon = "check-circle status-success", label = "Base Sincronizada", class = "status-success")
  }
  
  email_str <- as.character(user$email %||% "Usuário")
  
  badge_ui <- if (isTRUE(is_dev)) {
    htmltools::tags$span(
      class = "badge",
      style = "background: #fef3c7; color: #92400e; border: 1px solid #fde68a; font-size: 0.7rem; font-weight: 700; padding: 2px 6px; border-radius: 4px;",
      htmltools::tags$i(class = "fa fa-shield-halved", style = "margin-right: 3px;"),
      "Diretoria"
    )
  } else {
    htmltools::tags$span(
      class = "badge",
      style = "background: #e0f2fe; color: #0369a1; border: 1px solid #bae6fd; font-size: 0.7rem; font-weight: 700; padding: 2px 6px; border-radius: 4px;",
      htmltools::tags$i(class = "fa fa-user-check", style = "margin-right: 3px;"),
      "Leitor"
    )
  }
  
  htmltools::tags$div(
    style = "display: flex; align-items: center; gap: 0.75rem;",
    
    # Widget de Status de Sincronização
    htmltools::tags$button(
      id = "btn_header_status",
      class = sprintf("btn header-status-widget %s", status_info$class),
      onclick = "Shiny.setInputValue('click_header_status', Math.random(), {priority: 'event'})",
      htmltools::tags$i(class = sprintf("fa fa-%s", status_info$icon)),
      htmltools::tags$span(class = "status-label", style = "margin-left: 6px;", status_info$label)
    ),
    
    # Perfil do Usuário Logado
    htmltools::tags$div(
      class = "user-header-profile",
      htmltools::tags$i(class = "fa fa-circle-user", style = "font-size: 1.35rem; color: #004691;"),
      htmltools::tags$div(
        class = "user-header-info",
        htmltools::tags$span(class = "user-header-email", title = email_str, email_str),
        badge_ui
      ),
      htmltools::tags$button(
        id = "btn_header_logout",
        class = "btn-header-logout",
        onclick = "Shiny.setInputValue('btn_header_logout', Math.random(), {priority: 'event'})",
        title = "Sair da conta e encerrar sessão",
        htmltools::tags$i(class = "fa fa-arrow-right-from-bracket"),
        htmltools::tags$span("Sair")
      )
    )
  )
}
