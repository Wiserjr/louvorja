r"""Extrai um catalogo enxuto do database.db do LouvorJA (esquema 26.9 / BD 184).

O esquema mudou em relacao a 2024: `files` perdeu base_url/subdirectory e ganhou
`dir` + `duration`, `configs` virou a tabela `VERSAO`, e chegaram os videos
on-line e mais tres versoes biblicas.

Os caminhos de midia sao gravados no formato da **API** (`musics/pt/Album/X.mp3`),
que agora coincide com o `files.dir` local. Assim o mesmo texto serve para achar
o arquivo na pasta do celular e para baixa-lo do servidor.

Origem : C:\Program Files (x86)\Louvor JA\config\database.db
Destino: louvorja_pt.db  -> assets/ do app Flutter
"""
import base64
import os
import re
import sqlite3

SRC = r"C:\Program Files (x86)\Louvor JA\config\database.db"
DST = "louvorja_pt.db"

if os.path.exists(DST):
    os.remove(DST)

src = sqlite3.connect("file:" + SRC.replace("\\", "/") + "?mode=ro", uri=True)
src.row_factory = sqlite3.Row
dst = sqlite3.connect(DST)

dst.executescript("""
CREATE TABLE albums (
  id INTEGER PRIMARY KEY, nome TEXT NOT NULL, cor TEXT, capa TEXT, ordem INTEGER
);
CREATE TABLE categorias (
  id INTEGER PRIMARY KEY, nome TEXT NOT NULL, slug TEXT NOT NULL,
  tipo TEXT, ordem INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE album_categoria (
  id_album INTEGER NOT NULL, id_categoria INTEGER NOT NULL,
  subtitulo TEXT, ordem INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id_album, id_categoria)
);
CREATE TABLE musicas (
  id INTEGER PRIMARY KEY, nome TEXT NOT NULL,
  audio TEXT, audio_pb TEXT, imagem TEXT,
  audio_bytes INTEGER, tem_letra INTEGER NOT NULL DEFAULT 0,
  duracao_ms INTEGER
);
CREATE TABLE album_musicas (
  id_album INTEGER NOT NULL, id_musica INTEGER NOT NULL, faixa INTEGER NOT NULL,
  PRIMARY KEY (id_album, id_musica)
);
CREATE TABLE letras (
  id INTEGER PRIMARY KEY, id_musica INTEGER NOT NULL, ordem INTEGER NOT NULL,
  texto TEXT NOT NULL, texto_aux TEXT, imagem TEXT,
  ms INTEGER NOT NULL, ms_pb INTEGER NOT NULL, exibe_slide INTEGER NOT NULL
);
CREATE TABLE biblia_versao (
  id INTEGER PRIMARY KEY, nome TEXT NOT NULL, sigla TEXT NOT NULL
);
CREATE TABLE biblia_livro (
  id INTEGER PRIMARY KEY, numero INTEGER NOT NULL, nome TEXT NOT NULL,
  abreviacao TEXT NOT NULL, testamento INTEGER NOT NULL, capitulos INTEGER
);
CREATE TABLE biblia_versiculo (
  id INTEGER PRIMARY KEY, id_versao INTEGER NOT NULL, id_livro INTEGER NOT NULL,
  capitulo INTEGER NOT NULL, versiculo INTEGER NOT NULL, texto TEXT NOT NULL
);
-- Coletaneas on-line: canais, playlists e videos do YouTube que o programa
-- lista na aba propria. As miniaturas vem embutidas no banco em base64 e sao
-- guardadas aqui como BLOB - 4,4 MB de texto viram ~3,3 MB de bytes, e a lista
-- passa a funcionar sem rede.
CREATE TABLE onl_canais (
  id INTEGER PRIMARY KEY, nome TEXT NOT NULL, url TEXT, thumb BLOB
);
CREATE TABLE onl_playlists (
  id INTEGER PRIMARY KEY, id_canal INTEGER NOT NULL, nome TEXT NOT NULL,
  playlist_id TEXT, thumb BLOB
);
CREATE TABLE onl_videos (
  id INTEGER PRIMARY KEY, id_playlist INTEGER NOT NULL, video_id TEXT NOT NULL,
  nome TEXT NOT NULL, ordem INTEGER NOT NULL DEFAULT 0, thumb BLOB
);
CREATE TABLE meta (chave TEXT PRIMARY KEY, valor TEXT);
CREATE INDEX ix_letras_musica ON letras (id_musica, ordem);
CREATE INDEX ix_am_album      ON album_musicas (id_album, faixa);
CREATE INDEX ix_versiculo     ON biblia_versiculo (id_versao, id_livro, capitulo, versiculo);
CREATE INDEX ix_ac_categoria  ON album_categoria (id_categoria, ordem);
CREATE INDEX ix_onl_playlist  ON onl_videos (id_playlist, ordem);
CREATE INDEX ix_onl_canal     ON onl_playlists (id_canal);
""")


def caminho(dirdb, fn):
    """'/musics/pt/1992 - Brilha Jesus' + 'X.mp3' -> 'musics/pt/1992 - Brilha Jesus/X.mp3'"""
    if not fn:
        return None
    return re.sub(r"/{2,}", "/", (dirdb or "") + "/" + fn).lstrip("/")


def ms(t):
    """'00:01:23' -> 83000. Converter aqui evita parse de texto durante a reproducao."""
    if not t:
        return 0
    p = str(t).split(":")
    if len(p) != 3:
        return 0
    try:
        return (int(p[0]) * 3600 + int(p[1]) * 60 + int(float(p[2]))) * 1000
    except ValueError:
        return 0


# --- albuns ---
dst.executemany("INSERT INTO albums VALUES (?,?,?,?,?)", [
    (r["id_album"], r["name"], r["color"], caminho(r["dir"], r["fn"]), r["ordem"])
    for r in src.execute(
        'select a.id_album, a.name, a.color, f.dir, f.file_name fn, '
        '       (select min(ca."order") from categories_albums ca '
        '         where ca.id_album = a.id_album) ordem '
        '  from albums a '
        '  left join files f on f.id_file = a.id_file_image')
])

# --- categorias ---
# O indice publicado pela API traz so as 5 do tipo "collection". Aqui vem as 9,
# incluindo os dois hinarios (1.214 hinos), doxologia e infantis.
dst.executemany("INSERT INTO categorias VALUES (?,?,?,?,?)", [
    (r["id_category"], r["name"], r["slug"], r["type"], r["order"])
    for r in src.execute('select * from categories order by "order"')
])

# categories_albums.name guarda o subtitulo exibido no programa - nos CDs
# oficiais, o ano do album.
dst.executemany("INSERT INTO album_categoria VALUES (?,?,?,?)", [
    (r["id_album"], r["id_category"], (r["name"] or "").strip() or None, r["order"])
    for r in src.execute(
        'select id_album, id_category, name, "order" from categories_albums')
])

# --- musicas ---
com_letra = {r[0] for r in src.execute(
    "select distinct id_music from lyrics where show_slide=1 and trim(lyric) <> ''")}

dst.executemany("INSERT INTO musicas VALUES (?,?,?,?,?,?,?,?)", [
    (r["id"], r["nome"], caminho(r["a_dir"], r["a_fn"]),
     caminho(r["p_dir"], r["p_fn"]), caminho(r["i_dir"], r["i_fn"]),
     r["a_size"], 1 if r["id"] in com_letra else 0, ms(r["a_dur"]))
    for r in src.execute(
        'select m.id_music id, m.name nome, '
        '       fa.dir a_dir, fa.file_name a_fn, fa.size a_size, fa.duration a_dur, '
        '       fp.dir p_dir, fp.file_name p_fn, '
        '       fi.dir i_dir, fi.file_name i_fn '
        '  from musics m '
        '  left join files fa on fa.id_file = m.id_file_music '
        '  left join files fp on fp.id_file = m.id_file_instrumental_music '
        '  left join files fi on fi.id_file = m.id_file_image')
])

dst.executemany("INSERT INTO album_musicas VALUES (?,?,?)", [
    (r["id_album"], r["id_music"], r["track"])
    for r in src.execute("select id_album, id_music, track from albums_musics")
])

# --- letras ---
dst.executemany("INSERT INTO letras VALUES (?,?,?,?,?,?,?,?,?)", [
    (r["id_lyric"], r["id_music"], r["order"], r["lyric"], r["aux_lyric"],
     caminho(r["dir"], r["fn"]), ms(r["time"]),
     ms(r["instrumental_time"]) or ms(r["time"]), r["show_slide"])
    for r in src.execute(
        'select l.id_lyric, l.id_music, l."order", l.lyric, l.aux_lyric, '
        '       l.time, l.instrumental_time, l.show_slide, '
        '       f.dir, f.file_name fn '
        '  from lyrics l '
        '  left join files f on f.id_file = l.id_file_image')
])

# --- biblia: agora 10 versoes e 311 mil versiculos ---
dst.executemany("INSERT INTO biblia_versao VALUES (?,?,?)", [
    (r["id_bible_version"], r["name"], r["abbreviation"])
    for r in src.execute("select * from bible_version")
])
dst.executemany("INSERT INTO biblia_livro VALUES (?,?,?,?,?,?)", [
    (r["id_bible_book"], r["book_number"], r["name"], r["abbreviation"],
     r["testament"], r["chapters"])
    for r in src.execute("select * from bible_book")
])
dst.executemany("INSERT INTO biblia_versiculo VALUES (?,?,?,?,?,?)", [
    (r["id_bible_verse"], r["id_bible_version"], r["id_bible_book"],
     r["chapter"], r["verse"], r["text"])
    for r in src.execute("select * from bible_verse")
])

# --- coletaneas on-line ---
def thumb(v):
    """'data:image/png;base64,/9j/...' -> bytes. O rotulo MIME da origem diz PNG
    mas o conteudo e JPEG; guardar os bytes crus deixa o decodificador decidir."""
    if not v:
        return None
    dados = v.split(",", 1)[1] if v.startswith("data:") else v
    try:
        return base64.b64decode(dados)
    except Exception:
        return None


dst.executemany("INSERT INTO onl_canais VALUES (?,?,?,?)", [
    (r["id_online_video_channel"], r["title"], r["custom_url"],
     thumb(r["default_image_base64"]))
    for r in src.execute("select * from online_videos_channels")
])
dst.executemany("INSERT INTO onl_playlists VALUES (?,?,?,?,?)", [
    (r["id_online_video_playlist"], r["id_online_video_channel"], r["title"],
     r["playlist_id"], thumb(r["default_image_base64"]))
    for r in src.execute("select * from online_videos_playlists")
])
dst.executemany("INSERT INTO onl_videos VALUES (?,?,?,?,?,?)", [
    (r["id_online_video"], r["id_online_video_playlist"], r["video_id"],
     r["title"], r["sequence"], thumb(r["default_image_base64"]))
    for r in src.execute("select * from online_videos")
])

versao = src.execute("select VERSAO_BD from VERSAO").fetchone()
dst.executemany("INSERT INTO meta VALUES (?,?)", [
    ("versao_acervo", str(versao["VERSAO_BD"] if versao else 0)),
    ("origem", "LouvorJA desktop 26.9"),
])

dst.commit()
dst.execute("VACUUM")
dst.close()

chk = sqlite3.connect(DST)
print("=== catalogo gerado ===")
for t in ("albums", "categorias", "album_categoria", "musicas", "album_musicas",
          "letras", "biblia_versao", "biblia_livro", "biblia_versiculo",
          "onl_canais", "onl_playlists", "onl_videos"):
    print("  %-18s %7d" % (t, chk.execute("select count(*) from " + t).fetchone()[0]))
print("\norigem : %6.1f MB" % (os.path.getsize(SRC) / 1048576))
print("destino: %6.1f MB" % (os.path.getsize(DST) / 1048576))
print("versao :", chk.execute(
    "select valor from meta where chave='versao_acervo'").fetchone()[0])
print("\namostra:", chk.execute(
    "select nome, audio, duracao_ms from musicas where audio is not null limit 2"
).fetchall())
