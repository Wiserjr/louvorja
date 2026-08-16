import gzip, os, sqlite3

ROOT = r"C:\Program Files (x86)\Louvor JA\config"
c = sqlite3.connect("louvorja_pt.db")

# 1. caminhos resolvem em disco?
faltando = []
tot = 0
for campo in ("audio", "audio_pb", "imagem"):
    for (p,) in c.execute(f"select {campo} from musicas where {campo} is not null"):
        tot += 1
        if not os.path.exists(os.path.join(ROOT, p.replace("/", os.sep))):
            faltando.append(p)
print(f"1) midia de musicas: {tot - len(faltando)}/{tot} resolvem em disco")
for p in faltando[:3]:
    print("   AUSENTE:", p)

img = [p for (p,) in c.execute("select distinct imagem from letras where imagem is not null")]
ok = sum(1 for p in img if os.path.exists(os.path.join(ROOT, p.replace("/", os.sep))))
print(f"2) fundos de letra: {ok}/{len(img)} resolvem em disco")

# 3. tempos coerentes (crescentes dentro de cada musica)?
ruins = 0
amostra = [r[0] for r in c.execute(
    "select distinct id_musica from letras order by id_musica limit 400")]
for mid in amostra:
    ts = [r[0] for r in c.execute(
        "select ms from letras where id_musica=? order by ordem", (mid,))]
    if any(b < a for a, b in zip(ts, ts[1:])):
        ruins += 1
print(f"3) tempos crescentes: {len(amostra)-ruins}/{len(amostra)} musicas OK")

# 4. integridade referencial
orfas = c.execute(
    "select count(*) from letras l left join musicas m on m.id=l.id_musica where m.id is null"
).fetchone()[0]
sem_faixa = c.execute(
    "select count(*) from album_musicas am left join musicas m on m.id=am.id_musica where m.id is null"
).fetchone()[0]
print(f"4) letras orfas: {orfas} | vinculos album->musica quebrados: {sem_faixa}")

# 5. musicas sem letra e sem audio
print("5)", c.execute("select count(*) from musicas where tem_letra=0").fetchone()[0],
      "musicas sem letra |",
      c.execute("select count(*) from musicas where audio is null").fetchone()[0],
      "sem audio")

# 6. tamanho comprimido (para asset do APK)
raw = os.path.getsize("louvorja_pt.db")
gz = len(gzip.compress(open("louvorja_pt.db", "rb").read(), 9))
print(f"6) asset: {raw/1048576:.1f} MB cru -> {gz/1048576:.1f} MB comprimido (gzip)")

# 7. peso da midia local por tipo
for sub in ("musicas", "imagens", "capas"):
    d = os.path.join(ROOT, sub)
    tot = sum(os.path.getsize(os.path.join(r, f))
              for r, _, fs in os.walk(d) for f in fs)
    print(f"   {sub:8} {tot/1073741824:6.2f} GB")
