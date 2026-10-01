r"""Reconhece referências bíblicas escritas em português dentro de um texto.

É o que liga cada versículo aos trechos de Ellen G. White e dos pioneiros: os
livros citam a Bíblia por extenso ("Mateus 4:2-4", "1 João 3:2", "Apocalipse
3:7, 8") e às vezes abreviado ("Rm 6:23", "1Co 13:4"). Cada ocorrência vira um
intervalo de versículos.

O intervalo é guardado como dois inteiros, ``capitulo * 1000 + versiculo``:

    João 3:16        ->  (43, 3016, 3016)
    João 3:16, 17    ->  (43, 3016, 3017)
    Gênesis 4:25-6:2 ->  (1, 4025, 6002)
    Salmo 23         ->  (19, 23000, 23999)   capítulo inteiro

e o app acha as referências de um versículo com ``ini <= chave <= fim``.

Só o padrão do livro mais o capítulo (e, salvo exceções, os dois-pontos) é
aceito. "Testimonies for the Church 5:23", "Mensagens Escolhidas 1:45" e outras
obras citadas no mesmo formato não casam, porque o nome não é de um livro da
Bíblia.
"""
import re
import unicodedata

# Número do livro (ordem canônica, 1 a 66) e os nomes por que é chamado. O
# primeiro de cada lista é o nome de exibição.
LIVROS = {
    1: ["Gênesis", "Genesis", "Gn", "Gên", "Gen"],
    2: ["Êxodo", "Exodo", "Ex", "Êx"],
    3: ["Levítico", "Levitico", "Lv", "Lev"],
    4: ["Números", "Numeros", "Nm", "Núm"],
    5: ["Deuteronômio", "Deuteronomio", "Dt", "Deut"],
    6: ["Josué", "Josue", "Js"],
    7: ["Juízes", "Juizes", "Jz"],
    8: ["Rute", "Rt"],
    9: ["1 Samuel", "1Sm", "1 Sm"],
    10: ["2 Samuel", "2Sm", "2 Sm"],
    11: ["1 Reis", "1Rs", "1 Rs"],
    12: ["2 Reis", "2Rs", "2 Rs"],
    13: ["1 Crônicas", "1 Cronicas", "1Cr", "1 Cr"],
    14: ["2 Crônicas", "2 Cronicas", "2Cr", "2 Cr"],
    15: ["Esdras", "Ed"],
    16: ["Neemias", "Ne"],
    17: ["Ester", "Et", "Es"],
    18: ["Jó"],
    19: ["Salmos", "Salmo", "Sl"],
    20: ["Provérbios", "Proverbios", "Pv", "Prov"],
    21: ["Eclesiastes", "Ec", "Ecl"],
    22: ["Cantares", "Cantares de Salomão", "Cântico dos Cânticos",
         "Cânticos", "Canticos", "Ct", "Cn"],
    23: ["Isaías", "Isaias", "Is"],
    24: ["Jeremias", "Jr", "Jer"],
    25: ["Lamentações", "Lamentacoes", "Lamentações de Jeremias", "Lm"],
    26: ["Ezequiel", "Ez"],
    27: ["Daniel", "Dn"],
    28: ["Oséias", "Oseias", "Os"],
    29: ["Joel", "Jl"],
    30: ["Amós", "Amos", "Am"],
    31: ["Obadias", "Ob"],
    32: ["Jonas", "Jn"],
    33: ["Miquéias", "Miqueias", "Mq"],
    34: ["Naum", "Na"],
    35: ["Habacuque", "Hc"],
    36: ["Sofonias", "Sf"],
    37: ["Ageu", "Ag"],
    38: ["Zacarias", "Zc"],
    39: ["Malaquias", "Ml"],
    40: ["Mateus", "Mt"],
    41: ["Marcos", "Mc"],
    42: ["Lucas", "Lc"],
    43: ["João", "Joao", "Jo"],
    44: ["Atos", "Atos dos Apóstolos", "At"],
    45: ["Romanos", "Rm", "Rom"],
    46: ["1 Coríntios", "1 Corintios", "1Co", "1 Co", "1Cor", "1 Cor"],
    47: ["2 Coríntios", "2 Corintios", "2Co", "2 Co", "2Cor", "2 Cor"],
    48: ["Gálatas", "Galatas", "Gl", "Gál"],
    49: ["Efésios", "Efesios", "Ef"],
    50: ["Filipenses", "Fp", "Fl"],
    51: ["Colossenses", "Colossences", "Cl", "Col"],
    52: ["1 Tessalonicenses", "1Ts", "1 Ts"],
    53: ["2 Tessalonicenses", "2Ts", "2 Ts"],
    54: ["1 Timóteo", "1 Timoteo", "1Tm", "1 Tm", "1Tim"],
    55: ["2 Timóteo", "2 Timoteo", "2Tm", "2 Tm", "2Tim"],
    56: ["Tito", "Tt"],
    57: ["Filemom", "Filemon", "Fm"],
    58: ["Hebreus", "Hb"],
    59: ["Tiago", "Tg"],
    60: ["1 Pedro", "1Pe", "1 Pe", "1Pd", "1 Pd"],
    61: ["2 Pedro", "2Pe", "2 Pe", "2Pd", "2 Pd"],
    62: ["1 João", "1 Joao", "1Jo", "1 Jo"],
    63: ["2 João", "2 Joao", "2Jo", "2 Jo"],
    64: ["3 João", "3 Joao", "3Jo", "3 Jo"],
    65: ["Judas", "Jd"],
    66: ["Apocalipse", "Ap", "Apoc"],
}

# Capítulos de cada livro: referência a capítulo inexistente é descartada
# (pega "Atos 45:3" que na verdade era outra coisa).
CAPITULOS = [
    50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42,
    150, 31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4,
    28, 16, 24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5,
    3, 5, 1, 1, 1, 22,
]

# Livros de um capítulo só: "Judas 3" é o versículo 3, não o capítulo 3.
_UM_CAPITULO = {31, 57, 63, 64, 65}

# Abreviações curtas que também são palavras comuns ("Os", "Na", "Am", "Is",
# "Ed"...) só valem com dois-pontos ("Os 6:6"); nunca como capítulo inteiro.
_AMBIGUAS = {
    "Ex", "Ed", "Et", "Es", "Is", "Os", "Am", "Na", "Ag", "At", "Jo", "Jn",
    "Ne", "Ob", "Ct", "Cn", "Ec", "Ez", "Fm", "Fl", "Gl", "Cl", "Ap", "Mt",
    "Mc", "Lc", "Jr", "Jl", "Jd", "Lm", "Ml", "Hc", "Rt", "Js", "Jz", "Sl",
    "Pv", "Dn", "Mq", "Sf", "Zc", "Hb", "Tg", "Rm", "Ef", "Fp", "Tt",
    "Gn", "Lv", "Nm", "Dt", "Gen", "Lev", "Col", "Rom", "Jer", "Ecl",
    "Gál", "Gên", "Êx", "Núm", "Deut", "Prov", "Apoc", "Amos",
}

_ORDINAIS = {
    "1": "1", "2": "2", "3": "3",
    "I": "1", "II": "2", "III": "3",
    "1ª": "1", "2ª": "2", "3ª": "3",
    "1.ª": "1", "2.ª": "2", "3.ª": "3",
    "1º": "1", "2º": "2", "3º": "3",
    "Primeira": "1", "Segunda": "2", "Terceira": "3",
    "Primeiro": "1", "Segundo": "2",
}


def _sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


def _montar():
    """Mapa nome -> livro e a regex que casa qualquer um dos nomes.

    "1 Coríntios" também é escrito "I Coríntios", "1ª Coríntios", "Primeira
    Coríntios"; os ordinais são expandidos aqui em vez de repetidos na tabela.
    """
    nomes = {}
    for livro, lista in LIVROS.items():
        for nome in lista:
            m = re.match(r"^([123]) ?(.*)$", nome)
            if m:
                for ordinal, n in _ORDINAIS.items():
                    if n == m.group(1):
                        nomes[ordinal + " " + m.group(2)] = livro
                        if ordinal.isdigit():
                            nomes[ordinal + m.group(2)] = livro
            else:
                nomes[nome] = livro
    # Mais longo primeiro: "1 João" antes de "João", "Cantares de Salomão"
    # antes de "Cantares".
    alternativas = sorted(nomes, key=len, reverse=True)
    padrao = "|".join(re.escape(n).replace(r"\ ", r"\s+") for n in alternativas)
    return nomes, padrao


_NOMES, _PADRAO_NOMES = _montar()
_NOMES_CHAVE = {re.sub(r"\s+", " ", k): v for k, v in _NOMES.items()}

_HIFEN = r"\s*[-–—]\s*"

# Livro + capítulo, opcionalmente :versículo e o fim do intervalo. A palavra
# não pode vir colada a outra letra antes ("Joaquim 3:2" não é João).
_REF = re.compile(
    r"(?<![\wÀ-ÿ])(?P<livro>" + _PADRAO_NOMES + r")\.?\s+"
    r"(?P<cap>\d{1,3})"
    r"(?:\s*:\s*(?P<ver>\d{1,3})"
    r"(?:" + _HIFEN + r"(?P<a>\d{1,3})(?:\s*:\s*(?P<b>\d{1,3}))?)?"
    r")?"
    r"(?![\d\wÀ-ÿ])"
)

# Continuações depois da primeira referência:
#   ", 17"       mais um versículo do mesmo capítulo
#   ", 17-20"    mais um intervalo
#   "; 6:9"      outro capítulo do mesmo livro
#   "; 6"        outro capítulo inteiro (só onde capítulos inteiros valem)
_CONT_VERSO = re.compile(
    r"\s*,\s*(?P<v>\d{1,3})(?:" + _HIFEN + r"(?P<a>\d{1,3}))?(?![\d:\wÀ-ÿ])")
_CONT_CAP = re.compile(
    r"\s*;\s*(?P<c>\d{1,3})(?:\s*:\s*(?P<v>\d{1,3})"
    r"(?:" + _HIFEN + r"(?P<a>\d{1,3})(?:\s*:\s*(?P<b>\d{1,3}))?)?)?"
    r"(?![\d\wÀ-ÿ])")


def livro_por_nome(nome):
    return _NOMES_CHAVE.get(re.sub(r"\s+", " ", nome))


def _chave(c, v):
    return c * 1000 + v


def _intervalo(livro, cap, ver, a, b):
    """(ini, fim) ou None, conferindo os limites do livro."""
    if livro in _UM_CAPITULO and ver is None:
        # "Judas 3", "Filemom 10": o número é o versículo.
        cap, ver = 1, cap
    if not 1 <= cap <= CAPITULOS[livro - 1]:
        return None
    if ver is None:
        return _chave(cap, 0), _chave(cap, 999)
    if ver == 0:
        return None
    ini = _chave(cap, ver)
    if a is None:
        return ini, ini
    if b is not None:
        # Gênesis 4:25-6:2
        if not cap <= a <= CAPITULOS[livro - 1] or b == 0:
            return None
        fim = _chave(a, b)
    else:
        fim = _chave(cap, a)
    if fim < ini:
        return None
    return ini, fim


class Referencia:
    __slots__ = ("livro", "ini", "fim", "inicio", "final")

    def __init__(self, livro, ini, fim, inicio, final):
        self.livro = livro
        self.ini = ini
        self.fim = fim
        # Posição no texto analisado (do nome do livro ao fim da referência).
        self.inicio = inicio
        self.final = final

    def __repr__(self):
        return "Referencia(%d, %d, %d)" % (self.livro, self.ini, self.fim)

    def tupla(self):
        return (self.livro, self.ini, self.fim)


def encontrar(texto, capitulos_inteiros=True):
    """Todas as referências bíblicas de ``texto``, na ordem em que aparecem.

    ``capitulos_inteiros``: aceitar "Salmo 23" (sem versículo). Vale para nomes
    por extenso; as abreviações ambíguas exigem sempre os dois-pontos.
    """
    achadas = []
    pos = 0
    while True:
        m = _REF.search(texto, pos)
        if not m:
            break
        nome = re.sub(r"\s+", " ", m.group("livro"))
        livro = _NOMES_CHAVE[nome]
        cap = int(m.group("cap"))
        ver = int(m.group("ver")) if m.group("ver") else None
        a = int(m.group("a")) if m.group("a") else None
        b = int(m.group("b")) if m.group("b") else None
        pos = m.end()

        if ver is None:
            sem_numero = re.sub(r"^[123]\s*|^I{1,3}\s+", "", nome)
            ambigua = nome in _AMBIGUAS or sem_numero in _AMBIGUAS
            if (not capitulos_inteiros or ambigua) and \
                    livro not in _UM_CAPITULO:
                continue
            if ambigua and livro in _UM_CAPITULO:
                continue
        intervalo = _intervalo(livro, cap, ver, a, b)
        if intervalo is None:
            continue
        inicio = m.start()
        partes = [intervalo]
        cap_atual = cap if b is None else a

        # Continuações: ", 17", "; 6:9"
        while True:
            mv = _CONT_VERSO.match(texto, pos) if ver is not None else None
            if mv:
                v = int(mv.group("v"))
                va = int(mv.group("a")) if mv.group("a") else None
                iv = _intervalo(livro, cap_atual, v, va, None)
                if iv is None:
                    break
                partes.append(iv)
                pos = mv.end()
                continue
            mc = _CONT_CAP.match(texto, pos)
            if mc:
                c = int(mc.group("c"))
                v = int(mc.group("v")) if mc.group("v") else None
                if v is None and not capitulos_inteiros:
                    break
                va = int(mc.group("a")) if mc.group("a") else None
                vb = int(mc.group("b")) if mc.group("b") else None
                iv = _intervalo(livro, c, v, va, vb)
                if iv is None:
                    break
                partes.append(iv)
                ver = v
                cap_atual = c if vb is None else va
                pos = mc.end()
                continue
            break

        # "João 3:16, 17" vira um intervalo só (3016-3017); "Mateus 5:3; 6:9"
        # ficam dois. Junta o que for contíguo ou sobreposto.
        partes.sort()
        unidas = [list(partes[0])]
        for ini, fim in partes[1:]:
            if ini <= unidas[-1][1] + 1:
                unidas[-1][1] = max(unidas[-1][1], fim)
            else:
                unidas.append([ini, fim])
        for ini, fim in unidas:
            achadas.append(Referencia(livro, ini, fim, inicio, pos))
    return achadas


def nome_livro(livro):
    return LIVROS[livro][0]


def formatar(livro, ini, fim):
    """Volta ao texto: (43, 3016, 3017) -> "João 3:16-17"."""
    c1, v1 = divmod(ini, 1000)
    c2, v2 = divmod(fim, 1000)
    nome = nome_livro(livro)
    if v1 == 0 and v2 == 999:
        return "%s %d" % (nome, c1) if c1 == c2 else "%s %d-%d" % (nome, c1, c2)
    if ini == fim:
        return "%s %d:%d" % (nome, c1, v1)
    if c1 == c2:
        return "%s %d:%d-%d" % (nome, c1, v1, v2)
    return "%s %d:%d-%d:%d" % (nome, c1, v1, c2, v2)


def sem_acento(s):
    return _sem_acento(s)
