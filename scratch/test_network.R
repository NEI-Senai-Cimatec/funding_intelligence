library(httr2)

test_url <- function(url) {
  cat("Testing", url, "...\n")
  req <- request(url) |> req_timeout(10)
  resp <- tryCatch({
    req_perform(req)
  }, error = function(e) {
    cat("  Error:", e$message, "\n")
    NULL
  })
  if (!is.null(resp)) {
    cat("  Success! Status:", resp_status(resp), "\n")
  }
}

test_url("https://www.google.com")
test_url("https://api.bluesminds.com")
test_url("https://integrate.api.nvidia.com")
