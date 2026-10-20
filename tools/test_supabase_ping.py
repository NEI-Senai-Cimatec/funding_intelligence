#!/usr/bin/env python3
"""
Testa a conectividade e o endpoint de keep-alive do Supabase para o Radar da Inovação.
Pode ser executado localmente para validar se o projeto foi reativado com sucesso.
"""
import os
import sys
import json
import urllib.request
import urllib.error

# Garante suporte a UTF-8 em terminais Windows
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://jsystdrhtcoopjkrcwql.supabase.co").rstrip("/")
SUPABASE_ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpzeXN0ZHJodGNvb3Bqa3Jjd3FsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA4Njk5MzksImV4cCI6MjEwNjQ0NTkzOX0.2zCgYRema1h-KAz7ibQmoJfrmvVfoJTjMaKBeB18j98"
)

def ping_endpoint(name, url, headers):
    print(f"\n--- Testando {name} ---")
    print(f"URL: {url}")
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = resp.status
            body = resp.read().decode("utf-8")
            print(f"HTTP Status: {status}")
            print(f"Resposta: {body[:300]}")
            return status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8") if e.fp else ""
        print(f"HTTP Status: {e.code}")
        print(f"Resposta de erro: {body[:300]}")
        return e.code, body
    except Exception as e:
        print(f"Erro de conexao: {e}")
        return 0, str(e)

def main():
    print("=" * 60)
    print(" Verificando Status do Supabase - Radar da Inovacao")
    print("=" * 60)
    print(f"Projeto: {SUPABASE_URL}")

    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "User-Agent": "RadarInovacao-KeepAlive/1.0"
    }

    # 1. PostgREST
    status_db, _ = ping_endpoint(
        "PostgREST (Tabela 'perfis')",
        f"{SUPABASE_URL}/rest/v1/perfis?select=id&limit=1",
        headers
    )

    # 2. Auth GoTrue
    status_auth, _ = ping_endpoint(
        "Supabase Auth Healthcheck",
        f"{SUPABASE_URL}/auth/v1/health",
        headers
    )

    print("\n" + "=" * 60)
    if status_db in (200, 206) or status_auth == 200:
        print("✅ PROJETO ATIVO! As chamadas foram respondidas com sucesso.")
        print("   O timer de inatividade de 7 dias foi reiniciado.")
        sys.exit(0)
    elif status_db == 521 or status_auth == 521:
        print("⚠️ PROJETO PAUSADO (HTTP 521).")
        print("   Entre em https://supabase.com/dashboard e clique em 'Resume project'.")
        sys.exit(1)
    else:
        print("❌ Resposta inesperada do Supabase.")
        sys.exit(1)

if __name__ == "__main__":
    main()
