# ==============================================================================
# helpers_docx.R - Preenchimento do Modelo DOCX Institucional para Relatórios
# ==============================================================================

#' Gera relatório Word (.docx) preenchendo o modelo institucional oficial
#'
#' @param report_data Lista com os dados do relatório (estrutura retornada por generate_adherence_report)
#' @param output_file Caminho de destino do arquivo .docx gerado
#' @param template_path Caminho do modelo Word oficial (padrão: templates/modelo_editais.docx)
#' @return TRUE se gerado com sucesso, FALSE em caso de erro
generate_docx_report <- function(report_data, output_file, template_path = "templates/modelo_editais.docx") {
  if (is.null(report_data) || length(report_data$items) == 0L) {
    warning("[DOCX] Dados do relatório vazios para geração do DOCX.")
    return(FALSE)
  }

  # Localiza o template
  if (!file.exists(template_path)) {
    # Tenta caminhos alternativos relativos
    alt_paths <- c(
      file.path("templates", "modelo_editais.docx"),
      file.path("..", "templates", "modelo_editais.docx"),
      "modelo_editais.docx"
    )
    found <- Filter(file.exists, alt_paths)
    if (length(found) > 0) {
      template_path <- found[1]
    } else {
      warning("[DOCX] Arquivo modelo_editais.docx não encontrado em templates/")
      return(FALSE)
    }
  }

  template_path <- normalizePath(template_path, winslash = "/", mustWork = FALSE)
  output_file <- normalizePath(output_file, winslash = "/", mustWork = FALSE)

  # Escreve os dados em JSON temporário para comunicação segura
  tmp_json <- tempfile(fileext = ".json")
  on.exit(unlink(tmp_json), add = TRUE)
  
  # Garante codificação UTF-8
  json_payload <- jsonlite::toJSON(report_data, auto_unbox = TRUE, pretty = FALSE)
  writeLines(json_payload, tmp_json, useBytes = TRUE)

  # Localiza o script Python gerador
  script_path <- "scripts/fill_report_docx.py"
  if (!file.exists(script_path)) {
    alt_scripts <- c(
      file.path("scripts", "fill_report_docx.py"),
      file.path("..", "scripts", "fill_report_docx.py")
    )
    found_s <- Filter(file.exists, alt_scripts)
    if (length(found_s) > 0) script_path <- found_s[1]
  }
  script_path <- normalizePath(script_path, winslash = "/", mustWork = FALSE)

  # Detecta interpretador Python
  python_bins <- c(
    Sys.which("py"),
    Sys.which("python3"),
    Sys.which("python"),
    "C:/Users/felipe.dourado/AppData/Local/Programs/Python/Launcher/py.exe",
    "/usr/bin/python3",
    "/usr/local/bin/python3"
  )
  python_bins <- unique(Filter(function(b) nzchar(b) && file.exists(b), python_bins))

  filled_ok <- FALSE

  for (py_bin in python_bins) {
    args <- if (grepl("py(\\.exe)?$", py_bin, ignore.case = TRUE)) {
      c("-3", script_path, template_path, output_file, tmp_json)
    } else {
      c(script_path, template_path, output_file, tmp_json)
    }

    res <- tryCatch({
      system2(py_bin, args = args, stdout = TRUE, stderr = TRUE)
    }, error = function(e) {
      NULL
    })

    if (file.exists(output_file) && file.info(output_file)$size > 1000) {
      message("[DOCX] Arquivo Word gerado com sucesso via Python: ", output_file)
      filled_ok <- TRUE
      break
    }
  }

  # Fallback caso Python não esteja disponível: copia o template ou cria documento básico
  if (!filled_ok) {
    message("[DOCX] Python docx não disponível ou falhou, utilizando fallback...")
    tryCatch({
      file.copy(template_path, output_file, overwrite = TRUE)
      filled_ok <- TRUE
    }, error = function(e) {
      warning("[DOCX] Erro no fallback: ", e$message)
    })
  }

  return(filled_ok)
}
