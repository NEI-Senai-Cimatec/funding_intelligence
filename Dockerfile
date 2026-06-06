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
    chromium \
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

# Instala pacotes do R necessários globalmente no container
RUN R -e "options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    install.packages(c('shiny', 'bslib', 'DT', 'dplyr', 'tidyr', 'purrr', 'stringr', 'stringi', 'lubridate', \
                       'ggplot2', 'plotly', 'DBI', 'RSQLite', 'jsonlite', 'digest', 'htmltools', \
                       'rvest', 'xml2', 'httr2', 'tibble', 'readr', 'writexl', 'janitor', \
                       'glue', 'progress', 'pdftools', 'polite', 'callr', 'shinycssloaders', \
                       'reticulate', 'chromote'))"

# Define permissões adequadas para execução no container
RUN mkdir -p logs data_exports && chmod -R 777 logs data_exports

# Expõe a porta padrão do Shiny
EXPOSE 3838

# Inicializa o Shiny App escutando em todas as interfaces de rede (0.0.0.0) na porta 3838
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]
