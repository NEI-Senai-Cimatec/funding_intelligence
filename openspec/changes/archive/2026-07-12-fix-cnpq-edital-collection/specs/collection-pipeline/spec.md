# collection-pipeline (delta)

## Purpose

Modifications to the generic collection pipeline to support Plone CMS search results pages with offset-based pagination.

## MODIFIED Requirements

### Requirement: Candidate extraction from HTML
The system SHALL extract candidate records from listing pages via `extract_listing_candidates()` which: (1) parses content blocks (`article`, `.card`, `.views-row`, `.item`, `article.contenttype-document`, etc.) for titles, summaries, and links — when multiple anchors exist in a block, anchors inside heading elements (`h1, h2, h3, h4`) SHALL be preferred as the `detail_url` over generic anchors; (2) parses anchor elements directly; (3) filters candidates through `is_funding_opportunity_heuristics()`, (4) deduplicates by canonical URL. Fallback: if no candidates found, captures all PDF links as records.

#### Scenario: Block-based extraction with heading link
- **WHEN** a listing page contains `<div class="item"><h2><a href="DETAIL_URL">Title</a></h2><a href="share_url">Share</a></div>`
- **THEN** the candidate has `detail_url = DETAIL_URL`, not `share_url`

#### Scenario: Article-based extraction (Plone search results)
- **WHEN** a listing page contains `<article class="contenttype-document"><h2 class="tileHeadline"><a class="state-published" href="URL">Title</a></h2></article>`
- **THEN** the candidate has `detail_url = URL` and `title = "Title"`

#### Scenario: Heuristic filtering
- **WHEN** a candidate title matches "manual do cartão" or "perguntas frequentes"
- **THEN** the candidate is discarded by `is_funding_opportunity_heuristics()`

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
