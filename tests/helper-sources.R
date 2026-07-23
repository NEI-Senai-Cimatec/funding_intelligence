# Source all R helper files so functions are available in tests
# (project has no DESCRIPTION/NAMESPACE, so devtools::load_all won't work)
# testthat tests run with getwd() = project root
r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
for (f in r_files) {
  tryCatch(source(f, local = parent.env(environment()), encoding = "UTF-8"),
           error = function(e) NULL)
}
