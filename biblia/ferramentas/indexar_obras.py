r"""Índice versículo -> parágrafo dos livros de Ellen G. White e dos pioneiros.

    python ferramentas/indexar_obras.py            (de dentro de biblia/)

Baixa os PDFs do Centro White para ``ferramentas/cache/pdf/`` (fora do git),
lê cada um com o PDFium e grava em ``ferramentas/cache/obras.db``:

    obra       um registro por PDF, com tamanho e SHA-256 do arquivo indexado
    capitulo   títulos de capítulo, para a tela dizer "DTN, cap. 12 — A tentação"
    trecho     um parágrafo (ou seção) por registro: onde está no PDF, nunca o
               texto — ver obras.py sobre a licença
    ref_obra   versículos -> trecho, com o tipo da ligação:
                 0  o parágrafo cita o versículo ("... Mateus 4:4.")
                 1  "Este capítulo é baseado em Mateus 4:1-11" — a narrativa
                    do capítulo inteiro sobre aquela história bíblica
                 2  comentário versículo a versículo (Daniel e Apocalipse)

O ``construir_estudo.py`` copia essas tabelas para o banco que vai no app.
"""
import hashlib
import os
import re
import sqlite3
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import obras  # noqa: E402
from referencias_pt import encontrar  # noqa: E402
from texto_pdf import paragrafos, segmentos_para_texto  # noqa: E402

PASTA = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(PASTA, "cache")
PDFS = os.path.join(CACHE, "pdf")
SAIDA = os.path.join(CACHE, "obras.db")

ESQUEMA = """
CREATE TABLE obra (
  id INTEGER PRIMARY KEY, arquivo TEXT NOT NULL, sigla TEXT NOT NULL,
  titulo TEXT NOT NULL, autor TEXT NOT NULL, grupo TEXT NOT NULL,
  prioridade INTEGER NOT NULL, url TEXT NOT NULL, bytes INTEGER NOT NULL,
  sha256 TEXT NOT NULL, paginas INTEGER NOT NULL
);
CREATE TABLE capitulo (
  id INTEGER PRIMARY KEY, obra INTEGER NOT NULL, titulo TEXT NOT NULL,
  pagina INTEGER NOT NULL
);
CREATE TABLE trecho (
  id INTEGER PRIMARY KEY, obra INTEGER NOT NULL, capitulo INTEGER,
  pagina INTEGER NOT NULL, pagina_original INTEGER,
  segmentos TEXT NOT NULL, ancora TEXT
);
CREATE TABLE ref_obra (
  livro INTEGER NOT NULL, ini INTEGER NOT NULL, fim INTEGER NOT NULL,
  trecho INTEGER NOT NULL, tipo INTEGER NOT NULL
);
"""

_CAPITULO = re.compile(r"^(Capítulo|CAPÍTULO)\s+(\d+)\s*[—–-]\s*(.+)$")
_CAPITULO_DA = re.compile(r"^(Daniel|Apocalipse)\s+(\d{1,2})\s*[—–-]")
_VERSICULOS = re.compile(
    r"^VERS[ÍI]CULOS?\s+(\d{1,3})((?:\s*(?:[-–,]|e)\s*\d{1,3})*)\s*:")
_BASEADO = re.compile(r"^Este capítulo é baseado em\s+(.+)$")


def baixar(arquivo):
    destino = os.path.join(PDFS, arquivo + ".pdf")
    if os.path.exists(destino):
        return destino
    os.makedirs(PDFS, exist_ok=True)
    url = obras.url(arquivo)
    print("  baixando", url)
    for tentativa in range(4):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "biblia-estudo-indexador"})
            with urllib.request.urlopen(req, timeout=120) as r:
                dados = r.read()
            break
        except Exception:
            if tentativa == 3:
                raise
            time.sleep(2 ** (tentativa + 1))
    with open(destino + ".parcial", "wb") as f:
        f.write(dados)
    os.replace(destino + ".parcial", destino)
    return destino


def _metadados(caminho):
    import pypdfium2 as pdfium
    doc = pdfium.PdfDocument(caminho)
    try:
        meta = doc.get_metadata_dict()
        return meta.get("Title", "").strip(), len(doc)
    finally:
        doc.close()


def _titulo_limpo(titulo, arquivo):
    """'Patriarcas e Profetas (2007)' -> 'Patriarcas e Profetas'."""
    t = re.sub(r"\s*\((19|20)\d\d\)\s*$", "", titulo or "").strip()
    t = t.replace("Domingonos", "Domingo nos")
    if not t:
        t = arquivo.replace("-", " ")
    if t == "Cuidado de Deus":
        t = "O Cuidado de Deus"
    if ":" in t and len(t) > 60:
        t = t.split(":")[0].strip()
    return t


def _ancora(texto, ref):
    """O texto da própria citação ("Mateus 4:2-4"), usado pelo app para
    reencontrar o parágrafo se o PDF tiver mudado."""
    return re.sub(r"\s+", " ", texto[ref.inicio:ref.final]).strip()


def _contexto(lista, i):
    """Os segmentos a mostrar para o parágrafo ``lista[i]``.

    Parágrafo curto demais para se ler sozinho ganha vizinhos:

    - o que começa em minúscula é continuação do anterior, que a separação por
      recuo cortou (comum nos PDFs dos pioneiros, depois de citação recuada);
    - o que é só o versículo — o título do dia nas meditações matinais
      ("O pão nosso de cada dia dá-nos hoje. Mateus 6:11.") — vem seguido da
      meditação, que é o que interessa ler.
    """
    par = lista[i]
    segs = list(par.segmentos)
    if i > 0 and par.texto[:1].islower():
        segs = list(lista[i - 1].segmentos) + segs
    tamanho = len(par.texto)
    j = i + 1
    while tamanho < 300 and j < len(lista) and j <= i + 3:
        seguinte = lista[j]
        if _CAPITULO.match(seguinte.texto) or _BASEADO.match(seguinte.texto):
            break
        segs += seguinte.segmentos
        tamanho += len(seguinte.texto)
        j += 1
    return _unir(segs)


def _abertura_capitulo(lista, i):
    """Para "Este capítulo é baseado em...": a própria linha e o começo da
    narrativa (uns 1.200 caracteres), que é o que a pessoa quer ler."""
    segs = list(lista[i].segmentos)
    tamanho = 0
    j = i + 1
    while tamanho < 1200 and j < len(lista) and j <= i + 8:
        seguinte = lista[j]
        if _CAPITULO.match(seguinte.texto):
            break
        segs += seguinte.segmentos
        tamanho += len(seguinte.texto)
        j += 1
    return _unir(segs)


def _unir(segs):
    """Junta segmentos contíguos da mesma página."""
    unidos = [segs[0]]
    for p, a, b in segs[1:]:
        up, ua, ub = unidos[-1]
        if p == up and a <= ub + 2:
            unidos[-1] = (p, ua, max(ub, b))
        else:
            unidos.append((p, a, b))
    return unidos


def indexar_obra(con, id_obra, arquivo, comentario_versiculo):
    caminho = baixar(arquivo)
    capitulo_atual = None
    cap_da = None  # (livro, capitulo) em Daniel e Apocalipse
    secao = None   # [trecho_id, livro, ini, fim, segmentos]
    n_refs = 0

    def fechar_secao():
        nonlocal n_refs
        if secao is None:
            return
        tid, livro, ini, fim, segs, pag, pag_orig = secao
        con.execute(
            "INSERT INTO trecho VALUES (?,?,?,?,?,?,?)",
            (tid, id_obra, capitulo_atual, pag, pag_orig,
             segmentos_para_texto(segs), None))
        con.execute("INSERT INTO ref_obra VALUES (?,?,?,?,2)",
                    (livro, ini, fim, tid))
        n_refs += 1

    proximo_trecho = [con.execute(
        "SELECT ifnull(max(id),0)+1 FROM trecho").fetchone()[0]]

    def novo_id():
        v = proximo_trecho[0]
        proximo_trecho[0] += 1
        return v

    lista = list(paragrafos(caminho))
    for indice, par in enumerate(lista):
        texto = par.texto
        if not texto:
            continue
        m = _CAPITULO.match(texto)
        if m and ". . ." not in texto and len(texto) < 120:
            # Título de capítulo (o sumário tem os mesmos, com pontilhado).
            con.execute(
                "INSERT INTO capitulo (obra, titulo, pagina) VALUES (?,?,?)",
                (id_obra, texto, par.pagina))
            capitulo_atual = con.execute(
                "SELECT last_insert_rowid()").fetchone()[0]
            continue

        if comentario_versiculo:
            mc = _CAPITULO_DA.match(par.primeira_linha.strip())
            if mc:
                livro = 27 if mc.group(1) == "Daniel" else 66
                cap_da = (livro, int(mc.group(2)))
            mv = _VERSICULOS.match(texto)
            if mv and cap_da:
                fechar_secao()
                numeros = [int(mv.group(1))] + [
                    int(x) for x in re.findall(r"\d+", mv.group(2))]
                livro, cap = cap_da
                secao = [novo_id(), livro, cap * 1000 + min(numeros),
                         cap * 1000 + max(numeros), list(par.segmentos),
                         par.pagina, par.pagina_original]
                continue
            if secao is not None:
                if mc or len(secao[4]) > 40:
                    fechar_secao()
                    secao = None
                else:
                    secao[4].extend(par.segmentos)

        mb = _BASEADO.match(texto)
        refs = encontrar(mb.group(1) if mb else texto,
                         capitulos_inteiros=True)
        if not refs:
            continue
        tid = novo_id()
        ancora = None if mb else _ancora(texto, refs[0])
        segmentos = (_abertura_capitulo(lista, indice) if mb
                     else _contexto(lista, indice))
        con.execute(
            "INSERT INTO trecho VALUES (?,?,?,?,?,?,?)",
            (tid, id_obra, capitulo_atual, segmentos[0][0], par.pagina_original,
             segmentos_para_texto(segmentos), ancora))
        vistos = set()
        for r in refs:
            chave = (r.livro, r.ini, r.fim)
            if chave in vistos:
                continue
            vistos.add(chave)
            con.execute("INSERT INTO ref_obra VALUES (?,?,?,?,?)",
                        (r.livro, r.ini, r.fim, tid, 1 if mb else 0))
            n_refs += 1
    if comentario_versiculo:
        fechar_secao()
    return n_refs


def main():
    os.makedirs(CACHE, exist_ok=True)
    if os.path.exists(SAIDA):
        os.remove(SAIDA)
    con = sqlite3.connect(SAIDA)
    con.executescript(ESQUEMA)
    total = 0
    for i, (arquivo, sigla, grupo, prioridade, autor) in \
            enumerate(obras.todas(), start=1):
        caminho = baixar(arquivo)
        with open(caminho, "rb") as f:
            dados = f.read()
        titulo, paginas = _metadados(caminho)
        con.execute(
            "INSERT INTO obra VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (i, arquivo, sigla, _titulo_limpo(titulo, arquivo), autor, grupo,
             prioridade, obras.url(arquivo), len(dados),
             hashlib.sha256(dados).hexdigest(), paginas))
        n = indexar_obra(con, i, arquivo, arquivo in obras.COMENTARIO_VERSICULO)
        total += n
        print("%-6s %6d referências  %s" % (sigla, n, arquivo))
        con.commit()
    con.execute("CREATE INDEX ix_ref_obra ON ref_obra (livro, ini)")
    con.commit()
    print("Total: %d referências em %d trechos" % (
        total, con.execute("SELECT count(*) FROM trecho").fetchone()[0]))
    con.close()


if __name__ == "__main__":
    main()
