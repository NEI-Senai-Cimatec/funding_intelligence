## 1. Source Catalog

- [x] 1.1 Add Humboldt entry to `source_catalog()` in `R/helpers_db.R` (id_fonte="humboldt", nome_fonte="Alexander von Humboldt Foundation", sigla="HUMBOLDT", pais="Alemanha", metodo_coleta="html", idioma="en")
- [x] 1.2 Add "humboldt" to the list of valid source IDs in `init_database()` cleanup query

## 2. Collector Implementation

- [x] 2.1 Create `collect_humboldt()` function in `R/helpers_collect.R` — fetch listing page with filterBy=schollarships + filterBy=award, parse teaser cards
- [x] 2.2 Implement `extract_humboldt_listing()` — parse `.teaser.teaser--small` cards: title, For whom, From where, For what, detail URL
- [x] 2.3 Implement `extract_humboldt_detail()` — fetch detail page, extract icon-list metadata and main content section
- [x] 2.4 Implement `normalize_humboldt_country()` — map "From where" text to normalized country names (Brazil→Brasil, Germany→Alemanha, etc.)
- [x] 2.5 Implement `infer_humboldt_status()` — detect "closing date has elapsed" → encerrado, "next application round" → futuro, else → aberto
- [x] 2.6 Register collector: `register_collector("humboldt", collect_humboldt, "Humboldt Foundation HTML scraper")`

## 3. Record Mapping

- [x] 3.1 Map Humboldt fields to 35-column schema: titulo, elegibilidade, descricao_resumida, descricao_completa, link_detalhe, entidade="Alexander von Humboldt Foundation", fonte_oficial="humboldt", pais_origem="Alemanha", idioma="en"
- [x] 3.2 Set tipo_oportunidade based on listing filter: "fellowship" for scholarships, "award" for awards
- [x] 3.3 Generate hash_deduplicacao via digest::digest(paste0(titulo, "|", link_detalhe), algo="xxhash64")

## 4. Integration & Testing

- [x] 4.1 Test collector manually: `collect_humboldt(source_row, max_pages=5, max_records=20, use_ai=FALSE, log_path=NULL)`
- [x] 4.2 Verify records pass `finalize_records()` and `is_funding_opportunity_heuristics()` filters
- [x] 4.3 Update README.md: change "11 fontes" → "12 fontes", add Humboldt to Fontes Ativas table

## 5. Documentation

- [x] 5.1 Add Humboldt to the `collection-pipeline` main spec as a new requirement
- [x] 5.2 Update `data-model` main spec to reflect 12 sources in source catalog
