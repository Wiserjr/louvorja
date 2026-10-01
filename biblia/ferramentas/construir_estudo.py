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

    lugar, lugar_ref, mapa, geometria
        lugares bíblicos e mapas temáticos (ver construir_mapas.py)

    sinotico_secao, sinotico_evento, sinotico_ref
        guia sinótico (harmonia) dos evangelhos (ferramentas/sinotico.json),
        cada episódio ligado aos capítulos de Ellen G. White que o narram
        (O Desejado de Todas as Nações, Parábolas de Jesus, História da
        Redenção), achados pelo índice

    tema, tema_ref, tema_egw, estudo, estudo_pergunta
        índice temático e estudos bíblicos (ferramentas/temas.json). As
        leituras de Ellen G. White de cada tema não são escritas à mão: são os
        capítulos que mais citam os versículos do tema, achados pelo índice.
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
MAPAS = os.path.join(CACHE, "mapas.db")
TEMAS = os.path.join(PASTA, "temas.json")
SINOTICO = os.path.join(PASTA, "sinotico.json")

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


def copiar_mapas(con):
    if not os.path.exists(MAPAS):
        sys.exit("Falta %s — rode construir_mapas.py antes." % MAPAS)
    con.execute("ATTACH DATABASE ? AS m", (MAPAS,))
    for tabela in ("lugar", "lugar_ref", "mapa", "geometria"):
        sql = con.execute("SELECT sql FROM m.sqlite_master WHERE name=?",
                          (tabela,)).fetchone()[0]
        con.execute(sql)
        con.execute("INSERT INTO main.%s SELECT * FROM m.%s" % (tabela,
                                                               tabela))
    con.commit()
    con.execute("DETACH DATABASE m")
    con.execute("CREATE INDEX ix_lugar_ref ON lugar_ref (livro, chave)")
    con.execute("CREATE INDEX ix_lugar_ref_lugar ON lugar_ref (lugar)")
    print("  mapas: %d lugares, %d mapas temáticos" % (
        con.execute("SELECT count(*) FROM lugar").fetchone()[0],
        con.execute("SELECT count(*) FROM mapa").fetchone()[0]))


def _referencias(texto, existe, onde):
    """'Salmos 33:6, 9' -> [(19, 33006, 33006), (19, 33009, 33009)],
    conferindo que os versículos existem."""
    from referencias_pt import encontrar
    refs = [r.tupla() for r in encontrar(texto)]
    if not refs:
        sys.exit("%s: referência ilegível %r" % (onde, texto))
    for livro, ini, fim in refs:
        for k in (ini, fim):
            if k % 1000 not in (0, 999) and (livro, k) not in existe:
                sys.exit("%s: %r não existe na ARA" % (onde, texto))
    return refs


def temas(con, existe):
    with open(TEMAS, encoding="utf-8") as f:
        dados = json.load(f)
    con.executescript("""
    CREATE TABLE tema (
      id TEXT PRIMARY KEY, ordem INTEGER NOT NULL, categoria TEXT NOT NULL,
      titulo TEXT NOT NULL, resumo TEXT
    );
    CREATE TABLE tema_ref (
      tema TEXT NOT NULL, ordem INTEGER NOT NULL, livro INTEGER NOT NULL,
      ini INTEGER NOT NULL, fim INTEGER NOT NULL
    );
    CREATE TABLE tema_egw (
      tema TEXT NOT NULL, ordem INTEGER NOT NULL, obra INTEGER NOT NULL,
      capitulo INTEGER NOT NULL, pagina INTEGER NOT NULL,
      versiculos INTEGER NOT NULL
    );
    CREATE TABLE estudo (
      id TEXT PRIMARY KEY, ordem INTEGER NOT NULL, titulo TEXT NOT NULL,
      introducao TEXT
    );
    CREATE TABLE estudo_pergunta (
      estudo TEXT NOT NULL, ordem INTEGER NOT NULL, pergunta TEXT NOT NULL,
      livro INTEGER NOT NULL, ini INTEGER NOT NULL, fim INTEGER NOT NULL
    );
    """)
    n_refs = 0
    for ordem, t in enumerate(dados["temas"]):
        con.execute("INSERT INTO tema VALUES (?,?,?,?,?)",
                    (t["id"], ordem, t["categoria"], t["titulo"],
                     t.get("resumo")))
        refs = []
        for texto in t["versiculos"]:
            refs += _referencias(texto, existe, "tema " + t["id"])
        con.executemany("INSERT INTO tema_ref VALUES (?,?,?,?,?)",
                        [(t["id"], i, l, a, b)
                         for i, (l, a, b) in enumerate(refs)])
        n_refs += len(refs)
        _leituras(con, t["id"], refs)
    for ordem, e in enumerate(dados["estudos"]):
        con.execute("INSERT INTO estudo VALUES (?,?,?,?)",
                    (e["id"], ordem, e["titulo"], e.get("introducao")))
        for i, q in enumerate(e["perguntas"]):
            refs = _referencias(q["ref"], existe, "estudo " + e["id"])
            l, a = refs[0][0], refs[0][1]
            b = refs[-1][2] if refs[-1][0] == l else refs[0][2]
            con.execute("INSERT INTO estudo_pergunta VALUES (?,?,?,?,?,?)",
                        (e["id"], i, q["p"], l, a, b))
    print("  temas: %d (%d referências); estudos bíblicos: %d" % (
        len(dados["temas"]), n_refs, len(dados["estudos"])))


def _leituras(con, tema, refs):
    """Os capítulos de Ellen G. White que mais citam os versículos do tema."""
    contagem = {}
    for i, (livro, ini, fim) in enumerate(refs):
        for obra, cap, pagina in con.execute(
                "SELECT t.obra, t.capitulo, c.pagina FROM ref_obra r "
                "JOIN trecho t ON t.id = r.trecho "
                "JOIN capitulo c ON c.id = t.capitulo "
                "JOIN obra o ON o.id = t.obra "
                "WHERE r.livro = ? AND r.ini <= ? AND r.fim >= ? "
                "AND r.fim - r.ini < 900 AND o.grupo = 'egw' "
                "AND o.prioridade < 6",
                (livro, fim, ini)):
            chave = (obra, cap, pagina)
            contagem.setdefault(chave, set()).add(i)
    melhores = sorted(contagem.items(),
                      key=lambda x: (-len(x[1]), x[0][0], x[0][2]))
    escolhidos = [(k, len(v)) for k, v in melhores if len(v) >= 2][:6]
    con.executemany("INSERT INTO tema_egw VALUES (?,?,?,?,?,?)",
                    [(tema, i, o, c, p, n)
                     for i, ((o, c, p), n) in enumerate(escolhidos)])


def sinotico(con, existe):
    with open(SINOTICO, encoding="utf-8") as f:
        dados = json.load(f)
    con.executescript("""
    CREATE TABLE sinotico_secao (
      id INTEGER PRIMARY KEY, titulo TEXT NOT NULL
    );
    CREATE TABLE sinotico_evento (
      id INTEGER PRIMARY KEY, secao INTEGER NOT NULL, titulo TEXT NOT NULL
    );
    CREATE TABLE sinotico_leitura (
      evento INTEGER NOT NULL, ordem INTEGER NOT NULL, obra INTEGER NOT NULL,
      capitulo INTEGER NOT NULL, pagina INTEGER NOT NULL
    );
    CREATE TABLE sinotico_ref (
      evento INTEGER NOT NULL, livro INTEGER NOT NULL, ordem INTEGER NOT NULL,
      ini INTEGER NOT NULL, fim INTEGER NOT NULL
    );
    """)
    evento_id = 0
    ligados = 0
    for si, secao in enumerate(dados, start=1):
        con.execute("INSERT INTO sinotico_secao VALUES (?,?)",
                    (si, secao["periodo"]))
        for ev in secao["eventos"]:
            evento_id += 1
            refs = []
            for campo, livro in (("mt", 40), ("mc", 41), ("lc", 42),
                                 ("jo", 43)):
                if campo not in ev:
                    continue
                rs = _referencias(ev[campo], existe, "sinótico " + ev["t"])
                if any(l != livro for l, _, _ in rs):
                    sys.exit("sinótico %r: %s fora do evangelho %s" % (
                        ev["t"], ev[campo], campo))
                for ordem, (l, a, b) in enumerate(rs):
                    refs.append((evento_id, l, ordem, a, b))
            if not refs:
                sys.exit("sinótico %r: sem passagem" % ev["t"])
            leituras = _leituras_evento(con, refs)
            ligados += bool(leituras)
            con.execute("INSERT INTO sinotico_evento VALUES (?,?,?)",
                        (evento_id, si, ev["t"]))
            con.executemany(
                "INSERT INTO sinotico_leitura VALUES (?,?,?,?,?)",
                [(evento_id, i, o, c, p)
                 for i, (o, c, p) in enumerate(leituras)])
            con.executemany("INSERT INTO sinotico_ref VALUES (?,?,?,?,?)",
                            refs)
    con.execute("CREATE INDEX ix_sinotico_ref ON sinotico_ref (livro, ini)")
    print("  guia sinótico: %d episódios em %d períodos; %d narrados em "
          "capítulos de Ellen G. White" % (evento_id, len(dados), ligados))


def _leituras_evento(con, refs):
    """Capítulos que narram o episódio: os "Este capítulo é baseado em..."
    de O Desejado de Todas as Nações, Parábolas de Jesus e História da
    Redenção que se sobrepõem às passagens, do mais ao menos sobreposto.

    Só a ligação declarada pela própria autora conta: contar citações
    soltas ligava o prólogo de João ao capítulo "Tradição"."""
    pontos = {}
    for _, livro, _, ini, fim in refs:
        for obra, cap, pagina, a, b in con.execute(
                "SELECT t.obra, t.capitulo, t.pagina, r.ini, r.fim "
                "FROM ref_obra r JOIN trecho t ON t.id = r.trecho "
                "JOIN obra o ON o.id = t.obra "
                "WHERE r.tipo=1 AND o.sigla IN ('DTN', 'PJ', 'HR') "
                "AND r.livro=? AND r.ini<=? AND r.fim>=? "
                "AND t.capitulo IS NOT NULL", (livro, fim, ini)):
            sobre = max(min(fim, b) - max(ini, a) + 1, 1)
            atual = pontos.get((obra, cap), (0, pagina))
            pontos[(obra, cap)] = (atual[0] + sobre, min(atual[1], pagina))
    ordem = {"DTN": 0, "PJ": 1, "HR": 2}
    siglas = dict(con.execute("SELECT id, sigla FROM obra"))
    escolhidos = sorted(pontos.items(),
                        key=lambda x: (ordem[siglas[x[0][0]]], -x[1][0]))
    # Um capítulo por obra.
    vistos, saida = set(), []
    for (obra, cap), (_, pagina) in escolhidos:
        if obra not in vistos:
            vistos.add(obra)
            saida.append((obra, cap, pagina))
    return saida


NOTAS_ESCRITAS = os.path.join(PASTA, "notas")

# "Ver O Desejado, cap. 12" / "O Desejado de Todas as Nações, cap. 29" /
# "Parábolas de Jesus, cap. 16" — conferidos contra o índice.
_OBRAS_CITADAS = {
    "O Desejado de Todas as Nações": "DTN",
    "O Desejado": "DTN",
    "Parábolas de Jesus": "PJ",
    "O Maior Discurso de Cristo": "MDC",
    "Patriarcas e Profetas": "PP",
    "Profetas e Reis": "PR",
    "Atos dos Apóstolos": "AA",
    "O Grande Conflito": "GC",
}
_CITACAO_CAP = re.compile(
    r"(%s), cap\. (\d+)(?:, [\"“]?([^\"”.,;)]+)[\"”]?)?" % "|".join(
        sorted(map(re.escape, _OBRAS_CITADAS), key=len, reverse=True)))


def _ler_notas_escritas(existe):
    """ferramentas/notas/NN-livro.txt: notas escritas para o app.

        # 4
        1-2 | texto da nota sobre os versículos 1 e 2
    """
    saida = []
    if not os.path.isdir(NOTAS_ESCRITAS):
        return saida
    for nome in sorted(os.listdir(NOTAS_ESCRITAS)):
        m = re.match(r"^(\d+)-.*\.txt$", nome)
        if not m:
            continue
        livro = int(m.group(1))
        cap = None
        with open(os.path.join(NOTAS_ESCRITAS, nome), encoding="utf-8") as f:
            for n, linha in enumerate(f, start=1):
                linha = linha.strip()
                onde = "%s:%d" % (nome, n)
                if not linha or linha.startswith("# Notas") or \
                        linha.startswith("# Formato"):
                    continue
                mc = re.match(r"^#\s*(\d+)$", linha)
                if mc:
                    cap = int(mc.group(1))
                    continue
                mv = re.match(r"^(\d+)(?:-(\d+))?\s*\|\s*(.+)$", linha)
                if not mv or cap is None:
                    sys.exit("%s: linha fora do formato" % onde)
                a = int(mv.group(1))
                b = int(mv.group(2) or a)
                for v in (a, b):
                    if (livro, cap * 1000 + v) not in existe:
                        sys.exit("%s: %d:%d não existe" % (onde, cap, v))
                if b < a:
                    sys.exit("%s: intervalo invertido" % onde)
                saida.append((livro, cap * 1000 + a, cap * 1000 + b,
                              mv.group(3).strip(), onde))
    return saida


def _conferir_citacoes(con, texto, onde):
    """Toda citação "obra, cap. N" precisa existir no índice."""
    for m in _CITACAO_CAP.finditer(texto):
        sigla = _OBRAS_CITADAS[m.group(1)]
        num = int(m.group(2))
        titulos = [t for (t,) in con.execute(
            "SELECT c.titulo FROM capitulo c JOIN obra o ON o.id=c.obra "
            "WHERE o.sigla=? AND c.titulo LIKE ?",
            (sigla, "Capítulo %d —%%" % num))]
        if not titulos:
            sys.exit("%s: %s, cap. %d não existe" % (onde, sigla, num))
        esperado = m.group(3)
        if esperado:
            alvo = _sem_acento_texto(esperado.strip(' "“”'))
            if not any(alvo in _sem_acento_texto(t) for t in titulos):
                sys.exit("%s: %s, cap. %d é %r, não %r" % (
                    onde, sigla, num, titulos[0], esperado))


def _sem_acento_texto(s):
    return "".join(c for c in unicodedata.normalize("NFD", s.lower())
                   if unicodedata.category(c) != "Mn")


def notas(con, existe):
    """Notas de estudo: as escritas para o app (ferramentas/notas/) e as
    geradas pelo gerar_notas.py (cache/notas.jsonl), se houver."""
    n = 0
    for livro, ini, fim, texto, onde in _ler_notas_escritas(existe):
        _conferir_citacoes(con, texto, onde)
        con.execute("INSERT INTO nota VALUES (?,?,?,?)",
                    (livro, ini, fim, texto))
        n += 1
    escritas = n
    if os.path.exists(NOTAS):
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
    print("  notas: %d (%d escritas para o app, %d geradas)" % (
        n, escritas, n - escritas))


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
        existe = {(l, c * 1000 + v) for (l, c, v) in textos}
        notas(con, existe)
        copiar_mapas(con)
        temas(con, existe)
        sinotico(con, existe)
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
