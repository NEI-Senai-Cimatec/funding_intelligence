import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Accept': 'application/json'
}

endpoints = [
    'https://pncp.gov.br/api/consulta/v1/contratacoes/proposta-aberta?pagina=1',
    'https://pncp.gov.br/api/pncp/v1/orgaos/09533014000108/contratacoes/2024?pagina=1',
    'https://pncp.gov.br/api/pncp/v1/orgaos/00348003000110/contratacoes/2024?pagina=1',
    'https://pncp.gov.br/api/pncp/v1/orgaos/00399857000126/contratacoes/2024?pagina=1'
]

for ep in endpoints:
    print(f"\n--- Testing: {ep} ---")
    req = urllib.request.Request(ep, headers=headers)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print("Response type:", type(data))
            if isinstance(data, dict):
                print("Keys:", data.keys())
                items = data.get('data', data.get('items', []))
                print(f"Items count: {len(items)}")
                if items:
                    print("Sample item:", items[0].get('objeto') or items[0].get('numeroContratacao'))
            elif isinstance(data, list):
                print(f"List count: {len(data)}")
                if data:
                    print("Sample item:", data[0])
    except Exception as e:
        print("Error:", e)
