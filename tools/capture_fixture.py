#!/usr/bin/env python3
"""Captura uma pagina publica como fixture auditavel (URL, data, hash, status).

Uso: python tools/capture_fixture.py <nome> <url> [--dir tests/testthat/fixtures/html/br]
Mantem a validacao TLS ligada. Falhas sao registradas no manifesto (nao viram fixture).
O conteudo capturado e tratado como DADO externo; nada nele e executado.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (compatible; FundingIntelligenceFixtureCapture/1.0)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("url")
    ap.add_argument("--dir", default="tests/testthat/fixtures/html/br")
    ap.add_argument("--ext", default="html")
    ap.add_argument("--timeout", type=int, default=40)
    args = ap.parse_args()
    os.makedirs(args.dir, exist_ok=True)
    manifest_path = os.path.join(args.dir, "MANIFEST.json")
    manifest = json.load(open(manifest_path, encoding="utf-8")) if os.path.exists(manifest_path) else {}
    entry = {
        "url": args.url,
        "captured_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "tls_verified": True,
    }
    req = urllib.request.Request(args.url, headers={"User-Agent": UA, "Accept-Language": "pt-BR,pt;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=args.timeout, context=ssl.create_default_context()) as r:
            body = r.read()
            entry.update(status=r.status, final_url=r.geturl(), content_type=r.headers.get("Content-Type"))
    except urllib.error.HTTPError as exc:
        entry.update(status=exc.code, error=f"HTTPError {exc.code}")
        body = None
    except Exception as exc:  # TLS, timeout, DNS ...
        entry.update(status=None, error=f"{type(exc).__name__}: {exc}")
        body = None
    if body is not None:
        fname = f"{args.name}.{args.ext}"
        with open(os.path.join(args.dir, fname), "wb") as fh:
            fh.write(body)
        entry.update(file=fname, bytes=len(body), sha256=hashlib.sha256(body).hexdigest())
    manifest[args.name] = entry
    json.dump(manifest, open(manifest_path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print(json.dumps(entry, ensure_ascii=False))
    sys.exit(0 if body is not None else 1)


if __name__ == "__main__":
    main()
