local_libs <- 'c:/Users/Micro/source/repos/funding_intelligence/R_libs'
.libPaths(c(local_libs, .libPaths()))
library(rvest)

url <- "https://fapesp.br/oportunidades/"
html <- read_html(url)

# Find elements containing "Bolsa de PD em Educação"
nodes <- html_elements(html, "*")
texts <- html_text(nodes, trim = TRUE)
matches <- grep("Bolsa de PD em Educação", texts, fixed = TRUE)

cat("Found matches in nodes:\n")
for (m in head(matches, 10)) {
  node <- nodes[[m]]
  tag <- html_name(node)
  class <- html_attr(node, "class")
  id <- html_attr(node, "id")
  cat(sprintf("Tag: %s, Class: %s, ID: %s, Text length: %d\n", tag, class %||% "NA", id %||% "NA", nchar(texts[[m]])))
  
  # Print the outer HTML of the node if it's small (e.g. tag is div, li, p, span, a)
  if (tag %in% c("div", "li", "p", "span", "a", "tr", "td") && nchar(texts[[m]]) < 500) {
    cat(as.character(node), "\n---\n")
  }
}
