library(rvest)
library(httr2)
library(dplyr)

ua <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 1. DOE ASCR
cat("\n=================== INSPECTING DOE ASCR ===================\n")
req <- request("https://science.osti.gov/ascr/Funding-Opportunities") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE)
resp <- tryCatch(req_perform(req), error = function(e) NULL)
if (!is.null(resp)) {
  html <- resp_body_html(resp)
  cat("Page title:", html_text(html_element(html, "title")), "\n")
  # Look for table, article, or link elements
  tables <- html_elements(html, "table")
  cat("Tables count:", length(tables), "\n")
  if (length(tables) > 0) {
    for (i in seq_along(tables)) {
      cat("Table", i, "rows:", length(html_elements(tables[[i]], "tr")), "\n")
      print(html_table(tables[[i]]))
    }
  }
  
  # Look for h2, h3, or links
  links <- html_elements(html, "a[href]")
  hrefs <- html_attr(links, "href")
  texts <- html_text(links, trim = TRUE)
  df_links <- tibble(text = texts, href = hrefs) |>
    filter(nchar(text) > 10, !grepl("javascript|mailto|#|privacy|contact|search", href, ignore.case = TRUE))
  cat("Filtered links count:", nrow(df_links), "\n")
  print(head(df_links, 15))
}

# 2. EMBRAPA
cat("\n=================== INSPECTING EMBRAPA ===================\n")
req_emb <- request("https://www.embrapa.br/acessoainformacao/editais") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE, followlocation = TRUE)
resp_emb <- tryCatch(req_perform(req_emb), error = function(e) NULL)
if (!is.null(resp_emb)) {
  html_emb <- resp_body_html(resp_emb)
  cat("EMBRAPA Title:", html_text(html_element(html_emb, "title")), "\n")
  links_emb <- html_elements(html_emb, "a[href]")
  cat("EMBRAPA links count:", length(links_emb), "\n")
  txt_emb <- html_text(links_emb, trim = TRUE)
  href_emb <- html_attr(links_emb, "href")
  df_emb <- tibble(text = txt_emb, href = href_emb) |> filter(nchar(text) > 8)
  print(head(df_emb, 15))
} else {
  cat("EMBRAPA request failed.\n")
}

# 3. AEB
cat("\n=================== INSPECTING AEB ===================\n")
req_aeb <- request("https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE, followlocation = TRUE)
resp_aeb <- tryCatch(req_perform(req_aeb), error = function(e) NULL)
if (!is.null(resp_aeb)) {
  html_aeb <- resp_body_html(resp_aeb)
  cat("AEB Title:", html_text(html_element(html_aeb, "title")), "\n")
  links_aeb <- html_elements(html_aeb, "a[href]")
  txt_aeb <- html_text(links_aeb, trim = TRUE)
  href_aeb <- html_attr(links_aeb, "href")
  df_aeb <- tibble(text = txt_aeb, href = href_aeb) |> filter(nchar(text) > 8)
  print(head(df_aeb, 15))
} else {
  cat("AEB request failed.\n")
}

# 4. PNCP API (for SUDENE - cnpj 533014 or term)
cat("\n=================== TESTING PNCP API ===================\n")
pncp_urls <- c(
  "https://pncp.gov.br/api/pncp/v1/orgaos/00394460000141/contratacoes?pagina=1&tamanhoPagina=10",
  "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?q=sudene&status=todos&pagina=1&tamanhoPagina=10",
  "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?codigoModalidadeContratacao=8&status=todos&pagina=1&tamanhoPagina=10",
  "https://pncp.gov.br/api/pncp/v1/orgaos/00394460000141/compras?pagina=1"
)
for (pu in pncp_urls) {
  cat("Trying PNCP API:", pu, "\n")
  r_pncp <- tryCatch(req_perform(request(pu) |> req_user_agent(ua) |> req_options(ssl_verifypeer = FALSE)), error = function(e) NULL)
  if (!is.null(r_pncp)) {
    cat("Status:", resp_status(r_pncp), "\n")
    body_str <- resp_body_string(r_pncp)
    cat("Response snippet:", substr(body_str, 1, 300), "\n")
  } else {
    cat("PNCP request failed.\n")
  }
}
