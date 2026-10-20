#!/usr/bin/env python3
"""
tools/clean_database.py
Saneia a base de dados (SQLite local e Supabase REST), removendo definitivamente
registros que não são editais de fomento/pesquisa/inovação (redes sociais, menus,
páginas administrativas, portarias, modelos de documento, tópicos gerais).
"""

import sqlite3
import urllib.request
import json
import re
import sys

SUPABASE_URL = "https://jsystdrhtcoopjkrcwql.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpzeXN0ZHJodGNvb3Bqa3Jjd3FsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA4Njk5MzksImV4cCI6MjEwNjQ0NTkzOX0.2zCgYRema1h-KAz7ibQmoJfrmvVfoJTjMaKBeB18j98"

def is_garbage_record(row):
    id_reg = row['id_registro']
    t = (row['titulo'] or '').strip()
    t_lower = t.lower()
    t_clean = re.sub(r'[^a-z0-9 ]', '', t_lower)
    u = (row['link_detalhe'] or row['link_origem'] or '').strip()
    u_lower = u.lower()
    src = (row['fonte_oficial'] or '').strip().lower()
    
    # 1. Synthetic Seeds
    if id_reg in ['seed_1', 'seed_2']:
        return True, "Seed demonstrativo sintético"

    # 2. Social Media URLs or Titles
    social_domains = ['instagram.com', 'twitter.com', 'x.com', 'youtube.com', 'youtu.be', 'facebook.com', 'linkedin.com', 'flickr.com', 'tiktok.com']
    if any(sd in u_lower for sd in social_domains):
        return True, "Rede social (link externo)"
    if t_clean in ['instagram', 'twitter', 'fapealoficial', 'fapema oficial', 'a fapemig', 'youtube', 'facebook']:
        return True, "Rede social (título de perfil)"

    # 3. Admin / Login / Internal / Ombudsman
    admin_patterns = ['wp-admin', 'login.microsoft', 'demonstrativo_bolsa', 'e-ouv.al.gov.br', 'everest.fapemig.br', 'sig.fapesc.sc.gov.br', 'govdelivery.com', 'fapescgov.sharepoint.com', 'sbirpartnering.org']
    if any(ap in u_lower for ap in admin_patterns):
        return True, "Sistema de login / administrativo / ouvidoria"
    if t_clean in ['admin', 'restrito', 'ouvidoria', 'faplan demonstrativo de rendimentos', 'everest', 'plataforma fapesc']:
        return True, "Página de login / demonstrativo interno / ouvidoria"

    # 4. State FAPs without structural call scrapers that swallowed navigation menus
    if src == 'fapeal':
        return True, "FAPEAL: Link de navegação/redes (não é chamada)"
    if src == 'facepe':
        return True, "FACEPE: Menu institucional (não é chamada)"
    if src == 'fapesc':
        return True, "FAPESC: Menu/Página institucional (não é chamada)"
    if src == 'softex':
        return True, "SOFTEX: Página institucional/instituto (não é chamada)"

    # FAPEMA
    if src == 'fapema':
        if not t_lower.startswith('normas de apresentacao'):
            return True, "FAPEMA: Menu/Resoluções/Documento (não é chamada)"

    # FAPEMIG
    if src == 'fapemig':
        valid_fapemig = ['categoria a', '17/2026', '004/2026', '007/2026']
        if not any(v in t_lower for v in valid_fapemig):
            return True, "FAPEMIG: Menu/Página institucional (não é chamada)"

    # 5. CAPES (Templates, declarations, portarias, enrollment lists)
    if src == 'capes':
        if any(w in t_lower for w in ['portaria', 'modelo de projeto', 'declaracao de reconhecimento', 'relacao das inscricoes', 'programas de pos-graduacao que aderiram']):
            return True, "CAPES: Portaria / Modelo de documento / Lista de inscritos"

    # 6. ANP / Shell (fuel price subsidies, administrative services, document folders)
    if src == 'anp_shell':
        return True, "ANP: Subsídio de combustível ou contrato administrativo (não é edital P&D)"

    # 7. International Portals & Non-calls
    if src == 'neh' and u_lower in ['https://www.neh.gov/grants', 'https://www.neh.gov/grants/']:
        return True, "NEH: Página raiz de busca (não é oportunidade específica)"

    if src in ['nsf_international', 'nsf_cise']:
        if any(p in u_lower for p in ['/proposals-with-international', '/preparing-proposal', '/policies/pappg', 'research.gov', '/funding$', '/funding/opportunities$', '/cise/cyber-physical', '/cise/human-centered', '/cise/software-systems', '/cise/center-scale', '/cise/office-advanced', '/cise/computing-ai']) or u_lower == 'https://www.nsf.gov/cise':
            return True, "NSF: Guia de submissão / Divisão institucional / Página de busca"
        if t_clean in ['funding search', 'funding at nsf', 'preparing your proposal', 'researchgov grants management for nsf community', 'nsf proposal  award policies  procedures guide pappg', 'information for proposals with international collaborators']:
            return True, "NSF: Guia de submissão ou página de busca"

    if src in ['doe_genesis', 'doe_quantum_genesis']:
        if any(topic in u_lower for topic in ['/topics/', '/leadership-organization', 'govdelivery.com', '/internships-fellowships', '/doe-affiliated-nobel', '/funding-opportunities', '/collection/filter', 'fastcompany.com']):
            return True, "DOE: Tópicos gerais energy.gov / Inscrição newsletter / Artigo de revista"
        if t_clean in ['the genesis mission', 'powering today transforming tomorrow', 'subscribe', 'funding opportunities', 'internships  fellowships', 'doeaffiliated nobel prize laureates', 'learn more about funding opportunities']:
            return True, "DOE: Página institucional / Portal geral"

    if src == 'nasa_sbir':
        if any(p in u_lower for p in ['stmd-solicitations-and-opportunities', 'sbirpartnering.org', 'nasa-awards-enable-research']):
            return True, "NASA: Portal geral / Portal de parceiros / Notícia"

    if src == 'undp' and 'vehicle rental' in t_lower:
        return True, "UNDP: Aluguel de veículos (fora do escopo)"

    return False, "Válido"

def clean_database():
    sqlite_path = 'funding_intelligence.sqlite'
    conn = sqlite3.connect(sqlite_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    
    rows = cur.execute("SELECT id_registro, fonte_oficial, titulo, descricao_resumida, link_detalhe, link_origem FROM oportunidades").fetchall()
    print(f"[Limpeza] Total de registros atuais no SQLite: {len(rows)}")
    
    garbage_records = []
    for r in rows:
        row_dict = dict(r)
        is_bad, reason = is_garbage_record(row_dict)
        if is_bad:
            garbage_records.append((row_dict['id_registro'], row_dict['fonte_oficial'], row_dict['titulo'], reason))
            
    print(f"[Limpeza] Identificados {len(garbage_records)} registros inválidos/não-editais para exclusão.")
    
    if len(garbage_records) == 0:
        print("[Limpeza] Base já está limpa!")
        conn.close()
        return

    garbage_ids = [r[0] for r in garbage_records]
    
    # 1. Deletar do SQLite local
    print(f"[Limpeza] Deletando {len(garbage_ids)} registros de {sqlite_path}...")
    placeholders = ', '.join(['?'] * len(garbage_ids))
    cur.execute(f"DELETE FROM oportunidades WHERE id_registro IN ({placeholders})", garbage_ids)
    conn.commit()
    
    remaining_sqlite = cur.execute("SELECT count(*) FROM oportunidades").fetchone()[0]
    print(f"[Limpeza] SQLite saneado com sucesso! Restantes: {remaining_sqlite} oportunidades válidas.")
    conn.close()
    
    # 2. Deletar do Supabase REST API
    print(f"[Limpeza] Sincronizando exclusões no Supabase PostgreSQL...")
    batch_size = 50
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {SUPABASE_KEY}',
        'Content-Type': 'application/json'
    }
    
    deleted_remote = 0
    for i in range(0, len(garbage_ids), batch_size):
        chunk = garbage_ids[i:i + batch_size]
        id_filter = ','.join(chunk)
        url = f"{SUPABASE_URL}/rest/v1/oportunidades?id_registro=in.({id_filter})"
        
        req = urllib.request.Request(url, headers=headers, method='DELETE')
        try:
            with urllib.request.urlopen(req) as resp:
                if resp.status in (200, 204):
                    deleted_remote += len(chunk)
                    print(f"  - Deletado lote {i + 1} a {min(i + batch_size, len(garbage_ids))} no Supabase.")
        except Exception as e:
            print(f"  - Aviso no lote {i}: {e}")
            
    # Verificar contagem final no Supabase
    count_req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/oportunidades?select=id_registro",
        headers={**headers, 'Range': '0-0', 'Prefer': 'count=exact'}
    )
    try:
        with urllib.request.urlopen(count_req) as resp:
            cr = resp.headers.get('Content-Range')
            print(f"[Limpeza] Supabase PostgreSQL verificado! Content-Range: {cr}")
    except Exception as e:
        print(f"[Limpeza] Erro ao consultar contagem no Supabase: {e}")
        
    print(f"[Limpeza] Concluída com sucesso! Total saneado: {remaining_sqlite} editais reais.")

if __name__ == '__main__':
    clean_database()
