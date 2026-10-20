# QuIIN - QFunding Intelligence Hub

[![R 4.6+](https://img.shields.io/badge/R-4.6+-blue.svg)](https://www.r-project.org/)
[![Shiny](https://img.shields.io/badge/Shiny-1.8+-orange.svg)](https://shiny.posit.co/)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg)](#licença)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg)](https://www.docker.com/)
[![SENAI CIMATEC](https://img.shields.io/badge/SENAI--CIMATEC-004691.svg)](https://www.senaicimatec.com.br/)

Plataforma de inteligência estratégica para monitoramento, busca booleana avançada e recomendação personalizada de editais de financiamento científico e tecnológico — nacionais e internacionais.

Centraliza **21 fontes de fomento** (CNPq, CAPES, FINEP, FAPESB, Horizon Europe, ERC, SIGITEC, UNDP, EMBRAPII, DAAD, Quantum, Humboldt + 9 fontes dos EUA: Grants.gov, DOE ASCR, NSF OISE/QISE/CISE/NQNI, DOE Quantum Genesis/Genesis Mission, DARPA QBI) em uma única interface, enriquece cada oportunidade com IA generativa multi-provedor, traduz automaticamente registros europeus para pt-br e recomenda parceiros internos com base em afinidade temática.

---

## Visão Geral

| Componente | Status |
|---|---|
| Autenticação GoTrue & RBAC (Diretoria / Leitor) | ✅ Produção |
| Sessões Persistentes (`localStorage` + JWT Auto-Refresh) | ✅ Produção |
| Coleta multi-agência (21 fontes nacionais e internacionais) | ✅ Produção |
| Processamento assíncrono (background via `callr`) | ✅ Produção |
| Enriquecimento com IA (8 provedores com healthcheck e failover) | ✅ Produção |
| Tradução automática pt-br (fontes internacionais) | ✅ Produção |
| Busca booleana avançada (AST parser com operadores lógicos) | ✅ Produção |
| Aderência dinâmica e cálculo de relevância multicritério | ✅ Produção |
| Recomendação de parceiros internos SENAI CIMATEC | ✅ Produção |
| Banco PostgreSQL gerenciado (Neon.tech / Supabase) | ✅ Produção |
| Fallback e sincronização para SQLite local | ✅ Produção |
| Exportação de relatórios em XLSX e CSV com links diretos | ✅ Produção |
| Containerização Docker & Deploy Posit Connect | ✅ Produção |

---

## Quick Start

### 1. Instalar dependências

```r
install.packages(c(
  "shiny", "bslib", "DT", "dplyr", "tidyr", "purrr", "stringr", "stringi",
  "lubridate", "ggplot2", "plotly", "DBI", "RSQLite", "jsonlite", "digest",
  "htmltools", "rvest", "xml2", "httr2", "tibble", "readr", "writexl",
  "janitor", "glue", "progress", "pdftools", "polite", "callr",
  "shinycssloaders", "reticulate", "chromote", "httr",
  "memoise", "uuid"
))

# Apenas quando usar PostgreSQL (DATABASE_URL configurada):
install.packages("RPostgres")
```

### 2. Configurar variáveis de ambiente

Crie o arquivo `.Renviron` na raiz do projeto:

```env
# ─── Provedores de IA (pelo menos uma chave configurada) ───────────────
NVIDIA_API_KEY=nvapi-...
GROQ_API_KEY=gsk_...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=AIza...

# ─── Autenticação e RBAC (Supabase GoTrue) ──────────────────────────────
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_ANON_KEY=sua-chave-anon-publica
SUPABASE_DEV_EMAILS=diretoria@cimatec.com.br,admin@cimatec.com.br

# ─── Persistência (PostgreSQL Neon / Supabase) ─────────────────────────
# Se omitida, a aplicação utiliza automaticamente o SQLite local como fallback
DATABASE_URL=postgresql://usuario:senha@host:5432/postgres?sslmode=require
```

### 3. Executar

```r
shiny::runApp()
```

A aplicação estará disponível em `http://localhost:3838`.

---

## Arquitetura do Sistema

```mermaid
flowchart TD
    subgraph Client [Navegador do Usuário]
        UI[Interface Shiny / Bootstrap 5]
        AuthJS[auth.js: Sessão localStorage & Auto-Refresh]
    end

    subgraph Auth [Camada de Segurança & RBAC]
        GoTrue[Supabase Auth / GoTrue REST API]
        HelpersAuth[helpers_auth.R: Validação JWT & Perfis]
        PerfisDB[(Tabela public.perfis)]
    end

    subgraph Core [Camada de Lógica & Negócio]
        Utils[helpers_utils.R: Sanitização & Formatadores]
        TextSearch[helpers_text.R: AST Boolean Parser]
        Recommend[helpers_recommend.R: Scoring Multicritério]
        Export[helpers_export.R: XLSX / CSV]
    end

    subgraph Data [Camada de Coleta & IA]
        Collect[helpers_collect.R: Motor Multi-Agência]
        Stealth[tools/stealth_fetch.py: TLS Stealth Scraper]
        DB[helpers_db.R: Dialect Abstraction]
        AI[helpers_ai.R: Multi-LLM Healthcheck & Failover]
    end

    subgraph Storage [Persistência & Logs]
        Postgres[(PostgreSQL: Neon / Supabase)]
        SQLite[(SQLite Local: Fallback & Sync)]
        AuditLogs[(user_access_logs)]
        ExportsDir[(data_exports/)]
    end

    subgraph External [Fontes & Provedores Externos]
        Portais[21 Portais de Financiamento]
        LLMAPIs[APIs: NVIDIA, OpenAI, Groq, Gemini]
    end

    UI <--> AuthJS
    AuthJS <--> GoTrue
    UI <--> HelpersAuth
    HelpersAuth <--> PerfisDB
    HelpersAuth --> AuditLogs
    UI <--> Core
    Core <--> Data
    Collect --> Stealth
    Stealth --> Portais
    Collect --> Portais
    AI --> LLMAPIs
    DB --> Postgres
    DB --> SQLite
    Export --> ExportsDir
```

---

## Fontes de Dados

### Fontes Ativas

| ID | Fonte | País | Método de Coleta | Idioma |
|---|---|---|---|---|
| `cnpq` | Conselho Nacional de Desenvolvimento Científico e Tecnológico | Brasil | HTML scraper | pt |
| `capes` | Coordenação de Aperfeiçoamento de Pessoal de Nível Superior | Brasil | Plone API + HTML fallback | pt |
| `finep` | Financiadora de Estudos e Projetos | Brasil | Liferay REST API | pt |
| `fapesb` | Fundação de Amparo à Pesquisa do Estado da Bahia | Brasil | WordPress REST API | pt |
| `horizon_europe` | Horizon Europe | UE | EU F&T Portal REST API | en → pt (tradução automática) |
| `erc` | European Research Council | UE | EU F&T Portal REST API | en → pt (tradução automática) |
| `sigitec` | Petrobras SIGITEC | Brasil | REST API | pt |
| `undp` | UNDP Brasil | Brasil | JS component + HTML | pt |
| `embrapii` | EMBRAPII | Brasil | HTML scraping | pt |
| `daad` | DAAD Brasil | Alemanha | Hybrid JSON+HTML | en |
| `quantum` | EU Quantum Technologies | UE | EU FTOP REST API | en |
| `humboldt` | Alexander von Humboldt Foundation | Alemanha | HTML scraping | en |
| `grants_gov` | Grants.gov - U.S. Department of State | Estados Unidos | Hybrid API + HTML (CFDA 19.040) | en |
| `doe_ascr` | DOE Advanced Scientific Computing Research | Estados Unidos | HTML + OSTI API fallback | en |
| `nsf_international` | NSF Office of International Science and Engineering | Estados Unidos | HTML scraping | en |
| `nsf_qise` | NSF QISE International Supplements | Estados Unidos | HTML scraping (DCL) | en |
| `nsf_cise` | NSF CISE | Estados Unidos | Hybrid API + HTML | en |
| `doe_quantum_genesis` | DOE Quantum Genesis Initiative | Estados Unidos | HTML single-page monitor | en |
| `doe_genesis` | DOE Genesis Mission | Estados Unidos | HTML single-page monitor | en |
| `nsf_nqni` | NSF National Quantum Nanotechnology Infrastructure | Estados Unidos | HTML + PDF (nsf26-505) | en |
| `darpa_quantum_benchmarking` | DARPA Quantum Benchmarking Initiative | Estados Unidos | HTML + Playwright Stealth | en |

**Coletores especializados:**

- `collect_capes` — Plone REST API (`/++api++/pt-br/@search`) com fallback Playwright
- `collect_finep` — Liferay Headless Delivery API com filtro `situacao=aberta`
- `collect_fapesb` — WordPress REST API (`/wp-json/wp/v2/posts?categories=11`)
- `collect_horizon_europe` — EU F&T Portal Search API com 21 termos de busca (EIC, MSCA, WIDERA, CL2-CL5, EURATOM)
- `collect_erc` — EU F&T Portal Search API com termos ERC específicos
- `collect_sigitec` — REST API SIGITEC com listing + detalhe por ID
- `collect_undp` — Componente externo UNDP (JSON) + HTML de detalhe
- `collect_embrapii` — Parsing HTML estático da página de transparência
- `collect_daad` — Híbrido: JSON catálogo global (scholarships.js) + HTML scraping detalhe
- `collect_quantum` — EU F&T Portal Search API com busca por keyword "quantum"
- `collect_humboldt` — HTML scraping da Humboldt Foundation (listing + detalhe)
- `collect_grants_gov` — Hybrid API + HTML scraping Grants.gov (CFDA 19.040 Public Diplomacy, filtra NOFOs/APs)
- `collect_doe_ascr` — HTML scraping DOE ASCR + OSTI API fallback (HPC, quantum, AI for Science, FY2026 deadline 30/09/2026)
- `collect_nsf_international` — HTML scraping NSF OISE International Collaborations
- `collect_nsf_qise` — HTML scraping DCL QISE International Supplements (Brasil não prioritário)
- `collect_nsf_cise` — Hybrid API + HTML NSF CISE (directorate filtering)
- `collect_doe_quantum_genesis` — Single-page monitor DOE Quantum Genesis (retorna vazio se sem FOA ativa — sem registro fake)
- `collect_doe_genesis` — Single-page monitor DOE Genesis Mission (idem)
- `collect_nsf_nqni` — HTML + PDF parsing NSF NQNI nsf26-505 (US$100M)
- `collect_darpa_quantum_benchmarking` — HTML + Playwright Stealth DARPA QBI
- `collect_generic_official` — Fallback HTML para CNPq e fontes não especializadas

> **Nota sobre fontes EU/US:** Horizon Europe e ERC (e opcionalmente Grants.gov/NSF/DARPA) utilizam a EU F&T Portal API via
> Cloudflare Worker proxy (`EU_API_PROXY_URL`) para contornar bloqueio de IPs da AWS no Posit Connect Cloud.
> A mesma variável `EU_API_PROXY_URL` é generalizada para fontes US quando necessário (Grants.gov, DARPA QBI com WAF).
> Veja a seção [Configuração do Proxy FTOP](#configuração-do-proxy-ftop-cloudflare-worker).

### Fontes Descontinuadas

As seguintes fontes foram removidas na versão atual do sistema (commit `fbaa74c`):

| Fonte | Motivo da Remoção |
|---|---|
| FAPESP, FAPERJ, FAPEMIG, FAPES/ES, FAPESC/SC | FAPES regionais com estruturas de URL instáveis |
| CONFAP, BNDES, MCTI | Fontes com atualização irregular ou baixa aderência |
| Petrobras SIGITEC | API descontinuada ou inacessível |
| NIH, NSF, Wellcome Trust, Gates Foundation | Fontes internacionais com scraping complexo |
| IDRC, UNESCO, World Bank, IDB | Baixo volume de editais relevantes |
| EUREKA Network | Fontes europeias consolidadas no Horizon Europe |
| UNDP Brasil, Ministério da Saúde, iCS | Fontes temáticas com escopo limitado |

---

## Estrutura de Módulos

### `app.R` — Ponto de Entrada (~2.000 linhas)

Interface Shiny com `bslib` e Bootstrap 5. Responsável por:

- Orquestração do ciclo de vida da aplicação e controle reativo de sessões
- Renderização condicional da interface: tela de login/cadastro/recuperação quando não autenticado vs dashboard completo quando autenticado
- Controle de acesso granular baseado em perfis (RBAC): liberação seletiva de abas e botões para `diretoria` vs `leitor`
- Inicialização da persistência (PostgreSQL via `DATABASE_URL` na nuvem, SQLite local como fallback automático)
- Gerenciamento de coleta em background via `callr` com prevenção de processos zumbis
- Streaming de logs de scraping e auditoria em tempo real

### `R/helpers_auth.R` — Autenticação & RBAC (~1.000 linhas)

Módulo de segurança integrado à API REST GoTrue do Supabase:

- `supabase_authenticate()`: autenticação segura via email/senha com retorno de JWT (access_token) e refresh_token
- `supabase_sign_up()`: cadastro de novos usuários com auto-confirmação e vínculo à tabela de perfis
- `supabase_reset_password()`: disparo de email de redefinição de senha oficial
- `supabase_get_user_role()`: resolução de cargo (`diretoria` vs `leitor`) consultando a tabela `public.perfis` no PostgreSQL com fallback por whitelist de emails
- `registrar_log_acesso()`: trilha de auditoria gravando data/hora, email, cargo, IP do cliente e ação (`login`, `logout`, `coleta`) na tabela `user_access_logs`

### `R/helpers_export.R` — Utilitários de Exportação (~115 linhas)

Motor de exportação de dados para planilhas e relatórios:

- `prepare_export_data()`: padroniza as colunas essenciais para exportação institucional (Título, Entidade, Prazo Limite, Link Portal, Link Detalhes, Link PDF)
- `export_to_xlsx()`: geração de arquivos `.xlsx` nativos via `writexl` sem dependência de Java
- `export_to_csv()`: exportação em formato `.csv` compatível com UTF-8
- `generate_export_filename()`: nomenclatura padronizada com timestamp (`quiiin_export_YYYYMMDD_HHMMSS.xlsx`)

### `R/helpers_collect.R` — Motor de Coleta (~4.100 linhas)

Módulo central de extração e web scraping:

1. `source_dispatch()` — despacha estratégia correta para cada `id_fonte`
2. `collect_listing_with_pagination()` — navega páginas de listagem com suporte a paginação assíncrona
3. `extract_detail_bundle()` — baixa detalhes e anexos de cada oportunidade
4. `finalize_records()` — normaliza, infere campos e deduplica via hash determinístico
5. `translate_to_pt_br()` — traduz registros internacionais para pt-br via IA

**Estratégias de requisição (em cascata):**
- `httr2` → `curl_cffi` (TLS fingerprinting stealth) → Playwright (Python via `reticulate`) → `chromote` (R nativo)
- Detecção e contorno de proteções WAF/CDN (Cloudflare, Ray ID, Access Denied)

### `tools/stealth_fetch.py` — Scraper Stealth com Camuflagem TLS (58 linhas)

Utilitário em Python para fontes com bloqueio agressivo de robôs e bot-protection:
- Camuflagem TLS e HTTP/2 via impersonação do Chrome 120 (`curl_cffi`)
- Fallback para Chromium headless automatizado via Playwright com delays humanos
- Utilizado para fontes governamentais e portais com desafios Cloudflare

### `R/helpers_ai.R` — IA Multi-Provedor (~870 linhas)

Pipeline de extração, inferência e auditoria de editais:

1. `skill_extract_metadata()` — extração de metadados estruturados (datas, elegibilidade, valores, áreas)
2. `skill_verify_metadata()` — auditoria automática de consistência e descarte de ruídos
3. `translate_to_pt_br()` — tradução de editais internacionais com terminologia técnica refinada

**Provedores suportados com failover e healthcheck:**
- NVIDIA Build (ex.: `poolside/laguna-xs-2.1`)
- Google Gemini (`gemini-2.0-flash`)
- OpenAI (`gpt-4o-mini`, `gpt-4o`)
- Groq (`llama-3.3-70b-versatile`)
- Anthropic Claude, OpenRouter, DeepSeek, Bluesminds

### `R/helpers_db.R` — Persistência & Dialect Abstraction (~1.100 linhas)

- `conectar_banco()` — roteia dinamicamente por `DATABASE_URL`: PostgreSQL (Neon / Supabase) ou SQLite local
- `prepare_sql()`/`db_exec()`/`db_qry()` — traduz placeholders (`?`, `:nome`) para o dialeto ativo (`$1..$n` no Postgres)
- Sessão Postgres fixada em `TimeZone=UTC` (garantindo paridade de datas com o SQLite)
- SQLite local operando em modo WAL com timeout de concorrência (`busy_timeout = 5000ms`)
- Catálogo de fontes com UPSERT idempotente e migrações automáticas de colunas

### `R/helpers_text.R` — Busca Booleana & AST (247 linhas)

- Lexer tokenizador completo (`AND`, `OR`, `NOT`, parênteses, expressões exatas entre aspas)
- Parser recursivo construindo Árvore Sintática Abstrata (AST)
- Avaliador booleano de alta performance sobre índice textual

### `R/helpers_recommend.R` — Recomendação & Scoring (~230 linhas)

- Score de aderência multicritério robusto: palavras-chave (40%) + áreas temáticas (20%) + financiador (15%) + elegibilidade (15%) + país (10%)
- Algoritmo totalmente vetorizado com suporte determinístico para datasets unitários ou em lote
- Recomendação de pesquisadores e parceiros internos SENAI CIMATEC por afinidade tecnológica

### `R/helpers_utils.R` — Utilitários Gerais (~635 linhas)

- Normalização de texto, extração de valores monetários e conversão contextual de datas
- Operador de coalescência nula `%||%`, helpers de notificação e badges estilizados

### `www/auth.js` — Gerenciador de Sessão no Frontend (284 linhas)

Script JavaScript integrado ao Shiny:
- Armazenamento seguro de tokens e metadados no `localStorage` do navegador
- Restauração automática de sessão pós-refresh (F5) sem recarregar a interface nem expor telas
- Auto-refresh em segundo plano do JWT a cada 50 minutos contra o endpoint `/auth/v1/token`
- Limpeza rigorosa e imediata de credenciais nos formulários durante o logout

### Utilitários de Banco de Dados (`root` e `sql/`)

- `sync_supabase_to_sqlite.R`: script de sincronização bidirecional que espelha as 11 tabelas do Supabase REST para o SQLite local
- `migrate_to_neon.R`: script de migração completa de banco local para instâncias PostgreSQL Neon ou Supabase
- `sql/setup_supabase_perfis.sql`: script DDL para criação da tabela `public.perfis`, triggers de auto-cadastro e políticas de Row Level Security (RLS)

---

## Modelo de Dados

Schema versionado em `schema.sql` (PostgreSQL/Neon). Sem `DATABASE_URL`, o mesmo
modelo é criado em SQLite local (`funding_intelligence.sqlite`).

```
schema.sql (PostgreSQL) / funding_intelligence.sqlite (fallback local)
├── fontes_financiamento      — Catálogo de 11 agências ativas
├── oportunidades             — Editais coletados e enriquecidos pela IA
├── editais_rastreados        — Funil de candidaturas do usuário
├── perfil_usuario            — Preferências institucionais e áreas de interesse
├── buscas_salvas             — Consultas salvas com opção de alerta
├── historico_buscas          — Registro cronológico de buscas executadas
├── colaboradores             — Banco de parceiros externos classificados por expertise
├── pesquisadores_vencedores  — Banco de talentos CIMATEC com expertise declarada
├── projetos_aprovados        — Histórico de captação (FK → pesquisadores_vencedores)
├── logs_coleta               — Rastreabilidade de execuções do scraper
└── metrics_coleta            — Métricas de desempenho por fonte
```

### Tabela `oportunidades` — campos principais

| Campo | Tipo | Descrição |
|---|---|---|
| `id_registro` | TEXT PK | `{fonte}_{hash16}` — identificador único determinístico |
| `hash_deduplicacao` | TEXT UNIQUE | Hash xxHash64 de título + URL de origem |
| `titulo` | TEXT | Título limpo (traduzido para pt-br se fonte EU) |
| `descricao_resumida` | TEXT | Resumo informativo gerado pela IA |
| `palavras_chave` | TEXT | 5–8 termos do domínio científico/tecnológico |
| `elegibilidade` | TEXT | Critérios específicos de elegibilidade |
| `area_tematica` | TEXT | Áreas de conhecimento cobertas |
| `valor_financiado` | REAL | Valor numérico máximo do financiamento |
| `data_limite` | TEXT | Data de submissão (`YYYY-MM-DD`) |
| `status_oportunidade` | TEXT | `aberto` / `encerrado` / `futuro` |
| `idioma` | TEXT | Código do idioma (`pt`, `en`) |
| `campos_inferidos_ia` | TEXT | Lista dos campos preenchidos pela IA (cache) |
| `texto_bruto` | TEXT | Texto completo capturado para indexação |

---

## Pipeline de IA — Fluxo Detalhado

```
Texto Bruto do Edital (até 20.000 chars)
        │
        ▼
┌─────────────────────────────────┐
│  STAGE 1: skill_extract_metadata │
│  • System prompt: persona sênior │
│  • Campos: título, resumo,        │
│    keywords, elegibilidade,       │
│    tipo, status, datas, valor     │
└──────────────┬──────────────────┘
               │ JSON
               ▼
┌─────────────────────────────────┐
│  STAGE 2: skill_verify_metadata  │
│  • Auditoria de resumo           │
│  • Filtragem de keywords ruins   │
│  • Validação de data_limite      │
└──────────────┬──────────────────┘
               │ JSON auditado
               ▼
┌─────────────────────────────────┐
│  STAGE 3: translate_to_pt_br     │
│  • Apenas para fontes EU         │
│  • Traduz titulo + resumo        │
│  • Atualiza idioma para "pt"     │
└──────────────┬──────────────────┘
               │
               ▼
     Salvo no banco SQLite
     (campo campos_inferidos_ia)
```

> **Cache inteligente**: Registros com `campos_inferidos_ia` preenchido são pulados no próximo ciclo.

---

## Como Executar

### Pré-requisitos

| Componente | Versão Mínima | Obrigatório |
|---|---|---|
| R | 4.6+ | Sim |
| RStudio | 2024.04+ | Não (mas recomendado) |
| Docker | 24.0+ | Apenas para Opção 2 |
| Python | 3.10+ | Apenas para scraping JS |

### Opção 1 — Local (R)

```r
# 1. Instalar dependências
source("https://raw.githubusercontent.com/...")  # ou manual conforme Quick Start

# 2. Configurar .Renviron (veja seção Variáveis de Ambiente)

# 3. Executar
shiny::runApp()
```

### Opção 2 — Docker (Recomendado para Produção)

```bash
# 1. Configurar variáveis de ambiente
cp .env.example .env   # edite com suas chaves

# 2. Build e execução
docker compose up -d

# 3. Acessar
open http://localhost:3838
```

### Verificando a Instalação

```r
# Verificar pacotes
pkgs <- c("shiny", "bslib", "DT", "httr2", "DBI", "RSQLite", "reticulate")
missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) warning("Pacotes faltando: ", paste(missing, collapse = ", "))

# Verificar IA
source("R/helpers_ai.R")
ai_available()  # deve retornar TRUE se chave configurada

# Verificar banco (roteia por DATABASE_URL; sem ela, SQLite local)
source("R/helpers_utils.R")
source("R/helpers_db.R")
conn <- conectar_banco("funding_intelligence.sqlite")
DBI::dbListTables(conn)  # deve listar as 12 tabelas da aplicação
DBI::dbDisconnect(conn)
```

---

## Autenticação, Perfis de Usuário & Controle de Acesso (RBAC)

O sistema conta com um módulo robusto de segurança e controle de acesso integrado ao **Supabase Auth (GoTrue REST API)** e tabelas relacionais em PostgreSQL.

> **Guia passo a passo de configuração do Supabase:** [`docs/SUPABASE_AUTH_SETUP.md`](docs/SUPABASE_AUTH_SETUP.md)

### 1. Níveis de Acesso e Matriz de Permissões

| Recurso / Funcionalidade | Usuário Não Autenticado | Leitor / Pesquisador (`leitor`) | Desenvolvedor / Diretoria (`diretoria`) |
|---|:---:|:---:|:---:|
| **Acesso ao Dashboard** | ❌ Bloqueio total (Tela de Login) | ✅ Acesso liberado | ✅ Acesso liberado |
| **Aba "Resultados"** | ❌ Não visualiza | ✅ **Visível** | ✅ **Visível** |
| **Aba "Por financiador"** | ❌ Não visualiza | ✅ **Visível** | ✅ **Visível** |
| **Busca Booleana (AST)** | ❌ Bloqueado | ✅ **Liberado** | ✅ **Liberado** |
| **Exportação XLSX / CSV** | ❌ Bloqueado | ✅ **Liberado** | ✅ **Liberado** |
| **Botão "Atualizar base"** | ❌ Ocultado | ❌ **Ocultado** | ✅ **Visível e Executável** |
| **Aba "Buscas salvas"** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |
| **Aba "Editais rastreados"** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |
| **Logs de Coleta & IA** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |
| **Auditoria de Acessos** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |

> **Garantia de Sigilo:** Nenhum edital, oportunidade ou dado é trafegado pelo servidor Shiny antes da autenticação ser validada com sucesso via `req(rv$user)`.

### 2. Ciclo de Vida da Sessão Persistente (`www/auth.js`)

- **Persistência no Navegador:** Ao autenticar, o token JWT (`access_token`), `refresh_token` e metadados do usuário são persistidos de forma segura no `localStorage` do navegador.
- **Restauração Silenciosa (F5):** Ao recarregar a página, o script `auth.js` verifica a validade da sessão e a restaura automaticamente em segundo plano, sem travamento visual ou risco de loop infinito.
- **Auto-Refresh de Token:** A cada 50 minutos, uma rotina assíncrona solicita novo JWT junto à API do Supabase (`/auth/v1/token?grant_type=refresh_token`), evitando expirações abruptas durante análises longas.
- **Logout Seguro:** Ao clicar em "Sair", os tokens locais são apagados, as credenciais digitadas nos campos de entrada são limpas imediatamente e a sessão no servidor Shiny é terminada.

### 3. Configuração da Tabela de Perfis (`public.perfis`)

O script SQL oficial está disponível em [`sql/setup_supabase_perfis.sql`](sql/setup_supabase_perfis.sql). Ele implementa:
1. Tabela `public.perfis` com chave estrangeira para `auth.users(id)` em cascata.
2. Row Level Security (RLS) protegendo a leitura apenas para usuários autenticados.
3. Trigger PostgreSQL `on_auth_user_created` que cadastra automaticamente novos usuários com o cargo padrão `'leitor'`.
4. Gestão facilitada: a alteração de cargo para `'diretoria'` é feita diretamente pelo **Supabase Table Editor** (interface planilha) ou pelo SQL Editor.

---

## Exportação de Oportunidades (XLSX / CSV)

A plataforma implementa um pipeline completo de extração de dados através de [`R/helpers_export.R`](R/helpers_export.R), gerando planilhas otimizadas para tomadores de decisão e gestores de captação:

1. **Exportação da Tabela Filtrada:**
   - Botões dedicados no topo da visualização de resultados.
   - Gera relatórios em `.xlsx` (via `writexl`) ou `.csv` contendo as 6 colunas prioritárias: **Título**, **Entidade**, **Prazo Limite**, **Link Portal**, **Link Detalhes** e **Link Edital/PDF**.
   - Respeita integralmente os filtros booleanos e de pesquisa ativos na interface.
2. **Exportação Pós-Coleta:**
   - O modal de progresso de coleta disponibiliza botão de download imediato para a diretoria assim que os novos dados são consolidados.
3. **Nomenclatura Padronizada:**
   - Arquivos gerados com timestamp auditável: `quiiin_export_YYYYMMDD_HHMMSS.xlsx`.

---

## Sincronização Bidirecional Supabase ↔ SQLite

Para garantir redundância operacional e facilitar o desenvolvimento offline, o projeto conta com o utilitário [`sync_supabase_to_sqlite.R`](sync_supabase_to_sqlite.R):

- Conecta diretamente aos endpoints REST do Supabase utilizando `SUPABASE_URL` e `SUPABASE_ANON_KEY`.
- Sincroniza as 11 tabelas essenciais para o banco local `funding_intelligence.sqlite`.
- Execução direta via terminal ou script R:
  ```bash
  Rscript sync_supabase_to_sqlite.R
  ```

---

## Migração SQLite → Neon / Supabase (PostgreSQL)

> **Guia completo passo a passo:** [`docs/MIGRACAO_SQLITE_NEON.md`](docs/MIGRACAO_SQLITE_NEON.md)
> — configuração do Neon do zero, migração de dados, deploy no Posit Connect,
> nuances entre os dois backends e troubleshooting.

1. **Schema:** `schema.sql` contém o DDL PostgreSQL (12 tabelas, PKs, FKs e índices).
   Aplique-o no Neon **manualmente** (SQL Editor do Console, `neon psql` ou MCP `run_sql`)
   — `neon deploy` aplica apenas o `neon.ts` (política da branch), não executa o DDL.
   O app apenas verifica a presença das tabelas e colunas na inicialização.
2. **Dados:** `migrate_to_neon.R` copia o SQLite local para o Neon com conversão de tipos
   (DATE, TIMESTAMPTZ/UTC, BOOLEAN, JSONB), preservando IDs e realinhando as sequências:

   ```bash
   export DATABASE_URL="postgresql://...?sslmode=require"
   Rscript migrate_to_neon.R --dry-run   # valida conexão, schema e contagens
   Rscript migrate_to_neon.R             # migra (idempotente: UPSERT por chave primária)
   ```

3. **App:** com `DATABASE_URL` configurada, `app.R` conecta ao Neon; sem ela, usa o SQLite local.
   A coleta do botão "Atualizar base" grava direto no Postgres (o processo `callr` recebe a `DATABASE_URL`).

> **Conectividade:** a aplicação usa a porta **5432/tcp** (protocolo Postgres). Redes institucionais
> com inspeção de tráfego que bloqueiam payloads fora de 443/80 impedem a conexão local — nessas
> redes, aplique schema/dados por caminhos HTTPS (`neon deploy`, Console SQL editor ou o MCP da Neon
> com `run_sql`/`run_sql_transaction`) e execute o app a partir de uma rede sem esse bloqueio
> (ex.: hotspot) ou do ambiente de produção (Posit Connect).

---

## Configuração do Proxy FTOP (Cloudflare Worker)

### Por que é necessário?

A EU F&T Portal API (`api.tech.ec.europa.eu`) **bloqueia requisições vindas de IPs da AWS**. O Posit Connect Cloud roda na AWS, logo as coletas de Horizon Europe e ERC falham sem proxy.

A solução é um **Cloudflare Worker** que atua como intermediário: Connect → Worker (IP não-AWS) → FTOP API.

### Fluxo

```
Posit Connect Cloud (AWS)
        │
        ▼ HTTP POST
Cloudflare Worker (IP neutro)
        │
        ▼ HTTP POST (forward)
api.tech.ec.europa.eu/search?apiKey=SEDIA
        │
        ▼ JSON
Cloudflare Worker → Connect → Grava no banco de dados
```

### Passo 1 — Criar conta Cloudflare

1. Acesse [dash.cloudflare.com](https://dash.cloudflare.com)
2. Crie uma conta gratuita (plano gratuito: 100.000 requisições/dia)

### Passo 2 — Criar o Worker

1. No painel, vá em **Workers & Pages** → **Create** → **Create Worker**
2. Escolha um nome (ex: `ftop-proxy`)
3. Clique em **Deploy** (código inicial irrelevante)

### Passo 3 — Configurar o código do Worker

1. Clique em **Edit code** (aba "Code")
2. Substitua todo o conteúdo pelo código abaixo:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url);

    // Allow CORS from anywhere
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // Forward to FTOP API
    const targetUrl =
      "https://api.tech.ec.europa.eu" + url.pathname + url.search;

    const newRequest = new Request(targetUrl, {
      method: request.method,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        Referer: "https://ec.europa.eu/info/funding-tenders/opportunities/portal/",
        Origin: "https://ec.europa.eu",
        Accept: "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Content-Type": request.headers.get("Content-Type") || "application/x-www-form-urlencoded",
      },
      body: request.method !== "GET" && request.method !== "HEAD" ? await request.arrayBuffer() : undefined,
    });

    const response = await fetch(newRequest);
    const responseBody = await response.arrayBuffer();

    return new Response(responseBody, {
      status: response.status,
      headers: {
        ...corsHeaders,
        "Content-Type": response.headers.get("Content-Type") || "application/json",
      },
    });
  },
};
```

4. Clique em **Deploy**

### Passo 4 — Verificar o Worker

Teste no terminal:

```bash
curl -X POST "https://SEU-WORKER.seu-usuario.workers.dev/search?apiKey=SEDIA&text=HORIZON&pageSize=1"
```

Deve retornar JSON com `"totalResults"` > 0.

### Passo 5 — Configurar no Posit Connect

1. No painel do Connect, vá em **Environment** (ou **Variables**)
2. Adicione a variável:

| Variable | Value |
|---|---|
| `EU_API_PROXY_URL` | `https://SEU-WORKER.seu-usuario.workers.dev` |

3. Faça **restart** do aplicativo

### Troubleshooting

| Sintoma | Causa | Solução |
|---|---|---|
| `curl: (7) Failed to connect` | Worker URL incorreta ou não deployado | Verificar URL no Dashboard do Cloudflare |
| HTTP 404 do Worker | Rota incorreta | Verificar se Worker forwarda corretamente |
| `totalResults: 0` | Filtros de query muito específicos | Testar com `text=HORIZON` primeiro |
| Connect依旧 falha | Variável não propagada | Reiniciar app no Connect após adicionar env var |

---

## Variáveis de Ambiente

O arquivo `.Renviron` na raiz do projeto concentra todas as chaves e flags de configuração do sistema. **Nunca versione este arquivo no Git.**

### Autenticação & Controle de Acesso (Supabase Auth)

| Variável | Descrição | Obrigatório | Exemplo / Padrão |
|---|---|:---:|---|
| `SUPABASE_URL` | URL base do projeto Supabase | **Sim** | `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | Chave pública anônima do Supabase | **Sim** | `eyJhbGciOi...` |
| `SUPABASE_DEV_EMAILS` | Lista de e-mails com cargo de Diretoria permanente | Não | `diretoria@cimatec.com.br,admin@cimatec.com.br` |
| `SUPABASE_SERVICE_ROLE_KEY` | Chave de serviço administrativa (usada apenas em scripts) | Não | `eyJhbGciOi...` |

### Provedores de IA (pelo menos uma chave configurada)

| Variável | Descrição | Modelo Recomendado / Testado |
|---|---|---|
| `NVIDIA_API_KEY` | Chave NVIDIA Build | `poolside/laguna-xs-2.1`, `meta/llama-3.1-70b-instruct` |
| `GROQ_API_KEY` | Chave Groq | `llama-3.3-70b-versatile` |
| `OPENAI_API_KEY` | Chave OpenAI | `gpt-4o-mini`, `gpt-4o` |
| `GEMINI_API_KEY` | Chave Google Gemini | `gemini-2.0-flash` |
| `ANTHROPIC_API_KEY` | Chave Anthropic Claude | `claude-3-5-sonnet-20241022` |
| `DEEPSEEK_API_KEY` | Chave DeepSeek | `deepseek-chat` |
| `OPENROUTER_API_KEY` | Chave OpenRouter | Roteamento multi-modelo |
| `BLUESMINDS_API_KEY` | Chave Bluesminds | API legada institucional |

### Configuração do Pipeline de IA (opcional)

| Variável | Descrição | Padrão |
|---|---|---|
| `AI_PROVIDER` | Força provedor específico (`nvidia`, `groq`, `openai`, `gemini`, etc.) | Auto-detect |
| `AI_MODEL` | Força modelo específico do provedor ativo | Específico por provedor |
| `AI_API_URL` | Endpoint customizado para LLM | Padrão do provedor |
| `AI_MAX_CHARS` | Contexto máximo de texto por edital | `12000` (trim inteligente) |
| `AI_VERIFY_METADATA` | Habilita auditoria automática de qualidade do JSON | `true` |
| `AI_BATCH_SIZE` | Lote de requisições de IA paralelas | `3` |
| `AI_DELAY_BETWEEN_BATCHES` | Intervalo entre lotes de IA (segundos) | `2` |
| `SCRAPE_WORKERS` | Workers para raspagem paralela por fonte | `4` |

### Banco de Dados (PostgreSQL / SQLite)

| Variável | Descrição |
|---|---|
| `DATABASE_URL` | URL de conexão PostgreSQL (Neon ou Supabase com pooler). Se omitida, a aplicação opera em **SQLite local** (`funding_intelligence.sqlite`) sem falhas. Exemplo: `postgresql://postgres:senha@db.host.supabase.co:5432/postgres?sslmode=require` |

### Proxies e Contorno de Bloqueios

| Variável | Descrição | Padrão |
|---|---|---|
| `EU_API_PROXY_URL` | URL do Cloudflare Worker proxy para requisições FTOP API no Posit Connect | Vazio (acesso direto) |

---

## Governança do Repositório e Regras do `.gitignore`

Para manter o repositório limpo, seguro e livre de arquivos temporários, o projeto adota regras estritas de versionamento:

### 1. O que NUNCA deve ser commitado no Git:
- **Segredos e Credenciais:** `.Renviron`, `*.env`, `*.env.local`, `gdrive_credentials.json`
- **Bancos Locais e Lockfiles:** `funding_intelligence.sqlite*`, `*.sqlite-shm`, `*.sqlite-wal`
- **Ambiente Local e Bibliotecas:** `R_libs/`, `node_modules/`, `.Rproj.user/`
- **Arquivos Temporários e Logs de Execução:** `logs/`, `data_exports/`, `*.tmp`, `*.log`, `*.png`
- **Sessões e Perfis Temporários de Teste:** `scratch/`, `scratch_*/`, `scratch_edge_profile*/`
- **Metadados de Agentes e Caches de IDE:** `.neon`, `.impeccable`, `.openspec_cache/`

### 2. O que DEVE ser versionado:
- **Código-fonte:** `app.R`, módulos em `R/` (`helpers_*.R`)
- **Assets Web e Segurança:** `www/styles.css`, `www/auth.js`, `www/senai_cimatec.jpg`, `logos/`
- **Modelagem de Dados e Migrações:** `schema.sql`, `sql/setup_supabase_perfis.sql`, `migrate_to_neon.R`, `sync_supabase_to_sqlite.R`
- **Ferramentas Especializadas:** `tools/stealth_fetch.py`
- **Infraestrutura e Deploy:** `Dockerfile`, `docker-compose.yml`, `.dockerignore`, `manifest.json`
- **Documentação Técnica:** `README.md`, `CHANGELOG.md`, `docs/*.md`
- **Suítes de Teste:** `tests/testthat/`, `tests/playwright/`

---

## Fluxo do Usuário

1. **Exploração Inicial** — Ao abrir pela primeira vez, a base é semeada com dados demonstrativos
2. **Atualizar Base** — Clique em "Atualizar base" para coletar dados frescos (roda em background)
3. **Busca Avançada** — Use lógica booleana: `(quântica OR "tecnologia quântica") AND bolsa NOT licitação`
4. **Aderência Dinâmica** — Score recalculado em tempo real com base na query ativa
5. **Rastrear Editais** — Adicione editais à aba "Editais Rastreados" para acompanhar candidaturas
6. **Parceiros CIMATEC** — Veja pesquisadores internos recomendados para cada edital rastreado
7. ~~**Recomendações**~~ — Aba "Recomendados para mim" atualmente ocultada da UI (código preservado)
8. **Exportação** — Bases consolidadas salvas automaticamente em `data_exports/` (CSV, RDS, XLSX)

---

## Segurança e DevSecOps

- **Docker Non-Root** — Container não executa como `root`
- **PostgreSQL com SSL** — Neon exige `sslmode=require`; sessão fixada em UTC
- **SQLite WAL (fallback local)** — Leituras simultâneas durante escritas
- **Transações ACID** — UPSERT atômico com `dbBegin`/`dbCommit`
- **Prevenção de Zumbis** — `session$onSessionEnded` elimina processos filhos
- **Playwright Stealth** — Camuflagem de fingerprints contra WAFs
- **HEAD Check** — Verificação de saúde do host antes de scraping pesado
- **.dockerignore** — Impede cópia de chaves para imagem Docker

---

## Testes

```bash
# Testar utilitários
Rscript -e "testthat::test_file('tests/testthat/test-utils.R')"
Rscript -e "testthat::test_dir('tests/testthat')"

# Suite E2E Playwright (app rodando em http://localhost:3838)
Rscript tests/playwright/e2e-suite.R

# Testar concorrência SQLite
Rscript scratch/test_db_concurrency.R

# Testar stealth e conexões
Rscript scratch/test_stealth_request.R

# Testar retries da IA
Rscript scratch/test_ai_backoff.R
```

---

## Correções v2.0 (funding-hub-v2-hardening)

Correção dos 14 bugs do catálogo v2.0 + 5 melhorias de backlog (change OpenSpec `funding-hub-v2-hardening`):

| ID | Correção | Onde |
|---|---|---|
| BUG-01/05/11 | Status derivado em render (`derive_status`), nunca o campo congelado — tabela, modal, KPI, filtros e recomendações | `R/helpers_status.R`, `app.R`, `R/helpers_recommend.R`, `R/helpers_collect.R` |
| BUG-02 | Pipeline de enriquecimento resiliente: 3 tentativas com backoff → validação de schema → fallback heurístico obrigatório, com proveniência persistida | `R/helpers_ai.R`, `R/helpers_collect.R`, `R/helpers_db.R` |
| BUG-03/13 | Extração contextual de prazos (janelas ±120 chars), filtro de plausibilidade, consistência ano do título vs ano do prazo e flag de ambiguidade de data | `R/helpers_utils.R`, `R/helpers_collect.R` |
| BUG-04 | Score único (assinatura de interesses por sessão) para lista e modal + chips de termos casados | `R/helpers_recommend.R`, `app.R` |
| BUG-06 | Fontes UE com JS/CDN: cascata prioriza render headless + fallback CORDIS API para prazos ausentes | `R/helpers_collect.R` |
| BUG-07 | Contrato de IA v2 (`AI_ENRICHMENT_PROMPT`): sem status, com valor_estimado/moeda, 5 keywords, confiança e R1-R5; `validate_ai_schema` rejeita e anula campos inválidos | `R/helpers_ai.R` |
| BUG-08 | Proveniência por campo + trilha de auditoria no log de coleta | `R/helpers_ai.R`, `R/helpers_db.R` |
| BUG-09 | `trim_for_ai` preserva prazos/orçamentos no fim de textos longos | `R/helpers_text.R` |
| BUG-10 | Chaves de API apenas em headers (`x-goog-api-key`) + `redact_keys_in_text` | `R/helpers_ai.R` |
| BUG-12 | `hash_deduplicacao` sem `data_limite` (+ migração retroativa idempotente) | `R/helpers_db.R`, `R/helpers_collect.R` |
| BUG-14 | Testes de regressão (testthat TC-01..10 + Playwright E2E-01..07) | `tests/testthat/`, `tests/playwright/` |
| MH-02 | `compute_data_quality_score` + badge de qualidade na tabela e modal | `R/helpers_utils.R`, `app.R` |
| MH-03 | Observabilidade: colunas de enriquecimento + logs WARN de ambiguity/consistency | `R/helpers_db.R`, `R/helpers_utils.R` |
| MH-04 | Banner de proveniência, retry de enriquecimento e deep-link `?id=` | `app.R` |
| MH-05 | Coleta paralela por fonte (`SCRAPE_WORKERS`) + token-bucket por provedor | `R/helpers_collect.R`, `R/helpers_ai.R` |

### Testes (BUG-14)

- **Unitários:** `tests/testthat/test-status-engine.R` (15 casos), `test-date-extraction.R` (TC-06), `test-enrichment-fallback.R` (TC-04/05), `test-ai-schema-validation.R` (TC-09), `test-trim-ai.R` (TC-10), `test-adherence-consistency.R` (TC-08), `test-data-quality.R`, `test-dedup-hash.R` (TC-07 + migrações)
- **E2E Playwright:** `tests/playwright/e2e-suite.R` (E2E-01..07)
- A data de referência usa o fuso `America/Sao_Paulo`; funções de status/data aceitam `today` injetável para testes determinísticos

### `.Renviron` — modelo (chaves SEMPRE em headers, nunca em URL)

```
# Escolha ao menos uma chave de IA (uma por linha):
# GROQ_API_KEY=gsk_...
# GEMINI_API_KEY=AIza...
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...

AI_PROVIDER=groq
AI_MAX_CHARS=12000
AI_VERIFY_METADATA=true
AI_BATCH_SIZE=8
AI_DELAY_BETWEEN_BATCHES=6
SCRAPE_WORKERS=4

# Banco de dados em nuvem (opcional — sem ela o app usa SQLite local)
# DATABASE_URL=postgresql://user:senha@host/db?sslmode=require
```

- **Migração:** ao subir, o app adiciona idempotentemente as colunas `enrichment_status/model/at/error` e recalcula os hashes de deduplicação (sem `data_limite`). Não há perda de dados.

---

## Seções Ocultadas da Interface

| Seção | Estado | Motivo |
|---|---|---|
| Card "Exportação" (Resultados) | ❌ Oculto | Substituído pelos botões de exportação direta (XLSX/CSV) |
| Aba "Recomendados para mim" | ❌ Oculto | Funcionalidade em revisão. Código-fonte preservado e comentado no `app.R` (linhas 332-340) para reativação futura. Toda a lógica de recomendação (`helpers_recommend.R`, `recommended_table`, `profile_summary`, `collaborators_table`) permanece funcional. |

---

## Licença

Proprietária — SENAI CIMATEC / QuIIN. Uso interno autorizado.

---

## Contato

**QuIIN — Núcleo de Economia e Industrial**
SENAI CIMATEC — Salvador, BA, Brasil
