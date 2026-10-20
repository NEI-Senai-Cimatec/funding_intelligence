import sqlite3

con = sqlite3.connect('funding_intelligence.sqlite')
cur = con.cursor()

new_sources = [
    (
        "bndes",
        "Banco Nacional de Desenvolvimento Econômico e Social",
        "BNDES",
        "Brasil",
        "banco de desenvolvimento",
        "banco público",
        "https://www.bndes.gov.br/",
        "https://www.bndes.gov.br/wps/portal/site/home/onde-estamos/licitacoes-e-compras/editais",
        "html",
        "pt",
        "semanal",
        "Chamadas públicas e editais BNDES para inovação industrial, BNDES Garagem, FUST (telecom/IoT), Fundo Clima e BNDES Mais Inovação."
    ),
    (
        "esa_solutions",
        "ESA Space Solutions - European Space Agency",
        "ESA Solutions",
        "Europa",
        "agência espacial internacional",
        "organização multilateral",
        "https://business.esa.int/",
        "https://business.esa.int/funding",
        "html",
        "en",
        "semanal",
        "Oportunidades de financiamento direto e chamadas abertas da Agência Espacial Europeia (ESA) para soluções comerciais, satélites, IoT e aplicações terrestres."
    ),
    (
        "nasa_sbir",
        "NASA Small Business Innovation Research / STTR",
        "NASA SBIR",
        "Estados Unidos",
        "agência espacial",
        "governo federal",
        "https://sbir.nasa.gov/",
        "https://sbir.nasa.gov/solicitations",
        "html",
        "en",
        "mensal",
        "Financiamento de P&D tecnológico da NASA em automação, robótica, sensores avançados, computação embarcada e aeroespacial."
    ),
    (
        "facepe",
        "Fundação de Amparo à Ciência e Tecnologia de Pernambuco",
        "FACEPE",
        "Brasil",
        "fundação estadual de amparo",
        "fundação pública estadual",
        "https://www.facepe.br/",
        "https://www.facepe.br/editais/",
        "html",
        "pt",
        "semanal",
        "Editais e chamadas de P&D e inovação da FACEPE, com forte aderência ao ecossistema de TI, automação, IoT e pólos tecnológicos do Nordeste."
    ),
    (
        "funcap",
        "Fundação Cearense de Apoio ao Desenvolvimento Científico e Tecnológico",
        "FUNCAP",
        "Brasil",
        "fundação estadual de amparo",
        "fundação pública estadual",
        "https://www.funcap.ce.gov.br/",
        "https://www.funcap.ce.gov.br/editais/",
        "html",
        "pt",
        "semanal",
        "Fomento à pesquisa científica, inovação tecnológica, hubs de inteligência artificial e hardware/software no Ceará/Nordeste."
    ),
    (
        "fapeal",
        "Fundação de Amparo à Pesquisa do Estado de Alagoas",
        "FAPEAL",
        "Brasil",
        "fundação estadual de amparo",
        "fundação pública estadual",
        "https://fapeal.br/",
        "https://fapeal.br/editais/",
        "html",
        "pt",
        "mensal",
        "Editais de pesquisa e desenvolvimento tecnológico da FAPEAL para pesquisadores e ICTs regionais."
    ),
    (
        "fapema",
        "Fundação de Amparo à Pesquisa e ao Desenvolvimento Científico e Tecnológico do Maranhão",
        "FAPEMA",
        "Brasil",
        "fundação estadual de amparo",
        "fundação pública estadual",
        "https://www.fapema.br/",
        "https://www.fapema.br/editais/",
        "html",
        "pt",
        "mensal",
        "Chamadas e editais da FAPEMA para ciência, tecnologia e inovação no Maranhão e integração Nordeste."
    ),
    (
        "transferegov",
        "Portal Transferegov.br - Convênios e Programas Federais",
        "Transferegov",
        "Brasil",
        "portal federal de convênios",
        "governo federal",
        "https://www.gov.br/transferegov/pt-br",
        "https://www.gov.br/transferegov/pt-br",
        "html",
        "pt",
        "diária",
        "Portal unificado de captação e repasse de recursos voluntários da União, descentralização de recursos (TEDs), emendas e programas governamentais para ICTs."
    ),
    (
        "bnb_hubine",
        "Banco do Nordeste - Hub de Inovação (Hubine)",
        "Hubine BNB",
        "Brasil",
        "hub de inovação bancário",
        "banco público",
        "https://www.bnb.gov.br/hubine",
        "https://www.bnb.gov.br/hubine",
        "html",
        "pt",
        "mensal",
        "Hub de inovação do BNB para conexão com startups, aceleração, linhas de financiamento de inovação e programas de empreendedorismo do Nordeste."
    ),
    (
        "sebrae",
        "SEBRAE Inovação & Sebraetec",
        "SEBRAE",
        "Brasil",
        "serviço social autônomo",
        "sistema s",
        "https://sebrae.com.br/",
        "https://sebrae.com.br/sites/PortalSebrae/canais_adicionais/conheca_editais",
        "html",
        "pt",
        "semanal",
        "Editais de inovação do SEBRAE para MPEs, programas Sebraetec (automação e digitalização), Catalisa ICT e conexões universidade-empresa."
    ),
    (
        "softex",
        "Associação SOFTEX - Programas Prioritários MCTI",
        "SOFTEX",
        "Brasil",
        "organização social de ti",
        "associação civil",
        "https://softex.br/",
        "https://softex.br/editais/",
        "html",
        "pt",
        "semanal",
        "Editais e chamadas dos Programas Prioritários da Lei de Informática / MCTI para Inteligência Artificial, Ciência de Dados, IoT e Indústria 4.0."
    )
]

sql = """
INSERT INTO fontes_financiamento (
    id_fonte, nome_fonte, sigla, pais, categoria, tipo_financiador,
    url_principal, url_oportunidades, metodo_coleta, idioma,
    periodicidade_atualizacao, observacoes
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id_fonte) DO UPDATE SET
    nome_fonte = excluded.nome_fonte,
    sigla = excluded.sigla,
    pais = excluded.pais,
    categoria = excluded.categoria,
    tipo_financiador = excluded.tipo_financiador,
    url_principal = excluded.url_principal,
    url_oportunidades = excluded.url_oportunidades,
    metodo_coleta = excluded.metodo_coleta,
    idioma = excluded.idioma,
    periodicidade_atualizacao = excluded.periodicidade_atualizacao,
    observacoes = excluded.observacoes
"""

for s in new_sources:
    cur.execute(sql, s)
    print(f"Upserted source: {s[0]} ({s[2]})")

con.commit()

total = cur.execute("SELECT COUNT(*) FROM fontes_financiamento").fetchone()[0]
print(f"\nTotal sources in DB now: {total}")

con.close()
