source("R/helpers_utils.R")
source("R/helpers_ai.R")
library(httr2)

cfg <- get_ai_config()
prompt <- "Olá, tudo bem?"
req <- ai_make_request(prompt, cfg = cfg)

cat("Requesting to URL:", req$url, "\n")
cat("Request method:", req$method, "\n")
cat("Headers:\n")
print(req$headers)

resp <- tryCatch({
  httr2::req_perform(req)
}, error = function(e) {
  cat("\n--- ERROR DURING PERFORM ---\n")
  print(e)
  if (!is.null(e$response)) {
    cat("Response status:", resp_status(e$response), "\n")
    cat("Response body:\n")
    print(resp_body_string(e$response))
  }
  NULL
})

if (!is.null(resp)) {
  cat("\n--- RESPONSE SUCCESS ---\n")
  cat("Status:", resp_status(resp), "\n")
  cat("Body:\n")
  cat(resp_body_string(resp), "\n")
}
