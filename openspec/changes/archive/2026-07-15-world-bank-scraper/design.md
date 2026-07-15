## Context

The funding_intelligence system collects opportunities from 12 funding sources using a centralized collection pipeline. Each source has a specialized collector that handles its unique data format and access method. The World Bank represents a high-value addition as a major international development funder with structured data access through Excel exports and a REST API.

Current state:
- 12 sources configured in ontes_financiamento table
- Collection pipeline supports HTML scraping, REST APIs, and hybrid approaches
- Existing collectors: FINEP (Liferay REST), CAPES (Plone REST), SIGITEC (REST API), FAPESB (WordPress REST), DAAD (hybrid JS+HTML), Humboldt (HTML scraping)
- World Bank website at https://projects.worldbank.org/pt/projects-operations/opportunities provides Excel download and filtering by country

## Goals / Non-Goals

**Goals:**
- Enable automated collection of World Bank procurement notices for Brazil
- Support Excel download as primary data source (structured, reliable)
- Provide HTML scraping fallback when Excel is unavailable
- Implement API fallback using World Bank Projects API
- Map World Bank fields to the existing 35-column opportunity schema
- Integrate with existing collector dispatch system

**Non-Goals:**
- Real-time monitoring of World Bank updates (batch collection only)
- Collection from non-Brazil World Bank projects
- Historical data backfill (current opportunities only)
- Multi-language support (Portuguese/English mixed content)

## Decisions

### Decision 1: Excel-first collection strategy

**Choice**: Primary collection via Excel download, with HTML and API fallbacks

**Rationale**: The World Bank website provides a "Baixar para Excel" (Download to Excel) button that exports structured procurement data. This is more reliable than HTML scraping because:
- Structured data avoids HTML parsing fragility
- Excel format preserves data types and relationships
- Single download获取 all matching records (up to 20 per page)
- Less susceptible to website layout changes

**Alternatives considered**:
1. HTML scraping only: Rejected due to complex table structure and pagination
2. API-only: Rejected as primary because Projects API has different data model than procurement notices
3. PDF extraction: Rejected due to unstructured format and extraction complexity

### Decision 2: Three-tier fallback cascade

**Choice**: Excel → HTML → API fallback chain

**Rationale**: Different failure modes require different fallback strategies:
- Excel download fails (server error, CAPTCHA) → try HTML scraping
- HTML scraping fails (layout change, blocking) → try Projects API
- API fails (rate limiting, schema change) → return empty with warning

**Alternatives considered**:
1. Excel + API only: Rejected because HTML provides中间 fallback
2. Parallel collection: Rejected to avoid duplicate records and rate limiting

### Decision 3: World Bank Projects API as final fallback

**Choice**: Use https://search.worldbank.org/api/v2/projects API

**Rationale**: The Projects API provides:
- JSON response format (easy parsing)
- Country filtering via countrycode=BRA
- Status filtering via status_exact=Active
- Project details including procurement information

**Limitations**:
- Different data model than procurement notices
- May not include all tender opportunities
- Rate limiting (1000 requests/day without API key)

### Decision 4: Field mapping strategy

**Choice**: Direct mapping from Excel columns to opportunity schema

**Rationale**: World Bank Excel provides structured fields that map directly:
- Aviso → 	itulo (notice title)
- Título do projeto → subtitulo (project title)
- País → pais_origem (country)
- Data de publicação → data_publicacao (publication date)
- Prazo de envio → data_limite (deadline)
- Tipo de aquisição → modalidade (acquisition type)
- Descrição → descricao_completa (full description)

**Unmapped fields**: Some World Bank fields have no equivalent in the 35-column schema (stored in observacoes)

## Risks / Trade-offs

### Risk 1: Excel download URL changes
**Mitigation**: Store URL pattern in source catalog, update via configuration change

### Risk 2: CAPTCHA/rate limiting on Excel download
**Mitigation**: Implement exponential backoff, use existing anti-detection cascade (httr2 → Playwright → Chromote)

### Risk 3: World Bank API schema changes
**Mitigation**: Version API calls, validate response schema, fallback to HTML/Excel

### Risk 4: Data quality issues (missing fields, encoding)
**Mitigation**: Validate required fields (titulo, link_origem), skip records with critical missing data

### Trade-off: Excel reliability vs. API completeness
- Excel provides procurement notices (tenders) but may miss some opportunities
- Projects API provides broader project data but less tender-specific detail
- Solution: Use Excel as primary, API as supplementary for project context

## Migration Plan

1. Add world_bank source to ontes_financiamento via seed_sources()
2. Implement collect_world_bank() function in helpers_collect.R
3. Register collector in .collector_registry environment
4. Test with single collection run
5. Monitor collection logs for errors

## Open Questions

1. Should we cache Excel files locally to avoid repeated downloads?
2. How often should World Bank collection run (daily, weekly)?
3. Should we extract text from linked PDFs in procurement notices?
4. What is the rate limit for World Bank Projects API without authentication?
