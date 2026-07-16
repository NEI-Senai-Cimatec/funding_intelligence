# helpers_export.R
# Export utility functions for QuIIN platform

#' Generate timestamped filename for exports
#' @param prefix Filename prefix
#' @param extension File extension (xlsx or csv)
#' @return Character string with timestamped filename
generate_export_filename <- function(prefix = "quiiin_export", extension = "xlsx") {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  sprintf("%s_%s.%s", prefix, timestamp, extension)
}

#' Export data to XLSX format using writexl
#' @param data Data frame to export
#' @param filename Optional filename (if NULL, generates timestamped filename)
#' @param path Directory path to save file
#' @return Path to the saved file
export_to_xlsx <- function(data, filename = NULL, path = app_file("data_exports")) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    stop("Package 'writexl' is required for XLSX export")
  }
  
  ensure_dir(path)
  
  if (is.null(filename)) {
    filename <- generate_export_filename("quiiin_export", "xlsx")
  }
  
  filepath <- file.path(path, filename)
  writexl::write_xlsx(data, filepath)
  
  message(sprintf("Dados exportados para: %s", filepath))
  return(filepath)
}

#' Export data to CSV format
#' @param data Data frame to export
#' @param filename Optional filename (if NULL, generates timestamped filename)
#' @param path Directory path to save file
#' @return Path to the saved file
export_to_csv <- function(data, filename = NULL, path = app_file("data_exports")) {
  ensure_dir(path)
  
  if (is.null(filename)) {
    filename <- generate_export_filename("quiiin_export", "csv")
  }
  
  filepath <- file.path(path, filename)
  write.csv(data, filepath, row.names = FALSE, fileEncoding = "UTF-8")
  
  message(sprintf("Dados exportados para: %s", filepath))
  return(filepath)
}

#' Prepare data for export with only 6 specific columns
#' @param data Original data frame from filtered_results()
#' @return Data frame ready for export with only: Titulo, Entidade, Prazo Limite, Link Portal, Link Detalhes, Link PDF
prepare_export_data <- function(data) {
  if (is.null(data) || nrow(data) == 0) {
    return(tibble::tibble())
  }
  
  data |>
    dplyr::mutate(
      # Format Prazo Limite for export
      data_limite_fmt = format_date_br(data_limite)
    ) |>
    dplyr::select(
      # Only the 6 specified columns
      titulo,
      entidade,
      data_limite_fmt,
      link_origem,
      link_detalhe,
      link_documento_pdf
    ) |>
    dplyr::rename(
      "Título" = titulo,
      "Entidade" = entidade,
      "Prazo Limite" = data_limite_fmt,
      "Link Portal" = link_origem,
      "Link Detalhes" = link_detalhe,
      "Link PDF" = link_documento_pdf
    )
}

#' Download file to user's browser
#' @param filepath Path to the file to download
#' @param filename Display filename for download
download_file <- function(filepath, filename = basename(filepath)) {
  if (!file.exists(filepath)) {
    stop(sprintf("Arquivo não encontrado: %s", filepath))
  }
  
  fileContentType <- if (grepl("\\.xlsx$", filepath, ignore.case = TRUE)) {
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  } else if (grepl("\\.csv$", filepath, ignore.case = TRUE)) {
    "text/csv"
  } else {
    "application/octet-stream"
  }
  
  shiny::downloadHandler(
    filename = function() {
      filename
    },
    content = function(file) {
      file.copy(filepath, file)
    },
    contentType = fileContentType
  )
}