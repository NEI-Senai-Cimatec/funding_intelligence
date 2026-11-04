#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Preenche o template Word institucional (templates/modelo_editais.docx)
com até 3 editais selecionados para o relatório, adicionando hyperlinks
clicáveis no campo 'Link de acesso' e suportando conversão direta para PDF.
"""

import sys
import json
import os
import subprocess
import xml.sax.saxutils

try:
    import docx
    from docx.oxml import parse_xml
    from docx.opc.constants import RELATIONSHIP_TYPE
except ImportError:
    print("ERRO: Pacote python-docx nao encontrado. Instale com: pip install python-docx", file=sys.stderr)
    sys.exit(1)

def add_hyperlink(paragraph, url, text, font_name="Calibri", font_size=None, color="004691", underline=True):
    """
    Insere um hyperlink clicável nativo do Word no parágrafo especificado.
    Ao converter para PDF, o leitor de PDF preserva o link clicável.
    """
    part = paragraph.part
    r_id = part.relate_to(url, RELATIONSHIP_TYPE.HYPERLINK, is_external=True)
    escaped_text = xml.sax.saxutils.escape(text)

    font_xml = f'<w:rFonts w:ascii="{font_name}" w:hAnsi="{font_name}"/>' if font_name else ''
    size_xml = f'<w:sz w:val="{int(font_size.pt * 2)}"/>' if font_size and hasattr(font_size, 'pt') else ''
    u_xml = '<w:u w:val="single"/>' if underline else ''
    color_xml = f'<w:color w:val="{color}"/>' if color else ''

    hyperlink_xml = f'''
        <w:hyperlink xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                     xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                     r:id="{r_id}">
            <w:r>
                <w:rPr>
                    {font_xml}
                    {size_xml}
                    {color_xml}
                    {u_xml}
                </w:rPr>
                <w:t>{escaped_text}</w:t>
            </w:r>
        </w:hyperlink>
    '''
    hyperlink = parse_xml(hyperlink_xml)
    paragraph._p.append(hyperlink)
    return hyperlink

def fill_field(p, label, value):
    """
    Garante que o parágrafo inicie com o label em negrito e o valor com peso normal,
    preservando as propriedades de fonte originais do parágrafo.
    """
    str_val = str(value) if value is not None else ""
    if not p.runs:
        r = p.add_run(label + " ")
        r.bold = True
        p.add_run(str_val)
        return

    sample_run = p.runs[0]
    font_name = sample_run.font.name if sample_run.font else None
    font_size = sample_run.font.size if sample_run.font else None

    p.runs[0].text = label + " "
    p.runs[0].bold = True

    if len(p.runs) > 1:
        p.runs[1].text = str_val
        p.runs[1].bold = False
        for r in p.runs[2:]:
            r.text = ""
    else:
        new_r = p.add_run(str_val)
        new_r.bold = False
        if font_name:
            new_r.font.name = font_name
        if font_size:
            new_r.font.size = font_size

def fill_link_field(p, label, link_label, link_url):
    """
    Preenche o campo de link como um hyperlink clicável nativo se houver URL válida.
    """
    # Limpa runs existentes
    sample_run = p.runs[0] if p.runs else None
    font_name = sample_run.font.name if sample_run and sample_run.font else "Calibri"
    font_size = sample_run.font.size if sample_run and sample_run.font else None

    p.text = "" # limpa o parágrafo

    r_lbl = p.add_run(label + " ")
    r_lbl.bold = True
    if font_name:
        r_lbl.font.name = font_name
    if font_size:
        r_lbl.font.size = font_size

    url = (link_url or "").strip()
    lbl = (link_label or "").strip()

    if url and url.startswith(("http://", "https://")):
        display_text = lbl if lbl and lbl != "#" else url
        add_hyperlink(p, url, display_text, font_name=font_name, font_size=font_size, color="004691", underline=True)
    else:
        r_val = p.add_run(lbl or url or "Não informado")
        r_val.bold = False
        if font_name:
            r_val.font.name = font_name
        if font_size:
            r_val.font.size = font_size

def convert_docx_to_pdf(docx_path, pdf_path):
    """
    Converte um arquivo .docx para .pdf usando docx2pdf (MS Word COM) no Windows
    ou LibreOffice no Linux.
    """
    docx_path = os.path.abspath(docx_path)
    pdf_path = os.path.abspath(pdf_path)

    # 1. Tenta docx2pdf (utiliza MS Word COM instalado no Windows)
    try:
        from docx2pdf import convert
        convert(docx_path, pdf_path)
        if os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 1000:
            print(f"[PDF] Conversão via docx2pdf concluída com sucesso: {pdf_path}")
            return True
    except Exception as e:
        print(f"[PDF] Falha no docx2pdf: {e}", file=sys.stderr)

    # 2. Tenta LibreOffice em modo headless (comum em servidores Linux / Docker)
    soffice_cmd = None
    for cmd in ["soffice", "libreoffice", r"C:\Program Files\LibreOffice\program\soffice.exe"]:
        try:
            res = subprocess.run([cmd, "--version"], capture_output=True, text=True)
            if res.returncode == 0:
                soffice_cmd = cmd
                break
        except Exception:
            continue

    if soffice_cmd:
        try:
            out_dir = os.path.dirname(pdf_path)
            cmd = [soffice_cmd, "--headless", "--convert-to", "pdf", docx_path, "--outdir", out_dir]
            subprocess.run(cmd, check=True, capture_output=True)
            # O LibreOffice salva com o mesmo nome base do docx
            base_pdf = os.path.splitext(docx_path)[0] + ".pdf"
            if os.path.exists(base_pdf) and base_pdf != pdf_path:
                if os.path.exists(pdf_path):
                    os.remove(pdf_path)
                os.rename(base_pdf, pdf_path)
            if os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 1000:
                print(f"[PDF] Conversão via LibreOffice concluída com sucesso: {pdf_path}")
                return True
        except Exception as e:
            print(f"[PDF] Falha no LibreOffice: {e}", file=sys.stderr)

    # 3. PowerShell Word COM direto no Windows (fallback se docx2pdf falhar)
    if os.name == 'nt':
        try:
            ps_script = f'''
            $word = New-Object -ComObject Word.Application
            $word.Visible = $false
            $doc = $word.Documents.Open("{docx_path}")
            $doc.SaveAs([ref]"{pdf_path}", [ref]17)
            $doc.Close()
            $word.Quit()
            '''
            subprocess.run(["powershell", "-NoProfile", "-Command", ps_script], check=True, capture_output=True)
            if os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 1000:
                print(f"[PDF] Conversão via PowerShell Word COM concluída: {pdf_path}")
                return True
        except Exception as e:
            print(f"[PDF] Falha no PowerShell COM: {e}", file=sys.stderr)

    return False

def fill_docx_report(template_path, output_path, report_data, convert_to_pdf=False):
    if not os.path.exists(template_path):
        raise FileNotFoundError(f"Template DOCX nao encontrado: {template_path}")

    doc = docx.Document(template_path)
    items = report_data.get('items', [])
    # Limita estritamente a 3 editais conforme solicitado
    items = items[:3]
    n_items = len(items)

    # Mapeamento dos 3 slots de parágrafos no template oficial
    slots = [
        {
            'edital': 5, 'tipo': 6, 'pais': 7, 'prazo': 8,
            'area': 9, 'resumo': 10, 'orcamento': 11, 'link': 12
        },
        {
            'edital': 27, 'tipo': 28, 'pais': 29, 'prazo': 30,
            'area': 31, 'resumo': 32, 'orcamento': 33, 'link': 34
        },
        {
            'edital': 54, 'tipo': 55, 'pais': 56, 'prazo': 57,
            'area': 58, 'resumo': 59, 'orcamento': 60, 'link': 61
        }
    ]

    for s_idx, slot in enumerate(slots):
        if s_idx < n_items:
            it = items[s_idx]
            link_url = it.get('link_url', '')
            link_lbl = it.get('link_label', '')

            fill_field(doc.paragraphs[slot['edital']], "Edital:", it.get('edital', ''))
            fill_field(doc.paragraphs[slot['tipo']], "Tipo de oportunidade:", it.get('tipo', ''))
            fill_field(doc.paragraphs[slot['pais']], "País de origem:", it.get('pais', ''))
            fill_field(doc.paragraphs[slot['prazo']], "Prazo limite de submissão:", it.get('prazo', ''))
            fill_field(doc.paragraphs[slot['area']], "Área temática:", it.get('area', ''))
            fill_field(doc.paragraphs[slot['resumo']], "Resumo:", it.get('resumo', ''))
            fill_field(doc.paragraphs[slot['orcamento']], "Orçamento estimado:", it.get('orcamento', ''))
            fill_link_field(doc.paragraphs[slot['link']], "Link de acesso:", link_lbl, link_url)
        else:
            # Limpa placeholders dos slots não utilizados
            for field, p_idx in slot.items():
                if p_idx < len(doc.paragraphs):
                    doc.paragraphs[p_idx].text = ""

    out_dir = os.path.dirname(os.path.abspath(output_path))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    # Determina caminhos de salvamento
    if convert_to_pdf or output_path.lower().endswith(".pdf"):
        # Salva primeiro em DOCX temporário e depois converte para PDF
        tmp_docx = output_path[:-4] + "_temp.docx" if output_path.lower().endswith(".pdf") else output_path + ".docx"
        doc.save(tmp_docx)
        pdf_out = output_path if output_path.lower().endswith(".pdf") else os.path.splitext(output_path)[0] + ".pdf"
        
        ok = convert_docx_to_pdf(tmp_docx, pdf_out)
        try:
            if os.path.exists(tmp_docx):
                os.remove(tmp_docx)
        except Exception:
            pass

        if not ok:
            raise RuntimeError(f"Falha ao converter DOCX para PDF em {pdf_out}")
        print(f"Sucesso: Relatório PDF gerado em {pdf_out}")
    else:
        doc.save(output_path)
        print(f"Sucesso: Relatório DOCX gerado em {output_path}")

def main():
    if len(sys.argv) < 4:
        print("Uso: fill_report_docx.py <template_path> <output_path> <json_data_path> [--pdf]", file=sys.stderr)
        sys.exit(1)

    template_path = sys.argv[1]
    output_path = sys.argv[2]
    json_path = sys.argv[3]
    convert_to_pdf = "--pdf" in sys.argv or output_path.lower().endswith(".pdf")

    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    fill_docx_report(template_path, output_path, data, convert_to_pdf=convert_to_pdf)

if __name__ == '__main__':
    main()
