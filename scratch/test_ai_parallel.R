source("R/helpers_utils.R")
source("R/helpers_ai.R")

# Habilitar carregamento de pacotes adicionais
library(httr2)
library(jsonlite)

# Verifica se a IA está disponível
if (!ai_available()) {
  stop("IA não está disponível! Verifique o arquivo .Renviron.")
}

message("Testando chamada paralela à IA...")

prompts <- list(
  "Responda apenas com a palavra 'LARANJA' em formato JSON: {\"cor\": \"LARANJA\"}",
  "Responda apenas com a palavra 'AZUL' em formato JSON: {\"cor\": \"AZUL\"}",
  "Responda apenas com a palavra 'VERDE' em formato JSON: {\"cor\": \"VERDE\"}"
)

start_time <- Sys.time()
results <- ai_request_parallel(prompts)
end_time <- Sys.time()

message(sprintf("Chamadas finalizadas em: %.2f segundos", as.numeric(end_time - start_time, units = "secs")))
print(results)
