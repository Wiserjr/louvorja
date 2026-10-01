"""Gera ``assets/biblia.db.gz`` — o texto das traduções que vai no app.

    python ferramentas/construir_biblia.py          (de dentro de biblia/)

A fonte é o catálogo do Louvor JA (``../assets/louvorja_pt.db.gz``), que já tem
as doze traduções conferidas pelo ``conferir_catalogo.py`` daquele app —
incluindo as duas edições da Bíblia Livre injetadas pelo ``build_db.py``. Assim
os dois apps mostram exatamente o mesmo texto e só existe um lugar para
corrigir uma tradução.
"""
import gzip
import os
import shutil
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from referencias_pt import CAPITULOS, LIVROS  # noqa: E402

PASTA = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(PASTA)
ORIGEM = os.path.join(RAIZ, "..", "assets", "louvorja_pt.db.gz")
DESTINO = os.path.join(RAIZ, "assets", "biblia.db.gz")

# Ordem de exibição. A ARA vem primeiro: é a versão da Bíblia de Estudo
# Andrews e a mais citada nas edições brasileiras de Ellen G. White.
ORDEM = ["ARA", "NAA", "ARC", "ACF", "NVI", "NVT", "NTLH", "KJA", "ACRF",
         "ARIB", "BLIVRE", "BLIVRE-TR"]

ABREVIACOES = [
    "Gn", "Êx", "Lv", "Nm", "Dt", "Js", "Jz", "Rt", "1Sm", "2Sm", "1Rs",
    "2Rs", "1Cr", "2Cr", "Ed", "Ne", "Et", "Jó", "Sl", "Pv", "Ec", "Ct", "Is",
    "Jr", "Lm", "Ez", "Dn", "Os", "Jl", "Am", "Ob", "Jn", "Mq", "Na", "Hc",
    "Sf", "Ag", "Zc", "Ml", "Mt", "Mc", "Lc", "Jo", "At", "Rm", "1Co", "2Co",
    "Gl", "Ef", "Fp", "Cl", "1Ts", "2Ts", "1Tm", "2Tm", "Tt", "Fm", "Hb",
    "Tg", "1Pe", "2Pe", "1Jo", "2Jo", "3Jo", "Jd", "Ap",
]

ESQUEMA = """
CREATE TABLE versao (
  id INTEGER PRIMARY KEY, sigla TEXT NOT NULL, nome TEXT NOT NULL,
  ordem INTEGER NOT NULL
);
CREATE TABLE livro (
  numero INTEGER PRIMARY KEY, nome TEXT NOT NULL, abreviacao TEXT NOT NULL,
  testamento INTEGER NOT NULL, capitulos INTEGER NOT NULL
);
CREATE TABLE versiculo (
  versao INTEGER NOT NULL, livro INTEGER NOT NULL, capitulo INTEGER NOT NULL,
  versiculo INTEGER NOT NULL, texto TEXT NOT NULL,
  PRIMARY KEY (versao, livro, capitulo, versiculo)
) WITHOUT ROWID;
CREATE TABLE info (chave TEXT PRIMARY KEY, valor TEXT);
"""


def main():
    origem = sys.argv[1] if len(sys.argv) > 1 else ORIGEM
    tmp = tempfile.mkdtemp()
    try:
        fonte = os.path.join(tmp, "fonte.db")
        with gzip.open(origem) as g, open(fonte, "wb") as f:
            shutil.copyfileobj(g, f)
        src = sqlite3.connect(fonte)
        dst_caminho = os.path.join(tmp, "biblia.db")
        dst = sqlite3.connect(dst_caminho)
        dst.executescript(ESQUEMA)

        versoes = src.execute(
            "SELECT id, sigla, nome FROM biblia_versao").fetchall()
        siglas = {s for _, s, _ in versoes}
        faltando = set(ORDEM) - siglas
        if faltando:
            sys.exit("Faltam traduções na origem: %s" % ", ".join(faltando))
        for vid, sigla, nome in versoes:
            ordem = ORDEM.index(sigla) if sigla in ORDEM else 99
            dst.execute("INSERT INTO versao VALUES (?,?,?,?)",
                        (vid, sigla, nome, ordem))

        for n in range(1, 67):
            dst.execute("INSERT INTO livro VALUES (?,?,?,?,?)",
                        (n, LIVROS[n][0], ABREVIACOES[n - 1],
                         1 if n <= 39 else 2, CAPITULOS[n - 1]))

        livro_de = dict(src.execute(
            "SELECT id, numero FROM biblia_livro").fetchall())
        linhas = (
            (v, livro_de[l], c, n, t.strip())
            for v, l, c, n, t in src.execute(
                "SELECT id_versao, id_livro, capitulo, versiculo, texto "
                "FROM biblia_versiculo ORDER BY id_versao, id_livro, "
                "capitulo, versiculo"))
        dst.executemany("INSERT OR IGNORE INTO versiculo VALUES (?,?,?,?,?)",
                        linhas)
        dst.execute("INSERT INTO info VALUES ('esquema', '1')")
        dst.commit()

        for vid, sigla, _ in sorted(versoes, key=lambda x: x[1]):
            n = dst.execute("SELECT count(*) FROM versiculo WHERE versao=?",
                            (vid,)).fetchone()[0]
            print("  %-10s %6d versículos" % (sigla, n))
            if n < 31000:
                sys.exit("%s incompleta" % sigla)
        dst.execute("VACUUM")
        dst.close()
        src.close()

        os.makedirs(os.path.dirname(DESTINO), exist_ok=True)
        with open(dst_caminho, "rb") as f, \
                gzip.GzipFile(DESTINO, "wb", compresslevel=9, mtime=0) as g:
            shutil.copyfileobj(f, g)
        print("Gerado %s (%.1f MB)" % (
            DESTINO, os.path.getsize(DESTINO) / 1e6))
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
