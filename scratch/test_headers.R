library(httr2)

url <- "https://sigitec-competitividade.petrobras.com.br/v2/ms-authorization/opportunity/getAllPublicOpportunities"
cat("Testing with custom browser-like headers...\n")

req <- request(url) |>
  req_headers(
    `Host` = "sigitec-competitividade.petrobras.com.br",
    `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    `Accept` = "application/json, text/plain, */*",
    `Accept-Language` = "pt-BR,pt;q=0.9,en;q=0.8",
    `Referer` = "https://sigitec-competitividade.petrobras.com.br/v2/public/opportunities",
    `Origin` = "https://sigitec-competitividade.petrobras.com.br",
    `Connection` = "keep-alive"
  ) |>
  req_timeout(20)

resp <- tryCatch(req_perform(req), error = function(e) e)
if (inherits(resp, "error")) {
  cat("Error:", conditionMessage(resp), "\n")
} else {
  cat("Success! Status:", resp_status(resp), "\n")
  body <- resp_body_string(resp)
  cat("Body snippet:", substr(body, 1, 1000), "\n")
}
