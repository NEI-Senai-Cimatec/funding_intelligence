# cnpq-collector

## Purpose

Specialized CNPq collector that extracts edital (chamada) records from `https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas` using paginated search results and detail page following.

## ADDED Requirements

### Requirement: Paginated listing extraction from Busca_abertas
The system SHALL extract CNPq chamada records from the `Busca_abertas` search results page by identifying `<article class="contenttype-document">` elements and extracting the title link from `h2.tileHeadline a.state-published`. Each chamada SHALL be visited individually for full content.

#### Scenario: Extract chamada from search results
- **WHEN** `collect_cnpq()` fetches `Busca_abertas` containing `<article class="contenttype-document"><h2 class="tileHeadline"><a class="state-published" href="DETAIL_URL">Chamada CNPq 25/2026</a></h2></article>`
- **THEN** the detail URL is extracted from `h2.tileHeadline a.state-published[href]` and the title from its text content

#### Scenario: Listing page shows only titles
- **WHEN** the listing page contains chamada items without descriptions or dates
- **THEN** the collector follows each detail URL to obtain full content

### Requirement: b_start:int offset-based pagination
The system SHALL paginate through `Busca_abertas` results using the `b_start:int` URL parameter. Pagination SHALL continue while `detect_next_page()` returns a URL with `b_start:int` parameter and `max_pages` is not exceeded.

#### Scenario: Multi-page collection
- **WHEN** `Busca_abertas` has 3 pages (15 items) and `max_pages=5, max_records=50`
- **THEN** all 3 pages are visited (b_start=0, 5, 10) and chamadas are extracted from each

#### Scenario: Page limit reached
- **WHEN** `max_pages=2` and the listing has 5 pages
- **THEN** only pages 1-2 are processed

#### Scenario: No more results
- **WHEN** a page returns 0 chamada items
- **THEN** pagination stops

### Requirement: Dual-page collection with deduplication
The system SHALL collect chamadas from both `Busca_abertas` (primary) and `abertas-para-submissao` (supplementary). Records from both sources SHALL be deduplicated by `link_detalhe` URL.

#### Scenario: Same chamada on both pages
- **WHEN** a chamada appears on both `Busca_abertas` and `abertas-para-submissao`
- **THEN** only one record is kept, preferring the version with more detail

#### Scenario: Unique chamada on supplementary page
- **WHEN** a chamada appears only on `abertas-para-submissao`
- **THEN** it is included in the output

### Requirement: Detail page content extraction
The system SHALL visit each chamada's detail page to extract full content including title, description, dates, file attachments (PDFs, DOCX), and submission periods.

#### Scenario: Detail page with PDF attachments
- **WHEN** a chamada detail page contains PDF links
- **THEN** the PDFs are downloaded and their text is extracted via `pdftools::pdf_text()`

#### Scenario: Detail page with submission dates
- **WHEN** a chamada detail page contains "INSCRICOES: DD/MM/YYYY a DD/MM/YYYY"
- **THEN** `data_abertura` and `data_limite` are parsed from this pattern

### Requirement: Registered collector
The system SHALL register `collect_cnpq` in the `.collector_registry` environment so that `get_collector("cnpq")` returns the specialized collector.

#### Scenario: Collector registry lookup
- **WHEN** `get_collector("cnpq")` is called
- **THEN** it returns the `collect_cnpq` function, not the generic fallback
