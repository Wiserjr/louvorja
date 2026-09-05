r"""Importa a Biblia Livre (BLIVRE) para o banco do LouvorJA desktop.

A BLIVRE e a unica traducao completa em portugues que pode ser redistribuida
dentro do APK: esta sob Creative Commons Atribuicao 3.0 Brasil, por Diego
Santos, Mario Sergio e Marco Teles. As outras dez versoes do acervo sao
proprietarias.

NAO e mais necessario para o APK: o build_db.py injeta a traducao direto no
catalogo, lendo os mesmos arquivos por ferramentas/blivre.py. Esta ferramenta
serve a quem quer a Biblia Livre tambem no programa Windows - e ali a
importacao continua sendo apagada a cada atualizacao do programa base.

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
import shutil
import sqlite3
import sys
from datetime import datetime

import blivre

BANCO_PADRAO = r"C:\Program Files (x86)\Louvor JA\config\database.db"



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

    nome, abrev, origem = blivre.EDICOES[a.edicao]
    print("BLIVRE / edicao %s (%s)" % (a.edicao, origem))

    versiculos = blivre.ler(a.edicao, a.sem_titulos)
    print("  lidos %d versiculos" % len(versiculos))

    # blivre.ler ja validou contra o canone e teria lancado ValueError.
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
