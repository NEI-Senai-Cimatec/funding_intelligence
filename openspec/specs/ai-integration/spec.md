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
The system SHALL send extraction prompts via `build_extraction_prompt()` which requests a JSON response with fields: `titulo_limpo`, `resumo` (max 3 sentences), `elegibilidade`, `area_tematica`, `tipo_oportunidade` (enum edital/chamada/grant/fellowship/bolsa/subvencao/premio/licitacao), `idioma` (enum pt/en/es), `data_limite`, `data_publicacao`, `valor_estimado` (number), `moeda` (enum BRL/USD/EUR/GBP/CAD), `palavras_chave` (exactly 5 domain-specific terms), `observacoes`, and a `confianca` object with 0.0-1.0 per-field confidence. The prompt SHALL explicitly forbid returning status fields (the system derives status by temporal rule), forbid fabricated values (no evidence → null), forbid year/number/agency-name tokens in keywords, and include an auto-audit narrative. Few-shot example with a real edital excerpt SHALL be embedded.

#### Scenario: Valid extraction response
- **WHEN** a funding opportunity text is sent to the AI
- **THEN** a JSON response with all required fields is returned

#### Scenario: AI attempts to return status
- **WHEN** the model returns a `status_oportunidade` field
- **THEN** the field is discarded by validation and status remains system-derived

#### Scenario: Keywords without semantic value
- **WHEN** `palavras_chave` contains years like "2026" or agency names like "CNPq"
- **THEN** those tokens are removed and replaced by domain-specific terms

#### Scenario: Non-edital classification
- **WHEN** the AI determines text is not a funding opportunity
- **THEN** an explicit discard indicator is returned along with `motivo_descarte` containing the reason

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
The system SHALL map AI extraction results to the record schema via `apply_ai_fields_to_df()` which fills fields including: titulo, descricao_resumida, palavras_chave, elegibilidade, area_tematica, tipo_oportunidade, idioma, data_limite, data_publicacao, observacoes, valor_financiado, moeda. Fields are only overwritten if the AI value is non-empty. The AI SHALL NEVER write `status_oportunidade`; status remains derived by temporal rule.

#### Scenario: AI enriches empty fields
- **WHEN** a record has `area_tematica = NA` and the AI returns `area_tematica = "Saúde"`
- **THEN** the field is updated to "Saúde" and added to `campos_inferidos_ia`

#### Scenario: AI supplies estimated value
- **WHEN** the AI returns `valor_estimado = 2000000` and `moeda = "BRL"`
- **THEN** `valor_financiado` is set to 2000000 and `moeda` to "BRL" on empty fields

#### Scenario: AI status ignored
- **WHEN** the AI returns a non-empty `status_oportunidade`
- **THEN** the record's status column is NOT modified by AI output

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
The system SHALL retry failed AI requests via `ai_request()` with: manual retry up to `retries` times (default 2), exponential backoff with jitter (`2^attempt + runif(0,1)`), 429 responses respected with `Retry-After` header, 5xx responses retried with backoff. Enrichment calls additionally follow the enrichment pipeline strategy (up to 3 attempts with `2^attempt` second sleeps) before falling back to heuristics.

#### Scenario: Rate limit retry
- **WHEN** an AI request returns 429 with `Retry-After: 5`
- **THEN** the request is retried after 5 seconds

#### Scenario: Server error retry
- **WHEN** an AI request returns 500
- **THEN** the request is retried after an exponential backoff delay

### Requirement: AI output schema validation
The system SHALL validate every AI JSON response before applying it via `validate_ai_schema()` which checks: required fields present, `tipo_oportunidade`/`idioma`/`moeda` within enum values, `palavras_chave` exactly 5 items, no year-only / numeric / agency-acronym tokens in keywords, and a no-fabrication audit. Invalid fields SHALL be nulled (forcing heuristic fallback) and the concrete validation error SHALL be recorded in the audit trail.

#### Scenario: Invalid keyword count rejected
- **WHEN** the AI returns `palavras_chave` with 4 items
- **THEN** validation reports "palavras_chave deve ter 5 itens" and the field is rejected

#### Scenario: Year tokens stripped from keywords
- **WHEN** `palavras_chave` contains "2026"
- **THEN** the token is removed from the keyword list

### Requirement: Resilient enrichment pipeline with heuristic fallback
The system SHALL enrich records via a resilient pipeline: (1) attempt AI extraction up to 3 times with exponential backoff, (2) on persistent failure or empty result mark the record `enrichment_status = "falha"` and apply a required heuristic fallback that fills empty `tipo_oportunidade`, `idioma`, `area_tematica`, `data_limite`, `palavras_chave` and other inferable fields from text heuristics, (3) on success mark the record `enrichment_status = "ok"` and record the used model, (4) always persist provenance (`enrichment_model`, `enrichment_at`, `enrichment_error`) and audit log entries naming the source of every recovered field. The UI SHALL signal both outcomes to the user; silent empty coverage is never allowed.

#### Scenario: AI offline, heuristic fallback applied
- **WHEN** no AI provider is available
- **THEN** the record keeps `enrichment_status = "falha"` and inherits inferred type/language/date from text heuristics, with a WARN audit entry

#### Scenario: Transient failure then success
- **WHEN** the first 2 AI attempts fail and the 3rd succeeds
- **THEN** `enrichment_status = "ok"` and AI fields are applied

#### Scenario: Provenance recorded
- **WHEN** enrichment completes with any outcome
- **THEN** `enrichment_at` is set to the completion timestamp and `enrichment_error` carries the failure detail (or is empty on success)

### Requirement: Enrichment prompt input trimming preserving deadline windows
The system SHALL trim texts longer than the AI input limit by keeping the header (first 4k chars), at most 12k chars total composed of header + ±120-char windows around deadline/budget keywords ("prazo", "deadline", "submiss", "valor", "orçamento", "budget") + the last 2k chars, so deadlines frequently located at the end of PDFs survive the truncation.

#### Scenario: Deadline at the end of a long text
- **WHEN** a 50k-char text has its deadline in the final 2k chars
- **THEN** the trimmed prompt still contains the deadline text

#### Scenario: Truncation length cap respected
- **WHEN** the assembled window text still exceeds the input limit
- **THEN** the result is capped to the input limit

### Requirement: AI API key transport security
The system SHALL send API credentials only via HTTP headers (e.g., `x-goog-api-key` for Gemini, `Authorization` for OpenAI/Anthropic/Groq/OpenRouter/DeepSeek/NVIDIA). API keys SHALL NEVER appear in request URLs, logs, or persisted audit records.

#### Scenario: Gemini key in header
- **WHEN** the active provider is Gemini
- **THEN** the request carries the key as `x-goog-api-key` header and no `?key=` query parameter

#### Scenario: No key leakage in logs
- **WHEN** a request fails and is audited
- **THEN** the audit record contains no API key material
