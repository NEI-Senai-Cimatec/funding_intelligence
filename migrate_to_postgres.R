#!/usr/bin/env Rscript
# ==============================================================================
# Script de Migração: SQLite -> PostgreSQL
# ==============================================================================
# 
# Este script migra o banco de dados SQLite local para PostgreSQL.
# 
# Uso:
#   Rscript migrate_to_postgres.R
#
# Variáveis de ambiente necessárias:
#   DATABASE_URL  - URL de conexão PostgreSQL (formato: postgresql://user:pass@host:port/db)
#   
#   OU formato individual:
#   DB_HOST       - Host do PostgreSQL
#   DB_PORT       - Porta (padrão: 5432)
#   DB_NAME       - Nome do banco
#   DB_USER       - Usuário
#   DB_PASSWORD   - Senha
#
# Exemplos:
#   
#   # Supabase
#   export DATABASE_URL="postgresql://postgres:SENHA@xxxxx.supabase.co:5432/postgres"
#   
#   # Neon
#   export DATABASE_URL="postgresql://neondb_owner:SENHA@ep-xxx.us-east-1.aws.neon.tech/neondb?sslmode=require"
#
# ==============================================================================

# Carrega helpers
source("R/helpers_utils.R")
source("R/helpers_db_postgres.R")

# Verifica se RPostgres está instalado
if (!requireNamespace("RPostgres", quietly = TRUE)) {
  message("Erro: Pacote RPostgres não encontrado.")
  message("Instale com: install.packages('RPostgres')")
  stop("RPostgres não disponível")
}

if (!requireNamespace("RSQLite", quietly = TRUE)) {
  message("Erro: Pacote RSQLite não encontrado.")
  message("Instale com: install.packages('RSQLite')")
  stop("RSQLite não disponível")
}

# Verifica variáveis de ambiente
database_url <- Sys.getenv("DATABASE_URL")
db_host <- Sys.getenv("DB_HOST")

if (!nzchar(database_url) && !nzchar(db_host)) {
  message("Erro: Variáveis de ambiente não configuradas.")
  message("")
  message("Configure DATABASE_URL ou DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD")
  message("")
  message("Exemplo Supabase:")
  message('  export DATABASE_URL="postgresql://postgres:SENHA@xxxxx.supabase.co:5432/postgres"')
  message("")
  message("Exemplo Neon:")
  message('  export DATABASE_URL="postgresql://neondb_owner:SENHA@ep-xxx.us-east-1.aws.neon.tech/neondb?sslmode=require"')
  stop("Variáveis de ambiente não configuradas")
}

# Verifica se existe SQLite local
sqlite_path <- "funding_intelligence.sqlite"
if (!file.exists(sqlite_path)) {
  message(sprintf("Arquivo SQLite não encontrado: %s", sqlite_path))
  message("Criando tabelas vazias no PostgreSQL...")
  
  # Conecta ao PostgreSQL
  pg_conn <- get_db_connection()
  on.exit(DBI::dbDisconnect(pg_conn))
  
  # Cria tabelas
  create_tables(pg_conn)
  
  # Roda seeds
  seed_sources(pg_conn)
  seed_profile(pg_conn)
  seed_saved_searches(pg_conn)
  seed_search_history(pg_conn)
  seed_collaborators(pg_conn)
  seed_pesquisadores_vencedores(pg_conn)
  seed_projetos_aprovados(pg_conn)
  
  message("Tabelas criadas com sucesso no PostgreSQL!")
  message("Execute novamente este script após popular o banco via aplicação.")
  invisible(TRUE)
}

# Conecta ao PostgreSQL
message("Conectando ao PostgreSQL...")
pg_conn <- tryCatch(
  get_db_connection(),
  error = function(e) {
    message(sprintf("Erro ao conectar ao PostgreSQL: %s", e$message))
    stop("Falha na conexão com PostgreSQL")
  }
)
on.exit({
  if (DBI::dbIsValid(pg_conn)) DBI::dbDisconnect(pg_conn)
}, add = TRUE)

message("Conexão estabelecida com sucesso!")

# Cria tabelas no PostgreSQL
message("Criando tabelas no PostgreSQL...")
create_tables(pg_conn)
message("Tabelas criadas!")

# Migra dados do SQLite
message(sprintf("Migrando dados de: %s", sqlite_path))
migrate_sqlite_to_postgres(sqlite_path, pg_conn)

# Verifica migração
message("")
message("=== Verificação da Migração ===")
tabelas <- c(
  "fontes_financiamento", "oportunidades", "buscas_salvas",
  "editais_rastreados", "perfil_usuario", "historico_buscas",
  "colaboradores", "logs_coleta", "pesquisadores_vencedores",
  "projetos_aprovados", "metrics_coleta"
)

for (tabela in tabelas) {
  tryCatch({
    count <- DBI::dbGetQuery(pg_conn, sprintf("SELECT COUNT(*) as n FROM %s", tabela))$n[[1]]
    message(sprintf("  %-25s: %d registros", tabela, count))
  }, error = function(e) {
    message(sprintf("  %-25s: ERRO - %s", tabela, e$message))
  })
}

message("")
message("=== Migração Concluída ===")
message("")
message("Próximos passos:")
message("1. Configure as variáveis de ambiente no Posit Connect:")
message("   DATABASE_URL=postgresql://...")
message("")
message("2. Atualize o manifest:")
message('   rsconnect::writeManifest()')
message("")
message("3. Publique no Posit Connect:")
message('   rsconnect::deployApp()')
message("")
message("Ou para Docker:")
message("   docker-compose up -d")
