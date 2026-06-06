# Test Sigitec Petrobras scraping
source("R/helpers_utils.R")
source("R/helpers_db.R")
source("R/helpers_text.R")
source("R/helpers_ai.R")
source("R/helpers_collect.R")

url <- "https://sigitec-competitividade.petrobras.com.br/v2/public/opportunities"
cat("Fetching page via safe_request_page (forcing browser fallback since we want to test SPA rendering)...\n")

# Use safe_request_page_playwright directly
res <- safe_request_page_playwright(url)
if (isTRUE(res$ok)) {
  cat("Success! Rendeered HTML size:", nchar(res$text), "\n")
  writeLines(res$text, "scratch/sigitec_rendered.html")
  
  # Try to extract candidates
  source_row <- tibble::tibble(
    id_fonte = "sigitec",
    sigla = "PETROBRAS",
    nome_fonte = "SIGITEC PETROBRAS",
    pais = "Brasil",
    url_oportunidades = url,
    idioma = "pt"
  )
  
  candidates <- extract_listing_candidates(res$html, url, source_row)
  cat("Found", nrow(candidates), "candidates.\n")
  if (nrow(candidates) > 0) {
    print(candidates)
  } else {
    # Let's inspect links in the HTML
    links <- rvest::html_nodes(res$html, "a")
    hrefs <- rvest::html_attr(links, "href")
    texts <- rvest::html_text(links, trim = TRUE)
    cat("All Links in rendered page:\n")
    print(tibble::tibble(text = texts, href = hrefs))
  }
} else {
  cat("Failed to fetch page using Playwright.\n")
}
