r"""Monta a pasta de midia do LouvorJA para copiar ao celular.

O app le o catalogo completo (asset) e descobre em runtime o que existe nesta
pasta. A saida usa os caminhos do catalogo, ja no formato da API:

    <destino>/musics/pt/<album>/<musica>.mp3
    <destino>/images/<fundo>.jpg

Repare que a saida NAO espelha os nomes de pasta do Windows (`musicas`,
`imagens`): ela espelha o catalogo. Assim o mesmo caminho serve para a pasta
copiada e para o download pelo servidor, e o app nao precisa saber a origem.

Uso:
    python empacotar.py --listar
    python empacotar.py --albuns 1,4,7-12 --destino "D:\LouvorJA"
    python empacotar.py --albuns todos --destino "D:\LouvorJA" --com-playback
"""
import argparse
import os
import shutil
import sqlite3
import sys

from caminhos import para_local, e_portugues

BANCO = "louvorja_pt.db"


def conecta():
    c = sqlite3.connect(BANCO)
    c.row_factory = sqlite3.Row
    return c


def albuns_com_tamanho(c):
    return list(c.execute("""
        select a.id, a.nome, cat.nome categoria, ac.subtitulo,
               count(*) musicas, coalesce(sum(m.audio_bytes),0) bytes
          from albums a
          join album_musicas am on am.id_album = a.id
          join musicas m on m.id = am.id_musica
          left join album_categoria ac on ac.id_album = a.id
          left join categorias cat on cat.id = ac.id_categoria
         group by a.id, a.nome, cat.nome, ac.subtitulo
         order by cat.ordem, cat.nome, a.nome"""))


def parse_selecao(txt, validos):
    """'1,4,7-12' -> {1,4,...,12}; 'todos' -> todos os ids"""
    if txt.strip().lower() in ("todos", "all", "*"):
        return set(validos)
    sel = set()
    for parte in txt.split(","):
        parte = parte.strip()
        if not parte:
            continue
        if "-" in parte:
            a, b = parte.split("-", 1)
            sel.update(range(int(a), int(b) + 1))
        else:
            sel.add(int(parte))
    return sel & set(validos)


def arquivos_de(c, ids, com_playback):
    marks = ",".join("?" * len(ids))
    arquivos = set()

    campos = ["m.audio", "m.imagem"] + (["m.audio_pb"] if com_playback else [])
    q = ("select " + ", ".join(campos) +
         "  from musicas m join album_musicas am on am.id_musica = m.id "
         " where am.id_album in (" + marks + ")")
    for row in c.execute(q, tuple(ids)):
        arquivos.update(p for p in row if p)

    q = ("select distinct l.imagem from letras l "
         "  join album_musicas am on am.id_musica = l.id_musica "
         " where am.id_album in (" + marks + ") and l.imagem is not null")
    arquivos.update(r[0] for r in c.execute(q, tuple(ids)))

    return sorted(p for p in arquivos if e_portugues(p))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listar", action="store_true")
    ap.add_argument("--albuns")
    ap.add_argument("--destino")
    ap.add_argument("--com-playback", action="store_true",
                    help="inclui as faixas de playback/instrumental")
    ap.add_argument("--simular", action="store_true",
                    help="calcula o tamanho sem copiar nada")
    a = ap.parse_args()

    c = conecta()
    albuns = albuns_com_tamanho(c)

    if a.listar or not a.albuns:
        cat_atual = None
        for r in albuns:
            if r["categoria"] != cat_atual:
                cat_atual = r["categoria"]
                print("\n" + str(cat_atual or "Sem categoria").upper())
                print("  %4s  %7s  %9s  %s" % ("id", "musicas", "tamanho", "album"))
            sub = (" (" + r["subtitulo"] + ")") if r["subtitulo"] else ""
            print("  %4d  %7d  %6.0f MB  %s%s" %
                  (r["id"], r["musicas"], r["bytes"] / 1048576, r["nome"], sub))
        tot = sum(r["bytes"] for r in albuns)
        print("\n%d albuns, %d musicas, %.2f GB no total" %
              (len(albuns), sum(r["musicas"] for r in albuns), tot / 1073741824))
        if not a.albuns:
            return

    ids = parse_selecao(a.albuns, [r["id"] for r in albuns])
    if not ids:
        sys.exit("nenhum album valido na selecao")

    arquivos = arquivos_de(c, sorted(ids), a.com_playback)
    total = 0
    ausentes = []
    for rel in arquivos:
        p = para_local(rel)
        if os.path.exists(p):
            total += os.path.getsize(p)
        else:
            ausentes.append(rel)

    nomes = {r["id"]: r["nome"] for r in albuns}
    print("\n%d albuns selecionados:" % len(ids))
    for i in sorted(ids):
        print("   -", nomes[i])
    print("\n%d arquivos, %.2f GB" % (len(arquivos), total / 1073741824))
    if ausentes:
        print("AVISO: %d ausentes na origem, ex.: %s" % (len(ausentes), ausentes[0]))

    if a.simular or not a.destino:
        print("\n(simulacao - nada copiado)")
        return

    unidade = os.path.splitdrive(os.path.abspath(a.destino))[0] + os.sep
    livre = shutil.disk_usage(unidade).free
    if livre < total:
        sys.exit("espaco insuficiente no destino: %.1f GB livres" % (livre / 1073741824))

    copiados = 0
    for n, rel in enumerate(arquivos, 1):
        org = para_local(rel)
        if not os.path.exists(org):
            continue
        # a saida espelha o catalogo, nao os nomes de pasta do Windows
        dst = os.path.join(a.destino, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not (os.path.exists(dst) and os.path.getsize(dst) == os.path.getsize(org)):
            shutil.copy2(org, dst)
        copiados += 1
        if n % 100 == 0 or n == len(arquivos):
            print("\r  %d/%d arquivos..." % (n, len(arquivos)), end="", flush=True)
    print("\n\npronto: %d arquivos em %s" % (copiados, a.destino))
    print("copie essa pasta inteira para o celular e aponte o app para ela.")


if __name__ == "__main__":
    main()
