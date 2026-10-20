## Context

A Humboldt Foundation mantém um catálogo de programas em `humboldt-foundation.de/en/apply/sponsorship-programmes/programmes-a-to-z` com filtros por tipo (All, Awards, Fellowships, Phasing-out). Cada programa é um card com título, público-alvo, país de origem, e duração. Páginas de detalhe contêm seções estruturadas: The fellowship, Sponsorship, Requirements, How to apply, Host institutions, Timeframe, Selection procedure.

O site é construído com TYPO3 CMS, conteúdo estático (sem JS rendering necessário), sem proteção anti-bot agressiva. Scraping via httr2 + xml2 é suficiente.

## Goals / Non-Goals

**Goals:**
- Criar coletor que extraia todos os fellowship/award programs da Humboldt
- Extrair dados estruturados de cada página de detalhe (título, elegibilidade, país, duração, prazo)
- Integrar ao pipeline existente de coleta com suporte a IA
- Filtrar automaticamente programas que aceitam pesquisadores brasileiros ou de países em desenvolvimento

**Non-Goals:**
- Coletar dados de alumni ou rede Humboldt (não é financiamento)
- Monitorar status de aplicações (muito volátil)
- Substituir o site oficial da Humboldt

## Design

### Estrutura do Site Humboldt

**Listing page:**
```
/en/apply/sponsorship-programmes/programmes-a-to-z
  ?tx_rsmavhcontent_programmes[filterBy]=schollarships  (fellowships)
  ?tx_rsmavhcontent_programmes[filterBy]=award          (awards)
  ?tx_rsmavhcontent_programmes[filterBy]=all             (todos)
```

**Cards no listing:**
```html
<article class="teaser teaser--small">
  <h3 class="headline headline--2 teaser__headline">Título do Programa</h3>
  <div class="teaser__text">
    <p><strong>For whom:</strong> público-alvo</p>
    <p><strong>From where:</strong> países de origem</p>
    <p><strong>For what:</strong> descrição/duração</p>
  </div>
  <a href="/en/apply/sponsorship-programmes/slug-do-programa">More</a>
</article>
```

**Detail page:**
```
/en/apply/sponsorship-programmes/{slug}
```
- Header: título + metadata (For whom, From where, For what)
- Seções: The fellowship, Sponsorship, Requirements, How to apply, Timeframe, etc.
- Status: aviso sobre rodada de inscrições (aberta/fechada/próxima)

### Estratégia de Coleta

**Abordagem:** HTML scraping estático (não precisa de Playwright/Chromote).

1. Buscar listing page com filtro `filterBy=schollarships` + `filterBy=award`
2. Extrair cards: título, metadata (for whom, from where, for what), link de detalhe
3. Para cada link de detalhe, extrair seções relevantes
4. Mapear para schema padrão de `oportunidades`

**Decisão:** Usar `collect_listing_with_pagination()` como base, com `page_builder` customizado para a URL de filtros da Humboldt (não é paginação tradicional — são filtros).

**Alternativa considerada:** Buscar apenas a página "All" e filtrar no código. Rejeitado porque a Humboldt tem muitos programas (>30) e queremos apenas fellowships/awards.

### Mapeamento de Campos

| Campo Humboldt | Campo DB | Observação |
|---|---|---|
| Título do card | `titulo` | Direto |
| For whom | `elegibilidade` | Público-alvo |
| From where | `pais_origem` | Normalizar países |
| For what | `descricao_resumida` | Duração + descrição |
| Detail page content | `descricao_completa` | Texto completo da seção principal |
| Link de detalhe | `link_detalhe` | URL absoluta |
| (calculado) | `status_oportunidade` | Inferir de textos de status |
| (calculado) | `idioma` | "en" (site em inglês) |
| (fixo) | `entidade` | "Alexander von Humboldt Foundation" |
| (fixo) | `fonte_oficial` | "humboldt" |
| (fixo) | `pais_origem` | "Alemanha" (sede da fundação) |
| (fixo) | `tipo_oportunidade` | "fellowship" ou "award" |
| (fixo) | `modalidade` | "bolsa" ou "prêmio" |

### Normalização de Países

O campo "From where" varia muito:
- "Brazil" → "Brasil"
- "Germany" → "Alemanha"
- "non-European developing and transition countries" → "Internacional (países em desenvolvimento)"
- "All countries" → "Internacional"

Usar `normalize_country()` existente + extensão para termos da Humboldt.

### Detecção de Status

O site não tem campo de status explícito. Usar heurísticas:
- Texto contém "closing date has elapsed" ou "not currently possible to apply" → `encerrado`
- Texto contém "next application round" com data futura → `futuro`
- Caso contrário → `aberto` (programas permanentes como Georg Forster)

### Deduplicação

Hash: `digest::digest(paste0(titulo, "|", link_detalhe), algo = "xxhash64")`

## Risks / Trade-offs

- **[Risk] Site pode mudar de estrutura** → Mitigação: CSS selectors robustos (classes BEM), fallback para `extract_listing_candidates()` genérica
- **[Risk] Programas podem não ter data de encerramento** → Mitigação: Classificar como "aberto" por padrão, permitir atualização manual
- **[Trade-off] Coletar todos vs. filtrar** → Coletar todos e deixar o usuário filtrar via UI existente
