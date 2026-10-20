## Why

O README.md está desatualizado em relação ao estado real do sistema. Após o change `baseline-spec` (arquivado 2026-07-11) que estabeleceu 6 main specs, o README precisa ser sincronizado com a realidade: 11 fontes configuradas (não 6), contagens de linhas corretas, fontes ativas corretas, e variáveis de ambiente precisas.

## What Changes

- Atualização do `README.md` na raiz do projeto (~578 linhas)
- Correção de "6 fontes" para 11 fontes em toda a documentação
- Correção de contagens de linhas por módulo
- Correção da tabela "Fontes Ativas" (adicionar sigitec, undp, embrapii, daad, quantum)
- Correção da seção "Fontes Descontinuadas" (remover EMBRAPII e DAAD que estão ativos)
- Correção de env var `GROQ_RATE_DELAY` para `AI_DELAY_BETWEEN_BATCHES`
- Nenhuma alteração de código — change puramente documental

## Capabilities

### New Capabilities
_(nenhuma — não há mudanças de requisitos)_

### Modified Capabilities
_(nenhuma — o README não afeta specs de requisitos)_

## Impact

- **Arquivo alterado:** `README.md` (raiz do projeto)
- **Código afetado:** Nenhum
- **Dependências:** Nenhuma
