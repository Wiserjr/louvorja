r"""Gera o catalogo do app Hinarios: so os dois hinarios, sem o resto do acervo.

O app Hinarios existe para quem tem pouco espaco no celular: o Louvor JA leva
um catalogo de 27 MB (75 albuns, Biblia em 12 traducoes, coletaneas on-line) e
um acervo de ~15 GB para baixar. Este leva so o Hinario Adventista e o de 1996 -
letra, tempos e caminhos de audio -, em menos de 1 MB. O audio continua vindo da
API, hino a hino, quando a pessoa toca.

Le o assets/louvorja_pt.db.gz, o mesmo catalogo que vai no Louvor JA, e grava
assets/hinario.db.gz com o MESMO esquema: o codigo do app nao precisa saber qual
dos dois catalogos abriu. Os hinarios sao achados pela categoria (tipo
'hymnal'), nao por id fixo.

    python ferramentas/build_hinario.py

Regere sempre que o catalogo do Louvor JA for regerado. O gzip e deterministico
(sem data no cabecalho): rodar de novo sem mudanca no catalogo nao muda o
arquivo, e o git nao registra alteracao a toa.
"""
import gzip
import os
import shutil
import sqlite3
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGEM = os.path.join(RAIZ, "assets", "louvorja_pt.db.gz")
DESTINO = os.path.join(RAIZ, "assets", "hinario.db.gz")

# Tabelas do esquema que o app consulta. Biblia e coletaneas on-line ficam
# vazias: existem para o esquema ser o mesmo, nao para ter conteudo.
TABELAS_COPIADAS = ("categorias", "albums", "album_categoria", "musicas",
                    "album_musicas", "letras", "meta")

# Conferencia: se o catalogo de origem perder um hinario, o build falha aqui em
# vez de sair um app com metade dos hinos.
HINOS_MINIMOS = 1200


def descompactar(origem, destino):
    with gzip.open(origem, "rb") as g, open(destino, "wb") as f:
        shutil.copyfileobj(g, f)


def main():
    if not os.path.exists(ORIGEM):
        sys.exit("ERRO: %s nao encontrado." % ORIGEM)

    tmp = tempfile.mkdtemp(prefix="hinario_")
    completo = os.path.join(tmp, "completo.db")
    hinario = os.path.join(tmp, "hinario.db")
    descompactar(ORIGEM, completo)

    src = sqlite3.connect(completo)
    cats = [r[0] for r in src.execute(
        "SELECT id FROM categorias WHERE tipo = 'hymnal' ORDER BY ordem")]
    if not cats:
        sys.exit("ERRO: nenhuma categoria de hinario no catalogo.")

    # Esquema inteiro, inclusive as tabelas que ficam vazias.
    dst = sqlite3.connect(hinario)
    for (sql,) in src.execute(
            "SELECT sql FROM sqlite_master WHERE type IN ('table', 'index')"
            " AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"):
        dst.execute(sql)
    dst.commit()
    dst.close()

    src.execute("ATTACH DATABASE ? AS h", (hinario,))
    marcas = ",".join("?" * len(cats))
    src.execute("CREATE TEMP TABLE alb AS SELECT id_album AS id FROM album_categoria"
                " WHERE id_categoria IN (%s)" % marcas, cats)
    src.execute("CREATE TEMP TABLE mus AS SELECT DISTINCT id_musica AS id"
                " FROM album_musicas WHERE id_album IN (SELECT id FROM alb)")
    filtros = {
        "categorias": "id IN (%s)" % marcas,
        "albums": "id IN (SELECT id FROM alb)",
        "album_categoria": "id_album IN (SELECT id FROM alb) AND id_categoria IN (%s)" % marcas,
        "musicas": "id IN (SELECT id FROM mus)",
        "album_musicas": "id_album IN (SELECT id FROM alb)",
        "letras": "id_musica IN (SELECT id FROM mus)",
        "meta": "1",
    }
    for t in TABELAS_COPIADAS:
        # Cada lista de categorias no filtro consome um jogo de parametros.
        args = cats * (filtros[t].count("?") // len(cats))
        src.execute("INSERT INTO h.%s SELECT * FROM main.%s WHERE %s" % (t, t, filtros[t]), args)
    src.execute("INSERT OR REPLACE INTO h.meta (chave, valor) VALUES ('conteudo', 'hinarios')")
    src.commit()
    src.execute("DETACH DATABASE h")
    src.close()

    dst = sqlite3.connect(hinario)
    dst.execute("VACUUM")
    hinos = dst.execute("SELECT COUNT(*) FROM album_musicas").fetchone()[0]
    albuns = dst.execute("SELECT a.nome, COUNT(*) FROM albums a JOIN album_musicas am"
                         " ON am.id_album = a.id GROUP BY a.id ORDER BY a.nome").fetchall()
    letras = dst.execute("SELECT COUNT(*) FROM letras").fetchone()[0]
    dst.close()
    if hinos < HINOS_MINIMOS:
        sys.exit("ERRO: so %d hinos no catalogo gerado (esperado >= %d)." % (hinos, HINOS_MINIMOS))

    # mtime=0 e sem nome de arquivo no cabecalho: mesmo conteudo, mesmos bytes.
    with open(hinario, "rb") as f, open(DESTINO, "wb") as saida:
        with gzip.GzipFile(filename="", mode="wb", compresslevel=9,
                           fileobj=saida, mtime=0) as g:
            shutil.copyfileobj(f, g)
    shutil.rmtree(tmp, ignore_errors=True)

    for nome, n in albuns:
        print("  %-28s %4d hinos" % (nome, n))
    print("%d linhas de letra" % letras)
    print("%s: %d KB" % (os.path.relpath(DESTINO, RAIZ), os.path.getsize(DESTINO) // 1024))


if __name__ == "__main__":
    main()
