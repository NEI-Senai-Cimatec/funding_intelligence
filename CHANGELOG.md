# Changelog

Todas as alterações relevantes da plataforma QuIIN - Funding Intelligence Hub.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/);
versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [2.1.0] - 2026-11-05

Revisão "Radar da Inovação e SITE do NEI" (itens 1 a 11 do documento de revisão).

### Changed
- Login com layout no estilo SIG QuIIN: fundo tecnológico, cartão translúcido com a marca
  Radar da Inovação, identificação institucional no topo e faixa de logos (NEI, SENAI CIMATEC, FIEB).
- Subtítulo do cabeçalho: "Plataforma de inteligência de fomento à P&D+I".
- Rodapé: "Superintendência de Planejamento e Novos Negócios".
- Filtros "Área Temática" e "Idioma" removidos do sidebar e da busca avançada.
- `tipo_oportunidade` padronizado na leitura da base (`classify_tipo_oportunidade`):
  Bolsas, Fomento à pesquisa, Fomento a eventos, Financiamento, Subvenção econômica, Prêmio,
  Licitação, Incentivos fiscais à PD&I, Capital de risco, Outros. Valor bruto preservado em
  `tipo_oportunidade_fonte`.
- Abas temáticas: colunas "Análise & Justificativa" e "Ideia de Projeto / Consórcio" substituídas
  por "Objeto de Financiamento".
- Heurística de aderência por campus usa só título + resumo e casa palavra inteira (antes lia o
  texto bruto da página e casava substrings, ex.: "rov" em "improve"); justificativas antigas
  geradas pela heurística são recalculadas na exibição.
- Palavras-chave oficiais por campus (`CAMPUS_SEARCH_QUERIES`: Sertão, Aeroespacial, Mar, Digital,
  SENAI CIMATEC amplo) usadas no filtro de Campi e no relatório, e cadastradas como Buscas Salvas.

### Fixed
- Abas temáticas ignoravam os filtros do sidebar (ex.: "Status = Abertos" mostrava editais encerrados).
- Relatório DOCX: marcadores `{{campo_n}}` quebrados pelo Word em vários runs não eram substituídos;
  downloads DOCX/PDF agora avisam o usuário em caso de falha.
- `status_display_label` podia retornar lista (R < 4.4) e quebrar a tabela de resultados.

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
