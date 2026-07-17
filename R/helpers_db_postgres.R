# Helper para conexão com PostgreSQL
# Suporta Supabase, Neon, ou qualquer PostgreSQL compatível

get_db_connection <- function() {
  database_url <- Sys.getenv("DATABASE_URL")
  
  if (nzchar(database_url)) {
    message("[DB] Parseando DATABASE_URL manualmente...")
    
    # Parse manual da URL PostgreSQL
    # Formato: postgresql://user:password@host:port/dbname
    parsed <- tryCatch({
      url_clean <- sub("^postgresql://", "", database_url)
      
      # Extrai user:password (tudo antes do ultimo @)
      user_pass <- sub("@[^@]+$", "", url_clean)
      user <- sub(":.*$", "", user_pass)
      password <- sub("^.*:", "", user_pass)
      
      # Extrai host:port/dbname (tudo depois do ultimo @)
      host_db <- sub("^[^@]*@", "", url_clean)
      
      # host:port (antes da barra)
      host_port <- sub("/.*$", "", host_db)
      
      # Trata IPv6 [::1] e host normal
      if (grepl("^\\[", host_port)) {
        host <- sub("^\\[", "", sub("\\].*$", "", host_port))
        port <- as.integer(sub("^\\]:", "", sub("\\]$", "", host_port)))
      } else {
        host <- sub(":.*$", "", host_port)
        port <- suppressWarnings(as.integer(sub("^.*:", "", host_port)))
        if (is.na(port)) port <- 5432L
      }
      
      # dbname (depois da barra)
      dbname <- sub("^/", "", sub("^[^/]*", "", host_db))
      if (!nzchar(dbname)) dbname <- "postgres"
      
      list(host = host, port = port, dbname = dbname, 
           user = user, password = password)
    }, error = function(e) {
      message(sprintf("[DB] Erro ao parsear URL: %s", e$message))
      NULL
    })
    
    if (is.null(parsed)) {
      stop("Falha ao parsear DATABASE_URL: ", database_url)
    }
    
    message(sprintf("[DB] Conectando: host=%s port=%d dbname=%s user=%s",
                    parsed$host, parsed$port, parsed$dbname, parsed$user))
    
    conn <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = parsed$host,
      port = parsed$port,
      dbname = parsed$dbname,
      user = parsed$user,
      password = parsed$password
    )
  } else {
    # Conexão via parâmetros individuais
    conn <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("DB_HOST", "localhost"),
      port = as.integer(Sys.getenv("DB_PORT", "5432")),
      dbname = Sys.getenv("DB_NAME", "postgres"),
      user = Sys.getenv("DB_USER", "postgres"),
      password = Sys.getenv("DB_PASSWORD", "")
    )
  }
  
  # Configurações de sessão
  DBI::dbExecute(conn, "SET timezone = 'America/Sao_Paulo'")
  DBI::dbExecute(conn, "SET client_encoding = 'UTF8'")
  
  return(conn)
}

source_catalog <- function() {
  tibble::tribble(
    ~id_fonte, ~nome_fonte, ~sigla, ~pais, ~categoria, ~tipo_financiador, ~url_principal, ~url_oportunidades, ~metodo_coleta, ~idioma, ~periodicidade_atualizacao, ~observacoes,
    "cnpq", "Conselho Nacional de Desenvolvimento Científico e Tecnológico", "CNPq", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/cnpq/pt-br", "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao", "html", "pt", "diária", "Portal gov.br com chamadas abertas e links para detalhes.",
    "capes", "Coordenação de Aperfeiçoamento de Pessoal de Nível Superior", "CAPES", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/capes/pt-br", "https://www.gov.br/capes/pt-br/assuntos/editais-e-resultados-capes", "html", "pt", "diária", "Página de editais e resultados.",
    "finep", "Financiadora de Estudos e Projetos", "FINEP", "Brasil", "agência pública nacional", "governo federal", "https://www.finep.gov.br/", "https://www.finep.gov.br/o/c/chamadapublicas?sort=dataDePublicacao:desc&pageSize=250", "api_json", "pt", "diária", "API REST pública Liferay Headless Delivery. Filtros: publicoAlvo=ict, situacao=aberta.",
    "fapesb", "Fundação de Amparo à Pesquisa do Estado da Bahia", "FAPESB", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.fapesb.ba.gov.br/", "https://www.fapesb.ba.gov.br/category/edital/aberto/", "html", "pt", "diária", "Editais e chamadas da FAPESB.",
    "horizon_europe", "Horizon Europe", "HEU", "União Europeia", "programa multilateral", "união supranacional", "https://research-and-innovation.ec.europa.eu/", "https://api.tech.ec.europa.eu/search-api/prod/rest/search?apiKey=SEDIA", "api_json", "en", "diária", "API REST pública EU F&T Portal. Busca HORIZON (CL1-CL5, EIC, MSCA, WIDERA) + pós-filtro frameworkProgramme=43108390.",
    "erc", "European Research Council", "ERC", "União Europeia", "agência internacional", "união supranacional", "https://erc.europa.eu/", "https://api.tech.ec.europa.eu/search-api/prod/rest/search?apiKey=SEDIA&text=ERC", "api_json", "en", "diária", "API REST pública EU F&T Portal. Busca ERC + pós-filtro Horizon Europe (43108390) + ERC (43108406).",
    "sigitec", "Petrobras SIGITEC - Sistema de Gestão de Inovação e Tecnologia Competitividade", "PETROBRAS", "Brasil", "empresa estatal", "empresa pública", "https://sigitec-competitividade.petrobras.com.br", "https://sigitec-competitividade.petrobras.com.br/v2/public/opportunities", "api_json", "pt", "diária", "API REST pública SIGITEC Petrobras. Listing + detalhe por ID. Oportunidades de P&D para empresas e ICTs.",
    "undp", "United Nations Development Programme - Brasil", "UNDP", "Brasil", "agência internacional", "organização multilateral", "https://www.undp.org/pt/brazil", "https://www.undp.org/pt/brazil/licitacoes", "api_json", "pt", "diária", "Componente externo UNDP Procurement Notices. JSON via public-components.undp.org. Detalhes via procurement-notices.undp.org.",
    "embrapii", "Empresa Brasileira de Pesquisa e Inovação Industrial", "EMBRAPII", "Brasil", "empresa estatal", "empresa pública", "https://embrapii.org.br", "https://embrapii.org.br/transparencia/", "html", "pt", "diária", "Chamadas públicas EMBRAPII via parsing HTML estático da página de transparência. Detalhes com cronograma e documentos PDF.",
    "daad", "Deutscher Akademischer Austauschdienst - Brasil", "DAAD", "Alemanha", "agência internacional", "organização internacional", "https://www.daad-brasil.org/pt/", "https://www.daad-brasil.org/pt/bolsas/busca/", "hybrid", "en", "mensal", "Bolsas de estudo DAAD Brasil. Híbrido: JSON catálogo global (scholarships.js) + HTML scraping detalhe. ~82 bolsas filtradas para Brasil (origin=48).",
    "quantum", "EU Quantum Technologies - Calls for Proposals", "QUANTUM", "União Europeia", "programa temático", "união supranacional", "https://ec.europa.eu/info/funding-tenders/opportunities/portal/", "https://api.tech.ec.europa.eu/search-api/prod/rest/search?apiKey=SEDIA&text=quantum", "api_json", "en", "diária", "API REST EU F&T Portal. Busca por palavra-chave quantum + filtro Horizon Europe (43108390) + status Open. Garante captura de editais de computação e comunicação quântica.",
    "humboldt", "Alexander von Humboldt Foundation", "HUMBOLDT", "Alemanha", "fundação privada", "fundação", "https://www.humboldt-foundation.de/en/", "https://www.humboldt-foundation.de/en/apply/sponsorship-programmes/programmes-a-to-z", "html", "en", "mensal", "Bolsas e prêmios da Fundação Alexander von Humboldt. HTML scraping de listing com filtros (scholarships/awards) + detalhe por programa. Fellowships e awards para pesquisadores internacionais.",
    "world_bank", "World Bank", "WB", "Estados Unidos", "organismo internacional", "multilateral", "https://www.worldbank.org/", "https://projects.worldbank.org/pt/projects-operations/opportunities?project_ctry_name_exact=Brazil", "hybrid", "pt", "diaria", "Oportunidades de procurement do World Bank para Brasil. Download Excel + HTML scraping + API fallback (Projects API)."
  )
}

create_tables <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS fontes_financiamento (
      id_fonte VARCHAR(50) PRIMARY KEY,
      nome_fonte TEXT,
      sigla VARCHAR(20),
      pais VARCHAR(100),
      categoria VARCHAR(100),
      tipo_financiador VARCHAR(100),
      url_principal TEXT,
      url_oportunidades TEXT,
      metodo_coleta VARCHAR(50),
      idioma VARCHAR(10),
      periodicidade_atualizacao VARCHAR(50),
      observacoes TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS oportunidades (
      id_registro VARCHAR(100) PRIMARY KEY,
      entidade VARCHAR(200),
      pais_origem VARCHAR(100),
      titulo TEXT,
      subtitulo TEXT,
      descricao_resumida TEXT,
      descricao_completa TEXT,
      tipo_oportunidade VARCHAR(50),
      modalidade VARCHAR(50),
      area_tematica TEXT,
      palavras_chave TEXT,
      elegibilidade TEXT,
      publico_alvo TEXT,
      nivel_academico VARCHAR(100),
      instituicao_financiadora VARCHAR(200),
      valor_financiado DECIMAL(15,2),
      moeda VARCHAR(10),
      data_publicacao DATE,
      data_abertura DATE,
      data_limite DATE,
      data_encerramento DATE,
      status_oportunidade VARCHAR(20),
      link_origem TEXT,
      link_detalhe TEXT,
      link_documento_pdf TEXT,
      idioma VARCHAR(10),
      localidade TEXT,
      observacoes TEXT,
      texto_bruto TEXT,
      pagina_coletada INTEGER,
      fonte_oficial VARCHAR(50),
      data_hora_coleta TIMESTAMP,
      hash_deduplicacao VARCHAR(64) UNIQUE,
      campos_inferidos_ia TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS buscas_salvas (
      id SERIAL PRIMARY KEY,
      nome_busca TEXT,
      query_text TEXT,
      payload_avancado TEXT,
      alerta_ativo INTEGER,
      created_at TIMESTAMP,
      last_run_at TIMESTAMP
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS editais_rastreados (
      id SERIAL PRIMARY KEY,
      id_oportunidade VARCHAR(100) UNIQUE,
      status_usuario VARCHAR(50),
      observacoes TEXT,
      tracked_at TIMESTAMP,
      updated_at TIMESTAMP
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS perfil_usuario (
      id INTEGER PRIMARY KEY,
      nome_usuario TEXT,
      instituicao TEXT,
      palavras_chave_preferidas TEXT,
      areas_preferidas TEXT,
      paises_preferidos TEXT,
      financiadores_preferidos TEXT,
      tipos_oportunidade_preferidos TEXT,
      elegibilidade_preferida TEXT,
      updated_at TIMESTAMP
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS historico_buscas (
      id SERIAL PRIMARY KEY,
      query_text TEXT,
      filtros_json TEXT,
      executed_at TIMESTAMP
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS colaboradores (
      id SERIAL PRIMARY KEY,
      nome TEXT,
      instituicao TEXT,
      pais TEXT,
      area TEXT,
      palavras_chave TEXT,
      email TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS logs_coleta (
      id SERIAL PRIMARY KEY,
      fonte VARCHAR(50),
      metodo_coleta VARCHAR(50),
      status_execucao VARCHAR(50),
      mensagem TEXT,
      n_paginas INTEGER,
      n_registros INTEGER,
      url TEXT,
      data_execucao TIMESTAMP
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS pesquisadores_vencedores (
      id SERIAL PRIMARY KEY,
      nome TEXT,
      email TEXT,
      instituicao TEXT,
      expertise TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS projetos_aprovados (
      id SERIAL PRIMARY KEY,
      titulo_projeto TEXT,
      pesquisador_id INTEGER,
      edital_titulo TEXT,
      ano INTEGER,
      palavras_chave TEXT,
      FOREIGN KEY(pesquisador_id) REFERENCES pesquisadores_vencedores(id)
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS metrics_coleta (
      id SERIAL PRIMARY KEY,
      fonte VARCHAR(50),
      timestamp TIMESTAMP,
      metric_type VARCHAR(50),
      metric_value DECIMAL(15,4),
      context TEXT
    )")

  # Índices para performance
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_oportunidades_entidade ON oportunidades(entidade)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_oportunidades_status ON oportunidades(status_oportunidade)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_oportunidades_data_limite ON oportunidades(data_limite)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_oportunidades_hash ON oportunidades(hash_deduplicacao)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_logs_coleta_fonte ON logs_coleta(fonte)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_metrics_coleta_fonte ON metrics_coleta(fonte)")
  
  invisible(TRUE)
}

seed_sources <- function(conn) {
  src <- source_catalog()
  purrr::pwalk(src, function(...) {
    row <- list(...)
    DBI::dbExecute(
      conn,
      "INSERT INTO fontes_financiamento (id_fonte, nome_fonte, sigla, pais, categoria, tipo_financiador, url_principal, url_oportunidades, metodo_coleta, idioma, periodicidade_atualizacao, observacoes) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) ON CONFLICT(id_fonte) DO UPDATE SET nome_fonte = EXCLUDED.nome_fonte, sigla = EXCLUDED.sigla, pais = EXCLUDED.pais, categoria = EXCLUDED.categoria, tipo_financiador = EXCLUDED.tipo_financiador, url_principal = EXCLUDED.url_principal, url_oportunidades = EXCLUDED.url_oportunidades, metodo_coleta = EXCLUDED.metodo_coleta, idioma = EXCLUDED.idioma, periodicidade_atualizacao = EXCLUDED.periodicidade_atualizacao, observacoes = EXCLUDED.observacoes",
      params = row
    )
  })
  invisible(TRUE)
}

seed_profile <- function(conn) {
  profile <- tibble::tibble(
    id = 1L,
    nome_usuario = "Usuário",
    instituicao = "SENAI CIMATEC",
    palavras_chave_preferidas = "quântica; tecnologia quântica; comunicação quântica; sensores quânticos; computação quântica",
    areas_preferidas = "Tecnologias Quânticas; Comunicação Quântica; Sensores Quânticos; Computação Quântica",
    paises_preferidos = "Brasil; União Europeia; Estados Unidos; Canadá",
    financiadores_preferidos = "CNPq; CAPES; FINEP; FAPESB; Horizon Europe; ERC",
    tipos_oportunidade_preferidos = "grant; edital; fellowship; scholarship",
    elegibilidade_preferida = "ICTs; universidades; pesquisadores; empresas",
    updated_at = as.character(Sys.time())
  )
  
  existing <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM perfil_usuario WHERE id = 1")$n[[1]],
    error = function(e) 0
  )
  
  if (existing == 0) {
    DBI::dbWriteTable(conn, "perfil_usuario", profile, append = TRUE, row.names = FALSE)
  } else {
    DBI::dbExecute(conn, "UPDATE perfil_usuario SET nome_usuario = $1, instituicao = $2, palavras_chave_preferidas = $3, areas_preferidas = $4, paises_preferidos = $5, financiadores_preferidos = $6, tipos_oportunidade_preferidos = $7, elegibilidade_preferida = $8, updated_at = $9 WHERE id = 1",
      params = list(
        profile$nome_usuario, profile$instituicao, profile$palavras_chave_preferidas,
        profile$areas_preferidas, profile$paises_preferidos, profile$financiadores_preferidos,
        profile$tipos_oportunidade_preferidos, profile$elegibilidade_preferida, profile$updated_at
      )
    )
  }
  invisible(TRUE)
}

seed_saved_searches <- function(conn) {
  existing <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM buscas_salvas")$n[[1]],
    error = function(e) 0
  )
  if (existing > 0) {
    return(invisible(FALSE))
  }
  now <- as.character(Sys.time())
  searches <- tibble::tribble(
    ~nome_busca, ~query_text, ~payload_avancado, ~alerta_ativo, ~created_at, ~last_run_at,
    "Tecnologias quânticas", "(quântica OR \"tecnologia quântica\" OR quantum) AND (edital OR chamada OR grant OR fellowship)", "{}", 1L, now, now,
    "Comunicação, sensores e computação quântica", "\"comunicação quântica\" OR \"sensores quânticos\" OR \"computação quântica\" OR \"quantum communication\" OR \"quantum sensors\" OR \"quantum computing\"", "{}", 1L, now, now
  )
  DBI::dbWriteTable(conn, "buscas_salvas", searches, append = TRUE, row.names = FALSE)
}

seed_search_history <- function(conn) {
  existing <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM historico_buscas")$n[[1]],
    error = function(e) 0
  )
  if (existing > 0) {
    return(invisible(FALSE))
  }
  hist <- tibble::tribble(
    ~query_text, ~filtros_json, ~executed_at,
    "quântica OR tecnologia quântica", "{}", as.character(Sys.time() - 86400 * 5),
    "comunicação quântica OR sensores quânticos OR computação quântica", "{}", as.character(Sys.time() - 86400 * 3)
  )
  DBI::dbWriteTable(conn, "historico_buscas", hist, append = TRUE, row.names = FALSE)
}

seed_collaborators <- function(conn) {
  existing <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM colaboradores")$n[[1]],
    error = function(e) 0
  )
  if (existing > 0) {
    return(invisible(FALSE))
  }
  collaborators <- tibble::tribble(
    ~nome, ~instituicao, ~pais, ~area, ~palavras_chave, ~email,
    "Ana Martins", "UFES", "Brasil", "Saúde", "health innovation; medical devices; digital health", "ana.martins@example.org",
    "Henrik Vogel", "TU Berlin", "Alemanha", "Transição Energética", "hydrogen; storage; energy systems; decarbonization", "henrik.vogel@example.org",
    "Sofia Almeida", "USP", "Brasil", "Mudanças Climáticas", "agriculture; adaptation; climate risk", "sofia.almeida@example.org"
  )
  DBI::dbWriteTable(conn, "colaboradores", collaborators, append = TRUE, row.names = FALSE)
}

seed_pesquisadores_vencedores <- function(conn) {
  existing <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM pesquisadores_vencedores")$n[[1]],
    error = function(e) 0
  )
  if (existing > 0) {
    return(invisible(FALSE))
  }

  pesquisadores <- tibble::tribble(
    ~nome, ~email, ~instituicao, ~expertise,
    "Dr. Marcos Santos", "marcos.santos@cimatec.org.br", "SENAI CIMATEC", "computação quântica; qubits; supercondutores; hardware; tecnologia quântica",
    "Dra. Julia Costa", "julia.costa@cimatec.org.br", "SENAI CIMATEC", "comunicação quântica; criptografia pós-quântica; qkd; segurança quântica; tecnologia quântica",
    "Dr. Roberto Silva", "roberto.silva@cimatec.org.br", "SENAI CIMATEC", "computação quântica; otimização; algoritmos quânticos; annealer; tecnologia quântica",
    "Dra. Sandra Souza", "sandra.souza@cimatec.org.br", "SENAI CIMATEC", "saúde; dispositivos médicos; biotecnologia; diagnóstico precoce; inovação médica",
    "Dr. André Oliveira", "andre.oliveira@cimatec.org.br", "SENAI CIMATEC", "transição energética; hidrogênio verde; descarbonização; células de combustível"
  )
  DBI::dbWriteTable(conn, "pesquisadores_vencedores", pesquisadores, append = TRUE, row.names = FALSE)
  invisible(TRUE)
}

seed_projetos_aprovados <- function(conn) {
  existing <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM projetos_aprovados")$n[[1]],
    error = function(e) 0
  )
  if (existing > 0) {
    return(invisible(FALSE))
  }

  pesq <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT id, nome FROM pesquisadores_vencedores"),
    error = function(e) data.frame(id = integer(), nome = character(), stringsAsFactors = FALSE)
  )

  get_id <- function(nome_pesq) {
    id <- pesq$id[pesq$nome == nome_pesq]
    if (length(id) == 0) {
      return(1L)
    }
    as.integer(id[[1]])
  }

  projetos <- tibble::tribble(
    ~titulo_projeto, ~pesquisador_id, ~edital_titulo, ~ano, ~palavras_chave,
    "Desenvolvimento de Computadores Quânticos Supercondutores", get_id("Dr. Marcos Santos"), "Edital Tecnologias Quânticas Avançadas", 2024L, "qubits; supercondutores; hardware; criogenia; computação quântica",
    "Sensores Quânticos para Exploração Petrolífera", get_id("Dr. Marcos Santos"), "Chamada Especial de Sensores Quânticos", 2025L, "sensores quânticos; gravimetria; magnetômetros; quântica",
    "Redes de Comunicação Quântica e Criptografia em Fibras Ópticas", get_id("Dra. Julia Costa"), "Chamada Segurança e Comunicações Seguras", 2024L, "comunicação quântica; criptografia; qkd; segurança quântica",
    "Algoritmos Quânticos para Otimização de Processos Logísticos", get_id("Dr. Roberto Silva"), "Chamada Computação Científica de Alto Desempenho", 2025L, "computação quântica; otimização; algoritmos quânticos; annealer",
    "Dispositivo Portátil de Diagnóstico Rápido para Doenças Infecciosas", get_id("Dra. Sandra Souza"), "Edital Inovação em Saúde Pública", 2024L, "dispositivos médicos; biotecnologia; diagnóstico precoce; saúde",
    "Desenvolvimento de Eletrolisadores Eficientes para Hidrogênio Verde", get_id("Dr. André Oliveira"), "Edital Transição Energética Industrial", 2025L, "hidrogênio verde; descarbonização; eletrolisadores; energia limpa"
  )
  DBI::dbWriteTable(conn, "projetos_aprovados", projetos, append = TRUE, row.names = FALSE)
  invisible(TRUE)
}

seed_demo_opportunities <- function(conn) {
  existing <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]],
    error = function(e) 0
  )
  if (existing > 0) {
    return(invisible(FALSE))
  }
  today <- Sys.Date()
  demo <- tibble::tribble(
    ~entidade, ~pais_origem, ~titulo, ~subtitulo, ~descricao_resumida, ~descricao_completa, ~tipo_oportunidade, ~modalidade, ~area_tematica, ~palavras_chave, ~elegibilidade, ~publico_alvo, ~nivel_academico, ~instituicao_financiadora, ~valor_financiado, ~moeda, ~data_publicacao, ~data_abertura, ~data_limite, ~data_encerramento, ~status_oportunidade, ~link_origem, ~link_detalhe, ~link_documento_pdf, ~idioma, ~localidade, ~observacoes, ~texto_bruto, ~pagina_coletada, ~fonte_oficial, ~data_hora_coleta,
    "CNPq", "Brasil", "Edital Demo de Inovação em Saúde", "Base demonstrativa", "Apoio a projetos de inovação em saúde.", "Registro de demonstração para abertura do app na primeira execução.", "edital", "individual", "Saúde", "health; innovation; medical devices", "ICTs e pesquisadores", "pesquisadores; instituições", "doutorado", "CNPq", 100000, "BRL", as.character(today - 20), as.character(today - 15), as.character(today + 25), NA_character_, "aberto", "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao", "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao", NA_character_, "pt", "Brasil", "Seed demo.", "Seed demo.", 1L, "cnpq", as.character(Sys.time()),
    "Horizon Europe", "União Europeia", "Grant Demo for Energy Transition", "Seed", "Support for collaborative R&D in low-carbon industry.", "Seed record for initial dashboard rendering.", "grant", "rede", "Transição Energética", "energy transition; hydrogen; biomethane", "universities; companies; research organisations", "instituições; empresas", "instituição", "Horizon Europe", 2500000, "EUR", as.character(today - 40), as.character(today - 35), as.character(today + 60), NA_character_, "aberto", "https://research-and-innovation.ec.europa.eu/", "https://research-and-innovation.ec.europa.eu/", NA_character_, "en", "União Europeia", "Seed demo.", "Seed demo.", 1L, "horizon_europe", as.character(Sys.time())
  )
  demo$hash_deduplicacao <- vapply(seq_len(nrow(demo)), function(i) {
    make_hash(demo$entidade[i], demo$titulo[i], demo$link_detalhe[i], demo$data_limite[i])
  }, character(1))
  demo <- demo |>
    dplyr::mutate(
      id_registro = paste0("seed_", seq_len(dplyr::n())),
      campos_inferidos_ia = ""
    ) |>
    dplyr::select(id_registro, dplyr::everything())
  DBI::dbWriteTable(conn, "oportunidades", demo, append = TRUE, row.names = FALSE)
}

init_database <- function() {
  conn <- get_db_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  create_tables(conn)
  seed_sources(conn)
  seed_profile(conn)
  seed_saved_searches(conn)
  seed_search_history(conn)
  seed_collaborators(conn)
  seed_demo_opportunities(conn)
  seed_pesquisadores_vencedores(conn)
  seed_projetos_aprovados(conn)
  invisible(TRUE)
}

read_table <- function(conn, table_name) DBI::dbReadTable(conn, table_name)

read_app_data <- function(conn) {
  list(
    opportunities = tibble::as_tibble(read_table(conn, "oportunidades")) |>
      dplyr::mutate(
        data_publicacao = parse_date_safe(data_publicacao),
        data_abertura = parse_date_safe(data_abertura),
        data_limite = parse_date_safe(data_limite),
        data_encerramento = parse_date_safe(data_encerramento),
        data_hora_coleta = parse_datetime_safe(data_hora_coleta),
        valor_financiado = suppressWarnings(as.numeric(valor_financiado))
      ),
    sources = tibble::as_tibble(read_table(conn, "fontes_financiamento")),
    saved_searches = tibble::as_tibble(read_table(conn, "buscas_salvas")),
    tracked = tibble::as_tibble(read_table(conn, "editais_rastreados")),
    history = tibble::as_tibble(read_table(conn, "historico_buscas")),
    profile = tibble::as_tibble(read_table(conn, "perfil_usuario")),
    collaborators = tibble::as_tibble(read_table(conn, "colaboradores")),
    logs = tibble::as_tibble(read_table(conn, "logs_coleta"))
  )
}

upsert_opportunities <- function(conn, opportunities_df) {
  if (is.null(opportunities_df) || nrow(opportunities_df) == 0) {
    return(invisible(0L))
  }

  cols <- DBI::dbListFields(conn, "oportunidades")
  df <- tibble::as_tibble(opportunities_df)
  missing_cols <- setdiff(cols, names(df))
  if (length(missing_cols) > 0) {
    for (nm in missing_cols) df[[nm]] <- NA
  }
  df <- df[, cols, drop = FALSE]

  cols_no_pk <- setdiff(cols, "id_registro")
  update_clause <- paste(paste0(cols_no_pk, " = EXCLUDED.", cols_no_pk), collapse = ", ")
  
  # Gera parâmetros $1, $2, etc. para PostgreSQL
  params_placeholders <- paste0("$", seq_along(cols), collapse = ", ")
  
  sql_upsert <- paste0(
    "INSERT INTO oportunidades (", paste(cols, collapse = ", "), ") VALUES (",
    params_placeholders, ") ON CONFLICT(id_registro) DO UPDATE SET ",
    update_clause
  )

  inserted <- 0L
  in_transaction <- FALSE
  DBI::dbBegin(conn)
  in_transaction <- TRUE
  on.exit(
    {
      if (in_transaction && DBI::dbIsValid(conn)) {
        try(DBI::dbRollback(conn), silent = TRUE)
      }
    },
    add = TRUE
  )

  for (i in seq_len(nrow(df))) {
    row <- as.list(df[i, , drop = FALSE])
    row <- lapply(row, function(x) {
      if (length(x) == 0) {
        return(NA)
      }
      x[[1]]
    })
    for (nm in names(row)) {
      if (is.character(row[[nm]])) {
        row[[nm]] <- enc2utf8(row[[nm]])
      }
      if (inherits(row[[nm]], "Date") || inherits(row[[nm]], "POSIXct") || inherits(row[[nm]], "POSIXt")) {
        row[[nm]] <- as.character(row[[nm]])
      }
    }

    # Gera o hash de deduplicação via MD5 de Título + Agência (entidade)
    if (is.null(row$hash_deduplicacao) || is.na(row$hash_deduplicacao) || !nzchar(row$hash_deduplicacao)) {
      hash_input <- paste(row$entidade, row$titulo, sep = "||")
      row$hash_deduplicacao <- digest::digest(hash_input, algo = "md5")
    }

    if (is.null(row$id_registro) || is.na(row$id_registro) || !nzchar(row$id_registro)) {
      row$id_registro <- paste0("auto_", substr(row$hash_deduplicacao, 1, 16))
    }

    # Converte a lista em vetor ordenado conforme as colunas
    params <- unname(row[cols])

    affected <- tryCatch(
      {
        DBI::dbExecute(conn, sql_upsert, params = params)
      },
      error = function(e) {
        0L
      }
    )

    if (affected > 0) inserted <- inserted + 1L
  }

  DBI::dbCommit(conn)
  in_transaction <- FALSE
  invisible(inserted)
}

log_collection <- function(conn, fonte, metodo_coleta, status_execucao, mensagem, n_paginas = 0L, n_registros = 0L, url = NA_character_) {
  DBI::dbExecute(
    conn,
    "INSERT INTO logs_coleta (fonte, metodo_coleta, status_execucao, mensagem, n_paginas, n_registros, url, data_execucao) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    params = list(fonte, metodo_coleta, status_execucao, mensagem, as.integer(n_paginas), as.integer(n_registros), url, as.character(Sys.time()))
  )
}

save_search_record <- function(conn, query_text, filters_json = "{}") {
  DBI::dbExecute(conn, "INSERT INTO historico_buscas (query_text, filtros_json, executed_at) VALUES ($1, $2, $3)", params = list(query_text, filters_json, as.character(Sys.time())))
}

save_named_search <- function(conn, nome_busca, query_text, payload_avancado = "{}", alerta_ativo = 0L) {
  DBI::dbExecute(conn, "INSERT INTO buscas_salvas (nome_busca, query_text, payload_avancado, alerta_ativo, created_at, last_run_at) VALUES ($1, $2, $3, $4, $5, $6)", params = list(nome_busca, query_text, payload_avancado, as.integer(alerta_ativo), as.character(Sys.time()), as.character(Sys.time())))
}

mark_saved_search_run <- function(conn, id) {
  DBI::dbExecute(conn, "UPDATE buscas_salvas SET last_run_at = $1 WHERE id = $2", params = list(as.character(Sys.time()), id))
}

track_opportunity <- function(conn, id_oportunidade, status_usuario = "avaliar", observacoes = "") {
  DBI::dbExecute(
    conn,
    "INSERT INTO editais_rastreados (id_oportunidade, status_usuario, observacoes, tracked_at, updated_at) VALUES ($1, $2, $3, $4, $5) ON CONFLICT(id_oportunidade) DO UPDATE SET status_usuario = EXCLUDED.status_usuario, observacoes = EXCLUDED.observacoes, updated_at = EXCLUDED.updated_at",
    params = list(id_oportunidade, status_usuario, observacoes, as.character(Sys.time()), as.character(Sys.time()))
  )
}

update_tracked_opportunity <- function(conn, id_oportunidade, status_usuario, observacoes = "") {
  DBI::dbExecute(conn, "UPDATE editais_rastreados SET status_usuario = $1, observacoes = $2, updated_at = $3 WHERE id_oportunidade = $4", params = list(status_usuario, observacoes, as.character(Sys.time()), id_oportunidade))
}

delete_tracked_opportunity <- function(conn, id_oportunidade) {
  DBI::dbExecute(conn, "DELETE FROM editais_rastreados WHERE id_oportunidade = $1", params = list(id_oportunidade))
}

# --- Métricas de Performance ---

log_metric <- function(conn, fonte, metric_type, value, context = NULL) {
  tryCatch(
    {
      ctx_json <- if (!is.null(context)) jsonlite::toJSON(context, auto_unbox = TRUE) else NULL
      DBI::dbExecute(conn,
        "INSERT INTO metrics_coleta (fonte, timestamp, metric_type, metric_value, context) VALUES ($1, $2, $3, $4, $5)",
        params = list(fonte, as.character(Sys.time()), metric_type, value, ctx_json)
      )
    },
    silent = TRUE
  )
}

get_latency_by_source <- function(conn, hours = 24) {
  tryCatch(
    {
      DBI::dbGetQuery(conn, "
      SELECT fonte, AVG(metric_value) as avg_latency, COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'http_latency' AND timestamp > NOW() - INTERVAL '1 hour' * $1
      GROUP BY fonte ORDER BY avg_latency DESC
    ", params = list(hours))
    },
    error = function(e) data.frame()
  )
}

get_block_rate <- function(conn, hours = 24) {
  tryCatch(
    {
      DBI::dbGetQuery(conn, "
      SELECT fonte,
             SUM(CASE WHEN context::json->>'blocked' = '1' THEN 1 ELSE 0 END) as blocks,
             COUNT(*) as total,
             ROUND(100.0 * SUM(CASE WHEN context::json->>'blocked' = '1' THEN 1 ELSE 0 END) / COUNT(*), 2) as block_pct
      FROM metrics_coleta
      WHERE metric_type = 'http_request' AND timestamp > NOW() - INTERVAL '1 hour' * $1
      GROUP BY fonte
    ", params = list(hours))
    },
    error = function(e) data.frame()
  )
}

get_ai_provider_usage <- function(conn, hours = 24) {
  tryCatch(
    {
      DBI::dbGetQuery(conn, "
      SELECT context::json->>'provider' as provider,
             AVG(metric_value) as avg_latency,
             COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'ai_request' AND timestamp > NOW() - INTERVAL '1 hour' * $1
      GROUP BY provider
    ", params = list(hours))
    },
    error = function(e) data.frame()
  )
}

get_collection_throughput <- function(conn, hours = 24) {
  tryCatch(
    {
      DBI::dbGetQuery(conn, "
      SELECT fonte, SUM(metric_value) as total_records,
             COUNT(*) as n_sources
      FROM metrics_coleta
      WHERE metric_type = 'source_records' AND timestamp > NOW() - INTERVAL '1 hour' * $1
      GROUP BY fonte ORDER BY total_records DESC
    ", params = list(hours))
    },
    error = function(e) data.frame()
  )
}

# Função para testar conexão
test_db_connection <- function() {
  tryCatch({
    conn <- get_db_connection()
    on.exit(DBI::dbDisconnect(conn))
    
    # Testa query simples
    result <- DBI::dbGetQuery(conn, "SELECT 1 as test")
    
    if (result$test == 1) {
      message("Conexão com PostgreSQL OK!")
      return(TRUE)
    }
    return(FALSE)
  }, error = function(e) {
    message(sprintf("Erro na conexão: %s", e$message))
    return(FALSE)
  })
}

# Função para migrar dados do SQLite para PostgreSQL
migrate_sqlite_to_postgres <- function(sqlite_path, pg_conn = NULL) {
  library(RSQLite)
  
  if (is.null(pg_conn)) {
    pg_conn <- get_db_connection()
    on.exit(DBI::dbDisconnect(pg_conn))
  }
  
  # Conecta ao SQLite
  sqlite_conn <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(DBI::dbDisconnect(sqlite_conn), add = TRUE)
  
  # Lista todas as tabelas
  tabelas <- DBI::dbListTables(sqlite_conn)
  
  for (tabela in tabelas) {
    message(sprintf("Migrando tabela: %s", tabela))
    
    # Lê dados do SQLite
    dados <- DBI::dbReadTable(sqlite_conn, tabela)
    
    if (nrow(dados) > 0) {
      # Ajusta nomes das colunas para PostgreSQL (lowercase)
      names(dados) <- tolower(names(dados))
      
      # Escreve no PostgreSQL
      DBI::dbWriteTable(pg_conn, tabela, dados, append = TRUE, row.names = FALSE)
      message(sprintf("  - %d registros migrados", nrow(dados)))
    } else {
      message("  - Tabela vazia, pulando")
    }
  }
  
  message("Migração concluída!")
  invisible(TRUE)
}
