#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Preenche o template Word institucional (templates/modelo_editais.docx)
com os editais selecionados para o relatório.
"""

import sys
import json
import os

try:
    import docx
    from docx.enum.text import WD_BREAK
except ImportError:
    print("ERRO: Pacote python-docx nao encontrado. Instale com: pip install python-docx", file=sys.stderr)
    sys.exit(1)

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

    # Salva tamanho e nome de fonte se presentes
    sample_run = p.runs[0]
    font_name = sample_run.font.name if sample_run.font else None
    font_size = sample_run.font.size if sample_run.font else None

    # Primeiro run recebe o label em negrito
    p.runs[0].text = label + " "
    p.runs[0].bold = True

    if len(p.runs) > 1:
        p.runs[1].text = str_val
        p.runs[1].bold = False
        # Limpa eventuais runs quebrados subsequentes
        for r in p.runs[2:]:
            r.text = ""
    else:
        new_r = p.add_run(str_val)
        new_r.bold = False
        if font_name:
            new_r.font.name = font_name
        if font_size:
            new_r.font.size = font_size

def fill_docx_report(template_path, output_path, report_data):
    if not os.path.exists(template_path):
        raise FileNotFoundError(f"Template DOCX nao encontrado: {template_path}")

    doc = docx.Document(template_path)
    items = report_data.get('items', [])
    n_items = len(items)

    # Mapeamento dos slots de parágrafos no template oficial
    # Slot 1: Parágrafos P[5] a P[12]
    # Slot 2: Parágrafos P[27] a P[34] (trata typo do template original que tinha resumo_1)
    # Slot 3: Parágrafos P[54] a P[61]
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
            if link_url and link_url != '#':
                link_str = f"{link_lbl} ({link_url})"
            else:
                link_str = link_lbl

            fill_field(doc.paragraphs[slot['edital']], "Edital:", it.get('edital', ''))
            fill_field(doc.paragraphs[slot['tipo']], "Tipo de oportunidade:", it.get('tipo', ''))
            fill_field(doc.paragraphs[slot['pais']], "País de origem:", it.get('pais', ''))
            fill_field(doc.paragraphs[slot['prazo']], "Prazo limite de submissão:", it.get('prazo', ''))
            fill_field(doc.paragraphs[slot['area']], "Área temática:", it.get('area', ''))
            fill_field(doc.paragraphs[slot['resumo']], "Resumo:", it.get('resumo', ''))
            fill_field(doc.paragraphs[slot['orcamento']], "Orçamento estimado:", it.get('orcamento', ''))
            fill_field(doc.paragraphs[slot['link']], "Link de acesso:", link_str)
        else:
            # Limpa placeholders dos slots não utilizados
            for field, p_idx in slot.items():
                if p_idx < len(doc.paragraphs):
                    doc.paragraphs[p_idx].text = ""

    # Se houver 4º edital, insere um bloco adicional formatado antes das citações finais
    if n_items >= 4:
        it = items[3]
        link_url = it.get('link_url', '')
        link_lbl = it.get('link_label', '')
        if link_url and link_url != '#':
            link_str = f"{link_lbl} ({link_url})"
        else:
            link_str = link_lbl

        # Insere antes da seção de citações (P[62])
        p_target = doc.paragraphs[62] if len(doc.paragraphs) > 62 else doc.paragraphs[-1]
        p_target.insert_paragraph_before("____________________________________________________________")
        
        # Quebra de página para o 4º edital ficar em página dedicada e harmoniosa
        p_pb = p_target.insert_paragraph_before()
        r_pb = p_pb.add_run()
        r_pb.add_break(WD_BREAK.PAGE)

        # Cabeçalho institucional QuIIN
        p_h = p_target.insert_paragraph_before(doc.paragraphs[0].text)
        p_h.style = doc.paragraphs[0].style
        p_target.insert_paragraph_before("")

        # 8 Campos do edital 4
        fill_field(p_target.insert_paragraph_before(), "Edital:", it.get('edital', ''))
        fill_field(p_target.insert_paragraph_before(), "Tipo de oportunidade:", it.get('tipo', ''))
        fill_field(p_target.insert_paragraph_before(), "País de origem:", it.get('pais', ''))
        fill_field(p_target.insert_paragraph_before(), "Prazo limite de submissão:", it.get('prazo', ''))
        fill_field(p_target.insert_paragraph_before(), "Área temática:", it.get('area', ''))
        fill_field(p_target.insert_paragraph_before(), "Resumo:", it.get('resumo', ''))
        fill_field(p_target.insert_paragraph_before(), "Orçamento estimado:", it.get('orcamento', ''))
        fill_field(p_target.insert_paragraph_before(), "Link de acesso:", link_str)

    # Cria diretório de destino se não existir
    out_dir = os.path.dirname(os.path.abspath(output_path))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    doc.save(output_path)
    print(f"Sucesso: Relatório DOCX gerado em {output_path}")

def main():
    if len(sys.argv) < 4:
        print("Uso: fill_report_docx.py <template_path> <output_path> <json_data_path>", file=sys.stderr)
        sys.exit(1)

    template_path = sys.argv[1]
    output_path = sys.argv[2]
    json_path = sys.argv[3]

    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    fill_docx_report(template_path, output_path, data)

if __name__ == '__main__':
    main()
