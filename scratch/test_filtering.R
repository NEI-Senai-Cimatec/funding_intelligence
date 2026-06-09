# Test script for static heuristics and database cleanup
# Run this from the root of the project

# Set up library paths
local_libs <- file.path(getwd(), "R_libs")
if (dir.exists(local_libs)) .libPaths(c(local_libs, .libPaths()))

library(DBI)
library(RSQLite)
library(dplyr)
library(tibble)

# Source dependencies
source("R/helpers_utils.R")
source("R/helpers_text.R")
source("R/helpers_db.R")
source("R/helpers_collect.R")
source("R/helpers_ai.R")

message("=== TEST 1: Static Heuristics ===")

# Test cases for static heuristics
test_cases <- list(
  # Invalid cases (should return FALSE)
  list(title = "Manual do Cartão BB Pesquisa CAPES", url = "https://capes.gov.br/manual", expected = FALSE),
  list(title = "Carta de Serviço ao Cidadão do CNPq", url = "https://cnpq.gov.br/carta", expected = FALSE),
  list(title = "Instruções para envio de Relatórios de Atividades de Bolsas", url = "https://faperj.br/relatorios", expected = FALSE),
  list(title = "Tv Fapesc", url = "https://fapesc.sc.gov.br/tv", expected = FALSE),
  list(title = "Sobre a FINEP", url = "https://finep.gov.br/sobre", expected = FALSE),
  list(title = "Chamadas Públicas Archive - Embrapii", url = "https://embrapii.org.br/archive", expected = FALSE),
  list(title = "Strategic Plan 2025-2027", url = "https://ec.europa.eu/horizon-europe/plan", expected = FALSE),
  
  # Valid cases (should return TRUE)
  list(title = "Edital de Apoio a Projetos de IA", url = "https://fapesc.sc.gov.br/editais/abertos/1", expected = TRUE),
  list(title = "Chamada Pública CNPq nº 12/2026", url = "https://gov.br/cnpq/chamadas/12-2026", expected = TRUE),
  list(title = "Horizon Europe Research Grants for Clean Energy", url = "https://ec.europa.eu/opportunities/calls/clean-energy", expected = TRUE)
)

failed_heuristics <- 0
for (tc in test_cases) {
  res <- is_funding_opportunity_heuristics(title = tc$title, url = tc$url)
  if (res == tc$expected) {
    message(sprintf(" PASS: '%s' -> %s", tc$title, res))
  } else {
    message(sprintf(" FAIL: '%s' -> Got %s, expected %s", tc$title, res, tc$expected))
    failed_heuristics <- failed_heuristics + 1
  }
}

message("\n=== TEST 2: Database Cleanup ===")

# Create a temporary in-memory database to test cleanup
test_conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
on.exit(DBI::dbDisconnect(test_conn), add = TRUE)

# Create table schema
create_tables(test_conn)

# Insert mock opportunities (some valid, some invalid)
mock_ops <- tibble::tribble(
  ~id_registro, ~titulo, ~descricao_resumida, ~link_origem, ~link_detalhe, ~texto_bruto,
  "op_valid_1", "Edital de Pesquisa Quântica 2026", "Apoio a projetos em computação quântica", "https://cnpq.br/chamada", "https://cnpq.br/chamada/detalhes", "Texto completo do edital...",
  "op_invalid_1", "Manual do Cartão BB Pesquisa CAPES", "Manual do usuário", "https://capes.br/manual", "https://capes.br/manual/pdf", "Como usar o cartão BB pesquisa...",
  "op_valid_2", "Chamada Pública FAPESC nº 05/2026", "Fomento para startups", "https://fapesc.br/editais", "https://fapesc.br/editais/05", "Chamada aberta para fomento de startups...",
  "op_invalid_2", "Instruções para envio de Relatórios de Atividades de Bolsas", "Tutorial administrative", "https://faperj.br/procedimento", "https://faperj.br/procedimento/enviar", "Como preencher o relatorio..."
)

mock_ops$hash_deduplicacao <- vapply(seq_len(nrow(mock_ops)), function(i) {
  digest::digest(paste0(mock_ops$titulo[[i]], mock_ops$link_origem[[i]]), algo = "xxhash64")
}, character(1))
mock_ops$campos_inferidos_ia <- ""

DBI::dbWriteTable(test_conn, "oportunidades", mock_ops, append = TRUE)

# Verify count before cleanup
before_count <- DBI::dbGetQuery(test_conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]]
message("Count before cleanup: ", before_count)

# Run cleanup
cleanup_database_opportunities(test_conn)

# Verify count and items after cleanup
after_ops <- DBI::dbGetQuery(test_conn, "SELECT id_registro, titulo FROM oportunidades")
message("Count after cleanup: ", nrow(after_ops))
message("Remaining records:")
print(after_ops)

failed_db_cleanup <- 0
if (nrow(after_ops) != 2) {
  message(" FAIL: Database cleanup did not keep exactly 2 valid opportunities.")
  failed_db_cleanup <- 1
} else if (!all(after_ops$id_registro %in% c("op_valid_1", "op_valid_2"))) {
  message(" FAIL: Database cleanup kept incorrect opportunities.")
  failed_db_cleanup <- 1
} else {
  message(" PASS: Database cleanup successfully removed non-funding opportunities.")
}

message("\n=== TEST 3: AI Classification Prompt ===")
if (ai_available()) {
  message("AI is configured. Testing AI classification with a mock news article...")
  mock_news_text <- "FINEP comemora 20 anos de fomento à inovação no Brasil com solenidade na sede e lançamento de livro comemorativo. O evento contou com a presença de diversas autoridades e ex-diretores. A solenidade marcou a entrega de medalhas de honra ao mérito. O livro está disponível em PDF no portal da Finep."
  
  res_ai <- skill_extract_metadata(mock_news_text, current_info = list(titulo_limpo = "Finep 20 anos"))
  
  message("AI extraction output:")
  print(res_ai)
  
  if (!is.null(res_ai$e_edital_fomento) && isFALSE(res_ai$e_edital_fomento)) {
    message(" PASS: AI correctly classified news/commemorative page as e_edital_fomento = FALSE")
  } else {
    message(" WARNING: AI did not classify news/commemorative page as FALSE (e_edital_fomento was ", res_ai$e_edital_fomento, ")")
  }
} else {
  message("AI is not available. Skipping AI classification test.")
}

# Final summary
message("\n=== TEST SUMMARY ===")
if (failed_heuristics == 0 && failed_db_cleanup == 0) {
  message("ALL TESTS PASSED SUCCESSFULLY!")
} else {
  message(sprintf("SOME TESTS FAILED: %d heuristics errors, %d db cleanup errors", failed_heuristics, failed_db_cleanup))
}
