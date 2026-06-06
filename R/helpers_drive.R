# Helper para sincronização do SQLite com o Google Drive
library(googledrive)

# Desativa a autenticação interativa e o caching de tokens para execução não interativa no container
options(gargle_oauth_cache = FALSE, gargle_oauth_email = NA)

drive_auth_service <- function() {
  sa_json <- Sys.getenv("GDRIVE_SERVICE_ACCOUNT_JSON")
  sa_content <- Sys.getenv("GDRIVE_SERVICE_ACCOUNT_CONTENT")
  
  if (nzchar(sa_content)) {
    # Grava o conteúdo JSON em um arquivo temporário para que o googledrive possa ler
    temp_json <- tempfile(fileext = ".json")
    writeLines(sa_content, temp_json)
    googledrive::drive_auth(path = temp_json)
    return(TRUE)
  } else if (nzchar(sa_json) && file.exists(sa_json)) {
    googledrive::drive_auth(path = sa_json)
    return(TRUE)
  }
  
  message("[GDrive] Configurações de autenticação de conta de serviço (GDRIVE_SERVICE_ACCOUNT_JSON / GDRIVE_SERVICE_ACCOUNT_CONTENT) ausentes.")
  return(FALSE)
}

drive_download_db <- function(db_path = "funding_intelligence.sqlite") {
  file_id <- Sys.getenv("GDRIVE_FILE_ID")
  if (!nzchar(file_id)) {
    message("[GDrive] GDRIVE_FILE_ID não configurado. Sincronização ignorada (usará banco local).")
    return(FALSE)
  }
  
  authed <- tryCatch(drive_auth_service(), error = function(e) {
    message(sprintf("[GDrive] Falha na autenticação: %s", e$message))
    FALSE
  })
  if (!authed) {
    message("[GDrive] Autenticação ausente ou incorreta. Usando banco local.")
    return(FALSE)
  }
  
  message("[GDrive] Baixando base de dados atualizada do Google Drive...")
  res <- tryCatch({
    googledrive::drive_download(
      file = googledrive::as_id(file_id),
      path = db_path,
      overwrite = TRUE
    )
    message("[GDrive] Base de dados baixada com sucesso do Google Drive!")
    TRUE
  }, error = function(e) {
    message(sprintf("[GDrive] Erro ao baixar base do Google Drive: %s. Utilizando base local atual.", e$message))
    FALSE
  })
  
  return(res)
}

drive_upload_db <- function(db_path = "funding_intelligence.sqlite") {
  file_id <- Sys.getenv("GDRIVE_FILE_ID")
  if (!nzchar(file_id)) {
    message("[GDrive] GDRIVE_FILE_ID não configurado. Upload ignorado.")
    return(FALSE)
  }
  
  if (!file.exists(db_path)) {
    message("[GDrive] Arquivo local do banco de dados não encontrado para upload.")
    return(FALSE)
  }
  
  authed <- tryCatch(drive_auth_service(), error = function(e) {
    message(sprintf("[GDrive] Falha na autenticação: %s", e$message))
    FALSE
  })
  if (!authed) {
    message("[GDrive] Autenticação ausente ou incorreta. Upload ignorado.")
    return(FALSE)
  }
  
  message("[GDrive] Enviando/atualizando base de dados no Google Drive...")
  res <- tryCatch({
    googledrive::drive_update(
      file = googledrive::as_id(file_id),
      media = db_path
    )
    message("[GDrive] Base de dados sincronizada com sucesso no Google Drive!")
    TRUE
  }, error = function(e) {
    message(sprintf("[GDrive] Erro ao sincronizar base no Google Drive: %s", e$message))
    FALSE
  })
  
  return(res)
}
