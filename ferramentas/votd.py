r"""Gera o calendario do Versiculo do Dia para o asset do app.

A API da YouVersion (/v1/verse_of_the_days) devolve apenas a **referencia** de
cada dia do ano, nunca o texto:

    {"day": 1, "passage_id": "ISA.43.18-19"}

Por isso o app nao precisa da API em tempo de execucao: esta ferramenta busca o
calendario uma vez aqui no PC, converte o codigo USFM do livro para o `numero`
usado em `biblia_livro` e grava um JSON de ~30 KB no assets/. No celular o texto
sai do proprio banco offline, na traducao que o usuario escolheu - sem rede, sem
chave embutida no APK e sem limite de requisicoes.

A chave vem da variavel de ambiente YVP_APP_KEY (nunca gravada no repositorio):

    set YVP_APP_KEY=sua_chave
    python ferramentas/votd.py

Origem : https://api.youversion.com/v1/verse_of_the_days
Destino: assets/versiculo_do_dia.json
"""
import json
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.request
from datetime import date

URL = "https://api.youversion.com/v1/verse_of_the_days"
BANCO = os.path.join(os.path.dirname(__file__), "louvorja_pt.db")
DST = os.path.join(os.path.dirname(__file__), "..", "assets", "versiculo_do_dia.json")

# Ordem canonica: indice + 1 == biblia_livro.numero
CANON = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA",
    "1KI", "2KI", "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO",
    "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO",
    "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL", "MAT",
    "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP",
    "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
    "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]
NUMERO = {codigo: i + 1 for i, codigo in enumerate(CANON)}

# LIV.CAP.VER, LIV.CAP.VER-VER ou LIV.CAP.VER-LIV.CAP.VER
REF = re.compile(r"^([1-3A-Z]{3})\.(\d+)\.(\d+)(?:-(?:([1-3A-Z]{3})\.(\d+)\.)?(\d+))?$")


def buscar(chave):
    req = urllib.request.Request(URL, headers={
        "X-YVP-App-Key": chave,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            dados = json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit("ERRO HTTP %d: %s" % (e.code, e.read()[:200].decode("replace")))
    return dados.get("data", dados) if isinstance(dados, dict) else dados


def converter(passage_id):
    """'ISA.43.18-19' -> (23, 43, 18, 19). None se nao reconhecer."""
    m = REF.match(passage_id)
    if not m:
        return None
    livro, cap, v1, livro2, cap2, v2 = m.groups()
    # Intervalos que cruzam livro ou capitulo o app nao sabe renderizar.
    if (livro2 and livro2 != livro) or (cap2 and int(cap2) != int(cap)):
        return None
    numero = NUMERO.get(livro)
    if numero is None:
        return None
    return numero, int(cap), int(v1), int(v2) if v2 else int(v1)


def validar(con, dias):
    """Confere se cada referencia existe em TODAS as traducoes do banco.

    As versoes tem contagens diferentes (31.102 a 31.106 versiculos), entao uma
    referencia pode faltar em alguma traducao e a tela sairia vazia naquele dia.
    """
    versoes = con.execute("select id, sigla from biblia_versao order by id").fetchall()
    buracos = []
    for d in dias:
        esperado = d["ate"] - d["versiculo"] + 1
        for id_versao, sigla in versoes:
            achados = con.execute(
                "select count(*) from biblia_versiculo where id_versao=?"
                " and id_livro=? and capitulo=? and versiculo between ? and ?",
                (id_versao, d["livro"], d["capitulo"], d["versiculo"], d["ate"]),
            ).fetchone()[0]
            if achados != esperado:
                buracos.append((d["dia"], d["ref"], sigla, achados, esperado))
    return versoes, buracos


chave = os.environ.get("YVP_APP_KEY")
if not chave:
    sys.exit("Defina YVP_APP_KEY antes de rodar (veja o cabecalho deste arquivo).")
if not os.path.exists(BANCO):
    sys.exit("ERRO: %s nao encontrado. Rode build_db.py antes." % BANCO)

print("buscando calendario...")
bruto = buscar(chave)
print("  %d entradas recebidas" % len(bruto))

dias, ignorados = [], []
for item in bruto:
    ref = item.get("passage_id", "")
    conv = converter(ref)
    if conv is None:
        ignorados.append((item.get("day"), ref))
        continue
    livro, capitulo, v1, v2 = conv
    dias.append({
        "dia": item["day"],
        "livro": livro,
        "capitulo": capitulo,
        "versiculo": v1,
        "ate": v2,
        "ref": ref,
    })
dias.sort(key=lambda d: d["dia"])

if ignorados:
    print("  %d referencias ignoradas (formato nao suportado):" % len(ignorados))
    for dia, ref in ignorados[:5]:
        print("     dia %s -> %s" % (dia, ref))

con = sqlite3.connect("file:" + BANCO.replace("\\", "/") + "?mode=ro", uri=True)
versoes, buracos = validar(con, dias)

print("\n=== validacao ===")
print("  dias convertidos  %7d" % len(dias))
print("  traducoes         %7d" % len(versoes))
print("  com intervalo     %7d" % sum(1 for d in dias if d["ate"] > d["versiculo"]))
print("  lacunas           %7d" % len(buracos))
for dia, ref, sigla, achados, esperado in buracos[:10]:
    print("     dia %3d %-16s %-6s %d/%d versiculos" % (dia, ref, sigla, achados, esperado))

faltando = sorted(set(range(1, 367)) - {d["dia"] for d in dias})
if faltando:
    print("  DIAS SEM VERSICULO: %s" % faltando[:10])

saida = {
    "origem": "YouVersion Platform - /v1/verse_of_the_days",
    "gerado_em": date.today().isoformat(),
    "observacao": "Apenas referencias. O texto vem do banco offline do app.",
    "dias": dias,
}
with open(DST, "w", encoding="utf-8", newline="\n") as f:
    json.dump(saida, f, ensure_ascii=False, indent=0, separators=(",", ":"))
    f.write("\n")

print("\ndestino: %s (%.1f KB)" % (os.path.normpath(DST), os.path.getsize(DST) / 1024))

hoje = date.today().timetuple().tm_yday
atual = next((d for d in dias if d["dia"] == hoje), None)
if atual:
    nome = con.execute("select nome from biblia_livro where numero=?",
                       (atual["livro"],)).fetchone()[0]
    texto = " ".join(t for (t,) in con.execute(
        "select texto from biblia_versiculo where id_versao=5 and id_livro=?"
        " and capitulo=? and versiculo between ? and ? order by versiculo",
        (atual["livro"], atual["capitulo"], atual["versiculo"], atual["ate"])))
    faixa = ("%d-%d" % (atual["versiculo"], atual["ate"])
             if atual["ate"] > atual["versiculo"] else str(atual["versiculo"]))
    print("\nhoje (dia %d) - %s %d:%s (NVI):" % (hoje, nome, atual["capitulo"], faixa))
    print("  %s" % texto[:220])
con.close()
