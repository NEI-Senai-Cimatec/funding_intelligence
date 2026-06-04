# Teste de Configuração e Chamadas do Módulo Multi-Provedor de IA
source("R/helpers_utils.R")
source("R/helpers_ai.R")

message("--- TESTANDO AUTODETECÇÃO ---")

# Limpa o ambiente antes do teste
Sys.unsetenv(c("GEMINI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROQ_API_KEY", "OPENROUTER_API_KEY", "DEEPSEEK_API_KEY", "AI_PROVIDER", "AI_MODEL", "AI_API_KEY", "AI_API_URL"))

message("Caso 1: Nenhuma variável de ambiente definida")
cfg <- get_ai_config()
print(cfg)
stopifnot(!ai_available())

message("\nCaso 2: Apenas GEMINI_API_KEY definida")
Sys.setenv(GEMINI_API_KEY = "dummy_gemini_key")
cfg <- get_ai_config()
print(cfg)
stopifnot(cfg$provider == "gemini")
stopifnot(cfg$model == "gemini-1.5-flash")
stopifnot(cfg$api_key == "dummy_gemini_key")
stopifnot(ai_available())
Sys.unsetenv("GEMINI_API_KEY")

message("\nCaso 3: Apenas OPENAI_API_KEY definida")
Sys.setenv(OPENAI_API_KEY = "dummy_openai_key")
cfg <- get_ai_config()
print(cfg)
stopifnot(cfg$provider == "openai")
stopifnot(cfg$model == "gpt-4o-mini")
stopifnot(cfg$api_key == "dummy_openai_key")
stopifnot(cfg$api_url == "https://api.openai.com/v1/chat/completions")
stopifnot(ai_available())
Sys.unsetenv("OPENAI_API_KEY")

message("\nCaso 4: Provedor explicitamente customizado com Groq")
Sys.setenv(GROQ_API_KEY = "dummy_groq_key")
cfg <- get_ai_config()
print(cfg)
stopifnot(cfg$provider == "groq")
stopifnot(cfg$model == "llama-3.3-70b-versatile")
stopifnot(cfg$api_key == "dummy_groq_key")
stopifnot(cfg$api_url == "https://api.groq.com/openai/v1/chat/completions")
stopifnot(ai_available())
Sys.unsetenv("GROQ_API_KEY")

message("\nCaso 5: Customização total via AI_PROVIDER, AI_MODEL, AI_API_KEY e AI_API_URL")
Sys.setenv(
  AI_PROVIDER = "custom_openai",
  AI_MODEL = "deepseek-reasoner",
  AI_API_KEY = "my_custom_key",
  AI_API_URL = "https://api.mycustomendpoint.com/v1/chat/completions"
)
cfg <- get_ai_config()
print(cfg)
stopifnot(cfg$provider == "custom_openai")
stopifnot(cfg$model == "deepseek-reasoner")
stopifnot(cfg$api_key == "my_custom_key")
stopifnot(cfg$api_url == "https://api.mycustomendpoint.com/v1/chat/completions")
stopifnot(ai_available())
Sys.unsetenv(c("AI_PROVIDER", "AI_MODEL", "AI_API_KEY", "AI_API_URL"))

message("\n--- TODOS OS TESTES PASSARAM COM SUCESSO! ---")
