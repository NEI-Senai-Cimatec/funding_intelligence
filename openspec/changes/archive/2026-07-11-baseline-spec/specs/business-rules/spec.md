## ADDED Requirements

### Requirement: Funding opportunity heuristic validation
The system SHALL validate each candidate record via `is_funding_opportunity_heuristics()` which checks URL patterns, title patterns, and content signals. Discard rules include: URL contains `/noticias`, `/faq`, `/retificacao`, `/resultado`, `/anexo`; title contains "manual do cartão", "perguntas frequentes", "quem somos", "tutorial"; content is a navigation-only link. Special rules: climate-related alterations are kept, "resultado-final" is discarded, e-books/reports are discarded.

#### Scenario: Non-funding URL detected
- **WHEN** a candidate URL contains `/noticias` or `/perguntas-frequentes`
- **THEN** `is_funding_opportunity_heuristics()` returns FALSE

#### Scenario: Non-funding title detected
- **WHEN** a candidate title contains "manual do cartão" or "cobrança administrativa"
- **THEN** `is_funding_opportunity_heuristics()` returns FALSE

#### Scenario: Valid funding opportunity
- **WHEN** a candidate has a title like "Edital de Inovação em Saúde" and a valid URL
- **THEN** `is_funding_opportunity_heuristics()` returns TRUE

### Requirement: Current-year record filtering
The system SHALL filter records by relevance to the current year via `is_current_year_record()`. Non-EU sources require `data_publicacao` year to match the current year. EU sources (horizon_europe, erc) receive lenient treatment: records are accepted if deadline ≥ current year, or if the current/future year is mentioned in title/text, or if no past years (5-year window) are the only years mentioned.

#### Scenario: Non-EU record from current year
- **WHEN** a Brazilian source record has `data_publicacao` in the current year
- **THEN** the record passes the year filter

#### Scenario: Non-EU record from past year
- **WHEN** a Brazilian source record has `data_publicacao` in a previous year
- **THEN** the record is rejected by the year filter

#### Scenario: EU record with future deadline
- **WHEN** a Horizon Europe record has `data_limite` in a future year
- **THEN** the record passes the year filter (plurianual treatment)

### Requirement: Status classification from deadline and text
The system SHALL classify opportunity status via `classify_status()` which: (1) computes `diff_days = deadline - today`, (2) returns "encerrado" if diff < 0, "encerrando" if diff ≤ 14, "em breve" if start > today, "aberto" otherwise. Text-based fallback: patterns for "encerrad/closed", "open/abert", "coming soon".

#### Scenario: Open opportunity
- **WHEN** a record has `data_limite` 30 days in the future
- **THEN** status is classified as "aberto"

#### Scenario: Closing soon
- **WHEN** a record has `data_limite` 10 days in the future
- **THEN** status is classified as "encerrando"

#### Scenario: Expired opportunity
- **WHEN** a record has `data_limite` in the past
- **THEN** status is classified as "encerrado"

### Requirement: Language inference from text content
The system SHALL infer language via `infer_language_simple()` which matches keyword patterns: Portuguese patterns ("edital", "chamada", "bolsa", "inscrições"), English patterns ("call", "grant", "funding", "deadline"), Spanish patterns ("convocatoria", "subvención", "beca").

#### Scenario: Portuguese text detected
- **WHEN** text contains "edital" and "chamada"
- **THEN** language is inferred as "pt"

#### Scenario: English text detected
- **WHEN** text contains "grant" and "funding"
- **THEN** language is inferred as "en"

### Requirement: Opportunity type inference from text
The system SHALL infer opportunity type via `infer_type_from_text()` which matches: "fellowship/scholarship/bolsa" → "bolsa", "subvenc/subsidy" → "subvenção", "call for proposals/chamada" → "chamada pública", "grant/research grant" → "grant", "edital" → "edital", default → "oportunidade".

#### Scenario: Fellowship detected
- **WHEN** text contains "fellowship" or "scholarship"
- **THEN** type is inferred as "bolsa"

#### Scenario: Grant detected
- **WHEN** text contains "grant" or "research grant"
- **THEN** type is inferred as "grant"

### Requirement: Area thematic inference from text
The system SHALL infer thematic area via `infer_area_from_text_one()` which matches: health/medical/biomed → "Saúde", climate/agriculture/bioeconom → "Mudanças Climáticas e Agricultura", hydrogen/energy/decarbon → "Transição Energética", innovation/industrial → "Inovação e Indústria", culture → "Cultura", education/scholarship/mobility → "Educação e Mobilidade", default → "Multitemático".

#### Scenario: Health-related opportunity
- **WHEN** text contains "health" or "medical" or "saúde"
- **THEN** area is inferred as "Saúde"

#### Scenario: Energy transition opportunity
- **WHEN** text contains "hydrogen" or "energy" or "energia"
- **THEN** area is inferred as "Transição Energética"

### Requirement: Deduplication priority by status and date
The system SHALL deduplicate records via `dedupe_records()` which: normalizes titles (Latin-ASCII, lowercase), assigns status priority (aberto=1, futuro=2, encerrado=3, other=4), computes content length, sorts by status priority DESC → deadline DESC → content length DESC, and keeps the first record per `(entidade, title_norm)`.

#### Scenario: Status priority
- **WHEN** two records have the same entity and normalized title, one "aberto" and one "encerrado"
- **THEN** the "aberto" record is kept

#### Scenario: Date tiebreak
- **WHEN** two records have the same entity, title, and status
- **THEN** the record with the later deadline is kept

### Requirement: Keyword extraction with stopwords
The system SHALL extract keywords via `extract_keywords_simple()` which: tokenizes text (4+ char tokens), removes a 150+ word stopword list (including funding terms, administrative terms, pronouns, prepositions in PT/EN), ranks by frequency, and returns the top 8 terms.

#### Scenario: Valid keyword extraction
- **WHEN** text contains "quantum computing qubits superconductors algorithms"
- **THEN** keywords include domain-specific terms like "quantum", "computing", "qubits"

#### Scenario: Stopword filtering
- **WHEN** text contains "edital para pesquisa de desenvolvimento"
- **THEN** "edital", "para", "pesquisa", "desenvolvimento" are filtered as stopwords

### Requirement: Date extraction from multiple formats
The system SHALL extract dates from text via `extract_dates_from_text()` which recognizes: `DD/MM/YYYY`, `YYYY-MM-DD`, `DD de mês de YYYY` (Portuguese month names). All formats are normalized to `YYYY-MM-DD`.

#### Scenario: Brazilian date format
- **WHEN** text contains "15/03/2026"
- **THEN** the date is extracted as "2026-03-15"

#### Scenario: Portuguese text date
- **WHEN** text contains "15 de março de 2026"
- **THEN** the date is extracted as "2026-03-15"

### Requirement: Money value parsing
The system SHALL parse monetary values via `parse_money_text()` which detects currency symbols (R$, US$, EUR, GBP, CAD) and extracts numeric values. Currency is inferred from text patterns; values are parsed with thousand separators handled.

#### Scenario: Brazilian currency
- **WHEN** text contains "R$ 150.000,00"
- **THEN** value is 150000 and currency is "BRL"

#### Scenario: Euro currency
- **WHEN** text contains "€2.500.000"
- **THEN** value is 2500000 and currency is "EUR"
