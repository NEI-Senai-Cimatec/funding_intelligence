## 1. Specification Writing

- [x] 1.1 Create `specs/app-architecture/spec.md` — document Shiny UI structure, server reactivity, background process management, Google Drive sync, package bootstrap
- [x] 1.2 Create `specs/collection-pipeline/spec.md` — document collector registry, HTTP cascade, rate limiting, pagination, EU/FINEP/CAPES/SIGITEC/FAPESB/DAAD specialized collectors, record finalization
- [x] 1.3 Create `specs/business-rules/spec.md` — document funding heuristics (50+ URL/title patterns), year filtering, status/language/type/area inference, dedup logic, date/money parsing
- [x] 1.4 Create `specs/data-model/spec.md` — document 11 SQLite tables, 35-column oportunidades schema, UPSERT operations, seed data, startup cleanup
- [x] 1.5 Create `specs/ai-integration/spec.md` — document 8 providers, fallback chain, circuit breaker, extraction prompts, audit skill, batch processing, EU translation
- [x] 1.6 Create `specs/search-recommendation/spec.md` — document boolean AST parser, structured filters, adherence scoring, partner recommendation, tracked opportunities

## 2. Cross-Reference Validation

- [x] 2.1 Verify `app-architecture` spec references match actual `app.R` line numbers and function names
- [x] 2.2 Verify `collection-pipeline` spec references match actual `helpers_collect.R` function signatures and flow
- [x] 2.3 Verify `business-rules` spec patterns match actual regex patterns in `is_funding_opportunity_heuristics()`
- [x] 2.4 Verify `data-model` spec schema matches actual `create_tables()` DDL in `helpers_db.R`
- [x] 2.5 Verify `ai-integration` spec provider configs match actual `get_ai_config()` defaults in `helpers_ai.R`
- [x] 2.6 Verify `search-recommendation` spec scoring weights match actual `compute_adherence_score()` formula in `helpers_recommend.R`

## 3. Completeness Check

- [x] 3.1 Ensure every public function in `helpers_collect.R` is referenced in `collection-pipeline` or `business-rules` specs
- [x] 3.2 Ensure every table in `helpers_db.R` `create_tables()` is documented in `data-model` spec
- [x] 3.3 Ensure every AI provider in `helpers_ai.R` `get_ai_config()` is documented in `ai-integration` spec
- [x] 3.4 Ensure every env var used in the codebase is documented in at least one spec

## 4. Final Review

- [x] 4.1 Review all 6 specs for consistency in terminology (e.g., "record" vs "opportunity" vs "edital")
- [x] 4.2 Ensure all scenarios use WHEN/THEN format with exactly 4 hashtags
- [x] 4.3 Confirm no new functionality is proposed — all specs describe the current state only
