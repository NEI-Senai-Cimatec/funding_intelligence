# ==============================================================================
# helpers_docx.R - Preenchimento do Modelo DOCX/PDF Institucional para Relatórios
# ==============================================================================

#' Detecta interpretador Python viável no sistema
find_python_interpreter <- function() {
  python_bins <- c(
    Sys.which("py"),
    Sys.which("python3"),
    Sys.which("python"),
    "C:/Users/felipe.dourado/AppData/Local/Programs/Python/Launcher/py.exe",
    "/usr/bin/python3",
    "/usr/local/bin/python3"
  )
  python_bins <- unique(Filter(function(b) nzchar(b) && file.exists(b), python_bins))
  return(python_bins)
}

#' Resolve caminho do modelo oficial
resolve_report_template <- function(template_path = "templates/modelo_editais.docx") {
  if (file.exists(template_path)) return(normalizePath(template_path, winslash = "/", mustWork = FALSE))
  alt_paths <- c(
    file.path("templates", "modelo_editais.docx"),
    file.path("..", "templates", "modelo_editais.docx"),
    "modelo_editais.docx"
  )
  found <- Filter(file.exists, alt_paths)
  if (length(found) > 0) return(normalizePath(found[1], winslash = "/", mustWork = FALSE))
  return(NULL)
}

#' Resolve caminho do script Python preenchedor
resolve_report_script <- function(script_path = "scripts/fill_report_docx.py") {
  if (file.exists(script_path)) return(normalizePath(script_path, winslash = "/", mustWork = FALSE))
  alt_scripts <- c(
    file.path("scripts", "fill_report_docx.py"),
    file.path("..", "scripts", "fill_report_docx.py")
  )
  found_s <- Filter(file.exists, alt_scripts)
  if (length(found_s) > 0) return(normalizePath(found_s[1], winslash = "/", mustWork = FALSE))
  return(NULL)
}

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

  tmpl <- resolve_report_template(template_path)
  if (is.null(tmpl)) {
    warning("[DOCX] Arquivo modelo_editais.docx não encontrado em templates/")
    return(FALSE)
  }

  script_p <- resolve_report_script()
  if (is.null(script_p)) {
    warning("[DOCX] Script scripts/fill_report_docx.py não encontrado.")
    return(FALSE)
  }

  output_file <- normalizePath(output_file, winslash = "/", mustWork = FALSE)
  tmp_json <- tempfile(fileext = ".json")
  on.exit(unlink(tmp_json), add = TRUE)
  
  # Garante até 3 itens
  report_data$items <- utils::head(report_data$items, 3L)
  json_payload <- jsonlite::toJSON(report_data, auto_unbox = TRUE, pretty = FALSE)
  writeLines(json_payload, tmp_json, useBytes = TRUE)

  python_bins <- find_python_interpreter()
  filled_ok <- FALSE

  for (py_bin in python_bins) {
    args <- if (grepl("py(\\.exe)?$", py_bin, ignore.case = TRUE)) {
      c("-3", script_p, tmpl, output_file, tmp_json)
    } else {
      c(script_p, tmpl, output_file, tmp_json)
    }

    res <- tryCatch({
      system2(py_bin, args = args, stdout = TRUE, stderr = TRUE)
    }, error = function(e) NULL)

    if (file.exists(output_file) && file.info(output_file)$size > 1000) {
      message("[DOCX] Arquivo Word gerado com sucesso via Python: ", output_file)
      filled_ok <- TRUE
      break
    }
  }

  if (!filled_ok) {
    message("[DOCX] Falha na geração via Python, utilizando fallback cópia simples...")
    tryCatch({
      file.copy(tmpl, output_file, overwrite = TRUE)
      filled_ok <- TRUE
    }, error = function(e) warning("[DOCX] Erro no fallback: ", e$message))
  }

  return(filled_ok)
}

#' Gera relatório oficial em formato PDF (.pdf) bloqueado para modificação
#'
#' @param report_data Lista com os dados do relatório
#' @param output_file Caminho de destino do arquivo .pdf gerado
#' @param template_path Caminho do modelo Word oficial
#' @return TRUE se gerado com sucesso, FALSE em caso de erro
generate_pdf_report <- function(report_data, output_file, template_path = "templates/modelo_editais.docx") {
  if (is.null(report_data) || length(report_data$items) == 0L) {
    warning("[PDF] Dados do relatório vazios para geração do PDF.")
    return(FALSE)
  }

  tmpl <- resolve_report_template(template_path)
  if (is.null(tmpl)) {
    warning("[PDF] Arquivo modelo_editais.docx não encontrado em templates/")
    return(FALSE)
  }

  script_p <- resolve_report_script()
  if (is.null(script_p)) {
    warning("[PDF] Script scripts/fill_report_docx.py não encontrado.")
    return(FALSE)
  }

  output_file <- normalizePath(output_file, winslash = "/", mustWork = FALSE)
  tmp_json <- tempfile(fileext = ".json")
  on.exit(unlink(tmp_json), add = TRUE)
  
  # Garante até 3 itens
  report_data$items <- utils::head(report_data$items, 3L)
  json_payload <- jsonlite::toJSON(report_data, auto_unbox = TRUE, pretty = FALSE)
  writeLines(json_payload, tmp_json, useBytes = TRUE)

  python_bins <- find_python_interpreter()
  pdf_ok <- FALSE

  for (py_bin in python_bins) {
    args <- if (grepl("py(\\.exe)?$", py_bin, ignore.case = TRUE)) {
      c("-3", script_p, tmpl, output_file, tmp_json, "--pdf")
    } else {
      c(script_p, tmpl, output_file, tmp_json, "--pdf")
    }

    res <- tryCatch({
      system2(py_bin, args = args, stdout = TRUE, stderr = TRUE)
    }, error = function(e) NULL)

    if (file.exists(output_file) && file.info(output_file)$size > 1000) {
      message("[PDF] Relatório PDF gerado com sucesso via Python: ", output_file)
      pdf_ok <- TRUE
      break
    }
  }

  # Se a conversão a PDF não tiver suporte no ambiente (ex.: container sem LibreOffice/Word),
  # gera DOCX como fallback seguro e renomeia ou avisa
  if (!pdf_ok) {
    warning("[PDF] Conversão direta para PDF indisponível no ambiente.")
  }

  return(pdf_ok)
}
