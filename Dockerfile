# ── Estágio 1: instalação e validação de pacotes (Builder) ─────────────────────
FROM rocker/r-ver:4.4.0 AS builder

# Instala dependências de sistema necessárias para compilação/instalação no builder
# libuv1-dev é necessário para compilação e carregamento do pacote 'fs' (dependência do googledrive e polite)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpoppler-cpp-dev \
    sqlite3 \
    libsqlite3-dev \
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfontconfig1-dev \
    libprotobuf23 \
    libuv1-dev \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Instala pacotes do R usando os binários pré-compilados do Posit Package Manager (Ubuntu Jammy)
# Valida a instalação de todos os pacotes e remove o otelsdk que causa problemas de libprotobuf
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest')); \
  pkgs <- c( \
    'shiny', 'bslib', 'DT', 'dplyr', 'tidyr', 'purrr', \
    'stringr', 'stringi', 'lubridate', 'ggplot2', 'plotly', \
    'DBI', 'RSQLite', 'jsonlite', 'digest', 'htmltools', \
    'rvest', 'xml2', 'httr2', 'tibble', 'readr', 'writexl', \
    'janitor', 'glue', 'progress', 'pdftools', 'polite', \
    'callr', 'shinycssloaders', 'reticulate', 'chromote', \
    'googledrive', 'httr', 'memoise', 'ratelimitr', 'uuid', \
    'readxl' \
  ); \
  suppressMessages(install.packages(pkgs, dependencies = TRUE)); \
  tryCatch(remove.packages('otelsdk'), error = function(e) invisible(NULL)); \
  failed <- Filter( \
    Negate(is.null), \
    lapply(pkgs, function(pkg) { \
      tryCatch( \
        { loadNamespace(pkg); NULL }, \
        error = function(e) sprintf('%s (%s)', pkg, e\$message) \
      ) \
    }) \
  ); \
  if (length(failed) > 0) \
    stop(paste('Pacotes faltando:', paste(unlist(failed), collapse = '; '))); \
  message('Build OK — ', length(pkgs), ' pacotes validados.') \
"

# ── Estágio 2: imagem de runtime enxuta (Runtime) ──────────────────────────────
FROM rocker/r-ver:4.4.0

# Instala dependências de runtime necessárias para a execução
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 \
    curl \
    openssl \
    libxml2 \
    libpoppler-cpp9v5 \
    sqlite3 \
    libsqlite3-0 \
    libpng16-16 \
    libjpeg62-turbo \
    libtiff5 \
    libfreetype6 \
    libharfbuzz0b \
    libfribidi0 \
    libfontconfig1 \
    libprotobuf23 \
    libuv1 \
    python3 \
    python3-pip \
    python3-venv \
    wget \
    ca-certificates \
    && wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y --no-install-recommends ./google-chrome-stable_current_amd64.deb \
    && rm google-chrome-stable_current_amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# Configura ambiente Python para o reticulate
ENV RETICULATE_PYTHON=/usr/bin/python3
# Configura o diretório compartilhado dos browsers do Playwright
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright

# Instala dependências Python (Playwright + Stealth) e baixa o chromium para o local compartilhado
RUN pip3 install --no-cache-dir playwright playwright-stealth && \
    playwright install --with-deps chromium && \
    chmod -R 755 /usr/local/share/playwright

# Copia a biblioteca do R compilada do estágio anterior
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Cria diretório da aplicação e configura permissões
WORKDIR /app

# Copia os arquivos da aplicação
COPY . .

# Cria usuário não-privilegiado 'shiny' e ajusta permissões
RUN groupadd -r shiny && useradd -r -g shiny -d /home/shiny -m shiny && \
    mkdir -p logs data_exports && \
    chown -R shiny:shiny /app && \
    chmod -R 755 logs data_exports

# Executa o container com o usuário não-privilegiado
USER shiny

# Expõe a porta padrão do Shiny
EXPOSE 3838

# Inicializa o Shiny App escutando em todas as interfaces de rede (0.0.0.0) na porta 3838
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]
