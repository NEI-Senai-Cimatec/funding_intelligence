local_libs <- 'c:/Users/Micro/source/repos/funding_intelligence/R_libs'
.libPaths(c(local_libs, .libPaths()))
library(rvest)

url <- "https://fapesp.br/oportunidades/"
html <- read_html(url)

# Run block matching
block_sel <- paste(
  c(
    "article", ".card", ".cards-item", ".views-row", ".view-content .views-row", ".resultado",
    ".result", ".results-item", ".entry", ".post", ".item", ".media", ".tile", ".callout",
    ".news-item", ".list-item", ".node", ".content-item", "li", "tr", "section"
  ),
  collapse = ", "
)
blocks <- html_elements(html, block_sel)

for (i in seq_along(blocks)) {
  node <- blocks[[i]]
  raw_txt <- html_text(node, trim = TRUE)
  if (grepl("Bolsa de PD em Educação", raw_txt, fixed = TRUE) && nchar(raw_txt) < 1000) {
    cat(sprintf("=== Block %d ===\n", i))
    cat("Tag:", html_name(node), "\n")
    cat("Class:", html_attr(node, "class"), "\n")
    
    anchors <- html_elements(node, "a[href]")
    hrefs <- html_attr(anchors, "href")
    abs_urls <- vapply(hrefs, function(h) xml2::url_absolute(h, url), character(1))
    
    cat("Hrefs found:\n")
    print(hrefs)
    cat("Abs URLs found:\n")
    print(abs_urls)
    
    pdf_idx <- grepl("\\.pdf($|\\?)", abs_urls, ignore.case = TRUE)
    detail_idx <- !pdf_idx & !is.na(abs_urls) & nzchar(abs_urls)
    detail_urls <- unique(abs_urls[detail_idx])
    
    cat("Detail URLs:\n")
    print(detail_urls)
    cat("Pick first non-empty detail URL:\n")
    print(detail_urls[1])
  }
}
