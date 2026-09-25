import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'application/json'
}

test_urls = [
    'https://pncp.gov.br/api/pncp/v1/orgaos/09533014000108/contratacoes/2024',
    'https://pncp.gov.br/api/pncp/v1/orgaos',
    'https://pncp.gov.br/api/consulta/v1/contratacoes/publicas',
    'https://pncp.gov.br/api/pncp/v1/contratacoes/publicas',
    'https://pncp.gov.br/api/consulta/v1/contratacoes/usuario',
    'https://pncp.gov.br/api/search/v1/contratacoes?q=sudene',
    'https://pncp.gov.br/api/pncp/v1/contratacoes/proposta-aberta'
]

for url in test_urls:
    print(f"\n--- Testing: {url} ---")
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            print("Status:", resp.status)
            content = resp.read()[:300]
            print("Body snippet:", content.decode('utf-8', errors='ignore'))
    except Exception as e:
        print("Error:", e)
