# Test exact Sigitec API endpoint
library(httr2)

url <- "https://sigitec-competitividade.petrobras.com.br/v2/ms-authorization/opportunity/getAllPublicOpportunities"
cat("Testing API URL:", url, "\n")
req <- request(url) |>
  req_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") |>
  req_timeout(15)

resp <- tryCatch(req_perform(req), error = function(e) e)
if (inherits(resp, "error")) {
  cat("Error:", conditionMessage(resp), "\n")
  if (!is.null(resp$response)) {
    cat("Status:", resp_status(resp$response), "\n")
    cat("Body:", resp_body_string(resp$response), "\n")
  }
} else {
  cat("Success! Status:", resp_status(resp), "\n")
  body <- resp_body_string(resp)
  cat("Body snippet:", substr(body, 1, 2000), "\n")
}
