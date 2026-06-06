filepath <- "C:/Users/Micro/.gemini/antigravity-ide/brain/f3dae400-0e4b-49de-b132-50251431e9b6/.system_generated/steps/2647/content.md"
if (file.exists(filepath)) {
  txt <- readLines(filepath, warn = FALSE)
  txt_comb <- paste(txt, collapse = "\n")
  
  idx <- gregexpr("getOportunities", txt_comb, fixed = TRUE)[[1]]
  if (idx[1] != -1) {
    for (pos in idx) {
      start <- max(1, pos - 150)
      end <- min(nchar(txt_comb), pos + 250)
      cat("Context of getOportunities:", substr(txt_comb, start, end), "\n\n")
    }
  }
}
