get_db_connection <- function(db_path) {
  ensure_dir(dirname(db_path))
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  # Ativar WAL mode e timeout de concorrência (10s) para evitar "database locked"
  try({
    DBI::dbExecute(conn, "PRAGMA journal_mode = WAL;")
    DBI::dbExecute(conn, "PRAGMA busy_timeout = 10000;")
  }, silent = TRUE)
  return(conn)
}

source_catalog <- function() {
  tibble::tribble(
    ~id_fonte, ~nome_fonte, ~sigla, ~pais, ~categoria, ~tipo_financiador, ~url_principal, ~url_oportunidades, ~metodo_coleta, ~idioma, ~periodicidade_atualizacao, ~observacoes,
    "cnpq", "Conselho Nacional de Desenvolvimento Científico e Tecnológico", "CNPq", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/cnpq/pt-br", "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao", "html", "pt", "diária", "Portal gov.br com chamadas abertas e links para detalhes.",
    "capes", "Coordenação de Aperfeiçoamento de Pessoal de Nível Superior", "CAPES", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/capes/pt-br", "https://www.gov.br/capes/pt-br/assuntos/editais-e-resultados-capes", "html", "pt", "diária", "Página de editais e resultados.",
    "finep", "Financiadora de Estudos e Projetos", "FINEP", "Brasil", "agência pública nacional", "governo federal", "https://www.finep.gov.br/", "https://www.finep.gov.br/chamadas-publicas/chamadaspublicas?situacao=aberta", "html", "pt", "diária", "Chamadas públicas abertas.",
    "fapesb", "Fundação de Amparo à Pesquisa do Estado da Bahia", "FAPESB", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.fapesb.ba.gov.br/", "https://www.fapesb.ba.gov.br/category/edital/aberto/", "html", "pt", "diária", "Editais e chamadas da FAPESB.",
    "horizon_europe", "Horizon Europe", "HEU", "União Europeia", "programa multilateral", "união supranacional", "https://research-and-innovation.ec.europa.eu/", "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/calls-for-proposals?order=DESC&pageNumber=1&pageSize=50&sortBy=relevance&keywords=HORIZON&isExactMatch=true&status=31094501,31094502,31094503", "html", "en", "diária", "Programa europeu e chamadas abertas.",
    "erc", "European Research Council", "ERC", "União Europeia", "agência internacional", "união supranacional", "https://erc.europa.eu/", "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/calls-for-proposals?order=DESC&pageNumber=1&pageSize=50&sortBy=startDate&status=31094501,31094502&programmePart=43108406&frameworkProgramme=43108390&isExactMatch=true", "html", "en", "diária", "Grant schemes and application pages."
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

  DBI::dbExecute(conn, "
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
    financiadores_preferidos = "CNPq; CAPES; FINEP; FAPESB; Horizon Europe; ERC",
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

migrate_existing_keywords <- function(conn) {
  res <- tryCatch({
    DBI::dbGetQuery(conn, "SELECT id_registro, titulo, subtitulo, descricao_resumida, descricao_completa, palavras_chave, campos_inferidos_ia FROM oportunidades")
  }, error = function(e) NULL)
  
  if (is.null(res) || nrow(res) == 0) return(invisible(FALSE))
  
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
        tryCatch({
          DBI::dbExecute(
            conn,
            "UPDATE oportunidades SET palavras_chave = ? WHERE id_registro = ?",
            params = list(new_kw, id)
          )
          updated_count <- updated_count + 1
        }, error = function(e) NULL)
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
  res <- tryCatch({
    DBI::dbGetQuery(conn, "SELECT id_registro, titulo, descricao_resumida, link_origem, link_detalhe, texto_bruto FROM oportunidades")
  }, error = function(e) NULL)
  
  if (is.null(res) || nrow(res) == 0) return(invisible(FALSE))
  
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
      tryCatch({
        DBI::dbExecute(conn, "DELETE FROM oportunidades WHERE id_registro = ?", params = list(id))
      }, error = function(e) NULL)
    }
  }

  # 2. Deduplicação Retroativa de Editais com o Mesmo Nome por Entidade
  res_dedupe <- tryCatch({
    DBI::dbGetQuery(conn, "SELECT id_registro, entidade, titulo, status_oportunidade, data_limite, texto_bruto, descricao_resumida FROM oportunidades")
  }, error = function(e) NULL)

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
        tryCatch({
          DBI::dbExecute(conn, "DELETE FROM oportunidades WHERE id_registro = ?", params = list(id))
        }, error = function(e) NULL)
      }
    }
  }

  invisible(TRUE)
}

init_database <- function(db_path) {
  conn <- get_db_connection(db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  create_tables(conn)
  seed_sources(conn)
  try(DBI::dbExecute(conn, "DELETE FROM fontes_financiamento WHERE id_fonte NOT IN (?, ?, ?, ?, ?, ?)", params = list("cnpq", "capes", "finep", "fapesb", "horizon_europe", "erc")), silent = TRUE)
  seed_profile(conn)
  seed_saved_searches(conn)
  seed_search_history(conn)
  seed_collaborators(conn)
  seed_demo_opportunities(conn)
  seed_pesquisadores_vencedores(conn)
  seed_projetos_aprovados(conn)
  try(cleanup_database_opportunities(conn), silent = TRUE)
  try(migrate_existing_keywords(conn), silent = TRUE)
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

  cols_no_pk <- setdiff(cols, "id_registro")
  update_clause <- paste(paste0(cols_no_pk, " = excluded.", cols_no_pk), collapse = ", ")
  sql_upsert <- paste0(
    "INSERT INTO oportunidades (", paste(cols, collapse = ", "), ") VALUES (", 
    paste(paste0(":", cols), collapse = ", "), ") ON CONFLICT(id_registro) DO UPDATE SET ", 
    update_clause
  )

  inserted <- 0L
  in_transaction <- FALSE
  DBI::dbBegin(conn)
  in_transaction <- TRUE
  on.exit({
    if (in_transaction && DBI::dbIsValid(conn)) {
      try(DBI::dbRollback(conn), silent = TRUE)
    }
  }, add = TRUE)

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
    
    # Gera o hash de deduplicação via MD5 de Título + Agência (entidade)
    if (is.null(row$hash_deduplicacao) || is.na(row$hash_deduplicacao) || !nzchar(row$hash_deduplicacao)) {
      hash_input <- paste(row$entidade, row$titulo, sep = "||")
      row$hash_deduplicacao <- digest::digest(hash_input, algo = "md5")
    }
    
    if (is.null(row$id_registro) || is.na(row$id_registro) || !nzchar(row$id_registro)) {
      row$id_registro <- paste0("auto_", substr(row$hash_deduplicacao, 1, 16))
    }

    affected <- tryCatch({
      DBI::dbExecute(conn, sql_upsert, params = row)
    }, error = function(e) {
      0L
    })

    if (affected > 0) inserted <- inserted + 1L
  }

  DBI::dbCommit(conn)
  in_transaction <- FALSE
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


# --- Métricas de Performance ---

log_metric <- function(conn, fonte, metric_type, value, context = NULL) {
  tryCatch({
    ctx_json <- if (!is.null(context)) jsonlite::toJSON(context, auto_unbox = TRUE) else NULL
    DBI::dbExecute(conn,
      "INSERT INTO metrics_coleta (fonte, timestamp, metric_type, metric_value, context) VALUES (?, ?, ?, ?, ?)",
      params = list(fonte, as.character(Sys.time()), metric_type, value, ctx_json)
    )
  }, silent = TRUE)
}

get_latency_by_source <- function(conn, hours = 24) {
  tryCatch({
    DBI::dbGetQuery(conn, "
      SELECT fonte, AVG(metric_value) as avg_latency, COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'http_latency' AND timestamp > datetime('now', ?)
      GROUP BY fonte ORDER BY avg_latency DESC
    ", params = list(paste0("-", hours, " hours")))
  }, error = function(e) data.frame())
}

get_block_rate <- function(conn, hours = 24) {
  tryCatch({
    DBI::dbGetQuery(conn, "
      SELECT fonte,
             SUM(CASE WHEN json_extract(context, '$.blocked') = 1 THEN 1 ELSE 0 END) as blocks,
             COUNT(*) as total,
             ROUND(100.0 * SUM(CASE WHEN json_extract(context, '$.blocked') = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) as block_pct
      FROM metrics_coleta
      WHERE metric_type = 'http_request' AND timestamp > datetime('now', ?)
      GROUP BY fonte
    ", params = list(paste0("-", hours, " hours")))
  }, error = function(e) data.frame())
}

get_ai_provider_usage <- function(conn, hours = 24) {
  tryCatch({
    DBI::dbGetQuery(conn, "
      SELECT json_extract(context, '$.provider') as provider,
             AVG(metric_value) as avg_latency,
             COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'ai_request' AND timestamp > datetime('now', ?)
      GROUP BY provider
    ", params = list(paste0("-", hours, " hours")))
  }, error = function(e) data.frame())
}

get_collection_throughput <- function(conn, hours = 24) {
  tryCatch({
    DBI::dbGetQuery(conn, "
      SELECT fonte, SUM(metric_value) as total_records,
             COUNT(*) as n_sources
      FROM metrics_coleta
      WHERE metric_type = 'source_records' AND timestamp > datetime('now', ?)
      GROUP BY fonte ORDER BY total_records DESC
    ", params = list(paste0("-", hours, " hours")))
  }, error = function(e) data.frame())
}
