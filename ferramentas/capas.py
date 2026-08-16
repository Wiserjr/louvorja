"""Converte as capas de album (BMP) para WebP, para virarem asset do APK.

72 capas x 56 KB de BMP nao comprimido e desperdicio dentro de um APK.
Como as capas sao poucas e nunca mudam, elas vao embutidas no app - assim a
grade de albuns aparece completa mesmo antes de o usuario copiar qualquer MP3.
"""
import os, sqlite3
from PIL import Image

ORIGEM = r"C:\Program Files (x86)\Louvor JA\config"
SAIDA = "assets_capas"
os.makedirs(SAIDA, exist_ok=True)

c = sqlite3.connect("louvorja_pt.db")
capas = [(i, p) for i, p in c.execute(
    "select id, capa from albums where capa is not null")]

antes = depois = 0
falhas = []
for id_album, rel in capas:
    org = os.path.join(ORIGEM, rel.replace("/", os.sep))
    if not os.path.exists(org):
        falhas.append(rel)
        continue
    dst = os.path.join(SAIDA, f"{id_album}.webp")
    try:
        im = Image.open(org).convert("RGB")
        im.thumbnail((512, 512), Image.LANCZOS)   # capa nunca precisa de mais que isso
        im.save(dst, "WEBP", quality=85, method=6)
        antes += os.path.getsize(org)
        depois += os.path.getsize(dst)
    except Exception as e:
        falhas.append(f"{rel}: {e}")

print(f"capas convertidas : {len(capas) - len(falhas)}/{len(capas)}")
print(f"tamanho   : {antes/1048576:.2f} MB -> {depois/1024:.0f} KB")
if falhas:
    print("falhas:", falhas[:3])

# dimensoes de uma amostra, para dimensionar a grade na UI
amostra = sorted(os.listdir(SAIDA))[:3]
for f in amostra:
    with Image.open(os.path.join(SAIDA, f)) as im:
        print(f"  {f}: {im.size[0]}x{im.size[1]}px, {os.path.getsize(os.path.join(SAIDA,f))/1024:.0f} KB")
