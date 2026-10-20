helper_files <- list.files("R", pattern = "^helpers_.*\\.R$", full.names = TRUE)
for (f in helper_files) source(f, encoding = "UTF-8")

urls <- list(
  sudene = "https://pncp.gov.br/app/editais?q=533014&status=todos&pagina=1&tam_pagina=100&tipos=1",
  pncp_api = "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?q=533014&status=todos&pagina=1&tamanhoPagina=100",
  embrapa = "https://www.embrapa.br/acessoainformacao/editais",
  bnb_fundeci = "https://www.bnb.gov.br/ConveniosWeb/Convenente.ProgramaConvenio.Lista.aspx",
  fab_dcta = "https://ieav.dcta.mil.br/index.php/editais",
  finep_aero = "https://www.finep.gov.br/oportunidades",
  aeb = "https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos",
  doe_ascr = "https://science.osti.gov/ascr/Funding-Opportunities"
)

for (name in names(urls)) {
  u <- urls[[name]]
  cat("\n=========================================\nTesting URL:", name, "->", u, "\n")
  
  if (name %in% c("doe_ascr")) {
    res <- safe_request_page_us(u)
  } else {
    res <- safe_request_page(u)
  }
  
  cat("OK:", isTRUE(res$ok), "Status:", res$status_code %||% "N/A", "\n")
  if (isTRUE(res$ok) && !is.null(res$html)) {
    title <- extract_meta_title(res$html)
    cat("Title:", title %||% "N/A", "\n")
    body_txt <- rvest::html_text(res$html, trim = TRUE)
    cat("Body text length:", nchar(body_txt), "\n")
    snippet <- substr(gsub("\\s+", " ", body_txt), 1, 300)
    cat("Snippet:", snippet, "\n")
    
    # Check links
    links <- rvest::html_nodes(res$html, "a[href]")
    cat("Total links:", length(links), "\n")
    if (length(links) > 0) {
      hrefs <- rvest::html_attr(links, "href")
      texts <- rvest::html_text(links, trim = TRUE)
      valid <- !is.na(texts) & nzchar(texts) & nchar(texts) > 5
      sub_texts <- head(texts[valid], 10)
      cat("Sample links:", paste(sub_texts, collapse = " | "), "\n")
    }
  } else {
    cat("Error/Failed:", res$error %||% "No HTML returned", "\n")
  }
}
