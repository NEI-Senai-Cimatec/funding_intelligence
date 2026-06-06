source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_text.R")
source("R/helpers_ai.R")
source("R/helpers_collect.R")

library(tibble)
library(dplyr)

message("--- INICIANDO TESTE DE ENRIQUECIMENTO COM REGISTRO INÉDITO ---")

test_df <- tibble(
  id_registro = c("fapesp_021f1b5b321cc87f", NA_character_),
  hash_deduplicacao = c("021f1b5b321cc87f", NA_character_),
  titulo = c("Oportunidades de Bolsas", "Edital Inedito de Foguetes FINEP 2026"),
  fonte_oficial = c("fapesp", "finep"),
  link_origem = c("http://example.com/fapesp1", "http://example.com/finep_inedito_2026"),
  descricao_resumida = c("Antiga descricao", NA_character_),
  descricao_completa = c("Texto completo antigo", "Chamada pública FINEP para tecnologia aeroespacial e propulsão líquida."),
  texto_bruto = c(
    "Texto bruto antigo", 
    "O objetivo da FINEP com este edital é financiar o desenvolvimento de foguetes no Brasil. A FINEP vai apoiar projetos com valor total de fomento de R$ 5.000.000,00. A seleção será feita em lotes de 12 empresas de cada vez."
  ),
  tipo_oportunidade = c("bolsa", NA_character_),
  status_oportunidade = c("aberto", NA_character_),
  idioma = c("pt", NA_character_),
  valor_financiado = c(NA_real_, 12.0), # False positive!
  moeda = c(NA_character_, "BRL"),
  data_limite = c(NA_character_, NA_character_),
  data_publicacao = c(NA_character_, NA_character_),
  observacoes = c(NA_character_, NA_character_),
  campos_inferidos_ia = c(NA_character_, NA_character_)
)

log_progress <- function(msg, phase = "INFO") {
  message(sprintf("[%s] %s", phase, msg))
}
assign("log_progress", log_progress, envir = .GlobalEnv)

result_df <- enrich_records_parallel(test_df)

message("\n--- RESULTADOS DETALHADOS ---")
glimpse(result_df)
