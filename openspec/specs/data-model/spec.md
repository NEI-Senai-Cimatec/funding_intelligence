# data-model

## Purpose

Defines the SQLite data model: 11 tables, the 35-column `oportunidades` schema, source catalog, UPSERT operations with transaction safety, collection logging/metrics, startup cleanup, and seed data.

## Requirements

### Requirement: SQLite database schema with 11 tables
The system SHALL maintain a SQLite database with 11 tables: `fontes_financiamento` (source catalog), `oportunidades` (collected opportunities), `buscas_salvas` (saved searches), `editais_rastreados` (tracked opportunities), `perfil_usuario` (user profile), `historico_buscas` (search history), `colaboradores` (potential partners), `pesquisadores_vencedores` (CIMATEC researchers), `projetos_aprovados` (approved projects), `logs_coleta` (collection audit), `metrics_coleta` (performance metrics). Tables are created idempotently via `CREATE TABLE IF NOT EXISTS`.

#### Scenario: Fresh database creation
- **WHEN** `init_database()` is called on a non-existent database file
- **THEN** all 11 tables are created and seeded with default data

#### Scenario: Existing database preservation
- **WHEN** `init_database()` is called on an existing database
- **THEN** tables are created only if missing; existing data is preserved

### Requirement: Opportunidades table schema
The system SHALL maintain the `oportunidades` table with 35 columns: `id_registro` (TEXT PK), `entidade`, `pais_origem`, `titulo`, `subtitulo`, `descricao_resumida`, `descricao_completa`, `tipo_oportunidade`, `modalidade`, `area_tematica`, `palavras_chave`, `elegibilidade`, `publico_alvo`, `nivel_academico`, `instituicao_financiadora`, `valor_financiado` (REAL), `moeda`, `data_publicacao`, `data_abertura`, `data_limite`, `data_encerramento`, `status_oportunidade`, `link_origem`, `link_detalhe`, `link_documento_pdf`, `idioma`, `localidade`, `observacoes`, `texto_bruto`, `pagina_coletada` (INTEGER), `fonte_oficial`, `data_hora_coleta`, `hash_deduplicacao` (TEXT UNIQUE), `campos_inferidos_ia`.

#### Scenario: Record insertion with all fields
- **WHEN** a record with all 35 fields is inserted via `upsert_opportunities()`
- **THEN** the record is stored with all fields preserved

#### Scenario: Upsert on conflict
- **WHEN** a record with an existing `id_registro` is inserted
- **THEN** the existing record is updated with the new values (all fields except PK)

### Requirement: Source catalog with 11 funding sources
The system SHALL maintain a source catalog in `fontes_financiamento` with 11 entries: cnpq, capes, finep, fapesb, horizon_europe, erc, sigitec, undp, embrapii, daad, quantum. Each entry includes: id_fonte, nome_fonte, sigla, pais, categoria, tipo_financiador, url_principal, url_oportunidades, metodo_coleta, idioma, periodicidade_atualizacao, observacoes.

#### Scenario: Source catalog initialization
- **WHEN** `seed_sources()` is called
- **THEN** all 11 sources are inserted via UPSERT (existing sources are updated)

#### Scenario: Source removal
- **WHEN** `init_database()` runs and a source ID is not in the 11 configured IDs
- **THEN** the orphaned source is deleted from `fontes_financiamento`

### Requirement: Upsert operation with transaction safety
The system SHALL insert/update opportunities via `upsert_opportunities()` which: processes rows sequentially within a transaction (`dbBegin`/`dbCommit`), uses `INSERT ... ON CONFLICT(id_registro) DO UPDATE SET ...`, generates `hash_deduplicacao` via MD5 of `entidade + titulo` if missing, generates `id_registro` as `auto_{hash16}` if missing, and rolls back on error.

#### Scenario: Successful batch upsert
- **WHEN** 10 new records are upserted
- **THEN** all 10 are inserted and the committed count is returned

#### Scenario: Partial failure rollback
- **WHEN** the 5th record in a batch of 10 causes a constraint error
- **THEN** the transaction is rolled back and 0 records are committed

### Requirement: Collection logging and metrics
The system SHALL log collection executions via `log_collection()` which inserts into `logs_coleta` with: fonte, metodo_coleta, status_execucao (sucesso/erro), mensagem, n_paginas, n_registros, url, data_execucao. Performance metrics are logged via `log_metric()` into `metrics_coleta` with: fonte, timestamp, metric_type, metric_value, context (JSON).

#### Scenario: Successful collection logged
- **WHEN** a source collection completes with 15 records
- **THEN** a row is inserted into `logs_coleta` with `status_execucao = "sucesso"` and `n_registros = 15`

#### Scenario: Failed collection logged
- **WHEN** a source collection fails with an error
- **THEN** a row is inserted into `logs_coleta` with `status_execucao = "erro"` and the error message

### Requirement: Database cleanup on startup
The system SHALL clean the database on startup via `cleanup_database_opportunities()` which: (1) applies `is_funding_opportunity_heuristics()` to all records and deletes non-funding entries, (2) performs retroactive deduplication by `(entidade, title_norm)` keeping the best record by status/date/content length.

#### Scenario: Non-funding records removed
- **WHEN** the database contains records with titles matching "manual do cartão"
- **THEN** those records are deleted during startup cleanup

#### Scenario: Duplicate records consolidated
- **WHEN** the database contains two records with the same entity and normalized title
- **THEN** only the best record (by status priority) is kept

### Requirement: Seed data for demo and testing
The system SHALL seed initial data on fresh database creation: 2 demo opportunities (CNPq + Horizon Europe), 2 saved searches (quantum technologies), 3 collaborators (UFES, TU Berlin, USP), 5 CIMATEC researchers with expertise, 6 approved projects, user profile (SENAI CIMATEC, quantum focus). Seeds are idempotent — skipped if data already exists.

#### Scenario: Demo data on fresh database
- **WHEN** `init_database()` creates a new database
- **THEN** 2 demo opportunities and all seed data are inserted

#### Scenario: Seed idempotency
- **WHEN** `seed_demo_opportunities()` is called on a database with existing opportunities
- **THEN** no demo records are inserted
