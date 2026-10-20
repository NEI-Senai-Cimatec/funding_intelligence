# Sincronização completa entre Supabase REST API e SQLite local
local_libs <- file.path(getwd(), "R_libs")
if (dir.exists(local_libs)) .libPaths(c(local_libs, .libPaths()))
suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(DBI)
  library(RSQLite)
  library(dplyr)
})

readRenviron(".Renviron")

url <- Sys.getenv("SUPABASE_URL")
key <- Sys.getenv("SUPABASE_ANON_KEY")

if (!nzchar(url) || !nzchar(key)) {
  stop("SUPABASE_URL ou SUPABASE_ANON_KEY não encontradas no .Renviron!")
}

clean_url <- sub("/rest/v1/?$", "", trimws(url), ignore.case = TRUE)
clean_url <- sub("/+$", "", clean_url)

tables <- c(
  "fontes_financiamento",
  "oportunidades",
  "colaboradores",
  "perfil_usuario",
  "pesquisadores_vencedores",
  "projetos_aprovados",
  "buscas_salvas",
  "editais_rastreados",
  "historico_buscas",
  "logs_coleta",
  "metrics_coleta"
)

con <- DBI::dbConnect(RSQLite::SQLite(), "funding_intelligence.sqlite")

cat("=== Sincronizando tabelas do Supabase para funding_intelligence.sqlite ===\n")

for (tbl in tables) {
  tryCatch({
    endpoint <- paste0(clean_url, "/rest/v1/", tbl, "?select=*")
    r <- httr2::request(endpoint) |>
      httr2::req_headers(
        "apikey" = key,
        "Authorization" = paste("Bearer", key)
      ) |>
      httr2::req_error(is_error = function(e) FALSE) |>
      httr2::req_perform()
    
    st <- httr2::resp_status(r)
    if (st == 200) {
      body_text <- httr2::resp_body_string(r)
      rows <- jsonlite::fromJSON(body_text, simplifyVector = FALSE)
      if (length(rows) > 0) {
        clean_rows <- lapply(rows, function(row) {
          lapply(row, function(val) {
            if (is.null(val)) return(NA)
            if (is.list(val) || length(val) > 1) return(as.character(jsonlite::toJSON(val, auto_unbox = TRUE)))
            val
          })
        })
        df <- dplyr::bind_rows(clean_rows)
        DBI::dbWriteTable(con, tbl, df, overwrite = TRUE)
        cat(sprintf("✓ %-26s: %4d registros sincronizados.\n", tbl, nrow(df)))
      } else {
        cat(sprintf("- %-26s:    0 registros no Supabase.\n", tbl))
      }
    } else {
      cat(sprintf("! %-26s: status HTTP %d.\n", tbl, st))
    }
  }, error = function(e) {
    cat(sprintf("x %-26s: erro: %s\n", tbl, e$message))
  })
}

DBI::dbDisconnect(con)
cat("=== Sincronização concluída com sucesso! ===\n")
