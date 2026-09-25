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

  DBI::dbConnect(
    RPostgres::Postgres(),
    host = host,
    port = as.integer(parsed$port %||% 5432L),
    dbname = dbname,
    user = parsed$username,
    password = parsed$password,
    sslmode = sslmode,
    application_name = "funding_intelligence",
    # Fixa a sessão em UTC: strings de data/hora sem fuso (geradas pelo R com
    # as.character(Sys.time())) são interpretadas como UTC, preservando a
    # semântica atual do SQLite + parse_datetime_safe(tz = "UTC").
    options = "-c TimeZone=UTC"
  )
}

conectar_banco <- function(db_path = "funding_intelligence.sqlite") {
  database_url <- trimws(Sys.getenv("DATABASE_URL"))
  if (nzchar(database_url)) {
    return(conectar_postgres(database_url))
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
    "darpa_quantum_benchmarking", "DARPA Quantum Benchmarking Initiative", "DARPA QBI", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.darpa.mil/", "https://www.darpa.mil/research/programs/quantum-benchmarking-initiative", "html", "en", "mensal", "Fronteira tecnológica e avaliação de arquiteturas quantum computing. Identificar empresas e pesquisadores avançados.",
    "aeb", "Agência Espacial Brasileira", "AEB", "Brasil", "agência pública nacional", "governo federal", "https://www.gov.br/aeb/pt-br", "https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos", "html", "pt", "diária", "Programa Espacial Brasileiro, Uniespaço, satélites, VANTs e sensoriamento remoto.",
    "finep_aero", "FINEP Aeroespacial e Defesa", "FINEP Aero", "Brasil", "agência pública nacional", "governo federal", "https://www.finep.gov.br/", "https://www.finep.gov.br/oportunidades", "api_json", "pt", "diária", "Subvenção e fomento FINEP para tecnologias críticas aeroespaciais e de defesa nacional.",
    "fab_dcta", "Departamento de Ciência e Tecnologia Aeroespacial - FAB", "DCTA/FAB", "Brasil", "agência de defesa", "governo federal", "https://www.dcta.fab.mil.br/", "https://ieav.dcta.mil.br/index.php/editais", "html", "pt", "semanal", "Pesquisa e inovação aeroespacial de defesa, radares, propulsão e veículos aéreos.",
    "bnb_fundeci", "Banco do Nordeste - FUNDECI", "BNB FUNDECI", "Brasil", "banco de desenvolvimento", "banco público", "https://www.bnb.gov.br/", "https://www.bnb.gov.br/ConveniosWeb/Convenente.ProgramaConvenio.Lista.aspx", "html", "pt", "semanal", "Fundo de desenvolvimento para agricultura de precisão, semiárido, energias renováveis e recursos hídricos no Sertão.",
    "codevasf", "Companhia de Desenvolvimento dos Vales do São Francisco e do Parnaíba", "CODEVASF", "Brasil", "empresa pública federal", "governo federal", "https://www.codevasf.gov.br/", "https://www.codevasf.gov.br/acesso-a-informacao/licitacoes-e-editais", "html", "pt", "mensal", "Inovação agrícola, irrigação, bioeconomia e desenvolvimento sustentável na bacia do São Francisco e Oeste Baiano.",
    "embrapa", "Empresa Brasileira de Pesquisa Agropecuária & MAPA", "EMBRAPA/MAPA", "Brasil", "empresa pública de pesquisa", "governo federal", "https://www.embrapa.br/", "https://www.embrapa.br/acessoainformacao/editais", "html", "pt", "diária", "Biotecnologia agrícola, agrotech, convivência com o semiárido e bioeconomia para o Sertão.",
    "sudene", "Superintendência do Desenvolvimento do Nordeste", "SUDENE", "Brasil", "agência de desenvolvimento regional", "governo federal", "https://www.gov.br/sudene/pt-br", "https://pncp.gov.br/app/editais?q=533014&status=todos&pagina=1&tam_pagina=100&tipos=1", "html", "pt", "mensal", "Chamadas PRDNE para desenvolvimento regional, matriz energética limpa e inovação agroindustrial no Nordeste/Sertão.",
    "neh", "National Endowment for the Humanities", "NEH", "Estados Unidos", "agência pública nacional", "governo federal", "https://www.neh.gov/", "https://www.neh.gov/grants", "html", "en", "semanal", "Editais e concessões do National Endowment for the Humanities. Foco em humanidades digitais, infraestrutura de pesquisa, inovação cultural e tecnologia.",
    "bndes", "Banco Nacional de Desenvolvimento Econômico e Social", "BNDES", "Brasil", "banco de desenvolvimento", "banco público", "https://www.bndes.gov.br/", "https://www.bndes.gov.br/wps/portal/site/home/onde-estamos/licitacoes-e-compras/editais", "html", "pt", "semanal", "Chamadas públicas e editais BNDES para inovação industrial, BNDES Garagem, FUST (telecom/IoT), Fundo Clima e BNDES Mais Inovação.",
    "esa_solutions", "ESA Space Solutions - European Space Agency", "ESA Solutions", "Europa", "agência espacial internacional", "organização multilateral", "https://business.esa.int/", "https://business.esa.int/funding", "html", "en", "semanal", "Oportunidades de financiamento direto e chamadas abertas da Agência Espacial Europeia (ESA) para soluções comerciais, satélites, IoT e aplicações terrestres.",
    "nasa_sbir", "NASA Small Business Innovation Research / STTR", "NASA SBIR", "Estados Unidos", "agência espacial", "governo federal", "https://sbir.nasa.gov/", "https://sbir.nasa.gov/solicitations", "html", "en", "mensal", "Financiamento de P&D tecnológico da NASA em automação, robótica, sensores avançados, computação embarcada e aeroespacial.",
    "facepe", "Fundação de Amparo à Ciência e Tecnologia de Pernambuco", "FACEPE", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.facepe.br/", "https://www.facepe.br/editais/", "html", "pt", "semanal", "Editais e chamadas de P&D e inovação da FACEPE, com forte aderência ao ecossistema de TI, automação, IoT e pólos tecnológicos do Nordeste.",
    "funcap", "Fundação Cearense de Apoio ao Desenvolvimento Científico e Tecnológico", "FUNCAP", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.funcap.ce.gov.br/", "https://www.funcap.ce.gov.br/editais/", "html", "pt", "semanal", "Fomento à pesquisa científica, inovação tecnológica, hubs de inteligência artificial e hardware/software no Ceará/Nordeste.",
    "fapeal", "Fundação de Amparo à Pesquisa do Estado de Alagoas", "FAPEAL", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://fapeal.br/", "https://fapeal.br/editais/", "html", "pt", "mensal", "Editais de pesquisa e desenvolvimento tecnológico da FAPEAL para pesquisadores e ICTs regionais.",
    "fapema", "Fundação de Amparo à Pesquisa e ao Desenvolvimento Científico e Tecnológico do Maranhão", "FAPEMA", "Brasil", "fundação estadual de amparo", "fundação pública estadual", "https://www.fapema.br/", "https://www.fapema.br/editais/", "html", "pt", "mensal", "Chamadas e editais da FAPEMA para ciência, tecnologia e inovação no Maranhão e integração Nordeste.",
    "transferegov", "Portal Transferegov.br - Convênios e Programas Federais", "Transferegov", "Brasil", "portal federal de convênios", "governo federal", "https://www.gov.br/transferegov/pt-br", "https://www.gov.br/transferegov/pt-br", "html", "pt", "diária", "Portal unificado de captação e repasse de recursos voluntários da União, descentralização de recursos (TEDs), emendas e programas governamentais para ICTs.",
    "bnb_hubine", "Banco do Nordeste - Hub de Inovação (Hubine)", "Hubine BNB", "Brasil", "hub de inovação bancário", "banco público", "https://www.bnb.gov.br/hubine", "https://www.bnb.gov.br/hubine", "html", "pt", "mensal", "Hub de inovação do BNB para conexão com startups, aceleração, linhas de financiamento de inovação e programas de empreendedorismo do Nordeste.",
    "sebrae", "SEBRAE Inovação & Sebraetec", "SEBRAE", "Brasil", "serviço social autônomo", "sistema s", "https://sebrae.com.br/", "https://sebrae.com.br/sites/PortalSebrae/canais_adicionais/conheca_editais", "html", "pt", "semanal", "Editais de inovação do SEBRAE para MPEs, programas Sebraetec (automação e digitalização), Catalisa ICT e conexões universidade-empresa.",
    "softex", "Associação SOFTEX - Programas Prioritários MCTI", "SOFTEX", "Brasil", "organização social de ti", "associação civil", "https://softex.br/", "https://softex.br/editais/", "html", "pt", "semanal", "Editais e chamadas dos Programas Prioritários da Lei de Informática / MCTI para Inteligência Artificial, Ciência de Dados, IoT e Indústria 4.0."
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
      campos_inferidos_ia TEXT,
      enrichment_status TEXT DEFAULT 'pendente',
      enrichment_model TEXT,
      enrichment_at TEXT,
      enrichment_error TEXT
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


seed_demo_opportunities <- function(conn) {
  existing <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM oportunidades")$n[[1]]
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
  DBI::dbWriteTable(conn, "oportunidades", demo, append = TRUE)
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

cleanup_database_opportunities <- function(conn) {
  # 1. Limpeza por Heurísticas Estáticas (incluindo novos filtros de retificações e Finep)
  res <- tryCatch(
    {
      DBI::dbGetQuery(conn, "SELECT id_registro, titulo, descricao_resumida, link_origem, link_detalhe, texto_bruto FROM oportunidades")
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
          db_exec(conn, "DELETE FROM oportunidades WHERE id_registro = ?", params = list(id))
        },
        error = function(e) NULL
      )
    }
  }

  # 2. Deduplicação Retroativa de Editais com o Mesmo Nome por Entidade
  res_dedupe <- tryCatch(
    {
      DBI::dbGetQuery(conn, "SELECT id_registro, entidade, titulo, status_oportunidade, data_limite, texto_bruto, descricao_resumida FROM oportunidades")
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
            db_exec(conn, "DELETE FROM oportunidades WHERE id_registro = ?", params = list(id))
          },
          error = function(e) NULL
        )
      }
    }
  }

  invisible(TRUE)
}

# Poda o catálogo para as 21 fontes ativas (fontes descontinuadas do catálogo
# ampliado não devem ser coletadas). Idempotente e válida em ambos os backends.
prune_inactive_sources <- function(conn) {
  try(
    db_exec(conn, "DELETE FROM fontes_financiamento WHERE id_fonte NOT IN (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", params = list("cnpq", "capes", "finep", "fapesb", "horizon_europe", "erc", "sigitec", "undp", "embrapii", "daad", "quantum", "humboldt", "grants_gov", "doe_ascr", "nsf_international", "nsf_qise", "nsf_cise", "doe_quantum_genesis", "doe_genesis", "nsf_nqni", "darpa_quantum_benchmarking")),
    silent = TRUE
  )
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
  try(cleanup_database_opportunities(conn), silent = TRUE)
  try(migrate_existing_keywords(conn), silent = TRUE)
  try(migrate_enrichment_columns(conn), silent = TRUE)
  try(migrate_dedup_hashes(conn), silent = TRUE)
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
              warning(sprintf("[upsert] hash colisão ignorada id=%s titulo='%s' hash=%s", row$id_registro %||% "NA", substr(row$titulo %||% "", 1, 60), row$hash_deduplicacao %||% "NA"), call. = FALSE)
            }
          },
          silent = TRUE
        )
        0L
      }
    )
    if (failed) {
      try(DBI::dbExecute(conn, "ROLLBACK TO SAVEPOINT upsert_row"), silent = TRUE)
    }
    try(DBI::dbExecute(conn, "RELEASE SAVEPOINT upsert_row"), silent = TRUE)

    if (affected > 0) inserted <- inserted + 1L
  }

  DBI::dbCommit(conn)
  in_transaction <- FALSE
  invisible(inserted)
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
