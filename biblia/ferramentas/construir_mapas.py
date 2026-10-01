"""Lugares bíblicos e mapas: gera ``ferramentas/cache/mapas.db``.

    python ferramentas/construir_mapas.py           (de dentro de biblia/)
    python ferramentas/construir_estudo.py          (copia para o app)

Fontes:

- **Bible Geocoding Data**, de OpenBible.info (CC BY 4.0): 1.342 lugares
  antigos, a identificação moderna mais provável de cada um, com coordenadas,
  grau de confiança e os versículos onde são citados.
  https://github.com/openbibleinfo/Bible-Geocoding-Data
- **Natural Earth** (domínio público): terra, lagos e rios do Mediterrâneo ao
  golfo Pérsico, simplificados para caberem em poucas centenas de KB.
- ``ferramentas/mapas.json``: os mapas temáticos (Abraão, Êxodo, reinos,
  viagens de Paulo...), escritos para este app.

Os nomes dos lugares vêm em inglês. O nome em português é descoberto no
próprio texto da ARA: entre as palavras com inicial maiúscula dos versículos
onde o lugar aparece, a que mais se repete e mais se parece com o nome inglês
("Bethlehem" -> "Belém", "Kadesh-barnea" -> "Cades-Barnéia"). Os poucos casos
em que isso falha estão em ``NOMES`` abaixo.
"""
import collections
import difflib
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

from referencias_pt import encontrar  # noqa: E402

PASTA = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(PASTA)
CACHE = os.path.join(PASTA, "cache")
GEO = os.path.join(CACHE, "geo")
SAIDA = os.path.join(CACHE, "mapas.db")
BIBLIA = os.path.join(RAIZ, "assets", "biblia.db.gz")
MAPAS = os.path.join(PASTA, "mapas.json")

URL_LUGARES = ("https://raw.githubusercontent.com/openbibleinfo/"
               "Bible-Geocoding-Data/main/data/ancient.jsonl")
URL_NE = "https://naciscdn.org/naturalearth/10m/physical/%s.zip"
CAMADAS_NE = ["ne_10m_land", "ne_10m_lakes", "ne_10m_rivers_lake_centerlines"]

# Do estreito de Gibraltar ao golfo Pérsico: cobre de Roma (viagens de Paulo)
# a Susã e Ur.
LIMITES = (8.0, 20.0, 60.0, 46.0)  # lon_min, lat_min, lon_max, lat_max
TOLERANCIA = 0.025                 # graus, na simplificação

# Represas, canais e lagos artificiais modernos não estavam lá.
MODERNOS = {
    "Suez Canal", "Ismailiya Canal", "Lake Nasser", "Buhayrat al-Assad",
    "Ataturk Barajt", "Keban Baraji", "Mingevir Reservoir",
    "Buhayrat ath Tharthar", "Lake Habbaniyah", "Lake Razazah",
    "Hindiyah Channel", "Gharraf Canal", "Ferenc Csatorna", "Saksak Dagi",
}

TIPOS_FORA = {"structure", "special", "gate"}

# Onde a descoberta automática erra, ou o nome precisa distinguir dois
# lugares homônimos.
NOMES = {
    "Nazareth": "Nazaré",
    "City of David": "Cidade de Davi",
    "Great Sea": "Mar Grande (Mediterrâneo)",
    "Salt Sea": "Mar Salgado (Mar Morto)",
    "Sea of Galilee": "Mar da Galiléia",
    "Red Sea 1": "Mar Vermelho",
    "Red Sea 2": "Mar Vermelho (golfo de Ácaba)",
    "Red Sea 3": "Mar Vermelho",
    "Mount of Olives": "Monte das Oliveiras",
    "Caesarea Philippi": "Cesaréia de Filipe",
    "Caesarea": "Cesaréia",
    "Antioch 1": "Antioquia (da Síria)",
    "Antioch 2": "Antioquia da Pisídia",
    "Forum of Appius": "Praça de Ápio",
    "Three Taverns": "Três Vendas",
    "Fair Havens": "Bons Portos",
    "Egypt": "Egito",
    "Tigris": "Rio Tigre",
    "Euphrates": "Rio Eufrates",
    "Nile": "Rio Nilo",
    "Jordan": "Rio Jordão",
    "Ecbatana": "Ecbátana",
    "Golgotha": "Gólgota",
    "Gethsemane": "Getsêmani",
    "Rhegium": "Régio",
    "Puteoli": "Putéoli",
    "Syracuse": "Siracusa",
    "Seleucia": "Selêucia",
    "Attalia": "Atália",
    "Troas": "Trôade",
    "Mitylene": "Mitilene",
    "Ptolemais": "Ptolemaida",
    "Myra": "Mirra",
    "Malta": "Malta",
    "Mount Horeb": "Monte Horebe",
    "Mount Sinai": "Monte Sinai",
    "Mount Carmel": "Monte Carmelo",
    "Mount Nebo": "Monte Nebo",
    "Mount Hor 1": "Monte Hor",
    "Mount Gerizim": "Monte Gerizim",
    "Ur 1": "Ur dos caldeus",
    "Chebar": "Rio Quebar",
    "Babel": "Babel",
    "Babylon 1": "Babilônia",
    "Babylon 2": "Babilônia (Roma)",
    "Babylon 3": "Babilônia (Roma)",
    "Bethany 2": "Betânia, além do Jordão",
    "Succoth 2": "Sucote (no Egito)",
    "Goshen 1": "Gósen",
    "Rameses": "Ramessés",
    "Carchemish": "Carquemis",
    "Cherith": "Torrente de Querite",
    "Jordan Valley": "Vale do Jordão",
    "Cush 1": "Cuxe",
    "Naioth": "Naiote",
    "Thebes": "Tebas (Nô)",
    "Lebo-hamath": "Lebo-Hamate",
}

# Direções que o conjunto de dados registra como lugar ("o Oriente").
DIRECOES = re.compile(r"^(East|West|North|South|Southwest|Northeast)\b")

PALAVRAS_GENERICAS = {
    "Sea": "Mar", "Mount": "Monte", "River": "Rio", "Valley": "Vale",
    "Brook": "Ribeiro", "Wilderness": "Deserto", "Desert": "Deserto",
    "Pool": "Tanque", "Plain": "Planície", "Hill": "Outeiro",
    "Spring": "Fonte", "Well": "Poço", "Tower": "Torre", "Island": "Ilha",
    "Field": "Campo", "Rock": "Rocha", "Cave": "Caverna",
}

NAO_SAO_LUGARES = {
    "Senhor", "Deus", "Então", "Disse", "Porque", "Mas", "Eis", "Quando",
    "Assim", "Ele", "Eu", "Davi", "Jesus", "Moisés", "Saul", "Salomão",
}

OSIS = (
    "Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr Ezra "
    "Neh Esth Job Ps Prov Eccl Song Isa Jer Lam Ezek Dan Hos Joel Amos Obad "
    "Jonah Mic Nah Hab Zeph Hag Zech Mal Matt Mark Luke John Acts Rom 1Cor "
    "2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas 1Pet "
    "2Pet 1John 2John 3John Jude Rev").split()
NUMERO = {b: i + 1 for i, b in enumerate(OSIS)}

ESQUEMA = """
CREATE TABLE lugar (
  id INTEGER PRIMARY KEY, chave TEXT NOT NULL, nome TEXT NOT NULL,
  nome_en TEXT NOT NULL, tipo TEXT NOT NULL, lon REAL NOT NULL,
  lat REAL NOT NULL, confianca INTEGER NOT NULL, versiculos INTEGER NOT NULL
);
CREATE TABLE lugar_ref (
  lugar INTEGER NOT NULL, livro INTEGER NOT NULL, chave INTEGER NOT NULL
);
CREATE TABLE mapa (
  id TEXT PRIMARY KEY, ordem INTEGER NOT NULL, titulo TEXT NOT NULL,
  periodo TEXT, descricao TEXT, referencias TEXT, lugares TEXT NOT NULL,
  rotas TEXT NOT NULL
);
CREATE TABLE geometria (camada TEXT PRIMARY KEY, dados TEXT NOT NULL);
"""


def _sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn").lower()


def _baixar(url, destino):
    if not os.path.exists(destino):
        print("  baixando", url)
        urllib.request.urlretrieve(url, destino + ".parcial")
        os.replace(destino + ".parcial", destino)
    return destino


def _textos_ara():
    tmp = tempfile.mkdtemp()
    try:
        caminho = os.path.join(tmp, "b.db")
        with gzip.open(BIBLIA) as g, open(caminho, "wb") as f:
            shutil.copyfileobj(g, f)
        con = sqlite3.connect(caminho)
        vid = con.execute(
            "SELECT id FROM versao WHERE sigla='ARA'").fetchone()[0]
        textos = {(l, c, v): re.sub(r"<[^>]+>", "", t) for l, c, v, t in
                  con.execute("SELECT livro, capitulo, versiculo, texto "
                              "FROM versiculo WHERE versao=?", (vid,))}
        con.close()
        return textos
    finally:
        shutil.rmtree(tmp)


_PALAVRA = re.compile(
    r"\b[A-ZÁÉÍÓÚÂÊÔÃÕÇ][\wáéíóúâêôãõçü'-]+"
    r"(?:-[A-ZÁÉÍÓÚ][\wáéíóúâêôãõç]+)*")


def nome_portugues(chave, versos):
    """Descobre o nome em português nos versículos (ARA) do lugar."""
    if chave in NOMES:
        return NOMES[chave]
    base = re.sub(r"\s+\d+$", "", chave)
    palavras = base.split()
    generico = None
    if palavras[0] in PALAVRAS_GENERICAS and len(palavras) > 1:
        generico = PALAVRAS_GENERICAS[palavras[0]]
        nucleo = " ".join(w for w in palavras[1:] if w not in ("of", "the"))
    else:
        nucleo = base
    if not versos:
        return None
    contagem = collections.Counter()
    for t in versos:
        contagem.update(set(_PALAVRA.findall(t)))
    melhor, nota = None, 0
    alvo = _sem_acento(nucleo.replace(" ", "-"))
    for w, n in contagem.items():
        if w in NAO_SAO_LUGARES:
            continue
        # Gentílicos ("Nazareno", "moabita") não são o nome do lugar.
        if re.search(r"(eno|ita|itas|eus|ense|enses)$", w) and \
                not alvo.endswith(_sem_acento(w)[-3:]):
            continue
        sim = difflib.SequenceMatcher(None, _sem_acento(w), alvo).ratio()
        pontos = sim * (n / len(versos)) ** 0.5
        if sim >= 0.45 and pontos > nota:
            melhor, nota = w, pontos
    if melhor and generico:
        formas = collections.Counter()
        padrao = re.compile(r"\b(%s)\s+(?:(de|do|da|dos|das)\s+)?%s\b" % (
            generico, re.escape(melhor)), re.I)
        for t in versos:
            for m in padrao.finditer(t):
                prep = (m.group(2) + " ") if m.group(2) else ""
                formas[generico + " " + prep + melhor] += 1
        melhor = formas.most_common(1)[0][0] if formas else \
            generico + " " + melhor
    return melhor


def _ponto(d):
    """(lon, lat, confiança 0-1000) da identificação mais provável."""
    for ident in d.get("identifications") or []:
        for r in ident.get("resolutions") or []:
            if r.get("lonlat"):
                lon, lat = map(float, r["lonlat"].split(","))
                conf = ident.get("score", {}).get("vote_average", 0)
                return lon, lat, int(conf)
    return None


def lugares(con):
    caminho = _baixar(URL_LUGARES, os.path.join(GEO, "ancient.jsonl"))
    textos = _textos_ara()
    chaves = {}
    n_refs = 0
    with open(caminho, encoding="utf-8") as f:
        dados = [json.loads(linha) for linha in f]
    dados = [d for d in dados if d.get("friendly_id") and d.get("verses")]
    for d in dados:
        tipo = (d.get("types") or ["?"])[0]
        if tipo in TIPOS_FORA or DIRECOES.match(d["friendly_id"]):
            continue
        ponto = _ponto(d)
        if not ponto:
            continue
        lon, lat, conf = ponto
        refs = []
        versos = []
        for v in d["verses"]:
            partes = v["osis"].split(".")
            if partes[0] not in NUMERO or len(partes) < 3:
                continue
            l, c, n = NUMERO[partes[0]], int(partes[1]), int(partes[2])
            refs.append((l, c * 1000 + n))
            if (l, c, n) in textos:
                versos.append(textos[(l, c, n)])
        nome = nome_portugues(d["friendly_id"], versos)
        if not nome:
            continue
        lid = len(chaves) + 1
        chaves[d["friendly_id"]] = lid
        con.execute("INSERT INTO lugar VALUES (?,?,?,?,?,?,?,?,?)",
                    (lid, d["friendly_id"], nome, d["friendly_id"], tipo,
                     round(lon, 5), round(lat, 5), conf, len(set(refs))))
        con.executemany("INSERT INTO lugar_ref VALUES (?,?,?)",
                        [(lid, l, k) for l, k in sorted(set(refs))])
        n_refs += len(set(refs))
    con.execute("CREATE INDEX ix_lugar_ref ON lugar_ref (livro, chave)")
    print("  lugares: %d, citados em %d versículos" % (len(chaves), n_refs))
    return chaves


def mapas(con, chaves):
    with open(MAPAS, encoding="utf-8") as f:
        lista = json.load(f)
    for ordem, m in enumerate(lista):
        faltam = [x for x in m["lugares"] if x not in chaves]
        for r in m["rotas"]:
            faltam += [x for x in r["lugares"] if x not in chaves]
        if faltam:
            sys.exit("Mapa %s: lugares desconhecidos %s" % (m["id"], faltam))
        for ref in m.get("referencias", []):
            if not encontrar(ref):
                sys.exit("Mapa %s: referência ilegível %r" % (m["id"], ref))
        rotas = [{"nome": r["nome"],
                  "lugares": [chaves[x] for x in r["lugares"]]}
                 for r in m["rotas"]]
        # Os pontos das rotas também aparecem como lugares do mapa.
        ids = []
        for x in m["lugares"] + [y for r in m["rotas"] for y in r["lugares"]]:
            if chaves[x] not in ids:
                ids.append(chaves[x])
        con.execute("INSERT INTO mapa VALUES (?,?,?,?,?,?,?,?)",
                    (m["id"], ordem, m["titulo"], m.get("periodo"),
                     m.get("descricao"),
                     json.dumps(m.get("referencias", []), ensure_ascii=False),
                     json.dumps(ids), json.dumps(rotas, ensure_ascii=False)))
    print("  mapas temáticos: %d" % len(lista))


def _geometrias(camada):
    import shapefile
    from shapely.geometry import box, shape
    zipado = _baixar(URL_NE % camada, os.path.join(GEO, camada + ".zip"))
    pasta = os.path.join(GEO, camada)
    if not os.path.isdir(pasta):
        with zipfile.ZipFile(zipado) as z:
            z.extractall(pasta)
    r = shapefile.Reader(os.path.join(pasta, camada))
    recorte = box(*LIMITES)
    campos = [f[0] for f in r.fields[1:]]
    for sr in r.iterShapeRecords():
        atributos = dict(zip(campos, sr.record))
        if atributos.get("name") in MODERNOS:
            continue
        g = shape(sr.shape.__geo_interface__)
        if not g.intersects(recorte):
            continue
        g = g.intersection(recorte).simplify(TOLERANCIA,
                                              preserve_topology=True)
        if g.is_empty:
            continue
        yield g


def _anel(coords):
    """Coordenadas em centésimos de grau, achatadas: [lon, lat, lon, lat...]."""
    plano = []
    for x, y in coords:
        plano += [round(x * 100), round(y * 100)]
    return plano


def geometria(con):
    from shapely.geometry import LineString, MultiLineString, \
        MultiPolygon, Polygon
    resultado = {}
    for camada, nome in [("ne_10m_land", "terra"), ("ne_10m_lakes", "lagos"),
                         ("ne_10m_rivers_lake_centerlines", "rios")]:
        partes = []
        for g in _geometrias(camada):
            if isinstance(g, Polygon):
                g = [g]
            elif isinstance(g, MultiPolygon):
                g = list(g.geoms)
            elif isinstance(g, LineString):
                g = [g]
            elif isinstance(g, MultiLineString):
                g = list(g.geoms)
            else:
                g = [x for x in getattr(g, "geoms", []) if
                     isinstance(x, (Polygon, LineString))]
            for p in g:
                if isinstance(p, Polygon):
                    if p.area < 0.002:
                        continue
                    partes.append(_anel(p.exterior.coords))
                    # Buracos da terra são lagos; a camada de lagos cuida.
                elif isinstance(p, LineString) and p.length > 0.05:
                    partes.append(_anel(p.coords))
        resultado[nome] = partes
        con.execute("INSERT INTO geometria VALUES (?,?)",
                    (nome, json.dumps(partes, separators=(",", ":"))))
    tamanho = sum(len(json.dumps(v)) for v in resultado.values())
    print("  geometria: %s (%.0f KB)" % (
        ", ".join("%s %d" % (k, len(v)) for k, v in resultado.items()),
        tamanho / 1024))
    con.execute("INSERT INTO geometria VALUES ('limites', ?)",
                (json.dumps(LIMITES),))


def main():
    os.makedirs(GEO, exist_ok=True)
    if os.path.exists(SAIDA):
        os.remove(SAIDA)
    con = sqlite3.connect(SAIDA)
    con.executescript(ESQUEMA)
    chaves = lugares(con)
    mapas(con, chaves)
    geometria(con)
    con.commit()
    con.close()
    print("Gerado", SAIDA)


if __name__ == "__main__":
    main()
