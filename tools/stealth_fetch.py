"""Fetch resiliente (curl_cffi com TLS impersonation, depois Playwright).

Contrato (R06):
  * A validação TLS NUNCA é desligada. Certificado inválido/expirado é um estado da
    fonte e é reportado, não contornado.
  * Em falha, grava um JSON de diagnóstico em <output_file>.err.json
    {"kind": "tls_error|http_error|blocked|network_error", "status": int|null, "message": str}
    e termina com exit code != 0.
  * Nunca grava como conteúdo uma página intersticial de erro do navegador.
"""
import json
import os
import sys
import time

url = sys.argv[1] if len(sys.argv) > 1 else ""
output_file = sys.argv[2] if len(sys.argv) > 2 else ""

if not url:
    print("Usage: python stealth_fetch.py <URL> [output_file]")
    sys.exit(1)

html_content = ""
success = False
diag = {"kind": "network_error", "status": None, "message": ""}


def looks_like_interstitial(text: str) -> bool:
    head = text[:4000].lower()
    return any(s in head for s in (
        "sua conexão não é particular", "sua conexao nao e particular",
        "your connection is not private", "err_cert_", "net::err_",
        "just a moment...", "attention required! | cloudflare",
    ))


def classify_exception(exc: Exception) -> str:
    msg = str(exc).lower()
    if any(k in msg for k in ("ssl", "tls", "certificate", "cert_", "handshake")):
        return "tls_error"
    return "network_error"


# Strategy 1: curl_cffi (browser TLS impersonation) COM validação de certificado
try:
    from curl_cffi import requests
    resp = requests.get(url, impersonate="chrome120", timeout=20, verify=True)
    diag["status"] = resp.status_code
    if resp.status_code == 200 and not looks_like_interstitial(resp.text) and "Just a moment..." not in resp.text and len(resp.content) > 800:
        html_content = resp.text
        success = True
        print(f"[STEALTH_FETCH][curl_cffi] Success! Downloaded {len(html_content)} bytes", file=sys.stderr)
    else:
        diag["kind"] = "blocked" if resp.status_code in (401, 403, 429) else "http_error"
        diag["message"] = f"HTTP {resp.status_code}"
        print(f"[STEALTH_FETCH][curl_cffi] Status {resp.status_code}, length {len(resp.content)}. Trying Playwright...", file=sys.stderr)
except Exception as e:
    diag["kind"] = classify_exception(e)
    diag["message"] = str(e)[:300]
    print(f"[STEALTH_FETCH][curl_cffi] Error ({diag['kind']}): {e}. Trying Playwright...", file=sys.stderr)

# Strategy 2: Playwright. Não ignora erros HTTPS; se TLS falhou, não insiste.
if not success and diag["kind"] != "tls_error":
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
                viewport={'width': 1280, 'height': 800},
                ignore_https_errors=False,
            )
            page = context.new_page()
            page.goto(url, wait_until="domcontentloaded", timeout=30000)
            time.sleep(3)  # allow JS execution & Cloudflare redirect
            html_content = page.content()
            browser.close()
            if len(html_content) > 1000 and not looks_like_interstitial(html_content):
                success = True
                print(f"[STEALTH_FETCH][playwright] Success! Downloaded {len(html_content)} bytes", file=sys.stderr)
            else:
                html_content = ""
    except Exception as e:
        if diag["kind"] != "tls_error":
            diag["kind"] = classify_exception(e)
            diag["message"] = str(e)[:300]
        print(f"[STEALTH_FETCH][playwright] Error: {e}", file=sys.stderr)

if success and output_file:
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html_content)
    print(f"[STEALTH_FETCH] Saved HTML to {output_file}", file=sys.stderr)
elif success:
    sys.stdout.buffer.write(html_content.encode('utf-8', errors='ignore'))
else:
    if output_file:
        try:
            with open(output_file + ".err.json", 'w', encoding='utf-8') as f:
                json.dump(diag, f)
        except OSError:
            pass
    print(f"[STEALTH_FETCH] Failed to fetch page content: {diag}", file=sys.stderr)
    sys.exit(1)
