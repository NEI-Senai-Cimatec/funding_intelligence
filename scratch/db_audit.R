library(RSQLite)
conn <- dbConnect(SQLite(), "funding_intelligence.sqlite")
df <- dbGetQuery(conn, "SELECT * FROM oportunidades")

cat("\n=================== DATABASE AUDIT ===================\n")
cat(sprintf("Total de registros na tabela oportunidades: %d\n", nrow(df)))

cat("\n--- Contagem de NAs, Empties ou 'null' por campo ---\n")
na_counts <- colSums(is.na(df) | df == "" | df == "null" | df == "NA")
for(col in names(na_counts)) {
  if (na_counts[col] > 0) {
    cat(sprintf("  %s: %d (%.1f%%)\n", col, na_counts[col], 100 * na_counts[col] / nrow(df)))
  }
}

cat("\n--- Tabela de Distribuição de Moedas ---\n")
print(table(df$moeda, useNA = "always"))

cat("\n--- Registros com Valor Financiado mas sem Moeda ou com Valor menor ou igual a 0 ---\n")
bad_values <- df[!is.na(df$valor_financiado) & (is.na(df$moeda) | df$moeda == "" | df$valor_financiado <= 0), c("id_registro", "titulo", "valor_financiado", "moeda")]
if (nrow(bad_values) > 0) {
  print(bad_values)
} else {
  cat("  Nenhum registro encontrado com inconsistência monetária.\n")
}

cat("\n--- Valores de data_limite com formato inválido (diferente de AAAA-MM-DD) ---\n")
idx_bad_date <- !grepl("^\\d{4}-\\d{2}-\\d{2}$", df$data_limite) & !is.na(df$data_limite) & df$data_limite != "" & df$data_limite != "null"
bad_dates <- df[idx_bad_date, c("id_registro", "titulo", "data_limite")]
if (nrow(bad_dates) > 0) {
  print(bad_dates)
} else {
  cat("  Nenhum registro encontrado com formato de data_limite inválido.\n")
}

cat("\n--- Valores de data_publicacao com formato inválido (diferente de AAAA-MM-DD) ---\n")
idx_bad_pub <- !grepl("^\\d{4}-\\d{2}-\\d{2}$", df$data_publicacao) & !is.na(df$data_publicacao) & df$data_publicacao != "" & df$data_publicacao != "null"
bad_pub <- df[idx_bad_pub, c("id_registro", "titulo", "data_publicacao")]
if (nrow(bad_pub) > 0) {
  print(bad_pub)
} else {
  cat("  Nenhum registro encontrado com formato de data_publicacao inválido.\n")
}

cat("\n--- Campos de Texto Truncados (ex: resumo ou titulo terminando em reticências ou cortados) ---\n")
truncated <- df[grepl("\\.\\.\\.$", df$titulo) | grepl("\\.\\.\\.$", df$descricao_resumida) | grepl("\\.\\.\\.$", df$descricao_completa), c("id_registro", "titulo")]
if (nrow(truncated) > 0) {
  print(truncated)
} else {
  cat("  Nenhum campo truncado com reticências (...) detectado.\n")
}

dbDisconnect(conn)
