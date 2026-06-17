local_libs <- 'c:/Users/Micro/source/repos/funding_intelligence/R_libs'
.libPaths(c(local_libs, .libPaths()))
library(RSQLite)

conn <- dbConnect(SQLite(), "funding_intelligence.sqlite")
r <- dbGetQuery(conn, "SELECT id_registro, titulo, descricao_resumida, descricao_completa, link_origem, link_detalhe FROM oportunidades WHERE id_registro = 'fapesp_49c1168879b5784e'")
dbDisconnect(conn)

cat("=== RECORD INFO ===\n")
cat("ID: ", r$id_registro[[1]], "\n")
cat("TITULO: ", r$titulo[[1]], "\n")
cat("DESC RESUMIDA: ", r$descricao_resumida[[1]], "\n")
cat("DESC COMPLETA: ", r$descricao_completa[[1]], "\n")
cat("LINK ORIGEM: ", r$link_origem[[1]], "\n")
cat("LINK DETALHE: ", r$link_detalhe[[1]], "\n")
