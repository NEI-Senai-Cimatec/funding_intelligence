# collection-pipeline

## Purpose

Defines the data collection pipeline: collector dispatch, HTTP request strategies with anti-detection, rate limiting, HTML pagination, candidate extraction, detail/PDF fetching, specialized collectors for 12 funding sources, and record finalization with deduplication.

## Requirements

### Requirement: Source dispatch and collector registry
The system SHALL maintain a collector registry (`.collector_registry` environment) mapping source IDs to collector functions. `source_dispatch()` looks up the collector for a given source ID and falls back to `collect_generic_official` if no specialized collector is registered. Each collector receives `(source_row, max_pages, max_records, use_ai, log_path)` and returns `list(records, pages_visited, last_url)`.

#### Scenario: Specialized collector invocation
- **WHEN** `source_dispatch()` is called with `source_row$id_fonte == "finep"`
- **THEN** `collect_finep()` is invoked and the Liferay REST API is queried

#### Scenario: Fallback to generic collector
- **WHEN** `source_dispatch()` is called with a source ID not in the registry
- **THEN** `collect_generic_official()` is invoked with HTML pagination

### Requirement: HTTP request cascade with anti-detection
The system SHALL attempt HTTP requests in a 3-level cascade: (1) `httr2` with stealth headers (rotating User-Agent, Sec-Fetch-*, Accept-Language), (2) Playwright headless Chromium via `reticulate` with stealth plugin, (3) Chromote (R native) with JS anti-fingerprinting injections. CDN/CAPTCHA blocking is detected via regex patterns. The cascade stops at the first successful non-blocked response.

#### Scenario: Successful httr2 request
- **WHEN** the target URL returns HTML without blocking signals
- **THEN** the HTML is parsed and returned with `method = "httr2"`

#### Scenario: httr2 blocked, Playwright succeeds
- **WHEN** httr2 returns a Cloudflare challenge page
- **THEN** Playwright is launched with stealth plugin and the page is rendered

#### Scenario: All methods fail
- **WHEN** all three HTTP methods fail or detect blocking
- **THEN** a warning is logged and `ok = FALSE` is returned

### Requirement: Domain-based rate limiting
The system SHALL enforce per-domain rate limiting via `DomainRateLimiter` R6 class: 2 seconds between requests to the same domain, 0.5 seconds between requests to different domains. Configurable via `SCRAPE_DOMAIN_DELAY` and `SCRAPE_DIFF_DELAY` env vars.

#### Scenario: Same-domain throttling
- **WHEN** two requests target the same domain within 2 seconds
- **THEN** the second request sleeps until the minimum delay has elapsed

#### Scenario: Cross-domain fast path
- **WHEN** consecutive requests target different domains
- **THEN** only a 0.5-second delay is applied

### Requirement: Listing page pagination
The system SHALL navigate paginated listing pages via `collect_listing_with_pagination()` which: fetches each page via `safe_request_page()`, extracts candidate records via `extract_listing_candidates()`, follows detail links via `extract_detail_bundle()`, and stops when `max_records` is reached, `max_pages` is exceeded, or no next page is detected. Next page detection uses `rel="next"` attributes, `b_start:int` offset parameters, or regex patterns for "proximo/next".

#### Scenario: Multi-page collection
- **WHEN** a listing page has 3 pages and `max_pages=5, max_records=50`
- **THEN** all 3 pages are visited and candidates are extracted from each

#### Scenario: Offset-based pagination
- **WHEN** a listing page uses `b_start:int` parameters for pagination
- **THEN** the collector follows `b_start:int` URLs until no more results

#### Scenario: Page limit reached
- **WHEN** `max_pages=2` and the listing has 5 pages
- **THEN** only pages 1-2 are processed

#### Scenario: No next page detected
- **WHEN** a listing page has no `rel="next"` link or matching text
- **THEN** pagination stops after the current page

### Requirement: Candidate extraction from HTML
The system SHALL extract candidate records from listing pages via `extract_listing_candidates()` which: (1) parses content blocks (`article`, `.card`, `.views-row`, `.item`, `article.contenttype-document`, etc.) for titles, summaries, and links — when multiple anchors exist in a block, anchors inside heading elements (`h1, h2, h3, h4`) SHALL be preferred as the `detail_url` over generic anchors; (2) parses anchor elements directly, (3) filters candidates through `is_funding_opportunity_heuristics()`, (4) deduplicates by canonical URL. Fallback: if no candidates found, captures all PDF links as records.

#### Scenario: Block-based extraction with heading link
- **WHEN** a listing page contains `<div class="item"><h2><a href="DETAIL_URL">Title</a></h2><a href="share_url">Share</a></div>`
- **THEN** the candidate has `detail_url = DETAIL_URL`, not `share_url`

#### Scenario: Article-based extraction (Plone search results)
- **WHEN** a listing page contains `<article class="contenttype-document"><h2 class="tileHeadline"><a class="state-published" href="URL">Title</a></h2></article>`
- **THEN** the candidate has `detail_url = URL` and `title = "Title"`

#### Scenario: Heuristic filtering
- **WHEN** a candidate title matches "manual do cartão" or "perguntas frequentes"
- **THEN** the candidate is discarded by `is_funding_opportunity_heuristics()`

### Requirement: Detail page and PDF text extraction
The system SHALL fetch detail pages via `extract_detail_bundle()` which: downloads the detail URL, extracts title (h1 → og:title → title tag), subtitle, paragraph text (up to 20,000 chars), and PDF links. If a PDF URL is found, `extract_text_from_pdf()` downloads and extracts text via `pdftools::pdf_text()`.

#### Scenario: Detail page with PDF
- **WHEN** a detail URL returns HTML containing a PDF link
- **THEN** both the HTML text and PDF text are concatenated into `full_text`

#### Scenario: PDF download failure
- **WHEN** a PDF URL returns HTML/CAPTCHA instead of a PDF
- **THEN** the PDF is skipped and only HTML text is used

### Requirement: Specialized EU API collection
The system SHALL collect Horizon Europe and ERC opportunities via the EU F&T Portal Search API (`api.tech.ec.europa.eu/search-api/prod/rest/search`). Horizon Europe uses 21 search terms covering EIC, MSCA, WIDERA, CL2-CL5, EURATOM. ERC uses ERC-specific terms filtered by `programmeDivision=43108406`. Both filter for `DATASOURCE=SEDIA` (topics), `frameworkProgramme=43108390`, and status≠Closed. Dedup by `callIdentifier` prefers English versions. A Cloudflare Worker proxy is used when `EU_API_PROXY_URL` is configured.

#### Scenario: Horizon Europe multi-term search
- **WHEN** `collect_horizon_europe()` runs with `max_records=100`
- **THEN** 21 search terms are queried, results are post-filtered for HEU topics, and deduplicated by callIdentifier

#### Scenario: EU API inaccessible
- **WHEN** `is_host_alive()` returns FALSE for the EU API endpoint
- **THEN** the collector returns an empty tibble and logs a warning

### Requirement: Specialized FINEP collection via Liferay REST
The system SHALL collect FINEP opportunities via the Liferay Headless Delivery API at `/o/c/chamadapublicas`. The collector paginates through results sorted by `dataDePublicacao:desc`, filters for `situacao.key == "aberta"`, and extracts fields including temaPrincipal, regiao, tipoDeOportunidade, and contrapartida.

#### Scenario: FINEP open opportunities
- **WHEN** `collect_finep()` runs
- **THEN** only opportunities with `situacao.key == "aberta"` are returned

### Requirement: Specialized CAPES collection via Plone REST
The system SHALL collect CAPES opportunities via the Plone REST API at `/++api++/pt-br/@search`. The collector queries the `editais` path, filters for PDFs with valid titles (excluding retificações/erratas), downloads PDFs to extract real content, and falls back to Playwright if the API is unavailable.

#### Scenario: CAPES Plone API success
- **WHEN** the Plone API returns items in the editais path
- **THEN** PDF items with valid titles are processed and non-PDF/non-editais are filtered

#### Scenario: CAPES API fallback
- **WHEN** the Plone API returns an error
- **THEN** Playwright is used to render the CAPES page and extract candidates

### Requirement: Specialized SIGITEC collection via REST API
The system SHALL collect Petrobras SIGITEC opportunities via the REST API at `/v2/ms-authorization/opportunity/getAllPublicOpportunities`. The collector fetches the full listing, filters for `status == "A"` (Aberta), then fetches details for each opportunity via `/v2/ms-authorization/opportunity/public-opportunity/{id}`. Falls back to Playwright if the API fails.

#### Scenario: SIGITEC API listing
- **WHEN** `collect_sigitec()` runs and the API is accessible
- **THEN** only opportunities with status "A" are processed with detail enrichment

### Requirement: Specialized FAPESB collection via WordPress REST
The system SHALL collect FAPESB opportunities via the WordPress REST API at `/wp-json/wp/v2/posts?categories=11` (category 11 = "Aberto"). The collector paginates, cleans HTML entities from titles, extracts dates from content via regex, and builds records with the FAPESB schema.

#### Scenario: FAPESB WordPress API
- **WHEN** `collect_fapesb()` runs
- **THEN** posts from category 11 are fetched, titles are cleaned, and dates are extracted from content

### Requirement: Specialized DAAD hybrid collection
The system SHALL collect DAAD Brasil scholarships via a hybrid approach: (1) fetch `scholarships.js` from the DAAD catalog (TAFFY JS format), parse the embedded JSON array, filter by `origin=48` (Brazil), map status/intentions/subject groups via reference tables; (2) scrape individual scholarship detail pages for full descriptions. The collector filters from ~82 Brazil-specific scholarships.

#### Scenario: DAAD catalog parsing
- **WHEN** `collect_daad()` runs
- **THEN** the `scholarships.js` file is fetched, parsed, and filtered for Brazil-origin scholarships (origin contains 48)

#### Scenario: DAAD reference table mapping
- **WHEN** a scholarship has status/intentions/subjectGrps IDs
- **THEN** the IDs are resolved to human-readable names via reference tables (status.js, intentions.js, subjectgroups.js)

### Requirement: Record finalization and schema enforcement
The system SHALL finalize collected records via `finalize_records()` which: (1) enforces the 35-column schema via `ensure_record_schema()`, (2) filters through `is_funding_opportunity_heuristics()`, (3) filters through `is_current_year_record()`, (4) infers language, status, and area from text, (5) deduplicates via `dedupe_records()`, (6) derives the deadline via contextual date extraction, (7) validates deadline-year consistency and flags violations, (8) writes `date_confidence` audit warnings for inconsistent or ambiguous dates, and (9) generates the deduplication hash from `(entidade, normalized title, primary link)` — explicitly NOT from `data_limite`, so that the same notice collected on different dates still collapses to one record. EU sources (horizon_europe, erc) receive special year-filtering treatment for plurianual programs.

#### Scenario: Record passes all filters
- **WHEN** a record has a valid funding title, current-year dates, and unique entity+title
- **THEN** the record is included in the output

#### Scenario: Record filtered by heuristics
- **WHEN** a record title matches "resultado final" or "retificação"
- **THEN** the record is discarded by `is_funding_opportunity_heuristics()`

#### Scenario: EU record with future deadline
- **WHEN** a Horizon Europe record has `data_limite` in a future year
- **THEN** the record is accepted (plurianual program treatment)

#### Scenario: Same notice collected twice with different deadlines
- **WHEN** two collections of the same notice produce different `data_limite` values
- **THEN** records share the same deduplication hash and only one record is kept

#### Scenario: Inconsistent deadline-year flagged
- **WHEN** a finalized record has a 2026 title year but a 2023 deadline
- **THEN** the record is kept with the date retained and a `date_confidence` WARN audit entry is written

### Requirement: Deduplication by entity and normalized title
The system SHALL deduplicate records via `dedupe_records()` which: normalizes titles (remove accents, lowercase), prioritizes status (aberto > futuro > encerrado), breaks ties by latest deadline then longest content, and keeps one record per `(entidade, title_norm)` pair.

#### Scenario: Duplicate records from same entity
- **WHEN** two records have the same entity and normalized title but different statuses
- **THEN** the record with the more favorable status (aberto) is kept

#### Scenario: Cross-entity duplicate titles
- **WHEN** two records have different entities but the same title
- **THEN** both records are kept (dedup is per-entity)

### Requirement: Specialized Humboldt Foundation collection via HTML scraping
The system SHALL collect Alexander von Humboldt Foundation programs via HTML scraping of the listing page at `/en/apply/sponsorship-programmes/programmes-a-to-z`. The collector fetches both `filterBy=schollarships` and `filterBy=award` listing pages, parses teaser cards (`.teaser`) extracting title, "For whom", "From where", "For what" metadata, and detail URLs. Detail pages are fetched individually to extract full descriptions and status inference. Country normalization maps "Brazil" → "Brasil", "Germany" → "Alemanha", etc.

#### Scenario: Humboldt listing page parsed
- **WHEN** `collect_humboldt()` runs
- **THEN** all teaser cards from both scholarship and award listing pages are extracted and deduplicated by title

#### Scenario: Humboldt detail page with status
- **WHEN** a detail page contains "closing date has elapsed"
- **THEN** status_oportunidade is classified as "encerrado"

#### Scenario: Humboldt permanent program
- **WHEN** a detail page has no closing date or next round text
- **THEN** status_oportunidade is classified as "aberto"

### Requirement: World Bank collector registration
The system SHALL register `collect_world_bank` in the collector registry for `id_fonte = "world_bank"` and dispatch to it via `source_dispatch()`.

#### Scenario: Dispatcher invokes World Bank collector
- **WHEN** `source_dispatch()` is called with `source_row$id_fonte == "world_bank"`
- **THEN** `collect_world_bank()` is invoked with API-first collection strategy

### Requirement: World Bank collection cascade
The system SHALL attempt World Bank collection in a 3-tier cascade: (1) Procurement Notices API query, (2) Excel (calls API internally), (3) HTML scraping with Playwright. The cascade stops at the first successful non-empty result.

#### Scenario: API collection succeeds
- **WHEN** the Procurement Notices API returns valid procurement notice data
- **THEN** the records are processed and returned without attempting Excel or HTML

#### Scenario: API fails, Excel succeeds
- **WHEN** the API fails or returns empty results
- **AND** the Excel collector (via API) returns valid candidates
- **THEN** the Excel-sourced records are processed and returned

#### Scenario: API and Excel fail, HTML succeeds
- **WHEN** both API and Excel collection fail
- **AND** the HTML scraping with Playwright returns valid candidates
- **THEN** the HTML-sourced records are processed and returned

#### Scenario: All methods fail
- **WHEN** all three collection methods fail or return empty results
- **THEN** a warning is logged and an empty tibble is returned

### Requirement: World Bank source catalog entry
The system SHALL include the World Bank as a configured source in `fontes_financiamento` with: `id_fonte = "world_bank"`, `nome_fonte = "World Bank"`, `sigla = "WB"`, `pais = "Estados Unidos"`, `categoria = "organismo internacional"`, `tipo_financiador = "multilateral"`, `url_principal = "https://www.worldbank.org/"`, `url_oportunidades = "https://projects.worldbank.org/pt/projects-operations/opportunities?project_ctry_name_exact=Brazil"`, `metodo_coleta = "hybrid"`, `idioma = "pt"`, `periodicidade_atualizacao = "diaria"`.

#### Scenario: Source catalog includes World Bank
- **WHEN** `seed_sources()` is called
- **THEN** the World Bank entry is inserted via UPSERT into `fontes_financiamento`

### Requirement: World Bank field mapping to opportunity schema
The system SHALL map World Bank data (from API) to the 35-column opportunity schema with the following mappings:
- `bid_description` to `titulo`
- `project_name` to `subtitulo`
- `noticedate` to `data_publicacao`
- `submission_deadline_date` to `data_limite`
- `notice_type` to `tipo_oportunidade` and `modalidade`
- `notice_status` to `status_oportunidade`
- `notice_lang_name` to `idioma`
- `project_ctry_name` to `pais_origem`
- `id` to `link_detalhe` (constructed as procurement-detail URL)
- "World Bank" to `instituicao_financiadora`

#### Scenario: Field mapping completeness
- **WHEN** a World Bank record has all required fields
- **THEN** the record is created with all mapped fields populated

#### Scenario: Missing optional fields
- **WHEN** a World Bank record has missing optional fields
- **THEN** the field is set to NA and the record is still processed

### Requirement: JS-rendered source fallback for EU portals
The system SHALL detect EU funding portals with JavaScript/CDN-rendered content (Horizon Europe/CORDIS, EC, eureka network domains) and, when static HTML scraping yields no candidates or missing deadlines, fall back to (1) the headless rendering cascade (Playwright/Chromote) and (2) the official EU F&T / CORDIS API endpoints. A successful fallback SHALL yield records whose `data_limite` is populated instead of "-".

#### Scenario: Static scrape misses JS-rendered deadlines
- **WHEN** an EU source page renders its deadline via JavaScript and static HTML has none
- **THEN** the source is re-fetched with the headless cascade and the deadline is extracted

#### Scenario: CORDIS API fallback for research topics
- **WHEN** the EU portal is inaccessible and the CORDIS API is reachable
- **THEN** records are built from the API response with deadlines populated

### Requirement: Parallel source collection with rate limiting
The system SHALL run per-source collection jobs in parallel (future/furrr multisession, default 4 workers) while enforcing, per provider/domain, rate limits: a token-bucket limiter for AI providers (Gemini 60 RPM, Groq token budget) and existing per-domain 2s/0.5s delays on HTTP paths. Failures SHALL be isolated per source: one source error logs an ERROR entry and returns an empty result without aborting the batch.

#### Scenario: Parallel collection completes
- **WHEN** 4 independent sources are collected with 4 workers
- **THEN** all 4 are scraped concurrently and results are merged into one record set

#### Scenario: Single source failure isolation
- **WHEN** one source errors during parallel collection
- **THEN** an ERROR audit entry is written and the remaining sources still produce records

#### Scenario: Rate limit enforces per-provider budget
- **WHEN** AI calls for Gemini exceed 60 requests per minute
- **THEN** subsequent calls are queued by the token bucket until the budget replenishes

### Requirement: Background collector process loads complete helper module set
The system SHALL define a single source of truth for the helper modules required by the collection pipeline (`COLLECTOR_HELPER_FILES` in `app.R`, including `helpers_status.R`, `helpers_utils.R`, `helpers_db.R`, `helpers_text.R`, `helpers_ai.R`, `helpers_collect.R`). The background collection process (`callr::r_bg`) SHALL source exactly this list before running `collect_all_sources()`, because collectors depend on cross-module functions (e.g., `status_today()` from `helpers_status.R` used by date-extraction helpers). A missing module file SHALL abort the background job with an explicit error instead of failing collectors at runtime.

#### Scenario: Background job loads all pipeline helpers
- **WHEN** a background collection is launched via `callr::r_bg`
- **THEN** every file in `COLLECTOR_HELPER_FILES` is sourced before `collect_all_sources()` runs, including `helpers_status.R`

#### Scenario: Collector date helpers work in background process
- **WHEN** `collect_cnpq()` or `collect_capes()` runs inside the background process and reaches date extraction (e.g., `extract_dates_contextual()`, `compute_data_quality_score()`)
- **THEN** `status_today()` resolves successfully and no "could not find function" error occurs

### Requirement: Collector error transparency in dispatch
The system SHALL propagate collector errors with their real cause: `source_dispatch()` SHALL return `list(error = conditionMessage(e), source_id, records = NULL, pages_visited = 0, last_url = "")` when a collector throws, instead of returning `NULL`. `collect_all_sources()` SHALL log this message to `logs_coleta` so failures are diagnosable. Log messages SHALL collapse multi-line error text (rlang bullets like "In index: 1. Caused by error in ...") into a single line so no cause is truncated. A collector failure SHALL never be recorded with the generic message "Resultado vazio na coleta paralela" when an error message is available.

#### Scenario: Collector throws, error reaches logs_coleta
- **WHEN** a collector raises an error during parallel collection
- **THEN** the `logs_coleta` row for that source has `status_execucao = "erro"` and `mensagem` containing the actual `conditionMessage`, not "Resultado vazio na coleta paralela"

#### Scenario: Multi-line error not truncated in logs
- **WHEN** an rlang error with cause chains is written via `log_write()`
- **THEN** the log line contains the full message with newlines collapsed to " | "
