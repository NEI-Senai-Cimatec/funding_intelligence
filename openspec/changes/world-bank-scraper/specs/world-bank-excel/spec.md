# world-bank-excel

## Purpose

Defines the World Bank Excel collection capability: download procurement notices Excel file, parse structured data, and map to the opportunity schema.

## Requirements

### Requirement: World Bank Excel download

The system SHALL download the World Bank procurement notices Excel file from the opportunities page. The download URL is constructed by appending `&export=Excel` to the base opportunities URL. The system SHALL use the HTTP cascade (httr2 -> Playwright -> Chromote) with anti-detection headers.

#### Scenario: Successful Excel download

- **WHEN** the World Bank opportunities page is accessed with `&export=Excel` parameter
- **THEN** an Excel file (.xlsx) is downloaded to a temporary location

#### Scenario: Excel download with CAPTCHA

- **WHEN** the download returns a CAPTCHA challenge page
- **THEN** the system falls back to HTML scraping

### Requirement: World Bank Excel parsing

The system SHALL parse the downloaded Excel file using `readxl::read_excel()` and extract columns: `Aviso` (notice title), `Pais` (country), `Titulo do projeto` (project title), `Tipo de notificacao` (notification type), `Idioma` (language), `Tipo de aquisicao` (acquisition type), `Data de publicacao` (publication date), `Prazo de envio` (submission deadline).

#### Scenario: Excel with valid data

- **WHEN** the Excel file contains procurement notice rows
- **THEN** each row is extracted as a candidate record with the mapped fields

#### Scenario: Excel with empty rows

- **WHEN** the Excel file contains empty rows or headers
- **THEN** empty rows are skipped and only valid data rows are processed

### Requirement: World Bank field mapping to opportunity schema

The system SHALL map World Bank Excel columns to the 35-column opportunity schema:
- `Aviso` to `titulo`
- `Titulo do projeto` to `subtitulo`
- `Pais` to `pais_origem`
- `Data de publicacao` to `data_publicacao`
- `Prazo de envio` to `data_limite`
- `Tipo de aquisicao` to `modalidade`
- `Tipo de notificacao` to `tipo_oportunidade`
- `Idioma` to `idioma`
- Detail page URL to `link_detalhe`
- "World Bank" to `instituicao_financiadora`
- `Brazil` to `localidade`

#### Scenario: Field mapping completeness

- **WHEN** a World Bank Excel row has all required fields
- **THEN** the record is created with all mapped fields populated

#### Scenario: Missing optional fields

- **WHEN** a World Bank Excel row has missing optional fields (e.g., `Prazo de envio`)
- **THEN** the field is set to NA and the record is still processed

### Requirement: World Bank Excel detail page extraction

The system SHALL follow the detail URL from each Excel row to extract additional information: full description, project details, and any attached documents.

#### Scenario: Detail page with full description

- **WHEN** a World Bank notice detail page is fetched
- **THEN** the full description text is extracted and stored in `descricao_completa`

#### Scenario: Detail page with PDF attachment

- **WHEN** a World Bank notice detail page contains a PDF link
- **THEN** the PDF is downloaded and text is extracted via `pdftools::pdf_text()`
