r"""Leitura da Biblia Livre a partir dos arquivos VPL publicados no GitHub.

Modulo compartilhado por build_db.py (que injeta a traducao direto no catalogo
do app) e por importar_blivre.py (que grava no banco do desktop, quando se quer
a traducao tambem no programa Windows).

A Biblia Livre e de Diego Santos, Mario Sergio e Marco Teles, sob Creative
Commons Atribuicao 3.0 Brasil. E a unica traducao completa em portugues que o
app pode redistribuir - as outras dez sao proprietarias.

Fonte: github.com/blivre/BibliaLivre, release 2018.2.0
"""
import os
import re
import zipfile

RELEASE = ("https://github.com/blivre/BibliaLivre/releases/download/"
           "2018.2.0/bliv-{ed}_vpl.zip")

PASTA = os.path.dirname(os.path.abspath(__file__))

EDICOES = {
    "n4": ("Bíblia Livre", "BLIVRE", "Nestle 1904 (texto critico)"),
    "tr": ("Bíblia Livre (Textus Receptus)", "BLIVRE-TR", "Textus Receptus"),
}

# Ordem canonica: indice + 1 == book_number == id_bible_book no LouvorJA.
CANON = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA",
    "1KI", "2KI", "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO",
    "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO",
    "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL", "MAT",
    "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP",
    "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
    "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]

CAPS_ESPERADOS = [
    50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42,
    150, 31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4,
    28, 16, 24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5,
    3, 5, 1, 1, 1, 22,
]

# A BLIVRE usa codigos proprios em oito livros; mapeados para o USFM padrao
# para que tudo continue funcionando se a fonte migrar de notacao.
ALIASES = {
    "SOL": "SNG",  # Canticos
    "EZE": "EZK",  # Ezequiel
    "JOE": "JOL",  # Joel
    "NAH": "NAM",  # Naum
    "MAR": "MRK",  # Marcos
    "JOH": "JHN",  # Joao
    "PHI": "PHP",  # Filipenses
    "JAM": "JAS",  # Tiago
    "1JO": "1JN",
    "2JO": "2JN",
    "3JO": "3JN",
}

LINHA = re.compile(r"^(\S+)\s+(\d+):(\d+)\s+(.*)$")

# Em 103 versiculos (quase todos Salmos) o titulo vem colado ao texto, sem
# espaco: "Salmo de Davi:O SENHOR e meu pastor...". As demais traducoes do
# acervo nao trazem sobrescrito, e projetar isso sairia inconsistente.
SOBRESCRITO = re.compile(r"^[^:]{3,80}:(?=[A-ZÀ-Ú])")


def caminho_do_zip(edicao):
    return os.path.join(PASTA, "blivre_%s_vpl.zip" % edicao)


def baixar_se_faltar(edicao):
    """Garante o zip em disco. Versionado no repositorio; baixa so se sumir."""
    import shutil
    import urllib.request

    destino = caminho_do_zip(edicao)
    if os.path.exists(destino):
        return destino
    url = RELEASE.format(ed=edicao)
    print("  baixando %s" % url)
    with urllib.request.urlopen(url, timeout=120) as r, open(destino, "wb") as f:
        shutil.copyfileobj(r, f)
    return destino


def ler(edicao, sem_titulos=True):
    """Devolve [(book_number, capitulo, versiculo, texto)] ja validado.

    Lanca ValueError se a fonte divergir do canone - melhor falhar no build que
    publicar uma traducao truncada.
    """
    caminho = baixar_se_faltar(edicao)
    with zipfile.ZipFile(caminho) as z:
        nome = next(n for n in z.namelist() if n.endswith(".txt"))
        texto = z.read(nome).decode("utf-8-sig")

    indice = {codigo: i + 1 for i, codigo in enumerate(CANON)}
    versiculos, desconhecidos = [], set()
    for linha in texto.splitlines():
        if not linha.strip():
            continue
        m = LINHA.match(linha)
        if not m:
            continue
        codigo, cap, ver, txt = m.groups()
        codigo = ALIASES.get(codigo, codigo)
        if codigo not in indice:
            desconhecidos.add(codigo)
            continue
        txt = txt.strip()
        if sem_titulos and int(ver) == 1:
            txt = SOBRESCRITO.sub("", txt).strip()
        versiculos.append((indice[codigo], int(cap), int(ver), txt))

    if desconhecidos:
        raise ValueError("codigos de livro nao mapeados: %s" % sorted(desconhecidos))

    problemas = validar(versiculos)
    if problemas:
        raise ValueError("; ".join(problemas))
    return versiculos


def validar(versiculos):
    """Confere contagem de livros e capitulos contra o canone protestante."""
    livros = {}
    for bn, cap, _, _ in versiculos:
        livros.setdefault(bn, set()).add(cap)

    problemas = []
    if len(livros) != 66:
        problemas.append("esperados 66 livros, encontrados %d" % len(livros))
    for bn in sorted(livros):
        esperado, obtido = CAPS_ESPERADOS[bn - 1], len(livros[bn])
        if esperado != obtido:
            problemas.append("%s: %d capitulos (esperado %d)"
                             % (CANON[bn - 1], obtido, esperado))
    return problemas
