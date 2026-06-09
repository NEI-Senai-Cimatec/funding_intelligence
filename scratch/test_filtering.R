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
  
  # New invalid cases for rectifications and Finep pages (should return FALSE)
  list(title = "Edital_Genesis_-_Caparao_-_1_Alteracao%20-%20Assinado.pdf", url = "https://fapes.es.gov.br/alteracao.pdf", expected = FALSE),
  list(title = "Financiamento via crédito para inovação - Finep", url = "https://finep.gov.br/financiamento-via-credito", expected = FALSE),
  list(title = "Oportunidades - Finep", url = "https://finep.gov.br/acesso-a-informacao/oportunidades", expected = FALSE),
  list(title = "Retificação nº 01/2026 da Chamada 12/2026", url = "https://cnpq.br/retificacao", expected = FALSE),
  list(title = "Errata do Edital 05/2026", url = "https://fapesc.sc.gov.br/errata", expected = FALSE),
  list(title = "Resultado Final da Chamada 01/2025", url = "https://finep.gov.br/resultado", expected = FALSE),
  
  # Valid cases (should return TRUE)
  list(title = "Edital de Apoio a Projetos de IA", url = "https://fapesc.sc.gov.br/editais/abertos/1", expected = TRUE),
  list(title = "Chamada Pública CNPq nº 12/2026", url = "https://gov.br/cnpq/chamadas/12-2026", expected = TRUE),
  list(title = "Horizon Europe Research Grants for Clean Energy", url = "https://ec.europa.eu/opportunities/calls/clean-energy", expected = TRUE),
  
  # Climate change exception check (should return TRUE)
  list(title = "Chamada para Projetos em Alterações Climáticas na Indústria", url = "https://finep.gov.br/chamadas/alteracoes-climaticas", expected = TRUE)
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

message("\n=== TEST 2: Database Cleanup and Deduplication ===")

# Create a temporary in-memory database to test cleanup
test_conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
on.exit(DBI::dbDisconnect(test_conn), add = TRUE)

# Create table schema
create_tables(test_conn)

# Insert mock opportunities (some valid, some invalid, some duplicates)
mock_ops <- tibble::tribble(
  ~id_registro, ~entidade, ~titulo, ~status_oportunidade, ~data_limite, ~descricao_resumida, ~link_origem, ~link_detalhe, ~texto_bruto,
  # Valid but duplicates: should merge and keep only the best active one (op_dup_3)
  "op_dup_1", "CNPq", "Chamada CNPq PCI 12/2026", "futuro", "2026-05-27", "short desc", "https://cnpq.br/1", "https://cnpq.br/1", "short text",
  "op_dup_2", "CNPq", "Chamada CNPq PCI 12/2026", "aberto", "2026-06-27", "longer description", "https://cnpq.br/2", "https://cnpq.br/2", "longer text",
  "op_dup_3", "CNPq", "Chamada CNPq PCI 12/2026", "aberto", "2026-06-27", "longest description of the three", "https://cnpq.br/3", "https://cnpq.br/3", "longest text that should be kept",
  
  # Valid single
  "op_valid_1", "FAPESC", "Edital de Apoio a IA Fapesc", "aberto", "2026-08-30", "valid fapesc", "https://fapesc.br/edital", "https://fapesc.br/edital/1", "full content",
  
  # Invalid by heuristics: rectifications and credit lines
  "op_finep_inst", "FINEP", "Financiamento via crédito - Finep", "aberto", "2026-06-27", "general line", "https://finep.br/credito", "https://finep.br/credito", "guide",
  "op_alteracao", "FAPES", "Edital_Genesis_-_Caparao_-_1_Alteracao.pdf", "aberto", "2025-09-19", "alteracao", "https://fapes.br/alteracao", "https://fapes.br/alteracao", "amendment text",
  "op_resultado", "FINEP", "Resultado Final da Chamada 01/2025", "aberto", "2025-12-15", "resultado", "https://finep.br/resultado", "https://finep.br/resultado", "results sheet"
)

mock_ops$hash_deduplicacao <- vapply(seq_len(nrow(mock_ops)), function(i) {
  digest::digest(paste0(mock_ops$titulo[[i]], mock_ops$link_origem[[i]]), algo = "xxhash64")
}, character(1))
mock_ops$campos_inferidos_ia <- ""
mock_ops$pais_origem <- "Brasil"

DBI::dbWriteTable(test_conn, "oportunidades", mock_ops, append = TRUE)

before_count <- DBI::dbGetQuery(test_conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]]
message("Count before cleanup: ", before_count)

# Run cleanup (heuristics + deduplication)
cleanup_database_opportunities(test_conn)

# Verify count and items after cleanup
after_ops <- DBI::dbGetQuery(test_conn, "SELECT id_registro, titulo, status_oportunidade, data_limite FROM oportunidades")
message("Count after cleanup: ", nrow(after_ops))
message("Remaining records:")
print(after_ops)

failed_db_cleanup <- 0
if (nrow(after_ops) != 2) {
  message(" FAIL: Database cleanup did not keep exactly 2 valid opportunities (the duplicate CNPq best candidate and Fapesc).")
  failed_db_cleanup <- 1
} else if (!all(after_ops$id_registro %in% c("op_dup_3", "op_valid_1"))) {
  message(" FAIL: Database cleanup kept incorrect opportunities. Kept: ", paste(after_ops$id_registro, collapse = ", "))
  failed_db_cleanup <- 1
} else {
  message(" PASS: Database cleanup successfully removed non-funding and duplicate opportunities.")
}

message("\n=== TEST 3: AI Classification Prompt ===")
if (ai_available()) {
  message("AI is configured. Testing AI classification with a mock rectification text...")
  mock_rect_text <- "ERRATA Nº 01/2026 - Chamada Pública CNPq nº 12/2026. Altera-se o cronograma do edital: onde se lê 'submissão até 27/05/2026', leia-se 'submissão até 27/06/2026'. As demais cláusulas permanecem inalteradas."
  
  res_ai <- skill_extract_metadata(mock_rect_text, current_info = list(titulo_limpo = "Errata da Chamada 12/2026"))
  
  message("AI extraction output:")
  print(res_ai)
  
  if (!is.null(res_ai$e_edital_fomento) && isFALSE(res_ai$e_edital_fomento)) {
    message(" PASS: AI correctly classified rectification page as e_edital_fomento = FALSE")
  } else {
    message(" WARNING: AI did not classify rectification page as FALSE (e_edital_fomento was ", res_ai$e_edital_fomento, ")")
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
