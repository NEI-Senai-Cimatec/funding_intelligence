local_libs <- 'c:/Users/Micro/source/repos/funding_intelligence/R_libs'
.libPaths(c(local_libs, .libPaths()))
source("R/helpers_utils.R")
source("R/helpers_collect.R")

url <- "https://fapesp.br/oportunidades/"
pg <- safe_request_page(url)
if (!pg$ok || is.null(pg$html)) {
  stop("Failed to fetch FAPESP page")
}

cat("Page status: OK\n")
# Check listing candidates
candidates <- extract_listing_candidates(pg$html, url, source_catalog() |> dplyr::filter(id_fonte == "fapesp"))
cat(sprintf("Found %d candidates\n", nrow(candidates)))

if (nrow(candidates) > 0) {
  print(head(as.data.frame(candidates[, c("title", "detail_url", "pdf_url")]), 15))
}
