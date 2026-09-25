# Test stealth collection pipeline for all 8 target sources
helper_files <- list.files("R", pattern = "^helpers_.*\\.R$", full.names = TRUE)
for (f in helper_files) source(f, encoding = "UTF-8")

sources <- c("fab_dcta", "embrapa", "bnb_fundeci", "codevasf", "aeb", "sudene", "finep_aero", "doe_ascr")

cat("\n=======================================================\n")
cat("TESTING STEALTH COLLECTION FOR ALL 8 SOURCES\n")
cat("=======================================================\n")

for (s in sources) {
  cat("\n-------------------------------------------------------\n")
  cat("Running collector for source_id:", s, "\n")
  
  s_row <- tibble::tibble(
    id_fonte = s,
    url_oportunidades = list(NULL)
  )
  
  res <- source_dispatch(s_row, max_pages = 1, max_records = 5)
  cat("Success:", is.null(res$error), "\n")
  if (!is.null(res$error)) {
    cat("Error message:", res$error, "\n")
  }
  
  recs <- res$records
  if (!is.null(recs) && nrow(recs) > 0) {
    cat("Total records collected:", nrow(recs), "\n")
    for (i in seq_len(min(3, nrow(recs)))) {
      cat(sprintf("   [%d] Title: %s\n       Link: %s\n", i, recs$titulo[i], recs$link_detalhe[i]))
    }
  } else {
    cat("No records returned.\n")
  }
}
