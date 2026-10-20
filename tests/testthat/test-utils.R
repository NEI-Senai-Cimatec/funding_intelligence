test_that("extract_domain works correctly", {
  expect_equal(extract_domain("https://www.gov.br/cnpq/pt-br"), "www.gov.br")
  expect_equal(extract_domain("https://api.groq.com/openai/v1/chat"), "api.groq.com")
  expect_equal(extract_domain("https://example.com:8080/path"), "example.com:8080")
  expect_equal(extract_domain("invalid-url"), "")
  expect_equal(extract_domain(""), "")
})

test_that("normalize_ai_date handles various formats", {
  expect_equal(normalize_ai_date("2025-03-15"), "2025-03-15")
  expect_equal(normalize_ai_date("15/03/2025"), "2025-03-15")
  expect_equal(normalize_ai_date("03/15/2025"), "2025-03-15")
  expect_equal(normalize_ai_date("a definir"), NA_character_)
  expect_equal(normalize_ai_date(NULL), NA_character_)
  expect_equal(normalize_ai_date(NA), NA_character_)
  expect_equal(normalize_ai_date(""), NA_character_)
})

test_that("validate_enum_field works with synonyms", {
  result <- validate_enum_field("aberto", .AI_ENUMS$status_oportunidade)
  expect_true(result$valid)
  expect_equal(result$normalized, "aberto")
  
  result <- validate_enum_field("open", .AI_ENUMS$status_oportunidade)
  expect_true(result$valid)
  expect_equal(result$normalized, "aberto")
  
  result <- validate_enum_field("invalid_status", .AI_ENUMS$status_oportunidade)
  expect_false(result$valid)
})

test_that("validate_language_code normalizes correctly", {
  result <- validate_language_code("pt")
  expect_true(result$valid)
  expect_equal(result$normalized, "pt")
  
  result <- validate_language_code("Português")
  expect_true(result$valid)
  expect_equal(result$normalized, "pt")
  
  result <- validate_language_code("english")
  expect_true(result$valid)
  expect_equal(result$normalized, "en")
})

test_that("validate_keyword_count checks count", {
  result <- validate_keyword_count("biotecnologia;saude;ciencia;tecnologia;educacao")
  expect_true(result$valid)
  expect_equal(result$count, 5)
  
  result <- validate_keyword_count("biotecnologia")
  expect_false(result$valid)
  expect_equal(result$count, 1)
})

test_that("validate_date_field normalizes dates", {
  result <- validate_date_field("2025-03-15")
  expect_true(result$valid)
  expect_equal(result$normalized, "2025-03-15")
  
  result <- validate_date_field("15/03/2025")
  expect_true(result$valid)
  expect_equal(result$normalized, "2025-03-15")
  
  result <- validate_date_field("invalid")
  expect_false(result$valid)
})

test_that("validate_numeric_field parses numbers", {
  result <- validate_numeric_field(150000)
  expect_true(result$valid)
  expect_equal(result$normalized, 150000)
  
  result <- validate_numeric_field("R$ 150.000")
  expect_true(result$valid)
  
  result <- validate_numeric_field("alto")
  expect_false(result$valid)
})

test_that("DomainRateLimiter respects delays", {
  limiter <- DomainRateLimiter$new(min_delay_same = 0.1, min_delay_diff = 0.05)
  
  start <- Sys.time()
  limiter$wait_if_needed("https://example.com/test1")
  limiter$wait_if_needed("https://example.com/test2")
  elapsed <- as.numeric(Sys.time() - start, units = "secs")
  
  expect_true(elapsed >= 0.1)
})

test_that("build_ai_fallback_chain returns providers with keys", {
  Sys.setenv(GROQ_API_KEY = "test_key")
  chain <- build_ai_fallback_chain()
  expect_true("groq" %in% chain)
  Sys.unsetenv("GROQ_API_KEY")
})

test_that("validate_ai_output handles valid data", {
  valid_data <- list(
    tipo_oportunidade = "edital",
    status_oportunidade = "aberto",
    idioma = "pt",
    data_limite = "2025-06-30",
    valor_financiado = 150000,
    palavras_chave = "biotecnologia;saude;ciencia;tecnologia;educacao"
  )
  result <- validate_ai_output(valid_data)
  expect_true(result$valid)
  expect_equal(length(result$warnings), 0)
})

test_that("validate_ai_output handles invalid data gracefully", {
  invalid_data <- list(
    tipo_oportunidade = "invalid_type",
    status_oportunidade = "open",
    idioma = "invalid_lang",
    data_limite = "15/03/2025",
    valor_financiado = "alto",
    palavras_chave = "biotecnologia"
  )
  result <- validate_ai_output(invalid_data)
  expect_true(result$valid)
  expect_true(length(result$warnings) > 0)
})
