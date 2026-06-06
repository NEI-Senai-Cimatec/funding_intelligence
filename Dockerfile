FROM rocker/r-ver:4.4.0

# Instala dependências de sistema necessárias no Linux
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpoppler-cpp-dev \
    sqlite3 \
    libsqlite3-dev \
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

# Instala pacotes do R necessários e garante que a instalação foi bem-sucedida
RUN R -e "options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    pkgs <- c('shiny', 'bslib', 'DT', 'dplyr', 'tidyr', 'purrr', 'stringr', 'stringi', 'lubridate', \
              'ggplot2', 'plotly', 'DBI', 'RSQLite', 'jsonlite', 'digest', 'htmltools', \
              'rvest', 'xml2', 'httr2', 'tibble', 'readr', 'writexl', 'janitor', \
              'glue', 'progress', 'pdftools', 'polite', 'callr', 'shinycssloaders', \
              'reticulate', 'chromote', 'googledrive'); \
    install.packages(pkgs); \
    missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]; \
    if (length(missing) > 0) stop(paste('Falha ao instalar pacotes:', paste(missing, collapse = \", \")))"

# Define permissões adequadas para execução no container
RUN mkdir -p logs data_exports && chmod -R 777 logs data_exports

# Expõe a porta padrão do Shiny
EXPOSE 3838

# Inicializa o Shiny App escutando em todas as interfaces de rede (0.0.0.0) na porta 3838
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]
