r"""Confere o catalogo que vai dentro do APK, antes de compilar.

Existe por causa de uma falha que nao da erro em lugar nenhum: a atualizacao do
programa base substitui o database.db do desktop e leva junto as edicoes da
Biblia Livre importadas por importar_blivre.py. Depois disso o build_db.py roda
com sucesso, o APK compila, a release sai - e as traducoes simplesmente nao
estao la. So se percebe abrindo o seletor de versoes no celular.

Confere o assets/louvorja_pt.db.gz, que e o arquivo realmente embarcado, e nao o
banco do desktop: entre um e outro existe uma geracao que pode nao ter sido
refeita.

    python ferramentas/conferir_catalogo.py

Sai com 0 se estiver tudo certo, 1 se faltar traducao. Catalogo desatualizado em
relacao ao desktop e apenas aviso - as vezes se publica de proposito sem regerar.
"""
import gzip
import os
import sqlite3
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET = os.path.join(RAIZ, "assets", "louvorja_pt.db.gz")
DESKTOP = r"C:\Program Files (x86)\Louvor JA\config\database.db"

TRADUCOES_ESPERADAS = 12

# As duas de licenca livre sao as unicas que nao vem do instalador: entram pelo
# importar_blivre.py e por isso somem a cada atualizacao do programa base.
OBRIGATORIAS = ("BLIVRE", "BLIVRE-TR")

VERSICULOS_MINIMOS = 31000


def abrir_asset():
    if not os.path.exists(ASSET):
        sys.exit("ERRO: %s nao encontrado. Rode build_db.py e compacte o asset." % ASSET)
    destino = os.path.join(tempfile.gettempdir(), "louvorja_conferencia.db")
    with open(ASSET, "rb") as f:
        dados = gzip.decompress(f.read())
    with open(destino, "wb") as f:
        f.write(dados)
    return sqlite3.connect(destino), destino


def versao_do_desktop():
    if not os.path.exists(DESKTOP):
        return None
    con = sqlite3.connect("file:%s?mode=ro" % DESKTOP.replace("\\", "/"), uri=True)
    try:
        r = con.execute("select VERSAO_BD from VERSAO").fetchone()
        return r[0] if r else None
    except sqlite3.Error:
        return None
    finally:
        con.close()


def main():
    con, tmp = abrir_asset()
    problemas, avisos = [], []

    try:
        versoes = con.execute(
            "select sigla, nome from biblia_versao order by id"
        ).fetchall()
        siglas = [s for s, _ in versoes]

        print("traducoes no asset: %d" % len(versoes))
        for sigla, nome in versoes:
            n = con.execute(
                "select count(*) from biblia_versiculo where id_versao ="
                " (select id from biblia_versao where sigla=?)", (sigla,)
            ).fetchone()[0]
            marca = "  <-- livre" if sigla in OBRIGATORIAS else ""
            print("   %-10s %7d versiculos  %s%s" % (sigla, n, nome[:34], marca))
            if n < VERSICULOS_MINIMOS:
                problemas.append(
                    "%s tem so %d versiculos (esperado >= %d)"
                    % (sigla, n, VERSICULOS_MINIMOS))

        for obrigatoria in OBRIGATORIAS:
            if obrigatoria not in siglas:
                problemas.append(
                    "%s ausente - reimporte com:"
                    " python ferramentas/importar_blivre.py%s --sem-titulos --aplicar"
                    " e regere o catalogo"
                    % (obrigatoria, " --edicao tr" if obrigatoria.endswith("TR") else ""))

        if len(versoes) != TRADUCOES_ESPERADAS:
            problemas.append(
                "esperadas %d traducoes, encontradas %d"
                % (TRADUCOES_ESPERADAS, len(versoes)))

        # Catalogo x desktop: divergir e legitimo, mas quase sempre e esquecimento.
        acervo = con.execute(
            "select valor from meta where chave='versao_acervo'").fetchone()
        acervo = int(acervo[0]) if acervo else None
        desktop = versao_do_desktop()
        print("\nacervo no asset: %s | no desktop: %s"
              % (acervo, desktop if desktop is not None else "indisponivel"))
        if acervo is not None and desktop is not None and acervo < desktop:
            avisos.append(
                "o desktop esta no acervo %d e o asset no %d;"
                " rode build_db.py se quiser publicar o mais novo" % (desktop, acervo))
    finally:
        con.close()
        try:
            os.remove(tmp)
        except OSError:
            pass

    for a in avisos:
        print("\nAVISO: %s" % a)

    if problemas:
        print("\nCATALOGO REPROVADO:")
        for p in problemas:
            print("  - %s" % p)
        sys.exit(1)

    print("\ncatalogo OK")


if __name__ == "__main__":
    main()
