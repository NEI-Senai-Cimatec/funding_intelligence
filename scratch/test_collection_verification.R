source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_text.R")
source("R/helpers_ai.R")
source("R/helpers_collect.R")

db_path <- "funding_intelligence.sqlite"
conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(conn))

message("--- Synchronizing Sources in Database ---")
# Synchronize sources table with new source_catalog
seed_sources(conn)

message("--- Verifying Sources in DB ---")
sources <- DBI::dbReadTable(conn, "fontes_financiamento")
tested_sources <- subset(sources, id_fonte %in% c("fapesb", "embrapii", "min_saude"))
print(tested_sources[, c("id_fonte", "nome_fonte", "url_oportunidades")])

# Test single source collection for FAPESB, EMBRAPII, MS (without AI first)
test_collect <- function(sid) {
  message(sprintf("\n--- Testing Collection for: %s ---", sid))
  src_row <- subset(sources, id_fonte == sid)
  
  # Run source collection for 1 page and max 1 record
  res <- tryCatch({
    source_dispatch(src_row, max_pages = 1, max_records = 1, use_ai = FALSE, log_path = NULL)
  }, error = function(e) {
    message(sprintf("Error collecting %s: %s", sid, e$message))
    NULL
  })
  
  if (!is.null(res)) {
    message(sprintf("Success! Pages visited: %d | Records found: %d", res$pages_visited, nrow(res$records)))
    if (nrow(res$records) > 0) {
      print(head(res$records[, c("titulo", "link_origem")], 1))
    }
  }
}

test_collect("fapesb")
test_collect("embrapii")
test_collect("min_saude")
