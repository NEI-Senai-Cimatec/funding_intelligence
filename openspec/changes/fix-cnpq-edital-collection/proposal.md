## Why

The CNPq collection pipeline returns 0 edital records. The scraper targets `abertas-para-submissao` (a Plone Collection view) but the actual working page is `Busca_abertas` (a paginated search results page with 5 items/page). Additionally, `is_plone_search_url()` incorrectly stops pagination on `Busca_abertas` because the URL contains `/busca_`.

## What Changes

- **Switch primary listing URL to `Busca_abertas`**: The correct listing page is `https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas` which uses `b_start:int` offset-based pagination (5 items/page).

- **Fix pagination to follow `b_start:int` offsets**: Remove the `is_plone_search_url()` check that stops pagination on same-page URLs. Distinguish between "different page" (stop) and "same page with offset" (continue).

- **Add `article.contenttype-document` block selector**: The `Busca_abertas` page uses `<article class="contenttype-document">` with `h2.tileHeadline a.state-published` for title links.

- **Collect from both pages with deduplication**: Use `Busca_abertas` (paginated, 5/page) as primary and `abertas-para-submissao` (all items inline) as supplementary. Deduplicate by detail URL.

- **Visit each chamada detail page**: The listing page only shows titles. Each chamada must be visited individually for full content, dates, and file attachments.

- **Plone REST API unavailable**: CNPq's `++api++/pt-br/@search` returns 404. HTML scraping is the only option.

## Capabilities

### New Capabilities
- `cnpq-collector`: Specialized CNPq collector with dual-page strategy, `b_start:int` pagination, and detail page following.

### Modified Capabilities
- `collection-pipeline`: Add `article.contenttype-document` selector; fix pagination to not stop on same-page offset URLs.

## Impact

- **Code**: `R/helpers_collect.R` — fix `is_plone_search_url()`, update `collect_cnpq()` to use `Busca_abertas`, add `article` selector.
- **Tests**: `tests/testthat/` — update tests for new selectors.
- **No API changes**: External interface unchanged.
