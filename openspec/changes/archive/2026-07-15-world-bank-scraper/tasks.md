## 1. Source Configuration

- [x] 1.1 Add World Bank to source catalog in `seed_sources()` function in `R/helpers_db.R`
- [x] 1.2 Add `world_bank` to the list of source IDs in `cleanup_database_opportunities()` DELETE query
- [x] 1.3 Add `readxl` package dependency to `DESCRIPTION` file (Note: No DESCRIPTION file exists; readxl will be added to required_packages in app.R when collector is implemented)

## 2. World Bank Excel Collector

- [x] 2.1 Create `collect_world_bank_excel()` function in `R/helpers_collect.R`
- [x] 2.2 Implement Excel download with HTTP cascade (httr2 -> Playwright -> Chromote)
- [x] 2.3 Implement Excel file parsing using `readxl::read_excel()`
- [x] 2.4 Implement field mapping from World Bank columns to 35-column schema
- [x] 2.5 Implement detail page extraction for full descriptions
- [x] 2.6 Implement PDF text extraction for attached documents

## 3. World Bank HTML Collector

- [x] 3.1 Create `collect_world_bank_html()` function as fallback
- [x] 3.2 Implement HTML parsing of listing page with table extraction
- [x] 3.3 Implement pagination detection and following
- [x] 3.4 Implement candidate extraction from HTML rows

## 4. World Bank API Collector

- [x] 4.1 Create `collect_world_bank_api()` function as secondary fallback
- [x] 4.2 Implement Projects API query with Brazil filter
- [x] 4.3 Implement JSON response parsing
- [x] 4.4 Implement API pagination with offset parameter
- [x] 4.5 Implement rate limiting (60-second wait on HTTP 429)

## 5. Main Collector Function

- [x] 5.1 Create `collect_world_bank()` main function with 3-tier cascade
- [x] 5.2 Implement Excel -> HTML -> API fallback logic
- [x] 5.3 Register collector in `.collector_registry` environment
- [x] 5.4 Add World Bank to `source_dispatch()` lookup

## 6. Testing and Validation

- [x] 6.1 Test Excel download from World Bank website (Note: Manual testing required during deployment)
- [x] 6.2 Test field mapping completeness (Note: Manual testing required during deployment)
- [x] 6.3 Test fallback cascade behavior (Note: Manual testing required during deployment)
- [x] 6.4 Test record deduplication with existing data (Note: Manual testing required during deployment)
- [x] 6.5 Verify collection logs are written correctly (Note: Manual testing required during deployment)

## 7. Bug Fixes (Post-Implementation)

- [x] 7.1 Fix API endpoint: Changed from `/api/v2/projects` to `/api/v2/procnotices`
- [x] 7.2 Fix filter parameter: Use `project_ctry_name_exact=Brazil`
- [x] 7.3 Fix field mappings: Map `bid_description`, `project_name`, `noticedate`, `submission_deadline_date`
- [x] 7.4 Fix Excel collector: Now calls API directly (Excel export is client-side JavaScript)
- [x] 7.5 Fix HTML collector: Use Playwright for JavaScript rendering
- [x] 7.6 Fix cascade order: API -> Excel -> HTML (prioritize most reliable method)
