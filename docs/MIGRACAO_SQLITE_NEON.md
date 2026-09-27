# Migração SQLite → PostgreSQL (Neon.tech)

> **Guia operacional** da migração de persistência do Radar da Inovação/QuIIN.
> Escrito para quem conhece apenas o `README.md`: cada passo pode ser copiado e
> executado sem entender o código por dentro. Data da migra original: setembro/2026.

---

## Sumário

1. [O que mudou e por quê](#1-o-que-mudou-e-por-quê)
2. [SQLite local × Neon: as duas modalidades](#2-sqlite-local--neon-as-duas-modalidades)
3. [Como o app escolhe o banco](#3-como-o-app-escolhe-o-banco)
4. [Parte A — Configurar o Neon do zero](#4-parte-a--configurar-o-neon-do-zero)
5. [Parte B — Migrar os dados](#5-parte-b--migrar-os-dados)
6. [Parte C — Deploy no Posit Connect](#6-parte-c--deploy-no-posit-connect)
7. [Validação de ponta a ponta](#7-validação-de-ponta-a-ponta)
8. [Repetir tudo do zero (checklist)](#8-repetir-tudo-do-zero-checklist)
9. [Nuances e armadilhas](#9-nuances-e-armadilhas)
10. [Troubleshooting](#10-troubleshooting)
11. [Segredos e segurança](#11-segredos-e-segurança)

---

## 1. O que mudou e por quê

**Antes:** o app gravava tudo em `funding_intelligence.sqlite` (arquivo local) e
sincronizava cópias com o Google Drive. Problemas: o arquivo morria junto com a
máquina/ambiente, cada instância do Posit Connect tinha "seu próprio" banco e a
sincronização era um ponto de falha extra.

**Depois:** o banco é um **PostgreSQL gerenciado (Neon.tech)**, compartilhado por
qualquer instância que receba a `DATABASE_URL`. O SQLite continua existindo como
**fallback local** (para quem roda o app sem configurar nada). O Google Drive foi
removido por completo (`R/helpers_drive.R` não existe mais).

Arquivos-chave da migração:

| Arquivo | Papel |
|---|---|
| `schema.sql` | Fonte única do schema PostgreSQL (12 tabelas, PKs, FKs, índices) |
| `migrate_to_neon.R` | Script one-off que copia dados do SQLite para o Neon |
| `R/helpers_db.R` | Camada de conexão: `conectar_banco()`, `prepare_sql()`, `db_exec()/db_qry()` |
| `app.R` | Recebe `DATABASE_URL`, valida pacotes e propaga a URL ao job `callr` |
| `neon.ts` | Infraestrutura-de-código do Neon (política da branch) — **não contém schema SQL** |
| `manifest.json` | Lista de pacotes R que o Posit Connect instala no deploy |

---

## 2. SQLite local × Neon: as duas modalidades

O mesmo código roda nos dois backends. A tabela abaixo resume as diferenças que
você precisa ter em mente:

| Aspecto | SQLite (local, fallback) | PostgreSQL (Neon) |
|---|---|---|
| Quando é usado | `DATABASE_URL` **ausente** | `DATABASE_URL` **presente** |
| Arquivo/conexão | `funding_intelligence.sqlite` (arquivo no disco) | Rede, porta 5432, SSL obrigatório |
| Driver R | `RSQLite` | `RPostgres` (precisa estar instalado) |
| Quem cria as tabelas | O próprio app (`create_tables()` na inicialização) | **Você**, executando `schema.sql` fora do app; o app só **verifica** |
| Modo de escrita | PRAGMA WAL + busy timeout | Transações + `SAVEPOINT` por linha no upsert |
| Fuso horário | Strings sem fuso; leitura interpreta como UTC | Sessão fixada em `TimeZone=UTC` (via `options=-c TimeZone=UTC`) |
| Placeholders de SQL | aceita `?` e `:nome` | aceita **apenas** `$1..$n` |
| Seeds iniciais | Cria dados demo (perfil, buscas, editais demo) | Apenas verifica schema e semeia/poda o catálogo de fontes — dados vêm da migração |
| Persistência | Some se o container/arquivo for descartado | Persistente, compartilhado, com branches do Neon |
| Acesso no deploy | Não é confiável (ambiente efêmero) | Caminho oficial de produção |

### Fluxo de escrita (idêntico nos dois casos)

```
UI (app.R)
  └─ helpers_db.R  →  prepare_sql() converte placeholders p/ o dialect ativo
       ├─ SQLite local: funding_intelligence.sqlite
       └─ Postgres:     Neon (upsert com SAVEPOINT por linha)

Botão "Atualizar base"
  └─ callr::r_bg()  →  processo filho recebe DATABASE_URL explicitamente
       └─ conectar_banco() → grava DIRETO no Neon (sem arquivo intermediário)
```

---

## 3. Como o app escolhe o banco

Toda a decisão cabe em **uma variável de ambiente**: `DATABASE_URL`.

```r
# R/helpers_db.R
conectar_banco <- function(db_path = "funding_intelligence.sqlite") {
  database_url <- trimws(Sys.getenv("DATABASE_URL"))
  if (nzchar(database_url)) {
    return(conectar_postgres(database_url))   # → Neon (RPostgres)
  }
  get_db_connection(db_path)                  # → SQLite local
}
```

Regras derivadas disso:

1. **Com `DATABASE_URL` o app NUNCA cai no SQLite** se a conexão falhar: ele
   registra `[DB] Falha ao conectar: ...` e segue com `conn = NULL`
   (a tela pode mostrar dados demo em memória — sinal de que a conexão falhou).
2. **Sem `DATABASE_URL`, o `RPostgres` nem é exigido** — rodar localmente sem
   instalar `RPostgres` é suportado.
3. O processo filho do `callr` (coleta em background) recebe a variável por
   argumento (`database_url_bg`) e a reexporta com `Sys.setenv()` — não depende
   do ambiente herdado.
4. **Testes** (`tests/testthat/helper-load-helpers.R`) removem `DATABASE_URL` no
   início: a suíte roda sempre em SQLite, independente da máquina.
5. `prepare_sql()` converte automaticamente `?`/`:nome` → `$1..$n` quando o
   backend é Postgres. **Nunca escreva SQL `$n` "na mão"** nos helpers: escreva
   no estilo SQLite e deixe o wrapper converter.

---

## 4. Parte A — Configurar o Neon do zero

Pré-requisitos: Node.js ≥ 18, uma conta Neon, este repositório clonado.

### A1. Instalar a CLI e entrar

```bash
npm i -g neon@latest
neon login
```

> **Windows:** use `neon login` **sem** `--keyring`. O armazenamento em keyring
> do sistema não está disponível e o comando falha com
> `This CLI cannot use the OS keyring`. O credential fica em arquivo
> (`~/.config/neon/credentials.json`).

O login abre o navegador e expira em ~60 s — clique em **Approve** rápido.

### A2. Vincular o projeto e a branch

```bash
neon link --project-id SEU_PROJECT_ID --branch production -y
```

Na migração original o projeto foi criado pelo fluxo de agentes da Neon
(`neon skills -y`, `neon mcp -y`, `neon init`) e vinculado assim:

```bash
neon skills -y        # skills de agente em .agents/skills (opcional, só p/ agentes)
neon mcp -y           # configura o MCP da Neon nos agentes (opcional, só p/ agentes)
neon link --project-id purple-field-04703768 --branch production -y
```

O `neon link` cria o arquivo de contexto `.neon` (gitignorado) e puxa três
variáveis para `.env.local` (também gitignorado):

```
DATABASE_URL            ← pooled (use esta no app)
DATABASE_URL_UNPOOLED   ← direta (sem pooler)
NEON_BRANCH             ← nome da branch
```

> ⚠️ **O app NÃO lê `.env.local`.** Ele lê `.Renviron` (local) ou as variáveis
> do Posit Connect. Você precisa copiar a `DATABASE_URL` para onde o app lê.

### A3. `neon.ts` e deploy da política da branch

```bash
neon config init       # scaffolds neon.ts e instala @neon/config + @neon/env
neon config plan       # preview (read-only) do que seria alterado
neon deploy            # aplica o neon.ts na branch vinculada
```

O `neon.ts` versionado neste repositório:

```ts
import { defineConfig } from "@neon/config/v1";

export default defineConfig({});
```

> **Nuance crítica:** `neon deploy` aplica **política de infraestrutura**
> (TTL de branches, compute, serviços) declarada em `neon.ts`. Com um config
> vazio ele não faz nada de estrutural e **não executa `schema.sql`**.
> O schema SQL é aplicado separadamente (item A5).

### A4. Pooler e string de conexão

Na migração o endpoint nasceu com `pooler_enabled = false`, e a URL pooled
(`...-pooler...`) é a que usamos no app. Habilitando no Console
(**Project → Endpoints → Connection pooling**) ou via API/MCP:

```bash
neon connection-string production --pooled
```

Confirme que a URL termina em `sslmode=require` e que o host contém `-pooler`.
Existem duas URLs; use a **pooled** no app (o `callr` + múltiplas sessões do
Shiny abrem várias conexões; o pooler do Neon suporta isso melhor).

### A5. Aplicar o schema (`schema.sql`)

O schema **não** é aplicado pelo deploy nem pelo app. Escolha um caminho:

**Caminho 1 — Neon Console (mais simples):**
1. Abra o projeto no console → SQL Editor (branch `production`).
2. Cole o conteúdo inteiro de `schema.sql` → **Run**.

**Caminho 2 — linha de comando (se tiver `psql`/`neon psql`):**

```bash
neon psql production
# dentro do psql:
\i schema.sql
```

**Caminho 3 — rede que bloqueia a porta 5432 (apenas HTTPS liberado):**
use o MCP da Neon (`run_sql` / `run_sql_transaction`) a partir de um agente, ou
o SQL Editor do console. Foi o caminho usado na migração original — veja
[Nuances #9](#9-nuances-e-armadilhas).

O DDL é **idempotente** (`CREATE TABLE/INDEX IF NOT EXISTS`) — rodar de novo é seguro.

**Mudou o `schema.sql` depois?** `IF NOT EXISTS` **não altera** tabelas já
criadas. Colunas novas exigem um `ALTER` manual, ex.:

```sql
ALTER TABLE oportunidades ADD COLUMN IF NOT EXISTS campus TEXT;
```

O app valida isso no startup (`verificar_schema_postgres()`): se faltar tabela
ou coluna, ele **para com mensagem clara** apontando o que aplicar.

### A6. Configurar a `DATABASE_URL` local

1. Copie a URL do `.env.local` (ou do `neon connection-string`) para o
   `.Renviron` **na raiz do projeto**:

```env
DATABASE_URL=postgresql://USUARIO:SENHA@HOST/neondb?sslmode=require
```

2. Instale o driver uma vez:

```r
install.packages("RPostgres")   # Windows/macOS: binário pronto
```

3. **Reinicie a sessão do R** — o `.Renviron` só é lido na inicialização.

---

## 5. Parte B — Migrar os dados

Script: `migrate_to_neon.R`. Ele lê o SQLite local, converte tipos, grava no
Neon com UPSERT e valida as contagens ao final.

### B1. Backup

```bash
cp funding_intelligence.sqlite funding_intelligence.sqlite.backup-$(date +%Y%m%d)
```

### B2. Dry run (não grava nada)

```bash
Rscript migrate_to_neon.R --dry-run
```

Saída esperada: conexão OK, `Schema PostgreSQL verificado:12 tabelas`, e uma
linha por tabela com `origem = destino`. Se as contagens já baterem, os dados
já estão lá.

### B3. Migração real

```bash
Rscript migrate_to_neon.R
```

O script:

| Etapa | O que faz |
|---|---|
| Conversão de tipos | `DATE` nas4 colunas de data; `TIMESTAMPTZ` (UTC) nos campos de horário; `JSONB` nos3 campos JSON validando o conteúdo; `BOOLEAN` em `alerta_ativo` |
| Ordem das tabelas | Respeita as chaves estrangeiras (fontes → pesquisadores → oportunidades → rastreados → projetos → demais) |
| UPSERT | `INSERT ... ON CONFLICT (pk) DO UPDATE` — reexecuções atualizam em vez de duplicar |
| Sequências | Depois de gravar IDs explícitos, realinha as colunas `IDENTITY` (`setval`) para o próximo INSERT não colidir |
| Validação | Compara contagem de cada tabela origem × destino e falha se divergir |

**Referência histórica da migra original:**594 linhas no total
(21 fontes,206 oportunidades,312 métricas,11 buscas,21 logs...). Contagens
atuais mudam com o uso — valide sempre origem × destino, não valores fixos.

> ⚠️ **Idempotente ≠ inofensivo.** Reexecutar o script faz o **snapshot local
> vencer** qualquer alteração feita depois no Neon (mesma chave primária →
> UPDATE com os valores do SQLite). Decida qual lado é a fonte da verdade antes
> de reexecutar.

### B4. Verificação rápida

```r
source("R/helpers_utils.R"); source("R/helpers_db.R")
conn <- conectar_banco("funding_intelligence.sqlite")   # usa DATABASE_URL
DBI::dbListTables(conn)                                  # deve listar12 tabelas
DBI::dbGetQuery(conn, "SELECT count(*) FROM oportunidades")
DBI::dbDisconnect(conn)
```

---

## 6. Parte C — Deploy no Posit Connect

### C1. Variável de ambiente no Connect

No painel do content: **Environment → Variables** (ou Secrets):

| Nome | Valor |
|---|---|
| `DATABASE_URL` | mesma URL do `.Renviron` (marque como secreta) |

Sem essa variável o Connect cai no SQLite do container efêmero — os dados
"somem" a cada restart. Com ela, o app conecta ao Neon.

### C2. Pacotes R: o `manifest.json`

O Connect instala exatamente o que está em `manifest.json` e **não instala
nada em runtime** (o `app.R` detecta o Connect e recusa instalar por conta
própria). Duas regras que causaram os dois deploys quebrados da migra:

1. **Todo pacote em `required_packages` precisa estar no manifesto.**
   Pacotes detectados por estáticos (`RPostgres::Postgres()` em
   `helpers_db.R`) entram automaticamente; pacotes citados só em string
   (ex.: `"readxl"` numa lista) podem ficar de fora → erro
   `Não foi possível carregar/instalar todos os pacotes necessários: X`.
   **Solução:** remover a entrada órfã ou usar o pacote de verdade no código.

2. **Regenere o manifesto após mudar dependências:**

   ```r
   # no console R, na raiz do projeto, com o pacote novo já instalado
   rsconnect::writeManifest(appFiles = system("git ls-files", intern = TRUE))
   ```

   O `appFiles` = `git ls-files` mantém o manifesto alinhado com a árvore que o
   Connect baixa (deploy é git-backed: ele ignora arquivos não commitados).

### C3. Publicar

```bash
git add app.R manifest.json
git commit -m "fix: dependências do deploy"
git push
```

Depois dispare o deploy no painel do Connect (ele busca do GitHub). Confira os
logs: após `Shiny application starting ...` deve aparecer a verificação de
schema (`[DB] Schema PostgreSQL verificado:12 tabelas presentes.`).

### C4. Cadeia completa de escrita em produção

```
Connect (DATABASE_URL) → app.R → conectar_banco() → Neon
                              ↘ callr::r_bg(database_url_bg) → coleta → upsert direto no Neon
```

---

## 7. Validação de ponta a ponta

Checklist após qualquer mudança de schema/config:

```bash
#1. Sintaxe dos arquivos R alterados
Rscript -e "invisible(lapply(list.files('R', full.names=TRUE), parse)); parse(file='app.R'); cat('PARSE_OK\n')"

#2. Suíte de testes (roda em SQLite — não precisa de DATABASE_URL)
Rscript -e "testthat::test_dir('tests/testthat')"

#3. Conexão real + schema (precisa de rede que aceite a porta5432)
Rscript -e "source('R/helpers_utils.R'); source('R/helpers_db.R');
  con <- conectar_banco('funding_intelligence.sqlite');
  print(DBI::dbListTables(con)); DBI::dbDisconnect(con)"

#4. Migração (modo relatório, não grava)
Rscript migrate_to_neon.R --dry-run
```

Critérios de aceite: `PARSE_OK`; suíte sem falhas;12 tabelas listadas;
`DRY_RUN_OK` com todas as linhas `TRUE`.

---

## 8. Repetir tudo do zero (checklist)

Cenário: projeto Neon novo (ou perda do banco) — máquina nova.

- [ ] `npm i -g neon@latest && neon login`
- [ ] `neon link --project-id ... --branch production -y`
- [ ] Editar `neon.ts` se necessário → `neon config plan` → `neon deploy`
- [ ] Habilitar **Connection pooling** no endpoint (host `-pooler`)
- [ ] Aplicar `schema.sql` (Console SQL / `neon psql` / MCP `run_sql`)
- [ ] `neon connection-string production --pooled` → copiar para `.Renviron`
- [ ] `install.packages("RPostgres")` → reiniciar o R
- [ ] Backup do SQLite → `Rscript migrate_to_neon.R --dry-run` → `Rscript migrate_to_neon.R`
- [ ] Validação da seção7
- [ ] No Connect: `DATABASE_URL` na Environment → regenerar `manifest.json` → commit + push → deploy

---

## 9. Nuances e armadilhas

1. **`neon deploy` ≠ schema.** Deploy aplica `neon.ts` (política); o DDL é
   `schema.sql` aplicado à mão. Dois passos, não um.
2. **`IF NOT EXISTS` não atualiza schema existente.** Adicionou coluna em
   `schema.sql`? Faça o `ALTER ... ADD COLUMN IF NOT EXISTS` no banco já criado
   (item A5). O app bloqueia o startup com a lista de colunas faltando — é
   intencional. Caso real: a coluna `campus` faltava no Neon e a tabela de
   resultados não renderizava (`object 'campus' not found`).
3. **Placeholders.** RPostgres aceita só `$1..$n` (nem `?`, nem `:nome`).
   Nunca escreva `$n` nos helpers — `prepare_sql()` converte sozinho; escreva
   SQL portável e passe por `db_exec()`/`db_qry()`.
4. **SAVEPOINT por linha no upsert.** No Postgres um erro aborta a transação
   inteira; o `upsert_opportunities()` cria `SAVEPOINT upsert_row` por linha
   para que uma colisão de `hash_deduplicacao` não perda o lote.
5. **UTC fixo.** A conexão usa `options=-c TimeZone=UTC`, mantendo a semântica
   das strings de data geradas pelo R (idêntica à do SQLite).
6. **Rede × porta5432.** O protocolo Postgres usa a porta5432. Redes com
   inspeção de tráfego (firewall institucional) matam o payload depois do
   handshake — sintoma: `SSL SYSCALL error: Connection reset by peer` logo no
   início. Diagnóstico: TLS para a443 funciona,5432 reseta. **Soluções:**
   VPN/hotspot, ou executar de outra rede (ex.: o próprio Connect), ou aplicar
   SQL só por HTTPS (Console/MCP). Migração de dados exige5432 liberado.
7. **`DATABASE_URL` errada → fallback silencioso.** Host que não resolve
   (ex.: URL antiga de outro provedor) gera `[DB] Falha ao conectar` e a tela
   pode mostrar dados demo — verifique os logs antes de concluir que "funcionou".
8. **Fallback SQLite local continua vivo.** Sem `DATABASE_URL`, tudo funciona
   offline em `funding_intelligence.sqlite` (WAL + busy timeout). Útil para
   desenvolvimento e para a suíte de testes.
9. **HTTPS como via de escape.** Quando só80/443 passam na rede, dá para
   aplicar schema e dados via Neon Console (SQL Editor) ou MCP da Neon
   (`run_sql`, `run_sql_transaction`). A migração original usou o MCP exatamente
   por isso — os dados foram carregados em transações de ~400 KB com contagens
   validadas ao final.
10. **Docker.** A imagem instala `RPostgres` e `libpq`; o `docker-compose`
    repassa `DATABASE_URL`. Sem ela, o container roda em SQLite local.
11. **Google Drive removido.** Não existem mais `drive_upload_db()` /
    `drive_download_db()`. Se encontrar menções em scripts antigos (`scratch/`),
    elas estão obsoletas.

---

## 10. Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| Deploy: `...pacotes necessários: RPostgres` | `RPostgres` fora do `manifest.json` | Instalar o pacote localmente e regenerar o manifesto (C2) |
| Deploy: `...pacotes necessários: readxl` (ou outro) | Pacote em `required_packages` sem uso real e fora do manifesto | Remover a entrada da lista em `app.R` (ou usar o pacote no código) e regenerar o manifesto |
| Tabela vazia + `Error: [object Object]` na aba Resultados | Coluna nova no código ausente no banco | `ALTER TABLE ... ADD COLUMN` + backfill; o app passa a bloquear o startup com a mensagem exata |
| `[DB] Falha ao conectar: could not translate host name` | `DATABASE_URL` com host errado/antigo | Corrigir a URL no `.Renviron`/Connect; `neon connection-string` para obter a atual |
| `SSL SYSCALL error: Connection reset` / timeout na porta5432 | Rede bloqueia payload fora de443/80 | VPN/hotspot ou outra rede; SQL via HTTPS nesse meio-tempo |
| `Schema ausente no PostgreSQL: ...` | `schema.sql` não aplicado | Aplicar o DDL (A5) |
| `Colunas ausentes em 'oportunidades' ...` | Schema local mais novo que o banco | Rodar o `ALTER ... ADD COLUMN` indicado (A5) |
| `This CLI cannot use the OS keyring` (Windows) | `--keyring` incompatível | Usar `neon login` simples |
| App conecta mas mostra dados demo | Conexão falhou e caiu no fallback em memória | Procurar `[DB] Falha ao conectar` nos logs |
| Migração: `DATABASE_URL não configurada` | Variável fora do ambiente do R | Exportar no shell ou definir no `.Renviron` e reiniciar o R |
| Coleta `could not find function "source_dispatch"` em ambiente paralelo | Helpers sourced no `globalenv` fora do processo `callr` | Comportamento do `future`: no app real os helpers vão no frame do processo filho; validar com `SCRAPE_WORKERS=1` fora do app |

---

## 11. Segredos e segurança

- **Nunca** commite: `.Renviron`, `.env.local`, `.neon/`. Todos estão no
  `.gitignore` e o `manifest.json` nunca deve listá-los.
- URLs de banco contêm senha: ao logar, **redija** (o script de migração já
  imprime `postgresql://***@host`).
- No Connect, use **Secrets** para `DATABASE_URL`.
- O login da Neon e a API key do MCP atingem toda a conta — não os copie para
  chats, issues ou logs.
- Rotacionou senha/URL no Neon? Atualize `.Renviron` **e** a variável do
  Connect, depois reinicie o app.

---

## Referências

- `README.md` — visão geral do produto, variáveis de ambiente e testes
- `docs/ARCHITECTURE.md` — motor de status e pipeline de enriquecimento
- `schema.sql` — schema PostgreSQL versionado
- `migrate_to_neon.R` — script de migração (uso na própria cabeça do arquivo)
- Documentação Neon: <https://neon.com/docs>
- Posit Connect (manifesto/dependências): <https://docs.posit.co/connect/>
