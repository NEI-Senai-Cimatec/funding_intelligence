helper_files <- list.files("R", pattern = "^helpers_.*\\.R$", full.names = TRUE)
for (f in helper_files) source(f, encoding = "UTF-8")

cat("\n=================== 1. FAB DCTA ===================\n")
pg_dcta <- safe_request_page("https://ieav.dcta.mil.br/index.php/editais")
cat("DCTA OK:", isTRUE(pg_dcta$ok), "\n")
if (isTRUE(pg_dcta$ok) && !is.null(pg_dcta$html)) {
  links <- rvest::html_elements(pg_dcta$html, "a[href]")
  cat("Total links:", length(links), "\n")
  for (l in links) {
    txt <- rvest::html_text(l, trim = TRUE)
    hr <- rvest::html_attr(l, "href")
    if (nchar(txt) > 5 && !grepl("acessibilidade|governo|mapa|alto contraste|joomla|facebook|instagram|twitter", txt, ignore.case = TRUE)) {
      cat("DCTA LINK:", txt, "==>", hr, "\n")
    }
  }
}

cat("\n=================== 2. AEB ===================\n")
pg_aeb <- safe_request_page("https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos")
cat("AEB OK:", isTRUE(pg_aeb$ok), "\n")
if (isTRUE(pg_aeb$ok) && !is.null(pg_aeb$html)) {
  nodes <- rvest::html_elements(pg_aeb$html, "article, .tileItem, .hentry, h2.tileHeadline a, h3.tileHeadline a, #content a, div.item a")
  cat("AEB nodes:", length(nodes), "\n")
  for (n in head(nodes, 25)) {
    txt <- rvest::html_text(n, trim = TRUE)
    hr <- rvest::html_attr(n, "href") %||% rvest::html_attr(rvest::html_element(n, "a"), "href")
    if (!is.na(txt) && nchar(txt) > 8 && !grepl("ir para|acesso|navega|desenrola|imposto", txt, ignore.case = TRUE)) {
      cat("AEB ITEM:", substr(gsub("\\s+", " ", txt), 1, 100), "==>", hr, "\n")
    }
  }
}

cat("\n=================== 3. FINEP AERO ===================\n")
pg_finep <- safe_request_page("https://www.finep.gov.br/oportunidades")
cat("FINEP OK:", isTRUE(pg_finep$ok), "\n")
if (isTRUE(pg_finep$ok) && !is.null(pg_finep$html)) {
  links <- rvest::html_elements(pg_finep$html, "a[href]")
  cat("FINEP links:", length(links), "\n")
  for (l in links) {
    txt <- rvest::html_text(l, trim = TRUE)
    hr <- rvest::html_attr(l, "href")
    if (nchar(txt) > 10 && grepl("chamada|edital|programa|oportunidade|subvenção|finep|pesquisa", txt, ignore.case = TRUE)) {
      cat("FINEP LINK:", txt, "==>", hr, "\n")
    }
  }
}

cat("\n=================== 4. EMBRAPA ===================\n")
# Try with safe_request_page or custom timeout
pg_emb <- safe_request_page("https://www.embrapa.br/acessoainformacao/editais")
cat("EMBRAPA OK:", isTRUE(pg_emb$ok), "\n")
if (isTRUE(pg_emb$ok) && !is.null(pg_emb$html)) {
  links <- rvest::html_elements(pg_emb$html, "a[href]")
  cat("EMBRAPA links:", length(links), "\n")
  for (l in head(links, 30)) {
    txt <- rvest::html_text(l, trim = TRUE)
    hr <- rvest::html_attr(l, "href")
    if (nchar(txt) > 8) cat("EMBRAPA LINK:", txt, "==>", hr, "\n")
  }
}

cat("\n=================== 5. DOE ASCR ===================\n")
pg_ascr <- safe_request_page_us("https://science.osti.gov/ascr/Funding-Opportunities")
cat("DOE ASCR OK:", isTRUE(pg_ascr$ok), "\n")
if (isTRUE(pg_ascr$ok) && !is.null(pg_ascr$html)) {
  # Extract text content of the page
  page_title <- extract_meta_title(pg_ascr$html)
  cat("Title:", page_title, "\n")
  p_nodes <- rvest::html_elements(pg_ascr$html, "main p, main li, article p, article li, .content p, .content li")
  cat("Paragraphs:", length(p_nodes), "\n")
  for (p in head(p_nodes, 15)) {
    txt <- rvest::html_text(p, trim = TRUE)
    if (nchar(txt) > 20) cat("ASCR P:", substr(gsub("\\s+", " ", txt), 1, 120), "\n")
  }
}
