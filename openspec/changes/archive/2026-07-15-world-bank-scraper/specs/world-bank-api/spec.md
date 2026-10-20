# world-bank-api

## Purpose

Defines the World Bank Projects API integration as a fallback collection method: query active projects in Brazil, extract procurement information, and map to opportunity schema.

## Requirements

### Requirement: World Bank Projects API query

The system SHALL query the World Bank Projects API at https://search.worldbank.org/api/v2/projects with parameters: ormat=json, countrycode=BRA, status_exact=Active, ows=50, os=0. The API returns JSON with project details including procurement opportunities.

#### Scenario: Successful API query

- **WHEN** the World Bank Projects API is queried with Brazil filter
- **THEN** a JSON response containing active projects is returned

#### Scenario: API rate limiting

- **WHEN** the API returns HTTP 429 (Too Many Requests)
- **THEN** the system waits 60 seconds and retries once

#### Scenario: API unavailable

- **WHEN** the API endpoint is unreachable or returns HTTP 5xx
- **THEN** the system logs a warning and returns empty results

### Requirement: World Bank API response parsing

The system SHALL parse the API JSON response and extract: project_name, countryname, status, project_abstract, lendinginstrument, oardapprovaldate, egionname, 	heme_list.

#### Scenario: API response with projects

- **WHEN** the API returns a JSON response with projects array
- **THEN** each project is extracted as a candidate record

#### Scenario: API response with no projects

- **WHEN** the API returns an empty projects array
- **THEN** the system returns zero records without error

### Requirement: World Bank API field mapping

The system SHALL map API fields to the 35-column opportunity schema:
- project_name to 	itulo
- project_abstract to descricao_completa
- countryname to pais_origem
- oardapprovaldate to data_publicacao
- status to status_oportunidade
- lendinginstrument to modalidade
- egionname to localidade
- Project URL to link_detalhe
- "World Bank" to instituicao_financiadora

#### Scenario: API field mapping completeness

- **WHEN** an API project has all mapped fields
- **THEN** the record is created with all mapped fields populated

#### Scenario: API field with missing data

- **WHEN** an API project has project_abstract as empty string
- **THEN** descricao_completa is set to NA and the record is still processed

### Requirement: World Bank API pagination

The system SHALL paginate through API results using os (offset) parameter. Pagination continues while 
um_found > current offset and max_records is not exceeded.

#### Scenario: Multi-page API results

- **WHEN** the API returns 
um_found=100 and ows=50
- **THEN** the system fetches page 1 (os=0) and page 2 (os=50)

#### Scenario: API page limit reached

- **WHEN** max_records=25 and the API returns 100 results
- **THEN** only the first 25 records are processed
