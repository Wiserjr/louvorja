"""Catálogo das obras indexadas: os e-books de Ellen G. White e os dos pioneiros
publicados pelo Centro de Pesquisas Ellen G. White (Unasp).

    https://centrowhite.org.br/downloads/ebooks/
    https://centrowhite.org.br/downloads/ebooks-apl/

O app NÃO leva o texto destes livros. A licença dos e-books (página
"Informações sobre este livro" de cada um) é de uso pessoal e proíbe
redistribuir. Por isso o app baixa cada PDF direto do site do Centro White, no
aparelho de quem vai ler — o mesmo download que a pessoa faria pelo navegador —
e o que vai no app é só o índice: em que página e em que posição de cada PDF
está o parágrafo que cita cada versículo.

A posição só vale para o arquivo exato que foi indexado. Por isso cada obra
guarda tamanho e SHA-256: se o Centro White trocar um PDF, o app percebe e
recorre à busca pela própria citação na página (ver ``trechos.dart``), e o
``indexar_obras.py`` precisa rodar de novo.

Campos: arquivo (nome no CDN, sem .pdf), sigla, grupo, prioridade.

A sigla segue o costume das publicações em português (DTN, PP, PR, AA, GC...)
onde ele existe. A prioridade ordena os trechos na tela: primeiro a série
Conflito dos Séculos, que narra a história bíblica livro a livro, depois os
livros de comentário e doutrina, por fim compilações e edições condensadas
(que repetem o texto das obras completas).
"""

CDN = "https://cdn.centrowhite.org.br/home/uploads/2022/11/"

PAGINAS = {
    "egw": "https://centrowhite.org.br/downloads/ebooks/",
    "pioneiros": "https://centrowhite.org.br/downloads/ebooks-apl/",
}

# (arquivo, sigla, prioridade). Menor prioridade aparece antes.
EGW = [
    # Série Conflito dos Séculos
    ("Patriarcas-e-Profetas", "PP", 1),
    ("Profetas-e-Reis", "PR", 1),
    ("O-Desejado-de-Todas-as-Nacoes", "DTN", 1),
    ("Atos-dos-Apostolos", "AA", 1),
    ("O-Grande-Conflito", "GC", 1),
    # Comentário e exposição bíblica
    ("Parabolas-de-Jesus", "PJ", 2),
    ("O-Maior-Discurso-de-Cristo", "MDC", 2),
    ("Historia-da-Redencao", "HR", 2),
    ("Primeiros-Escritos", "PE", 2),
    ("Caminho-a-Cristo", "CC", 2),
    ("Educacao", "Ed", 2),
    ("A-Ciencia-do-Bom-Viver", "CBV", 2),
    ("Cristo-em-Seu-Santuario", "CSS", 2),
    ("Mensagens-Escolhidas-1", "ME1", 3),
    ("Mensagens-Escolhidas-2", "ME2", 3),
    ("Mensagens-Escolhidas-3", "ME3", 3),
    ("Testemunhos-para-a-Igreja-1", "T1", 3),
    ("Testemunhos-para-a-Igreja-2", "T2", 3),
    ("Testemunhos-para-a-Igreja-3", "T3", 3),
    ("Testemunhos-para-a-Igreja-4", "T4", 3),
    ("Testemunhos-para-a-Igreja-5", "T5", 3),
    ("Testemunhos-para-a-Igreja-6", "T6", 3),
    ("Testemunhos-para-a-Igreja-7", "T7", 3),
    ("Testemunhos-para-a-Igreja-8", "T8", 3),
    ("Testemunhos-para-a-Igreja-9", "T9", 3),
    ("Testemunhos-para-Ministros-e-Obreiros-Evangelicos", "TM", 3),
    ("Obreiros-Evangelicos", "OE", 3),
    ("Servico-Cristao", "SC", 3),
    ("Eventos-Finais", "EF", 3),
    ("Fe-e-Obras", "FO", 3),
    ("Santificacao", "San", 3),
    ("Vida-e-Ensinos", "VE", 3),
    ("Evangelismo", "Ev", 3),
    ("Conselhos-para-a-Igreja", "CI", 4),
    ("Conselhos-sobre-Saude", "CS", 4),
    ("Conselhos-sobre-o-Regime-Alimentar", "CRA", 4),
    ("Conselhos-sobre-Educacao", "CE", 4),
    ("Conselhos-sobre-Mordomia", "CSM", 4),
    ("Conselhos-sobre-a-Escola-Sabatina", "CES", 4),
    ("Conselhos-aos-Professores-Pais-e-Estudantes", "CPPE", 4),
    ("Conselhos-aos-Idosos", "CId", 4),
    ("Fundamentos-da-Educacao-Crista", "FEC", 4),
    ("Fundamentos-do-Lar-Cristao", "FLC", 4),
    ("O-Lar-Adventista", "LA", 4),
    ("Orientacao-da-Crianca", "OC", 4),
    ("Mensagens-aos-Jovens", "MJ", 4),
    ("Mente-Carater-e-Personalidade-1", "MCP1", 4),
    ("Mente-Carater-e-Personalidade-2", "MCP2", 4),
    ("Medicina-e-Salvacao", "MS", 4),
    ("Temperanca", "Te", 4),
    ("Beneficencia-Social", "BS", 4),
    ("Lideranca-Crista", "LC", 4),
    ("O-Colportor-Evangelista", "Col", 4),
    ("Testemunhos-Seletos-1", "TS1", 4),
    ("Testemunhos-Seletos-2", "TS2", 4),
    ("Testemunhos-Seletos-3", "TS3", 4),
    ("Testemunhos-Sobre-Conduta-Sexual-Adulterio-e-Divorcio", "TCS", 4),
    ("A-Verdade-sobre-os-Anjos", "VA", 4),
    ("A-Igreja-Remanescente", "IR", 4),
    ("Mensageiros-da-Esperanca", "MEsp", 4),
    ("Vida-no-Campo", "VC", 4),
    ("Visoes-do-Ceu", "VCe", 4),
    ("Licoes-da-Vida-de-Neemias", "LVN", 4),
    ("No-Deserto-da-Tentacao", "NDT", 4),
    ("Reavivamento-e-seus-Resultados", "RR", 4),
    ("Musica-Sua-Influencia-na-Vida-do-Cristao", "Mus", 4),
    ("Como-Lidar-com-as-Emocoes", "CLE", 4),
    ("Cartas-a-Jovens-Namorados", "CJN", 4),
    ("So-para-Jovens", "SPJ", 4),
    ("Filhas-de-Deus", "FD", 4),
    ("O-Outro-Poder", "OP", 4),
    ("Um-Convite-a-Diferenca", "UCD", 4),
    ("Ser-Mae-O-que-e", "SM", 4),
    ("Foi-Por-Voce", "FPV", 4),
    # Meditações matinais (uma por dia, cada uma sobre um versículo)
    ("A-Fe-Pela-Qual-Eu-Vivo", "FEV", 5),
    ("A-Maravilhosa-Graca-de-Deus", "MGD", 5),
    ("Cristo-Triunfante", "CT", 5),
    ("E-Recebereis-Poder", "ERP", 5),
    ("Este-Dia-com-Deus", "EDD", 5),
    ("Exaltai-o", "Exo", 5),
    ("Filhos-e-Filhas-de-Deus", "FFD", 5),
    ("Jesus-Meu-Modelo", "JMM", 5),
    ("Maranata-O-Senhor-Vem", "Mar", 5),
    ("Minha-Consagracao-Hoje", "MCH", 5),
    ("Nos-Lugares-Celestiais", "NLC", 5),
    ("Nossa-Alta-Vocacao", "NAV", 5),
    ("O-Cuidado-de-Deus", "CD", 5),
    ("Olhando-Para-O-Alto", "OPA", 5),
    ("Para-Conhece-lo", "PC", 5),
    ("Refletindo-a-Cristo", "RC", 5),
    ("Vidas-que-Falam", "VQF", 5),
    # Edições condensadas e adaptadas: repetem o texto das completas
    ("O-Grande-Conflito-condensado", "GCc", 6),
    ("A-Ciencia-do-Bom-Viver-condensado", "CBVc", 6),
    ("Caminho-a-Cristo-nova-edicao", "CCn", 6),
    ("Vida-de-Jesus", "VJ", 6),
]

# Pioneiros: (arquivo, sigla, prioridade, autor). Os PDFs da Adventist
# Pioneer Library nem sempre trazem o autor nos metadados.
PIONEIROS = [
    ("Daniel-e-Apocalipse", "DA", 1, "Urias Smith"),
    ("Historia-do-Sabado", "HS", 2, "J. N. Andrews"),
    ("O-Sabado-e-o-Domingo-nos-Primeiros-Tres-Seculos", "SDP", 2,
     "J. N. Andrews"),
    ("A-Mensagem-do-Terceiro-Anjo-1893-1", "MTA", 2, "A. T. Jones"),
    ("Estudos-sobre-Fe", "ESF", 2, "A. T. Jones e E. J. Waggoner"),
    ("Lei-Dominical-Nacional", "LDN", 3, "A. T. Jones"),
    ("No-Poder-do-Espirito", "NPE", 2, "W. W. Prescott"),
    ("Estudos-em-Educacao-Crista", "EEC", 3, "E. A. Sutherland"),
    ("O-Grande-Movimento-Adventista", "GMA", 3, "J. N. Loughborough"),
    ("Minha-Historia", "MH", 3, "Tiago White"),
    ("As-Aventuras-do-Capitao-Jose-Bates", "ACJB", 3, "José Bates"),
]

# Comentário versículo a versículo: o livro é dividido em seções com
# "VERSÍCULOS 1, 2:" sob títulos "Daniel 01 — ...", "Apocalipse 13 — ...".
# Cada seção vira um trecho ligado aos versículos que ela comenta.
COMENTARIO_VERSICULO = {"Daniel-e-Apocalipse"}


def todas():
    """[(arquivo, sigla, grupo, prioridade, autor)] na ordem do catálogo."""
    lista = [(a, s, "egw", p, "Ellen G. White") for a, s, p in EGW]
    lista += [(a, s, "pioneiros", p, autor) for a, s, p, autor in PIONEIROS]
    siglas = [x[1] for x in lista]
    assert len(siglas) == len(set(siglas)), "sigla repetida"
    return lista


def url(arquivo):
    return CDN + arquivo + ".pdf"
