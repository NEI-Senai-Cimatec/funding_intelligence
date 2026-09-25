from curl_cffi import requests
from bs4 import BeautifulSoup
import re

candidate_urls = {
    'bndes': 'https://www.bndes.gov.br/wps/portal/site/home/financiamento/chamadas-publicas',
    'facepe': 'http://www.facepe.br/editais/abertos/',
    'funcap': 'https://www.funcap.ce.gov.br/editais/',
    'transferegov': 'https://www.gov.br/transferegov/pt-br/programas',
    'nasa_sbir': 'https://sbir.nasa.gov/solicitations',
    'esa_solutions': 'https://business.esa.int/funding',
    'euspa': 'https://www.euspa.europa.eu/opportunities/funding-and-tenders',
    'senai_inovacao': 'https://plataformadeinovacao.com.br/',
    'sebrae': 'https://catalisaict.sebrae.com.br/',
    'softex': 'https://softex.br/editais/',
    'fbb': 'https://fundacaobb.org.br/pt-br/editais'
}

for name, url in candidate_urls.items():
    print(f"\n--- Testing {name}: {url} ---")
    try:
        resp = requests.get(url, impersonate="chrome120", timeout=12, verify=False)
        print(f"Status: {resp.status_code}, Bytes: {len(resp.content)}")
        if resp.status_code == 200:
            soup = BeautifulSoup(resp.text, 'html.parser')
            title = soup.title.string.strip() if soup.title else 'No Title'
            print("Title:", title[:80])
            links = soup.find_all('a', href=True)
            print("Total links:", len(links))
        else:
            print("Non-200 status code.")
    except Exception as e:
        print(f"Error: {e}")
