# ai-integration

## Purpose

Defines the multi-provider AI integration: provider configuration and auto-detection, fallback chain with circuit breaker, extraction prompts, metadata audit, batch processing, enrichment caching, field mapping, EU translation, and request retry with backoff.

## Requirements

### Requirement: Multi-provider AI configuration
The system SHALL support 8 AI providers: Bluesminds, Gemini, OpenAI, NVIDIA, Anthropic, Groq, OpenRouter, DeepSeek. Provider is auto-detected from available API keys in priority order, or forced via `AI_PROVIDER` env var. Each provider has a default model and API URL. The active provider configuration is resolved by `get_ai_config()`.

#### Scenario: Auto-detection from API keys
- **WHEN** only `GROQ_API_KEY` is set
- **THEN** provider is "groq" with model "llama-3.3-70b-versatile"

#### Scenario: Forced provider
- **WHEN** `AI_PROVIDER=gemini` is set along with `GEMINI_API_KEY`
- **THEN** provider is "gemini" regardless of other available keys

### Requirement: Provider fallback chain with circuit breaker
The system SHALL implement automatic fallback across providers via `ai_request_with_fallback()`. The fallback order is: groq → openai → gemini → anthropic → nvidia → deepseek → openrouter → bluesminds. Each provider has a circuit breaker: 3 consecutive failures trigger a 300-second cooldown. On successful request, the provider's failure count is reset.

#### Scenario: Primary provider fails, fallback succeeds
- **WHEN** Groq returns 429 and OpenAI returns 200
- **THEN** the OpenAI response is used and Groq failure is recorded

#### Scenario: Circuit breaker activates
- **WHEN** a provider fails 3 times consecutively
- **THEN** that provider is skipped for 300 seconds

#### Scenario: All providers fail
- **WHEN** all providers in the chain are unavailable or in cooldown
- **THEN** `NULL` is returned and a warning is logged

### Requirement: AI extraction prompt with structured output
The system SHALL send extraction prompts via `build_extraction_prompt()` which requests a JSON response with 18+ fields: e_edital_fomento (boolean), motivo_descarte, titulo_limpo, resumo (2-3 sentences), elegibilidade, area_tematica, tipo_oportunidade, status_oportunidade, idioma, data_limite, data_publicacao, valor_financiado, moeda, modalidade, publico_alvo, nivel_academico, data_abertura, data_encerramento, palavras_chave (5-8 terms), observacoes. The system prompt establishes a senior funding curation specialist persona.

#### Scenario: Valid extraction response
- **WHEN** a funding opportunity text is sent to the AI
- **THEN** a JSON response with all required fields is returned

#### Scenario: Non-edital classification
- **WHEN** the AI determines text is not a funding opportunity
- **THEN** `e_edital_fomento` is `false` and `motivo_descarte` contains the reason

### Requirement: AI metadata audit and verification
The system SHALL optionally verify AI extraction results via `skill_verify_metadata()` (controlled by `AI_VERIFY_METADATA` env var, default true). The audit checks: e_edital_fomento correctness, resumo quality (no raw text copies), palavras_chave validity (no institution names, no generic terms), data_limite format, elegibilidade specificity.

#### Scenario: Audit improves poor summary
- **WHEN** the extracted resumo is a copy of the raw text
- **THEN** the audit rewrites it as a concise 2-3 sentence summary

#### Scenario: Audit filters bad keywords
- **WHEN** palavras_chave contains "CNPq" or "edital"
- **THEN** the audit replaces them with domain-specific terms

### Requirement: Batch processing with provider-specific limits
The system SHALL process AI enrichment requests in batches via `enrich_records_parallel()` with provider-specific batch sizes: Groq=8, OpenAI=5, Gemini=8, Anthropic=3, Bluesminds=5, NVIDIA=5, OpenRouter=5, DeepSeek=5. Configurable via `AI_BATCH_SIZE` env var. Delays between batches: Groq=6s, others=1-3s. Configurable via `AI_DELAY_BETWEEN_BATCHES`.

#### Scenario: Batch processing with Groq
- **WHEN** 20 records need enrichment with Groq provider
- **THEN** records are processed in batches of 8 with 6-second delays between batches

#### Scenario: Custom batch size
- **WHEN** `AI_BATCH_SIZE=10` is set
- **THEN** all providers use batch size 10

### Requirement: AI enrichment cache via database
The system SHALL cache AI enrichment results in the database. Before enriching a record, `enrich_records_parallel()` checks if the record exists in `oportunidades` with non-empty `descricao_resumida` and `campos_inferidos_ia`. Cached records are loaded from the database instead of re-querying the AI.

#### Scenario: Cache hit
- **WHEN** a record's `id_registro` exists in the database with `campos_inferidos_ia` populated
- **THEN** the AI is not queried and the cached version is used

#### Scenario: Cache miss
- **WHEN** a record's `id_registro` does not exist in the database
- **THEN** the AI is queried and the result is stored

### Requirement: AI field mapping to record schema
The system SHALL map AI extraction results to the 35-column record schema via `apply_ai_fields_to_df()` which fills 17+ fields: titulo, descricao_resumida, palavras_chave, elegibilidade, area_tematica, tipo_oportunidade, status_oportunidade, idioma, data_limite, data_publicacao, observacoes, modalidade, publico_alvo, nivel_academico, data_abertura, data_encerramento, valor_financiado, moeda. Fields are only overwritten if the AI value is non-empty.

#### Scenario: AI enriches empty fields
- **WHEN** a record has `area_tematica = NA` and the AI returns `area_tematica = "Saúde"`
- **THEN** the field is updated to "Saúde" and added to `campos_inferidos_ia`

#### Scenario: AI preserves existing fields
- **WHEN** a record has `area_tematica = "Energia"` and the AI returns `area_tematica = "Saúde"`
- **THEN** the field is updated to "Saúde" (AI overwrites with overwrite=TRUE for this field)

### Requirement: EU record translation to Portuguese
The system SHALL translate titles and summaries of EU source records (horizon_europe, erc) to Portuguese via `translate_to_pt_br()` using `polyglotr::google_translate()`. Translation is applied to non-`pt` records. Rate limited to 0.3s between calls. Controlled by `AI_TRANSLATE_EU` env var (default true).

#### Scenario: EU record translated
- **WHEN** a Horizon Europe record has `idioma = "en"`
- **THEN** the title and summary are translated to Portuguese and `idioma` is updated to "pt"

#### Scenario: Translation disabled
- **WHEN** `AI_TRANSLATE_EU=false`
- **THEN** EU records are not translated

### Requirement: AI request retry with exponential backoff
The system SHALL retry failed AI requests via `ai_request()` with: manual retry up to `retries` times (default 2), exponential backoff with jitter (`2^attempt + runif(0,1)`), 429 responses respected with `Retry-After` header, 5xx responses retried with backoff.

#### Scenario: Rate limit retry
- **WHEN** an AI request returns 429 with `Retry-After: 5`
- **THEN** the request is retried after 5 seconds

#### Scenario: Server error retry
- **WHEN** an AI request returns 500
- **THEN** the request is retried after an exponential backoff delay
