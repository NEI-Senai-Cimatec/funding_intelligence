from curl_cffi import requests
from bs4 import BeautifulSoup

alt_urls = {
    'bndes_editais': 'https://www.bndes.gov.br/wps/portal/site/home/onde-estamos/licitacoes-e-compras/editais',
    'bndes_chamadas': 'https://www.bndes.gov.br/wps/portal/site/home/financiamento/chamadas-publicas/todas-as-chamadas',
    'facepe_main': 'https://www.facepe.br/editais/',
    'facepe_noticias': 'https://www.facepe.br/noticias/',
    'fapeal': 'https://fapeal.br/editais/',
    'fapema': 'https://www.fapema.br/editais/',
    'sebrae_editais': 'https://sebrae.com.br/sites/PortalSebrae/canais_adicionais/conheca_editais',
    'senai_plataforma': 'https://www.portaldaindustria.com.br/senai/canais/plataforma-de-inovacao-para-a-industria/',
    'transferegov_home': 'https://www.gov.br/transferegov/pt-br',
    'hubine_bnb': 'https://www.bnb.gov.br/hubine',
    'euspa_tenders': 'https://www.euspa.europa.eu/opportunities/calls-proposals'
}

for name, url in alt_urls.items():
    try:
        r = requests.get(url, impersonate="chrome120", timeout=12, verify=False)
        print(f"[{name}] Status: {r.status_code}, Length: {len(r.content)}")
        if r.status_code == 200:
            soup = BeautifulSoup(r.text, 'html.parser')
            t = soup.title.string.strip() if soup.title else 'No Title'
            print(f"   Title: {t[:60]}")
    except Exception as e:
        print(f"[{name}] Error: {e}")
