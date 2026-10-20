test_that(".extract_deadline_from_cronograma_section finds date near 'submissão' in cronograma", {
  txt <- paste(
    "EDITAL No 018/2026",
    "OBJETO: Financiamento de projetos.",
    "",
    "5. CRONOGRAMA DO EDITAL",
    "Etapa 1: Submissão de propostas: 15/07/2026 a 15/08/2026",
    "Etapa 2: Análise técnica: até 30/09/2026",
    "Etapa 3: Resultado: 15/11/2026",
    sep = "\n"
  )
  result <- .extract_deadline_from_cronograma_section(txt)
  expect_equal(result, "2026-08-15")
})

test_that(".extract_deadline_from_cronograma_section finds 'data final de postagem'", {
  txt <- paste(
    "CRONOGRAMA DO EDITAL",
    "Publicação do edital: 01/07/2026",
    "Data final de postagem das propostas: 30/09/2026",
    "Resultado preliminar: 15/12/2026",
    sep = "\n"
  )
  result <- .extract_deadline_from_cronograma_section(txt)
  expect_equal(result, "2026-09-30")
})

test_that(".extract_deadline_from_cronograma_section handles ISO dates", {
  txt <- paste(
    "CRONOGRAMA",
    "Prazo final para submissão: 2026-12-31",
    "Resultado: 2027-03-01",
    sep = "\n"
  )
  result <- .extract_deadline_from_cronograma_section(txt)
  expect_equal(result, "2026-12-31")
})

test_that(".extract_deadline_from_cronograma_section handles long-form Portuguese dates", {
  txt <- paste(
    "5. CRONOGRAMA",
    "Envio da proposta: 15 de julho de 2026",
    "Resultado: 1 de setembro de 2026",
    sep = "\n"
  )
  result <- .extract_deadline_from_cronograma_section(txt)
  expect_equal(result, "2026-07-15")
})

test_that(".extract_deadline_from_cronograma_section returns NA for empty text", {
  expect_equal(.extract_deadline_from_cronograma_section(""), NA_character_)
  expect_equal(.extract_deadline_from_cronograma_section("abc"), NA_character_)
  expect_equal(.extract_deadline_from_cronograma_section(NA_character_), NA_character_)
})

test_that(".extract_deadline_generic finds 'prazo final'", {
  txt <- "Edital de concessão. Prazo final: 20/06/2027. Resultado em agosto."
  result <- .extract_deadline_generic(txt)
  expect_equal(result, "2027-06-20")
})

test_that(".extract_deadline_generic finds 'período de submissão'", {
  txt <- "Período de submissão: 01/03/2026 a 30/04/2026."
  result <- .extract_deadline_generic(txt)
  expect_equal(result, "2026-04-30")
})

test_that(".extract_deadline_generic prefers future date over past date", {
  txt <- "Edital publicado em 01/01/2026. Prazo final: 30/12/2027."
  result <- .extract_deadline_generic(txt)
  expect_equal(result, "2027-12-30")
})

test_that(".parse_fapesb_category_items filters erratas and prev year", {
  # Mock HTML with errata and prev year items
  html <- xml2::read_html('
    <div id="tab1">
      <div class="edital-item col-md-12">
        <div class="edital-title"><h3><a href="https://www.fapesb.ba.gov.br/edital-018-2026/">EDITAL 018/2026 - APOIO A PUBLICACAO</a></h3></div>
        <p>Descricao do edital</p>
      </div>
      <div class="edital-item col-md-12">
        <div class="edital-title"><h3><a href="https://www.fapesb.ba.gov.br/errata-018/">ERRATA 018/2026</a></h3></div>
        <p>Errata</p>
      </div>
      <div class="edital-item col-md-12">
        <div class="edital-title"><h3><a href="https://www.fapesb.ba.gov.br/edital-005-2025/">EDITAL 005/2025 - BOLSAS</a></h3></div>
        <p>Bolsas 2025</p>
      </div>
    </div>
  ')
  items <- .parse_fapesb_category_items(html, 2026L)
  expect_equal(nrow(items), 1L)
  expect_equal(items$titulo, "EDITAL 018/2026 - APOIO A PUBLICACAO")
})

test_that(".extract_fapesb_prazo_from_detail returns status on parse error", {
  result <- .extract_fapesb_prazo_from_detail("not html", "https://example.com")
  expect_equal(result$status, "html_parse_error")
  expect_true(is.na(result$data_limite))
})

test_that("extract_dates_from_text handles DD/MM/AA format", {
  result <- extract_dates_from_text("Início: 15/07/26. Fim: 30/12/26.")
  result <- result[!is.na(result)]
  expect_true(length(result) >= 1)
})

test_that("extract_dates_from_text handles DD.MM.YYYY format", {
  result <- extract_dates_from_text("Início: 15.07.2026. Fim: 30.12.2026.")
  result <- result[!is.na(result)]
  expect_equal(length(result), 2)
})

test_that("extract_dates_from_text handles ordinal dates", {
  result <- extract_dates_from_text("Entrega: 1º de setembro de 2026.")
  result <- result[!is.na(result)]
  expect_equal(length(result), 1)
  expect_equal(format(result, "%Y-%m-%d"), "2026-09-01")
})

test_that("extract_dates_from_text handles Month/YYYY format", {
  result <- extract_dates_from_text("Publicação: julho/2026. Resultado: setembro/2026.")
  result <- result[!is.na(result)]
  expect_equal(length(result), 2)
})
