helper_files <- list.files("R", pattern = "^helpers_.*\\.R$", full.names = TRUE)
for (f in helper_files) {
  source(f, encoding = "UTF-8")
}

db_path <- "funding_intelligence.sqlite"
init_database(db_path)

conn <- get_db_connection(db_path)
neh <- DBI::dbGetQuery(conn, "SELECT id_fonte, nome_fonte, sigla, pais FROM fontes_financiamento WHERE id_fonte = 'neh'")
cat("--- NEH entry in SQLite ---\n")
print(neh)

total_sources <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM fontes_financiamento")$n[[1]]
cat("Total sources in DB:", total_sources, "\n")
DBI::dbDisconnect(conn)
