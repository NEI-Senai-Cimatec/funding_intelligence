local_libs <- 'c:/Users/Micro/source/repos/funding_intelligence/R_libs'
.libPaths(c(local_libs, .libPaths()))

source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_ai.R")
source("R/helpers_collect.R")

library(RSQLite)

db_path <- "funding_intelligence.sqlite"
conn <- dbConnect(SQLite(), db_path)

# 1. Clean existing dummy if present
dbExecute(conn, "DELETE FROM oportunidades WHERE id_registro = 'fapesp_test_999'")

# 2. Create raw mock record
raw_record <- tibble::tibble(
  id_registro = "fapesp_test_999",
  entidade = "FAPESP",
  pais_origem = "Brasil",
  titulo = "Bolsa de Pós-Doutorado em Computação Quântica e IA",
  subtitulo = "Subtítulo do edital teste",
  descricao_resumida = "Esta é a descrição resumida inicial do edital...",
  descricao_completa = "Esta é a descrição completa. O edital financia bolsas de pós-doutorado em computação quântica e inteligência artificial aplicada a saúde. Público-alvo: pesquisadores doutores. Valor: R$ 150.000,00. Inscrições abrem em 01/08/2026 e encerram em 30/10/2026.",
  tipo_oportunidade = "bolsa",
  modalidade = NA_character_,
  area_tematica = NA_character_,
  palavras_chave = NA_character_,
  elegibilidade = NA_character_,
  publico_alvo = NA_character_,
  nivel_academico = NA_character_,
  instituicao_financiadora = "FAPESP",
  valor_financiado = NA_real_,
  moeda = NA_character_,
  data_publicacao = NA_character_,
  data_abertura = NA_character_,
  data_limite = "2026-10-30",
  data_encerramento = NA_character_,
  status_oportunidade = "aberto",
  link_origem = "https://fapesp.br/oportunidades/",
  link_detalhe = NA_character_,
  link_documento_pdf = NA_character_,
  idioma = "pt",
  localidade = "São Paulo",
  observacoes = NA_character_,
  texto_bruto = "Esta é a descrição completa...",
  pagina_coletada = 1L,
  fonte_oficial = "fapesp",
  data_hora_coleta = as.character(Sys.time()),
  hash_deduplicacao = "hash_test_999",
  campos_inferidos_ia = NA_character_
)

# 3. Save raw record in DB (representing pre-existing un-enriched record)
message("Saving raw mock record in database...")
n_ins <- upsert_opportunities(conn, raw_record)
cat("Inserted: ", n_ins, "\n")

# Verify it was inserted with null fields
check_raw <- dbGetQuery(conn, "SELECT id_registro, modalidade, publico_alvo, palavras_chave, campos_inferidos_ia FROM oportunidades WHERE id_registro = 'fapesp_test_999'")
print(as.list(check_raw))

# 4. Enrich record with AI (this will trigger AI extraction and populate fields)
message("\n--- Running AI Enrichment ---")
enriched_df <- enrich_records_parallel(raw_record)

# 5. Persist enriched record using UPSERT
message("\nSaving enriched record via UPSERT...")
n_up <- upsert_opportunities(conn, enriched_df)
cat("UPSERT affected: ", n_up, "\n")

# 6. Query DB and check fields
message("\n--- Querying final DB record ---")
final_rec <- dbGetQuery(conn, "SELECT * FROM oportunidades WHERE id_registro = 'fapesp_test_999'")

dbDisconnect(conn)

cat("\n=== RESULTS ===\n")
cat("ID: ", final_rec$id_registro[[1]], "\n")
cat("TITULO ENRIQUECIDO: ", final_rec$titulo[[1]], "\n")
cat("PALAVRAS-CHAVE: ", final_rec$palavras_chave[[1]], "\n")
cat("MODALIDADE: ", final_rec$modalidade[[1]], "\n")
cat("PÚBLICO-ALVO: ", final_rec$publico_alvo[[1]], "\n")
cat("NÍVEL ACADÊMICO: ", final_rec$nivel_academico[[1]], "\n")
cat("DATA ABERTURA: ", final_rec$data_abertura[[1]], "\n")
cat("DATA ENCERRAMENTO: ", final_rec$data_encerramento[[1]], "\n")
cat("VALOR: ", final_rec$valor_financiado[[1]], "\n")
cat("MOEDA: ", final_rec$moeda[[1]], "\n")
cat("CAMPOS INFERIDOS IA: ", final_rec$campos_inferidos_ia[[1]], "\n")

# Assertions
failed <- FALSE
if (is.na(final_rec$campos_inferidos_ia[[1]]) || !nzchar(final_rec$campos_inferidos_ia[[1]])) {
  message("FAIL: campos_inferidos_ia was not populated or UPSERT failed!")
  failed <- TRUE
}
if (is.na(final_rec$modalidade[[1]]) || !nzchar(final_rec$modalidade[[1]])) {
  message("FAIL: modalidade was not populated by AI!")
  failed <- TRUE
}
if (!grepl(";", final_rec$palavras_chave[[1]]) && nchar(final_rec$palavras_chave[[1]]) > 0) {
  # Palavras chave should be a comma/semicolon separated list, not a single word
  message("WARNING: palavras_chave only has one keyword, check if vector split succeeded.")
}

if (!failed) {
  message("\nSUCCESS: All Data QA modifications verified and working!")
} else {
  message("\nFAIL: Some checks did not pass.")
}
