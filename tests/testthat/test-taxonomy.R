test_that("categorias_tipo_oportunidade retorna as 5 categorias na ordem", {
  cats <- categorias_tipo_oportunidade()

  expect_length(cats, 5)
  expect_equal(
    names(cats),
    c("edital_chamada", "bolsa_fellowship", "premio", "licitacao_contratacao", "outros")
  )
  expect_equal(
    unname(cats),
    c(
      "Editais, Chamadas e Apoio",
      "Bolsas e Fellowships",
      "Prêmios",
      "Licitações e Contratações",
      "Outros"
    )
  )
})

test_that("categorias_tipo_oportunidade_choices usa labels como nome e slugs como valor", {
  choices <- categorias_tipo_oportunidade_choices()

  expect_equal(
    names(choices),
    c(
      "Editais, Chamadas e Apoio",
      "Bolsas e Fellowships",
      "Prêmios",
      "Licitações e Contratações",
      "Outros"
    )
  )
  expect_equal(
    unname(choices),
    c("edital_chamada", "bolsa_fellowship", "premio", "licitacao_contratacao", "outros")
  )
})

test_that("categorizar_tipo_oportunidade normaliza variantes de escrita", {
  expect_equal(categorizar_tipo_oportunidade("edital"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("Edital"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("chamada"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("chamada pública"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("chamada_publica"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("chamada publica"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("grant"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("Edital (grant opportunity)"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("Edital de fomento para pesquisa em supercondutores"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("Não reembolsável"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("Apoio Institucional"), "edital_chamada")
  expect_equal(categorizar_tipo_oportunidade("subvenção"), "edital_chamada")

  expect_equal(categorizar_tipo_oportunidade("bolsa"), "bolsa_fellowship")
  expect_equal(categorizar_tipo_oportunidade("bolsa_estudo"), "bolsa_fellowship")
  expect_equal(categorizar_tipo_oportunidade("bolsa_pesquisa"), "bolsa_fellowship")
  expect_equal(categorizar_tipo_oportunidade("fellowship"), "bolsa_fellowship")
  expect_equal(categorizar_tipo_oportunidade("scholarship"), "bolsa_fellowship")

  expect_equal(categorizar_tipo_oportunidade("premio"), "premio")
  expect_equal(categorizar_tipo_oportunidade("prêmio"), "premio")
  expect_equal(categorizar_tipo_oportunidade("award"), "premio")
  expect_equal(categorizar_tipo_oportunidade("prize"), "premio")

  expect_equal(categorizar_tipo_oportunidade("licitacao"), "licitacao_contratacao")
  expect_equal(categorizar_tipo_oportunidade("licitação"), "licitacao_contratacao")
  expect_equal(categorizar_tipo_oportunidade("consultoria"), "licitacao_contratacao")
  expect_equal(categorizar_tipo_oportunidade("contratação"), "licitacao_contratacao")

  expect_equal(categorizar_tipo_oportunidade("oportunidade"), "outros")
  expect_equal(categorizar_tipo_oportunidade("Guia de notificações / Sistema de comunicação"), "outros")
  expect_equal(categorizar_tipo_oportunidade("valor-inexistente"), "outros")
  expect_equal(categorizar_tipo_oportunidade(NA_character_), "outros")
  expect_equal(categorizar_tipo_oportunidade(NULL), "outros")
  expect_equal(categorizar_tipo_oportunidade("   "), "outros")
})

test_that("categorizar_tipo_oportunidade infere nulos por título e fonte", {
  expect_equal(
    categorizar_tipo_oportunidade(NA_character_, "MSCA Postdoctoral Fellowships 2026", "horizon_europe"),
    "bolsa_fellowship"
  )
  expect_equal(
    categorizar_tipo_oportunidade(NULL, "MSCA-COFUND 2027", "horizon_europe"),
    "bolsa_fellowship"
  )
  expect_equal(
    categorizar_tipo_oportunidade(NA_character_, "The European Prize for Women Innovators", "horizon_europe"),
    "premio"
  )
  expect_equal(
    categorizar_tipo_oportunidade(NA_character_, "Large-Scale Photonic Quantum Computing Platform Technologies", "quantum"),
    "edital_chamada"
  )
  expect_equal(
    categorizar_tipo_oportunidade(NA_character_, "FIP Conexões Startups 2026", "finep"),
    "outros"
  )
  expect_equal(
    categorizar_tipo_oportunidade(NA_character_, "Subscribe", "doe_genesis"),
    "outros"
  )
})

test_that("categorizar_tipo_oportunidade aplica overrides pontuais", {
  expect_equal(
    categorizar_tipo_oportunidade("Apoio Institucional", "Prêmio Mulheres Inovadoras - 7ª edição - 2026", "finep"),
    "premio"
  )
  expect_equal(
    categorizar_tipo_oportunidade("grant", "MSCA COFUND 2026", "horizon_europe"),
    "bolsa_fellowship"
  )
})

test_that("mapear_tipos_para_categorias aceita valores antigos e slugs", {
  expect_equal(
    mapear_tipos_para_categorias(c("Edital", "bolsa", "outros")),
    c("edital_chamada", "bolsa_fellowship", "outros")
  )
  expect_equal(mapear_tipos_para_categorias(character()), character())
  expect_equal(mapear_tipos_para_categorias(NULL), character())
})

test_that("mapear_tipos_para_categorias é idempotente para todos os slugs", {
  slugs <- names(categorias_tipo_oportunidade())
  expect_equal(mapear_tipos_para_categorias(slugs), slugs)
  expect_equal(categorizar_tipo_oportunidade("outros", "Edital de Teste", "cnpq"), "outros")
})

test_that("rotulo_categoria_tipo retorna label e fallback", {
  expect_equal(rotulo_categoria_tipo("edital_chamada"), "Editais, Chamadas e Apoio")
  expect_equal(rotulo_categoria_tipo("desconhecida"), "desconhecida")
  expect_equal(rotulo_categoria_tipo(NA_character_), "Outros")
})
