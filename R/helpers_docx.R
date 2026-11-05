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

#' Junta os runs do Word que quebram um marcador {{campo_n}} em vários pedaços
#'
#' O Word divide o texto em vários <w:r> (revisão ortográfica, rsid, idioma...).
#' Ex.: <w:t>{</w:t></w:r><w:r><w:t>{edital_1}}</w:t>. Aqui removemos marcas
#' que não carregam texto e unimos apenas os runs que estão DENTRO de um marcador
#' aberto, preservando a formatação (negrito dos rótulos etc.) do restante.
docx_merge_split_placeholders <- function(xml) {
  xml <- gsub("<w:proofErr\\b[^>]*/>", "", xml, perl = TRUE)
  xml <- gsub("<w:bookmark(Start|End)\\b[^>]*/>", "", xml, perl = TRUE)
  xml <- gsub("<w:lastRenderedPageBreak/>", "", xml, fixed = TRUE)
  xml <- gsub("<w:noProof/>", "", xml, fixed = TRUE)
  boundary <- "</w:t></w:r><w:r\\b[^>]*>(?:<w:rPr>(?:(?!</w:rPr>).)*</w:rPr>)?<w:t\\b[^>]*>"
  # "{" seguido de "{" em outro run
  for (k in 1:5) {
    xml <- gsub(paste0("\\{", boundary, "\\{"), "{{", xml, perl = TRUE)
  }
  # marcador aberto ("{{campo") cujo restante está nos runs seguintes
  for (k in 1:10) {
    novo <- gsub(paste0("(\\{\\{[^{}<]{0,40})", boundary), "\\1", xml, perl = TRUE)
    if (identical(novo, xml)) break
    xml <- novo
  }
  xml
}

#' Envolve valor substituído em um run XML explícito sem negrito (Sora Light 9pt)
wrap_nonbold_docx_run <- function(escaped_val) {
  if (!nzchar(escaped_val)) return("")
  sprintf(
    '</w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Sora Light" w:hAnsi="Sora Light" w:cs="Sora Light"/><w:b w:val="0"/><w:bCs w:val="0"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r><w:r><w:t>',
    escaped_val
  )
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
  clean_xml <- docx_merge_split_placeholders(clean_xml)

  extra_rels <- character(0)

  # 3. Substitui os placeholders dos 3 editais garantindo rótulos em negrito e valores sem negrito
  for (i in 1:3) {
    it <- if (i <= n_items) items[[i]] else NULL

    edital_val <- if (!is.null(it)) wrap_nonbold_docx_run(escape_xml_entities(it$edital)) else ""
    tipo_val   <- if (!is.null(it)) wrap_nonbold_docx_run(escape_xml_entities(it$tipo)) else ""
    pais_val   <- if (!is.null(it)) wrap_nonbold_docx_run(escape_xml_entities(it$pais)) else ""
    prazo_val  <- if (!is.null(it)) wrap_nonbold_docx_run(escape_xml_entities(it$prazo)) else ""
    area_val   <- if (!is.null(it)) wrap_nonbold_docx_run(escape_xml_entities(it$area)) else ""
    resumo_val <- if (!is.null(it)) wrap_nonbold_docx_run(escape_xml_entities(it$resumo)) else ""
    orc_val    <- if (!is.null(it)) wrap_nonbold_docx_run(escape_xml_entities(it$orcamento)) else ""

    link_url   <- if (!is.null(it)) trimws(it$link_url %||% "") else ""
    link_lbl   <- if (!is.null(it)) trimws(it$link_label %||% "") else ""
    if (!is.null(it)) {
      if (!nzchar(link_lbl) && nzchar(link_url)) link_lbl <- link_url
      if (!nzchar(link_lbl)) link_lbl <- "Acessar Edital"
    }

    # Injeção de hiperlink real em OpenXML se a URL for válida (sem negrito no valor do link)
    if (!is.null(it) && nzchar(link_url) && !identical(link_url, "#") && grepl("^https?://", link_url)) {
      rel_id <- paste0("rIdFundingHl", i)
      extra_rels <- c(extra_rels, sprintf(
        '<Relationship Id="%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="%s" TargetMode="External"/>',
        rel_id, escape_xml_entities(link_url)
      ))
      link_val_xml <- sprintf(
        '</w:t></w:r><w:hyperlink r:id="%s" w:history="1"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/><w:rFonts w:ascii="Sora Light" w:hAnsi="Sora Light" w:cs="Sora Light"/><w:b w:val="0"/><w:bCs w:val="0"/><w:color w:val="0563C1"/><w:sz w:val="18"/><w:szCs w:val="18"/><w:u w:val="single"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:hyperlink><w:r><w:t>',
        rel_id, escape_xml_entities(link_lbl)
      )
    } else if (!is.null(it) && nzchar(link_lbl)) {
      link_val_xml <- wrap_nonbold_docx_run(escape_xml_entities(link_lbl))
    } else {
      link_val_xml <- ""
    }

    clean_xml <- gsub(paste0("\\{\\{edital_", i, "\\}\\}"), edital_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{tipo_", i, "\\}\\}"), tipo_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{pais_", i, "\\}\\}"), pais_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{prazo_", i, "\\}\\}"), prazo_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{(área|area)_", i, "\\}\\}"), area_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{(orçamento|orcamento)_", i, "\\}\\}"), orc_val, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{link_", i, "\\}\\}"), link_val_xml, clean_xml, perl = TRUE)
    clean_xml <- gsub(paste0("\\{\\{resumo_", i, "\\}\\}"), resumo_val, clean_xml, perl = TRUE)
  }

  # Nenhum marcador {{...}} pode sobrar no documento final
  sobras <- regmatches(clean_xml, gregexpr("\\{\\{[^{}<]{1,40}\\}\\}", clean_xml, perl = TRUE))[[1]]
  if (length(sobras) > 0L) {
    clean_xml <- gsub("\\{\\{[^{}<]{1,40}\\}\\}", "", clean_xml, perl = TRUE)
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
#' gera um PDF institucional oficial diretamente via R com o modelo Radar da Inovação
#' (NEI - SENAI CIMATEC), chaves em negrito, valores sem negrito e links clicáveis.
#'
#' @param report_data Lista com dados do relatório
#' @param output_pdf Caminho do arquivo PDF de saída
#' @param template_path Caminho do modelo Word oficial
#' @return TRUE se gerado com sucesso, FALSE em caso de erro
generate_pdf_report <- function(report_data, output_pdf, template_path = "templates/modelo_editais.docx") {
  output_pdf <- normalizePath(output_pdf, winslash = "/", mustWork = FALSE)
  ensure_dir(dirname(output_pdf))
  if (file.exists(output_pdf)) unlink(output_pdf)

  # 1. Primeiro gera o DOCX preenchido
  tmp_docx <- tempfile(fileext = ".docx")
  on.exit(unlink(tmp_docx), add = TRUE)
  docx_ok <- generate_docx_report(report_data, tmp_docx, template_path = template_path)

  pdf_created <- FALSE

  # 2. Tentativa 1 (Windows com docx2pdf se instalado)
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
        res <- suppressWarnings(system2(py, args = cmd_args, stdout = TRUE, stderr = TRUE))
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

  # 4. Tentativa 3: Renderiza o PDF institucional oficial Radar da Inovação (NEI - SENAI CIMATEC)
  # diretamente em R nativo com anotações de link clicáveis (/Subtype /Link /URI)
  if (!pdf_created) {
    message("[PDF] Gerando PDF institucional Radar da Inovação (NEI - SENAI CIMATEC) via R nativo...")
    tryCatch({
      generate_fallback_institutional_pdf(report_data, output_pdf, template_path = template_path)
      if (file.exists(output_pdf) && file.size(output_pdf) > 500) {
        pdf_created <- TRUE
      }
    }, error = function(e) {
      warning("[PDF] Falha na geração do PDF institucional via R: ", e$message)
    })
  }

  return(pdf_created)
}

#' Desenha um campo no formato "Chave: Valor" onde a chave fica em negrito (font = 2)
#' e o valor fica sem negrito (font = 1), com quebra automática de linhas.
draw_pdf_labeled_field <- function(x_pos, y_curr, label_txt, value_txt,
                                   max_w = 150, cex_val = 0.78, line_h = 4.5,
                                   max_lines = 5, val_col = "#000000",
                                   underline_val = FALSE) {
  # 1. Desenha o rótulo em negrito (font = 2)
  graphics::text(x_pos, y_curr, label_txt, col = "#000000", font = 2, cex = cex_val, adj = 0)
  label_w <- graphics::strwidth(label_txt, font = 2, cex = cex_val)

  value_txt <- trimws(as.character(value_txt %||% ""))
  if (!nzchar(value_txt)) {
    return(list(y_next = y_curr - line_h, rect_pt = NULL))
  }

  words <- strsplit(value_txt, "\\s+")[[1]]
  lines_out <- character(0)
  curr_line <- ""
  avail_w <- max(20, max_w - label_w)

  for (w in words) {
    cand <- if (nzchar(curr_line)) paste(curr_line, w) else w
    w_cand <- graphics::strwidth(cand, font = 1, cex = cex_val)
    if (w_cand <= avail_w || !nzchar(curr_line)) {
      curr_line <- cand
    } else {
      lines_out <- c(lines_out, curr_line)
      curr_line <- w
      avail_w <- max_w
    }
  }
  if (nzchar(curr_line)) {
    lines_out <- c(lines_out, curr_line)
  }

  if (length(lines_out) > max_lines) {
    lines_out <- lines_out[seq_len(max_lines)]
    lines_out[max_lines] <- paste0(substr(lines_out[max_lines], 1, max(10, nchar(lines_out[max_lines]) - 3)), "...")
  }

  # 2. Desenha a 1ª linha do valor logo após o rótulo, SEM negrito (font = 1)
  x_val1 <- x_pos + label_w
  val1_w <- graphics::strwidth(lines_out[1], font = 1, cex = cex_val)
  graphics::text(x_val1, y_curr, lines_out[1], col = val_col, font = 1, cex = cex_val, adj = 0)

  if (isTRUE(underline_val) && val1_w > 0) {
    graphics::lines(c(x_val1, x_val1 + val1_w), c(y_curr - 0.85, y_curr - 0.85), col = val_col, lwd = 0.75)
  }

  # Calcula retângulo em pontos PDF (595 x 841) para anotação de link clicável
  x1_pt <- graphics::grconvertX(x_val1, from = "user", to = "ndc") * 595
  x2_pt <- graphics::grconvertX(x_val1 + val1_w, from = "user", to = "ndc") * 595
  y1_pt <- graphics::grconvertY(y_curr - 1.2, from = "user", to = "ndc") * 841
  y2_pt <- graphics::grconvertY(y_curr + 3.2, from = "user", to = "ndc") * 841
  rect_pt <- c(round(x1_pt, 2), round(y1_pt, 2), round(x2_pt, 2), round(y2_pt, 2))

  y_curr <- y_curr - line_h

  # 3. Desenha as linhas subsequentes do valor alinhadas em x_pos, SEM negrito (font = 1)
  if (length(lines_out) >= 2) {
    for (idx in 2:length(lines_out)) {
      graphics::text(x_pos, y_curr, lines_out[idx], col = val_col, font = 1, cex = cex_val, adj = 0)
      y_curr <- y_curr - line_h
    }
  }

  list(y_next = y_curr, rect_pt = rect_pt)
}

#' Injeta anotações de hiperlink clicáveis (/Subtype /Link /A << /S /URI ... >>)
#' nas páginas do PDF gerado pelo grDevices::pdf() operando diretamente sobre bytes brutos.
inject_pdf_uri_links <- function(pdf_path, page_links) {
  if (!file.exists(pdf_path) || length(page_links) == 0L) return(invisible(FALSE))

  raw_bytes <- readBin(pdf_path, what = "raw", n = file.info(pdf_path)$size)
  to_search_str <- function(rb) {
    sb <- rb
    sb[sb == as.raw(0L)] <- as.raw(1L)
    s <- rawToChar(sb)
    Encoding(s) <- "latin1"
    s
  }

  search_str <- to_search_str(raw_bytes)

  # Localiza os objetos /Type /Page em ordem de página (1-to-1 com índices de raw_bytes)
  page_matches <- gregexpr(
    "[0-9]+ 0 obj\\r?\\n<< /Type /Page /Parent [0-9]+ 0 R /Contents [0-9]+ 0 R /Resources [0-9]+ 0 R >>\\r?\\nendobj",
    search_str, perl = TRUE, useBytes = TRUE
  )[[1]]
  if (length(page_matches) == 0L || page_matches[1] == -1L) return(invisible(FALSE))

  # Substitui de trás para frente diretamente em raw_bytes preservando os streams FlateDecode
  for (p_idx in rev(seq_along(page_matches))) {
    if (p_idx <= length(page_links) && !is.null(page_links[[p_idx]])) {
      lnk <- page_links[[p_idx]]
      url_clean <- gsub("([()\\\\])", "\\\\\\1", lnk$url, perl = TRUE)
      r <- lnk$rect
      annot_str <- sprintf(
        "/Annots [ << /Type /Annot /Subtype /Link /Rect [%.2f %.2f %.2f %.2f] /Border [0 0 0] /A << /Type /Action /S /URI /URI (%s) >> >> ] >>",
        r[1], r[2], r[3], r[4], url_clean
      )
      m_start <- page_matches[p_idx]
      m_len <- attr(page_matches, "match.length")[p_idx]
      orig_obj <- rawToChar(raw_bytes[m_start:(m_start + m_len - 1L)])
      new_obj <- sub(">>(\\r?\\nendobj)$", paste0(annot_str, "\\1"), orig_obj, perl = TRUE)
      new_obj_raw <- charToRaw(new_obj)

      prefix_raw <- if (m_start > 1L) raw_bytes[1L:(m_start - 1L)] else raw(0)
      suffix_start <- m_start + m_len
      suffix_raw <- if (suffix_start <= length(raw_bytes)) raw_bytes[suffix_start:length(raw_bytes)] else raw(0)
      raw_bytes <- c(prefix_raw, new_obj_raw, suffix_raw)
    }
  }

  # Reconstrói a tabela xref com os byte offsets exatos de cada "N 0 obj"
  search_str <- to_search_str(raw_bytes)
  xref_pos <- regexpr("xref\\r?\\n", search_str, perl = TRUE, useBytes = TRUE)[1]
  if (xref_pos > 1L) {
    body_raw <- raw_bytes[1L:(xref_pos - 1L)]
    body_search <- substr(search_str, 1L, xref_pos - 1L)

    obj_matches <- gregexpr("([0-9]+) 0 obj", body_search, perl = TRUE, useBytes = TRUE)[[1]]
    obj_strs <- regmatches(body_search, list(obj_matches))[[1]]
    obj_ids <- as.integer(sub(" 0 obj$", "", obj_strs))
    max_id <- max(obj_ids)

    xref_lines <- character(max_id + 1L)
    xref_lines[1] <- "0000000000 65535 f "
    for (k in seq_along(obj_ids)) {
      id <- obj_ids[k]
      offset <- obj_matches[k] - 1L # 0-indexed byte offset
      xref_lines[id + 1L] <- sprintf("%010d 00000 n ", offset)
    }

    trailer_pos <- regexpr("trailer\\r?\\n<<[\\s\\S]*?>>", search_str, perl = TRUE, useBytes = TRUE)
    trailer_block <- if (trailer_pos[1] > 0L) {
      t_start <- trailer_pos[1]
      t_len <- attr(trailer_pos, "match.length")
      rawToChar(raw_bytes[t_start:(t_start + t_len - 1L)])
    } else {
      sprintf("trailer\n<< /Size %d /Root 1 0 R /Info 2 0 R >>", max_id + 1L)
    }

    new_xref_offset <- length(body_raw)
    new_tail <- paste0(
      "xref\n",
      sprintf("0 %d\n", max_id + 1L),
      paste(xref_lines, collapse = "\n"), "\n",
      trailer_block, "\n",
      "startxref\n",
      sprintf("%d\n", new_xref_offset),
      "%%EOF\n"
    )
    raw_bytes <- c(body_raw, charToRaw(new_tail))
  }

  writeBin(raw_bytes, pdf_path)
  invisible(TRUE)
}

#' Gera PDF institucional oficial utilizando o dispositivo gráfico nativo do R
#' Segue fielmente o modelo Radar da Inovação (NEI - SENAI CIMATEC), com rótulos
#' em negrito, valores sem negrito e hiperlinks clicáveis.
generate_fallback_institutional_pdf <- function(report_data, output_pdf, template_path = "templates/modelo_editais.docx") {
  items <- utils::head(report_data$items %||% list(), 3L)

  # Resolve a imagem de fundo do modelo Radar da Inovação (SENAI CIMATEC)
  bg_path <- file.path("templates", "modelo_editais_bg.png")
  has_bg <- file.exists(bg_path) && requireNamespace("png", quietly = TRUE)
  bg_img <- if (has_bg) tryCatch(png::readPNG(bg_path), error = function(e) NULL) else NULL

  mes_ano <- format(Sys.time(), "%m/%Y")
  page_links <- vector("list", 3L)

  local({
    grDevices::pdf(
      file = output_pdf,
      width = 8.27, # A4
      height = 11.69,
      paper = "a4",
      family = "Helvetica"
    )
    on.exit(grDevices::dev.off(), add = TRUE)

    for (page_num in 1:3) {
      it <- if (page_num <= length(items)) items[[page_num]] else NULL

      graphics::par(mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 0), xaxs = "i", yaxs = "i")
      graphics::plot.new()
      graphics::plot.window(xlim = c(0, 210), ylim = c(0, 297))

      # 1. Fundo Oficial Radar da Inovação (cabeçalho azul curvo + logo SENAI CIMATEC)
      if (!is.null(bg_img)) {
        graphics::rasterImage(bg_img, 0, 0, 210, 297)
      } else {
        graphics::rect(0, 240, 210, 297, col = "#0B0B45", border = NA)
        graphics::rect(10, 226, 200, 255, col = "#000080", border = NA)
      }

      # 2. Textos do Cabeçalho Oficial (idênticos ao modelo Word Radar da Inovação)
      graphics::text(21, 266.5, "BOLETIM", col = "#00FFFF", font = 1, cex = 1.55, adj = 0)
      graphics::text(21, 258.5, "Radar da Inovação", col = "#00FFFF", font = 1, cex = 1.40, adj = 0)
      graphics::text(192, 267.5, sprintf("Edição %s", mes_ano), col = "#FFFFFF", font = 1, cex = 0.90, adj = 1)

      graphics::text(
        105, 246.5,
        "Publicação seriada que divulga oportunidade de financiamento à pesquisa,",
        col = "#FFFFFF", font = 2, cex = 0.92, adj = 0.5
      )
      graphics::text(
        105, 241.5,
        "desenvolvimento e inovação",
        col = "#FFFFFF", font = 2, cex = 0.92, adj = 0.5
      )

      # 3. Conteúdo do Edital na página correspondente (chaves em negrito, valores sem negrito)
      y_curr <- 195
      x_pos <- 30

      edital_txt <- if (!is.null(it)) (it$edital %||% "") else ""
      tipo_txt   <- if (!is.null(it)) (it$tipo %||% "") else ""
      pais_txt   <- if (!is.null(it)) (it$pais %||% "") else ""
      prazo_txt  <- if (!is.null(it)) (it$prazo %||% "") else ""
      area_txt   <- if (!is.null(it)) (it$area %||% "") else ""
      resumo_txt <- if (!is.null(it)) (it$resumo %||% "") else ""
      orc_txt    <- if (!is.null(it)) (it$orcamento %||% "") else ""

      link_url <- if (!is.null(it)) trimws(it$link_url %||% "") else ""
      link_lbl <- if (!is.null(it)) trimws(it$link_label %||% "") else ""
      if (!is.null(it)) {
        if (!nzchar(link_lbl) && nzchar(link_url)) link_lbl <- link_url
        if (!nzchar(link_lbl)) link_lbl <- "Acessar Edital"
      }
      is_valid_url <- nzchar(link_url) && !identical(link_url, "#") && grepl("^https?://", link_url)

      y_curr <- draw_pdf_labeled_field(x_pos, y_curr, "Edital: ", edital_txt, max_lines = 3)$y_next
      y_curr <- draw_pdf_labeled_field(x_pos, y_curr, "Tipo de oportunidade: ", tipo_txt, max_lines = 2)$y_next
      y_curr <- draw_pdf_labeled_field(x_pos, y_curr, "País de origem: ", pais_txt, max_lines = 1)$y_next
      y_curr <- draw_pdf_labeled_field(x_pos, y_curr, "Prazo limite de submissão: ", prazo_txt, max_lines = 1)$y_next
      y_curr <- draw_pdf_labeled_field(x_pos, y_curr, "Área temática: ", area_txt, max_lines = 2)$y_next

      y_curr <- y_curr - 3.5
      y_curr <- draw_pdf_labeled_field(x_pos, y_curr, "Resumo: ", resumo_txt, max_lines = 6)$y_next

      y_curr <- y_curr - 3.5
      y_curr <- draw_pdf_labeled_field(x_pos, y_curr, "Orçamento estimado: ", orc_txt, max_lines = 2)$y_next

      y_curr <- y_curr - 3.5
      link_res <- draw_pdf_labeled_field(
        x_pos, y_curr,
        "Link de acesso: ", link_lbl,
        max_lines = 1,
        val_col = if (is_valid_url) "#0563C1" else "#000000",
        underline_val = is_valid_url
      )
      y_curr <- link_res$y_next

      if (is_valid_url && !is.null(link_res$rect_pt)) {
        page_links[[page_num]] <<- list(url = link_url, rect = link_res$rect_pt)
      }

      # Linha divisória horizontal (presente nas páginas 1 e 3 do modelo Word)
      if (page_num %in% c(1, 3)) {
        y_line <- if (page_num == 3) min(y_curr - 4.0, 145) else (y_curr - 12.0)
        graphics::lines(c(30, 98), c(y_line, y_line), col = "#000000", lwd = 0.8)
        y_curr <- y_line - 6.0
      }

      # 4. Na Página 3: Ficha Técnica Oficial do NEI / SENAI CIMATEC
      if (page_num == 3) {
        y_ficha <- y_curr - 1.0
        graphics::text(30, y_ficha, "MOTA, Mabel Diz Marques Mota; SILVA, Raphael Oliveira; DANTAS, Yuri; FIGUEIROA, Felipe.", col = "#000000", font = 1, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 3.6
        graphics::text(30, y_ficha, "Boletim: Radar da Inovação. Organização: MABEL DIZ MARQUES MOTA. Salvador: NEI, 2026.", col = "#000000", font = 3, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 3.6
        graphics::text(30, y_ficha, "Boletim Técnico.", col = "#000000", font = 3, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 7.2
        graphics::text(30, y_ficha, "@NÚCLEO DE ECONOMIA INDUSTRIAL – 2026", col = "#000000", font = 1, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 3.6
        graphics::text(30, y_ficha, "Boletim Técnico NEI. Salvador: SENAI CIMATEC, 2026.", col = "#000000", font = 1, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 3.6
        graphics::text(30, y_ficha, "1. Financiamento. 2. Fomento à pesquisa. 3. Bolsas. 4. Projetos de Pesquisa Desenvolvimento e", col = "#000000", font = 1, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 3.6
        graphics::text(30, y_ficha, "Inovação. 5. Núcleo de Economia Industrial.", col = "#000000", font = 1, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 3.6
        graphics::text(30, y_ficha, "Publicação Interna do SENAI CIMATEC. É permitida a reprodução deste texto e dos dados nele", col = "#000000", font = 1, cex = 0.68, adj = 0)
        y_ficha <- y_ficha - 3.6
        graphics::text(30, y_ficha, "contidos, desde que citada a fonte. Reproduções para fins comerciais são proibidas.", col = "#000000", font = 1, cex = 0.68, adj = 0)
      }

      # 5. Número da Página no canto inferior direito
      graphics::text(180, 22, as.character(page_num), col = "#000000", font = 1, cex = 0.95, adj = 1)
    }
  })

  # 6. Injeta os links clicáveis (/Subtype /Link /URI) diretamente nos objetos de página do PDF
  tryCatch(inject_pdf_uri_links(output_pdf, page_links), error = function(e) {
    warning("[PDF] Aviso ao injetar links clicáveis no PDF: ", e$message)
  })

  return(TRUE)
}
