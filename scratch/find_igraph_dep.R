# Script to find which packages import or depend on igraph
local_lib <- "C:/Users/Micro/AppData/Local/R/win-library/4.6"
sys_lib <- "C:/Program Files/R/R-4.6.0/library"

libs <- c(local_lib, sys_lib)

find_dep <- function() {
  results <- list()
  for (lib in libs) {
    if (!dir.exists(lib)) next
    pkgs <- list.dirs(lib, full.names = FALSE, recursive = FALSE)
    for (pkg in pkgs) {
      desc_file <- file.path(lib, pkg, "DESCRIPTION")
      if (file.exists(desc_file)) {
        lines <- readLines(desc_file, warn = FALSE)
        content <- paste(lines, collapse = "\n")
        if (grepl("igraph", content, ignore.case = TRUE)) {
          # Extract Imports/Depends section
          results[[pkg]] <- list(lib = lib, pkg = pkg)
        }
      }
    }
  }
  return(results)
}

deps <- find_dep()
print(deps)
