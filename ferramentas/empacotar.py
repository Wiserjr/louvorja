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
    python empacotar.py --so-imagens --reduzir --destino "D:\LouvorJA"

Sobre `--so-imagens`: os fundos dos slides sao selecionados junto com os albuns,
entao quem empacota parte do acervo fica com parte dos fundos. As demais musicas
ainda tocam - o app busca o fundo na API sob demanda -, mas depender da rede no
meio do culto e ruim, e a rajada de requisicoes ajuda a estourar o limite do
servidor. Sao 1.003 imagens; leva-las de uma vez custa pouco perto dos MP3.
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


def todas_as_imagens(c):
    """Todos os fundos citados pelo catalogo, independentemente de album."""
    return sorted(
        r[0] for r in c.execute(
            "select distinct imagem from letras where imagem is not null"))


def copiar_reduzido(origem, destino, lado=1920, qualidade=82):
    """Recomprime um JPEG para o destino. Devolve False se nao souber tratar.

    Quase todos os fundos sao 1024x768 salvos com qualidade altissima - bons
    para projetor, exagerados para um fundo atras de texto num celular. A
    recompressao corta o conjunto de 343 MB para cerca de 134 MB.

    PNG fica de fora: sao 4 arquivos, 11 MB no total, e converte-los mudaria a
    extensao que o catalogo referencia.
    """
    if not origem.lower().endswith((".jpg", ".jpeg")):
        return False
    try:
        from PIL import Image
    except ImportError:
        return False
    try:
        with Image.open(origem) as im:
            im = im.convert("RGB")
            if max(im.size) > lado:
                im.thumbnail((lado, lado), Image.LANCZOS)
            im.save(destino, "JPEG", quality=qualidade,
                    optimize=True, progressive=True)
    except Exception:
        return False
    return True


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
    ap.add_argument("--so-imagens", action="store_true", dest="so_imagens",
                    help="leva todos os fundos do acervo, sem audio nenhum")
    ap.add_argument("--reduzir", action="store_true",
                    help="recomprime os JPEG (q82, max 1920px) ao copiar")
    a = ap.parse_args()

    c = conecta()
    albuns = albuns_com_tamanho(c)

    if a.so_imagens:
        arquivos = todas_as_imagens(c)
        ids = []
    elif a.listar or not a.albuns:
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

    if not a.so_imagens:
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

    if a.so_imagens:
        print("\ntodos os fundos do acervo (sem audio)")
    else:
        nomes = {r["id"]: r["nome"] for r in albuns}
        print("\n%d albuns selecionados:" % len(ids))
        for i in sorted(ids):
            print("   -", nomes[i])
    print("\n%d arquivos, %.0f MB" % (len(arquivos), total / 1048576))
    if a.reduzir:
        print("com --reduzir os JPEG saem bem menores que isso")
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
        # Com --reduzir o tamanho do destino nao bate com o da origem de
        # proposito, entao a presenca do arquivo e o unico criterio.
        ja_esta = os.path.exists(dst) and (
            a.reduzir or os.path.getsize(dst) == os.path.getsize(org))
        if not ja_esta and not (a.reduzir and copiar_reduzido(org, dst)):
            shutil.copy2(org, dst)
        copiados += 1
        if n % 100 == 0 or n == len(arquivos):
            print("\r  %d/%d arquivos..." % (n, len(arquivos)), end="", flush=True)
    print("\n\npronto: %d arquivos em %s" % (copiados, a.destino))
    print("copie essa pasta inteira para o celular e aponte o app para ela.")


if __name__ == "__main__":
    main()
