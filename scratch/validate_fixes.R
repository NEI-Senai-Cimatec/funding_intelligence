# Script de validação dos ajustes do CAPES e filtro de ano corrente
# Para rodar: Rscript scratch/validate_fixes.R

source("R/helpers_utils.R")
source("R/helpers_collect.R")

message("=== TESTE 1: Limpeza de Título (clean_edital_title) ===")

test_titles <- list(
  list(input = "EDITAL2ProgramaFamiliaePoliticasPublicasnoBrasil.pdf", expected = "EDITAL 2 Programa Familia e Politicas Publicas no Brasil"),
  list(input = "Edital_12_2026_Inovacao.pdf", expected = "Edital 12 2026 Inovacao"),
  list(input = "ChamadaPublicaCNPq.pdf", expected = "Chamada Publica CNPq"),
  list(input = "Edital 05/2026", expected = "Edital 05/2026"), # Não deve alterar se já estiver limpo
  list(input = "EDITAL502026RedeNordestenoBrasil.pdf", expected = "EDITAL 50 2026 Rede Nordeste no Brasil")
)

failed_titles <- 0
for (tc in test_titles) {
  res <- clean_edital_title(tc$input)
  if (identical(res, tc$expected)) {
    message(sprintf(" PASS: '%s' -> '%s'", tc$input, res))
  } else {
    message(sprintf(" FAIL: '%s' -> Got '%s', expected '%s'", tc$input, res, tc$expected))
    failed_titles <- failed_titles + 1
  }
}

message("\n=== TESTE 2: Filtro de Ano Corrente (is_current_year_record) ===")
# Ano corrente esperado: 2026 (baseado no horário do sistema)
current_year <- as.integer(format(Sys.Date(), "%Y"))
message(sprintf("Ano corrente detectado: %d", current_year))

test_records <- list(
  # Caso 1: Publicado em 2026
  list(pub = "2026-06-01", lim = "2026-08-01", title = "Edital Teste", text = "Texto", expected = TRUE),
  # Caso 2: Publicado em 2025 (Antigo)
  list(pub = "2025-12-01", lim = "2026-01-01", title = "Edital Teste", text = "Texto", expected = FALSE),
  # Caso 3: Sem data de publicação, mas limite em 2026
  list(pub = NA, lim = "2026-05-01", title = "Edital Teste", text = "Texto", expected = TRUE),
  # Caso 4: Sem data de publicação, mas limite em 2025 (Antigo)
  list(pub = NA, lim = "2025-12-31", title = "Edital Teste", text = "Texto", expected = FALSE),
  # Caso 5: Sem datas, mas menciona 2026 no título
  list(pub = NA, lim = NA, title = "Chamada 21/2026", text = "Texto explicativo", expected = TRUE),
  # Caso 6: Sem datas, mas menciona 2025 no título (Antigo)
  list(pub = NA, lim = NA, title = "Chamada 15/2025", text = "Texto explicativo", expected = FALSE),
  # Caso 7: Sem datas, mas menciona 2026 no texto
  list(pub = NA, lim = NA, title = "Chamada Inovação", text = "Edital lançado em 2026 pela instituição", expected = TRUE)
)

failed_records <- 0
for (i in seq_along(test_records)) {
  tc <- test_records[[i]]
  res <- is_current_year_record(tc$pub, tc$lim, tc$title, tc$text)
  if (res == tc$expected) {
    message(sprintf(" PASS: Caso %d -> %s", i, res))
  } else {
    message(sprintf(" FAIL: Caso %d -> Got %s, expected %s", i, res, tc$expected))
    failed_records <- failed_records + 1
  }
}

if (failed_titles == 0 && failed_records == 0) {
  message("\nTODOS OS TESTES PASSARAM COM SUCESSO!")
} else {
  stop("\nHOUVE FALHAS NOS TESTES.")
}
