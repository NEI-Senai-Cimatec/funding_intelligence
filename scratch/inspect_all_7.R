library(rvest)
library(httr2)
library(dplyr)

ua <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 1. BNB FUNDECI
cat("\n=================== 1. BNB FUNDECI ===================\n")
r_bnb <- request("https://www.bnb.gov.br/ConveniosWeb/Convenente.ProgramaConvenio.Lista.aspx") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE, followlocation = TRUE) |>
  req_perform()
html_bnb <- resp_body_html(r_bnb)
tables_bnb <- html_elements(html_bnb, "table")
cat("BNB tables count:", length(tables_bnb), "\n")
if (length(tables_bnb) > 0) {
  for (tb in tables_bnb) {
    df_tb <- tryCatch(html_table(tb), error = function(e) NULL)
    if (!is.null(df_tb)) print(head(df_tb, 10))
  }
}
links_bnb <- html_elements(html_bnb, "a[href]")
for (l in links_bnb) {
  txt <- html_text(l, trim = TRUE)
  hr <- html_attr(l, "href")
  if (nchar(txt) > 5) cat("BNB LINK:", txt, "==>", hr, "\n")
}

# 2. FAB DCTA
cat("\n=================== 2. FAB DCTA ===================\n")
r_dcta <- request("https://ieav.dcta.mil.br/index.php/editais") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE, followlocation = TRUE) |>
  req_perform()
html_dcta <- resp_body_html(r_dcta)
links_dcta <- html_elements(html_dcta, ".item-page a, article a, .content a, td a, p a")
cat("DCTA content links count:", length(links_dcta), "\n")
for (l in head(links_dcta, 20)) {
  txt <- html_text(l, trim = TRUE)
  hr <- html_attr(l, "href")
  cat("DCTA LINK:", txt, "==>", hr, "\n")
}

# 3. AEB
cat("\n=================== 3. AEB ===================\n")
r_aeb <- request("https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE, followlocation = TRUE) |>
  req_perform()
html_aeb <- resp_body_html(r_aeb)
nodes_aeb <- html_elements(html_aeb, ".tileItem, article, .hentry, #content a, div.item a")
cat("AEB content nodes count:", length(nodes_aeb), "\n")
for (n in head(nodes_aeb, 20)) {
  txt <- html_text(n, trim = TRUE)
  hr <- html_attr(n, "href") %||% html_attr(html_element(n, "a"), "href")
  if (!is.null(txt) && nchar(txt) > 5) cat("AEB NODE:", substr(gsub("\\s+", " ", txt), 1, 100), "==>", hr, "\n")
}

# 4. PNCP for SUDENE
cat("\n=================== 4. PNCP API FOR SUDENE ===================\n")
# Try PNCP v1 search endpoints
pncp_endpoints <- c(
  "https://pncp.gov.br/api/pncp/v1/orgaos/04017002000180/contratacoes?pagina=1",
  "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?codigoModalidadeContratacao=8&status=todos&pagina=1",
  "https://pncp.gov.br/api/pncp/v1/contratacoes/publicas?q=533014",
  "https://pncp.gov.br/api/search/?q=533014",
  "https://pncp.gov.br/api/search/v1/contratacoes?q=533014",
  "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?q=SUDENE&pagina=1"
)
for (pe in pncp_endpoints) {
  r_p <- tryCatch(
    request(pe) |> req_user_agent(ua) |> req_options(ssl_verifypeer = FALSE) |> req_perform(),
    error = function(e) e
  )
  if (inherits(r_p, "httr2_response")) {
    cat("PNCP SUCCESS:", pe, "| Status:", resp_status(r_p), "\n")
    cat("Body:", substr(resp_body_string(r_p), 1, 300), "\n")
  } else {
    cat("PNCP FAIL:", pe, "| Error:", conditionMessage(r_p), "\n")
  }
}

# 5. DOE ASCR
cat("\n=================== 5. DOE ASCR ===================\n")
r_ascr <- request("https://science.osti.gov/ascr/Funding-Opportunities") |>
  req_user_agent(ua) |>
  req_options(ssl_verifypeer = FALSE, followlocation = TRUE) |>
  req_perform()
html_ascr <- resp_body_html(r_ascr)
cat("DOE ASCR text summary:\n")
p_nodes <- html_elements(html_ascr, "p, li, h2, h3")
p_txts <- html_text(p_nodes, trim = TRUE)
p_txts <- p_txts[nchar(p_txts) > 15]
for (t in head(p_txts, 15)) {
  cat("- ", substr(gsub("\\s+", " ", t), 1, 120), "\n")
}
