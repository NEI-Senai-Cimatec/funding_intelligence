## Context

O QuIIN é um aplicativo Shiny com ~6.000 linhas de código distribuídas em `app.R` e 7 módulos helpers. A base de código inclui:
- UI com bslib/Bootstrap 5 e 6 abas
- Pipeline de coleta com 11 coletores especializados e cascata HTTP de 3 níveis
- Integração com 8 provedores de IA com fallback automático
- SQLite com 11 tabelas e sincronização Google Drive
- Processos background via `callr::r_bg()` com streaming de logs

A documentação existente é o README.md (~580 linhas), que cobre visão geral e Quick Start, mas não detalha contratos entre módulos, regras de negócio granulares, nem fluxos de dados internos. Não há specs formais.

## Goals / Non-Goals

**Goals:**
- Documentar o estado atual do sistema como especificação formal e testável
- Capturar regras de negócio implicitamente codificadas (dedup, heurísticas, classificação)
- Documentar contratos entre módulos (input/output de cada função-chave)
- Criar base para futuras mudanças arquiteturais com referência precisa
- Manter consistência com o código existente (não criar novas funcionalidades)

**Non-Goals:**
- Propor melhorias ou refatorações
- Documentar código de teste/scratch
- Criar documentação de API para usuários finais
- Alterar qualquer arquivo de código
- Documentar dependências de sistema ou configuração de deploy (já cobertas pelo README)

## Decisions

### Decision 1: Estrutura de specs por capacidade funcional

**Escolha:** Organizar specs por capacidade funcional (app-architecture, collection-pipeline, etc.) em vez de por arquivo de código.

**Alternativas consideradas:**
- Por arquivo (`app.R spec`, `helpers_collect.R spec`): Mais fácil de mapear para código, mas não captura fluxos que cruzam módulos.
- Por camada (`UI spec`, `Data spec`, `AI spec`): Mais alinhado com arquitetura, mas agrupa demais e dificulta localização.

**Racional:** A organização por capacidade permite que cada spec seja autocontida e testável, mapeando diretamente para os cenários de uso do sistema.

### Decision 2: Specs como documentação do estado atual (não delta)

**Escolha:** Criar specs completos do estado atual (ADDED Requirements) em vez de modifications.

**Racional:** Não existem specs prévios. Este change estabelece a baseline, então todos os requisitos são novos.

### Decision 3: Formato de cenários WHEN/THEN

**Escolha:** Usar formato WHEN/THEN para todos os cenários, mesmo para documentação pura.

**Racional:** O formato é conciso, testável, e força clareza sobre o comportamento esperado. Mesmo que não haja testes automatizados para todas as capacidades, o formato estabelece o padrão para specs futuros.

## Risks / Trade-offs

- **[Risk] Documentação pode ficar desatualizada** → Mitigação: Specs referenciam localizações específicas no código (`file:line`), facilitando verificação futura
- **[Risk] Specs podem estar incompletos** → Mitigação: Foco nas capacidades mais críticas (coleta, IA, dedup) que representam 80% da complexidade do sistema
- **[Trade-off] Granularidade** → Specs detalhados vs. visão executiva. Escolhemos detalhamento médio — cada requirement tem pelo menos 1 cenário, mas não cobrimos cada branch de código
