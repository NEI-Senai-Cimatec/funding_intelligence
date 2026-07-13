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
The system SHALL finalize collected records via `finalize_records()` which: (1) enforces the 35-column schema via `ensure_record_schema()`, (2) filters through `is_funding_opportunity_heuristics()`, (3) filters through `is_current_year_record()`, (4) infers language, status, and area from text, (5) deduplicates via `dedupe_records()`. EU sources (horizon_europe, erc) receive special year-filtering treatment for plurianual programs.

#### Scenario: Record passes all filters
- **WHEN** a record has a valid funding title, current-year dates, and unique entity+title
- **THEN** the record is included in the output

#### Scenario: Record filtered by heuristics
- **WHEN** a record title matches "resultado final" or "retificação"
- **THEN** the record is discarded by `is_funding_opportunity_heuristics()`

#### Scenario: EU record with future deadline
- **WHEN** a Horizon Europe record has `data_limite` in a future year
- **THEN** the record is accepted (plurianual program treatment)

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
