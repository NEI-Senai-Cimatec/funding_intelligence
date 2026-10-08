get_db_connection <- function(db_path) {
  ensure_dir(dirname(db_path))
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  # Ativar WAL mode e timeout de concorrência (10s) para evitar "database locked"
  try(
    {
      DBI::dbExecute(conn, "PRAGMA journal_mode = WAL;")
      DBI::dbExecute(conn, "PRAGMA busy_timeout = 10000;")
      DBI::dbExecute(conn, "PRAGMA encoding = 'UTF-8';")
    },
    silent = TRUE
  )
  return(conn)
}

# ─── Camada de conexão: PostgreSQL via DATABASE_URL, SQLite como fallback ────
# Migração SQLite -> Neon.tech. Se DATABASE_URL existir, toda a aplicação
# (inclusive o job de coleta em callr) conecta ao Postgres; caso contrário,
# permanece no SQLite local. O schema do Postgres é versionado fora do app
# (schema.sql) — o app apenas o verifica.

db_is_postgres <- function(conn) {
  inherits(conn, "PqConnection")
}

conectar_postgres <- function(database_url) {
  if (!requireNamespace("RPostgres", quietly = TRUE)) {
    stop(
      "DATABASE_URL está configurada, mas o pacote RPostgres não está instalado. Instale com install.packages('RPostgres').",
      call. = FALSE
    )
  }

  parsed <- httr::parse_url(database_url)
  host <- parsed$hostname %||% ""
  dbname <- sub("^/", "", parsed$path %||% "")
  if (!nzchar(host) || !nzchar(dbname)) {
    stop(
      "DATABASE_URL inválida: esperado formato postgresql://usuario:senha@host:5432/banco?sslmode=require",
      call. = FALSE
    )
  }

  # sslmode é garantido: exigido pelo Neon; valor explícito na URL tem precedência.
  sslmode <- parsed$query$sslmode %||% ""
  if (!nzchar(sslmode)) {
    sslmode <- "require"
  }

  # Limite rígido de 2 segundos para evitar qualquer travamento de conexão no Windows
  setTimeLimit(elapsed = 2, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf, transient = FALSE), add = TRUE)

  DBI::dbConnect(
    RPostgres::Postgres(),
    host = host,
    port = as.integer(parsed$port %||% 5432L),
    dbname = dbname,
    user = parsed$username,
    password = parsed$password,
    sslmode = sslmode,
    connect_timeout = 1L,
    application_name = "funding_intelligence",
    options = "-c TimeZone=UTC"
  )
}

.pg_remote_unavailable <- FALSE

conectar_banco <- function(db_path = "funding_intelligence.sqlite") {
  database_url <- trimws(Sys.getenv("DATABASE_URL"))
  is_unavail <- isTRUE(.GlobalEnv$.pg_remote_unavailable) || isTRUE(.pg_remote_unavailable)
  if (nzchar(database_url) && !is_unavail) {
    pg_conn <- tryCatch(
      conectar_postgres(database_url),
      error = function(e) {
        .pg_remote_unavailable <<- TRUE
        .GlobalEnv$.pg_remote_unavailable <- TRUE
        message(sprintf("[DB] Conexão com PostgreSQL remoto indisponível (%s). Recorrendo à base local SQLite (%s).", conditionMessage(e), db_path))
        NULL
      }
    )
    if (!is.null(pg_conn) && DBI::dbIsValid(pg_conn)) return(pg_conn)
  }
  get_db_connection(db_path)
}

# ─── Compatibilidade de placeholders ─────────────────────────────────────────
# RSQLite aceita '?' e ':nome'; RPostgres exige '$1..$n' e NÃO aceita '?'
# nem ':nome' (r-dbi/RPostgres#201, #391). prepare_sql() reescreve a SQL para
# o backend ativo, preservando literais entre aspas simples.

prepare_sql <- function(conn, sql, params = NULL) {
  if (!db_is_postgres(conn)) {
    return(list(sql = sql, params = params))
  }

  chars <- strsplit(sql, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  out <- character(n)
  filled <- 0L
  next_pos <- 0L
  named_at <- integer()
  used_positional <- FALSE
  i <- 1L

  while (i <= n) {
    ch <- chars[[i]]

    # Literal entre aspas simples: copia inteiro (trata '' como escape).
    if (identical(ch, "'")) {
      j <- i + 1L
      closed <- FALSE
      while (j <= n) {
        if (identical(chars[[j]], "'")) {
          if (j < n && identical(chars[[j + 1L]], "'")) {
            j <- j + 2L
            next
          }
          closed <- TRUE
          break
        }
        j <- j + 1L
      }
      end <- if (closed) j else n
      filled <- filled + 1L
      out[[filled]] <- paste(chars[i:end], collapse = "")
      i <- end + 1L
      next
    }

    # Placeholder posicional '?'
    if (identical(ch, "?")) {
      used_positional <- TRUE
      next_pos <- next_pos + 1L
      filled <- filled + 1L
      out[[filled]] <- paste0("$", next_pos)
      i <- i + 1L
      next
    }

    # Placeholder nomeado ':nome' (não confunde com cast '::tipo')
    prev_ok <- i > 1L && !identical(chars[[i - 1L]], ":") &&
      !grepl("[A-Za-z0-9_]", chars[[i - 1L]])
    next_ok <- i < n && grepl("[A-Za-z_]", chars[[i + 1L]])
    if (identical(ch, ":") && prev_ok && next_ok) {
      j <- i + 1L
      while (j <= n && grepl("[A-Za-z0-9_]", chars[[j]])) {
        j <- j + 1L
      }
      name <- paste(chars[(i + 1L):(j - 1L)], collapse = "")
      if (name %in% names(named_at)) {
        idx <- unname(named_at[[name]])
      } else {
        next_pos <- next_pos + 1L
        idx <- next_pos
        named_at[[name]] <- idx
      }
      filled <- filled + 1L
      out[[filled]] <- paste0("$", idx)
      i <- j
      next
    }

    filled <- filled + 1L
    out[[filled]] <- ch
    i <- i + 1L
  }

  if (used_positional && length(named_at) > 0L) {
    stop("SQL mistura placeholders '?' e ':nome' — padronize antes de executar.", call. = FALSE)
  }

  new_params <- params
  if (length(named_at) > 0L) {
    if (is.null(names(params)) || any(!nzchar(names(params)))) {
      stop(sprintf("SQL usa placeholders nomeados (%s), mas params não está nomeado.", paste(names(named_at), collapse = ", ")), call. = FALSE)
    }
    missing <- setdiff(names(named_at), names(params))
    if (length(missing) > 0L) {
      stop(sprintf("Params ausentes para placeholders nomeados: %s", paste(missing, collapse = ", ")), call. = FALSE)
    }
    reordered <- vector("list", next_pos)
    for (nm in names(named_at)) {
      reordered[[unname(named_at[[nm]])]] <- params[[nm]]
    }
    new_params <- reordered
  }

  list(sql = paste(out[seq_len(filled)], collapse = ""), params = new_params)
}

db_exec <- function(conn, sql, params = NULL) {
  q <- prepare_sql(conn, sql, params)
  if (is.null(q$params)) {
    DBI::dbExecute(conn, q$sql)
  } else {
    DBI::dbExecute(conn, q$sql, params = q$params)
  }
}

db_qry <- function(conn, sql, params = NULL) {
  q <- prepare_sql(conn, sql, params)
  if (is.null(q$params)) {
    DBI::dbGetQuery(conn, q$sql)
  } else {
    DBI::dbGetQuery(conn, q$sql, params = q$params)
  }
}

.app_tables <- c(
  "fontes_financiamento", "oportunidades", "migration_flags", "buscas_salvas",
  "editais_rastreados", "perfil_usuario", "historico_buscas", "colaboradores",
  "logs_coleta", "pesquisadores_vencedores", "projetos_aprovados", "metrics_coleta"
)

# Colunas obrigatórias de oportunidades — se o schema do Neon estiver desatualizado
# (ex.: coluna nova em schema.sql ainda não aplicada), o app falha com instrução clara
# em vez de quebrar em runtime ao renderizar a tabela principal.
.oportunidades_cols_esperadas <- c(
  "id_registro", "entidade", "pais_origem", "titulo", "subtitulo", "descricao_resumida",
  "descricao_completa", "tipo_oportunidade", "modalidade", "area_tematica", "palavras_chave",
  "elegibilidade", "publico_alvo", "nivel_academico", "instituicao_financiadora",
  "valor_financiado", "moeda", "data_publicacao", "data_abertura", "data_limite",
  "data_encerramento", "status_oportunidade", "link_origem", "link_detalhe",
  "link_documento_pdf", "idioma", "localidade", "observacoes", "texto_bruto",
  "pagina_coletada", "fonte_oficial", "data_hora_coleta", "hash_deduplicacao", "campus",
  "campos_inferidos_ia", "enrichment_status", "enrichment_model", "enrichment_at",
  "enrichment_error"
)

verificar_schema_postgres <- function(conn) {
  existentes <- DBI::dbGetQuery(
    conn,
    "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = 'public'"
  )$tablename
  faltantes <- setdiff(.app_tables, existentes)
  if (length(faltantes) > 0L) {
    stop(
      sprintf(
        "Schema ausente no PostgreSQL: %s. Aplique schema.sql (ex.: psql -f schema.sql ou neonctl apply) antes de iniciar a aplicação.",
        paste(faltantes, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  cols_oport <- DBI::dbGetQuery(
    conn,
    "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'oportunidades'"
  )$column_name
  cols_faltantes <- setdiff(.oportunidades_cols_esperadas, cols_oport)
  if (length(cols_faltantes) > 0L) {
    stop(
      sprintf(
        paste0(
          "Colunas ausentes em 'oportunidades' no PostgreSQL: %s. ",
          "O schema.sql local está mais atual que o banco — aplique as migrações de coluna ",
          "(ex.: ALTER TABLE oportunidades ADD COLUMN ...) antes de iniciar a aplicação."
        ),
        paste(cols_faltantes, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  message(sprintf("[DB] Schema PostgreSQL verificado: %d tabelas presentes.", length(.app_tables)))
  invisible(TRUE)
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
    "sigitec", "Petrobras SIGITEC - Sistema de Gestão de Inovação e Tecnologia Competitividade", "PETROBRAS", "Brasil", "empresa estatal", "empresa pública", "https://sigitec-competitividade.petrobras.com.br", "https://sigitec-competitividade.petrobras.com.br/v2/public/opportunities", "api_json", "pt", "diária", "API pública do SIGITEC (listagem + detalhe); página /v2/public/opportunities é uma SPA, não um endpoint JSON. Status oficiais A/J/R/F/CC. Fonte canônica; alias legado: anp_shell.",
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
    "darpa_quantum_benchmarking", "DARPA Quantum Benchmarking Initiative", "DARPA QBI", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.darpa.mil/", "https://www.darpa.mil/research/programs/quantum-benchmarking-initiative", "html", "en", "mensal", "Fronteira tecnológica e avaliação de arquiteturas quantum computing. Identificar empresas e pesquisadores avançados.",
    "aeb", "Agência Espacial Brasileira", "AEB", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/aeb/pt-br", "https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos", "html", "pt", "diária", "Concursos e processos seletivos da AEB (seções Abertos/Encerrados). Concursos de cargo são excluídos; consultorias e eventos exigem revisão.",
    "finep_aero", "FINEP Aeroespacial e Defesa", "FINEP Aero", "Brasil", "agência pública nacional", "governo federal", "https://www.finep.gov.br/", "https://www.finep.gov.br/oportunidades", "api_json", "pt", "diária", "Subvenção e fomento FINEP para tecnologias críticas aeroespaciais e de defesa nacional.",
    "fab_dcta", "Departamento de Ciência e Tecnologia Aeroespacial - FAB", "DCTA/FAB", "Brasil", "agência de defesa", "governo federal", "https://www.dcta.fab.mil.br/", "https://ieav.dcta.mil.br/index.php/editais", "html", "pt", "semanal", "Chamadas públicas do IEAv/DCTA com cronogramas (PDF) e retificações.",
    "bnb_fundeci", "Banco do Nordeste - FUNDECI", "BNB FUNDECI", "Brasil", "banco de desenvolvimento", "banco público", "https://www.bnb.gov.br/", "https://www.bnb.gov.br/fundeci/editais", "html", "pt", "semanal", "Editais de seleção de projetos do Fundeci e do Fundo Sustentabilidade (cards, detalhes, PDFs e cronogramas). Inscrições encerradas e vigência são estados distintos.",
    "codevasf", "Companhia de Desenvolvimento dos Vales do São Francisco e do Parnaíba", "CODEVASF", "Brasil", "empresa pública federal", "governo federal", "https://www.codevasf.gov.br/", "https://www.codevasf.gov.br/acesso-a-informacao/licitacoes-e-editais", "html", "pt", "mensal", "Inovação agrícola, irrigação, bioeconomia e desenvolvimento sustentável na bacia do São Francisco e Oeste Baiano.",
    "embrapa", "Empresa Brasileira de Pesquisa Agropecuária & MAPA", "EMBRAPA/MAPA", "Brasil", "empresa pública de pesquisa", "governo federal", "https://www.embrapa.br/", "https://www.embrapa.br/acessoainformacao/editais", "html", "pt", "diária", "A URL cadastrada lista editais de licitação (compras administrativas). Itens são julgados por tipo/objeto; sem chamadas de pesquisa, retorna vazio com diagnóstico.",
    "sudene", "Superintendência do Desenvolvimento do Nordeste", "SUDENE", "Brasil", "agência de desenvolvimento regional", "governo federal", "https://www.gov.br/sudene/pt-br", "https://pncp.gov.br/app/editais?q=533014&status=todos&pagina=1&tam_pagina=100&tipos=1", "html", "pt", "mensal", "Chamadas PRDNE para desenvolvimento regional, matriz energética limpa e inovação agroindustrial no Nordeste/Sertão.",
    "neh", "National Endowment for the Humanities", "NEH", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.neh.gov/", "https://www.neh.gov/grants", "html", "en", "semanal", "Editais e concessões do National Endowment for the Humanities. Foco em humanidades digitais, infraestrutura de pesquisa, inovação cultural e tecnologia.",
    "bndes", "Banco Nacional de Desenvolvimento Econômico e Social", "BNDES", "Brasil", "banco de desenvolvimento", "banco público", "https://www.bndes.gov.br/", "https://www.bndes.gov.br/wps/portal/site/home/transparencia/licitacoes-contratos/licitacoes/", "html", "pt", "semanal", "Licitações do BNDES; prioridade para Chamadas públicas para contratação de inovação (CPSI). Navegação, redes sociais e serviços de crédito não são oportunidades.",
    "esa_solutions", "ESA Space Solutions - European Space Agency", "ESA Solutions", "Europa", "agência espacial internacional", "organização multilateral", "https://business.esa.int/", "https://business.esa.int/funding", "html", "en", "semanal", "Oportunidades de financiamento direto e chamadas abertas da Agência Espacial Europeia (ESA) para soluções comerciais, satélites, IoT e aplicações terrestres.",
    "nasa_sbir", "NASA Small Business Innovation Research / STTR", "NASA SBIR", "Estados Unidos", "agência espacial", "governo federal", "https://sbir.nasa.gov/", "https://sbir.nasa.gov/solicitations", "html", "en", "mensal", "Financiamento de P&D tecnológico da NASA em automação, robótica, sensores avançados, computação embarcada e aeroespacial.",
    "facepe", "Fundação de Amparo à Ciência e Tecnologia de Pernambuco", "FACEPE", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.facepe.br/", "https://www.facepe.br/editais/", "html", "pt", "semanal", "Editais e chamadas de P&D e inovação da FACEPE, com forte aderência ao ecossistema de TI, automação, IoT e pólos tecnológicos do Nordeste.",
    "funcap", "Fundação Cearense de Apoio ao Desenvolvimento Científico e Tecnológico", "FUNCAP", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.funcap.ce.gov.br/", "https://www.funcap.ce.gov.br/editais/", "html", "pt", "semanal", "Editais FUNCAP. A página principal pode falhar na validação TLS (estado da fonte, sem bypass); alternativa oficial: https://montenegro.funcap.ce.gov.br/sugba/editais/index_montenegro.php.",
    "fapeal", "Fundação de Amparo à Pesquisa do Estado de Alagoas", "FAPEAL", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapeal.br/", "https://fapeal.br/editais/", "html", "pt", "mensal", "Editais de pesquisa e desenvolvimento tecnológico da FAPEAL para pesquisadores e ICTs regionais.",
    "fapema", "Fundação de Amparo à Pesquisa e ao Desenvolvimento Científico e Tecnológico do Maranhão", "FAPEMA", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.fapema.br/", "https://www.fapema.br/editais/", "html", "pt", "mensal", "Chamadas e editais da FAPEMA para ciência, tecnologia e inovação no Maranhão e integração Nordeste.",
    "transferegov", "Portal Transferegov.br - Convênios e Programas Federais", "Transferegov", "Brasil", "portal federal de convênios", "governo federal", "https://www.gov.br/transferegov/pt-br", "https://www.gov.br/transferegov/pt-br", "html", "pt", "diária", "Portal unificado de captação e repasse de recursos voluntários da União, descentralização de recursos (TEDs), emendas e programas governamentais para ICTs.",
    "bnb_hubine", "Banco do Nordeste - Hub de Inovação (Hubine)", "Hubine BNB", "Brasil", "hub de inovação bancário", "banco público", "https://www.bnb.gov.br/hub-de-inovacao", "https://www.bnb.gov.br/hub-de-inovacao", "html", "pt", "mensal", "Página institucional do hub; só seleções concretas com documento (aceleração, CPSI) são oportunidades. Zero oportunidades é resultado válido.",
    "sebrae", "SEBRAE Inovação & Sebraetec", "SEBRAE", "Brasil", "serviço social autônomo", "sistema s", "https://sebrae.com.br/", "https://sebrae.com.br/sites/PortalSebrae/canais_adicionais/conheca_editais", "html", "pt", "semanal", "Editais de inovação do SEBRAE para MPEs, programas Sebraetec (automação e digitalização), Catalisa ICT e conexões universidade-empresa.",
    "softex", "Associação SOFTEX - Programas Prioritários MCTI", "SOFTEX", "Brasil", "organização social de ti", "associação civil", "https://softex.br/", "https://softex.br/editais/", "html", "pt", "semanal", "Editais e chamadas dos Programas Prioritários da Lei de Informática / MCTI para Inteligência Artificial, Ciência de Dados, IoT e Indústria 4.0.",
    "pncp_gov", "Governo Federal - PNCP & Ministérios (MCTI, MDIC, MPOR, Defesa, Marinha)", "PNCP Gov", "Brasil", "portal público federal", "governo federal", "https://pncp.gov.br/", "https://pncp.gov.br/api/consulta/v1/contratacoes/publicas", "api_json", "pt", "diária", "API REST pública PNCP para ministérios federais, Marinha do Brasil, Ministério da Defesa, MCTI, MDIC e MPOR.",
    "fapesp", "Fundação de Amparo à Pesquisa do Estado de São Paulo", "FAPESP", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapesp.br/", "https://fapesp.br/chamadas", "html", "pt", "diária", "Chamadas de pesquisa, PIPE-FAPESP, centros de pesquisa e parcerias industriais.",
    "faperj", "Fundação Carlos Chagas Filho de Amparo à Pesquisa do Estado do RJ", "FAPERJ", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.faperj.br/", "https://www.faperj.br/?id=editais", "html", "pt", "diária", "Editais FAPERJ de infraestrutura, inovação tecnológica e setor naval/offshore do Rio de Janeiro.",
    "fapemig", "Fundação de Amparo à Pesquisa do Estado de Minas Gerais", "FAPEMIG", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapemig.br/", "https://fapemig.br/pt/chamadas/", "html", "pt", "semanal", "Chamadas públicas FAPEMIG para PD&I e parcerias institucionais.",
    "fapesc", "Fundação de Amparo à Pesquisa e Inovação do Estado de Santa Catarina", "FAPESC", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapesc.sc.gov.br/", "https://fapesc.sc.gov.br/editais/", "html", "pt", "semanal", "Editais FAPESC para ecossistema de inovação, robótica e tecnologia marítima/portuária.",
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
      campus TEXT,
      campos_inferidos_ia TEXT,
      enrichment_status TEXT DEFAULT 'pendente',
      enrichment_model TEXT,
      enrichment_at TEXT,
      enrichment_error TEXT,
      status_oficial TEXT,
      fluxo_continuo INTEGER,
      id_chamada TEXT,
      tipo_escopo TEXT,
      validacao_status TEXT,
      validacao_motivo TEXT,
      validacao_evidencia TEXT,
      validacao_versao TEXT,
      validacao_em TEXT,
      proveniencia_json TEXT,
      campus_justificativa TEXT,
      valor_teto_projeto REAL,
      data_vigencia_fim TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS id_aliases (
      id_antigo TEXT PRIMARY KEY,
      id_novo TEXT,
      motivo TEXT,
      criado_em TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS saneamento_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id TEXT,
      id_registro TEXT,
      acao TEXT,
      justificativa TEXT,
      antes_json TEXT,
      depois_json TEXT,
      criado_em TEXT,
      revertido_em TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS migration_flags (
      flag TEXT PRIMARY KEY,
      applied_at TEXT
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

  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS user_access_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      email TEXT,
      role TEXT,
      action TEXT,
      details TEXT,
      timestamp TEXT DEFAULT (datetime('now', 'localtime'))
    )")
}

seed_sources <- function(conn) {
  src <- source_catalog()
  purrr::pwalk(src, function(...) {
    row <- list(...)
    db_exec(
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
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM historico_buscas")$n[[1]]
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
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM colaboradores")$n[[1]]
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
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM pesquisadores_vencedores")$n[[1]]
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
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM projetos_aprovados")$n[[1]]
  if (existing > 0) {
    return(invisible(FALSE))
  }

  pesq <- DBI::dbGetQuery(conn, "SELECT id, nome FROM pesquisadores_vencedores")

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


# Modo demonstração: SOMENTE com configuração explícita (FI_DEMO_MODE=true ou options(fi.demo_mode = TRUE)).
# Nunca é chamado como fallback de produção; registros demo têm prefixo `demo_` e fonte `demo`.
demo_mode_enabled <- function() {
  isTRUE(getOption("fi.demo_mode", FALSE)) || identical(tolower(Sys.getenv("FI_DEMO_MODE", "false")), "true")
}

seed_demo_opportunities <- function(conn) {
  if (!demo_mode_enabled()) {
    return(invisible(FALSE))
  }
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]]
  if (existing > 0) {
    return(invisible(FALSE))
  }
  today <- Sys.Date()
  demo <- tibble::tribble(
    ~entidade, ~pais_origem, ~titulo, ~subtitulo, ~descricao_resumida, ~descricao_completa, ~tipo_oportunidade, ~modalidade, ~area_tematica, ~palavras_chave, ~elegibilidade, ~publico_alvo, ~nivel_academico, ~instituicao_financiadora, ~valor_financiado, ~moeda, ~data_publicacao, ~data_abertura, ~data_limite, ~data_encerramento, ~status_oportunidade, ~link_origem, ~link_detalhe, ~link_documento_pdf, ~idioma, ~localidade, ~observacoes, ~texto_bruto, ~pagina_coletada, ~fonte_oficial, ~data_hora_coleta,
    "CNPq", "Brasil", "Edital Demo de Inovação em Saúde", "Base demonstrativa", "Apoio a projetos de inovação em saúde.", "Registro de demonstração (modo explícito).", "edital", "individual", "Saúde", "health; innovation; medical devices", "ICTs e pesquisadores", "pesquisadores; instituições", "doutorado", "CNPq", 100000, "BRL", as.character(today - 20), as.character(today - 15), as.character(today + 25), NA_character_, "aberto", "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao", "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao", NA_character_, "pt", "Brasil", "DEMONSTRACAO (FI_DEMO_MODE).", "DEMONSTRACAO (FI_DEMO_MODE).", 1L, "demo", as.character(Sys.time()),
    "Horizon Europe", "União Europeia", "Grant Demo for Energy Transition", "Seed", "Support for collaborative R&D in low-carbon industry.", "Seed record for initial dashboard rendering.", "grant", "rede", "Transição Energética", "energy transition; hydrogen; biomethane", "universities; companies; research organisations", "instituições; empresas", "instituição", "Horizon Europe", 2500000, "EUR", as.character(today - 40), as.character(today - 35), as.character(today + 60), NA_character_, "aberto", "https://research-and-innovation.ec.europa.eu/", "https://research-and-innovation.ec.europa.eu/", NA_character_, "en", "União Europeia", "DEMONSTRACAO (FI_DEMO_MODE).", "DEMONSTRACAO (FI_DEMO_MODE).", 1L, "demo", as.character(Sys.time())
  )
  demo$hash_deduplicacao <- vapply(seq_len(nrow(demo)), function(i) {
    make_hash(demo$entidade[i], normalize_text(demo$titulo[i]), demo$link_detalhe[i])
  }, character(1))
  demo <- demo |>
    dplyr::mutate(
      id_registro = paste0("demo_", seq_len(dplyr::n())),
      fonte_oficial = "demo",
      tipo_escopo = "demo", validacao_status = "validado", validacao_motivo = "demo_explicito", validacao_versao = "demo",
      campos_inferidos_ia = ""
    ) |>
    dplyr::select(id_registro, dplyr::everything())
  DBI::dbWriteTable(conn, "oportunidades", demo, append = TRUE)
}

# ─── Migrações idempotentes (BUG-02/12) ───────────────────────────────────────
# Adiciona as colunas de proveniência de enriquecimento em bancos existentes e
# recalcula hash_deduplicacao (que nunca mais inclui data_limite).

.enrichment_columns <- list(
  campus = "TEXT",
  enrichment_status = "TEXT DEFAULT 'pendente'",
  enrichment_model = "TEXT",
  enrichment_at = "TEXT",
  enrichment_error = "TEXT",
  aderencia_naval_nivel = "TEXT",
  aderencia_naval_justificativa = "TEXT",
  ideia_projeto_consorcio = "TEXT",
  aderencia_sertao_nivel = "TEXT",
  aderencia_sertao_justificativa = "TEXT",
  ideia_projeto_sertao = "TEXT",
  aderencia_aero_nivel = "TEXT",
  aderencia_aero_justificativa = "TEXT",
  ideia_projeto_aero = "TEXT",
  aderencia_digital_nivel = "TEXT",
  aderencia_digital_justificativa = "TEXT",
  ideia_projeto_digital = "TEXT",
  aderencia_park_nivel = "TEXT",
  aderencia_park_justificativa = "TEXT",
  ideia_projeto_park = "TEXT"
)

migration_marker <- function(conn, flag) {
  tryCatch(
    {
      res <- db_qry(conn, "SELECT 1 AS ok FROM migration_flags WHERE flag = ?", params = list(flag))
      nrow(res) > 0L
    },
    error = function(e) TRUE
  )
}

set_migration_marker <- function(conn, flag) {
  try(
    {
      # ON CONFLICT funciona tanto no SQLite (>=3.24) quanto no PostgreSQL,
      # substituindo o INSERT OR REPLACE exclusivo do SQLite.
      db_exec(
        conn,
        "INSERT INTO migration_flags (flag, applied_at) VALUES (?, ?) ON CONFLICT(flag) DO UPDATE SET applied_at = excluded.applied_at",
        params = list(flag, as.character(Sys.time()))
      )
    },
    silent = TRUE
  )
}

# Colunas do contrato de integridade brasileiro (R01/R02/R03). Idempotente; SQLite e PostgreSQL.
.br_integrity_columns <- list(
  status_oficial = "TEXT", fluxo_continuo = "INTEGER", id_chamada = "TEXT", tipo_escopo = "TEXT",
  validacao_status = "TEXT", validacao_motivo = "TEXT", validacao_evidencia = "TEXT",
  validacao_versao = "TEXT", validacao_em = "TEXT", proveniencia_json = "TEXT",
  campus_justificativa = "TEXT", valor_teto_projeto = "REAL", data_vigencia_fim = "TEXT"
)

migrate_br_integrity_columns <- function(conn) {
  cols <- tryCatch(DBI::dbListFields(conn, "oportunidades"), error = function(e) character())
  pg <- db_is_postgres(conn)
  for (nm in names(.br_integrity_columns)) {
    if (!nm %in% cols) {
      ty <- .br_integrity_columns[[nm]]
      if (pg && ty == "REAL") ty <- "DOUBLE PRECISION"
      DBI::dbExecute(conn, sprintf("ALTER TABLE oportunidades ADD COLUMN %s %s", nm, ty))
      message(sprintf("[Migration] Coluna '%s' adicionada a oportunidades.", nm))
    }
  }
  id_pk <- if (pg) "TEXT PRIMARY KEY" else "TEXT PRIMARY KEY"
  DBI::dbExecute(conn, sprintf("CREATE TABLE IF NOT EXISTS id_aliases (id_antigo %s, id_novo TEXT, motivo TEXT, criado_em TEXT)", id_pk))
  serial <- if (pg) "SERIAL PRIMARY KEY" else "INTEGER PRIMARY KEY AUTOINCREMENT"
  DBI::dbExecute(conn, sprintf("CREATE TABLE IF NOT EXISTS saneamento_log (id %s, batch_id TEXT, id_registro TEXT, acao TEXT, justificativa TEXT, antes_json TEXT, depois_json TEXT, criado_em TEXT, revertido_em TEXT)", serial))
  invisible(TRUE)
}

migrate_enrichment_columns <- function(conn) {
  cols <- tryCatch(DBI::dbListFields(conn, "oportunidades"), error = function(e) character())
  for (nm in names(.enrichment_columns)) {
    if (!nm %in% cols) {
      DBI::dbExecute(conn, sprintf("ALTER TABLE oportunidades ADD COLUMN %s %s", nm, .enrichment_columns[[nm]]))
      message(sprintf("[Migration] Coluna '%s' adicionada a oportunidades.", nm))
    }
  }
  invisible(TRUE)
}

migrate_dedup_hashes <- function(conn) {
  if (!isTRUE(migration_marker(conn, "dedup_hash_v2"))) {
    res <- tryCatch(
      {
        DBI::dbGetQuery(conn, "SELECT id_registro, entidade, titulo, link_detalhe, link_documento_pdf, link_origem, hash_deduplicacao FROM oportunidades")
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
              db_exec(
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

migrate_existing_keywords <- function(conn) {
  res <- tryCatch(
    {
      DBI::dbGetQuery(conn, "SELECT id_registro, titulo, subtitulo, descricao_resumida, descricao_completa, palavras_chave, campos_inferidos_ia FROM oportunidades")
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
            db_exec(
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

# Limpeza NÃO destrutiva (R07): por padrão apenas relata (dry run). Com apply = TRUE move para
# QUARENTENA reversível (nunca DELETE) os registros brasileiros sintéticos/fora do escopo,
# usando validate_opportunity(). Nunca é chamada na inicialização do app.
# Saneamento completo e rollback: tools/sanitize_br.R / R/helpers_sanitize.R.
cleanup_database_opportunities <- function(conn, apply = FALSE, batch_id = NULL) {
  plan <- sanitize_br_plan(conn)
  if (!isTRUE(apply)) {
    return(invisible(plan))
  }
  sanitize_br_apply(conn, plan, batch_id = batch_id)
}

# Poda o catálogo para as 21 fontes ativas (fontes descontinuadas do catálogo
# ampliado não devem ser coletadas). Idempotente e válida em ambos os backends.
prune_inactive_sources <- function(conn) {
  try({
    active_ids <- source_catalog()$id_fonte
    if (length(active_ids) > 0) {
      placeholders <- paste(rep("?", length(active_ids)), collapse = ", ")
      sql <- sprintf("DELETE FROM fontes_financiamento WHERE id_fonte NOT IN (%s)", placeholders)
      db_exec(conn, sql, params = as.list(active_ids))
    }
  }, silent = TRUE)
  invisible(TRUE)
}

init_database <- function(db_path) {
  conn <- conectar_banco(db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  if (db_is_postgres(conn)) {
    # Postgres/Neon: schema versionado externamente (schema.sql). O app apenas
    # verifica a presença das tabelas e mantém o catálogo de fontes idempotente.
    # Seeds demonstrativos e migrações SQLite são aplicáveis somente ao fallback local.
    verificar_schema_postgres(conn)
    try(migrate_br_integrity_columns(conn), silent = TRUE)
    seed_sources(conn)
    prune_inactive_sources(conn)
    return(invisible(TRUE))
  }

  create_tables(conn)
  seed_sources(conn)
  prune_inactive_sources(conn)
  try(DBI::dbExecute(conn, "UPDATE oportunidades SET pais_origem = 'União Europeia' WHERE pais_origem = 'Uniao Europeia'"), silent = TRUE)
  seed_profile(conn)
  seed_saved_searches(conn)
  seed_search_history(conn)
  seed_collaborators(conn)
  seed_demo_opportunities(conn)
  seed_pesquisadores_vencedores(conn)
  seed_projetos_aprovados(conn)
  # NÃO há limpeza destrutiva na inicialização: saneamento é explícito (tools/sanitize_br.R),
  # com dry run por padrão, quarentena reversível e log de rollback.
  try(migrate_existing_keywords(conn), silent = TRUE)
  try(migrate_enrichment_columns(conn), silent = TRUE)
  try(migrate_br_integrity_columns(conn), silent = TRUE)
  try(migrate_dedup_hashes(conn), silent = TRUE)
  invisible(TRUE)
}

read_table <- function(conn, table_name) DBI::dbReadTable(conn, table_name)

# `only_validated = TRUE` (padrão): tabela, filtros, KPIs, recomendações, alertas e exportações usam o
# MESMO universo validado. Itens a_verificar/rejeitado/quarentena ficam em `opportunities_review`.
# Registros legados sem avaliação (validacao_status NULL) permanecem visíveis (compatibilidade).
read_app_data <- function(conn, only_validated = TRUE) {
  all_opps <- tibble::as_tibble(read_table(conn, "oportunidades")) |>
    dplyr::mutate(
      data_publicacao = parse_date_safe(data_publicacao),
      data_abertura = parse_date_safe(data_abertura),
      data_limite = parse_date_safe(data_limite),
      data_encerramento = parse_date_safe(data_encerramento),
      data_hora_coleta = parse_datetime_safe(data_hora_coleta),
      valor_financiado = suppressWarnings(as.numeric(valor_financiado))
    )
  pub <- if (isTRUE(only_validated)) filter_validated(all_opps) else all_opps
  review <- if ("validacao_status" %in% names(all_opps)) {
    all_opps[!is.na(all_opps$validacao_status) & all_opps$validacao_status != "validado", , drop = FALSE]
  } else all_opps[0, , drop = FALSE]
  list(
    opportunities = pub,
    opportunities_review = review,
    sources = tibble::as_tibble(read_table(conn, "fontes_financiamento")),
    saved_searches = tibble::as_tibble(read_table(conn, "buscas_salvas")),
    tracked = tibble::as_tibble(read_table(conn, "editais_rastreados")),
    history = tibble::as_tibble(read_table(conn, "historico_buscas")),
    profile = tibble::as_tibble(read_table(conn, "perfil_usuario")),
    collaborators = tibble::as_tibble(read_table(conn, "colaboradores")),
    logs = tibble::as_tibble(read_table(conn, "logs_coleta")),
    user_access_logs = tibble::as_tibble(tryCatch(read_table(conn, "user_access_logs"), error = function(e) tibble::tibble()))
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

# Contrato de persistência (R07 / T20 T21):
#  * Campo ausente (NULL/NA/"") no novo registro NÃO apaga o valor já persistido
#    (COALESCE por campo): uma coleta parcial não destrói dado verificado, enriquecimento
#    de IA, avaliações ou referências do usuário.
#  * Valor novo não vazio atualiza (ex.: prazo retificado).
#  * Remoção oficial de um campo é EXPLÍCITA: `clear_fields = list(<id_registro> = c("data_limite"))`.
#  * Decisões manuais de validação (validacao_motivo iniciando em "manual:") não são sobrescritas.
#  * Colisões de hash UNIQUE e falhas por linha são CONTADAS e expostas como atributos do retorno.
upsert_opportunities <- function(conn, opportunities_df, clear_fields = NULL) {
  if (is.null(opportunities_df) || nrow(opportunities_df) == 0) {
    return(invisible(structure(0L, updated = 0L, collisions = 0L, failed = 0L)))
  }

  cols <- DBI::dbListFields(conn, "oportunidades")
  df <- tibble::as_tibble(opportunities_df)
  missing_cols <- setdiff(cols, names(df))
  if (length(missing_cols) > 0) {
    for (nm in missing_cols) df[[nm]] <- NA
  }
  df <- df[, cols, drop = FALSE]

  cols_no_pk <- setdiff(cols, "id_registro")
  numeric_cols <- c("valor_financiado", "valor_teto_projeto", "pagina_coletada", "fluxo_continuo")
  manual_guard <- c("validacao_status", "validacao_motivo", "validacao_evidencia", "validacao_versao", "validacao_em")
  merge_expr <- function(cn) {
    new <- if (cn %in% numeric_cols) sprintf("excluded.%s", cn) else sprintf("NULLIF(excluded.%s, '')", cn)
    base <- sprintf("COALESCE(%s, oportunidades.%s)", new, cn)
    if (cn %in% manual_guard && "validacao_motivo" %in% cols) {
      base <- sprintf("CASE WHEN oportunidades.validacao_motivo LIKE 'manual:%%' THEN oportunidades.%s ELSE %s END", cn, base)
    }
    sprintf("%s = %s", cn, base)
  }
  update_clause <- paste(vapply(cols_no_pk, merge_expr, character(1)), collapse = ", ")
  sql_upsert <- paste0(
    "INSERT INTO oportunidades (", paste(cols, collapse = ", "), ") VALUES (",
    paste(paste0(":", cols), collapse = ", "), ") ON CONFLICT(id_registro) DO UPDATE SET ",
    update_clause
  )
  existing_ids <- tryCatch(DBI::dbGetQuery(conn, "SELECT id_registro FROM oportunidades")$id_registro, error = function(e) character())
  n_updated <- 0L; n_collisions <- 0L; n_failed <- 0L

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

    # SAVEPOINT por linha: em PostgreSQL um erro aborta a transação inteira;
    # o savepoint isola a falha (ex.: colisão de hash UNIQUE) sem perder o lote.
    failed <- FALSE
    was_existing <- !is.null(row$id_registro) && !is.na(row$id_registro) && row$id_registro %in% existing_ids
    DBI::dbExecute(conn, "SAVEPOINT upsert_row")
    affected <- tryCatch(
      {
        db_exec(conn, sql_upsert, params = row)
      },
      error = function(e) {
        failed <<- TRUE
        # Loga colisão de hash_deduplicacao UNIQUE sem abortar o lote (observabilidade)
        try(
          {
            msg <- conditionMessage(e)
            if (grepl("UNIQUE constraint failed.*hash_deduplicacao|hash_deduplicacao.*UNIQUE|duplicate key value violates unique constraint", msg, ignore.case = TRUE)) {
              n_collisions <<- n_collisions + 1L
              warning(sprintf("[upsert] hash colisão ignorada id=%s titulo='%s' hash=%s", row$id_registro %||% "NA", substr(row$titulo %||% "", 1, 60), row$hash_deduplicacao %||% "NA"), call. = FALSE)
            }
          },
          silent = TRUE
        )
        0L
      }
    )
    if (failed) {
      n_failed <- n_failed + 1L
      try(DBI::dbExecute(conn, "ROLLBACK TO SAVEPOINT upsert_row"), silent = TRUE)
    }
    try(DBI::dbExecute(conn, "RELEASE SAVEPOINT upsert_row"), silent = TRUE)

    if (affected > 0) {
      inserted <- inserted + 1L
      if (was_existing) n_updated <- n_updated + 1L
    }
  }

  # Remoção oficial explícita de campos (nunca por ausência no payload)
  if (!is.null(clear_fields) && length(clear_fields) > 0L) {
    for (id in names(clear_fields)) {
      for (cn in intersect(clear_fields[[id]], cols_no_pk)) {
        db_exec(conn, sprintf("UPDATE oportunidades SET %s = NULL WHERE id_registro = ?", cn), params = list(id))
      }
    }
  }

  DBI::dbCommit(conn)
  in_transaction <- FALSE
  invisible(structure(inserted, updated = n_updated, collisions = n_collisions, failed = n_failed))
}

log_collection <- function(conn, fonte, metodo_coleta, status_execucao, mensagem, n_paginas = 0L, n_registros = 0L, url = NA_character_) {
  db_exec(
    conn,
    "INSERT INTO logs_coleta (fonte, metodo_coleta, status_execucao, mensagem, n_paginas, n_registros, url, data_execucao) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(fonte, metodo_coleta, status_execucao, mensagem, as.integer(n_paginas), as.integer(n_registros), url, as.character(Sys.time()))
  )
}

save_search_record <- function(conn, query_text, filters_json = "{}") {
  db_exec(conn, "INSERT INTO historico_buscas (query_text, filtros_json, executed_at) VALUES (?, ?, ?)", params = list(query_text, filters_json, as.character(Sys.time())))
}

save_named_search <- function(conn, nome_busca, query_text, payload_avancado = "{}", alerta_ativo = 0L) {
  db_exec(conn, "INSERT INTO buscas_salvas (nome_busca, query_text, payload_avancado, alerta_ativo, created_at, last_run_at) VALUES (?, ?, ?, ?, ?, ?)", params = list(nome_busca, query_text, payload_avancado, as.integer(alerta_ativo), as.character(Sys.time()), as.character(Sys.time())))
}

mark_saved_search_run <- function(conn, id) {
  db_exec(conn, "UPDATE buscas_salvas SET last_run_at = ? WHERE id = ?", params = list(as.character(Sys.time()), id))
}

track_opportunity <- function(conn, id_oportunidade, status_usuario = "avaliar", observacoes = "") {
  db_exec(
    conn,
    "INSERT INTO editais_rastreados (id_oportunidade, status_usuario, observacoes, tracked_at, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id_oportunidade) DO UPDATE SET status_usuario = excluded.status_usuario, observacoes = excluded.observacoes, updated_at = excluded.updated_at",
    params = list(id_oportunidade, status_usuario, observacoes, as.character(Sys.time()), as.character(Sys.time()))
  )
}

update_tracked_opportunity <- function(conn, id_oportunidade, status_usuario, observacoes = "") {
  db_exec(conn, "UPDATE editais_rastreados SET status_usuario = ?, observacoes = ?, updated_at = ? WHERE id_oportunidade = ?", params = list(status_usuario, observacoes, as.character(Sys.time()), id_oportunidade))
}

delete_tracked_opportunity <- function(conn, id_oportunidade) {
  db_exec(conn, "DELETE FROM editais_rastreados WHERE id_oportunidade = ?", params = list(id_oportunidade))
}


# --- Métricas de Performance ---

log_metric <- function(conn, fonte, metric_type, value, context = NULL) {
  tryCatch(
    {
      ctx_json <- if (!is.null(context)) as.character(jsonlite::toJSON(context, auto_unbox = TRUE)) else NULL
      db_exec(conn,
        "INSERT INTO metrics_coleta (fonte, timestamp, metric_type, metric_value, context) VALUES (?, ?, ?, ?, ?)",
        params = list(fonte, as.character(Sys.time()), metric_type, value, ctx_json)
      )
    },
    silent = TRUE
  )
}

# Filtro temporal por dialect: SQLite usa datetime('now', ...); Postgres usa interval.
.metric_time_filter_sql <- function(conn, param_name) {
  if (db_is_postgres(conn)) {
    sprintf("\"timestamp\" > now() - (%s::int * interval '1 hour')", param_name)
  } else {
    sprintf("timestamp > datetime('now', %s)", param_name)
  }
}

.get_metrics_window <- function(conn, hours) {
  if (db_is_postgres(conn)) list(as.integer(hours)) else list(paste0("-", hours, " hours"))
}

get_latency_by_source <- function(conn, hours = 24) {
  tryCatch(
    {
      sql <- sprintf("
      SELECT fonte, AVG(metric_value) as avg_latency, COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'http_latency' AND %s
      GROUP BY fonte ORDER BY avg_latency DESC
    ", .metric_time_filter_sql(conn, if (db_is_postgres(conn)) "$1" else "?"))
      db_qry(conn, sql, params = .get_metrics_window(conn, hours))
    },
    error = function(e) data.frame()
  )
}

get_block_rate <- function(conn, hours = 24) {
  tryCatch(
    {
      if (db_is_postgres(conn)) {
        sql <- "
      SELECT fonte,
             SUM(CASE WHEN (context->>'blocked')::boolean THEN 1 ELSE 0 END) as blocks,
             COUNT(*) as total,
             ROUND(100.0 * SUM(CASE WHEN (context->>'blocked')::boolean THEN 1 ELSE 0 END) / COUNT(*), 2) as block_pct
      FROM metrics_coleta
      WHERE metric_type = 'http_request' AND \"timestamp\" > now() - ($1::int * interval '1 hour')
      GROUP BY fonte
    "
      } else {
        sql <- "
      SELECT fonte,
             SUM(CASE WHEN json_extract(context, '$.blocked') = 1 THEN 1 ELSE 0 END) as blocks,
             COUNT(*) as total,
             ROUND(100.0 * SUM(CASE WHEN json_extract(context, '$.blocked') = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) as block_pct
      FROM metrics_coleta
      WHERE metric_type = 'http_request' AND timestamp > datetime('now', ?)
      GROUP BY fonte
    "
      }
      db_qry(conn, sql, params = .get_metrics_window(conn, hours))
    },
    error = function(e) data.frame()
  )
}

get_ai_provider_usage <- function(conn, hours = 24) {
  tryCatch(
    {
      if (db_is_postgres(conn)) {
        sql <- "
      SELECT context->>'provider' as provider,
             AVG(metric_value) as avg_latency,
             COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'ai_request' AND \"timestamp\" > now() - ($1::int * interval '1 hour')
      GROUP BY provider
    "
      } else {
        sql <- "
      SELECT json_extract(context, '$.provider') as provider,
             AVG(metric_value) as avg_latency,
             COUNT(*) as n_requests
      FROM metrics_coleta
      WHERE metric_type = 'ai_request' AND timestamp > datetime('now', ?)
      GROUP BY provider
    "
      }
      db_qry(conn, sql, params = .get_metrics_window(conn, hours))
    },
    error = function(e) data.frame()
  )
}

get_collection_throughput <- function(conn, hours = 24) {
  tryCatch(
    {
      sql <- sprintf("
      SELECT fonte, SUM(metric_value) as total_records,
             COUNT(*) as n_sources
      FROM metrics_coleta
      WHERE metric_type = 'source_records' AND %s
      GROUP BY fonte ORDER BY total_records DESC
    ", .metric_time_filter_sql(conn, if (db_is_postgres(conn)) "$1" else "?"))
      db_qry(conn, sql, params = .get_metrics_window(conn, hours))
    },
    error = function(e) data.frame()
  )
}
