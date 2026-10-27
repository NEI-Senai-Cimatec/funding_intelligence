#!/usr/bin/env python3
"""
tools/update_startups_campus.py
Atualiza a coluna 'campus' dos editais aderentes ao ecossistema de Startups
no banco local SQLite e no Supabase PostgreSQL via REST.
"""

import sqlite3
import urllib.request
import json
import re
import os

SUPABASE_URL = "https://jsystdrhtcoopjkrcwql.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpzeXN0ZHJodGNvb3Bqa3Jjd3FsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA4Njk5MzksImV4cCI6MjEwNjQ0NTkzOX0.2zCgYRema1h-KAz7ibQmoJfrmvVfoJTjMaKBeB18j98"

STARTUP_REGEX = re.compile(
    r'\b(startups?|spin-?off|incubac\w*|acelerac\w*|venture capital|capital semente|seed|mpe|mpos?|microempresa\w*|pequenas? empresas?|inovacao aberta|open innovation|catalisa|pipe|centelha|sinapse|pitch|investidor-?anjo|tracionamento|deeptech|scale-?up)\b',
    re.IGNORECASE
)

def update_sqlite(db_path="funding_intelligence.sqlite"):
    if not os.path.exists(db_path):
        print(f"[SQLite] Arquivo {db_path} não encontrado.")
        return []

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT id_registro, titulo, descricao_resumida, palavras_chave, campus FROM oportunidades")
    rows = cur.fetchall()

    updated = []
    for r in rows:
        id_reg = r['id_registro']
        t = r['titulo'] or ''
        d = r['descricao_resumida'] or ''
        kw = r['palavras_chave'] or ''
        cp = (r['campus'] or '').strip()

        comb = f"{t} {d} {kw}"
        if STARTUP_REGEX.search(comb):
            if not cp or cp == 'Não classificado':
                new_cp = "Startups"
            elif 'startups' not in cp.lower():
                new_cp = f"{cp}; Startups"
            else:
                new_cp = cp

            if new_cp != cp:
                cur.execute("UPDATE oportunidades SET campus = ? WHERE id_registro = ?", (new_cp, id_reg))
                updated.append((id_reg, t, cp, new_cp))

    conn.commit()
    conn.close()
    print(f"[SQLite] {len(updated)} registros atualizados com campus 'Startups'.")
    return updated

def update_supabase(updated_records):
    if not updated_records:
        return

    print(f"[Supabase] Sincronizando {len(updated_records)} registros no Supabase REST...")
    success = 0
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal"
    }

    for id_reg, t, old_cp, new_cp in updated_records:
        url = f"{SUPABASE_URL}/rest/v1/oportunidades?id_registro=eq.{urllib.parse.quote(id_reg)}"
        payload = json.dumps({"campus": new_cp}).encode('utf-8')
        req = urllib.request.Request(url, data=payload, headers=headers, method='PATCH')
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status in (200, 204):
                    success += 1
        except Exception as e:
            print(f"  [Erro] Falha ao atualizar {id_reg}: {e}")

    print(f"[Supabase] {success}/{len(updated_records)} registros atualizados com sucesso.")

if __name__ == '__main__':
    updated = update_sqlite()
    for id_reg, t, old_cp, new_cp in updated[:5]:
        print(f"  - [{id_reg}] '{t[:50]}...': '{old_cp}' -> '{new_cp}'")
    update_supabase(updated)
