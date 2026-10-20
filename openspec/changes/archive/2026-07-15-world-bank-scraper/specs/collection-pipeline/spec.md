# collection-pipeline

## Purpose

Defines the data collection pipeline: collector dispatch, HTTP request strategies with anti-detection, rate limiting, HTML pagination, candidate extraction, detail/PDF fetching, specialized collectors for 12 funding sources, and record finalization with deduplication.

## Requirements

### Requirement: World Bank collector registration

The system SHALL register collect_world_bank in the collector registry for id_fonte = "world_bank" and dispatch to it via source_dispatch().

#### Scenario: Dispatcher invokes World Bank collector

- **WHEN** source_dispatch() is called with source_row == "world_bank"
- **THEN** collect_world_bank() is invoked with Excel-first collection strategy

### Requirement: World Bank collection cascade

The system SHALL attempt World Bank collection in a 3-tier cascade: (1) Excel download and parsing, (2) HTML scraping of listing page, (3) Projects API query. The cascade stops at the first successful non-empty result.

#### Scenario: Excel collection succeeds

- **WHEN** the Excel download returns valid procurement notice data
- **THEN** the records are processed and returned without attempting HTML or API

#### Scenario: Excel fails, HTML succeeds

- **WHEN** the Excel download fails (CAPTCHA, server error)
- **AND** the HTML scraping returns valid candidates
- **THEN** the HTML-sourced records are processed and returned

#### Scenario: Excel and HTML fail, API succeeds

- **WHEN** both Excel and HTML collection fail
- **AND** the Projects API returns active Brazil projects
- **THEN** the API-sourced records are processed and returned

#### Scenario: All methods fail

- **WHEN** all three collection methods fail or return empty results
- **THEN** a warning is logged and an empty tibble is returned

### Requirement: World Bank source catalog entry

The system SHALL include the World Bank as a configured source in ontes_financiamento with: id_fonte = "world_bank", 
ome_fonte = "World Bank", sigla = "WB", pais = "Estados Unidos", categoria = "organismo internacional", 	ipo_financiador = "multilateral", url_principal = "https://www.worldbank.org/", url_oportunidades = "https://projects.worldbank.org/pt/projects-operations/opportunities?project_ctry_name_exact=Brazil", metodo_coleta = "hybrid", idioma = "pt", periodicidade_atualizacao = "diaria".

#### Scenario: Source catalog includes World Bank

- **WHEN** seed_sources() is called
- **THEN** the World Bank entry is inserted via UPSERT into ontes_financiamento

### Requirement: World Bank field mapping to opportunity schema

The system SHALL map World Bank data (from Excel or API) to the 35-column opportunity schema with the following mappings:
- Aviso/project_name to 	itulo
- Título do projeto/project_abstract to subtitulo/descricao_completa
- País/countryname to pais_origem
- Data de publicação/oardapprovaldate to data_publicacao
- Prazo de envio to data_limite
- Tipo de aquisição/lendinginstrument to modalidade
- "World Bank" to instituicao_financiadora

#### Scenario: Field mapping completeness

- **WHEN** a World Bank record has all required fields
- **THEN** the record is created with all mapped fields populated

#### Scenario: Missing optional fields

- **WHEN** a World Bank record has missing optional fields
- **THEN** the field is set to NA and the record is still processed
