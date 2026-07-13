## Context

The CNPq collection uses `collect_cnpq()` (specialized collector) which delegates to `collect_listing_with_pagination()`. The primary listing page is `https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas` — a Plone search results page with paginated results (5 items/page, `b_start:int` offset parameter).

Each chamada is an `<article class="contenttype-document">` with `h2.tileHeadline a.state-published` for the title link. The listing page only shows titles and tags — no descriptions, dates, or file links. Each chamada must be visited individually for full content.

A secondary page `https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao` shows items inline with descriptions and file links, but may not be paginated consistently.

The Plone REST API (`++api++/pt-br/@search`) returns 404 on the CNPq instance — HTML scraping is the only option.

## Goals / Non-Goals

**Goals:**
- Extract all CNPq chamadas from `Busca_abertas` using `b_start:int` pagination
- Visit each chamada detail page for full content
- Collect supplementary data from `abertas-para-submissao` with deduplication
- Register a specialized CNPq collector
- Maintain backward compatibility with other sources

**Non-Goals:**
- Plone REST API integration (not available on CNPq)
- Changing the 35-column record schema
- Modifying the AI enrichment pipeline

## Decisions

### Decision 1: Primary listing URL

**Choice**: Use `Busca_abertas` as primary, `abertas-para-submissao` as supplementary.

**Rationale**: `Busca_abertas` is a proper paginated search results page with consistent structure. `abertas-para-submissao` is a Collection view that may not paginate reliably.

**Alternatives considered**:
- Use only `abertas-para-submissao` — rejected because pagination is unreliable.
- Use only `Busca_abertas` — rejected because it only shows titles, no descriptions.

### Decision 2: Pagination strategy

**Choice**: Follow `b_start:int` offset-based pagination on `Busca_abertas`. Stop when no more results or `max_pages` reached.

**Rationale**: The page uses Plone's standard offset pagination. Each page shows 5 items. The "Próximo" link contains `b_start:int=N` where N increments by 5.

**Alternatives considered**:
- Stop at "Plone search" URLs — rejected because `Busca_abertas` IS the search page and contains `/busca_` in its own pagination URLs.
- Use Plone batch_size parameter — rejected because API is not available.

### Decision 3: Block selector strategy

**Choice**: Add `article.contenttype-document` as a high-priority block selector for CNPq. Extract title from `h2.tileHeadline a.state-published`.

**Rationale**: The `Busca_abertas` page uses `<article class="contenttype-document">` elements. The title link is in `h2.tileHeadline a.state-published`.

**Alternatives considered**:
- Use generic `.item` selector — rejected because `Busca_abertas` doesn't use `.item` class.
- Use `li` or `tr` selectors — rejected because items are `<article>` elements.

### Decision 4: Detail page following

**Choice**: Always follow detail URLs to get full content. The listing page only shows titles.

**Rationale**: Each chamada has dates, descriptions, file attachments (PDFs, DOCX), and submission periods only available on the detail page.

### Decision 5: Deduplication

**Choice**: Collect from both pages, deduplicate by `link_detalhe` URL.

**Rationale**: `abertas-para-submissao` may have items not on `Busca_abertas` (or vice versa). Deduplication ensures no duplicate records.

## Risks / Trade-offs

- **[Risk] gov.br page structure changes** → Mitigation: Specialized collector isolates CNPq logic; `article.contenttype-document` is a standard Plone pattern.
- **[Risk] `Busca_abertas` page size changes** → Mitigation: Pagination follows `b_start:int` offsets dynamically, not hardcoded page counts.
- **[Trade-off] Slower collection** → Following detail pages adds HTTP requests. Mitigation: Parallel detail fetching with rate limiting.
- **[Trade-off] No API fallback** → HTML scraping is more fragile. Mitigation: The page is server-rendered and stable.
