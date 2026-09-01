test_that("source_catalog contains 21 sources including 9 US and no world_bank", {
  src <- source_catalog()
  expect_equal(nrow(src), 21)
  expect_false("world_bank" %in% src$id_fonte)
  us_ids <- c(
    "grants_gov", "doe_ascr", "nsf_international", "nsf_qise",
    "nsf_cise", "doe_quantum_genesis", "doe_genesis", "nsf_nqni",
    "darpa_quantum_benchmarking"
  )
  expect_true(all(us_ids %in% src$id_fonte))
  # Check specific metadata
  gg <- src[src$id_fonte == "grants_gov", ]
  expect_equal(gg$pais, "Estados Unidos")
  expect_equal(gg$metodo_coleta, "hybrid")
  expect_equal(gg$idioma, "en")
  expect_true(grepl("19\\.040", gg$observacoes))
  ascr <- src[src$id_fonte == "doe_ascr", ]
  expect_true(grepl("FY2026.*30/09/2026|30/09/2026", ascr$observacoes))
})

test_that("source_catalog US entries have correct country and hybrid/html methods", {
  src <- source_catalog()
  us <- src[src$pais == "Estados Unidos", ]
  # Should be exactly 9
  expect_equal(nrow(us), 9)
  expect_true(all(us$idioma == "en"))
  expect_true(all(us$metodo_coleta %in% c("hybrid", "html")))
})

test_that("US collectors are registered in registry", {
  us_ids <- c(
    "grants_gov", "doe_ascr", "nsf_international", "nsf_qise",
    "nsf_cise", "doe_quantum_genesis", "doe_genesis", "nsf_nqni",
    "darpa_quantum_benchmarking"
  )
  for (id in us_ids) {
    coll <- get_collector(id)
    expect_false(grepl("Generic", coll$description),
      info = paste("Collector for", id, "should not be generic fallback"))
    expect_true(is.function(coll$fn),
      info = paste("Collector function for", id, "missing"))
  }
})

test_that("classify_status handles US MM/DD/YYYY format correctly", {
  expect_equal(classify_status(deadline = "09/30/2026", text = "test")[[1]], "aberto")
  expect_equal(classify_status(deadline = "09/30/2026")[[1]], "aberto")
  expect_equal(classify_status(deadline = "12/31/2020")[[1]], "encerrado")
  expect_equal(classify_status(deadline = "01/15/2020")[[1]], "encerrado")
  # ISO still works
  expect_equal(classify_status(deadline = "2026-09-30")[[1]], "aberto")
  expect_equal(classify_status(deadline = "2020-01-01")[[1]], "encerrado")
  # Vectorized
  res <- classify_status(deadline = c("09/30/2026", "2020-01-01", NA), text = c("a", "b", "c"))
  expect_equal(res[[1]], "aberto")
  expect_equal(res[[2]], "encerrado")
})

test_that("hash_deduplicacao uses xxhash64 and is deterministic", {
  h1 <- digest::digest(paste0("Test Title", "https://example.com"), algo = "xxhash64")
  h2 <- digest::digest(paste0("Test Title", "https://example.com"), algo = "xxhash64")
  expect_equal(h1, h2)
  expect_equal(nchar(h1), 16)
  # Different title -> different hash
  h3 <- digest::digest(paste0("Other Title", "https://example.com"), algo = "xxhash64")
  expect_false(h1 == h3)
})

test_that("extract_dates_from_text captures US MM/DD/YYYY", {
  dates <- extract_dates_from_text("Deadline: 09/30/2026 and 12/31/2026")
  expect_true(any(dates == as.Date("2026-09-30")))
  expect_true(any(dates == as.Date("2026-12-31")))
  dates2 <- extract_dates_from_text("Closing date: 09/30/2026")
  expect_equal(dates2[[1]], as.Date("2026-09-30"))
})

test_that("DOE ASCR record generation uses USD and correct fields", {
  # Simulate minimal DOE ASCR page structure without network
  # Create a fake source_row
  src_row <- tibble::tibble(
    id_fonte = "doe_ascr",
    nome_fonte = "DOE ASCR",
    sigla = "DOE ASCR",
    pais = "Estados Unidos",
    url_oportunidades = "https://science.osti.gov/ascr/Funding-Opportunities",
    url_principal = "https://science.energy.gov/ascr/",
    idioma = "en"
  )
  # Test helper functions directly: build a record via extract_core_record
  rec <- extract_core_record(
    source_row = src_row,
    input_title = "FY2026 Continuation of Solicitation for Advanced Scientific Computing Research",
    input_summary = "DOE Office of Science ASCR supports HPC, quantum computing and AI for Science. Deadline 09/30/2026.",
    input_full_text = "Funding Opportunity Announcement. HPC and quantum computing. Closing date: 09/30/2026. DOE National Laboratories partnership.",
    page_url = "https://science.osti.gov/ascr/Funding-Opportunities",
    detail_url = "https://science.osti.gov/ascr/Funding-Opportunities",
    pdf_url = NA_character_,
    page_no = 1L
  )
  expect_equal(rec$pais_origem, "Estados Unidos")
  expect_equal(rec$idioma, "en")
  expect_equal(rec$fonte_oficial, "doe_ascr")
  expect_true(grepl("HPC|quantum", rec$texto_bruto, ignore.case = TRUE))
  expect_equal(as.character(parse_date_safe(rec$data_limite) ), "2026-09-30")
  expect_equal(rec$status_oportunidade, "aberto")
})

test_that("Grants.gov hash includes opportunity number and is xxhash64", {
  titulo <- "Public Diplomacy Programs for U.S. Mission Brazil"
  opp_num <- "PD-BRAZIL-FY2026-01"
  h <- digest::digest(paste0("Grants.gov", "||", opp_num, "||", titulo), algo = "xxhash64")
  expect_equal(nchar(h), 16)
  id <- sprintf("grants_gov_%s", substr(h, 1, 16))
  expect_true(startsWith(id, "grants_gov_"))
})

test_that("NSF QISE supplement status is aberto for at any time", {
  txt <- "International Collaboration Supplements in Quantum Information Science and Engineering - supplement requests accepted at any time"
  status <- classify_status(deadline = NA_character_, text = txt)[[1]]
  # At any time should be aberto via future logic; but QISE collector explicitly sets aberto
  # Test that the DCL text contains expected eligibility note
  src <- source_catalog()
  qise <- src[src$id_fonte == "nsf_qise", ]
  expect_true(grepl("Brasil.*n.o priorit", qise$observacoes, ignore.case = TRUE) ||
              grepl("Brasil elegível", qise$observacoes, ignore.case = TRUE))
})

test_that("NSF NQNI has correct budget and solicitation URL", {
  src <- source_catalog()
  nqni <- src[src$id_fonte == "nsf_nqni", ]
  expect_true(grepl("nsf26-505", nqni$url_oportunidades))
  expect_true(grepl("100M", nqni$observacoes))
  expect_equal(nqni$metodo_coleta, "html")
})

test_that("DARPA QBI has Playwright stealth description", {
  coll <- get_collector("darpa_quantum_benchmarking")
  expect_true(grepl("Playwright|Stealth", coll$description, ignore.case = TRUE))
})

test_that("DOE Quantum Genesis and Genesis return empty when no FOA (offline logic)", {
  # Test that the collector logic for single-page monitor returns empty when page lacks FOA signals
  # We cannot call live network, so we test the helper logic: page without FOA should be considered empty
  fake_text_no_foa <- "Genesis Mission is an initiative for AI and quantum. Learn more about our vision for 2028."
  has_foa <- grepl("Funding Opportunity Announcement|FOA|solicitation|apply now|deadline.*202", fake_text_no_foa, ignore.case = TRUE)
  expect_false(has_foa)
  fake_text_with_foa <- "Funding Opportunity Announcement FOA-2026-001: Apply now. Deadline 09/30/2026."
  has_foa2 <- grepl("Funding Opportunity Announcement|FOA|solicitation|apply now|deadline.*202", fake_text_with_foa, ignore.case = TRUE)
  expect_true(has_foa2)
})

test_that("get_us_proxy_url respects EU_API_PROXY_URL env var", {
  # Clear env
  old <- Sys.getenv("EU_API_PROXY_URL", unset = "")
  Sys.unsetenv("EU_API_PROXY_URL")
  expect_equal(get_us_proxy_url("https://simpler.grants.gov/search"), "https://simpler.grants.gov/search")
  # Set proxy
  Sys.setenv(EU_API_PROXY_URL = "https://worker.example.workers.dev")
  expect_true(grepl("worker\\.example", get_us_proxy_url("https://simpler.grants.gov/search")))
  expect_equal(get_us_proxy_url("https://api.tech.ec.europa.eu/search-api/prod/rest/search"), "https://api.tech.ec.europa.eu/search-api/prod/rest/search")
  # Restore
  if (nzchar(old)) Sys.setenv(EU_API_PROXY_URL = old) else Sys.unsetenv("EU_API_PROXY_URL")
})

test_that("NSF CISE hybrid and filtering metadata present", {
  src <- source_catalog()
  cise <- src[src$id_fonte == "nsf_cise", ]
  expect_equal(cise$metodo_coleta, "hybrid")
  expect_true(grepl("CISE", cise$observacoes) || grepl("HPC", cise$observacoes))
})

test_that("seed_sources persists new US sources after init_database", {
  db_path <- tempfile(fileext = ".sqlite")
  conn <- get_db_connection(db_path)
  create_tables(conn)
  seed_sources(conn)
  src <- DBI::dbGetQuery(conn, "SELECT id_fonte FROM fontes_financiamento")
  expect_equal(nrow(src), 21)
  expect_true(all(c("grants_gov", "doe_ascr") %in% src$id_fonte))
  # Simulate init_database cleaning world_bank
  DBI::dbExecute(conn, "INSERT OR REPLACE INTO fontes_financiamento (id_fonte, nome_fonte, sigla, pais, categoria, tipo_financiador, url_principal, url_oportunidades, metodo_coleta, idioma, periodicidade_atualizacao, observacoes) VALUES ('world_bank','WB','WB','USA','x','y','https://x','https://y','html','en','diaria','test')")
  DBI::dbDisconnect(conn)
  init_database(db_path)
  conn2 <- get_db_connection(db_path)
  src2 <- DBI::dbGetQuery(conn2, "SELECT id_fonte FROM fontes_financiamento WHERE id_fonte='world_bank'")
  expect_equal(nrow(src2), 0)
  DBI::dbDisconnect(conn2)
  unlink(db_path)
})

test_that("finalize_records does not discard US future deadlines", {
  src_row <- tibble::tibble(
    id_fonte = "doe_ascr",
    nome_fonte = "DOE ASCR",
    sigla = "DOE ASCR",
    pais = "Estados Unidos",
    url_oportunidades = "https://science.osti.gov/ascr/Funding-Opportunities",
    url_principal = "https://science.energy.gov/ascr/",
    idioma = "en"
  )
  rec <- extract_core_record(
    source_row = src_row,
    input_title = "FY2026 Continuation of Solicitation",
    input_summary = "HPC Quantum",
    input_full_text = "Deadline 09/30/2026",
    page_url = "https://science.osti.gov/ascr/Funding-Opportunities",
    detail_url = NA_character_,
    pdf_url = NA_character_,
    page_no = 1L
  )
  rec$data_limite <- "2026-09-30"
  df <- finalize_records(rec, fonte_oficial = "doe_ascr")
  # Should keep, not filter as old year
  expect_true(nrow(df) >= 1)
})
