# Test source_dispatch for the new sources
helper_files <- list.files("R", pattern = "^helpers_.*\\.R$", full.names = TRUE)
for (f in helper_files) source(f, encoding = "UTF-8")

conn <- get_db_connection("funding_intelligence.sqlite")
new_sources_df <- DBI::dbGetQuery(conn, "SELECT * FROM fontes_financiamento WHERE id_fonte IN ('bndes', 'esa_solutions', 'nasa_sbir', 'facepe', 'funcap', 'transferegov', 'bnb_hubine', 'sebrae', 'softex')")
DBI::dbDisconnect(conn)

cat(sprintf("Testing %d new sources via source_dispatch...\n", nrow(new_sources_df)))

for (i in seq_len(nrow(new_sources_df))) {
  row <- new_sources_df[i, ]
  cat(sprintf("\n--- Testing: %s (%s) ---\n", row$id_fonte, row$sigla))
  res <- tryCatch({
    source_dispatch(row, max_pages = 1, max_records = 3)
  }, error = function(e) list(error = conditionMessage(e), records = NULL))
  
  if (!is.null(res$error)) {
    cat("Error:", res$error, "\n")
  } else if (!is.null(res$records) && nrow(res$records) > 0) {
    cat(sprintf("SUCCESS! %d records collected:\n", nrow(res$records)))
    for (j in seq_len(min(2, nrow(res$records)))) {
      cat(sprintf("   [%d] %s\n       URL: %s\n", j, res$records$titulo[j], res$records$link_detalhe[j]))
    }
  } else {
    cat("Finished with 0 records.\n")
  }
}
