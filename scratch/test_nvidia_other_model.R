source("R/helpers_utils.R")
source("R/helpers_ai.R")
library(httr2)

test_model <- function(model_name) {
  cat("\n--- Testing Model:", model_name, "---\n")
  
  Sys.setenv(
    AI_PROVIDER = "nvidia",
    AI_MODEL = model_name,
    AI_API_KEY = Sys.getenv("NVIDIA_API_KEY")
  )
  
  cfg <- get_ai_config()
  prompt <- "Olá, tudo bem?"
  req <- ai_make_request(prompt, cfg = cfg)
  
  resp <- tryCatch({
    httr2::req_perform(req)
  }, error = function(e) {
    cat("Error:", e$message, "\n")
    NULL
  })
  
  if (!is.null(resp)) {
    cat("Success! Status:", resp_status(resp), "\n")
    cat("Body excerpt:\n", substr(resp_body_string(resp), 1, 200), "\n")
  }
}

test_model("meta/llama-3.1-8b-instruct")
test_model("nvidia/llama-3.1-nemotron-70b-instruct")
