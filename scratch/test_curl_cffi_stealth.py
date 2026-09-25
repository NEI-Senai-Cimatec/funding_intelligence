from curl_cffi import requests

urls = {
    'sudene': 'https://pncp.gov.br/app/editais?q=533014&status=todos&pagina=1&tam_pagina=100&tipos=1',
    'embrapa': 'https://www.embrapa.br/acessoainformacao/editais',
    'codevasf': 'https://www.codevasf.gov.br/acesso-a-informacao/licitacoes-e-editais',
    'bnb_fundeci': 'https://www.bnb.gov.br/ConveniosWeb/Convenente.ProgramaConvenio.Lista.aspx',
    'fab_dcta': 'https://ieav.dcta.mil.br/index.php/editais',
    'finep_aero': 'https://www.finep.gov.br/oportunidades',
    'aeb': 'https://www.gov.br/aeb/pt-br/acesso-a-informacao/concurso-e-processos-seletivos',
    'doe_ascr': 'https://science.osti.gov/ascr/Funding-Opportunities'
}

for name, url in urls.items():
    print(f"\n=================== Testing {name}: {url} ===================")
    try:
        resp = requests.get(url, impersonate="chrome120", timeout=12, verify=False)
        print(f"Status: {resp.status_code}")
        print(f"Content length: {len(resp.content)} bytes")
        snippet = resp.text[:300].replace('\n', ' ').strip()
        print(f"Snippet: {snippet}")
        
        # Check if Cloudflare challenge was passed
        if "Just a moment..." in resp.text:
            print("RESULT: Cloudflare challenge detected (requires JS renderer or Turnstile solver)")
        elif resp.status_code == 200:
            print("RESULT: SUCCESS! Page fetched cleanly with browser impersonation!")
        else:
            print(f"RESULT: Failed with status {resp.status_code}")
    except Exception as e:
        print(f"ERROR: {e}")
