## Context

O README.md (~578 linhas) é a documentação principal do projeto para novos desenvolvedores e usuários. Após o change `baseline-spec` que estabeleceu 6 main specs documentando o estado real do sistema, uma verificação cruzada revelou múltiplas inconsistências entre o README e o código fonte.

## Goals / Non-Goals

**Goals:**
- Sincronizar o README.md com o estado real do sistema documentado pelos specs
- Corrigir todas as inconsistências factuais (fontes, linhas, env vars)
- Manter a estrutura existente do README (não reescrever do zero)
- Garantir que a documentação seja confiável para onboarding

**Non-Goals:**
- Reescrever a seção de arquitetura (já documentada nos specs)
- Adicionar novas seções ao README
- Alterar código ou specs
- Atualizar a seção de Proxy FTOP (já correta)

## Inconsistências Encontradas

### 1. Número de fontes: 6 → 11

| Local no README | Linha | Texto atual | Correção |
|---|---|---|---|
| Introdução | 11 | "Centraliza **6 fontes de fomento**" | "Centraliza **11 fontes de fomento**" |
| Mermaid diagram | 103 | `Fontes[6 Portais de Fomento]` | `Fontes[11 Portais de Fomento]` |
| Tabela fontes ativas | 124-131 | 6 linhas | Adicionar sigitec, undp, embrapii, daad, quantum |
| Coletores especializados | 133-140 | 6 coletores | Adicionar collect_sigitec, collect_undp, collect_embrapii, collect_daad, collect_quantum |
| helpers_db.R | 203 | "Catálogo de 6 fontes com UPSERT" | "Catálogo de 11 fontes com UPSERT" |
| Modelo de dados | 233 | "Catálogo de 6 agências ativas" | "Catálogo de 11 agências ativas" |

### 2. Fontes descontinuadas incorretas

| Fonte | Status no README | Status real |
|---|---|---|
| EMBRAPII | Listada como descontinuada (linha 153) | **Ativa** — `collect_embrapii` em `helpers_collect.R:3564` |
| DAAD | Listada como descontinuada (linha 157) | **Ativa** — `collect_daad` em `helpers_collect.R:4280` |

**Ação:** Remover EMBRAPII e DAAD da tabela "Fontes Descontinuadas".

### 3. Contagens de linhas desatualizadas

| Módulo | Linha no README | Linhas reais | Delta |
|---|---|---|---|
| `app.R` | 1.541 (linha 164) | ~1.600 | +59 |
| `helpers_collect.R` | ~2.910 (linha 174) | ~4.100 | +1.190 |
| `helpers_ai.R` | 793 (linha 188) | ~867 | +74 |
| `helpers_db.R` | 593 (linha 199) | ~722 | +129 |

### 4. Env var incorreta

| Linha | Texto atual | Correção |
|---|---|---|
| 508 | `GROQ_RATE_DELAY` | `AI_DELAY_BETWEEN_BATCHES` |

### 5. Fontes ativas — dados faltantes

A tabela "Fontes Ativas" (linhas 124-131) precisa de 5 novas linhas:

| ID | Fonte | País | Método | Idioma |
|---|---|---|---|---|
| `sigitec` | Petrobras SIGITEC | Brasil | REST API | pt |
| `undp` | UNDP Brasil | Brasil | JS component + HTML | pt |
| `embrapii` | EMBRAPII | Brasil | HTML scraping | pt |
| `daad` | DAAD Brasil | Alemanha | Hybrid JSON+HTML | en |
| `quantum` | EU Quantum Technologies | UE | EU FTOP REST API | en |

## Decisions

### Decision 1: Atualização pontual vs reescrita completa

**Escolha:** Atualizar apenas as seções inconsistentes, mantendo a estrutura existente.

**Alternativa:** Reescrever o README do zero usando os specs como fonte.

**Racional:** A estrutura atual é boa (Quick Start, Arquitetura, Fontes, Módulos, Modelo de Dados, Pipeline IA, Variáveis de Ambiente, Proxy FTOP). Apenas dados específicos estão desatualizados.

### Decision 2: Manter design.md como documento de arquitetura

**Escolha:** Manter o design.md criado anteriormente como documentação de arquitetura, separado do README.

**Racional:** O design.md documenta decisões técnicas (por que callr, por que SQLite WAL, etc.) — informação que não pertence ao README (que é para usuários/developers, não para decisões de design).

## Risks / Trade-offs

- **[Risk] README pode ficar desatualizado novamente** → Mitigação: specs em `openspec/specs/` são a fonte da verdade; o README deve ser derivado deles
- **[Trade-off] Granularidade** → README mantém visão executiva; specs mantêm detalhesgranulares
