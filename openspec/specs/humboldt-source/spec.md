# humboldt-source

## Purpose

Defines the Alexander von Humboldt Foundation data source: HTML scraping of fellowship and award programs, detail page extraction, status inference, and country normalization.

## Requirements

### Requirement: Humboldt Foundation source catalog entry
The system SHALL include the Alexander von Humboldt Foundation as a configured source in `fontes_financiamento` with: `id_fonte = "humboldt"`, `nome_fonte = "Alexander von Humboldt Foundation"`, `sigla = "HUMBOLDT"`, `pais = "Alemanha"`, `categoria = "fundação privada"`, `tipo_financiador = "fundação"`, `url_principal = "https://www.humboldt-foundation.de/en/"`, `url_oportunidades = "https://www.humboldt-foundation.de/en/apply/sponsorship-programmes/programmes-a-to-z"`, `metodo_coleta = "html"`, `idioma = "en"`.

#### Scenario: Source catalog includes Humboldt
- **WHEN** `seed_sources()` is called
- **THEN** the Humboldt entry is inserted via UPSERT into `fontes_financiamento`

### Requirement: Humboldt HTML listing collection
The system SHALL collect Humboldt programs via HTML scraping of the listing page. The collector fetches the listing page with `filterBy=schollarships` and `filterBy=award`, parses teaser cards (`.teaser.teaser--small`) extracting: title (`.teaser__headline`), "For whom" / "From where" / "For what" metadata, and detail URL (`.teaser__link a[href]`). Both fellowship and award pages are fetched and combined.

#### Scenario: Listing page parsed
- **WHEN** `collect_humboldt()` runs
- **THEN** all teaser cards from both scholarship and award listing pages are extracted

#### Scenario: Card metadata extracted
- **WHEN** a card contains "For whom: postdoctoral researchers" and "From where: Brazil"
- **THEN** elegibilidade is set to "postdoctoral researchers" and pais_origem tracks "Brazil"

### Requirement: Humboldt detail page extraction
The system SHALL fetch each program's detail page and extract: the main heading, structured metadata from the icon-list (For whom, From where, For what), and the primary content section. The detail page URL pattern is `/en/apply/sponsorship-programmes/{slug}`.

#### Scenario: Detail page with full metadata
- **WHEN** a detail page for "International Climate Protection Fellowship" is fetched
- **THEN** the collector extracts title, eligibility, country, duration, and description text

#### Scenario: Detail page fetch failure
- **WHEN** a detail page returns HTTP 404 or network error
- **THEN** the record is created with data from the listing card only

### Requirement: Humboldt status inference
The system SHALL infer opportunity status from detail page text using heuristics: text contains "closing date has elapsed" or "not currently possible to apply" → "encerrado"; text contains "next application round" with a future date → "futuro"; otherwise → "aberto".

#### Scenario: Closed program detected
- **WHEN** detail page contains "The closing date for applications has elapsed"
- **THEN** status_oportunidade is classified as "encerrado"

#### Scenario: Permanent program
- **WHEN** detail page has no closing date text and no next round mention
- **THEN** status_oportunidade is classified as "aberto"

### Requirement: Humboldt country normalization
The system SHALL normalize "From where" values from the Humboldt site: "Brazil" → "Brasil", "Germany" → "Alemanha", "non-European developing and transition countries" → "Internacional (países em desenvolvimento)", "All countries" → "Internacional".

#### Scenario: Brazilian eligibility
- **WHEN** a program's "From where" field contains "Brazil"
- **THEN** the record is marked as relevant to Brazilian researchers

### Requirement: Humboldt collector registration
The system SHALL register `collect_humboldt` in the collector registry for `id_fonte = "humboldt"` and dispatch to it via `source_dispatch()`.

#### Scenario: Dispatcher invokes Humboldt collector
- **WHEN** `source_dispatch()` is called with `source_row$id_fonte == "humboldt"`
- **THEN** `collect_humboldt()` is invoked with HTML scraping
