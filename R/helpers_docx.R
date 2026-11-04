# ==============================================================================
# helpers_docx.R - Preenchimento do Modelo DOCX/PDF Institucional para Relatórios
# 100% Nativo em R (Zero Dependência de Python em Produção/Posit Connect)
# ==============================================================================

#' Resolve caminho do modelo oficial
resolve_report_template <- function(template_path = "templates/modelo_editais.docx") {
  if (file.exists(template_path)) return(normalizePath(template_path, winslash = "/", mustWork = FALSE))
  alt_paths <- c(
    file.path("templates", "modelo_editais.docx"),
    file.path("..", "templates", "modelo_editais.docx"),
    file.path(getwd(), "templates", "modelo_editais.docx"),
    "modelo_editais.docx"
  )
  found <- Filter(file.exists, alt_paths)
  if (length(found) > 0) return(normalizePath(found[1], winslash = "/", mustWork = FALSE))
  return(NULL)
}

#' Escapa caracteres especiais para XML
escape_xml_entities <- function(s) {
  if (is.null(s) || is.na(s)) return("")
  s <- as.character(s)
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s <- gsub("\"", "&quot;", s, fixed = TRUE)
  s <- gsub("'", "&apos;", s, fixed = TRUE)
  s
}

#' Gera relatório Word (.docx) preenchendo o modelo institucional oficial em R Puro
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

  output_file <- normalizePath(output_file, winslash = "/", mustWork = FALSE)
  ensure_dir(dirname(output_file))

  # Limita rigorosamente a até 3 itens (conforme os 3 slots do modelo institucional)
  items <- utils::head(report_data$items, 3L)
  n_items <- length(items)

  tmp_dir <- file.path(tempdir(), paste0("docx_pure_", as.integer(Sys.time()), "_", sample.int(10000, 1)))
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # 1. Descompacta o template DOCX usando zip::unzip (nativo, sem binário externo)
  zip::unzip(tmpl, exdir = tmp_dir)
  doc_xml_file <- file.path(tmp_dir, "word", "document.xml")
  rels_xml_file <- file.path(tmp_dir, "word", "_rels", "document.xml.rels")

  if (!file.exists(doc_xml_file)) {
    warning("[DOCX] word/document.xml não encontrado no pacote DOCX!")
    return(FALSE)
  }

  xml_content <- readLines(doc_xml_file, encoding = "UTF-8", warn = FALSE)
  clean_xml <- paste(xml_content, collapse = "\n")

  rels_content <- if (file.exists(rels_xml_file)) {
    paste(readLines(rels_xml_file, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  } else {
    ""
  }

  # 2. Normaliza os placeholders que o MS Word quebra entre múltiplos tags/runs
  # Exemplo: <w:t>{</w:t></w:r><w:r ...><w:t>{edital_1}}</w:t> -> {{edital_1}}
  for (k in 1:10) {
    clean_xml <- gsub("</w:t></w:r><w:r\\b[^>]*>(?:<w:rPr\\b[^>]*>.*?</w:rPr>)?<w:t\\b[^>]*>", "", clean_xml, perl = TRUE)
  }

  extra_rels <- character(0)

  # 3. Substitui os placeholders dos 3 editais
  for (i in 1:3) {
    it <- if (i <= n_items) items[[i]] else NULL

    edital_val <- if (!is.null(it)) escape_xml_entities(it$edital) else ""
    tipo_val   <- if (!is.null(it)) escape_xml_entities(it$tipo) else ""
    pais_val   <- if (!is.null(it)) escape_xml_entities(it$pais) else ""
    prazo_val  <- if (!is.null(it)) escape_xml_entities(it$prazo) else ""
    area_val   <- if (!is.null(it)) escape_xml_entities(it$area) else ""
    resumo_val <- if (!is.null(it)) escape_xml_entities(it$resumo) else ""
    orc_val    <- if (!is.null(it)) escape_xml_entities(it$orcamento) else ""

    link_url   <- if (!is.null(it)) trimws(it$link_url %||% "") else ""
    link_lbl   <- if (!is.null(it)) trimws(it$link_label %||% "") else ""
    if (!nzchar(link_lbl) && nzchar(link_url)) link_lbl <- link_url
    if (!nzchar(link_lbl)) link_lbl <- "Acessar Edital"

    # Injeção de hiperlink real em OpenXML se a URL for válida
    if (nzchar(link_url) && !identical(link_url, "#") && grepl("^https?://", link_url)) {
      rel_id <- paste0("rIdFundingHl", i)
      extra_rels <- c(extra_rels, sprintf(
        '<Relationship Id="%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="%s" TargetMode="External"/>',
        rel_id, escape_xml_entities(link_url)
      ))
      link_val_xml <- sprintf(
        '</w:t></w:r><w:hyperlink r:id="%s" w:history="1"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr><w:t>%s</w:t></w:r></w:hyperlink><w:r><w:t>',
        rel_id, escape_xml_entities(link_lbl)
      )
    } else {
      link_val_xml <- escape_xml_entities(link_lbl)
    }

    clean_xml <- gsub(paste0("\\{\\{edital_", i, "\\}\\}"), edital_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{tipo_", i, "\\}\\}"), tipo_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{pais_", i, "\\}\\}"), pais_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{prazo_", i, "\\}\\}"), prazo_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{(área|area)_", i, "\\}\\}"), area_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{(orçamento|orcamento)_", i, "\\}\\}"), orc_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{link_", i, "\\}\\}"), link_val_xml, clean_xml, perl = TRUE)

    # Tratamento específico do slot 2 que possui {{resumo_1}} no modelo original
    if (i == 2) {
      parts <- strsplit(clean_xml, "\\{\\{resumo_1\\}\\}")[[1]]
      if (length(parts) >= 3) {
        clean_xml <- paste0(parts[1], escape_xml_entities(if (n_items >= 1) items[[1]]$resumo else ""),
                            parts[2], resumo_val,
                            paste(parts[3:length(parts)], collapse = ""))
      }
    } else if (i == 3) {
      clean_xml <- gsub("\\{\\{resumo_3\\}\\}", resumo_val, clean_xml, perl = TRUE)
    }
  }

  if (n_items >= 1) {
    clean_xml <- gsub("\\{\\{resumo_1\\}\\}", escape_xml_entities(items[[1]]$resumo), clean_xml, perl = TRUE)
  }

  # Injeta os relacionamentos de hyperlink no document.xml.rels
  if (length(extra_rels) > 0 && nzchar(rels_content)) {
    rels_content <- sub("</Relationships>", paste0(paste(extra_rels, collapse = "\n"), "\n</Relationships>"), rels_content, fixed = TRUE)
    writeLines(rels_content, rels_xml_file, useBytes = TRUE)
  }

  writeLines(clean_xml, doc_xml_file, useBytes = TRUE)

  # Compacta com zip::zip
  if (file.exists(output_file)) unlink(output_file)

  orig_dir <- getwd()
  setwd(tmp_dir)
  all_files <- list.files(recursive = TRUE, all.files = TRUE, no.. = TRUE)
  zip::zip(zipfile = output_file, files = all_files)
  setwd(orig_dir)

  if (file.exists(output_file) && file.size(output_file) > 1000) {
    message(sprintf("[DOCX] Relatório Word gerado com sucesso via R puro: %s (%d bytes)", output_file, file.size(output_file)))
    return(TRUE)
  }

  warning("[DOCX] Falha na gravação do arquivo DOCX final.")
  return(FALSE)
}

#' Gera versão PDF oficial com garantia de integridade e múltiplos fallbacks
#'
#' Tenta conversão direta do DOCX para manter 100% a identidade visual do template.
#' Se o servidor (como Posit Connect Linux) não possuir Word ou LibreOffice,
#' gera um PDF institucional oficial diretamente via R para garantir que o download
#' nunca falhe com erro HTTP 404.
#'
#' @param report_data Lista com dados do relatório
#' @param output_pdf Caminho do arquivo PDF de saída
#' @param template_path Caminho do modelo Word oficial
#' @return TRUE se gerado com sucesso, FALSE em caso de erro
generate_pdf_report <- function(report_data, output_pdf, template_path = "templates/modelo_editais.docx") {
  output_pdf <- normalizePath(output_pdf, winslash = "/", mustWork = FALSE)
  ensure_dir(dirname(output_pdf))

  # 1. Primeiro gera o DOCX preenchido
  tmp_docx <- tempfile(fileext = ".docx")
  on.exit(unlink(tmp_docx), add = TRUE)
  docx_ok <- generate_docx_report(report_data, tmp_docx, template_path = template_path)

  pdf_created <- FALSE

  # 2. Tentativa 1 (Windows com Word / docx2pdf via Python Launcher ou COM)
  if (docx_ok && .Platform$OS.type == "windows") {
    tryCatch({
      py_bins <- c(
        Sys.which("py"),
        Sys.which("python3"),
        Sys.which("python"),
        "C:/Users/felipe.dourado/AppData/Local/Programs/Python/Launcher/py.exe"
      )
      py_bins <- unique(Filter(function(b) nzchar(b) && file.exists(b), py_bins))
      for (py in py_bins) {
        cmd_args <- c("-c", sprintf("from docx2pdf import convert; convert(r'%s', r'%s')", tmp_docx, output_pdf))
        res <- system2(py, args = cmd_args, stdout = TRUE, stderr = TRUE)
        if (file.exists(output_pdf) && file.size(output_pdf) > 1000) {
          message("[PDF] PDF gerado via docx2pdf com sucesso.")
          pdf_created <- TRUE
          break
        }
      }
    }, error = function(e) NULL)
  }

  # 3. Tentativa 2 (Linux / Servidor: LibreOffice headless)
  if (!pdf_created && docx_ok) {
    libreoffice_bins <- c("soffice", "libreoffice", "/usr/bin/libreoffice", "/usr/bin/soffice")
    for (lb in libreoffice_bins) {
      lb_path <- Sys.which(lb)
      if (nzchar(lb_path) || file.exists(lb)) {
        res <- tryCatch({
          out_dir <- dirname(output_pdf)
          system2(lb, args = c("--headless", "--convert-to", "pdf", "--outdir", out_dir, tmp_docx), stdout = TRUE, stderr = TRUE)
        }, error = function(e) NULL)
        
        gen_pdf <- file.path(dirname(output_pdf), sub("\\.docx$", ".pdf", basename(tmp_docx)))
        if (file.exists(gen_pdf)) {
          file.rename(gen_pdf, output_pdf)
          if (file.exists(output_pdf) && file.size(output_pdf) > 1000) {
            message("[PDF] PDF gerado via LibreOffice headless com sucesso.")
            pdf_created <- TRUE
            break
          }
        }
      }
    }
  }

  # 4. Tentativa 3: Se não há Word nem LibreOffice (ambiente Posit Connect padrão),
  # renderiza um PDF oficial formatado institucionalmente em R para evitar erro 404
  if (!pdf_created) {
    message("[PDF] Motores externos (Word/LibreOffice) indisponíveis. Gerando PDF oficial via R nativo...")
    tryCatch({
      generate_fallback_institutional_pdf(report_data, output_pdf)
      if (file.exists(output_pdf) && file.size(output_pdf) > 500) {
        pdf_created <- TRUE
      }
    }, error = function(e) {
      warning("[PDF] Falha na geração do PDF fallback via R: ", e$message)
    })
  }

  return(pdf_created)
}

#' Gera PDF institucional oficial utilizando o dispositivo gráfico nativo do R
#' Garante documento legível, formatado com as cores SENAI CIMATEC e 100% infalível em qualquer servidor
generate_fallback_institutional_pdf <- function(report_data, output_pdf) {
  items <- utils::head(report_data$items %||% list(), 3L)
  campus_title <- toupper(report_data$campus_name %||% "SENAI CIMATEC")
  data_geracao <- format(Sys.time(), "%d/%m/%Y às %H:%M")

  grDevices::pdf(
    file = output_pdf,
    width = 8.27, # A4
    height = 11.69,
    paper = "a4",
    family = "Helvetica"
  )
  on.exit(grDevices::dev.off(), add = TRUE)

  # Configurações de layout
  graphics::par(mar = c(2, 2.5, 2, 2.5), oma = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 100), ylim = c(0, 100))

  # Cabeçalho Institucional
  graphics::rect(0, 93, 100, 100, col = "#003366", border = NA)
  graphics::text(5, 96.5, "SENAI CIMATEC | FUNDING INTELLIGENCE", col = "#FFFFFF", font = 2, cex = 1.3, adj = 0)
  graphics::text(5, 94.2, sprintf("RELATÓRIO OFICIAL DE OPORTUNIDADES ABERTAS - %s", campus_title), col = "#DCE8F5", font = 1, cex = 0.85, adj = 0)
  graphics::text(95, 95.5, sprintf("Gerado em: %s", data_geracao), col = "#E0E0E0", font = 3, cex = 0.75, adj = 1)

  y_curr <- 89

  if (length(items) == 0) {
    graphics::text(50, 50, "Nenhuma oportunidade aberta encontrada para os critérios selecionados.", cex = 1.1, col = "#555555")
    return(TRUE)
  }

  for (idx in seq_along(items)) {
    it <- items[[idx]]
    
    # Caixa de destaque do Edital
    graphics::rect(2, y_curr - 26, 98, y_curr, col = "#F8F9FA", border = "#D0D7DE", lwd = 1.2)
    graphics::rect(2, y_curr - 4.5, 98, y_curr, col = "#E9ECEF", border = NA)

    # Título do Edital
    edital_titulo <- paste(strwrap(it$edital %||% "Edital sem título", width = 85), collapse = "\n")
    graphics::text(4, y_curr - 2.5, sprintf("Edital: %s", edital_titulo), col = "#003366", font = 2, cex = 0.9, adj = 0)

    # Metadados
    graphics::text(4, y_curr - 6.5, sprintf("Tipo de oportunidade: %s", it$tipo %||% "N/A"), col = "#333333", cex = 0.8, adj = 0)
    graphics::text(55, y_curr - 6.5, sprintf("País de origem: %s", it$pais %||% "N/A"), col = "#333333", cex = 0.8, adj = 0)

    graphics::text(4, y_curr - 9.5, sprintf("Prazo limite: %s", it$prazo %||% "N/A"), col = "#854F06", font = 2, cex = 0.8, adj = 0)
    graphics::text(55, y_curr - 9.5, sprintf("Área temática: %s", it$area %||% "N/A"), col = "#333333", cex = 0.8, adj = 0)

    graphics::text(4, y_curr - 12.5, sprintf("Orçamento estimado: %s", it$orcamento %||% "N/A"), col = "#1F7A3F", font = 2, cex = 0.8, adj = 0)

    # Resumo com quebra automática de linha
    resumo_txt <- it$resumo %||% "Sem resumo cadastrado."
    wrapped_resumo <- paste(utils::head(strwrap(resumo_txt, width = 95), 4), collapse = "\n")
    graphics::text(4, y_curr - 17, sprintf("Resumo:\n%s", wrapped_resumo), col = "#444444", cex = 0.75, adj = c(0, 1))

    # Link de acesso
    link_url <- it$link_url %||% ""
    link_lbl <- it$link_label %||% "Acessar Portal Oficial"
    graphics::text(4, y_curr - 24, sprintf("Link de acesso: %s (%s)", link_lbl, link_url), col = "#0969DA", font = 2, cex = 0.8, adj = 0)

    y_curr <- y_curr - 29
  }

  # Rodapé Institucional
  graphics::rect(0, 0, 100, 3, col = "#F0F4F8", border = NA)
  graphics::text(50, 1.5, "QuIIN - Núcleo de Inteligência e Inovação | SENAI CIMATEC | Uso Exclusivo Institucional", col = "#666666", cex = 0.75, font = 3)

  return(TRUE)
}
