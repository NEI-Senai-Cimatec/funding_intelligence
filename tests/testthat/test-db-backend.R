test_that("sql_placeholders_to_postgres converte apenas ? fora de strings", {
  expect_equal(
    sql_placeholders_to_postgres("SELECT ? AS a, '?' AS b, ? AS c"),
    "SELECT $1 AS a, '?' AS b, $2 AS c"
  )
  expect_equal(sql_placeholders_to_postgres("SELECT 1"), "SELECT 1")
  expect_equal(sql_placeholders_to_postgres("SELECT 'a?b'"), "SELECT 'a?b'")
})

test_that("db_backend_name distingue Postgres de SQLite", {
  expect_equal(db_backend_name("PostgreSQL 18.0"), "postgres")
  expect_equal(db_backend_name("SQLite"), "sqlite")
  expect_equal(db_backend_name(NA_character_), "sqlite")
})

test_that("using_postgres usa DATA_BASE_URL e o legado DATABASE_URL", {
  old_data <- Sys.getenv("DATA_BASE_URL", unset = NA_character_)
  old_db <- Sys.getenv("DATABASE_URL", unset = NA_character_)
  on.exit({
    if (is.na(old_data)) Sys.unsetenv("DATA_BASE_URL") else Sys.setenv(DATA_BASE_URL = old_data)
    if (is.na(old_db)) Sys.unsetenv("DATABASE_URL") else Sys.setenv(DATABASE_URL = old_db)
  }, add = TRUE)

  Sys.unsetenv(c("DATA_BASE_URL", "DATABASE_URL"))
  expect_false(using_postgres())

  Sys.setenv(DATABASE_URL = "postgresql://user:pass@example.com/db")
  expect_true(using_postgres())

  Sys.unsetenv("DATABASE_URL")
  Sys.setenv(DATA_BASE_URL = "postgresql://user:pass@example.com/db")
  expect_true(using_postgres())
})

test_that("get_db_connection(':memory:') ignora DATA_BASE_URL e usa SQLite", {
  old_data <- Sys.getenv("DATA_BASE_URL", unset = NA_character_)
  on.exit({
    if (is.na(old_data)) Sys.unsetenv("DATA_BASE_URL") else Sys.setenv(DATA_BASE_URL = old_data)
  }, add = TRUE)
  Sys.setenv(DATA_BASE_URL = "postgresql://invalid:invalid@127.0.0.1:1/invalid")

  conn <- get_db_connection(":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  expect_equal(db_backend(conn), "sqlite")
})

test_that("postgres_schema_statements é compatível com Postgres", {
  sql <- postgres_schema_statements()

  expect_true(length(sql) > 0)
  expect_true(any(grepl("BIGSERIAL", sql)))
  expect_false(any(grepl("AUTOINCREMENT", sql, ignore.case = TRUE)))
  expect_true(any(grepl("tipo_oportunidade_categoria", sql)))
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS oportunidades", sql)))
})
