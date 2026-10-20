source("R/helpers_utils.R")
source("R/helpers_ai.R")
library(httr2)

# Set environment variables for the test
Sys.setenv(
  AI_PROVIDER = "bluesminds",
  AI_API_KEY = Sys.getenv("BLUESMINDS_API_KEY_BACKUP"),
  AI_MODEL = "moonshotai/kimi-k2.6"
)

cfg <- get_ai_config()
message(sprintf("Testing Provider: %s | Model: %s", cfg$provider, cfg$model))

prompt <- "Diga Olá!"
res <- ai_request(prompt)
message("\n--- RESPONSE ---")
print(res)
