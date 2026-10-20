# Arquitetura — Motor de Status e Pipeline de Enriquecimento (v2.0)

Diagramas e decisões estruturais introduzidos pelo change OpenSpec
`funding-hub-v2-hardening` (BUG-01..14 / MELHORIA-01..05).

## 1. Motor de Status Derivado (fonte única da verdade)

Estado antes: `classify_status()` calculava o status **uma vez na coleta** e o
campo congelado `status_oportunidade` era renderizado diretamente — prazos
futuros apareciam como ENCERRADO e prazos passados como ABERTO.

Estado depois:

```
                  +---------------------------+
  SQLite ------> |      read_app_data()      |      (Dados crus + status legado)
                  +-------------+-------------+
                                |
                                v
                       +------------------+
  Sys.Date() (tz) ---> |  derive_status()  |  <-- puro, rederivado a CADA render
  America/Sao_Paulo    |  (helpers_status) |        (data_limite, data_abertura,
                       +------------------+         texto_bruto, today)
                                |
            +-------------------+-------------------+
            v                   v                   v
  Tabela (badge)          Modal (Ficha Rápida)   KPI "Urgentes (14 dias)"
  Filtro "somente         +------> derive_status <------+--------------------+
  urgentes"               |      +------> recomendações gating (derivado != encerrado)
                          |  count_urgent_status (somente "encerrando")
```

**Invariantes:** (I-1) nenhuma superfície lê `status_oportunidade` para
render; (I-2) o campo armazenado é informativo de coleta; (I-3) regra temporal
única: `diff < 0 → encerrado`, `0 ≤ diff ≤ 14 → encerrando`,
`data_abertura > hoje → em_breve`, senão `aberto`; sem data → heurística de
texto; sem sinal → `desconhecido`.

## 2. Pipeline de Enriquecimento Resiliente

```
                          ┌────────────────────────────────┐
   Record coletado ──────>│ enrichment_status = "pendente" │
                          └───────────────┬────────────────┘
                                          v
                        ┌─────────────────────────────────┐
                        │ trim_for_ai (4k + janelas + 2k) │  BUG-09
                        └────────────────┬────────────────┘
                                         v
                        ┌─────────────────────────────────┐
                        │ tentativas (até 3) + backoff 2^n │  BUG-02
                        └───────────────┬─────────────────┘
                    sucesso ──┐       ┌─|─ falha/após tentativas
                              v       v
                 ┌─────────────────────┐   ┌──────────────────────────────┐
                 │ validate_ai_schema  │   │ enrichment_status = "falha"   │
                 │ (enums, 5 keywords, │   │ + enrichment_error            │
                 │  datas, R3 no‑status)│  │ + apply_heuristic_fallback() │
                 └──────────┬──────────┘   └──────────────┬───────────────┘
                            v                             v
                 ┌─────────────────────┐   ┌──────────────────────────────┐
                 │ campos preenchidos   │   │ WARN audit: campo por origem  │
                 │ + provenance ok      │   │ (helpers_utils/log_write)     │
                 └──────────┬──────────┘   └──────────────┬───────────────┘
                            └───────────────┬─────────────┘
                                            v
                     upsert_opportunities (38 colunas, provenance persistida)
```

**Proveniência (BUG-08/MH-03):** `enrichment_status`, `enrichment_model`,
`enrichment_at`, `enrichment_error` — migração idempotente em `helpers_db.R`
(`migrate_enrichment_columns`, `migration_flags`).

## 3. Datas e Qualidade

- **BUG-03:** `extract_dates_contextual` — janelas ±120 chars em torno de
  keywords de prazo + filtro `hoje±2 anos`; `extract_core_record`/finalização
  nunca mais usam `max()` global de todas as datas.
- **BUG-13:** `parse_date_safe` marca `attr(..., "confidence") = "low"` quando
  DD/MM vs MM/DD produzem datas distintas + WARN auditado.
- **MH-02:** `compute_data_quality_score` (100 − 30 sem prazo − 20 ano
  inconsistente − 25 pub após prazo − 15 prazo fora de janela) + badge
  `Qualidade: N%` na tabela/modal.

## 4. Adesão (score) — single source of truth

```
search_query ──> collect_interest_signature(conn, query) ──> interest_sig (reactiveVal)
                                                                 │
                                    +──────────┬─────────────────┤
                                    v          v                 v
                             base_results   modal (score + chips)  recomendações
                             (lista)        matched_keywords()
```

## 5. Coleta e Performance (MH-05, BUG-06, BUG-12)

```
fontes_financiamento ──> collect_sources_parallel (future/multisession,
                         SCRAPE_WORKERS=4, erros isolados por fonte)
                              │
                              v
                   source_dispatch ──> needs_headless(url) ──> Playwright/chromote
                              │                              (portais JS/CDN)
                              v
              EU (horizon_europe/erc): CORDIS API fallback p/ prazos ausentes
                              │
               finalize_records (hash sem data_limite + date_confidence WARN)
                              │
               upsert_opportunities (hash UNIQUE estável BUG-12)
```

## 6. Campos alterados / migração

| Tabela | Alteração | Migração |
|---|---|---|
| `oportunidades` | +4 colunas (`enrichment_*`) → 38 colunas (34 base + 4) | `migrate_enrichment_columns` (idempotente) |
| `migration_flags` | nova tabela de marcas | `CREATE TABLE IF NOT EXISTS` |
| `hash_deduplicacao` | fórmula sem `data_limite` | `migrate_dedup_hashes` (marca `dedup_hash_v2` v1) |

## 7. Segurança

- Chave Gemini: `x-goog-api-key` header — sem `?key=` na URL (BUG-10).
- `redact_keys_in_text` aplicado em mensagens de log para nunca vazar material
  de API key.
