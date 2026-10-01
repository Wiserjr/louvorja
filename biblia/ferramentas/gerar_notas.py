r"""Gera notas de estudo por versículo com a API do Claude (opcional).

    pip install anthropic pypdfium2
    python ferramentas/gerar_notas.py --simular --livros 43     (só mostra)
    python ferramentas/gerar_notas.py --livros 40-43            (evangelhos)
    python ferramentas/gerar_notas.py                           (Bíblia toda)
    python ferramentas/construir_estudo.py                      (põe no app)

Um pedido por capítulo (1.189 no total), enviados pela Batches API — metade
do preço da API normal, resultado em até 24 h (quase sempre em menos de 1 h).
Para cada capítulo o modelo recebe:

  - o texto do capítulo na ARA, numerado;
  - os trechos de Ellen G. White e dos pioneiros que o índice liga ao capítulo
    (lidos dos PDFs em ferramentas/cache/pdf, no seu PC), com a referência
    "DTN, p. 72" de cada um;
  - as citações do AT/NT e as passagens paralelas do capítulo.

e devolve notas curtas em JSON, no formato que o construir_estudo.py lê
(ferramentas/cache/notas.jsonl, uma linha por capítulo).

O script é retomável: capítulos que já estão no notas.jsonl não são enviados
de novo, e o lote em andamento fica anotado em cache/notas_lote.json — se o
PC desligar, rode de novo que ele continua de onde parou.

Credenciais: a variável ANTHROPIC_API_KEY, ou um perfil do `ant auth login`.
Custo estimado da Bíblia toda: algumas dezenas de dólares (veja --simular,
que conta os tokens de um capítulo).

As notas são texto gerado por IA. Revise antes de publicar — sobretudo as de
livros e temas doutrinários sensíveis — e diga no app que são geradas.
"""
import argparse
import gzip
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from referencias_pt import CAPITULOS, formatar, nome_livro  # noqa: E402

PASTA = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(PASTA)
CACHE = os.path.join(PASTA, "cache")
NOTAS = os.path.join(CACHE, "notas.jsonl")
LOTE = os.path.join(CACHE, "notas_lote.json")
OBRAS = os.path.join(CACHE, "obras.db")
BIBLIA = os.path.join(RAIZ, "assets", "biblia.db.gz")
ESTUDO = os.path.join(RAIZ, "assets", "estudo.db.gz")

MODELO = "claude-opus-5-5"
TRECHOS_POR_CAPITULO = 10
CARACTERES_POR_TRECHO = 900

SISTEMA = """\
Você escreve as notas de rodapé de uma Bíblia de estudo adventista em \
português do Brasil, no espírito da Bíblia de Estudo Andrews: notas curtas, \
fiéis ao texto, que ajudam a entender o versículo no seu contexto histórico, \
literário e teológico, e que o ligam ao conjunto das Escrituras.

Para cada capítulo, escreva notas sobre os versículos ou grupos de versículos \
que mais precisam de explicação — em média uma nota a cada dois ou três \
versículos. Cada nota tem de 1 a 4 frases e diz algo que o leitor não tiraria \
sozinho do texto: o sentido de uma palavra hebraica ou grega, um costume da \
época, a geografia, a ligação com outra passagem, o cumprimento de uma \
profecia, a aplicação para a vida cristã.

Use os trechos de Ellen G. White e dos pioneiros que acompanham o capítulo \
quando eles iluminarem o versículo, citando a referência exatamente como veio \
(por exemplo "DTN, p. 72"); resuma com suas palavras, sem copiar frases \
longas. Nunca invente citação, referência ou página que não esteja na lista. \
Quando o capítulo é citado no Novo Testamento (ou cita o Antigo), diga onde.

Mantenha a interpretação histórica e profética adventista onde ela se aplica \
(por exemplo em Daniel e Apocalipse, no sábado, no santuário, no estado dos \
mortos), apresentando-a com sobriedade. Não escreva introdução nem conclusão: \
só as notas."""

ESQUEMA = {
    "type": "object",
    "properties": {
        "notas": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "versiculo_inicial": {"type": "integer"},
                    "versiculo_final": {"type": "integer"},
                    "texto": {"type": "string"},
                },
                "required": ["versiculo_inicial", "versiculo_final", "texto"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["notas"],
    "additionalProperties": False,
}


def _abrir_gz(caminho, tmp):
    destino = os.path.join(tmp, os.path.basename(caminho)[:-3])
    with gzip.open(caminho) as g, open(destino, "wb") as f:
        shutil.copyfileobj(g, f)
    return sqlite3.connect(destino)


def _intervalo_livros(texto):
    if not texto:
        return list(range(1, 67))
    livros = []
    for parte in texto.split(","):
        if "-" in parte:
            a, b = parte.split("-")
            livros += range(int(a), int(b) + 1)
        else:
            livros.append(int(parte))
    return livros


class Contexto:
    """Monta o pedido de um capítulo."""

    def __init__(self, tmp):
        self.biblia = _abrir_gz(BIBLIA, tmp)
        self.estudo = _abrir_gz(ESTUDO, tmp)
        self.ara = self.biblia.execute(
            "SELECT id FROM versao WHERE sigla='ARA'").fetchone()[0]
        self._paginas = {}

    def _texto_trecho(self, arquivo, segmentos):
        from texto_pdf import ler_paginas, texto_dos_segmentos
        caminho = os.path.join(CACHE, "pdf", arquivo + ".pdf")
        if not os.path.exists(caminho):
            return None
        if arquivo not in self._paginas:
            # Um livro por vez na memória.
            self._paginas = {arquivo: [p.texto for p in ler_paginas(caminho)]}
        segs = [tuple(map(int, s.split(":"))) for s in segmentos.split(";")]
        return texto_dos_segmentos(self._paginas[arquivo], segs)

    def pedido(self, livro, cap):
        versos = self.biblia.execute(
            "SELECT versiculo, texto FROM versiculo WHERE versao=? AND "
            "livro=? AND capitulo=? ORDER BY versiculo",
            (self.ara, livro, cap)).fetchall()
        linhas = ["%d %s" % (v, re.sub(r"<[^>]+>", "", t)) for v, t in versos]

        ini, fim = cap * 1000, cap * 1000 + 999
        trechos = self.estudo.execute(
            "SELECT DISTINCT o.sigla, o.titulo, o.autor, o.arquivo, "
            "  t.pagina, t.pagina_original, t.segmentos, r.livro, r.ini, "
            "  r.fim, r.tipo, o.prioridade "
            "FROM ref_obra r JOIN trecho t ON t.id=r.trecho "
            "JOIN obra o ON o.id=t.obra "
            "WHERE r.livro=? AND r.ini<=? AND r.fim>=? AND r.fim-r.ini<2000 "
            "ORDER BY r.tipo=0, o.prioridade, r.fim-r.ini LIMIT ?",
            (livro, fim, ini, TRECHOS_POR_CAPITULO)).fetchall()
        blocos = []
        for (sigla, titulo, autor, arquivo, pag, pag_orig, segs, l, a, b,
             tipo, _) in trechos:
            texto = self._texto_trecho(arquivo, segs)
            if not texto:
                continue
            if len(texto) > CARACTERES_POR_TRECHO:
                texto = texto[:CARACTERES_POR_TRECHO].rsplit(" ", 1)[0] + "…"
            ref = "%s, p. %s" % (sigla, pag_orig or pag + 1)
            blocos.append("[%s] %s (%s) — sobre %s:\n%s" % (
                ref, titulo, autor, formatar(l, a, b), texto))

        citacoes = self.estudo.execute(
            "SELECT ini, livro2, ini2, fim2, tipo FROM ref_cruzada WHERE "
            "livro=? AND ini BETWEEN ? AND ? AND tipo IN (2, 3) ORDER BY ini",
            (livro, ini, fim)).fetchall()
        cit = ["%d -> %s (%s)" % (i % 1000, formatar(l2, a2, b2),
                                  "citação" if t == 2 else "paralelo")
               for i, l2, a2, b2, t in citacoes]

        partes = ["# %s %d (ARA)\n\n%s" % (nome_livro(livro), cap,
                                          "\n".join(linhas))]
        if cit:
            partes.append("# Citações e paralelos\n\n" + "\n".join(cit))
        if blocos:
            partes.append("# Trechos de Ellen G. White e pioneiros\n\n" +
                          "\n\n".join(blocos))
        else:
            partes.append("# Trechos de Ellen G. White e pioneiros\n\n"
                          "(nenhum trecho indexado cita este capítulo)")
        return "\n\n".join(partes), len(versos)


def _parametros(conteudo):
    return {
        "model": MODELO,
        "max_tokens": 16000,
        "system": SISTEMA,
        "output_config": {
            "effort": "medium",
            "format": {"type": "json_schema", "schema": ESQUEMA},
        },
        "messages": [{"role": "user", "content": conteudo}],
    }


def _feitos():
    feitos = set()
    # Capítulos que já têm notas escritas em ferramentas/notas/ não são
    # enviados (os evangelhos, por exemplo).
    pasta = os.path.join(PASTA, "notas")
    if os.path.isdir(pasta):
        for nome in os.listdir(pasta):
            m = re.match(r"^(\d+)-.*\.txt$", nome)
            if not m:
                continue
            with open(os.path.join(pasta, nome), encoding="utf-8") as f:
                for linha in f:
                    mc = re.match(r"^#\s*(\d+)\s*$", linha)
                    if mc:
                        feitos.add((int(m.group(1)), int(mc.group(1))))
    if os.path.exists(NOTAS):
        with open(NOTAS, encoding="utf-8") as f:
            for linha in f:
                if linha.strip():
                    d = json.loads(linha)
                    feitos.add((d["livro"], d["capitulo"]))
    return feitos


def _gravar(livro, cap, total_versos, notas):
    saida = []
    for n in notas:
        a, b = n["versiculo_inicial"], n["versiculo_final"]
        if not 1 <= a <= total_versos:
            continue
        b = min(max(a, b), total_versos)
        texto = n["texto"].strip()
        if texto:
            saida.append({"ini": cap * 1000 + a, "fim": cap * 1000 + b,
                          "texto": texto})
    with open(NOTAS, "a", encoding="utf-8") as f:
        f.write(json.dumps({"livro": livro, "capitulo": cap,
                            "notas": saida}, ensure_ascii=False) + "\n")
    return len(saida)


def _coletar(cliente, lote_id, versos):
    resultados = 0
    falhas = []
    for r in cliente.messages.batches.results(lote_id):
        livro, cap = map(int, r.custom_id.split("-")[1:])
        if r.result.type != "succeeded":
            falhas.append((r.custom_id, r.result.type))
            continue
        msg = r.result.message
        if msg.stop_reason != "end_turn":
            # refusal ou max_tokens: fica para a próxima rodada.
            falhas.append((r.custom_id, msg.stop_reason))
            continue
        texto = next((b.text for b in msg.content if b.type == "text"), "")
        try:
            notas = json.loads(texto)["notas"]
        except (ValueError, KeyError):
            falhas.append((r.custom_id, "json inválido"))
            continue
        _gravar(livro, cap, versos.get(r.custom_id, 999), notas)
        resultados += 1
    return resultados, falhas


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--livros", help="ex.: 40-43 ou 1,19,23 (padrão: todos)")
    ap.add_argument("--simular", action="store_true",
                    help="mostra o pedido do primeiro capítulo e conta tokens")
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)

    import anthropic
    cliente = anthropic.Anthropic()

    # Lote em andamento de uma rodada anterior: termina antes de criar outro.
    if os.path.exists(LOTE) and not args.simular:
        with open(LOTE, encoding="utf-8") as f:
            pendente = json.load(f)
        _aguardar_e_coletar(cliente, pendente["id"], pendente["versos"])
        os.remove(LOTE)

    tmp = tempfile.mkdtemp()
    try:
        ctx = Contexto(tmp)
        feitos = _feitos()
        pedidos, versos = [], {}
        for livro in _intervalo_livros(args.livros):
            for cap in range(1, CAPITULOS[livro - 1] + 1):
                if (livro, cap) in feitos:
                    continue
                conteudo, n = ctx.pedido(livro, cap)
                cid = "cap-%d-%d" % (livro, cap)
                versos[cid] = n
                pedidos.append({"custom_id": cid,
                                "params": _parametros(conteudo)})
                if args.simular:
                    break
            if args.simular and pedidos:
                break

        if not pedidos:
            print("Todos os capítulos pedidos já têm notas em", NOTAS)
            return
        if args.simular:
            p = pedidos[0]["params"]
            print(p["messages"][0]["content"])
            contagem = cliente.messages.count_tokens(
                model=MODELO, system=SISTEMA, messages=p["messages"])
            print("\n--- %d tokens de entrada neste capítulo (sem contar o "
                  "esquema)" % contagem.input_tokens)
            return

        print("Enviando %d capítulos em lote…" % len(pedidos))
        lote = cliente.messages.batches.create(requests=pedidos)
        with open(LOTE, "w", encoding="utf-8") as f:
            json.dump({"id": lote.id, "versos": versos}, f)
        _aguardar_e_coletar(cliente, lote.id, versos)
        os.remove(LOTE)
    finally:
        shutil.rmtree(tmp)


def _aguardar_e_coletar(cliente, lote_id, versos):
    print("Lote", lote_id)
    while True:
        lote = cliente.messages.batches.retrieve(lote_id)
        if lote.processing_status == "ended":
            break
        c = lote.request_counts
        print("  processando: %d · prontos: %d · com erro: %d" % (
            c.processing, c.succeeded, c.errored))
        time.sleep(60)
    feitos, falhas = _coletar(cliente, lote_id, versos)
    print("%d capítulos com notas gravados em %s" % (feitos, NOTAS))
    if falhas:
        print("%d falharam e serão reenviados na próxima rodada:" % len(falhas))
        for cid, motivo in falhas[:20]:
            print("  ", cid, motivo)
    print("Agora rode: python ferramentas/construir_estudo.py")


if __name__ == "__main__":
    main()
