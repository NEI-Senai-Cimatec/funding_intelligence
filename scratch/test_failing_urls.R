library(httr2)

urls <- list(
  acoes_programas = "https://www.gov.br/saude/pt-br/acesso-a-informacao/acoes-e-programas",
  embrapii = "https://embrapii.org.br/chamadas-publicas/",
  fapesb = "https://www.fapesb.ba.gov.br/editais"
)

test_url <- function(name, url) {
  message(sprintf("Testing %s: %s", name, url))
  
  req <- httr2::request(url) |>
    httr2::req_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") |>
    httr2::req_headers(
      `Accept-Language` = "pt-BR,pt;q=0.9,en;q=0.8",
      `Accept` = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
    ) |>
    httr2::req_timeout(10)
  
  resp <- try(httr2::req_perform(req), silent = TRUE)
  
  if (inherits(resp, "try-error")) {
    message(sprintf("  -> ERROR: %s", conditionMessage(attr(resp, "condition"))))
    return(FALSE)
  }
  
  status <- httr2::resp_status(resp)
  txt <- try(httr2::resp_body_string(resp), silent = TRUE)
  
  if (inherits(txt, "try-error")) {
    message(sprintf("  -> Success with status %d but body string extraction failed", status))
    return(FALSE)
  }
  
  has_block <- grepl("attention required! \\| cloudflare|cf-challenge|ray id:|checking your browser before accessing|security challenge|access denied", tolower(txt))
  
  message(sprintf("  -> Status: %d | Length: %d | CDN Block: %s", status, nchar(txt), has_block))
  return(status == 200 && !has_block)
}

for (n in names(urls)) {
  test_url(n, urls[[n]])
}
