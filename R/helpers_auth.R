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

# Solicita envio de e-mail de recuperação de senha no Supabase Auth
supabase_request_password_reset <- function(email, redirect_to = NULL) {
  email <- tolower(trimws(as.character(email %||% "")))
  
  if (!nzchar(email)) {
    return(list(
      success = FALSE,
      message = "Por favor, informe seu e-mail institucional para recuperar a senha."
    ))
  }
  
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) {
    return(list(
      success = FALSE,
      message = "Configuração do Supabase ausente. Defina SUPABASE_URL e SUPABASE_ANON_KEY no arquivo .Renviron."
    ))
  }
  
  endpoint <- paste0(cfg$url, "/auth/v1/recover")
  if (!is.null(redirect_to) && nzchar(redirect_to)) {
    endpoint <- paste0(endpoint, "?redirect_to=", utils::URLencode(redirect_to, reserved = TRUE))
  }
  
  body_data <- list(email = email)
  if (!is.null(redirect_to) && nzchar(redirect_to)) {
    body_data$redirect_to <- redirect_to
    body_data$redirectTo <- redirect_to
  }
  
  resp <- tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = cfg$anon_key,
        "Authorization" = paste("Bearer", cfg$anon_key),
        "Content-Type" = "application/json"
      ) |>
      httr2::req_body_json(body_data) |>
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
  
  if (status %in% c(200, 201, 204)) {
    return(list(
      success = TRUE,
      message = "Link de recuperação enviado com sucesso! Verifique sua caixa de entrada (e pasta de spam) para redefinir sua senha."
    ))
  }
  
  raw_msg <- body_json$msg %||% body_json$error_description %||% body_json$message %||% ""
  
  err_msg <- if (grepl("too many requests|rate limit", tolower(raw_msg))) {
    "Muitas tentativas consecutivas de recuperação. Aguarde alguns instantes e tente novamente."
  } else if (grepl("user not found", tolower(raw_msg))) {
    "E-mail não encontrado no sistema. Por favor, verifique o endereço digitado."
  } else if (nzchar(raw_msg)) {
    raw_msg
  } else {
    sprintf("Não foi possível solicitar a recuperação de senha (Código HTTP %s).", status)
  }
  
  list(
    success = FALSE,
    message = err_msg,
    status_code = status
  )
}

# Atualiza a senha do usuário utilizando o access_token de recuperação
supabase_update_password <- function(access_token, new_password) {
  access_token <- as.character(access_token %||% "")
  new_password <- as.character(new_password %||% "")
  
  if (!nzchar(access_token)) {
    return(list(
      success = FALSE,
      message = "Token de recuperação ausente ou expirado. Por favor, solicite um novo link de recuperação."
    ))
  }
  
  if (!nzchar(new_password) || nchar(new_password) < 6) {
    return(list(
      success = FALSE,
      message = "A nova senha deve conter no mínimo 6 caracteres."
    ))
  }
  
  cfg <- supabase_get_config()
  if (!isTRUE(cfg$is_configured)) {
    return(list(
      success = FALSE,
      message = "Configuração do Supabase ausente. Defina SUPABASE_URL e SUPABASE_ANON_KEY no arquivo .Renviron."
    ))
  }
  
  # Se o token não for um JWT clássico (não contiver 2 pontos), tenta trocar via /auth/v1/verify
  is_jwt <- grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", access_token)
  if (!is_jwt) {
    verify_endpoint <- paste0(cfg$url, "/auth/v1/verify")
    verify_body <- list(type = "recovery")
    if (nchar(access_token) == 64 || !grepl("-", access_token)) {
      verify_body$token_hash <- access_token
    } else {
      verify_body$token <- access_token
    }
    
    verify_resp <- tryCatch({
      httr2::request(verify_endpoint) |>
        httr2::req_headers(
          "apikey" = cfg$anon_key,
          "Content-Type" = "application/json"
        ) |>
        httr2::req_body_json(verify_body) |>
        httr2::req_error(is_error = function(resp) FALSE) |>
        httr2::req_timeout(10) |>
        httr2::req_perform()
    }, error = function(e) NULL)
    
    if (!is.null(verify_resp) && httr2::resp_status(verify_resp) %in% c(200, 201)) {
      v_text <- tryCatch(httr2::resp_body_string(verify_resp), error = function(e) "")
      v_json <- tryCatch(jsonlite::fromJSON(v_text, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(v_json$access_token) && nzchar(as.character(v_json$access_token))) {
        access_token <- as.character(v_json$access_token)
      }
    }
  }
  
  endpoint <- paste0(cfg$url, "/auth/v1/user")
  
  resp <- tryCatch({
    httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = cfg$anon_key,
        "Authorization" = paste("Bearer", access_token),
        "Content-Type" = "application/json"
      ) |>
      httr2::req_method("PUT") |>
      httr2::req_body_json(list(password = new_password)) |>
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
  
  if (status %in% c(200, 204)) {
    return(list(
      success = TRUE,
      user = body_json,
      message = "Senha redefinida com sucesso! Você já pode entrar com sua nova senha."
    ))
  }
  
  raw_msg <- body_json$msg %||% body_json$error_description %||% body_json$message %||% ""
  
  err_msg <- if (grepl("weak_password|at least 6 characters", tolower(raw_msg))) {
    "A nova senha deve conter no mínimo 6 caracteres."
  } else if (grepl("same_password|different from the old|should be different|different from", tolower(raw_msg))) {
    "A nova senha deve ser diferente da senha anterior."
  } else if (grepl("expired|invalid_token|jwt", tolower(raw_msg))) {
    "O link de recuperação expirou ou é inválido. Por favor, solicite uma nova recuperação."
  } else if (nzchar(raw_msg)) {
    raw_msg
  } else {
    sprintf("Não foi possível redefinir a senha (Código HTTP %s).", status)
  }
  
  list(
    success = FALSE,
    message = err_msg,
    status_code = status
  )
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
  if (!is.list(session_data)) return(list(success = FALSE, is_invalid = TRUE))
  access_tok <- as.character(session_data$access_token %||% "")
  refresh_tok <- as.character(session_data$refresh_token %||% "")
  cached_user <- session_data$user
  
  # 1. Tenta validar o access_token atual na API GoTrue do Supabase
  user_res <- if (nzchar(access_tok)) {
    supabase_get_user(access_tok)
  } else {
    list(success = FALSE, status_code = 401)
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
  ref_res <- if (nzchar(refresh_tok)) {
    supabase_refresh_session(refresh_tok)
  } else {
    list(success = FALSE, status_code = NULL)
  }
  
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
  
  # 3. Fallback de resiliência: se houve erro de rede ou timeout e o usuário cached é válido
  ref_status <- ref_res$status_code %||% 0
  is_explicit_rejection <- ref_status %in% c(400, 401, 403)
  
  if (!is_explicit_rejection && is.list(cached_user) && !is.null(cached_user$email) && nzchar(as.character(cached_user$email))) {
    user <- cached_user
    is_dev <- supabase_is_dev_or_diretoria(user, conn = conn)
    user$cargo <- user$cargo %||% (if (isTRUE(is_dev)) "diretoria" else "leitor")
    return(list(
      success = TRUE,
      user = user,
      access_token = access_tok,
      refresh_token = refresh_tok,
      is_dev = is_dev,
      updated = FALSE,
      offline_fallback = TRUE
    ))
  }
  
  list(success = FALSE, is_invalid = is_explicit_rejection)
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
      
      # Proteção Instantânea contra Flash do Login: Se houver indício de recuperação na URL ou sessionStorage,
      # injeta estilo imediato ocultando o formulário de login e forçando a exibição da tela de redefinição.
      htmltools::tags$script(htmltools::HTML("
        (function() {
          try {
            var h = window.location.hash || '';
            var s = window.location.search || '';
            var ref = document.referrer || '';
            var st = '';
            try { st = sessionStorage.getItem('quiin_pending_recovery_token') || ''; } catch(e) {}
            var isRec = (h.indexOf('type=recovery') !== -1) || (h.indexOf('access_token=') !== -1) ||
                        (s.indexOf('type=recovery') !== -1) || (s.indexOf('code=') !== -1) ||
                        (ref.indexOf('type=recovery') !== -1) || (st.length > 5);
            if (isRec) {
              var sNode = document.createElement('style');
              sNode.id = 'quiin_recovery_instant_css';
              sNode.textContent = '#auth_form_login, .auth-tabs-nav, #auth_form_signup, #auth_form_forgot, #auth_restoring_state { display: none !important; } #auth_form_reset_password { display: block !important; }';
              document.head.appendChild(sNode);
            }
          } catch(e) {}
        })();
      ")),

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
              autocomplete = "username",
              onkeydown = "if (event.key === 'Enter' || event.keyCode === 13) { event.preventDefault(); window.submitLoginForm && window.submitLoginForm(); }"
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
              style = "padding-right: 2.5rem;",
              onkeydown = "if (event.key === 'Enter' || event.keyCode === 13) { event.preventDefault(); window.submitLoginForm && window.submitLoginForm(); }"
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
        
        # Link 'Esqueci a senha'
        htmltools::tags$div(
          style = "display: flex; justify-content: flex-end; margin-top: -0.4rem; margin-bottom: 1.15rem;",
          htmltools::tags$a(
            id = "link_forgot_password",
            href = "#",
            class = "auth-link-forgot",
            onclick = "window.switchAuthTab && window.switchAuthTab('forgot'); return false;",
            htmltools::tags$i(class = "fa fa-key", style = "margin-right: 4px; font-size: 0.75rem;"),
            "Esqueci a senha"
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
        
        # Alerta de sucesso dinâmico instantâneo (ex.: após redefinição de senha)
        htmltools::tags$div(
          id = "auth_login_success_box",
          class = "auth-alert auth-alert-success",
          style = "display: none; margin-bottom: 1rem;",
          htmltools::tags$i(class = "fa fa-circle-check", style = "margin-top: 2px;"),
          htmltools::tags$div(id = "auth_login_success_text", "")
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
      
      # ─── Formulário 3: Esqueci a Senha / Solicitação de Recuperação ────────
      htmltools::tags$div(
        id = "auth_form_forgot",
        style = "display: none;",
        
        htmltools::tags$div(
          style = "text-align: center; margin-bottom: 1.35rem;",
          htmltools::tags$div(
            style = "width: 52px; height: 52px; border-radius: 50%; background: #eff6ff; border: 1px solid #bfdbfe; color: #004691; display: inline-flex; align-items: center; justify-content: center; font-size: 1.35rem; margin-bottom: 0.75rem; box-shadow: 0 2px 8px rgba(0, 70, 145, 0.1);",
            htmltools::tags$i(class = "fa fa-key")
          ),
          htmltools::tags$h3(style = "font-size: 1.25rem; font-weight: 800; color: #0f172a; margin: 0 0 0.35rem 0;", "Recuperar Senha"),
          htmltools::tags$p(style = "font-size: 0.85rem; color: #64748b; margin: 0; line-height: 1.45;", "Digite seu e-mail institucional cadastrado. Enviaremos um link seguro para você redefinir sua senha de acesso.")
        ),
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "E-mail institucional:"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-envelope auth-input-icon"),
            shiny::tags$input(
              id = "recovery_email",
              type = "email",
              class = "auth-input",
              placeholder = "seu.email@fieb.org.br",
              autocomplete = "email"
            )
          )
        ),
        
        # Alerta de erro dinâmico de recuperação
        htmltools::tags$div(
          id = "auth_recovery_error_box",
          class = "auth-alert auth-alert-danger",
          style = "display: none; margin-bottom: 1rem;",
          htmltools::tags$i(class = "fa fa-circle-exclamation", style = "margin-top: 2px;"),
          htmltools::tags$div(id = "auth_recovery_error_text", "")
        ),
        
        # Alerta de sucesso dinâmico de recuperação
        htmltools::tags$div(
          id = "auth_recovery_success_box",
          class = "auth-alert auth-alert-success",
          style = "display: none; margin-bottom: 1rem;",
          htmltools::tags$i(class = "fa fa-circle-check", style = "margin-top: 2px;"),
          htmltools::tags$div(id = "auth_recovery_success_text", "")
        ),
        
        htmltools::tags$button(
          id = "btn_recovery_submit",
          type = "button",
          class = "auth-btn-primary",
          onclick = "window.submitRecoveryForm && window.submitRecoveryForm()",
          htmltools::tags$i(class = "fa fa-paper-plane", style = "margin-right: 8px;"),
          htmltools::tags$span("Enviar Link de Recuperação")
        ),
        
        htmltools::tags$div(
          style = "text-align: center; margin-top: 1.25rem; font-size: 0.825rem;",
          htmltools::tags$a(
            href = "#",
            class = "auth-link-back",
            onclick = "window.switchAuthTab && window.switchAuthTab('login'); return false;",
            htmltools::tags$i(class = "fa fa-arrow-left"),
            htmltools::tags$span("Voltar para o Login")
          )
        )
      ),
      
      # ─── Formulário 4: Redefinir Nova Senha (via link do e-mail) ────────────
      htmltools::tags$div(
        id = "auth_form_reset_password",
        style = "display: none;",
        
        htmltools::tags$div(
          style = "text-align: center; margin-bottom: 1.35rem;",
          htmltools::tags$div(
            style = "width: 52px; height: 52px; border-radius: 50%; background: #f0fdf4; border: 1px solid #bbf7d0; color: #16a34a; display: inline-flex; align-items: center; justify-content: center; font-size: 1.35rem; margin-bottom: 0.75rem; box-shadow: 0 2px 8px rgba(22, 163, 74, 0.1);",
            htmltools::tags$i(class = "fa fa-lock-open")
          ),
          htmltools::tags$h3(style = "font-size: 1.25rem; font-weight: 800; color: #0f172a; margin: 0 0 0.35rem 0;", "Criar Nova Senha"),
          htmltools::tags$p(style = "font-size: 0.85rem; color: #64748b; margin: 0; line-height: 1.45;", "Defina uma nova senha segura para acessar a plataforma.")
        ),
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "Nova senha (mínimo 6 caracteres):"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-lock auth-input-icon"),
            shiny::tags$input(
              id = "reset_password_new",
              type = "password",
              class = "auth-input",
              placeholder = "••••••••",
              autocomplete = "new-password",
              style = "padding-right: 2.5rem;"
            ),
            htmltools::tags$button(
              type = "button",
              class = "btn-toggle-pwd",
              `data-target` = "reset_password_new",
              style = "position: absolute; right: 0.75rem; background: none; border: none; color: #94a3b8; cursor: pointer; padding: 4px;",
              title = "Mostrar/ocultar senha",
              htmltools::tags$i(class = "fa fa-eye")
            )
          )
        ),
        
        htmltools::tags$div(
          class = "auth-form-group",
          htmltools::tags$label(class = "auth-form-label", "Confirmar nova senha:"),
          htmltools::tags$div(
            class = "auth-input-wrapper",
            htmltools::tags$i(class = "fa fa-check-double auth-input-icon"),
            shiny::tags$input(
              id = "reset_password_confirm",
              type = "password",
              class = "auth-input",
              placeholder = "••••••••",
              autocomplete = "new-password",
              style = "padding-right: 2.5rem;"
            ),
            htmltools::tags$button(
              type = "button",
              class = "btn-toggle-pwd",
              `data-target` = "reset_password_confirm",
              style = "position: absolute; right: 0.75rem; background: none; border: none; color: #94a3b8; cursor: pointer; padding: 4px;",
              title = "Mostrar/ocultar senha",
              htmltools::tags$i(class = "fa fa-eye")
            )
          )
        ),
        
        # Alerta de erro dinâmico de redefinição
        htmltools::tags$div(
          id = "auth_reset_error_box",
          class = "auth-alert auth-alert-danger",
          style = "display: none; margin-bottom: 1rem;",
          htmltools::tags$i(class = "fa fa-circle-exclamation", style = "margin-top: 2px;"),
          htmltools::tags$div(id = "auth_reset_error_text", "")
        ),
        
        htmltools::tags$button(
          id = "btn_reset_password_submit",
          type = "button",
          class = "auth-btn-primary",
          style = "background: linear-gradient(135deg, #16a34a 0%, #15803d 100%);",
          onclick = "window.submitResetPasswordForm && window.submitResetPasswordForm()",
          htmltools::tags$i(class = "fa fa-check", style = "margin-right: 8px;"),
          htmltools::tags$span("Atualizar Senha")
        ),
        
        htmltools::tags$div(
          style = "text-align: center; margin-top: 1.25rem; font-size: 0.825rem;",
          htmltools::tags$a(
            href = "#",
            class = "auth-link-back",
            onclick = "window.switchAuthTab && window.switchAuthTab('login'); return false;",
            htmltools::tags$i(class = "fa fa-arrow-left"),
            htmltools::tags$span("Voltar para o Login")
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
        id = "btn_header_change_password",
        class = "btn-header-change-pwd",
        style = "background: none; border: 1px solid #cbd5e1; border-radius: 4px; padding: 4px 8px; font-size: 0.75rem; color: #475569; cursor: pointer; display: inline-flex; align-items: center; gap: 4px; transition: all 0.2s;",
        onclick = "if (!this.disabled) { var b = this; b.disabled = true; $(b).find('i').removeClass('fa-key').addClass('fa-spinner fa-spin'); Shiny.setInputValue('btn_header_change_password', Math.random(), {priority: 'event'}); setTimeout(function(){ b.disabled = false; $(b).find('i').removeClass('fa-spinner fa-spin').addClass('fa-key'); }, 1500); }",
        title = "Alterar minha senha de acesso",
        htmltools::tags$i(class = "fa fa-key"),
        htmltools::tags$span("Alterar Senha")
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

# Modal dedicado para Criação e Redefinição de Nova Senha (disparado via link ou botão)
show_reset_password_modal <- function(session, access_token = "", error_msg = NULL, success_msg = NULL) {
  shiny::showModal(
    shiny::modalDialog(
      title = htmltools::tags$div(
        style = "display: flex; align-items: center; justify-content: space-between; width: 100%; gap: 12px;",
        htmltools::tags$div(
          style = "display: flex; align-items: center; gap: 12px;",
          htmltools::tags$div(
            style = "background: #eff6ff; color: #004691; width: 40px; height: 40px; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 1.25rem;",
            htmltools::tags$i(class = "fa fa-key")
          ),
          htmltools::tags$div(
            htmltools::tags$h4(style = "margin: 0; color: #004691; font-weight: 700; font-size: 1.2rem;", "🔑 Criar Nova Senha"),
            htmltools::tags$span(style = "font-size: 0.8rem; color: #64748b;", "Radar da Inovação — SENAI CIMATEC")
          )
        ),
        htmltools::tags$div(
          style = "display: inline-flex; align-items: center; gap: 6px; font-size: 0.75rem; color: #94a3b8; background: #f8fafc; border: 1px dashed #cbd5e1; padding: 4px 10px; border-radius: 20px; user-select: none;",
          title = "Clique e arraste este cabeçalho para reposicionar o modal onde preferir",
          htmltools::tags$i(class = "fa fa-up-down-left-right"),
          htmltools::tags$span("Arrastável")
        )
      ),
      size = "l",
      easyClose = FALSE,
      footer = htmltools::tags$div(
        style = "display: flex; justify-content: flex-end; gap: 10px; width: 100%;",
        shiny::actionButton(
          "btn_modal_cancel_recovery",
          label = "Cancelar",
          class = "btn btn-outline-secondary",
          style = "font-size: 0.85rem;"
        ),
        shiny::actionButton(
          "btn_modal_submit_new_password",
          label = "Salvar Nova Senha",
          class = "btn btn-primary",
          style = "background: linear-gradient(135deg, #16a34a 0%, #15803d 100%); border: none; font-weight: 600; padding: 8px 18px;",
          icon = shiny::icon("check")
        )
      ),
      htmltools::tags$div(
        style = "padding: 8px 0;",
        htmltools::tags$p(
          style = "color: #334155; font-size: 0.95rem; margin-bottom: 16px; line-height: 1.5;",
          "Defina uma nova senha para sua conta institucional no Radar da Inovação. A nova senha deve conter no mínimo 6 caracteres."
        ),
        shiny::uiOutput("modal_reset_password_error_ui"),
        htmltools::tags$div(
          class = "row g-3",
          style = "margin-bottom: 1.25rem;",
          htmltools::tags$div(
            class = "col-12 col-md-6",
            htmltools::tags$label(class = "form-label fw-bold text-secondary", style = "font-size: 0.85rem;", "Nova Senha (mínimo 6 caracteres):"),
            htmltools::tags$div(
              class = "form-group shiny-input-container",
              style = "position: relative; width: 100%; margin-bottom: 0;",
              shiny::tags$input(
                id = "modal_reset_password_new",
                type = "password",
                class = "shiny-input-password form-control",
                placeholder = "••••••••",
                autocomplete = "new-password",
                `data-lpignore` = "true",
                `data-form-type` = "other",
                value = "",
                `data-update-on` = "change",
                style = "padding-right: 2.75rem;",
                onkeydown = "if (event.key === 'Enter' || event.keyCode === 13) { event.preventDefault(); $('#btn_modal_submit_new_password').click(); }"
              ),
              htmltools::tags$button(
                type = "button",
                class = "btn-toggle-pwd",
                `data-target` = "modal_reset_password_new",
                style = "position: absolute; right: 0.75rem; top: 7px; background: none; border: none; color: #94a3b8; cursor: pointer; padding: 4px; z-index: 10;",
                title = "Mostrar/ocultar senha",
                htmltools::tags$i(class = "fa fa-eye")
              )
            )
          ),
          htmltools::tags$div(
            class = "col-12 col-md-6",
            htmltools::tags$label(class = "form-label fw-bold text-secondary", style = "font-size: 0.85rem;", "Confirmar Nova Senha:"),
            htmltools::tags$div(
              class = "form-group shiny-input-container",
              style = "position: relative; width: 100%; margin-bottom: 0;",
              shiny::tags$input(
                id = "modal_reset_password_confirm",
                type = "password",
                class = "shiny-input-password form-control",
                placeholder = "••••••••",
                autocomplete = "new-password",
                `data-lpignore` = "true",
                `data-form-type` = "other",
                value = "",
                `data-update-on` = "change",
                style = "padding-right: 2.75rem;",
                onkeydown = "if (event.key === 'Enter' || event.keyCode === 13) { event.preventDefault(); $('#btn_modal_submit_new_password').click(); }"
              ),
              htmltools::tags$button(
                type = "button",
                class = "btn-toggle-pwd",
                `data-target` = "modal_reset_password_confirm",
                style = "position: absolute; right: 0.75rem; top: 7px; background: none; border: none; color: #94a3b8; cursor: pointer; padding: 4px; z-index: 10;",
                title = "Mostrar/ocultar senha",
                htmltools::tags$i(class = "fa fa-eye")
              )
            )
          )
        ),
        htmltools::tags$div(
          style = "font-size: 0.8rem; color: #64748b; margin-top: 5px;",
          htmltools::tags$i(class = "fa fa-info-circle", style = "margin-right: 4px;"),
          "Após atualizar, sua nova senha passará a valer imediatamente para os próximos logins."
        )
      )
    )
  )
}
