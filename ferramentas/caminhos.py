r"""Traducao entre o caminho do catalogo e a pasta local do LouvorJA.

O catalogo guarda o caminho no formato da API (`musics/pt/Album/X.mp3`), que e o
mesmo `files.dir` do banco desde a versao 26.9. Ja a instalacao no Windows manteve
os nomes antigos de pasta (`musicas`, `imagens`, `capas`), entao a leitura do
disco precisa desta traducao. A gravacao, tanto no pacote para o celular quanto
no download, usa sempre o formato do catalogo.
"""
import os

RAIZ_PADRAO = r"C:\Program Files (x86)\Louvor JA\config"

# prefixo no catalogo -> pasta na instalacao Windows
MAPA = {
    "musics/pt": "musicas",
    "images": "imagens",
    "covers": "capas",
}


def para_local(rel, raiz=RAIZ_PADRAO):
    """'musics/pt/1992 - Brilha Jesus/X.mp3' -> '<raiz>\\musicas\\1992 - Brilha Jesus\\X.mp3'"""
    for prefixo, pasta in MAPA.items():
        if rel == prefixo:
            return os.path.join(raiz, pasta)
        if rel.startswith(prefixo + "/"):
            resto = rel[len(prefixo) + 1:].replace("/", os.sep)
            return os.path.join(raiz, pasta, resto)
    return os.path.join(raiz, rel.replace("/", os.sep))


def existe(rel, raiz=RAIZ_PADRAO):
    return os.path.exists(para_local(rel, raiz))


def e_portugues(rel):
    """Arquivos em espanhol vem no mesmo catalogo, mas nao estao nesta instalacao."""
    return not rel.startswith("musics/es/")
