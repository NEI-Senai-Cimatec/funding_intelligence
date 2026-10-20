# Teste da nova implementação do collector SIGITEC
# Executar: Rscript scratch/test_sigitec_v2.R

source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_text.R")
source("R/helpers_ai.R")
source("R/helpers_collect.R")

cat("=== Teste do Collector SIGITEC Petrobras ===\n\n")

# Criar source_row de teste
source_row <- tibble::tibble(
  id_fonte = "sigitec",
  sigla = "PETROBRAS",
  nome_fonte = "Petrobras SIGITEC - Sistema de Gestão de Inovação e Tecnologia Competitividade",
  pais = "Brasil",
  url_oportunidades = "https://sigitec-competitividade.petrobras.com.br/v2/public/opportunities",
  idioma = "pt"
)

cat("1. Verificando se o collector está registrado...\n")
collector <- get_collector("sigitec")
cat("   Collector:", collector$description, "\n\n")

cat("2. Testando conexão com a API...\n")
listing_url <- "https://sigitec-competitividade.petrobras.com.br/v2/ms-authorization/opportunity/getAllPublicOpportunities"
alive <- is_host_alive(listing_url)
cat("   Host alive:", alive, "\n\n")

if (!alive) {
  cat("   ERRO: Host inacessível. Abortando teste.\n")
  quit(status = 1)
}

cat("3. Executando coleta (max 5 registros para teste rápido)...\n")
log_file <- "logs/test_sigitec_v2.log"
ensure_dir(dirname(log_file))

result <- collect_sigitec(
  source_row = source_row,
  max_pages = 1,
  max_records = 5,
  use_ai = FALSE,
  log_path = log_file
)

cat("\n4. Resultados:\n")
cat("   Registros coletados:", nrow(result$records), "\n")
cat("   Páginas visitadas:", result$pages_visited, "\n")
cat("   Última URL:", result$last_url, "\n\n")

if (nrow(result$records) > 0) {
  cat("5. Estrutura dos registros:\n")
  print(tibble::glimpse(result$records))
  
  cat("\n6. Primeiro registro (resumo):\n")
  rec <- result$records[1, ]
  cat("   ID:", rec$id_registro, "\n")
  cat("   Título:", substr(rec$titulo, 1, 80), "\n")
  cat("   Status:", rec$status_oportunidade, "\n")
  cat("   Deadline:", rec$data_limite, "\n")
  cat("   Link:", rec$link_detalhe, "\n")
  cat("   Área:", rec$area_tematica, "\n")
  
  cat("\n7. Verificando campos obrigatórios...\n")
  required_fields <- c("id_registro", "titulo", "entidade", "pais_origem", 
                       "link_origem", "fonte_oficial", "hash_deduplicacao")
  missing <- setdiff(required_fields, names(result$records))
  if (length(missing) > 0) {
    cat("   CAMPOS FALTANDO:", paste(missing, collapse = ", "), "\n")
  } else {
    cat("   OK - Todos os campos obrigatórios presentes.\n")
  }
  
  # Verificar deduplicação
  cat("\n8. Verificando deduplicação...\n")
  n_unique <- length(unique(result$records$hash_deduplicacao))
  cat("   Hashes únicos:", n_unique, "/", nrow(result$records), "\n")
  if (n_unique == nrow(result$records)) {
    cat("   OK - Todos os hashes são únicos.\n")
  } else {
    cat("   AVISO: Hashes duplicados encontrados!\n")
  }
  
  cat("\n9. Amostra dos dados (3 registros):\n")
  print(result$records[1:min(3, nrow(result$records)), 
                       c("id_registro", "titulo", "status_oportunidade", 
                         "data_limite", "area_tematica")])
} else {
  cat("   AVISO: Nenhum registro coletado. Verifique o log em:", log_file, "\n")
}

cat("\n=== Teste concluído ===\n")
