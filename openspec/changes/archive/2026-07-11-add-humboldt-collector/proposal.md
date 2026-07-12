## Why

A Alexander von Humboldt Foundation é uma das mais prestigiosas fundações de pesquisa da Alemanha, oferecendo bolsas (fellowships) e prêmios (awards) para pesquisadores de todo o mundo. O site da Humboldt lista programas de financiamento como fellowships de pesquisa, bolsas de proteção climática, e programas de scouting — todos com detalhes sobre elegibilidade, prazos, e como se candidatar. Integrar essa fonte ao QuIIN permite que pesquisadores brasileiros acessem oportunidades de alta qualidade que atualmente não são monitoradas.

## What Changes

- Novo coletor `collect_humboldt` em `R/helpers_collect.R` (~200 linhas)
- Nova fonte `humboldt` no catálogo de fontes em `helpers_db.R`
- Atualização do `README.md` para listar a nova fonte (11 → 12 fontes)
- Atualização do `Dockerfile` se necessário (não deve ser — scraping via httr2)

## Capabilities

### New Capabilities
- `humboldt-source`: Integração da Alexander von Humboldt Foundation como fonte de dados

### Modified Capabilities
_(nenhuma — este change não modifica requisitos existentes)_

## Impact

- **Código alterado:** `R/helpers_collect.R` (+~200 linhas), `R/helpers_db.R` (+1 linha no source_catalog), `README.md` (atualização de contagem)
- **Dependências:** Nenhuma nova — scraping via httr2//xml2 já disponíveis
- **Risco:** Baixo — site estático (TYPO3), sem proteção anti-bot agressiva
