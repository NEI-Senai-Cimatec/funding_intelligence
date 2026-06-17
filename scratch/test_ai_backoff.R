# scratch/test_ai_backoff.R
library(httr2)

source("R/helpers_utils.R")
source("R/helpers_ai.R")

message("Testing httr2 retry configuration...")

# Create a dummy request
req <- httr2::request("https://httpbin.org/status/429")

# Apply the retry logic
retries <- 2
req_with_retry <- req |>
  httr2::req_retry(
    max_tries = retries + 1,
    backoff = function(i) 2^i + stats::runif(1, 0, 1),
    is_transient = function(resp) {
      status <- httr2::resp_status(resp)
      status == 429 || status >= 500
    }
  )

# Verify the request object has retry attributes
message("Checking request properties:")
message("Max tries configured: ", req_with_retry$policies$retry_max_tries)

if (is.null(req_with_retry$policies$retry_max_tries) || req_with_retry$policies$retry_max_tries != 3) {
  stop("Test failed: retry_max_tries is not set correctly!")
}

# Run request and verify it retries on 429 (we can use req_perform to see it fail after retries)
message("Executing request on status/429 (will retry 3 times)...")
start_time <- Sys.time()
resp <- tryCatch({
  httr2::req_perform(req_with_retry)
}, error = function(e) e)
end_time <- Sys.time()

elapsed <- as.numeric(end_time - start_time)
message("Request finished in ", round(elapsed, 2), " seconds.")

# Since it retried with exponential backoff (2^1 + 2^2 = ~6 seconds plus jitter),
# the total elapsed time should be at least 4-5 seconds.
if (elapsed < 3) {
  stop("Test failed: Request did not backoff or retry!")
}

message("SUCCESS: Jittered exponential backoff retries verified!")
