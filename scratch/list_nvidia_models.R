library(httr2)
library(jsonlite)

api_key <- Sys.getenv("NVIDIA_API_KEY")
url <- "https://integrate.api.nvidia.com/v1/models"

req <- request(url) |>
  req_headers(
    `Authorization` = sprintf("Bearer %s", api_key)
  ) |>
  req_timeout(30)

resp <- tryCatch({
  req_perform(req)
}, error = function(e) {
  cat("Error performing request:", e$message, "\n")
  if (!is.null(e$response)) {
    cat("Status code:", resp_status(e$response), "\n")
    cat("Body:\n", resp_body_string(e$response), "\n")
  }
  NULL
})

if (!is.null(resp)) {
  txt <- resp_body_string(resp)
  parsed <- fromJSON(txt)
  message("Available Nvidia Models:")
  print(parsed$data$id)
}
