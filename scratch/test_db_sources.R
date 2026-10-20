library(DBI)
library(RSQLite)

conn <- DBI::dbConnect(RSQLite::SQLite(), "funding_intelligence.sqlite")
on.exit(DBI::dbDisconnect(conn))

sources <- DBI::dbGetQuery(conn, "SELECT id_fonte, nome_fonte, url_oportunidades FROM fontes_financiamento WHERE id_fonte IN ('fapesb', 'embrapii')")
print(sources)
