import urllib.request
import urllib.parse
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'application/json'
}

keywords = [
    'sudene',
    'embrapa',
    'codevasf',
    'bnb',
    'dcta',
    'aeb',
    'finep',
    'inovacao'
]

for kw in keywords:
    url = f"https://pncp.gov.br/api/consulta/v1/contratacoes/publicas?q={urllib.parse.quote(kw)}&status=todos&pagina=1&tamanhoPagina=5"
    print(f"\n=================== PNCP API Test: '{kw}' ===================")
    print("URL:", url)
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print("Total records found:", data.get('totalRegistros', 0))
            print("Total pages:", data.get('totalPaginas', 0))
            items = data.get('data', [])
            print(f"Items returned in page 1: {len(items)}")
            for item in items[:3]:
                orgao = item.get('orgaoEntidade', {}).get('razaoSocial', 'N/A')
                objeto = item.get('objeto', 'N/A')
                num = item.get('numeroContratacao', 'N/A')
                ano = item.get('anoContratacao', 'N/A')
                link = item.get('linkSistemaOrigem') or f"https://pncp.gov.br/app/editais/{item.get('orgaoEntidade',{}).get('cnpj')}/{ano}/{num}"
                print(f" - [{orgao}] Ano {ano} Num {num}: {objeto[:100]}...")
                print(f"   Link: {link}")
    except Exception as e:
        print(f"ERROR: {e}")
