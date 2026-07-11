# QuIIN — Baseline Specification (Current State)

**Status:** v1.0 — 2026-07-11
**Scope:** Full system snapshot — app.R, Docker, R/ helpers, data model, collection pipeline, AI integration.

---

## 1. System Overview

**QuIIN (QFunding Intelligence Hub)** is a Shiny-based application for monitoring, searching, and recommending research funding opportunities. It aggregates data from 11 configured funding sources (6 active), enriches records with generative AI, and provides a web dashboard with boolean search, adherence scoring, and partner recommendation.

### Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                   UI Layer (app.R + bslib)                  │
│   Dashboard │ Results │ Tracked │ Recommended │ Logs │ ...  │
├─────────────────────────────────────────────────────────────┤
│                   Logic Layer                               │
│   helpers_utils.R │ helpers_text.R │ helpers_recommend.R    │
├─────────────────────────────────────────────────────────────┤
│                   Data & Collection Layer                   │
│   helpers_collect.R │ helpers_db.R │ helpers_ai.R │ ...     │
├─────────────────────────────────────────────────────────────┤
│                   Persistence                               │
│   SQLite (WAL) │ Google Drive │ data_exports/               │
├─────────────────────────────────────────────────────────────┤
│                   External                                  │
│   11 Portais │ LLM APIs (8 providers) │ Playwright/Chromote │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. app.R — Application Entry Point (~1,600 lines)

### 2.1 Bootstrap & Package Management

- **Local lib strategy:** `R_libs/` directory at project root used as first `.libPaths()` entry
- **Auto-install:** Packages missing from `R_libs/` are installed from CRAN on startup (skipped on Posit Connect via `CONNECT_SERVER`/`CONNECT_API_KEY` env vars)
- **Required packages (30):** shiny, bslib, DT, dplyr, tidyr, purrr, stringr, stringi, lubridate, ggplot2, plotly, DBI, RSQLite, jsonlite, digest, htmltools, rvest, xml2, httr, httr2, tibble, tools, readr, writexl, janitor, glue, progress, pdftools, polite, callr, shinycssloaders, googledrive
- **Fail-safe:** App refuses to start if any required package is missing after install attempt

### 2.2 Helper Loading Order

```
safe_source("R/helpers_utils.R")
safe_source("R/helpers_db.R")
safe_source("R/helpers_text.R")
safe_source("R/helpers_ai.R")
safe_source("R/helpers_recommend.R")
safe_source("R/helpers_collect.R")
safe_source("R/helpers_drive.R")
```

### 2.3 Initialization Sequence

1. `drive_download_db()` — download SQLite from Google Drive (if configured)
2. `init_database()` — create tables, seed sources/profile/searches/demo data, run cleanup
3. `get_db_connection()` — open SQLite with WAL + busy_timeout=10s
4. `onStop()` — disconnect + `drive_upload_db()` sync
5. Optional: startup tests via `testthat::test_dir()` (if `RUN_STARTUP_TESTS=true`)

### 2.4 UI Structure (bslib + Bootstrap 5)

- **Theme:** `bs_theme(version=5, bootswatch="flatly", primary="#004691", secondary="#0f172a")`
- **Header:** SENAI CIMATEC logo + app title + dynamic status widget (syncing/active/synced)
- **Sidebar (320px):** 5 selectize filters (Funder, Area, Status, Type, Language) + Clear button
- **Search bar:** Boolean query input + Region radio (Ambas/Brasileiras/Europeias/Internacionais) + 4 action buttons (Search, Advanced, Save, Update Base)
- **4 Value Boxes:** Visible records, Active sources, Urgent (14 days), Last collection
- **6 Nav Panels:**
  1. **Resultados** — collection status + source counter + export status + DT table
  2. **Por financiador** — plotly chart + funder profile + funder table
  3. **Buscas salvas** — DT table
  4. **Editais rastreados** — DT table + update form + partner recommendations
  5. **Recomendados para mim** — recommended DT + profile summary + collaborators table
  6. **Logs** — DT table

### 2.5 Server — Reactive State

**Reactive values (`rv`):** opportunities, sources, saved_searches, tracked, history, profile, collaborators, logs, current_query, advanced_filters, last_collect_summary, selected_tracked_id, collecting, drive_status, bg_process, bg_start_time

**Progress tracking (`progress_rv`):** step, total, percentage, detail, phase, logs, status

### 2.6 Background Collection Process

- **Mechanism:** `callr::r_bg()` — completely separate R process
- **Prevention of concurrent runs:** `.global_scraping_active` global flag checked before launch
- **Parameter passing:** All args (source_ids, max_pages, max_records, use_ai, env vars) passed explicitly as `args` to child process
- **Status streaming:** JSON file (`collection_status.json`) + text log (`collection_modal_log.txt`) polled every 1.5s
- **Zombie prevention:** `session$onSessionEnded` kills `bg_proc_ref` if alive
- **Phase display:** "Scraping" → "IA" → "Concluído" with animated progress bar
- **Modal:** Real-time log viewer (dark theme pre block) with Minimize/Close buttons

### 2.7 Search & Filtering

- **Boolean search:** Full AST parser (AND, OR, NOT, parentheses, quoted phrases, wildcard `*`)
- **Dynamic adherence:** Score recalculated in real-time from query terms against record text fields
- **Advanced filters:** Required terms, optional terms, exclude terms, exact phrase, language, country, type, area, funder, eligibility, maturity, deadline range
- **Sidebar filters:** Applied on top of boolean search results
- **Region filter:** Brasileiras (pais=Brasil), Europeias (pais=União Europeia), Internacionais (pais!=Brasil), Ambas (Brasil ∪ União Europeia ∪ Alemanha)

### 2.8 Data Synchronization

- **On startup:** `drive_download_db()` pulls latest SQLite from Google Drive
- **After collection:** `safe_drive_upload()` pushes updated SQLite
- **On tracked/save actions:** `safe_drive_upload()` triggered
- **On app close:** `drive_upload_db()` in `onStop()`
- **Error handling:** Failures show notification, status set to "error", gracefully ignored

---

## 3. Docker Configuration

### 3.1 Dockerfile (Multi-stage Build)

**Stage 1 — Builder** (`rocker/r-ver:4.4.0`):
- Installs system deps for compilation (libcurl, libssl, libxml2, libpoppler, sqlite3, etc.)
- Installs R packages from Posit Package Manager (Ubuntu Jammy binaries)
- Validates all packages load successfully; removes `otelsdk` (protobuf conflict)

**Stage 2 — Runtime** (`rocker/r-ver:4.4.0`):
- Runtime-only system libs (libcurl4, libxml2, libpoppler-cpp9v5, etc.)
- Python 3 + pip + Playwright + playwright-stealth
- Google Chrome (for Playwright headless)
- Copies R library from builder stage
- Non-root user `shiny` for security
- Port 3838 exposed

### 3.2 docker-compose.yml

- **Service:** `funding_intelligence_app`
- **Ports:** 3838:3838
- **Volumes:** SQLite (persisted on host), logs/, data_exports/
- **Environment:** 11 AI API keys (GEMINI, BLUESMINDS, OPENAI, NVIDIA, ANTHROPIC, GROQ, OPENROUTER, DEEPSEEK) + GDrive credentials (3 vars)
- **Restart:** `unless-stopped`
- **Healthcheck:** `curl -f http://localhost:3838/` every 30s

---

## 4. helpers_collect.R — Collection Engine (~4,100 lines)

### 4.1 Pipeline Architecture

```
collect_all_sources()
  │
  ├─ For each source:
  │   ├─ source_dispatch(source_row)
  │   │   ├─ get_collector(source_id) → registry lookup
  │   │   ├─ collector$fn(source_row, max_pages, max_records, ...)
  │   │   │   ├─ [Specialized] collect_capes / collect_finep / collect_horizon_europe / ...
  │   │   │   └─ [Generic] collect_generic_official → collect_listing_with_pagination
  │   │   │       ├─ safe_request_page() (httr2 → Playwright → Chromote)
  │   │   │       ├─ extract_listing_candidates()
  │   │   │       ├─ extract_detail_bundle()
  │   │   │       └─ extract_core_record()
  │   │   └─ enrich_records_parallel() (if use_ai=TRUE)
  │   │
  │   ├─ finalize_records() → schema enforcement + heuristic filtering + dedup
  │   ├─ translate_to_pt_br() (for EU sources)
  │   ├─ upsert_opportunities() → SQLite UPSERT
  │   └─ log_collection() → audit trail
  │
  └─ save_collection_exports() → CSV + RDS + XLSX
```

### 4.2 Collector Registry

Custom collectors registered via `register_collector(source_id, fn)`. Fallback: `collect_generic_official`.

| Source ID | Collector | Strategy |
|---|---|---|
| `cnpq` | `collect_cnpq` (alias for generic) | HTML scraper with pagination |
| `capes` | `collect_capes` | Plone REST API → Playwright fallback |
| `finep` | `collect_finep` | Liferay Headless Delivery API (GET, JSON) |
| `fapesb` | `collect_fapesb` | WordPress REST API (`/wp-json/wp/v2/posts`) |
| `horizon_europe` | `collect_horizon_europe` | EU F&T Portal Search API (21 search terms) |
| `erc` | `collect_erc` | EU F&T Portal Search API (ERC-specific terms) |
| `sigitec` | `collect_sigitec` | SIGITEC REST API + detail endpoint |
| `undp` | `collect_undp` | External JS component (JSON) + HTML detail |
| `embrapii` | `collect_embrapii` | HTML scraping (transparency page) |
| `daad` | `collect_daad` | Hybrid: JSON catalog (`scholarships.js`) + HTML detail |
| `quantum` | `collect_quantum` | EU F&T Portal (keyword: "quantum") |

### 4.3 HTTP Request Cascade (`safe_request_page`)

1. **httr2** — Fast HTTP GET with stealth headers (User-Agent rotation, Sec-Fetch-*, Accept-Language)
2. **Playwright** (Python via `reticulate`) — Headless Chromium with stealth plugin, anti-fingerprinting
3. **Chromote** (R native) — Chromium DevTools Protocol with JS stealth injections

**Detection:** CDN/CAPTCHA blocking detected via regex: `attention required! | cloudflare|cf-challenge|ray id:|checking your browser|security challenge|access denied`

**Rate limiting:** `DomainRateLimiter` R6 class — 2s same-domain, 0.5s cross-domain delay. Configurable via `SCRAPE_DOMAIN_DELAY` / `SCRAPE_DIFF_DELAY`.

### 4.4 EU API Requests (`eu_api_request`)

- **Target:** `api.tech.ec.europa.eu/search-api/prod/rest/search?apiKey=SEDIA`
- **Proxy:** Optional Cloudflare Worker via `EU_API_PROXY_URL` env var
- **Fallback chain:** curl R (SSL verify=1) → curl R (SSL verify=0) → curl CLI
- **Pre-flight:** `is_host_alive()` checks DNS/reachability before collection loop

### 4.5 Record Processing Pipeline

**`extract_core_record()`:**
- Builds tibble with 35 columns matching `oportunidades` schema
- Generates `hash_deduplicacao` via xxHash64 of `titulo + link_origem`
- Generates `id_registro` as `{source_id}_{hash16}`
- Extracts dates from text (DD/MM/YYYY, YYYY-MM-DD, "DD de mês de YYYY")
- Parses monetary values (BRL, USD, EUR, GBP, CAD)
- Infers status from deadline vs today
- Infers type from text keywords

**`finalize_records()`:**
- Enforces `ensure_record_schema()` (35-column schema)
- Filters via `is_funding_opportunity_heuristics()` — 50+ URL/title patterns for non-funding content
- Filters via `is_current_year_record()` — rejects records older than current year (EU sources get special treatment for plurianual programs)
- Infers language, status, area from text
- Deduplicates via `dedupe_records()` — same entity + normalized title → keeps best (open > future > encerrado, latest date, longest content)

### 4.6 Specialized Collector Details

**CAPES (Plone REST API):**
- Endpoint: `/++api++/pt-br/@search?path=/pt-br/centrais-de-conteudo/editais`
- Filters PDFs, excludes retificações/erratas/atas
- Downloads PDF to extract real content for summary
- Fallback: Playwright HTML scraping

**FINEP (Liferay REST API):**
- Endpoint: `/o/c/chamadapublicas?sort=dataDePublicacao:desc`
- Filters by `situacao.key == "aberta"` (public/ICT targets)
- Extracts: temaPrincipal, regiao, tipoDeOportunidade, contrapartida

**Horizon Europe (EU F&T Portal):**
- 21 search terms covering EIC, MSCA, WIDERA, CL2-CL5, EURATOM
- Post-filter: `DATASOURCE=SEDIA` (topics, not projects), `frameworkProgramme=43108390`, status≠Closed
- Dedup by `callIdentifier` — prefer English version over local language
- Override: `effective_max=100` (vs default 15) for plurianual programs

**ERC (EU F&T Portal):**
- Same API as HEU, filtered by `programmeDivision=43108406` (ERC division)
- 2 search terms: "ERC AdG 2026", "ERC PoC 2026"

**SIGITEC (Petrobras):**
- Listing: `/v2/ms-authorization/opportunity/getAllPublicOpportunities`
- Detail: `/v2/ms-authorization/opportunity/public-opportunity/{id}`
- Filter: `status == "A"` (Aberta)
- Extracts: numberOP, theme/subTheme, TRL/CRL, expectedSolution
- Fallback: Playwright SPA rendering

**FAPESB (WordPress):**
- Endpoint: `/wp-json/wp/v2/posts?categories=11&per_page=10` (category 11 = "Aberto")
- Extracts dates from content via regex `DD/MM/AA(AA)`

**UNDP:**
- External JS component: `public-components.undp.org/?comp=proc_notices&cty_id_c=BRA`
- Parses JSON from JavaScript callback wrapper
- Detail HTML: `procurement-notices.undp.org/view_negotiation.cfm?nego_id=`

**EMBRAPII:**
- Static HTML scraping of transparency page (`embrapii.org.br/transparencia/`)
- Extracts from `#chamadas` section, follows detail links
- Parses schedule table for inscription dates (data_abertura/data_limite)
- Extracts PDF document links

**DAAD (Hybrid):**
- JSON catalog: `daad-brasil.org/pt/bolsas/busca/` → embedded `scholarships.js` (TAFFY format)
- Filters by `origin=48` (Brazil) — ~82 scholarships
- Reference tables: `status.js`, `intentions.js`, `subjectgroups.js`
- Per-scholarship: detail page scraped for full description

### 4.7 Deduplication Logic

**In-flight dedup (`dedupe_records`):**
- Normalizes title (remove accents, lowercase)
- Priority: aberto(1) > futuro(2) > encerrado(3) > other(4)
- Tiebreak: latest deadline → longest content
- `distinct(entidade, title_norm, .keep_all = TRUE)`

**Database-level dedup:**
- `hash_deduplicacao` column: UNIQUE constraint
- `upsert_opportunities()` uses `ON CONFLICT(id_registro) DO UPDATE`
- `cleanup_database_opportunities()` runs on startup: applies heuristics + retroactive dedup

**DAAD-specific dedup (within `finalize_records`):**
- Same as general: `entidade + title_norm` uniqueness

**EU-specific dedup (HEU/ERC):**
- Dedup by `callIdentifier` — prefer English title over local language version
- `dedup_map` keyed by call_id, stores `is_english` flag

### 4.8 AI Enrichment Pipeline

**`enrich_records_parallel()`:**
1. **Cache check:** Queries SQLite for existing `id_registro` or `hash_deduplicacao` — skips if `descricao_resumida` and `campos_inferidos_ia` are non-empty
2. **Prompt construction:** `build_extraction_prompt()` — 500+ char system prompt + text (up to 20k chars)
3. **Batch execution:** Provider-specific batch sizes (Groq: 8, OpenAI: 5, Gemini: 8, Anthropic: 3) with delays
4. **Fallback chain:** `ai_request_with_fallback()` — tries providers in priority order, circuit breaker (3 failures → 5min cooldown)
5. **Post-processing:** `skill_verify_metadata()` audit + `apply_ai_fields_to_df()` field mapping

**Fields enriched by AI:** titulo, descricao_resumida, palavras_chave, elegibilidade, area_tematica, tipo_oportunidade, status_oportunidade, idioma, data_limite, data_publicacao, observacoes, modalidade, publico_alvo, nivel_academico, data_abertura, data_encerramento, valor_financiado, moeda

**Non-edital classification:** AI can set `e_edital_fomento=false` with `motivo_descarte` — record is discarded

---

## 5. helpers_ai.R — Multi-Provider AI Integration (~870 lines)

### 5.1 Provider Auto-Detection

Priority order: `AI_PROVIDER` env → Bluesminds → Gemini → OpenAI → NVIDIA → Anthropic → Groq → OpenRouter → DeepSeek

### 5.2 Supported Providers

| Provider | Default Model | API URL |
|---|---|---|
| Bluesminds | `moonshotai/kimi-k2.6` | `api.bluesminds.com/v1/chat/completions` |
| Gemini | `gemini-1.5-flash` | `generativelanguage.googleapis.com/v1beta/models/...` |
| OpenAI | `gpt-4o-mini` | `api.openai.com/v1/chat/completions` |
| NVIDIA | `meta/llama-3.3-70b-instruct` | `integrate.api.nvidia.com/v1/chat/completions` |
| Anthropic | `claude-3-5-haiku-latest` | `api.anthropic.com/v1/messages` |
| Groq | `llama-3.3-70b-versatile` | `api.groq.com/openai/v1/chat/completions` |
| OpenRouter | `deepseek/deepseek-v4-flash` | `openrouter.ai/api/v1/chat/completions` |
| DeepSeek | `deepseek-chat` | `api.deepseek.com/v1/chat/completions` |

### 5.3 Request Pipeline

1. `ai_make_request()` — builds httr2 request per provider format (Gemini systemInstruction, OpenAI messages array, Anthropic x-api-key header)
2. `ai_request()` — executes with retry (429 Retry-After, 5xx backoff, network errors)
3. `ai_request_with_fallback()` — tries all available providers in chain order
4. Circuit breaker: 3 consecutive failures → 300s cooldown per provider

### 5.4 Prompt Engineering

**System prompt:** Senior funding curation specialist persona, producing objective/informative/specific outputs.

**Extraction prompt (`build_extraction_prompt`):**
- 18+ structured fields
- Rules: e_edital_fomento (boolean), motivo_descarte, titulo_limpo, resumo (2-3 sentences), elegibilidade, area_tematica, tipo_oportunidade, status_oportunidade, idioma, data_limite, data_publicacao, valor_financiado, moeda, modalidade, publico_alvo, nivel_academico, data_abertura, data_encerramento, palavras_chave (5-8 terms, no institution names, no generic terms), observacoes
- Context passed as JSON (current extracted fields)

**Audit prompt (`skill_verify_metadata`):**
- Validates e_edital_fomento correctness
- Rewrites poor summaries
- Filters bad keywords
- Validates date formats and eligibility specificity

### 5.5 Translation

- `translate_to_pt_br()` — uses `polyglotr::google_translate()` (no API key needed)
- Translates title + summary (first 500 chars) for non-pt records
- Handles polyglotr double-encoding on Windows
- Rate limiting: 0.3s between calls

---

## 6. helpers_db.R — Data Layer (~720 lines)

### 6.1 SQLite Configuration

- **WAL mode:** `PRAGMA journal_mode = WAL` (concurrent reads during writes)
- **Busy timeout:** 10s (`PRAGMA busy_timeout = 10000`)
- **Encoding:** UTF-8

### 6.2 Schema (11 Tables)

| Table | Purpose | Key Fields |
|---|---|---|
| `fontes_financiamento` | Source catalog (11 rows) | `id_fonte` PK |
| `oportunidades` | Collected opportunities | `id_registro` PK, `hash_deduplicacao` UNIQUE |
| `buscas_salvas` | Saved searches | `id` AUTOINCREMENT |
| `editais_rastreados` | Tracked opportunities | `id_oportunidade` UNIQUE |
| `perfil_usuario` | User profile | `id` (always 1) |
| `historico_buscas` | Search history | `id` AUTOINCREMENT |
| `colaboradores` | Potential partners | `id` AUTOINCREMENT |
| `pesquisadores_vencedores` | CIMATEC researchers | `id` AUTOINCREMENT |
| `projetos_aprovados` | Research projects | `id` AUTOINCREMENT, FK→pesquisadores |
| `logs_coleta` | Collection audit trail | `id` AUTOINCREMENT |
| `metrics_coleta` | Performance metrics | `id` AUTOINCREMENT |

### 6.3 Source Catalog (11 sources, 6 active)

| ID | Name | Country | Method | Language |
|---|---|---|---|---|
| `cnpq` | CNPq | Brasil | HTML | pt |
| `capes` | CAPES | Brasil | Plone API | pt |
| `finep` | FINEP | Brasil | Liferay REST | pt |
| `fapesb` | FAPESB | Brasil | WordPress REST | pt |
| `horizon_europe` | Horizon Europe | EU | EU FTOP REST | en |
| `erc` | ERC | EU | EU FTOP REST | en |
| `sigitec` | Petrobras SIGITEC | Brasil | REST API | pt |
| `undp` | UNDP Brasil | Brasil | JS component | pt |
| `embrapii` | EMBRAPII | Brasil | HTML | pt |
| `daad` | DAAD Brasil | Alemanha | Hybrid JSON+HTML | en |
| `quantum` | EU Quantum | EU | EU FTOP REST | en |

### 6.4 Seed Data

- **Profile:** SENAI CIMATEC — quantum technologies focus (communication, sensors, computing)
- **Saved searches:** "Tecnologias quânticas" + "Comunicação, sensores e computação quântica"
- **Collaborators:** 3 demo entries (UFES, TU Berlin, USP)
- **Researchers:** 5 CIMATEC researchers with expertise areas
- **Projects:** 6 approved projects linked to researchers
- **Demo opportunities:** 2 seed records (CNPq + Horizon Europe)

### 6.5 Key Operations

- `upsert_opportunities()` — row-by-row UPSERT with `ON CONFLICT(id_registro) DO UPDATE`, wrapped in transaction
- `cleanup_database_opportunities()` — applies `is_funding_opportunity_heuristics()` + retroactive dedup on startup
- `migrate_existing_keywords()` — recalculates keywords for non-IA-enriched records

---

## 7. helpers_text.R — Boolean Search Engine (~300 lines)

### 7.1 Parser

- **Lexer:** Tokenizes AND, OR, NOT, parentheses, quoted phrases, wildcard `*`
- **Implicit AND:** Inserted between adjacent terms (e.g., `quantum sensors` → `quantum AND sensors`)
- **AST:** Recursive descent parser producing tree with nodes: TERM, AND, OR, NOT

### 7.2 Evaluator

- `evaluate_boolean_ast()` — recursively evaluates AST against normalized text
- Text columns searched: titulo, subtitulo, descricao_resumida, descricao_completa, palavras_chave, area_tematica, elegibilidade
- Term matching: word boundary regex with wildcard support

### 7.3 Structured Filters

Applied after boolean search: idioma, pais_origem, tipo_oportunidade, area_tematica, entidade, elegibilidade (substring), valor_financiado (range), data_limite (range)

---

## 8. helpers_recommend.R — Recommendation Engine (~155 lines)

### 8.1 Adherence Score

Weighted formula (0-100):
- **Keywords (40%):** Match between record text + query terms vs user profile keywords + history + tracked
- **Area themes (20%):** Record area/palavras_chave vs profile areas + tracked areas
- **Funder (15%):** Record entity in profile funders list
- **Country (10%):** Record country in profile countries
- **Eligibility (15%):** Record eligibility vs profile eligibility terms

### 8.2 Partner Recommendation

- Matches tracked opportunity text against `pesquisadores_vencedores` expertise + `projetos_aprovados` keywords
- Returns top-N researchers sorted by affinity score

### 8.3 Collaborator Discovery

- Matches interest signature against `colaboradores` table
- Keyword overlap scoring on nome + instituicao + area + palavras_chave

---

## 9. helpers_drive.R — Google Drive Sync (~95 lines)

- **Auth:** Service Account via `GDRIVE_SERVICE_ACCOUNT_JSON` (file path) or `GDRIVE_SERVICE_ACCOUNT_CONTENT` (inline JSON)
- **Download:** On app startup — `drive_download(file=GDRIVE_FILE_ID, overwrite=TRUE)`
- **Upload:** After collection + on tracked/save + on app close — `drive_update(file=GDRIVE_FILE_ID, media=db_path)`
- **Graceful degradation:** All operations wrapped in tryCatch, failures logged but don't block app

---

## 10. helpers_utils.R — Utility Functions (~830 lines)

### 10.1 Key Utilities

- `%||%` — Null-coalescing with empty/NA/function handling
- `normalize_text()` — Latin-ASCII transliteration, lowercase, whitespace normalization
- `parse_date_safe()` — Multi-format date parsing (YMD, DMY, MDY)
- `classify_status()` — Status inference from deadline vs today + text heuristics
- `infer_language_simple()` — Language detection via keyword patterns (pt/en/es)
- `infer_type_from_text()` — Type classification (bolsa/subvenção/chamada/grant/prêmio/edital)
- `extract_keywords_simple()` — TF-based keyword extraction with 150+ stopword list
- `calculate_dynamic_adherence()` — Real-time score from query terms vs record text

### 10.2 Scraping Utilities

- `.USER_AGENTS` — Pool of 8 browser User-Agent strings
- `build_scrape_headers()` — Full browser-like header set
- `DomainRateLimiter` R6 class — Per-domain rate limiting
- `safe_request_page()` — HTTP cascade with anti-detection
- `extract_pdf_links()`, `extract_candidate_links()`, `extract_listing_candidates()` — HTML parsing

### 10.3 AI Field Mapping

- `fill_ai_field()` — Modifies dataframe via `<<-` (pass-by-reference pattern)
- `apply_ai_fields_to_df()` — Maps 17+ AI output fields to record schema

---

## 11. Data Flow Summary

```
User clicks "Atualizar base"
  │
  ├─ Modal opens → callr::r_bg() launched
  │
  ├─ Child process:
  │   ├─ For each source (11):
  │   │   ├─ source_dispatch() → specialized collector
  │   │   ├─ HTTP requests (httr2 → Playwright → Chromote)
  │   │   ├─ HTML/API parsing → candidate extraction
  │   │   ├─ Detail page following → full text extraction
  │   │   ├─ PDF download → text extraction (pdftools)
  │   │   ├─ extract_core_record() → 35-field tibble
  │   │   ├─ finalize_records() → schema + heuristics + dedup
  │   │   ├─ [EU only] translate_to_pt_br()
  │   │   ├─ [if AI] enrich_records_parallel() → batch AI calls
  │   │   └─ upsert_opportunities() → SQLite UPSERT
  │   │
  │   ├─ save_collection_exports() → CSV + RDS + XLSX
  │   └─ Write status JSON → "done"
  │
  ├─ Parent polls status file every 1.5s
  │   ├─ Updates progress bar + log viewer
  │   └─ On "done": refresh_data() + safe_drive_upload()
  │
  └─ UI renders updated DT table
```

---

## 12. Business Rules Implemented

### 12.1 Record Validation (`is_funding_opportunity_heuristics`)

**URL-based discard:** `/noticias`, `/tv-`, `/video`, `/membros`, `/regulamentos`, `/como-usar`, `/archive`, `/privacidade`, `/lgpd`, `/contatos`, `/faq`, `/documentos`, `/institucional`, `retificacao`, `prorrogacao`, `aditivo`, `errata`, `gabarito`, `homologacao`, `anexo`

**Title-based discard:** `manual do cartao`, `cobranca administrativa`, `carta de servico`, `mapa de fomento`, `bolsas e projetos vigentes`, `acesso a informacao`, `lgpd`, `noticias`, `sobre a finep`, `faq`, `quem somos`, `tutorial`, `privacidade`, `retificacao`, `prorrogacao`, `resultado final`, `resultado preliminar`

**Special rules:** Alterations only kept if climate-related; results only kept if "resultado-recursos"; e-books/reports discarded; navigation-only links discarded

### 12.2 Year Filtering (`is_current_year_record`)

- Non-EU sources: `data_publicacao` year must equal current year
- EU sources (HEU/ERC): more lenient — accept if deadline ≥ current year, or if year mentioned in text
- Fallback: reject if only past years (5-year window) mentioned

### 12.3 Status Classification (`classify_status`)

- deadline < today → `encerrado`
- deadline ≤ today+14 → `encerrando`
- start > today → `em breve`
- Otherwise → `aberto`
- Text fallback: patterns for "encerrad/closed", "open/abert", "coming soon"

### 12.4 DAAD Dedup

- Part of general `dedupe_records()`: `entidade + title_norm` uniqueness
- Priority: open > future > encerrado
- Tiebreak: latest deadline → longest content

### 12.5 EU Source Override

- `effective_max = 100` (vs default 15) for horizon_europe, erc, quantum
- Post-filter: DATASOURCE=SEDIA (topics only), frameworkProgramme=43108390, status≠Closed
- Dedup by callIdentifier (prefer English)
- Plurianual treatment in `is_current_year_record()`

---

## 13. Environment Variables

### IA Keys (at least one required)
`BLUESMINDS_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`, `NVIDIA_API_KEY`, `ANTHROPIC_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`, `DEEPSEEK_API_KEY`

### IA Configuration (optional)
`AI_PROVIDER`, `AI_MODEL`, `AI_API_KEY`, `AI_API_URL`, `AI_MAX_CHARS`, `AI_VERIFY_METADATA`, `AI_BATCH_SIZE`, `AI_DELAY_BETWEEN_BATCHES`, `AI_TRANSLATE_EU`

### Google Drive
`GDRIVE_SERVICE_ACCOUNT_JSON`, `GDRIVE_SERVICE_ACCOUNT_CONTENT`, `GDRIVE_FILE_ID`

### EU Proxy
`EU_API_PROXY_URL`

### Scraping Tuning
`SCRAPE_DOMAIN_DELAY`, `SCRAPE_DIFF_DELAY`, `CHROMOTE_MAX_WAIT`, `CHROMOTE_MIN_WAIT`, `CHROMOTE_CHECK_INTERVAL`

### Operational
`RUN_STARTUP_TESTS`

---

## 14. Testing Infrastructure

- **Framework:** testthat
- **Test files:** `tests/testthat/test-utils.R`
- **Startup tests:** Conditional via `RUN_STARTUP_TESTS=true`
- **Scratch tests:** 30+ manual test scripts in `scratch/` for API testing, AI backoff, stealth, DB concurrency, enrichment, etc.

---

## 15. Known Limitations & Technical Debt

1. **No automated test suite** — only 1 test file for utils; no integration tests for collection/AI
2. **Global state dependency** — `.GlobalEnv$.global_scraping_active` flag for inter-process coordination
3. **Pass-by-reference via `<<-`** — `fill_ai_field()` and `apply_ai_fields_to_df()` mutate parent scope
4. **No connection pooling** — single SQLite connection per process; relies on WAL mode
5. **Single-user design** — no multi-user session management
6. **Hardcoded source catalog** — adding new sources requires code changes
7. **No structured error recovery** — failed sources logged but not retried
8. **Playwright dependency** — requires Python 3 + Chromium binary in Docker image
