# Changelog

Todas as alterações relevantes da plataforma QuIIN - Funding Intelligence Hub.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/);
versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [2.0.0] - 2026-09-02

Change OpenSpec: `funding-hub-v2-hardening` (14 bugs + 5 melhorias).

### Added
- Motor de status derivado `R/helpers_status.R` (`derive_status`/`derive_status_vec`),
  fonte única da verdade para tabela, modal, KPI e recomendações (BUG-01/05/11).
- Pipeline de enriquecimento resiliente com backoff, `validate_ai_schema` e
  `apply_heuristic_fallback` (BUG-02/07).
- Extração contextual de prazos `extract_dates_contextual`, validação de
  consistência ano-título vs ano-prazo e flag de ambiguidade de data (BUG-03/13).
- Camada de qualidade de dados `compute_data_quality_score` + badge (MH-02).
- Assinatura de interesses por sessão (cache) + chips de termos casados (BUG-04/MH-01).
- Fallback CORDIS API para prazos ausentes em fontes UE e priorização headless
  em portais JS/CDN (BUG-06).
- Coleta paralela por fonte (`SCRAPE_WORKERS`) e token-bucket por provedor (MH-05).
- Banner de proveniência de IA, botão de retry e deep-link `?id=` (MH-04).
- Suites de testes: testthat (TC-01..10) + Playwright E2E-01..07 (BUG-14).
- `AI_ENRICHMENT_PROMPT` v2 com R1-R5, few-shot e confiança por campo.

### Fixed
- Status congelado no banco exibido como ENCERRADO em prazos futuros (BUG-01).
- Modal vazio quando a IA falha — agora exibe heurísticas + banner (BUG-02).
- Datas de rodapé contaminando prazos via `max()` global (BUG-03).
- Score divergente entre lista e modal (BUG-04).
- KPI "Urgentes" inconsistente com a tabela (BUG-05).
- Prazos "-"/status DESCONHECIDO em fontes UE (BUG-06).
- Chaves de API Gemini expostas na URL (BUG-10) — agora em header
  `x-goog-api-key`; `redact_keys_in_text` protege logs.
- `hash_deduplicacao` incluía `data_limite`, duplicando editais (BUG-12).

### Changed
- Contrato de IA v2: `status_oportunidade` nunca é campo da IA; adicionados
  `valor_estimado`/`moeda`; exatamente 5 palavras-chave (BUG-07).
- `trim_for_ai` agora preserva prazos/orçamentos no fim de textos longos (BUG-09).
- Tabela `oportunidades` passa a ter 38 colunas (4 de proveniência de
  enriquecimento) com migração idempotente de bancos existentes.

### Migration Notes
- Na subida, o app executa automaticamente:
  1. `ALTER TABLE oportunidades ADD COLUMN` (enrichment_status, enrichment_model,
     enrichment_at, enrichment_error) — apenas se ausentes;
  2. Recalculo do `hash_deduplicacao` (sem `data_limite`) na primeira subida
     após a atualização (marca `dedup_hash_v2` no `migration_flags`).
- Nenhuma coluna é removida; `status_oportunidade` permanece no schema como
  valor informativo de coleta (o render ignora e rederiva).
