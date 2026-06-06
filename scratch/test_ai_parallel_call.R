source("R/helpers_utils.R")
source("R/helpers_ai.R")

library(httr2)
library(jsonlite)

text <- paste(
  "O objetivo da FINEP com este edital é financiar o desenvolvimento de foguetes no Brasil.",
  "A FINEP vai apoiar projetos com valor total de fomento de R$ 5.000.000,00.",
  "A seleção será feita em lotes de 12 empresas de cada vez."
)

current_info <- list(
  titulo_limpo = "Edital de Desenvolvimento de Foguetes Aeroespaciais",
  tipo_oportunidade = NA_character_,
  status_oportunidade = NA_character_,
  idioma = NA_character_
)

prompt <- paste(
  "Você é um agente especialista em extração de dados de editais de fomento.",
  "Analise o texto bruto do edital fornecido e extraia as seguintes informações estruturadas.",
  "Retorne OBRIGATORIAMENTE um JSON válido com os seguintes campos:",
  "- titulo_limpo: Título do edital sem caracteres especiais ou abreviações confusas.",
  "- resumo: Um resumo conciso do edital (máximo 3 parágrafos). ATENÇÃO: Foque no OBJETO DE FINANCIAMENTO (o que o edital está financiando e seus objetivos principais). Evite repetir menus do site, cabeçalhos, introduções genéricas ou links de navegação.",
  "- elegibilidade: Quem pode se candidatar (ex: ICTs, startups, pesquisadores individuais).",
  "- area_tematica: Principais áreas de conhecimento englobadas.",
  "- tipo_oportunidade: Categoria do fomento (ex: edital, grant, fellowship, licitação).",
  "- status_oportunidade: Status atual (aberto, encerrado, futuro).",
  "- idioma: Idioma oficial do edital (pt, en, etc.).",
  "- data_limite: Data máxima de submissão no formato AAAA-MM-DD (ou null se indefinida).",
  "- data_publicacao: Data de publicação no formato AAAA-MM-DD (ou null).",
  "- valor_financiado: O valor máximo ou global de financiamento do edital como número (ex: 150000.00, ou null se não houver valor explícito de fomento ou bolsa no texto). Ignore números que representem quantidades de itens (ex: '12 laranjas'), números de leis, portarias ou telefones.",
  "- moeda: A moeda correspondente ao valor financiado em código de 3 letras (ex: 'BRL', 'USD', 'EUR', 'GBP' ou null se valor_financiado for null).",
  "- palavras_chave: Exatamente 5 palavras-chave ou termos separados por vírgula que caracterizam o edital. ATENÇÃO: As palavras-chave devem refletir de fato o objeto de fomento e a tecnologia/temas do edital (ex: 'energia solar', 'inteligência artificial'). Evite termos genéricos como 'edital', 'chamada', 'pesquisa', 'fomento' ou o nome da instituição financiadora.",
  "- observacoes: Qualquer detalhe ou restrição relevante do edital.",
  "",
  "Contexto primário conhecido:", jsonlite::toJSON(current_info, auto_unbox = TRUE, null = "null"),
  "",
  "Texto do Edital:", trim_for_ai(text)
)

message("--- CHAMANDO AI_REQUEST_PARALLEL ---")
res <- ai_request_parallel(list(prompt))
print(res)
