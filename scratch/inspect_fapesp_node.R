local_libs <- 'c:/Users/Micro/source/repos/funding_intelligence/R_libs'
.libPaths(c(local_libs, .libPaths()))
library(rvest)

url <- "https://fapesp.br/oportunidades/"
html <- read_html(url)

# Find li node containing "Bolsa de PD em Educação"
lis <- html_elements(html, "li")
texts <- html_text(lis, trim = TRUE)
idx <- grep("Bolsa de PD em Educação", texts, fixed = TRUE)

if (length(idx) > 0) {
  cat("=== LI NODE HTML ===\n")
  cat(as.character(lis[[idx[1]]]), "\n")
} else {
  cat("No matching li node found\n")
}
