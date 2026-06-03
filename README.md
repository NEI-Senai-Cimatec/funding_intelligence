
# Funding Intelligence Hub — versão reescrita com coleta oficial

Aplicação em **R/Shiny** para busca, monitoramento e recomendação de oportunidades de financiamento científico e tecnológico.

## O que mudou

Esta versão reescreve a camada de coleta para partir **diretamente das páginas oficiais** das entidades financiadoras, com:

- scraping direto dos portais oficiais cadastrados;
- tentativa de paginação automática (`next`, paginação numérica e padrões `/page/n/` quando aplicável);
- coleta de metadados essenciais por registro;
- extração de texto de PDFs quando o edital estiver no documento;
- enriquecimento opcional com **Gemini**, via `Sys.getenv("GEMINI_API_KEY")`;
- deduplicação por título normalizado, link, data limite e hash;
- persistência em SQLite;
- exportação automática em **CSV**, **RDS** e **XLSX**.

## Estrutura de arquivos

- `app.R` — interface e servidor Shiny
- `R/helpers_utils.R` — utilitários, datas, parsing, logging e normalização
- `R/helpers_db.R` — banco SQLite, seed e persistência
- `R/helpers_text.R` — busca booleana e filtros estruturados
- `R/helpers_ai.R` — integração opcional com Gemini
- `R/helpers_recommend.R` — score de aderência e recomendação
- `R/helpers_collect.R` — scraping oficial, paginação, PDFs e exportação
- `www/styles.css` — estilos da interface

## Pacotes necessários

Instale antes de rodar:

```r
install.packages(c(
  "shiny", "bslib", "DT", "dplyr", "tidyr", "purrr", "stringr", "stringi", "lubridate",
  "ggplot2", "plotly", "DBI", "RSQLite", "jsonlite", "digest", "htmltools",
  "rvest", "xml2", "httr2", "tibble", "tools", "readr", "writexl", "janitor",
  "glue", "progress", "pdftools", "polite", "future", "furrr"
))
```

Se quiser usar fallback para páginas muito dependentes de JavaScript, também pode instalar:

```r
install.packages("chromote")
```

## Configuração da IA

A integração com Gemini é opcional. Defina a chave por variável de ambiente.

### Windows (sessão atual)

```r
Sys.setenv(GEMINI_API_KEY = "SUA_CHAVE_AQUI")
```

### Linux/macOS

```bash
export GEMINI_API_KEY="SUA_CHAVE_AQUI"
```

## Como executar

No diretório do projeto:

```r
shiny::runApp()
```

## Fluxo de uso

1. Abra o app.
2. Clique em **Atualizar base**.
3. Selecione as fontes oficiais, limite de páginas e se deseja usar IA.
4. Execute a coleta.
5. A aba **Resultados** será atualizada a partir da base SQLite.
6. Os exports serão salvos em `data_exports/`.

## Observações técnicas

- Algumas fontes internacionais listadas funcionam mais como **portais de programas e chamadas** do que como listas únicas de editais; por isso o coletor segue links oficiais com vocabulário de funding antes de consolidar os registros.
- Em páginas com PDF, o sistema guarda o link do documento e tenta extrair texto com `pdftools`.
- Em páginas com JavaScript mais pesado, o código tenta `chromote` se ele estiver instalado.
- O sistema foi organizado para expansão. Para adicionar uma nova fonte, faça o cadastro em `source_catalog()` e, se necessário, crie um coletor dedicado em `helpers_collect.R`.
