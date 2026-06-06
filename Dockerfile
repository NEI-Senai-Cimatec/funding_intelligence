FROM rocker/r-ver:4.4.0

# Instala dependências de sistema necessárias no Linux
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

# Instala dependências Python (Playwright) e navegadores
RUN pip3 install --no-cache-dir playwright && \
    playwright install --with-deps chromium

# Cria diretório da aplicação
WORKDIR /app

# Copia os arquivos da aplicação
COPY . .

# Remove otelsdk (telemetria) que vem pré-instalada e causa erros de libprotobuf ausente
RUN rm -rf /usr/local/lib/R/site-library/otelsdk

# Instala pacotes do R necessários usando os binários pré-compilados do Posit Package Manager (Ubuntu Jammy)
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest')); \
    pkgs <- c('shiny', 'bslib', 'DT', 'dplyr', 'tidyr', 'purrr', 'stringr', 'stringi', 'lubridate', \
              'ggplot2', 'plotly', 'DBI', 'RSQLite', 'jsonlite', 'digest', 'htmltools', \
              'rvest', 'xml2', 'httr2', 'tibble', 'readr', 'writexl', 'janitor', \
              'glue', 'progress', 'pdftools', 'polite', 'callr', 'shinycssloaders', \
              'reticulate', 'chromote', 'googledrive', 'httr', 'memoise', 'ratelimitr', 'uuid'); \
    install.packages(pkgs, dependencies = TRUE); \
    errors <- lapply(pkgs, function(pkg) { \
      tryCatch({ loadNamespace(pkg); NULL }, error = function(e) list(pkg = pkg, msg = e$message)) \
    }); \
    errors <- errors[!vapply(errors, is.null, logical(1))]; \
    if (length(errors) > 0) { \
      msg_details <- vapply(errors, function(x) sprintf('%s (%s)', x$pkg, x$msg), character(1)); \
      stop(paste('Falha ao instalar pacotes:', paste(msg_details, collapse = '; '))); \
    }"

# Define permissões adequadas para execução no container
RUN mkdir -p logs data_exports && chmod -R 777 logs data_exports

# Expõe a porta padrão do Shiny
EXPOSE 3838

# Inicializa o Shiny App escutando em todas as interfaces de rede (0.0.0.0) na porta 3838
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]
