# Script de teste para a nova coleta FINEP via API REST
# Execute: Rscript test_finep_api.R

cat("=== Teste da nova coleta FINEP via API REST ===\n\n")

# Carregar dependências
source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_collect.R")

# Testar 1: Verificar se a API responde
cat("Teste 1: Verificando se a API FINEP responde...\n")
url_teste <- "https://www.finep.gov.br/o/c/chamadapublicas?sort=dataDePublicacao:desc&page=1&pageSize=5"
response <- httr::GET(url_teste, httr::timeout(30))

if (httr::status_code(response) == 200) {
  cat("✓ API respondeu com status 200\n")
  data <- httr::content(response, as = "parsed", type = "application/json")
  cat(sprintf("  Total de registros disponíveis: %d\n", data$totalCount))
  cat(sprintf("  Registros nesta página: %d\n", length(data$items)))
} else {
  cat(sprintf("✗ API retornou status %d\n", httr::status_code(response)))
  stop("Falha na conexão com a API")
}

# Teste 2: Verificar estrutura dos dados
cat("\nTeste 2: Verificando estrutura dos dados...\n")
if (length(data$items) > 0) {
  item <- data$items[[1]]
  cat("✓ Estrutura de item:\n")
  cat(sprintf("  - ID: %d\n", item$id))
  cat(sprintf("  - Título: %s\n", substr(item$titulo, 1, 50)))
  cat(sprintf("  - Situação: %s\n", item$situacao$name))
  cat(sprintf("  - Público alvo: %d opções\n", length(item$publicoAlvo)))
  if (length(item$publicoAlvo) > 0) {
    cat(sprintf("    - Primeiro: %s (key: %s)\n", item$publicoAlvo[[1]]$name, item$publicoAlvo[[1]]$key))
  }
}

# Teste 3: Filtrar por ICT
cat("\nTeste 3: Testando filtro por ICT...\n")
ict_items <- Filter(function(item) {
  has_ict <- any(sapply(item$publicoAlvo, function(pa) pa$key == "ict"))
  is_aberta <- !is.null(item$situacao) && item$situacao$key == "aberta"
  (has_ict || length(item$publicoAlvo) == 0) && is_aberta
}, data$items)
cat(sprintf("✓ %d de %d itens são para ICT e estão abertos\n", length(ict_items), length(data$items)))

# Teste 4: Coleta completa (limitada)
cat("\nTeste 4: Testando coleta completa (limitada a 10 registros)...\n")
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

cat(sprintf("✓ Registros coletados: %d\n", nrow(result)))

if (nrow(result) > 0) {
  cat("\nPrimeiros 5 registros:\n")
  print(result[1:min(5, nrow(result)), c("titulo", "publico_alvo", "status_oportunidade", "data_limite")])
}

cat("\n=== Teste concluído com sucesso! ===\n")
