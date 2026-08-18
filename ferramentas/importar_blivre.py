r"""Importa a Biblia Livre (BLIVRE) para o banco do LouvorJA desktop.

A BLIVRE e a unica traducao completa em portugues que pode ser redistribuida
dentro do APK: esta sob Creative Commons Atribuicao 3.0 Brasil, por Diego
Santos, Mario Sergio e Marco Teles. As outras dez versoes do acervo sao
proprietarias.

Roda **antes** do build_db.py: grava no database.db do desktop, que e a fonte
de onde o catalogo do app e gerado.

    python ferramentas/importar_blivre.py --sem-titulos --aplicar
    python ferramentas/build_db.py

Por padrao NAO toca no banco - gera um .sql para revisao. Com --aplicar, faz
backup antes e restaura sozinho se algo falhar.

Origem : https://github.com/blivre/BibliaLivre (release 2018.2.0)
Destino: C:\Program Files (x86)\Louvor JA\config\database.db
"""
import argparse
import io
import os
import re
import shutil
import sqlite3
import sys
import urllib.request
import zipfile
from datetime import datetime

BANCO_PADRAO = r"C:\Program Files (x86)\Louvor JA\config\database.db"
RELEASE = "https://github.com/blivre/BibliaLivre/releases/download/2018.2.0/bliv-{ed}_vpl.zip"

EDICOES = {
    "n4": ("Bíblia Livre", "BLIVRE", "Nestle 1904 (texto critico)"),
    "tr": ("Bíblia Livre (Textus Receptus)", "BLIVRE-TR", "Textus Receptus"),
}

# Ordem canonica: indice na lista + 1 == book_number == id_bible_book no Louvor JA.
# Codigos em USFM padrao; ver ALIASES para os codigos proprios da BLIVRE.
CANON = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA",
    "1KI", "2KI", "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO",
    "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO",
    "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL", "MAT",
    "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP",
    "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
    "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]

CAPS_ESPERADOS = [
    50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42,
    150, 31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4,
    28, 16, 24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5,
    3, 5, 1, 1, 1, 22,
]

# A BLIVRE usa codigos proprios em 8 livros. Mapeamos para o USFM padrao
# para que o script continue funcionando se a fonte migrar para USFM.
ALIASES = {
    "SOL": "SNG",  # Canticos
    "EZE": "EZK",  # Ezequiel
    "JOE": "JOL",  # Joel
    "NAH": "NAM",  # Naum
    "MAR": "MRK",  # Marcos
    "JOH": "JHN",  # Joao
    "PHI": "PHP",  # Filipenses
    "JAM": "JAS",  # Tiago
    "1JO": "1JN",
    "2JO": "2JN",
    "3JO": "3JN",
}

LINHA = re.compile(r"^(\S+)\s+(\d+):(\d+)\s+(.*)$")

# Em 103 versiculos (quase todos Salmos) a BLIVRE traz o titulo/sobrescrito
# colado ao texto, sem espaco: "Salmo de Davi:O SENHOR e meu pastor...".
# As demais versoes do Louvor JA nao trazem sobrescrito, entao projetar isso
# geraria inconsistencia na tela. --sem-titulos remove o prefixo.
SOBRESCRITO = re.compile(r"^[^:]{3,80}:(?=[A-ZÀ-Ú])")


def baixar(edicao, destino):
    if os.path.exists(destino):
        print("  usando arquivo local: %s" % destino)
        return
    url = RELEASE.format(ed=edicao)
    print("  baixando %s" % url)
    with urllib.request.urlopen(url, timeout=120) as r, open(destino, "wb") as f:
        shutil.copyfileobj(r, f)


def ler_versiculos(zip_path, sem_titulos=False):
    """Devolve [(book_number, capitulo, versiculo, texto)]."""
    with zipfile.ZipFile(zip_path) as z:
        nome = next(n for n in z.namelist() if n.endswith(".txt"))
        texto = z.read(nome).decode("utf-8-sig")

    indice = {code: i + 1 for i, code in enumerate(CANON)}
    versiculos, desconhecidos = [], set()
    for linha in texto.splitlines():
        if not linha.strip():
            continue
        m = LINHA.match(linha)
        if not m:
            continue
        code, cap, ver, txt = m.groups()
        code = ALIASES.get(code, code)
        if code not in indice:
            desconhecidos.add(code)
            continue
        txt = txt.strip()
        if sem_titulos and int(ver) == 1:
            txt = SOBRESCRITO.sub("", txt).strip()
        versiculos.append((indice[code], int(cap), int(ver), txt))

    if desconhecidos:
        sys.exit("ERRO: codigos de livro nao mapeados: %s" % sorted(desconhecidos))
    return versiculos


def validar(versiculos):
    """Confere contagem de livros e capitulos contra o canone protestante."""
    livros = {}
    for bn, cap, _, _ in versiculos:
        livros.setdefault(bn, set()).add(cap)

    problemas = []
    if len(livros) != 66:
        problemas.append("esperados 66 livros, encontrados %d" % len(livros))
    for bn in sorted(livros):
        esperado, obtido = CAPS_ESPERADOS[bn - 1], len(livros[bn])
        if esperado != obtido:
            problemas.append("%s: %d capitulos (esperado %d)"
                             % (CANON[bn - 1], obtido, esperado))
    return problemas


def conferir_banco(caminho, abrev):
    """Le o banco em modo somente-leitura. Devolve (proximo_id, n_livros, ja_existe)."""
    con = sqlite3.connect("file:%s?mode=ro" % caminho, uri=True)
    try:
        prox = con.execute(
            "select ifnull(max(id_bible_version),0)+1 from bible_version").fetchone()[0]
        n_livros = con.execute(
            "select count(*) from bible_book where id_language='pt'").fetchone()[0]
        ja = con.execute(
            "select id_bible_version from bible_version"
            " where abbreviation=? and id_language='pt'", (abrev,)).fetchone()
        return prox, n_livros, ja
    finally:
        con.close()


def gerar_sql(versiculos, id_versao, nome, abrev, saida):
    def esc(s):
        return s.replace("'", "''")

    agora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with io.open(saida, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Importacao BLIVRE gerada em %s\n" % agora)
        f.write("-- Biblia Livre (BLIVRE) - Creative Commons Atribuicao 3.0 Brasil\n")
        f.write("-- Diego Santos, Mario Sergio e Marco Teles\n")
        f.write("-- https://sites.google.com/site/biblialivre/\n\n")
        f.write("BEGIN TRANSACTION;\n\n")
        # id explicito: se ja existir, a transacao aborta por conflito de chave primaria.
        f.write("INSERT INTO bible_version"
                " (id_bible_version,name,abbreviation,id_language,created_at,updated_at)\n"
                "VALUES (%d,'%s','%s','pt','%s','%s');\n\n"
                % (id_versao, esc(nome), esc(abrev), agora, agora))

        for i in range(0, len(versiculos), 500):
            lote = versiculos[i:i + 500]
            f.write("INSERT INTO bible_verse (id_bible_version,id_bible_book,"
                    "chapter,verse,text,id_language,created_at,updated_at) VALUES\n")
            f.write(",\n".join(
                "(%d,%d,%d,%d,'%s','pt','%s','%s')"
                % (id_versao, bn, cap, ver, esc(txt), agora, agora)
                for bn, cap, ver, txt in lote))
            f.write(";\n")

        f.write("\nCOMMIT;\n")


def aplicar(banco, sql_path, id_versao):
    backup = "%s.bak-%s" % (banco, datetime.now().strftime("%Y%m%d-%H%M%S"))
    print("  backup -> %s" % backup)
    shutil.copy2(banco, backup)

    con = sqlite3.connect(banco)
    try:
        con.executescript(io.open(sql_path, encoding="utf-8").read())
        con.commit()
    except Exception:
        con.close()
        print("  FALHOU. Restaurando backup.")
        shutil.copy2(backup, banco)
        raise

    n = con.execute("select count(*) from bible_verse where id_bible_version=?",
                    (id_versao,)).fetchone()[0]
    con.close()
    print("  gravados %d versiculos." % n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--edicao", choices=("n4", "tr"), default="n4")
    ap.add_argument("--banco", default=BANCO_PADRAO)
    ap.add_argument("--saida", default="blivre_import.sql")
    ap.add_argument("--aplicar", action="store_true")
    ap.add_argument("--sem-titulos", action="store_true", dest="sem_titulos",
                    help="remove sobrescritos dos Salmos (recomendado p/ projecao)")
    a = ap.parse_args()

    nome, abrev, origem = EDICOES[a.edicao]
    print("BLIVRE / edicao %s (%s)" % (a.edicao, origem))

    zip_path = "blivre_%s_vpl.zip" % a.edicao
    baixar(a.edicao, zip_path)

    versiculos = ler_versiculos(zip_path, a.sem_titulos)
    print("  lidos %d versiculos" % len(versiculos))

    problemas = validar(versiculos)
    if problemas:
        print("  VALIDACAO FALHOU:")
        for p in problemas:
            print("   -", p)
        sys.exit(1)
    print("  validacao OK: 66 livros, capitulos conferem com o canone")

    if not os.path.exists(a.banco):
        sys.exit("ERRO: banco nao encontrado em %s" % a.banco)

    id_versao, n_livros, ja_existe = conferir_banco(a.banco, abrev)
    if ja_existe:
        sys.exit("ERRO: '%s' ja existe no banco (id %d). Remova antes de reimportar."
                 % (abrev, ja_existe[0]))
    if n_livros != 66:
        sys.exit("ERRO: bible_book tem %d livros em 'pt' (esperado 66)." % n_livros)
    print("  proximo id_bible_version disponivel: %d" % id_versao)

    gerar_sql(versiculos, id_versao, nome, abrev, a.saida)
    print("  SQL gerado: %s (%.1f MB)"
          % (a.saida, os.path.getsize(a.saida) / 1024.0 / 1024.0))

    if a.aplicar:
        aplicar(a.banco, a.saida, id_versao)
    else:
        print("\n  Revise o SQL e rode com --aplicar para gravar (backup automatico).")


if __name__ == "__main__":
    main()
