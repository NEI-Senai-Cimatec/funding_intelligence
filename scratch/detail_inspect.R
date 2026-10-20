library(rvest)
library(httr2)
library(dplyr)

ua <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 1. DOE ASCR
cat("\n=================== 1. DOE ASCR HTML CONTENT ===================\n")
req_ascr <- request("https://science.osti.gov/ascr/Funding-Opportunities") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE, followlocation = TRUE)
resp_ascr <- tryCatch(req_perform(req_ascr), error = function(e) e)
if (inherits(resp_ascr, "httr2_response")) {
  html <- resp_body_html(resp_ascr)
  main_nodes <- html_elements(html, "main, article, .content, #content, .col-md-9, .col-lg-8, .body-content, body")
  cat("Main nodes found:", length(main_nodes), "\n")
  links <- html_elements(main_nodes, "a[href]")
  cat("Links in main area:", length(links), "\n")
  for (l in head(links, 25)) {
    txt <- html_text(l, trim = TRUE)
    hr <- html_attr(l, "href")
    if (nchar(txt) > 5) cat("LINK:", txt, "==>", hr, "\n")
  }
}

# 2. EMBRAPA
cat("\n=================== 2. EMBRAPA FETCHING ===================\n")
req_emb <- request("https://www.embrapa.br/acessoainformacao/editais") |>
  req_headers(`User-Agent` = ua) |>
  req_options(ssl_verifypeer = FALSE, ssl_verifyhost = FALSE, followlocation = TRUE)
resp_emb <- tryCatch(req_perform(req_emb), error = function(e) e)
if (inherits(resp_emb, "httr2_response")) {
  cat("EMBRAPA status:", resp_status(resp_emb), "\n")
  html_emb <- resp_body_html(resp_emb)
  cat("EMBRAPA title:", html_text(html_element(html_emb, "title")), "\n")
  items <- html_elements(html_emb, "a[href]")
  cat("EMBRAPA links found:", length(items), "\n")
  for (it in head(items, 20)) {
    t_text <- html_text(it, trim = TRUE)
    hr <- html_attr(it, "href")
    if (nchar(t_text) > 8) cat("ITEM:", t_text, "==>", hr, "\n")
  }
} else if (inherits(resp_emb, "error")) {
  cat("EMBRAPA error:", conditionMessage(resp_emb), "\n")
}

# 3. AEB
cat("\n=================== 3. AEB EDITAIS ===================\n")
req_aeb <- request("https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos") |>
  req_headers(`User-Agent` = ua) |>
  req_options(ssl_verifypeer = FALSE, ssl_verifyhost = FALSE, followlocation = TRUE)
resp_aeb <- tryCatch(req_perform(req_aeb), error = function(e) e)
if (inherits(resp_aeb, "httr2_response")) {
  html_aeb <- resp_body_html(resp_aeb)
  cat("AEB title:", html_text(html_element(html_aeb, "title")), "\n")
  tiles <- html_elements(html_aeb, "article, .tileItem, .entry, h2 a, h3 a, div.item, a[href]")
  cat("AEB tiles found:", length(tiles), "\n")
  for (tile in head(tiles, 20)) {
    txt <- html_text(tile, trim = TRUE)
    link <- html_attr(html_element(tile, "a"), "href") %||% html_attr(tile, "href")
    if (!is.null(txt) && nchar(txt) > 10) cat("AEB TILE:", substr(gsub("\\s+", " ", txt), 1, 100), "| LINK:", link, "\n")
  }
} else if (inherits(resp_aeb, "error")) {
  cat("AEB error:", conditionMessage(resp_aeb), "\n")
}

# 4. PNCP API (for SUDENE)
cat("\n=================== 4. SUDENE / PNCP API ===================\n")
pncp_test_urls <- c(
  "https://pncp.gov.br/api/pncp/v1/orgaos/533014/compras?pagina=1",
  "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?q=sudene&status=todos&pagina=1&tamanhoPagina=100",
  "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?cnpjOrgao=04017002000180&pagina=1&tamanhoPagina=50",
  "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?q=533014&status=todos&pagina=1&tamanhoPagina=100"
)

for (p_url in pncp_test_urls) {
  r_pncp <- tryCatch(
    request(p_url) |>
      req_headers(`User-Agent` = ua, Accept = "application/json") |>
      req_options(ssl_verifypeer = FALSE, ssl_verifyhost = FALSE) |>
      req_perform(),
    error = function(e) e
  )
  if (inherits(r_pncp, "httr2_response")) {
    cat("PNCP SUCCESS:", p_url, "| Status:", resp_status(r_pncp), "\n")
    str_body <- resp_body_string(r_pncp)
    cat("Body snippet:", substr(str_body, 1, 400), "\n\n")
  } else if (inherits(r_pncp, "error")) {
    cat("PNCP FAIL:", p_url, "| Error:", conditionMessage(r_pncp), "\n")
  }
}
