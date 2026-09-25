from curl_cffi import requests
from bs4 import BeautifulSoup
import re

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
    print(f"\n=================== SCRAPING {name.upper()} ({url}) ===================")
    try:
        resp = requests.get(url, impersonate="chrome120", timeout=15, verify=False)
        print(f"HTTP Status: {resp.status_code}, Bytes: {len(resp.content)}")
        if resp.status_code == 200:
            soup = BeautifulSoup(resp.text, 'html.parser')
            title = soup.title.string.strip() if soup.title else 'No Title'
            print("Page Title:", title)
            
            # Extract links and text
            links = soup.find_all('a', href=True)
            print(f"Total links on page: {len(links)}")
            
            found = 0
            for a in links:
                txt = a.get_text(strip=True)
                href = a['href']
                if len(txt) > 8 and not re.search(r'acessibilidade|governo|mapa|login|transparência|ir para', txt, re.I):
                    if re.search(r'edital|chamada|programa|seleção|licitação|portaria|subvenção|pesquisa|oportunidade|convênio|concurso', txt + ' ' + href, re.I):
                        found += 1
                        if found <= 5:
                            print(f"   [EDITAL LINK #{found}] {txt[:80]} ==> {href}")
            print(f"Total candidate edital links found: {found}")
    except Exception as e:
        print(f"ERROR: {e}")
