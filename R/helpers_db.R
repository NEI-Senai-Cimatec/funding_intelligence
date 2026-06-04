get_db_connection <- function(db_path) {
  ensure_dir(dirname(db_path))
  DBI::dbConnect(RSQLite::SQLite(), db_path)
}

source_catalog <- function() {
  tibble::tribble(
    ~id_fonte, ~nome_fonte, ~sigla, ~pais, ~categoria, ~tipo_financiador, ~url_principal, ~url_oportunidades, ~metodo_coleta, ~idioma, ~periodicidade_atualizacao, ~observacoes,
    "cnpq", "Conselho Nacional de Desenvolvimento Científico e Tecnológico", "CNPq", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/cnpq/pt-br", "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao", "html", "pt", "diária", "Portal gov.br com chamadas abertas e links para detalhes.",
    "capes", "Coordenação de Aperfeiçoamento de Pessoal de Nível Superior", "CAPES", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/capes/pt-br", "https://www.gov.br/capes/pt-br/assuntos/editais-e-resultados-capes", "html", "pt", "diária", "Página de editais e resultados.",
    "finep", "Financiadora de Estudos e Projetos", "FINEP", "Brasil", "agência pública nacional", "governo federal", "https://www.finep.gov.br/", "https://www.finep.gov.br/chamadas-publicas/chamadaspublicas?situacao=aberta", "html", "pt", "diária", "Chamadas públicas abertas.",
    "fapesp", "Fundação de Amparo à Pesquisa do Estado de São Paulo", "FAPESP", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapesp.br/", "https://fapesp.br/oportunidades/", "html", "pt", "diária", "Oportunidades de bolsas e auxílios.",
    "faperj", "Fundação Carlos Chagas Filho de Amparo à Pesquisa do Estado do Rio de Janeiro", "FAPERJ", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.faperj.br/", "https://www.faperj.br/?id=28.5.7", "html", "pt", "diária", "Lista anual de editais e chamadas.",
    "fapemig", "Fundação de Amparo à Pesquisa do Estado de Minas Gerais", "FAPEMIG", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapemig.br/", "https://fapemig.br/oportunidades/chamadas-e-editais", "html", "pt", "diária", "Chamadas e editais.",
    "fapes_es", "Fundação de Amparo à Pesquisa e Inovação do Espírito Santo", "FAPES", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapes.es.gov.br/", "https://fapes.es.gov.br/Editais/Abertos", "html", "pt", "diária", "Editais abertos com PDFs.",
    "confap", "Conselho Nacional das Fundações Estaduais de Amparo à Pesquisa", "CONFAP", "Brasil", "rede de fomento", "organização de coordenação", "https://confap.org.br/", "https://confap.org.br/pt/editais", "html", "pt", "diária", "Editais paginados por ano e status.",
    "bndes", "Banco Nacional de Desenvolvimento Econômico e Social", "BNDES", "Brasil", "banco de desenvolvimento", "empresa pública federal", "https://www.bndes.gov.br/", "https://www.bndes.gov.br/wps/vanityurl/chamadadeinovacao", "html", "pt", "diária", "Chamadas de inovação.",
    "mcti", "Ministério da Ciência, Tecnologia e Inovação", "MCTI", "Brasil", "ministério", "governo federal", "https://www.gov.br/mcti/pt-br", "https://www.gov.br/mcti/pt-br/acesso-a-informacao/editais", "html", "pt", "diária", "Editais do ministério.",
    "horizon_europe", "Horizon Europe", "HEU", "União Europeia", "programa multilateral", "união supranacional", "https://research-and-innovation.ec.europa.eu/", "https://research-and-innovation.ec.europa.eu/funding/funding-opportunities/funding-programmes-and-open-calls/horizon-europe_en", "html", "en", "diária", "Programa europeu e chamadas abertas.",
    "erc", "European Research Council", "ERC", "União Europeia", "agência internacional", "união supranacional", "https://erc.europa.eu/", "https://erc.europa.eu/apply-grant", "html", "en", "diária", "Grant schemes and application pages.",
    "nih", "National Institutes of Health", "NIH", "Estados Unidos", "agência internacional", "governo nacional", "https://grants.nih.gov/", "https://grants.nih.gov/funding/explore-nih-opportunities", "html", "en", "diária", "Grant opportunities portal.",
    "nsf", "U.S. National Science Foundation", "NSF", "Estados Unidos", "agência internacional", "governo nacional", "https://www.nsf.gov/", "https://www.nsf.gov/funding/getting-started", "html", "en", "diária", "Funding portal.",
    "wellcome", "Wellcome", "Wellcome", "Reino Unido", "fundação privada", "filantropia", "https://wellcome.org/", "https://wellcome.org/grant-funding/schemes", "html", "en", "diária", "Schemes and funding opportunities.",
    "gates", "Bill & Melinda Gates Foundation", "Gates", "Estados Unidos", "fundação privada", "filantropia", "https://www.gatesfoundation.org/", "https://www.gatesfoundation.org/about/how-we-work/grant-opportunities", "html", "en", "diária", "Grant opportunities.",
    "idrc", "International Development Research Centre", "IDRC", "Canadá", "organismo internacional", "governo nacional", "https://idrc-crdi.ca/", "https://idrc-crdi.ca/en/funding", "html", "en", "diária", "Funding page.",
    "unesco", "UNESCO", "UNESCO", "Internacional", "organismo multilateral", "ONU", "https://www.unesco.org/", "https://www.unesco.org/en/tags/call", "html", "en", "diária", "Calls and opportunities tagged call.",
    "daad", "German Academic Exchange Service", "DAAD", "Alemanha", "agência internacional", "cooperação acadêmica", "https://www2.daad.de/", "https://www2.daad.de/deutschland/stipendium/datenbank/en/21148-scholarship-database/?back=1&origin=1", "html", "en", "diária", "Scholarship database.",
    "world_bank", "World Bank", "World Bank", "Internacional", "banco de desenvolvimento", "multilateral", "https://www.worldbank.org/", "https://projects.worldbank.org/en/projects-operations/opportunities", "html", "en", "diária", "Opportunities page.",
    "idb", "Inter-American Development Bank", "IDB", "Internacional", "banco de desenvolvimento", "multilateral", "https://www.iadb.org/", "https://www.iadb.org/en/how-we-can-work-together/calls-proposals", "html", "en", "diária", "Calls for proposals.",
    "undp", "Programa das Nações Unidas para o Desenvolvimento", "PNUD", "Brasil", "organismo multilateral", "ONU", "https://www.undp.org/pt/brazil", "https://www.undp.org/pt/brazil/licitacoes", "html", "pt", "diária", "Licitações e oportunidades do PNUD Brasil.",
    "embrapii", "Empresa Brasileira de Pesquisa e Inovação Industrial", "EMBRAPII", "Brasil", "organização social", "contrato de gestão federal", "https://embrapii.org.br/", "https://embrapii.org.br/chamadas-publicas/", "html", "pt", "diária", "Chamadas públicas.",
    "ics", "Instituto Clima e Sociedade", "iCS", "Brasil", "fundação privada", "filantropia", "https://climaesociedade.org/", "https://climaesociedade.org/editais/", "html", "pt", "diária", "Editais e doações.",
    "min_saude", "Ministério da Saúde", "MS", "Brasil", "ministério", "governo federal", "https://www.gov.br/saude/pt-br", "https://www.gov.br/saude/pt-br/acesso-a-informacao/acoes-e-programas/editais", "html", "pt", "diária", "Fonte complementar nacional.",
    "fapesc", "Fundação de Amparo à Pesquisa e Inovação de Santa Catarina", "FAPESC", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapesc.sc.gov.br/", "https://fapesc.sc.gov.br/chamadas-abertas/", "html", "pt", "diária", "Editais abertos FAPESC.",
    "eureka", "Eureka Network", "EUREKA", "União Europeia", "programa multilateral", "associação internacional", "https://www.eurekanetwork.org/", "https://www.eurekanetwork.org/open-calls/", "html", "en", "diária", "Chamadas abertas para cooperação tecnológica internacional."
  )
}

create_tables <- function(conn) {
  DBI::dbExecute(conn, "
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

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS oportunidades (
      id_registro TEXT PRIMARY KEY,
      entidade TEXT,
      pais_origem TEXT,
      titulo TEXT,
      subtitulo TEXT,
      descricao_resumida TEXT,
      descricao_completa TEXT,
      tipo_oportunidade TEXT,
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
      campos_inferidos_ia TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS buscas_salvas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome_busca TEXT,
      query_text TEXT,
      payload_avancado TEXT,
      alerta_ativo INTEGER,
      created_at TEXT,
      last_run_at TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS editais_rastreados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_oportunidade TEXT UNIQUE,
      status_usuario TEXT,
      observacoes TEXT,
      tracked_at TEXT,
      updated_at TEXT
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
      updated_at TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS historico_buscas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      query_text TEXT,
      filtros_json TEXT,
      executed_at TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS colaboradores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT,
      instituicao TEXT,
      pais TEXT,
      area TEXT,
      palavras_chave TEXT,
      email TEXT
    )")

  DBI::dbExecute(conn, "
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

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS pesquisadores_vencedores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT,
      email TEXT,
      instituicao TEXT,
      expertise TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS projetos_aprovados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      titulo_projeto TEXT,
      pesquisador_id INTEGER,
      edital_titulo TEXT,
      ano INTEGER,
      palavras_chave TEXT,
      FOREIGN KEY(pesquisador_id) REFERENCES pesquisadores_vencedores(id)
    )")
}

seed_sources <- function(conn) {
  src <- source_catalog()
  purrr::pwalk(src, function(...) {
    row <- list(...)
    DBI::dbExecute(
      conn,
      "INSERT INTO fontes_financiamento (id_fonte, nome_fonte, sigla, pais, categoria, tipo_financiador, url_principal, url_oportunidades, metodo_coleta, idioma, periodicidade_atualizacao, observacoes) VALUES (:id_fonte, :nome_fonte, :sigla, :pais, :categoria, :tipo_financiador, :url_principal, :url_oportunidades, :metodo_coleta, :idioma, :periodicidade_atualizacao, :observacoes) ON CONFLICT(id_fonte) DO UPDATE SET nome_fonte = excluded.nome_fonte, sigla = excluded.sigla, pais = excluded.pais, categoria = excluded.categoria, tipo_financiador = excluded.tipo_financiador, url_principal = excluded.url_principal, url_oportunidades = excluded.url_oportunidades, metodo_coleta = excluded.metodo_coleta, idioma = excluded.idioma, periodicidade_atualizacao = excluded.periodicidade_atualizacao, observacoes = excluded.observacoes",
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
    financiadores_preferidos = "CNPq; FINEP; FAPES; Horizon Europe; NIH",
    tipos_oportunidade_preferidos = "grant; edital; fellowship; scholarship",
    elegibilidade_preferida = "ICTs; universidades; pesquisadores; empresas",
    updated_at = as.character(Sys.time())
  )
  DBI::dbExecute(conn, "DELETE FROM perfil_usuario WHERE id = 1")
  DBI::dbWriteTable(conn, "perfil_usuario", profile, append = TRUE)
  invisible(TRUE)
}

seed_saved_searches <- function(conn) {
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM buscas_salvas")$n[[1]]
  if (existing > 0) return(invisible(FALSE))
  now <- as.character(Sys.time())
  searches <- tibble::tribble(
    ~nome_busca, ~query_text, ~payload_avancado, ~alerta_ativo, ~created_at, ~last_run_at,
    "Tecnologias quânticas", "(quântica OR \"tecnologia quântica\" OR quantum) AND (edital OR chamada OR grant OR fellowship)", "{}", 1L, now, now,
    "Comunicação, sensores e computação quântica", "\"comunicação quântica\" OR \"sensores quânticos\" OR \"computação quântica\" OR \"quantum communication\" OR \"quantum sensors\" OR \"quantum computing\"", "{}", 1L, now, now
  )
  DBI::dbWriteTable(conn, "buscas_salvas", searches, append = TRUE)
}

seed_search_history <- function(conn) {
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM historico_buscas")$n[[1]]
  if (existing > 0) return(invisible(FALSE))
  hist <- tibble::tribble(
    ~query_text, ~filtros_json, ~executed_at,
    "quântica OR tecnologia quântica", "{}", as.character(Sys.time() - 86400 * 5),
    "comunicação quântica OR sensores quânticos OR computação quântica", "{}", as.character(Sys.time() - 86400 * 3)
  )
  DBI::dbWriteTable(conn, "historico_buscas", hist, append = TRUE)
}

seed_collaborators <- function(conn) {
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM colaboradores")$n[[1]]
  if (existing > 0) return(invisible(FALSE))
  collaborators <- tibble::tribble(
    ~nome, ~instituicao, ~pais, ~area, ~palavras_chave, ~email,
    "Ana Martins", "UFES", "Brasil", "Saúde", "health innovation; medical devices; digital health", "ana.martins@example.org",
    "Henrik Vogel", "TU Berlin", "Alemanha", "Transição Energética", "hydrogen; storage; energy systems; decarbonization", "henrik.vogel@example.org",
    "Sofia Almeida", "USP", "Brasil", "Mudanças Climáticas", "agriculture; adaptation; climate risk", "sofia.almeida@example.org"
  )
  DBI::dbWriteTable(conn, "colaboradores", collaborators, append = TRUE)
}

seed_pesquisadores_vencedores <- function(conn) {
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM pesquisadores_vencedores")$n[[1]]
  if (existing > 0) return(invisible(FALSE))
  
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
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM projetos_aprovados")$n[[1]]
  if (existing > 0) return(invisible(FALSE))
  
  pesq <- DBI::dbGetQuery(conn, "SELECT id, nome FROM pesquisadores_vencedores")
  
  get_id <- function(nome_pesq) {
    id <- pesq$id[pesq$nome == nome_pesq]
    if (length(id) == 0) return(1L)
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
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]]
  if (existing > 0) return(invisible(FALSE))
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
  DBI::dbWriteTable(conn, "oportunidades", demo, append = TRUE)
}

init_database <- function(db_path) {
  conn <- get_db_connection(db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  create_tables(conn)
  seed_sources(conn)
  try(DBI::dbExecute(conn, "DELETE FROM fontes_financiamento WHERE id_fonte IN (?, ?)", params = list("facepe", "fapesb")), silent = TRUE)
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
    sources = tibble::as_tibble(read_table(conn, "fontes_financiamento")) |>
      dplyr::filter(!(.data$id_fonte %in% c("facepe", "fapesb"))),
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
  if (is.null(opportunities_df) || nrow(opportunities_df) == 0) return(invisible(0L))

  cols <- DBI::dbListFields(conn, "oportunidades")
  df <- tibble::as_tibble(opportunities_df)
  missing_cols <- setdiff(cols, names(df))
  if (length(missing_cols) > 0) {
    for (nm in missing_cols) df[[nm]] <- NA
  }
  df <- df[, cols, drop = FALSE]

  sql_by_hash <- paste0(
    "INSERT INTO oportunidades (", paste(cols, collapse = ", "), ") VALUES (", paste(paste0(":", cols), collapse = ", "), ") ",
    "ON CONFLICT(hash_deduplicacao) DO UPDATE SET ",
    paste(sprintf("%s = excluded.%s", cols[cols != "hash_deduplicacao"], cols[cols != "hash_deduplicacao"]), collapse = ", ")
  )

  sql_by_id <- paste0(
    "INSERT INTO oportunidades (", paste(cols, collapse = ", "), ") VALUES (", paste(paste0(":", cols), collapse = ", "), ") ",
    "ON CONFLICT(id_registro) DO UPDATE SET ",
    paste(sprintf("%s = excluded.%s", cols[cols != "id_registro"], cols[cols != "id_registro"]), collapse = ", ")
  )

  inserted <- 0L
  for (i in seq_len(nrow(df))) {
    row <- as.list(df[i, , drop = FALSE])
    row <- lapply(row, function(x) {
      if (length(x) == 0) return(NA)
      x[[1]]
    })
    for (nm in names(row)) {
      if (inherits(row[[nm]], "Date") || inherits(row[[nm]], "POSIXct") || inherits(row[[nm]], "POSIXt")) {
        row[[nm]] <- as.character(row[[nm]])
      }
    }
    row$id_registro <- row$id_registro %||% paste0("auto_", substr(make_hash(row$entidade, row$titulo, row$link_detalhe, row$data_limite), 1, 16))
    row$hash_deduplicacao <- row$hash_deduplicacao %||% make_hash(row$entidade, row$titulo, row$link_detalhe, row$data_limite)

    ok <- tryCatch({
      DBI::dbExecute(conn, sql_by_hash, params = row)
      TRUE
    }, error = function(e) {
      tryCatch({
        DBI::dbExecute(conn, sql_by_id, params = row)
        TRUE
      }, error = function(e2) FALSE)
    })

    if (isTRUE(ok)) inserted <- inserted + 1L
  }

  invisible(inserted)
}

log_collection <- function(conn, fonte, metodo_coleta, status_execucao, mensagem, n_paginas = 0L, n_registros = 0L, url = NA_character_) {
  DBI::dbExecute(
    conn,
    "INSERT INTO logs_coleta (fonte, metodo_coleta, status_execucao, mensagem, n_paginas, n_registros, url, data_execucao) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(fonte, metodo_coleta, status_execucao, mensagem, as.integer(n_paginas), as.integer(n_registros), url, as.character(Sys.time()))
  )
}

save_search_record <- function(conn, query_text, filters_json = "{}") {
  DBI::dbExecute(conn, "INSERT INTO historico_buscas (query_text, filtros_json, executed_at) VALUES (?, ?, ?)", params = list(query_text, filters_json, as.character(Sys.time())))
}

save_named_search <- function(conn, nome_busca, query_text, payload_avancado = "{}", alerta_ativo = 0L) {
  DBI::dbExecute(conn, "INSERT INTO buscas_salvas (nome_busca, query_text, payload_avancado, alerta_ativo, created_at, last_run_at) VALUES (?, ?, ?, ?, ?, ?)", params = list(nome_busca, query_text, payload_avancado, as.integer(alerta_ativo), as.character(Sys.time()), as.character(Sys.time())))
}

mark_saved_search_run <- function(conn, id) {
  DBI::dbExecute(conn, "UPDATE buscas_salvas SET last_run_at = ? WHERE id = ?", params = list(as.character(Sys.time()), id))
}

track_opportunity <- function(conn, id_oportunidade, status_usuario = "avaliar", observacoes = "") {
  DBI::dbExecute(
    conn,
    "INSERT INTO editais_rastreados (id_oportunidade, status_usuario, observacoes, tracked_at, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id_oportunidade) DO UPDATE SET status_usuario = excluded.status_usuario, observacoes = excluded.observacoes, updated_at = excluded.updated_at",
    params = list(id_oportunidade, status_usuario, observacoes, as.character(Sys.time()), as.character(Sys.time()))
  )
}

update_tracked_opportunity <- function(conn, id_oportunidade, status_usuario, observacoes = "") {
  DBI::dbExecute(conn, "UPDATE editais_rastreados SET status_usuario = ?, observacoes = ?, updated_at = ? WHERE id_oportunidade = ?", params = list(status_usuario, observacoes, as.character(Sys.time()), id_oportunidade))
}

delete_tracked_opportunity <- function(conn, id_oportunidade) {
  DBI::dbExecute(conn, "DELETE FROM editais_rastreados WHERE id_oportunidade = ?", params = list(id_oportunidade))
}
