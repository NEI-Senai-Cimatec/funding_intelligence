# ─── Backend de banco: SQLite local x PostgreSQL/Neon (DATA_BASE_URL) ─────────

data_base_url <- function() {
  url <- Sys.getenv("DATA_BASE_URL", unset = "")
  if (!nzchar(url)) url <- Sys.getenv("DATABASE_URL", unset = "")
  trimws(url)
}

using_postgres <- function() nzchar(data_base_url())

db_backend_name <- function(dbms) {
  if (grepl("postgres", tolower(paste(dbms %||% "", collapse = " ")))) "postgres" else "sqlite"
}

db_backend <- function(conn = NULL) {
  if (is.null(conn)) {
    return(if (using_postgres()) "postgres" else "sqlite")
  }
  if (inherits(conn, "PqConnection")) return("postgres")
  if (inherits(conn, "SQLiteConnection")) return("sqlite")
  info <- tryCatch(DBI::dbGetInfo(conn), error = function(e) NULL)
  db_backend_name(info$dbms %||% "")
}

connect_postgres <- function(url) {
  u <- httr::parse_url(url)
  if (is.null(u$hostname) || !nzchar(u$hostname)) {
    stop("DATA_BASE_URL inválida: host ausente.", call. = FALSE)
  }
  q <- u$query %||% list()
  args <- list(
    drv = RPostgres::Postgres(),
    host = u$hostname,
    port = if (is.null(u$port) || !nzchar(as.character(u$port))) 5432L else as.integer(u$port),
    user = utils::URLdecode(u$username %||% ""),
    password = utils::URLdecode(u$password %||% ""),
    dbname = utils::URLdecode(u$path %||% ""),
    sslmode = q$sslmode %||% "require",
    connect_timeout = 15
  )
  if (!is.null(q$channel_binding) && nzchar(q$channel_binding)) {
    args$channel_binding <- q$channel_binding
  }
  do.call(DBI::dbConnect, args)
}

# RPostgres usa $1/$2; o restante do app fala ?. Converte apenas fora de strings.
sql_placeholders_to_postgres <- function(sql) {
  if (!nzchar(sql)) return(sql)
  chars <- strsplit(sql, "", fixed = TRUE)[[1]]
  out <- character(length(chars))
  in_single <- FALSE
  in_double <- FALSE
  idx <- 0L
  for (i in seq_along(chars)) {
    ch <- chars[[i]]
    if (ch == "'" && !in_double) {
      in_single <- !in_single
      out[[i]] <- ch
      next
    }
    if (ch == '"' && !in_single) {
      in_double <- !in_double
      out[[i]] <- ch
      next
    }
    if (ch == "?" && !in_single && !in_double) {
      idx <- idx + 1L
      out[[i]] <- paste0("$", idx)
      next
    }
    out[[i]] <- ch
  }
  paste(out, collapse = "")
}

coerce_integer64 <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0L) return(df)
  for (nm in names(df)) {
    if (inherits(df[[nm]], "integer64")) {
      df[[nm]] <- as.numeric(df[[nm]])
    }
  }
  df
}

db_execute <- function(conn, sql, params = NULL) {
  if (identical(db_backend(conn), "postgres")) {
    sql <- sql_placeholders_to_postgres(sql)
    if (!is.null(params)) params <- unname(params)
  }
  if (is.null(params)) DBI::dbExecute(conn, sql) else DBI::dbExecute(conn, sql, params = params)
}

db_get_query <- function(conn, sql, params = NULL) {
  is_postgres <- identical(db_backend(conn), "postgres")
  if (is_postgres) {
    sql <- sql_placeholders_to_postgres(sql)
    if (!is.null(params)) params <- unname(params)
  }
  res <- if (is.null(params)) DBI::dbGetQuery(conn, sql) else DBI::dbGetQuery(conn, sql, params = params)
  if (is_postgres) res <- coerce_integer64(res)
  res
}

get_db_connection <- function(db_path) {
  url <- data_base_url()
  if (nzchar(url) && !identical(db_path, ":memory:")) {
    return(connect_postgres(url))
  }

  ensure_dir(dirname(db_path))
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  # Ativar WAL mode e timeout de concorrência (10s) para evitar "database locked"
  try(
    {
      db_execute(conn, "PRAGMA journal_mode = WAL;")
      db_execute(conn, "PRAGMA busy_timeout = 10000;")
      db_execute(conn, "PRAGMA encoding = 'UTF-8';")
    },
    silent = TRUE
  )
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
    "grants_gov", "Grants.gov - U.S. Department of State", "Grants.gov", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.grants.gov/", "https://simpler.grants.gov/search", "hybrid", "en", "diária", "NOFOs/APs de Public Diplomacy de diferentes U.S. Missions. Foco em Public Diplomacy Programs (CFDA 19.040). Oportunidades sazonais (set-nov).",
    "doe_ascr", "DOE Advanced Scientific Computing Research", "DOE ASCR", "Estados Unidos", "agência pública nacional", "governo federal", "https://science.energy.gov/ascr/", "https://science.osti.gov/ascr/Funding-Opportunities", "html", "en", "semanal", "HPC, quantum computing, computational science, AI for Science. FY2026 Continuation of Solicitation fecha 30/09/2026. Parcerias com DOE National Laboratories.",
    "nsf_international", "NSF Office of International Science and Engineering", "NSF OISE", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.nsf.gov/oise", "https://www.nsf.gov/oise/international-collaborations", "html", "en", "mensal", "Colaboração internacional entre pesquisadores americanos e instituições estrangeiras. Internacionalização de pesquisa NSF.",
    "nsf_qise", "NSF QISE International Collaboration Supplements", "NSF QISE", "Estados Unidos", "programa temático", "governo federal", "https://www.nsf.gov/", "https://www.nsf.gov/funding/opportunities/dcl-international-collaboration-supplements-quantum-information", "html", "en", "mensal", "Supplements para NSF awards ativos adicionarem dimensão internacional em Quantum Information Science & Engineering. Brasil elegível não prioritário.",
    "nsf_cise", "NSF Directorate for Computer and Information Science and Engineering", "NSF CISE", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.nsf.gov/cise", "https://www.nsf.gov/funding/find-by-directorate", "hybrid", "en", "semanal", "Computação, AI, cybersecurity, software, systems, HPC, information science. Identificar PIs/universidades para parcerias com QuIIN.",
    "doe_quantum_genesis", "DOE Quantum Genesis Initiative", "DOE Quantum Genesis", "Estados Unidos", "iniciativa estratégica", "governo federal", "https://www.energy.gov/science", "https://www.energy.gov/science/articles/energy-department-announces-initiative-create-and-deploy-worlds-first", "html", "en", "mensal", "Iniciativa para criar fault-tolerant quantum computer cientificamente relevante até 2028. Lançada em junho/2026. Monitorar FOAs futuras.",
    "doe_genesis", "DOE Genesis Mission", "DOE Genesis", "Estados Unidos", "iniciativa estratégica", "governo federal", "https://www.energy.gov/genesis", "https://www.energy.gov/genesis", "html", "en", "mensal", "AI + advanced computing + quantum + scientific discovery. Precedente parceria EUA-Japão US$1B (DOE National Labs + instituições japonesas).",
    "nsf_nqni", "NSF National Quantum Nanotechnology Infrastructure", "NSF NQNI", "Estados Unidos", "programa temático", "governo federal", "https://www.nsf.gov/", "https://www.nsf.gov/funding/opportunities/nqni-national-quantum-nanotechnology-infrastructure/nsf26-505/solicitation", "html", "en", "mensal", "Rede nacional de infraestrutura quântica até US$100M (nsf26-505). Identificar universidades receptoras como parceiros potenciais.",
    "darpa_quantum_benchmarking", "DARPA Quantum Benchmarking Initiative", "DARPA QBI", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.darpa.mil/", "https://www.darpa.mil/research/programs/quantum-benchmarking-initiative", "html", "en", "mensal", "Fronteira tecnológica e avaliação de arquiteturas quantum computing. Identificar empresas e pesquisadores avançados."
  )
}

postgres_schema_statements <- function() {
  c(
    r"(CREATE TABLE IF NOT EXISTS fontes_financiamento (
      id_fonte TEXT PRIMARY KEY,
      nome_fonte TEXT,
      sigla TEXT,
      pais TEXT,
      categoria TEXT,
      tipo_financiador TEXT,
      url_principal TEXT,
      url_oportunidades TEXT,
      metodo_coleta TEXT,
      idioma TEXT,
      periodicidade_atualizacao TEXT,
      observacoes TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS oportunidades (
      id_registro TEXT PRIMARY KEY,
      entidade TEXT,
      pais_origem TEXT,
      titulo TEXT,
      subtitulo TEXT,
      descricao_resumida TEXT,
      descricao_completa TEXT,
      tipo_oportunidade TEXT,
      tipo_oportunidade_original TEXT,
      tipo_oportunidade_categoria TEXT,
      tipo_oportunidade_categoria_origem TEXT,
      modalidade TEXT,
      area_tematica TEXT,
      palavras_chave TEXT,
      elegibilidade TEXT,
      publico_alvo TEXT,
      nivel_academico TEXT,
      instituicao_financiadora TEXT,
      valor_financiado DOUBLE PRECISION,
      moeda TEXT,
      data_publicacao TEXT,
      data_abertura TEXT,
      data_limite TEXT,
      data_encerramento TEXT,
      status_oportunidade TEXT,
      link_origem TEXT,
      link_detalhe TEXT,
      link_documento_pdf TEXT,
      idioma TEXT,
      localidade TEXT,
      observacoes TEXT,
      texto_bruto TEXT,
      pagina_coletada INTEGER,
      fonte_oficial TEXT,
      data_hora_coleta TEXT,
      hash_deduplicacao TEXT UNIQUE,
      campos_inferidos_ia TEXT,
      enrichment_status TEXT DEFAULT 'pendente',
      enrichment_model TEXT,
      enrichment_at TEXT,
      enrichment_error TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS migration_flags (
      flag TEXT PRIMARY KEY,
      applied_at TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS buscas_salvas (
      id BIGSERIAL PRIMARY KEY,
      nome_busca TEXT,
      query_text TEXT,
      payload_avancado TEXT,
      alerta_ativo INTEGER,
      created_at TEXT,
      last_run_at TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS editais_rastreados (
      id BIGSERIAL PRIMARY KEY,
      id_oportunidade TEXT UNIQUE,
      status_usuario TEXT,
      observacoes TEXT,
      tracked_at TEXT,
      updated_at TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS perfil_usuario (
      id BIGSERIAL PRIMARY KEY,
      nome_usuario TEXT,
      instituicao TEXT,
      palavras_chave_preferidas TEXT,
      areas_preferidas TEXT,
      paises_preferidos TEXT,
      financiadores_preferidos TEXT,
      tipos_oportunidade_preferidos TEXT,
      elegibilidade_preferida TEXT,
      updated_at TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS historico_buscas (
      id BIGSERIAL PRIMARY KEY,
      query_text TEXT,
      filtros_json TEXT,
      executed_at TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS colaboradores (
      id BIGSERIAL PRIMARY KEY,
      nome TEXT,
      instituicao TEXT,
      pais TEXT,
      area TEXT,
      palavras_chave TEXT,
      email TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS logs_coleta (
      id BIGSERIAL PRIMARY KEY,
      fonte TEXT,
      metodo_coleta TEXT,
      status_execucao TEXT,
      mensagem TEXT,
      n_paginas INTEGER,
      n_registros INTEGER,
      url TEXT,
      data_execucao TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS pesquisadores_vencedores (
      id BIGSERIAL PRIMARY KEY,
      nome TEXT,
      email TEXT,
      instituicao TEXT,
      expertise TEXT
    ))",

    r"(CREATE TABLE IF NOT EXISTS projetos_aprovados (
      id BIGSERIAL PRIMARY KEY,
      titulo_projeto TEXT,
      pesquisador_id BIGINT,
      edital_titulo TEXT,
      ano INTEGER,
      palavras_chave TEXT,
      FOREIGN KEY(pesquisador_id) REFERENCES pesquisadores_vencedores(id)
    ))",

    r"(CREATE TABLE IF NOT EXISTS metrics_coleta (
      id BIGSERIAL PRIMARY KEY,
      fonte TEXT,
      "timestamp" TEXT,
      metric_type TEXT,
      metric_value DOUBLE PRECISION,
      context TEXT
    ))"
  )
}

create_postgres_tables <- function(conn) {
  suppressMessages({
    for (sql in postgres_schema_statements()) {
      db_execute(conn, sql)
    }
  })
  invisible(TRUE)
}

create_tables <- function(conn) {
  if (identical(db_backend(conn), "postgres")) {
    return(create_postgres_tables(conn))
  }
  create_sqlite_tables(conn)
}

create_sqlite_tables <- function(conn) {
  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS fontes_financiamento (
      id_fonte TEXT PRIMARY KEY,
      nome_fonte TEXT,
      sigla TEXT,
      pais TEXT,
      categoria TEXT,
      tipo_financiador TEXT,
      url_principal TEXT,
      url_oportunidades TEXT,
      metodo_coleta TEXT,
      idioma TEXT,
      periodicidade_atualizacao TEXT,
      observacoes TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS oportunidades (
      id_registro TEXT PRIMARY KEY,
      entidade TEXT,
      pais_origem TEXT,
      titulo TEXT,
      subtitulo TEXT,
      descricao_resumida TEXT,
      descricao_completa TEXT,
      tipo_oportunidade TEXT,
      tipo_oportunidade_original TEXT,
      tipo_oportunidade_categoria TEXT,
      tipo_oportunidade_categoria_origem TEXT,
      modalidade TEXT,
      area_tematica TEXT,
      palavras_chave TEXT,
      elegibilidade TEXT,
      publico_alvo TEXT,
      nivel_academico TEXT,
      instituicao_financiadora TEXT,
      valor_financiado REAL,
      moeda TEXT,
      data_publicacao TEXT,
      data_abertura TEXT,
      data_limite TEXT,
      data_encerramento TEXT,
      status_oportunidade TEXT,
      link_origem TEXT,
      link_detalhe TEXT,
      link_documento_pdf TEXT,
      idioma TEXT,
      localidade TEXT,
      observacoes TEXT,
      texto_bruto TEXT,
      pagina_coletada INTEGER,
      fonte_oficial TEXT,
      data_hora_coleta TEXT,
      hash_deduplicacao TEXT UNIQUE,
      campos_inferidos_ia TEXT,
      enrichment_status TEXT DEFAULT 'pendente',
      enrichment_model TEXT,
      enrichment_at TEXT,
      enrichment_error TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS migration_flags (
      flag TEXT PRIMARY KEY,
      applied_at TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS buscas_salvas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome_busca TEXT,
      query_text TEXT,
      payload_avancado TEXT,
      alerta_ativo INTEGER,
      created_at TEXT,
      last_run_at TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS editais_rastreados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_oportunidade TEXT UNIQUE,
      status_usuario TEXT,
      observacoes TEXT,
      tracked_at TEXT,
      updated_at TEXT
    )")

  db_execute(conn, "
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
      updated_at TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS historico_buscas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      query_text TEXT,
      filtros_json TEXT,
      executed_at TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS colaboradores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT,
      instituicao TEXT,
      pais TEXT,
      area TEXT,
      palavras_chave TEXT,
      email TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS logs_coleta (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fonte TEXT,
      metodo_coleta TEXT,
      status_execucao TEXT,
      mensagem TEXT,
      n_paginas INTEGER,
      n_registros INTEGER,
      url TEXT,
      data_execucao TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS pesquisadores_vencedores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT,
      email TEXT,
      instituicao TEXT,
      expertise TEXT
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS projetos_aprovados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      titulo_projeto TEXT,
      pesquisador_id INTEGER,
      edital_titulo TEXT,
      ano INTEGER,
      palavras_chave TEXT,
      FOREIGN KEY(pesquisador_id) REFERENCES pesquisadores_vencedores(id)
    )")

  db_execute(conn, "
    CREATE TABLE IF NOT EXISTS metrics_coleta (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fonte TEXT,
      timestamp TEXT,
      metric_type TEXT,
      metric_value REAL,
      context TEXT
    )")
}

seed_sources <- function(conn) {
  src <- source_catalog()
  purrr::pwalk(src, function(...) {
    row <- list(...)
    db_execute(
      conn,
      "INSERT INTO fontes_financiamento (id_fonte, nome_fonte, sigla, pais, categoria, tipo_financiador, url_principal, url_oportunidades, metodo_coleta, idioma, periodicidade_atualizacao, observacoes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id_fonte) DO UPDATE SET nome_fonte = excluded.nome_fonte, sigla = excluded.sigla, pais = excluded.pais, categoria = excluded.categoria, tipo_financiador = excluded.tipo_financiador, url_principal = excluded.url_principal, url_oportunidades = excluded.url_oportunidades, metodo_coleta = excluded.metodo_coleta, idioma = excluded.idioma, periodicidade_atualizacao = excluded.periodicidade_atualizacao, observacoes = excluded.observacoes",
      params = unname(row)
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
  db_execute(conn, "DELETE FROM perfil_usuario WHERE id = 1")
  DBI::dbWriteTable(conn, "perfil_usuario", profile, append = TRUE)
  invisible(TRUE)
}

seed_saved_searches <- function(conn) {
  existing <- db_get_query(conn, "SELECT COUNT(*) AS n FROM buscas_salvas")$n[[1]]
  if (existing > 0) {
    return(invisible(FALSE))
  }
  now <- as.character(Sys.time())
  searches <- tibble::tribble(
    ~nome_busca, ~query_text, ~payload_avancado, ~alerta_ativo, ~created_at, ~last_run_at,
    "Tecnologias quânticas", "(quântica OR \"tecnologia quântica\" OR quantum) AND (edital OR chamada OR grant OR fellowship)", "{}", 1L, now, now,
    "Comunicação, sensores e computação quântica", "\"comunicação quântica\" OR \"sensores quânticos\" OR \"computação quântica\" OR \"quantum communication\" OR \"quantum sensors\" OR \"quantum computing\"", "{}", 1L, now, now
  )
  DBI::dbWriteTable(conn, "buscas_salvas", searches, append = TRUE)
}

seed_search_history <- function(conn) {
  existing <- db_get_query(conn, "SELECT COUNT(*) AS n FROM historico_buscas")$n[[1]]
  if (existing > 0) {
    return(invisible(FALSE))
  }
  hist <- tibble::tribble(
    ~query_text, ~filtros_json, ~executed_at,
    "quântica OR tecnologia quântica", "{}", as.character(Sys.time() - 86400 * 5),
    "comunicação quântica OR sensores quânticos OR computação quântica", "{}", as.character(Sys.time() - 86400 * 3)
  )
  DBI::dbWriteTable(conn, "historico_buscas", hist, append = TRUE)
}

seed_collaborators <- function(conn) {
  existing <- db_get_query(conn, "SELECT COUNT(*) AS n FROM colaboradores")$n[[1]]
  if (existing > 0) {
    return(invisible(FALSE))
  }
  collaborators <- tibble::tribble(
    ~nome, ~instituicao, ~pais, ~area, ~palavras_chave, ~email,
    "Ana Martins", "UFES", "Brasil", "Saúde", "health innovation; medical devices; digital health", "ana.martins@example.org",
    "Henrik Vogel", "TU Berlin", "Alemanha", "Transição Energética", "hydrogen; storage; energy systems; decarbonization", "henrik.vogel@example.org",
    "Sofia Almeida", "USP", "Brasil", "Mudanças Climáticas", "agriculture; adaptation; climate risk", "sofia.almeida@example.org"
  )
  DBI::dbWriteTable(conn, "colaboradores", collaborators, append = TRUE)
}

seed_pesquisadores_vencedores <- function(conn) {
  existing <- db_get_query(conn, "SELECT COUNT(*) AS n FROM pesquisadores_vencedores")$n[[1]]
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
  DBI::dbWriteTable(conn, "pesquisadores_vencedores", pesquisadores, append = TRUE)
  invisible(TRUE)
}

seed_projetos_aprovados <- function(conn) {
  existing <- db_get_query(conn, "SELECT COUNT(*) AS n FROM projetos_aprovados")$n[[1]]
  if (existing > 0) {
    return(invisible(FALSE))
  }

  pesq <- db_get_query(conn, "SELECT id, nome FROM pesquisadores_vencedores")

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
  DBI::dbWriteTable(conn, "projetos_aprovados", projetos, append = TRUE)
  invisible(TRUE)
}


seed_demo_opportunities <- function(conn) {
  existing <- db_get_query(conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]]
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
    make_hash(demo$entidade[i], normalize_text(demo$titulo[i]), demo$link_detalhe[i])
  }, character(1))
  demo <- demo |>
    dplyr::mutate(
      id_registro = paste0("seed_", seq_len(dplyr::n())),
      campos_inferidos_ia = ""
    ) |>
    dplyr::select(id_registro, dplyr::everything())
  upsert_opportunities(conn, demo)
  invisible(TRUE)
}

# ─── Migrações idempotentes (BUG-02/12) ───────────────────────────────────────
# Adiciona as colunas de proveniência de enriquecimento em bancos existentes e
# recalcula hash_deduplicacao (que nunca mais inclui data_limite).

.enrichment_columns <- list(
  enrichment_status = "TEXT DEFAULT 'pendente'",
  enrichment_model = "TEXT",
  enrichment_at = "TEXT",
  enrichment_error = "TEXT"
)

migration_marker <- function(conn, flag) {
  tryCatch(
    {
      res <- db_get_query(conn, "SELECT 1 AS ok FROM migration_flags WHERE flag = ?", params = list(flag))
      nrow(res) > 0L
    },
    error = function(e) TRUE
  )
}

set_migration_marker <- function(conn, flag) {
  try(
    {
      db_execute(
        conn,
        "INSERT INTO migration_flags (flag, applied_at) VALUES (?, ?) ON CONFLICT(flag) DO UPDATE SET applied_at = excluded.applied_at",
        params = list(flag, as.character(Sys.time()))
      )
    },
    silent = TRUE
  )
}

migrate_enrichment_columns <- function(conn) {
  cols <- tryCatch(DBI::dbListFields(conn, "oportunidades"), error = function(e) character())
  for (nm in names(.enrichment_columns)) {
    if (!nm %in% cols) {
      db_execute(conn, sprintf("ALTER TABLE oportunidades ADD COLUMN %s %s", nm, .enrichment_columns[[nm]]))
      message(sprintf("[Migration] Coluna '%s' adicionada a oportunidades.", nm))
    }
  }
  invisible(TRUE)
}

migrate_dedup_hashes <- function(conn) {
  if (!isTRUE(migration_marker(conn, "dedup_hash_v2"))) {
    res <- tryCatch(
      {
        db_get_query(conn, "SELECT id_registro, entidade, titulo, link_detalhe, link_documento_pdf, link_origem, hash_deduplicacao FROM oportunidades")
      },
      error = function(e) NULL
    )
    if (!is.null(res) && nrow(res) > 0L) {
      updated <- 0L
      for (i in seq_len(nrow(res))) {
        primary_link <- dplyr::coalesce(res$link_detalhe[[i]], res$link_documento_pdf[[i]], res$link_origem[[i]], "")
        new_hash <- make_hash(res$entidade[[i]], normalize_text(res$titulo[[i]]), primary_link)
        if (!identical(res$hash_deduplicacao[[i]], new_hash)) {
          tryCatch(
            {
              db_execute(
                conn,
                "UPDATE oportunidades SET hash_deduplicacao = ?, id_registro = CASE WHEN id_registro IS NULL OR id_registro = '' THEN ? ELSE id_registro END WHERE id_registro = ?",
                params = list(new_hash, paste0("auto_", substr(new_hash, 1, 16)), res$id_registro[[i]])
              )
              updated <- updated + 1L
            },
            error = function(e) NULL
          )
        }
      }
      message(sprintf("[Migration] Recalculados %d hash(s) de deduplicacao (sem data_limite).", updated))
    }
    set_migration_marker(conn, "dedup_hash_v2")
  }
  invisible(TRUE)
}

# Migração idempotente do tipo de oportunidade para a taxonomia canônica.
# Preserva o valor bruto em tipo_oportunidade_original e preenche
# tipo_oportunidade_categoria + tipo_oportunidade_categoria_origem.
migrate_tipo_oportunidade <- function(conn, force = FALSE) {
  marker <- "tipo_oportunidade_v1"

  if (!"oportunidades" %in% DBI::dbListTables(conn)) {
    stop("Tabela 'oportunidades' não encontrada para a migração de tipo_oportunidade.", call. = FALSE)
  }
  if (!"migration_flags" %in% DBI::dbListTables(conn)) {
    db_execute(conn, "
      CREATE TABLE IF NOT EXISTS migration_flags (
        flag TEXT PRIMARY KEY,
        applied_at TEXT
      )")
  }

  counts_vazio <- data.frame(
    categoria = names(categorias_tipo_oportunidade()),
    n = 0L,
    stringsAsFactors = FALSE
  )
  origens_vazio <- data.frame(origem = character(), n = integer(), stringsAsFactors = FALSE)
  unknown_vazio <- data.frame(valor = character(), n = integer(), exemplo_titulo = character(), stringsAsFactors = FALSE)

  if (!isTRUE(force) && isTRUE(migration_marker(conn, marker))) {
    return(list(
      applied = FALSE,
      total = NA_integer_,
      counts = counts_vazio,
      origens = origens_vazio,
      unknown = unknown_vazio,
      log_path = NA_character_
    ))
  }

  cols <- DBI::dbListFields(conn, "oportunidades")
  novas_colunas <- c(
    tipo_oportunidade_original = "TEXT",
    tipo_oportunidade_categoria = "TEXT",
    tipo_oportunidade_categoria_origem = "TEXT"
  )
  for (nm in names(novas_colunas)) {
    if (!nm %in% cols) {
      db_execute(conn, sprintf("ALTER TABLE oportunidades ADD COLUMN %s %s", nm, novas_colunas[[nm]]))
      message(sprintf("[Migration] Coluna '%s' adicionada a oportunidades.", nm))
    }
  }

  rows <- db_get_query(
    conn,
    "SELECT id_registro, tipo_oportunidade, tipo_oportunidade_original, titulo, fonte_oficial
       FROM oportunidades"
  )

  if (nrow(rows) == 0L) {
    set_migration_marker(conn, marker)
    return(list(
      applied = TRUE,
      total = 0L,
      counts = counts_vazio,
      origens = origens_vazio,
      unknown = unknown_vazio,
      log_path = NA_character_
    ))
  }

  detalhes <- lapply(seq_len(nrow(rows)), function(i) {
    original <- rows$tipo_oportunidade_original[[i]]
    if (is.na(original) || !nzchar(original)) {
      original <- rows$tipo_oportunidade[[i]]
    }
    categorizar_tipo_oportunidade_detalhado(
      tipo = original,
      titulo = rows$titulo[[i]],
      fonte = rows$fonte_oficial[[i]]
    )
  })

  categorias <- vapply(detalhes, `[[`, character(1), "categoria")
  origens <- vapply(detalhes, `[[`, character(1), "origem")
  originais <- vapply(seq_len(nrow(rows)), function(i) {
    original <- rows$tipo_oportunidade_original[[i]]
    if (is.na(original) || !nzchar(original)) {
      rows$tipo_oportunidade[[i]]
    } else {
      original
    }
  }, character(1))

  in_tx <- FALSE
  DBI::dbBegin(conn)
  in_tx <- TRUE
  on.exit(
    if (in_tx) try(DBI::dbRollback(conn), silent = TRUE),
    add = TRUE
  )

  for (i in seq_len(nrow(rows))) {
    db_execute(
      conn,
      "UPDATE oportunidades
          SET tipo_oportunidade_original = ?,
              tipo_oportunidade_categoria = ?,
              tipo_oportunidade_categoria_origem = ?
        WHERE id_registro = ?",
      params = list(originais[[i]], categorias[[i]], origens[[i]], rows$id_registro[[i]])
    )
  }

  DBI::dbCommit(conn)
  in_tx <- FALSE
  set_migration_marker(conn, marker)

  count_tab <- table(factor(categorias, levels = names(categorias_tipo_oportunidade())))
  counts <- data.frame(
    categoria = names(count_tab),
    n = as.integer(count_tab),
    stringsAsFactors = FALSE
  )
  origem_tab <- table(factor(origens, levels = c("bruto", "override", "titulo", "fonte", "outros")))
  origens_df <- data.frame(
    origem = names(origem_tab),
    n = as.integer(origem_tab),
    stringsAsFactors = FALSE
  )

  outros_idx <- which(categorias == "outros")
  if (length(outros_idx) == 0L) {
    unknown <- unknown_vazio
  } else {
    valores <- originais[outros_idx]
    valores[is.na(valores) | !nzchar(valores)] <- "(sem tipo)"
    tab <- sort(table(valores), decreasing = TRUE)
    unknown <- data.frame(
      valor = names(tab),
      n = as.integer(tab),
      exemplo_titulo = vapply(names(tab), function(v) {
        idx <- outros_idx[valores == v][1]
        rows$titulo[[idx]] %||% ""
      }, character(1)),
      stringsAsFactors = FALSE
    )
  }

  log_path <- file.path(
    getwd(), "logs",
    sprintf("tipo_oportunidade_migracao_%s.log", format(Sys.time(), "%Y%m%d_%H%M%S"))
  )
  ensure_dir(dirname(log_path))
  linhas <- c(
    sprintf("Migração %s", marker),
    sprintf("Data: %s", Sys.time()),
    sprintf("Total de registros: %d", nrow(rows)),
    "",
    "Categorias:",
    sprintf("  %s: %d", counts$categoria, counts$n),
    "",
    "Origens:",
    sprintf("  %s: %d", origens_df$origem, origens_df$n),
    "",
    "Valores em Outros:",
    if (nrow(unknown) == 0L) {
      "  (nenhum)"
    } else {
      sprintf("  %s: %d | exemplo: %s", unknown$valor, unknown$n, unknown$exemplo_titulo)
    }
  )
  writeLines(enc2utf8(linhas), log_path, useBytes = TRUE)

  list(
    applied = TRUE,
    total = nrow(rows),
    counts = counts,
    origens = origens_df,
    unknown = unknown,
    log_path = log_path
  )
}

migrate_existing_keywords <- function(conn) {
  res <- tryCatch(
    {
      db_get_query(conn, "SELECT id_registro, titulo, subtitulo, descricao_resumida, descricao_completa, palavras_chave, campos_inferidos_ia FROM oportunidades")
    },
    error = function(e) NULL
  )

  if (is.null(res) || nrow(res) == 0) {
    return(invisible(FALSE))
  }

  updated_count <- 0
  for (i in seq_len(nrow(res))) {
    id <- res$id_registro[[i]]
    kw <- res$palavras_chave[[i]]
    inferred <- res$campos_inferidos_ia[[i]] %||% ""

    # Se não foi enriquecido via IA, vamos recalcular com o filtro de stopwords expandido
    is_ia_kw <- grepl("palavras_chave", inferred, fixed = TRUE)
    if (!is_ia_kw) {
      text <- paste(
        res$titulo[[i]] %||% "",
        res$subtitulo[[i]] %||% "",
        res$descricao_resumida[[i]] %||% "",
        res$descricao_completa[[i]] %||% "",
        collapse = "\n"
      )
      new_kw <- extract_keywords_simple(text)

      if (!identical(kw, new_kw)) {
        tryCatch(
          {
            db_execute(
              conn,
              "UPDATE oportunidades SET palavras_chave = ? WHERE id_registro = ?",
              params = list(new_kw, id)
            )
            updated_count <- updated_count + 1
          },
          error = function(e) NULL
        )
      }
    }
  }

  if (updated_count > 0) {
    message(sprintf("[Migration] Atualizadas as palavras-chave de %d edital(is) legado(s) no banco de dados.", updated_count))
  }
  invisible(TRUE)
}

cleanup_database_opportunities <- function(conn) {
  # 1. Limpeza por Heurísticas Estáticas (incluindo novos filtros de retificações e Finep)
  res <- tryCatch(
    {
      db_get_query(conn, "SELECT id_registro, titulo, descricao_resumida, link_origem, link_detalhe, texto_bruto FROM oportunidades")
    },
    error = function(e) NULL
  )

  if (is.null(res) || nrow(res) == 0) {
    return(invisible(FALSE))
  }

  to_delete <- character()
  for (i in seq_len(nrow(res))) {
    id <- res$id_registro[[i]]
    title <- res$titulo[[i]] %||% ""
    desc <- res$descricao_resumida[[i]] %||% ""
    url <- res$link_detalhe[[i]] %||% res$link_origem[[i]] %||% ""
    body_text <- res$texto_bruto[[i]] %||% ""

    is_funding <- TRUE
    if (exists("is_funding_opportunity_heuristics", mode = "function")) {
      is_funding <- is_funding_opportunity_heuristics(title = title, description = desc, url = url, body_text = body_text)
    } else {
      # Fallback básico
      t_norm <- tolower(title)
      if (grepl("manual do cartao|cobranca administrativa|carta de servico|mapa de fomento|bolsas e projetos vigentes|acoes e programas|strategic plan|membros do comite|perguntas frequentes|faq|contato|quem somos|links uteis|tutoriais|tutorial|instrucoes para envio|retificacao|alteracao|aditivo|resultado|esclarecimento", t_norm)) {
        is_funding <- FALSE
      }
    }

    if (!is_funding) {
      to_delete <- c(to_delete, id)
    }
  }

  if (length(to_delete) > 0) {
    message(sprintf("[DB Cleanup] Removendo %d registro(s) inválido(s)/não-editais do banco...", length(to_delete)))
    for (id in to_delete) {
      tryCatch(
        {
          db_execute(conn, "DELETE FROM oportunidades WHERE id_registro = ?", params = list(id))
        },
        error = function(e) NULL
      )
    }
  }

  # 2. Deduplicação Retroativa de Editais com o Mesmo Nome por Entidade
  res_dedupe <- tryCatch(
    {
      db_get_query(conn, "SELECT id_registro, entidade, titulo, status_oportunidade, data_limite, texto_bruto, descricao_resumida FROM oportunidades")
    },
    error = function(e) NULL
  )

  if (!is.null(res_dedupe) && nrow(res_dedupe) > 0 && exists("normalize_text", mode = "function") && exists("parse_date_safe", mode = "function")) {
    res_dedupe$title_norm <- vapply(res_dedupe$titulo, normalize_text, character(1))
    res_dedupe$parsed_date <- parse_date_safe(res_dedupe$data_limite)
    res_dedupe$status_priority <- dplyr::case_when(
      res_dedupe$status_oportunidade == "aberto" ~ 1L,
      res_dedupe$status_oportunidade == "futuro" ~ 2L,
      res_dedupe$status_oportunidade == "encerrado" ~ 3L,
      TRUE ~ 4L
    )
    res_dedupe$content_len <- nchar(dplyr::coalesce(res_dedupe$texto_bruto, "")) + nchar(dplyr::coalesce(res_dedupe$descricao_resumida, ""))

    keep_ids <- res_dedupe |>
      dplyr::arrange(
        status_priority,
        dplyr::desc(parsed_date),
        dplyr::desc(content_len)
      ) |>
      dplyr::distinct(entidade, title_norm, .keep_all = TRUE) |>
      dplyr::pull(id_registro)

    all_ids <- res_dedupe$id_registro
    to_delete_dedupe <- setdiff(all_ids, keep_ids)

    if (length(to_delete_dedupe) > 0) {
      message(sprintf("[DB Cleanup] Removendo %d registro(s) duplicado(s)/obsoletos do banco...", length(to_delete_dedupe)))
      for (id in to_delete_dedupe) {
        tryCatch(
          {
            db_execute(conn, "DELETE FROM oportunidades WHERE id_registro = ?", params = list(id))
          },
          error = function(e) NULL
        )
      }
    }
  }

  invisible(TRUE)
}

init_database <- function(db_path) {
  conn <- get_db_connection(db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  create_tables(conn)
  try(migrate_tipo_oportunidade(conn), silent = TRUE)
  seed_sources(conn)
  try(db_execute(conn, "DELETE FROM fontes_financiamento WHERE id_fonte NOT IN (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", params = list("cnpq", "capes", "finep", "fapesb", "horizon_europe", "erc", "sigitec", "undp", "embrapii", "daad", "quantum", "humboldt", "grants_gov", "doe_ascr", "nsf_international", "nsf_qise", "nsf_cise", "doe_quantum_genesis", "doe_genesis", "nsf_nqni", "darpa_quantum_benchmarking")), silent = TRUE)
  try(db_execute(conn, "UPDATE oportunidades SET pais_origem = 'União Europeia' WHERE pais_origem = 'Uniao Europeia'"), silent = TRUE)
  seed_profile(conn)
  seed_saved_searches(conn)
  seed_search_history(conn)
  seed_collaborators(conn)
  seed_demo_opportunities(conn)
  seed_pesquisadores_vencedores(conn)
  seed_projetos_aprovados(conn)
  try(cleanup_database_opportunities(conn), silent = TRUE)
  try(migrate_existing_keywords(conn), silent = TRUE)
  try(migrate_enrichment_columns(conn), silent = TRUE)
  try(migrate_dedup_hashes(conn), silent = TRUE)
  invisible(TRUE)
}

read_table <- function(conn, table_name) coerce_integer64(DBI::dbReadTable(conn, table_name))

read_app_data <- function(conn) {
  opps <- tibble::as_tibble(read_table(conn, "oportunidades"))
  if (!"tipo_oportunidade" %in% names(opps)) opps$tipo_oportunidade <- NA_character_
  if (!"tipo_oportunidade_original" %in% names(opps)) opps$tipo_oportunidade_original <- opps$tipo_oportunidade
  if (!"tipo_oportunidade_categoria" %in% names(opps)) opps$tipo_oportunidade_categoria <- NA_character_
  if (!"tipo_oportunidade_categoria_origem" %in% names(opps)) opps$tipo_oportunidade_categoria_origem <- NA_character_

  opps <- opps |>
    dplyr::mutate(
      tipo_oportunidade_original = dplyr::coalesce(tipo_oportunidade_original, tipo_oportunidade),
      tipo_oportunidade_categoria = dplyr::coalesce(
        tipo_oportunidade_categoria,
        categorizar_tipo_oportunidade_vec(tipo_oportunidade_original, titulo, fonte_oficial)
      ),
      data_publicacao = parse_date_safe(data_publicacao),
      data_abertura = parse_date_safe(data_abertura),
      data_limite = parse_date_safe(data_limite),
      data_encerramento = parse_date_safe(data_encerramento),
      data_hora_coleta = parse_datetime_safe(data_hora_coleta),
      valor_financiado = suppressWarnings(as.numeric(valor_financiado))
    )

  list(
    opportunities = opps,
    sources = tibble::as_tibble(read_table(conn, "fontes_financiamento")),
    saved_searches = tibble::as_tibble(read_table(conn, "buscas_salvas")),
    tracked = tibble::as_tibble(read_table(conn, "editais_rastreados")),
    history = tibble::as_tibble(read_table(conn, "historico_buscas")),
    profile = tibble::as_tibble(read_table(conn, "perfil_usuario")),
    collaborators = tibble::as_tibble(read_table(conn, "colaboradores")),
    logs = tibble::as_tibble(read_table(conn, "logs_coleta"))
  )
}

fallback_app_data <- function() {
  conn <- get_db_connection(":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  create_tables(conn)
  seed_sources(conn)
  seed_profile(conn)
  seed_saved_searches(conn)
  seed_search_history(conn)
  seed_collaborators(conn)
  seed_demo_opportunities(conn)
  read_app_data(conn)
}

upsert_opportunities <- function(conn, opportunities_df) {
  if (is.null(opportunities_df) || nrow(opportunities_df) == 0) {
    return(invisible(0L))
  }

  cols <- DBI::dbListFields(conn, "oportunidades")
  df <- tibble::as_tibble(opportunities_df)

  tipo_cols <- c(
    "tipo_oportunidade_original",
    "tipo_oportunidade_categoria",
    "tipo_oportunidade_categoria_origem"
  )
  if (all(tipo_cols %in% cols)) {
    if (!"tipo_oportunidade" %in% names(df)) df$tipo_oportunidade <- NA_character_
    if (!"tipo_oportunidade_original" %in% names(df)) df$tipo_oportunidade_original <- df$tipo_oportunidade
    df$tipo_oportunidade_original <- dplyr::coalesce(df$tipo_oportunidade_original, df$tipo_oportunidade)
    if (!"tipo_oportunidade_categoria" %in% names(df)) df$tipo_oportunidade_categoria <- NA_character_
    if (!"tipo_oportunidade_categoria_origem" %in% names(df)) df$tipo_oportunidade_categoria_origem <- NA_character_

    faltantes <- is.na(df$tipo_oportunidade_categoria) | !nzchar(df$tipo_oportunidade_categoria)
    if (any(faltantes)) {
      titulos <- if ("titulo" %in% names(df)) df$titulo else rep(NA_character_, nrow(df))
      fontes <- if ("fonte_oficial" %in% names(df)) df$fonte_oficial else rep(NA_character_, nrow(df))
      detalhes <- lapply(which(faltantes), function(i) {
        categorizar_tipo_oportunidade_detalhado(
          tipo = df$tipo_oportunidade_original[[i]],
          titulo = titulos[[i]],
          fonte = fontes[[i]]
        )
      })
      df$tipo_oportunidade_categoria[faltantes] <- vapply(detalhes, `[[`, character(1), "categoria")
      df$tipo_oportunidade_categoria_origem[faltantes] <- vapply(detalhes, `[[`, character(1), "origem")
    }
    origem_vazia <- is.na(df$tipo_oportunidade_categoria_origem) | !nzchar(df$tipo_oportunidade_categoria_origem)
    df$tipo_oportunidade_categoria_origem[origem_vazia] <- "bruto"
  }

  missing_cols <- setdiff(cols, names(df))
  if (length(missing_cols) > 0) {
    for (nm in missing_cols) df[[nm]] <- NA
  }
  df <- df[, cols, drop = FALSE]

  cols_no_pk <- setdiff(cols, "id_registro")
  update_clause <- paste(paste0(cols_no_pk, " = excluded.", cols_no_pk), collapse = ", ")
  sql_upsert <- paste0(
    "INSERT INTO oportunidades (", paste(cols, collapse = ", "), ") VALUES (",
    paste(rep("?", length(cols)), collapse = ", "), ") ON CONFLICT(id_registro) DO UPDATE SET ",
    update_clause
  )

  is_postgres <- identical(db_backend(conn), "postgres")
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

    # Gera o hash de deduplicação — sem data_limite (BUG-12): o mesmo edital
    # coletado em dias diferentes deve colapsar em um único registro.
    if (is.null(row$hash_deduplicacao) || is.na(row$hash_deduplicacao) || !nzchar(row$hash_deduplicacao)) {
      primary_link <- paste(row$link_detalhe, row$link_documento_pdf, row$link_origem, sep = "||")
      primary_link <- sub("^(NA\\|\\|)+", "", primary_link)
      primary_link <- sub("(\\|\\|NA)+$", "", primary_link)
      hash_input <- paste(row$entidade, normalize_text(row$titulo), primary_link, sep = "||")
      row$hash_deduplicacao <- digest::digest(hash_input, algo = "md5")
    }

    if (is.null(row$id_registro) || is.na(row$id_registro) || !nzchar(row$id_registro)) {
      row$id_registro <- paste0("auto_", substr(row$hash_deduplicacao, 1, 16))
    }

    if (is_postgres) {
      try(db_execute(conn, "SAVEPOINT fi_upsert_row"), silent = TRUE)
    }

    affected <- tryCatch(
      {
        db_execute(conn, sql_upsert, params = unname(row))
      },
      error = function(e) {
        if (is_postgres) {
          try(db_execute(conn, "ROLLBACK TO SAVEPOINT fi_upsert_row"), silent = TRUE)
        }
        # Loga colisão de hash_deduplicacao UNIQUE sem abortar transação (observabilidade)
        try(
          {
            msg <- conditionMessage(e)
            if (grepl("UNIQUE constraint failed.*hash_deduplicacao|hash_deduplicacao.*UNIQUE|duplicate key value violates unique constraint.*hash_deduplicacao|hash_deduplicacao.*duplicate key", msg, ignore.case = TRUE)) {
              warning(sprintf("[upsert] hash colisão ignorada id=%s titulo='%s' hash=%s", row$id_registro %||% "NA", substr(row$titulo %||% "", 1, 60), row$hash_deduplicacao %||% "NA"), call. = FALSE)
            }
          },
          silent = TRUE
        )
        0L
      }
    )

    if (is_postgres) {
      try(db_execute(conn, "RELEASE SAVEPOINT fi_upsert_row"), silent = TRUE)
    }

    if (affected > 0) inserted <- inserted + 1L
  }

  DBI::dbCommit(conn)
  in_transaction <- FALSE
  invisible(inserted)
}

log_collection <- function(conn, fonte, metodo_coleta, status_execucao, mensagem, n_paginas = 0L, n_registros = 0L, url = NA_character_) {
  db_execute(
    conn,
    "INSERT INTO logs_coleta (fonte, metodo_coleta, status_execucao, mensagem, n_paginas, n_registros, url, data_execucao) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(fonte, metodo_coleta, status_execucao, mensagem, as.integer(n_paginas), as.integer(n_registros), url, as.character(Sys.time()))
  )
}

save_search_record <- function(conn, query_text, filters_json = "{}") {
  db_execute(conn, "INSERT INTO historico_buscas (query_text, filtros_json, executed_at) VALUES (?, ?, ?)", params = list(query_text, filters_json, as.character(Sys.time())))
}

save_named_search <- function(conn, nome_busca, query_text, payload_avancado = "{}", alerta_ativo = 0L) {
  db_execute(conn, "INSERT INTO buscas_salvas (nome_busca, query_text, payload_avancado, alerta_ativo, created_at, last_run_at) VALUES (?, ?, ?, ?, ?, ?)", params = list(nome_busca, query_text, payload_avancado, as.integer(alerta_ativo), as.character(Sys.time()), as.character(Sys.time())))
}

mark_saved_search_run <- function(conn, id) {
  db_execute(conn, "UPDATE buscas_salvas SET last_run_at = ? WHERE id = ?", params = list(as.character(Sys.time()), id))
}

track_opportunity <- function(conn, id_oportunidade, status_usuario = "avaliar", observacoes = "") {
  db_execute(
    conn,
    "INSERT INTO editais_rastreados (id_oportunidade, status_usuario, observacoes, tracked_at, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id_oportunidade) DO UPDATE SET status_usuario = excluded.status_usuario, observacoes = excluded.observacoes, updated_at = excluded.updated_at",
    params = list(id_oportunidade, status_usuario, observacoes, as.character(Sys.time()), as.character(Sys.time()))
  )
}

update_tracked_opportunity <- function(conn, id_oportunidade, status_usuario, observacoes = "") {
  db_execute(conn, "UPDATE editais_rastreados SET status_usuario = ?, observacoes = ?, updated_at = ? WHERE id_oportunidade = ?", params = list(status_usuario, observacoes, as.character(Sys.time()), id_oportunidade))
}

delete_tracked_opportunity <- function(conn, id_oportunidade) {
  db_execute(conn, "DELETE FROM editais_rastreados WHERE id_oportunidade = ?", params = list(id_oportunidade))
}


# --- Métricas de Performance ---

metric_cutoff <- function(hours = 24) {
  format(Sys.time() - as.difftime(hours, units = "hours"), "%Y-%m-%d %H:%M:%S")
}

log_metric <- function(conn, fonte, metric_type, value, context = NULL) {
  tryCatch(
    {
      ctx_json <- if (!is.null(context)) jsonlite::toJSON(context, auto_unbox = TRUE) else NULL
      db_execute(conn,
        "INSERT INTO metrics_coleta (fonte, \"timestamp\", metric_type, metric_value, context) VALUES (?, ?, ?, ?, ?)",
        params = list(fonte, as.character(Sys.time()), metric_type, value, ctx_json)
      )
    },
    silent = TRUE
  )
}

get_latency_by_source <- function(conn, hours = 24) {
  tryCatch(
    {
      db_get_query(conn, "
      SELECT fonte, AVG(metric_value) as avg_latency, COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'http_latency' AND \"timestamp\" > ?
      GROUP BY fonte ORDER BY avg_latency DESC
    ", params = list(metric_cutoff(hours)))
    },
    error = function(e) data.frame()
  )
}

get_block_rate <- function(conn, hours = 24) {
  tryCatch(
    {
      blocked_expr <- if (identical(db_backend(conn), "postgres")) {
        "(context::jsonb ->> 'blocked')::int"
      } else {
        "json_extract(context, '$.blocked')"
      }
      sql <- sprintf("
      SELECT fonte,
             SUM(CASE WHEN %s = 1 THEN 1 ELSE 0 END) as blocks,
             COUNT(*) as total,
             ROUND(100.0 * SUM(CASE WHEN %s = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) as block_pct
      FROM metrics_coleta
      WHERE metric_type = 'http_request' AND \"timestamp\" > ?
      GROUP BY fonte
    ", blocked_expr, blocked_expr)
      db_get_query(conn, sql, params = list(metric_cutoff(hours)))
    },
    error = function(e) data.frame()
  )
}

get_ai_provider_usage <- function(conn, hours = 24) {
  tryCatch(
    {
      provider_expr <- if (identical(db_backend(conn), "postgres")) {
        "context::jsonb ->> 'provider'"
      } else {
        "json_extract(context, '$.provider')"
      }
      sql <- sprintf("
      SELECT %s as provider,
             AVG(metric_value) as avg_latency,
             COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'ai_request' AND \"timestamp\" > ?
      GROUP BY provider
    ", provider_expr)
      db_get_query(conn, sql, params = list(metric_cutoff(hours)))
    },
    error = function(e) data.frame()
  )
}

get_collection_throughput <- function(conn, hours = 24) {
  tryCatch(
    {
      db_get_query(conn, "
      SELECT fonte, SUM(metric_value) as total_records,
             COUNT(*) as n_sources
      FROM metrics_coleta
      WHERE metric_type = 'source_records' AND \"timestamp\" > ?
      GROUP BY fonte ORDER BY total_records DESC
    ", params = list(metric_cutoff(hours)))
    },
    error = function(e) data.frame()
  )
}
