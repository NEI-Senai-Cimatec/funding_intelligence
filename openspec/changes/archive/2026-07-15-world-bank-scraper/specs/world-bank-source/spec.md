# world-bank-source

## Purpose

Defines the World Bank data source configuration: source catalog entry, collection metadata, and integration with the funding intelligence system.

## Requirements

### Requirement: World Bank source catalog entry

The system SHALL include the World Bank as a configured source in ontes_financiamento with: id_fonte = "world_bank", 
ome_fonte = "World Bank", sigla = "WB", pais = "Estados Unidos", categoria = "organismo internacional", 	ipo_financiador = "multilateral", url_principal = "https://www.worldbank.org/", url_oportunidades = "https://projects.worldbank.org/pt/projects-operations/opportunities?project_ctry_name_exact=Brazil", metodo_coleta = "hybrid", idioma = "pt", periodicidade_atualizacao = "diaria".

#### Scenario: Source catalog includes World Bank

- **WHEN** seed_sources() is called
- **THEN** the World Bank entry is inserted via UPSERT into ontes_financiamento

#### Scenario: World Bank source metadata

- **WHEN** a collector queries the source catalog for id_fonte = "world_bank"
- **THEN** the source row contains url_oportunidades pointing to the Brazil-filtered opportunities page

### Requirement: World Bank collection method configuration

The system SHALL support three collection methods for World Bank: excel (primary), html (fallback), and pi (secondary fallback). The default method is excel.

#### Scenario: Default collection method

- **WHEN** no specific method is configured for World Bank collection
- **THEN** the system attempts Excel download first

#### Scenario: Method override via environment variable

- **WHEN** WORLD_BANK_METHOD environment variable is set to pi
- **THEN** the system uses API collection instead of Excel
