# Source all R helper files so functions are available in tests
# (project has no DESCRIPTION/NAMESPACE, so devtools::load_all won't work)
# CORREÇÕES:
# 1. Sourcing em globalenv(): corpos de test_that() são avaliados em um env cuja
#    cadeia termina em R_GlobalEnv e NÃO passa pelo env de sourcing do arquivo;
#    em globalenv() os helpers ficam visíveis em todos os testes.
#    (Antes: parent.env(environment()) apontava para um env travado — ex.
#    package:stats — e todo sourcing falhava silenciosamente no tryCatch.)
# 2. testthat 3e roda os testes com cwd = tests/testthat, portanto a raiz do
#    projeto é localizada subindo diretórios até encontrar app.R.
# 3. O gêmeo deste arquivo em tests/testthat/ chama-se helper-load-helpers.R,
#    pois testthat 3.3.2 ignora silenciosamente helpers com o nome
#    "helper-sources.R" na pasta de testes.
project_root <- getwd()
for (i in 1:4) {
  if (file.exists(file.path(project_root, "app.R"))) break
  project_root <- dirname(project_root)
}
r_files <- list.files(file.path(project_root, "R"), pattern = "\\.R$", full.names = TRUE)
for (f in r_files) {
  tryCatch(source(f, local = globalenv(), encoding = "UTF-8"),
           error = function(e) message(sprintf("helper-sources: falha ao carregar %s: %s", f, conditionMessage(e)))
  )
}
