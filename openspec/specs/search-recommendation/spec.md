# search-recommendation

## Purpose

Defines the search and recommendation engine: boolean query parsing with AST, structured filters, dynamic adherence scoring, opportunity/partner/collaborator recommendation, search history, saved searches, and tracked opportunity management.

## Requirements

### Requirement: Boolean query parser with AST
The system SHALL parse boolean queries via `parse_boolean_query()` which tokenizes input (AND, OR, NOT, parentheses, quoted phrases, wildcard `*`), inserts implicit AND between adjacent terms, and builds an AST with nodes: TERM, AND, OR, NOT. Queries without explicit operators are treated as OR.

#### Scenario: Simple OR query
- **WHEN** the query is "quantum sensors"
- **THEN** the AST is `OR(TERM("quantum"), TERM("sensors"))`

#### Scenario: Complex boolean query
- **WHEN** the query is `(quântica OR "tecnologia quântica") AND edital NOT licitação`
- **THEN** the AST correctly represents the precedence: OR inside parentheses, AND joining terms, NOT excluding licitação

#### Scenario: Quoted phrase
- **WHEN** the query contains `"inteligência artificial"`
- **THEN** the phrase is treated as a single TERM for matching

### Requirement: Boolean query evaluation against text index
The system SHALL evaluate boolean ASTs against a concatenated text index of each record (titulo, subtitulo, descricao_resumida, descricao_completa, palavras_chave, area_tematica, elegibilidade) via `apply_boolean_search()`. Text is normalized (Latin-ASCII, lowercase) before matching. Term matching uses word-boundary regex with wildcard support.

#### Scenario: Boolean AND match
- **WHEN** query is "quantum AND computing" and a record contains both terms
- **THEN** the record is included in results

#### Scenario: Boolean NOT exclusion
- **WHEN** query is "quantum NOT sensors" and a record contains "quantum sensors"
- **THEN** the record is excluded from results

### Requirement: Structured advanced filters
The system SHALL apply structured filters via `apply_structured_filters()` which supports: idioma (exact match), pais_origem (set membership), tipo_oportunidade (set membership), area_tematica (set membership), entidade (set membership), elegibilidade (substring match), valor_financiado (range), data_limite (range). Filters are applied after boolean search.

#### Scenario: Multi-filter application
- **WHEN** filters specify `idioma = "pt"` and `pais_origem = "Brasil"`
- **THEN** only Portuguese Brazilian records are returned

#### Scenario: Deadline range filter
- **WHEN** deadline range is set to the next 90 days
- **THEN** only records with `data_limite` within the range are returned

### Requirement: Dynamic adherence scoring
The system SHALL compute adherence scores via `compute_adherence_score()` using a weighted formula: keywords (40%), area themes (20%), funder (15%), country (10%), eligibility (15%). The signature is built from: user profile, search history, tracked opportunities, and current query terms. Scores are recalculated dynamically when the query changes.

#### Scenario: High adherence match
- **WHEN** a record's keywords overlap 80% with the user's interest signature
- **THEN** the keyword score is 80 and the total adherence is high

#### Scenario: No query active
- **WHEN** the search query is empty
- **THEN** adherence is based solely on the user profile signature

### Requirement: Recommendation of opportunities
The system SHALL recommend opportunities via `recommend_opportunities()` which: computes adherence scores, excludes already-tracked records and encerrado records, sorts by score DESC then deadline, and returns the top N results.

#### Scenario: Top recommendations
- **WHEN** there are 50 non-tracked open opportunities
- **THEN** the top 10 by adherence score are returned

### Requirement: Partner recommendation for tracked opportunities
The system SHALL recommend CIMATEC partners via `recommend_partners_for_opportunity()` which: matches the opportunity text against `pesquisadores_vencedores` expertise and `projetos_aprovados` keywords, computes keyword overlap scores, and returns top N researchers sorted by affinity.

#### Scenario: Partner match for quantum opportunity
- **WHEN** a tracked opportunity is about "quantum computing" and Dr. Marcos Santos has expertise in "computação quântica; qubits"
- **THEN** Dr. Santos is recommended with a high affinity score

### Requirement: Collaborator discovery
The system SHALL discover collaborators via `find_potential_collaborators()` which: builds an interest signature from profile + query, matches against the `colaboradores` table by keyword overlap on nome + instituicao + area + palavras_chave, and returns top N results.

#### Scenario: Collaborator match
- **WHEN** the user's interest includes "saúde" and a collaborator has area "Saúde"
- **THEN** that collaborator is returned with a high similarity score

### Requirement: Search history and saved searches
The system SHALL record search history via `save_search_record()` (inserts into `historico_buscas`) and support named saved searches via `save_named_search()` (inserts into `buscas_salvas` with optional weekly alert flag). Saved searches include the query text and advanced filter payload as JSON.

#### Scenario: History recorded on search
- **WHEN** user executes a search
- **THEN** the query text and timestamp are inserted into `historico_buscas`

#### Scenario: Named search saved
- **WHEN** user saves a search with name "Quantum Health" and alert enabled
- **THEN** a row is inserted into `buscas_salvas` with `alerta_ativo = 1`

### Requirement: Tracked opportunity management
The system SHALL manage tracked opportunities via: `track_opportunity()` (insert/update with UPSERT), `update_tracked_opportunity()` (update status and notes), `delete_tracked_opportunity()` (remove from tracking). Status options: avaliar, prioritário, submetido, descartado.

#### Scenario: Track new opportunity
- **WHEN** user clicks "Rastrear" on a result row
- **THEN** the opportunity is inserted into `editais_rastreados` with `status_usuario = "avaliar"`

#### Scenario: Update tracked status
- **WHEN** user changes status to "prioritário" and adds notes
- **THEN** the `editais_rastreados` row is updated with new status and notes
