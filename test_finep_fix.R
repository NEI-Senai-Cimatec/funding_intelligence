# Script de teste para verificar a correção do retorno de collect_finep
# Execute: Rscript test_finep_fix.R

cat("=== Teste da correção collect_finep ===\n\n")

# Carregar dependências
source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_collect.R")

# Testar: Verificar se collect_finep retorna lista
cat("Teste 1: Verificando tipo de retorno de collect_finep...\n")
source_row <- tibble::tibble(
  id_fonte = "finep",
  url_oportunidades = "https://www.finep.gov.br/o/c/chamadapublicas?sort=dataDePublicacao:desc&pageSize=250"
)

result <- collect_finep(
  source_row = source_row,
  max_pages = 1,
  max_records = 10,
  use_ai = FALSE,
  log_path = NULL
)

# Verificar se é lista
if (is.list(result) && !is.null(result$records)) {
  cat("✓ collect_finep retorna lista com campo 'records'\n")
  cat(sprintf("  - Número de registros: %d\n", nrow(result$records)))
  cat(sprintf("  - Páginas visitadas: %d\n", result$pages_visited))
  cat(sprintf("  - Última URL: %s\n", result$last_url))
} else {
  cat("✗ collect_finep NÃO retorna lista correta\n")
  cat(sprintf("  Tipo retornado: %s\n", class(result)))
  if (is.data.frame(result)) {
    cat(sprintf("  É um tibble com %d linhas\n", nrow(result)))
  }
}

# Teste 2: Verificar se os registros têm dados válidos
cat("\nTeste 2: Verificando dados dos registros...\n")
if (!is.null(result$records) && nrow(result$records) > 0) {
  cat("✓ Registros contêm dados válidos:\n")
  print(result$records[1:min(3, nrow(result$records)), c("titulo", "publico_alvo", "data_limite")])
}

# Teste 3: Simular o fluxo do pipeline
cat("\nTeste 3: Simulando fluxo do pipeline (collect_all_sources)...\n")
if (!is.null(result$records)) {
  recs <- finalize_records(result$records)
  cat(sprintf("✓ finalize_records retornou %d registros\n", nrow(recs)))
} else {
  cat("✗ result$records é NULL\n")
}

cat("\n=== Teste concluído! ===\n")
