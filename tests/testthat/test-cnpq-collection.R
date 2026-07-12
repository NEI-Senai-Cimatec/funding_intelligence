test_that("extract_listing_candidates prefers heading links over share links", {
  html <- xml2::read_html('
    <html><body>
      <div class="item visualIEFloatFix">
        <h2 class="headline">
          <a class="summary url" href="https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-25">Chamada CNPq 25/2026</a>
        </h2>
        <div class="social-links">
          <a href="https://www.facebook.com/sharer/sharer.php?u=https://example.com">Facebook</a>
          <a href="https://twitter.com/intent/tweet?url=https://example.com">Twitter</a>
        </div>
        <div id="parent-fieldname-text">
          <p>INSCRICOES: 10/07/2026 a 12/08/2026</p>
        </div>
      </div>
    </body></html>
  ')
  source_row <- tibble::tibble(
    id_fonte = "cnpq",
    sigla = "CNPq",
    url_oportunidades = "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas"
  )
  result <- extract_listing_candidates(html, "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas", source_row)
  expect_true(nrow(result) > 0)
  expect_true(grepl("chamada-25", result$detail_url[[1]], fixed = TRUE))
  expect_false(grepl("facebook", result$detail_url[[1]], fixed = TRUE))
  expect_true(grepl("Chamada CNPq 25", result$title[[1]], fixed = TRUE))
})

test_that("extract_listing_candidates extracts from article.contenttype-document blocks", {
  html <- xml2::read_html('
    <html><body>
      <article class="contenttype-document no-image">
        <div class="tileContent">
          <h2 class="tileHeadline">
            <a class="state-published" href="https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-no-14-2026/chamada-publica-cnpq-N-14-2026">
              7a Chamada publica MCTI/CNPq/BRICS-STI No 14/2026
            </a>
          </h2>
          <div class="keywords">
            <span><a class="link-category" rel="tag">#chamadas</a></span>
            <span><a class="link-category" rel="tag">#abertas</a></span>
          </div>
        </div>
      </article>
    </body></html>
  ')
  source_row <- tibble::tibble(
    id_fonte = "cnpq",
    sigla = "CNPq",
    url_oportunidades = "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas"
  )
  result <- extract_listing_candidates(html, "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas", source_row)
  expect_true(nrow(result) > 0)
  expect_true(grepl("chamada-no-14-2026", result$detail_url[[1]], fixed = TRUE))
  expect_true(grepl("BRICS-STI", result$title[[1]], fixed = TRUE))
})

test_that("is_plone_search_url detects external search interfaces but not same-page offsets", {
  # External search pages
  expect_true(is_plone_search_url("https://example.com/@@search?Text=foo"))
  expect_true(is_plone_search_url("https://example.com/path/search?q=test"))
  expect_true(is_plone_search_url("https://www.gov.br/cnpq/pt-br/@@search?Text=chamada"))

  # Same-page pagination (Busca_abertas with b_start:int) is NOT a different search page
  expect_false(is_plone_search_url(
    "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas?b_start:int=5",
    current_url = "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas"
  ))

  # Different page entirely
  expect_false(is_plone_search_url("https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao"))
  expect_false(is_plone_search_url(NA_character_))
  expect_false(is_plone_search_url(""))

  # Without current_url context, Busca_abertas is still allowed (could be a different search)
  expect_false(is_plone_search_url("https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas"))
})

test_that("extract_inscricoes_dates parses submission date ranges", {
  text1 <- "INSCRICOES: 10/07/2026 a 12/08/2026"
  result1 <- extract_inscricoes_dates(text1)
  expect_equal(result1$data_abertura, "2026-07-10")
  expect_equal(result1$data_limite, "2026-08-12")

  text2 <- "INSCRICÕES: 01/03/2025 a 30/04/2025"
  result2 <- extract_inscricoes_dates(text2)
  expect_equal(result2$data_abertura, "2025-03-01")
  expect_equal(result2$data_limite, "2025-04-30")

  text3 <- "No dates here"
  result3 <- extract_inscricoes_dates(text3)
  expect_true(is.na(result3$data_abertura))
  expect_true(is.na(result3$data_limite))
})

test_that("collect_cnpq is registered as custom collector not generic alias", {
  source_row <- tibble::tibble(
    id_fonte = "cnpq",
    sigla = "CNPq",
    url_oportunidades = "https://www.gov.br/cnpq/pt-br/chamadas/abertas-para-submissao",
    pais = "Brasil",
    nome_fonte = "Conselho Nacional de Desenvolvimento Cientifico e Tecnologico"
  )
  collector <- get_collector("cnpq")
  expect_false(identical(collector$fn, collect_generic_official))
  expect_true(is.function(collector$fn))
})

test_that("extract_listing_candidates filters social share links from detail_url", {
  html <- xml2::read_html('
    <html><body>
      <div class="item visualIEFloatFix">
        <h2 class="headline">
          <a class="summary url" href="https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-no-07-2026/chamada-publica-cnpq-N-07-2026">Chamada Publica CNPq No 07/2026 - PIBPG</a>
        </h2>
        <div class="social-links">
          <a href="http://www.facebook.com/sharer.php?u=https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-no-07-2026/chamada-publica-cnpq-N-07-2026">Facebook</a>
          <a href="https://twitter.com/share?text=Chamada">Twitter</a>
          <a href="https://www.linkedin.com/shareArticle?mini=true">LinkedIn</a>
          <a href="https://api.whatsapp.com/send?text=https://example.com">WhatsApp</a>
        </div>
        <div id="parent-fieldname-text">
          <div>O CNPq torna publica a Chamada Publica CNPq No 07/2026.</div>
          <ul>
            <li><a href="https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-no-07-2026/Chamada072026.pdf">Chamada</a></li>
            <li><a href="https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-no-07-2026/AnexoI.pdf">Anexo I</a> INSCRICÕES: 15/06/2026 a 30/07/2026</li>
          </ul>
        </div>
      </div>
    </body></html>
  ')
  source_row <- tibble::tibble(
    id_fonte = "cnpq",
    sigla = "CNPq",
    url_oportunidades = "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas"
  )
  result <- extract_listing_candidates(html, "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas", source_row)
  expect_true(nrow(result) > 0)

  # The detail_url should be the actual chamada page, not a social share link
  detail_urls <- result$detail_url[!is.na(result$detail_url)]
  expect_false(any(grepl("facebook|twitter|linkedin|whatsapp", detail_urls, ignore.case = TRUE)))
  expect_true(any(grepl("chamada-no-07-2026", detail_urls, fixed = TRUE)))
})

test_that("extract_listing_candidates handles Busca_abertas article pagination links", {
  html <- xml2::read_html('
    <html><body>
      <article class="contenttype-document no-image">
        <div class="tileContent">
          <h2 class="tileHeadline">
            <a class="state-published" href="https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-no-06-2026/chamada-publica-cnpq-N-06-2026">Chamada CNPq/FNDCT No 06/2026 - UNIVERSAL</a>
          </h2>
          <div class="keywords">
            <span><a class="link-category" rel="tag">#chamadas</a></span>
            <span><a class="link-category" rel="tag">#abertas</a></span>
          </div>
        </div>
      </article>
      <article class="contenttype-document no-image">
        <div class="tileContent">
          <h2 class="tileHeadline">
            <a class="state-published" href="https://www.gov.br/cnpq/pt-br/chamadas/todas-as-chamadas/chamadas-2026/chamada-no-16-2026/chamada-publica-cnpq-N-16-2026">Chamada Publica CNPq/CAPES/MRE No 16/2026 - PEC-PG</a>
          </h2>
        </div>
      </article>
      <ul class="paginacao listingBar">
        <li><a class="proximo" href="https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas?b_start:int=5">Proximo</a></li>
      </ul>
    </body></html>
  ')
  source_row <- tibble::tibble(
    id_fonte = "cnpq",
    sigla = "CNPq",
    url_oportunidades = "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas"
  )
  result <- extract_listing_candidates(html, "https://www.gov.br/cnpq/pt-br/chamadas/Busca_abertas", source_row)
  expect_true(nrow(result) >= 2)

  detail_urls <- result$detail_url[!is.na(result$detail_url)]
  expect_true(any(grepl("chamada-no-06-2026", detail_urls, fixed = TRUE)))
  expect_true(any(grepl("chamada-no-16-2026", detail_urls, fixed = TRUE)))

  # Pagination links should NOT be in the candidates
  expect_false(any(grepl("b_start:int", detail_urls, fixed = TRUE)))
})
