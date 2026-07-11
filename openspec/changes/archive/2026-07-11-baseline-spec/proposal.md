## Why

O sistema QuIIN não possui documentação estruturada da arquitetura atual. A base de código cresceu organicamente (~6.000 linhas entre app.R e 7 helpers), mas não existe uma especificação que descreva o estado atual do sistema como um todo — fluxos de dados, regras de negócio, contratos entre módulos, e decisões de design. Isso é crítico para:

- Onboarding de novos desenvolvedores
- Base para futuras mudanças arquiteturais
- Validação de integridade entre componentes
- Registro de regras de negócio implicitamente codificadas (dedup, heurísticas, cascata de HTTP)

## What Changes

- Criação de documentação de baseline em formato de especificação estruturada
- Documentação completa da arquitetura do aplicativo Shiny (UI + server + processos background)
- Documentação do pipeline de coleta de dados (11 coletores, cascata HTTP, rate limiting)
- Documentação das regras de negócio (dedup, heurísticas de validação, classificação de status)
- Documentação do modelo de dados (SQLite com 11 tabelas)
- Documentação da integração com IA (8 provedores, prompts, fallback chain)
- Nenhuma alteração de código — este é um change puramente de documentação

## Capabilities

### New Capabilities
- `app-architecture`: Arquitetura do aplicativo Shiny — UI bslib, server reativo, gerenciamento de processos background via callr, inicialização e sincronização Google Drive
- `collection-pipeline`: Pipeline de coleta de dados — 11 coletores especializados, cascade HTTP (httr2→Playwright→Chromote), detecção de CDN/CAPTCHA, rate limiting por domínio
- `business-rules`: Regras de negócio — heurísticas de validação de editais, deduplicação, classificação de status/idioma/tipo, filtro por ano corrente
- `data-model`: Modelo de dados — schema SQLite com 11 tabelas, operações CRUD, seed data, migrações
- `ai-integration`: Integração com IA — 8 provedores, pipeline de extração em 2 estágios, tradução automática, circuit breaker
- `search-recommendation`: Busca booleana e recomendação — parser AST, filtros estruturados, score de aderência ponderado, parceiros CIMATEC

### Modified Capabilities
_(nenhuma — este change não modifica requisitos existentes)_

## Impact

- **Documentação criada:** 6 arquivos de especificação em `openspec/changes/baseline-spec/specs/`
- **Código afetado:** Nenhum — change puramente documentacional
- **Dependências:** Nenhuma
- **Sistemas:** Nenhum
