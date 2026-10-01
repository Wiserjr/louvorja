"""Gera ``assets/estudo.db.gz`` — tudo o que acompanha o texto bíblico.

    python ferramentas/construir_estudo.py          (de dentro de biblia/)

Precisa, antes:
    python ferramentas/construir_biblia.py     (texto, usado para achar citações)
    python ferramentas/indexar_obras.py        (índice de Ellen G. White)

Junta num banco só:

    obra, capitulo, trecho, ref_obra
        o índice de Ellen G. White e dos pioneiros (ver indexar_obras.py)

    ref_cruzada
        referências cruzadas do OpenBible.info (CC BY), com os votos que a
        comunidade deu a cada uma — o app mostra primeiro as mais votadas. Cada
        par recebe um tipo, calculado aqui comparando o texto dos dois lados na
        ARA:
          0  referência temática
          1  alusão: o NT ecoa uma expressão do AT
          2  citação: o NT repete o AT (quatro ou mais palavras de conteúdo
             seguidas, iguais)
          3  passagem paralela: o mesmo relato contado duas vezes (evangelhos
             sinóticos; Samuel/Reis/Crônicas)

    introducao
        introdução a cada livro: autor, data, local, tema, mensagem, Cristo no
        livro (ferramentas/introducoes.json, escritas para este app)

    nota
        notas de estudo por versículo, se ferramentas/cache/notas.jsonl existir
        (ver gerar_notas.py)
"""
import gzip
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import unicodedata
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASTA = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(PASTA)
CACHE = os.path.join(PASTA, "cache")
OBRAS = os.path.join(CACHE, "obras.db")
NOTAS = os.path.join(CACHE, "notas.jsonl")
BIBLIA = os.path.join(RAIZ, "assets", "biblia.db.gz")
DESTINO = os.path.join(RAIZ, "assets", "estudo.db.gz")
INTRODUCOES = os.path.join(PASTA, "introducoes.json")

URL_REFERENCIAS = "https://a.openbible.info/data/cross-references.zip"
VOTOS_MINIMOS = 3

OSIS = (
    "Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr Ezra "
    "Neh Esth Job Ps Prov Eccl Song Isa Jer Lam Ezek Dan Hos Joel Amos Obad "
    "Jonah Mic Nah Hab Zeph Hag Zech Mal Matt Mark Luke John Acts Rom 1Cor "
    "2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas 1Pet "
    "2Pet 1John 2John 3John Jude Rev").split()
NUMERO = {b: i + 1 for i, b in enumerate(OSIS)}

EVANGELHOS = {40, 41, 42, 43}
HISTORICOS = {9, 10, 11, 12, 13, 14}  # Samuel, Reis, Crônicas

ESQUEMA = """
CREATE TABLE ref_cruzada (
  livro INTEGER NOT NULL, ini INTEGER NOT NULL,
  livro2 INTEGER NOT NULL, ini2 INTEGER NOT NULL, fim2 INTEGER NOT NULL,
  votos INTEGER NOT NULL, tipo INTEGER NOT NULL
);
CREATE TABLE introducao (
  livro INTEGER PRIMARY KEY, autor TEXT, data TEXT, local TEXT,
  destinatarios TEXT, tema TEXT, versiculo_chave TEXT, esboco TEXT,
  mensagem TEXT, cristo TEXT, egw TEXT
);
CREATE TABLE nota (
  livro INTEGER NOT NULL, ini INTEGER NOT NULL, fim INTEGER NOT NULL,
  texto TEXT NOT NULL
);
CREATE TABLE info (chave TEXT PRIMARY KEY, valor TEXT);
"""

PALAVRAS_VAZIAS = set("""
a o as os e de do da dos das em no na nos nas num numa um uma uns umas que se
ao aos à às para pra por pelo pela pelos pelas com sem nao mas eu tu ele ela
vos eles elas me te lhe lhes seu sua seus suas meu minha meus minhas teu tua
teus tuas nosso nossa vosso vossa este esta estes estas isto esse essa esses
essas isso aquele aquela aquilo como pois porque quando sobre ja tambem mais
muito todo toda todos todas era foi sera ser e ha nem ou entao assim eis ate
""".split())


def _palavras(texto):
    t = re.sub(r"<[^>]+>", "", texto).lower()
    t = "".join(c for c in unicodedata.normalize("NFD", t)
                if unicodedata.category(c) != "Mn")
    return [w for w in re.findall(r"[a-z]+", t)
            if w not in PALAVRAS_VAZIAS and len(w) > 1]


def _maior_sequencia(a, b):
    """Tamanho da maior sequência de palavras seguidas comum a ``a`` e ``b``."""
    melhor = 0
    anterior = [0] * (len(b) + 1)
    for x in a:
        atual = [0] * (len(b) + 1)
        for j, y in enumerate(b, start=1):
            if x == y:
                atual[j] = anterior[j - 1] + 1
                if atual[j] > melhor:
                    melhor = atual[j]
        anterior = atual
    return melhor


def _osis(ref):
    livro, cap, ver = ref.split(".")
    return NUMERO[livro], int(cap), int(ver)


def _baixar_referencias():
    os.makedirs(CACHE, exist_ok=True)
    txt = os.path.join(CACHE, "cross_references.txt")
    if not os.path.exists(txt):
        zipado = os.path.join(CACHE, "cross-references.zip")
        print("  baixando", URL_REFERENCIAS)
        urllib.request.urlretrieve(URL_REFERENCIAS, zipado)
        with zipfile.ZipFile(zipado) as z:
            z.extract("cross_references.txt", CACHE)
    return txt


# Fórmulas com que o NT introduz uma citação ("está escrito", "para que se
# cumprisse o que foi dito pelo profeta"). Com elas no versículo (ou no
# anterior), três palavras seguidas iguais bastam para ser citação.
_FORMULA = re.compile(
    r"escrito|escritura|profeta|cumprisse|cumpriu|cumpra|diz o senhor|"
    r"disse deus|esta dito|foi dito|diz davi|disse davi|moises disse|"
    r"isaias|jeremias|salmo")


def _formula_citacao(textos_nt, a):
    for k in (a, (a[0], a[1], a[2] - 1)):
        if _FORMULA.search(textos_nt.get(k, "")):
            return True
    return False


def _texto_ara(caminho_biblia):
    con = sqlite3.connect(caminho_biblia)
    vid = con.execute("SELECT id FROM versao WHERE sigla='ARA'").fetchone()[0]
    textos = {}
    crus = {}
    for l, c, v, t in con.execute(
            "SELECT livro, capitulo, versiculo, texto FROM versiculo "
            "WHERE versao=?", (vid,)):
        textos[(l, c, v)] = _palavras(t)
        if l >= 40:
            crus[(l, c, v)] = " ".join(_sem_acento(t))
    con.close()
    return textos, crus


def _sem_acento(texto):
    t = re.sub(r"<[^>]+>", "", texto).lower()
    return re.findall(r"[a-z]+", "".join(
        c for c in unicodedata.normalize("NFD", t)
        if unicodedata.category(c) != "Mn"))


def _tipo(a, b1, b2, textos, crus):
    """Classifica o par (versículo a) -> (intervalo b1..b2)."""
    la, lb = a[0], b1[0]
    nt_at = (la >= 40) != (lb >= 40)
    paralelo = (la in EVANGELHOS and lb in EVANGELHOS) or \
        (la in HISTORICOS and lb in HISTORICOS and la != lb)
    if not (nt_at or paralelo):
        return 0
    if b1[1] != b2[1] or b2[2] - b1[2] > 6:
        return 0
    outro = []
    for v in range(b1[2], b2[2] + 1):
        outro += textos.get((lb, b1[1], v), [])
    seq = _maior_sequencia(textos.get(a, []), outro)
    if paralelo:
        return 3 if seq >= 5 else 0
    if seq >= 4:
        return 2
    if seq == 3:
        nt = a if la >= 40 else b1
        return 2 if _formula_citacao(crus, nt) else 1
    return 0


def referencias_cruzadas(con, textos, crus):
    txt = _baixar_referencias()
    linhas = []
    tipos = {0: 0, 1: 0, 2: 0, 3: 0}
    with open(txt, encoding="utf-8") as f:
        next(f)
        for linha in f:
            de, para, votos = linha.rstrip("\n").split("\t")
            votos = int(votos)
            if votos < VOTOS_MINIMOS:
                continue
            a = _osis(de)
            partes = para.split("-")
            b1 = _osis(partes[0])
            b2 = _osis(partes[1]) if len(partes) > 1 else b1
            if b2[0] != b1[0]:
                continue
            tipo = _tipo(a, b1, b2, textos, crus)
            tipos[tipo] += 1
            linhas.append((a[0], a[1] * 1000 + a[2], b1[0],
                           b1[1] * 1000 + b1[2], b2[1] * 1000 + b2[2],
                           votos, tipo))
    # Citação achada só num sentido (NT -> AT) vale também no outro: quem lê
    # Deuteronômio 8:3 quer saber que Jesus o citou em Mateus 4:4.
    existentes = {(l, i, l2, i2) for l, i, l2, i2, _, _, _ in linhas}
    reversas = []
    for l, i, l2, i2, f2, votos, tipo in linhas:
        if tipo in (2, 3) and i2 == f2 and (l2, i2, l, i) not in existentes:
            reversas.append((l2, i2, l, i, i, votos, tipo))
    con.executemany("INSERT INTO ref_cruzada VALUES (?,?,?,?,?,?,?)",
                    linhas + reversas)
    con.execute("CREATE INDEX ix_ref_cruzada ON ref_cruzada (livro, ini)")
    print("  referências cruzadas: %d (+%d recíprocas); citações %d, "
          "alusões %d, paralelos %d" % (len(linhas), len(reversas),
                                        tipos[2], tipos[1], tipos[3]))


def copiar_obras(con):
    if not os.path.exists(OBRAS):
        sys.exit("Falta %s — rode indexar_obras.py antes." % OBRAS)
    con.execute("ATTACH DATABASE ? AS o", (OBRAS,))
    for tabela in ("obra", "capitulo", "trecho", "ref_obra"):
        sql = con.execute(
            "SELECT sql FROM o.sqlite_master WHERE name=?",
            (tabela,)).fetchone()[0]
        con.execute(sql)
        con.execute("INSERT INTO main.%s SELECT * FROM o.%s" % (tabela,
                                                               tabela))
    con.commit()
    con.execute("DETACH DATABASE o")
    con.execute("CREATE INDEX ix_ref_obra ON ref_obra (livro, ini)")
    con.execute("CREATE INDEX ix_trecho_obra ON trecho (obra, pagina)")
    n = con.execute("SELECT count(*) FROM ref_obra").fetchone()[0]
    print("  obras: %d ligações versículo -> trecho" % n)


def introducoes(con):
    with open(INTRODUCOES, encoding="utf-8") as f:
        dados = json.load(f)
    campos = ["autor", "data", "local", "destinatarios", "tema",
              "versiculo_chave", "esboco", "mensagem", "cristo", "egw"]
    for livro, intro in dados.items():
        valores = []
        for c in campos:
            v = intro.get(c)
            if isinstance(v, list):
                v = "\n".join(v)
            valores.append(v)
        con.execute("INSERT INTO introducao VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    [int(livro)] + valores)
    print("  introduções: %d livros" % len(dados))


def notas(con):
    if not os.path.exists(NOTAS):
        print("  notas: nenhuma (rode gerar_notas.py para criá-las)")
        return
    n = 0
    with open(NOTAS, encoding="utf-8") as f:
        for linha in f:
            if not linha.strip():
                continue
            d = json.loads(linha)
            for nota in d.get("notas", []):
                con.execute("INSERT INTO nota VALUES (?,?,?,?)",
                            (d["livro"], nota["ini"], nota["fim"],
                             nota["texto"]))
                n += 1
    con.execute("CREATE INDEX ix_nota ON nota (livro, ini)")
    print("  notas: %d" % n)


def main():
    tmp = tempfile.mkdtemp()
    try:
        biblia = os.path.join(tmp, "biblia.db")
        with gzip.open(BIBLIA) as g, open(biblia, "wb") as f:
            shutil.copyfileobj(g, f)
        textos, crus = _texto_ara(biblia)

        caminho = os.path.join(tmp, "estudo.db")
        con = sqlite3.connect(caminho)
        con.executescript(ESQUEMA)
        copiar_obras(con)
        referencias_cruzadas(con, textos, crus)
        introducoes(con)
        notas(con)
        con.execute("INSERT INTO info VALUES ('esquema', '1')")
        con.commit()
        con.execute("VACUUM")
        con.close()

        with open(caminho, "rb") as f, \
                gzip.GzipFile(DESTINO, "wb", compresslevel=9, mtime=0) as g:
            shutil.copyfileobj(f, g)
        print("Gerado %s (%.1f MB)" % (DESTINO,
                                       os.path.getsize(DESTINO) / 1e6))
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
