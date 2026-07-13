## 1. Fix is_plone_search_url() Pagination Logic

- [x] 1.1 Modify `is_plone_search_url()` in R/helpers_collect.R to NOT match URLs that are the same page with `b_start:int` offset parameter. The function should only return TRUE for genuinely different search pages, not for pagination of the same page.

## 2. Update collect_cnpq() to Use Busca_abertas

- [x] 2.1 Change the primary URL in `collect_cnpq()` from `abertas-para-submissao` to `Busca_abertas` (`https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas`).

## 3. Add Article-Based Block Selector

- [x] 3.1 Add `article.contenttype-document` to the `block_sel` vector in `extract_listing_candidates()`.
- [x] 3.2 Add extraction logic for `h2.tileHeadline a.state-published` as the title/detail link within article blocks.

## 4. Implement Dual-Page Collection with Deduplication

- [x] 4.1 Update `collect_cnpq()` to collect from both `Busca_abertas` (primary, paginated) and `abertas-para-submissao` (supplementary).
- [x] 4.2 Add deduplication by `link_detalhe` URL after combining records from both pages.

## 5. Update Tests

- [x] 5.1 Update test for `is_plone_search_url()` to verify it does NOT match same-page offset URLs.
- [x] 5.2 Update test for article-based extraction with `h2.tileHeadline a`.
- [x] 5.3 Run collection verification for CNPq.

## 6. Documentation

- [x] 6.1 Update README.md to reflect dual-page collection strategy.
- [x] 6.2 Verify openspec change status.
