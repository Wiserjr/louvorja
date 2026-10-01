"""Leitura do texto dos PDFs com o PDFium — o mesmo motor que o app usa.

Isto é o que permite ao app mostrar o parágrafo exato sem levar o texto: aqui,
no PC, cada parágrafo vira uma lista de segmentos ``(página, início, fim)``
contados em unidades UTF-16 sobre o texto cru da página, exatamente como o
``PdfPage.loadText()`` do pdfrx o devolve no aparelho (um caractere por
``FPDFText_GetUnicode``). O app recorta os mesmos intervalos e aplica a mesma
``normalizar()`` — a versão em Dart está em ``lib/dados/trechos.dart`` e as duas
são testadas com os mesmos casos.
"""
import re

import pypdfium2 as pdfium
import pypdfium2.raw as raw

# Pronomes que seguem hífen de verdade ("intitulou-se", "dá-lhe"). Quando a
# quebra de linha cai no hífen, o PDFium devolve \x02 no lugar dele e não dá
# para saber se era hífen de palavra composta ou de separação de sílabas; com
# pronome depois, é composto.
ENCLITICOS = {
    "se", "lhe", "lhes", "o", "a", "os", "as", "me", "te", "nos", "vos",
    "lo", "la", "los", "las", "no", "na", "nas", "mo", "ma", "ei", "ão",
    "á", "ás", "ia", "iam", "emos",
}

_MARCA = re.compile(r"\[\d{1,4}\]\s?")
_ESPACOS = re.compile(r"\s+")


def _quebra(m):
    seguinte = m.group(1)
    return ("-" if seguinte.lower() in ENCLITICOS else "") + seguinte


def normalizar(cru):
    """Texto cru de um trecho -> texto de leitura.

    Junta as linhas, desfaz a separação de sílabas, tira as marcas de página
    original ("[72]") e os espaços repetidos.
    """
    s = cru.replace("­", "\x02")
    # Hífen de fim de linha: \x02 (quando o PDF marca a separação) ou "-"
    # seguido da quebra.
    s = re.sub(r"(?:\x02\s*|-\r?\n\s*)(\w+)", _quebra, s)
    s = s.replace("\x02", "")
    s = _MARCA.sub("", s)
    s = _ESPACOS.sub(" ", s)
    return s.strip()


def _utf16(s):
    return len(s.encode("utf-16-le")) // 2


class Linha:
    __slots__ = ("pagina", "ini", "fim", "x", "texto", "cabecalho")

    def __init__(self, pagina, ini, fim, x, texto):
        self.pagina = pagina
        self.ini = ini  # UTF-16, no texto cru da página
        self.fim = fim
        self.x = x
        self.texto = texto
        self.cabecalho = False


class Pagina:
    __slots__ = ("indice", "texto", "linhas")

    def __init__(self, indice, texto, linhas):
        self.indice = indice
        self.texto = texto
        self.linhas = linhas


def ler_paginas(caminho):
    """Gera ``Pagina`` com o texto cru e as linhas (posição x do 1º caractere).

    O texto é montado caractere a caractere, como o pdfrx faz, e não com
    ``get_text_range``, que normaliza quebras de linha de outro jeito.
    """
    doc = pdfium.PdfDocument(caminho)
    try:
        for i in range(len(doc)):
            pagina = doc[i]
            tp = pagina.get_textpage()
            n = tp.count_chars()
            cods = [raw.FPDFText_GetUnicode(tp.raw, k) for k in range(n)]
            texto = "".join(chr(c) for c in cods)
            # Offsets em UTF-16, para casar com String do Dart.
            u16 = []
            acc = 0
            for c in cods:
                u16.append(acc)
                acc += 2 if c > 0xFFFF else 1
            u16.append(acc)

            linhas = []
            pos = 0
            for trecho in texto.split("\r\n"):
                fim = pos + len(trecho)
                if trecho.strip():
                    # x do primeiro caractere que não seja marca de página
                    # original: "[70] porta aberta" fica na margem esquerda.
                    m = _MARCA.match(trecho)
                    desloc = m.end() if m else 0
                    while desloc < len(trecho) and trecho[desloc].isspace():
                        desloc += 1
                    k = min(pos + desloc, n - 1)
                    try:
                        x = tp.get_charbox(k)[0]
                    except Exception:
                        x = 0.0
                    linhas.append(Linha(i, u16[pos], u16[fim], x, trecho))
                pos = fim + 2
            yield Pagina(i, texto, linhas)
            tp.close()
            pagina.close()
    finally:
        doc.close()


_CABECALHO = [
    re.compile(r"^\s*\d{1,4}\s*\|"),            # "14 | DANIEL E APOCALIPSE"
    re.compile(r"\|\s*\d{1,4}\s*$"),            # "DANIEL E APOCALIPSE | 15"
    re.compile(r"^\s*\d{1,4}\s+\S.{0,80}$"),    # "82 O Desejado de Todas..."
    re.compile(r"^.{1,80}\S\s+\d{1,4}\s*$"),    # "O Desejado de Todas... 83"
    re.compile(r"^\s*[ivxlc]{1,6}\s*$"),         # numeração romana
    re.compile(r"^\s*\d{1,4}\s*$"),             # só o número
]


def _assinatura(texto):
    """Texto da linha sem números nem espaços: o cabeçalho "82 O Desejado de
    Todas as Nações" e o "O Desejado de Todas as Nações 83" têm a mesma."""
    return re.sub(r"[\d\s|]+", "", texto).lower()


def marcar_cabecalhos(paginas):
    """Cabeçalho e rodapé (título do livro e número da página) não fazem parte
    de parágrafo nenhum.

    Candidatas são a primeira e a última linha de cada página, curtas e com
    número. Viram cabeçalho as que se repetem (sem os números) em várias
    páginas do livro, ou que são só um número — assim uma linha de texto que
    por acaso comece com número ("12 apóstolos...") não some.
    """
    candidatas = []
    for pag in paginas:
        if not pag.linhas:
            continue
        for linha in {id(pag.linhas[0]): pag.linhas[0],
                      id(pag.linhas[-1]): pag.linhas[-1]}.values():
            t = linha.texto
            if len(t) <= 90 and any(p.search(t) for p in _CABECALHO) and \
                    not re.search(r"\d+:\d+\.?\s*$", t):
                candidatas.append(linha)
    contagem = {}
    deslocamentos = {}
    for linha in candidatas:
        a = _assinatura(linha.texto)
        contagem[a] = contagem.get(a, 0) + 1
        d = _deslocamento(linha)
        if d is not None:
            deslocamentos[d] = deslocamentos.get(d, 0) + 1
    # O número impresso na página anda junto com o índice do PDF: a diferença
    # entre os dois é a mesma no livro todo (ou em longos trechos dele). É o
    # que pega o cabeçalho que muda a cada capítulo ("O primeiro advento de
    # Cristo 167"), que não se repete o bastante para a outra regra.
    frequentes = {d for d, n in deslocamentos.items() if n >= 5}
    for linha in candidatas:
        a = _assinatura(linha.texto)
        if not a or len(a) <= 6 and re.fullmatch(r"[ivxlc]+", a) or \
                contagem[a] >= 3 or _deslocamento(linha) in frequentes:
            linha.cabecalho = True


def _deslocamento(linha):
    m = re.match(r"^\s*(\d{1,4})\b", linha.texto) or \
        re.search(r"\b(\d{1,4})\s*$", linha.texto)
    return int(m.group(1)) - linha.pagina if m else None


class Paragrafo:
    __slots__ = ("segmentos", "texto", "pagina", "pagina_original", "capitulo",
                 "primeira_linha", "ultima")

    def __init__(self):
        self.segmentos = []  # [(pagina, ini, fim)]
        self.texto = ""
        self.pagina = 0
        self.pagina_original = None
        self.capitulo = None
        self.primeira_linha = ""
        self.ultima = ""


_INICIO_FORCADO = re.compile(
    r"^\s*(Capítulo\s+\d+|CAPÍTULO\s+\d+|Este capítulo é baseado|"
    r"VERS[ÍI]CULOS?\s+\d)")


def paragrafos(caminho):
    """Divide o livro em parágrafos, atravessando páginas.

    Parágrafo novo começa em linha recuada em relação à margem da página (o
    recuo de primeira linha), em linha centralizada (títulos) ou em linha que
    abre capítulo. A margem é a menor posição x das linhas da página, calculada
    por página porque páginas pares e ímpares têm margens diferentes.
    """
    paginas = list(ler_paginas(caminho))
    marcar_cabecalhos(paginas)
    atual = None
    ultima_marca = None
    pag_textos = {}
    for pag in paginas:
        corpo = [ln for ln in pag.linhas if not ln.cabecalho]
        if not corpo:
            continue
        xs = sorted(ln.x for ln in corpo if len(ln.texto.strip()) > 25)
        margem = xs[len(xs) // 10] if xs else min(ln.x for ln in corpo)
        for ln in corpo:
            novo = (atual is None or ln.x - margem > 8 or
                    _INICIO_FORCADO.match(ln.texto) is not None)
            if novo and atual is not None and \
                    atual.primeira_linha.startswith("Este capítulo é baseado") \
                    and not atual.ultima.rstrip().endswith("."):
                # A lista de passagens quebrou em linha centralizada:
                # "baseado em Mateus 4:1-11; Marcos 1:12, 13; Lucas" / "4:1-13."
                novo = False
            if novo:
                if atual is not None:
                    yield _fechar(atual, pag_textos)
                atual = Paragrafo()
                atual.pagina = ln.pagina
                atual.pagina_original = ultima_marca
                atual.primeira_linha = ln.texto
                pag_textos = {}
            atual.ultima = ln.texto
            seg = atual.segmentos
            if seg and seg[-1][0] == ln.pagina:
                seg[-1] = (ln.pagina, seg[-1][1], ln.fim)
            else:
                seg.append((ln.pagina, ln.ini, ln.fim))
            pag_textos[ln.pagina] = pag.texto
            for m in re.finditer(r"\[(\d{1,4})\]", ln.texto):
                ultima_marca = int(m.group(1))
                if atual.pagina_original is None:
                    atual.pagina_original = ultima_marca - 1
    if atual is not None:
        yield _fechar(atual, pag_textos)


def _cru_utf16(texto, ini, fim):
    """Recorta ``texto`` por posições UTF-16 (iguais às do Dart)."""
    b = texto.encode("utf-16-le")
    return b[ini * 2:fim * 2].decode("utf-16-le")


def _fechar(par, pag_textos):
    partes = [_cru_utf16(pag_textos[p], i, f) for p, i, f in par.segmentos]
    par.texto = normalizar("\r\n".join(partes))
    return par


def texto_dos_segmentos(paginas_cruas, segmentos):
    """O que o app faz: recorta os segmentos e normaliza."""
    partes = [_cru_utf16(paginas_cruas[p], i, f) for p, i, f in segmentos]
    return normalizar("\r\n".join(partes))


def segmentos_para_texto(segmentos):
    """[(p, i, f)] -> "p:i:f;p:i:f", o formato guardado no banco."""
    return ";".join("%d:%d:%d" % s for s in segmentos)
