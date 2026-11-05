criar_db_legado_tipos <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(conn, "
    CREATE TABLE oportunidades (
      id_registro TEXT PRIMARY KEY,
      tipo_oportunidade TEXT,
      titulo TEXT,
      fonte_oficial TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE migration_flags (
      flag TEXT PRIMARY KEY,
      applied_at TEXT
    )")
  conn
}

inserir_tipo_legado <- function(conn, id, tipo, titulo, fonte) {
  DBI::dbExecute(
    conn,
    "INSERT INTO oportunidades (id_registro, tipo_oportunidade, titulo, fonte_oficial) VALUES (?, ?, ?, ?)",
    params = list(id, tipo, titulo, fonte)
  )
}

test_that("ensure_record_schema inclui as colunas de categoria", {
  schema <- ensure_record_schema(tibble::tibble())
  expect_true(all(c(
    "tipo_oportunidade_original",
    "tipo_oportunidade_categoria",
    "tipo_oportunidade_categoria_origem"
  ) %in% names(schema)))
})

test_that("create_tables cria as colunas de categoria", {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  create_tables(conn)

  cols <- DBI::dbListFields(conn, "oportunidades")
  expect_true(all(c(
    "tipo_oportunidade_original",
    "tipo_oportunidade_categoria",
    "tipo_oportunidade_categoria_origem"
  ) %in% cols))
})

test_that("migrate_tipo_oportunidade adiciona colunas, preserva o bruto e categoriza", {
  conn <- criar_db_legado_tipos()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  inserir_tipo_legado(conn, "1", "Edital", "Edital de Inovação 2026", "cnpq")
  inserir_tipo_legado(conn, "2", "grant", "MSCA COFUND 2026", "horizon_europe")
  inserir_tipo_legado(conn, "3", NA_character_, "MSCA Postdoctoral Fellowships 2026", "horizon_europe")
  inserir_tipo_legado(conn, "4", NA_character_, "Large-Scale Photonic Quantum Computing", "quantum")
  inserir_tipo_legado(conn, "5", "Apoio Institucional", "Prêmio Mulheres Inovadoras - 7ª edição", "finep")
  inserir_tipo_legado(conn, "6", "valor-inexistente", "Edital de Teste", "outra")

  res <- migrate_tipo_oportunidade(conn)
  expect_true(isTRUE(res$applied))
  expect_equal(res$total, 6)

  cols <- DBI::dbListFields(conn, "oportunidades")
  expect_true(all(c(
    "tipo_oportunidade_original",
    "tipo_oportunidade_categoria",
    "tipo_oportunidade_categoria_origem"
  ) %in% cols))

  rows <- DBI::dbGetQuery(
    conn,
    "SELECT id_registro, tipo_oportunidade, tipo_oportunidade_original,
            tipo_oportunidade_categoria, tipo_oportunidade_categoria_origem
       FROM oportunidades ORDER BY id_registro"
  )

  expect_equal(rows$tipo_oportunidade_original, c("Edital", "grant", NA, NA, "Apoio Institucional", "valor-inexistente"))
  expect_equal(
    rows$tipo_oportunidade_categoria,
    c("edital_chamada", "bolsa_fellowship", "bolsa_fellowship", "edital_chamada", "premio", "outros")
  )
  expect_equal(
    rows$tipo_oportunidade_categoria_origem,
    c("bruto", "override", "titulo", "fonte", "override", "outros")
  )

  expect_equal(sum(res$counts$n), 6)
  expect_equal(res$counts$n[res$counts$categoria == "edital_chamada"], 2)
  expect_equal(res$counts$n[res$counts$categoria == "bolsa_fellowship"], 2)
  expect_equal(res$counts$n[res$counts$categoria == "premio"], 1)
  expect_equal(res$counts$n[res$counts$categoria == "outros"], 1)

  marcador <- DBI::dbGetQuery(conn, "SELECT flag FROM migration_flags WHERE flag = 'tipo_oportunidade_v1'")
  expect_equal(nrow(marcador), 1)
})

test_that("migrate_tipo_oportunidade é idempotente", {
  conn <- criar_db_legado_tipos()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  inserir_tipo_legado(conn, "1", "bolsa", "Bolsa de Pesquisa", "cnpq")

  first <- migrate_tipo_oportunidade(conn)
  expect_true(isTRUE(first$applied))
  before <- DBI::dbGetQuery(
    conn,
    "SELECT id_registro, tipo_oportunidade_original, tipo_oportunidade_categoria FROM oportunidades ORDER BY id_registro"
  )

  second <- migrate_tipo_oportunidade(conn)
  expect_false(isTRUE(second$applied))
  after <- DBI::dbGetQuery(
    conn,
    "SELECT id_registro, tipo_oportunidade_original, tipo_oportunidade_categoria FROM oportunidades ORDER BY id_registro"
  )

  expect_equal(after, before)
})

test_that("upsert_opportunities preenche as colunas de categoria", {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  create_tables(conn)

  df <- tibble::tibble(
    id_registro = "upsert_1",
    entidade = "Financiador Teste",
    titulo = "Chamada Pública de Teste",
    tipo_oportunidade = "chamada_publica",
    fonte_oficial = "teste"
  )
  n <- upsert_opportunities(conn, df)
  expect_equal(n, 1L)

  row <- DBI::dbGetQuery(
    conn,
    "SELECT tipo_oportunidade_original, tipo_oportunidade_categoria
       FROM oportunidades WHERE id_registro = 'upsert_1'"
  )
  expect_equal(row$tipo_oportunidade_original, "chamada_publica")
  expect_equal(row$tipo_oportunidade_categoria, "edital_chamada")
})

test_that("apply_structured_filters usa a categoria e aceita valores antigos", {
  df <- tibble::tibble(
    tipo_oportunidade = c("Edital", "bolsa"),
    tipo_oportunidade_categoria = c("edital_chamada", "bolsa_fellowship")
  )

  out_slug <- apply_structured_filters(df, list(tipo = "edital_chamada"))
  expect_equal(nrow(out_slug), 1)
  expect_equal(out_slug$tipo_oportunidade, "Edital")

  out_legado <- apply_structured_filters(df, list(tipo = "Edital"))
  expect_equal(nrow(out_legado), 1)
  expect_equal(out_legado$tipo_oportunidade, "Edital")

  out_outros <- apply_structured_filters(df, list(tipo = "outros"))
  expect_equal(nrow(out_outros), 0)
})
