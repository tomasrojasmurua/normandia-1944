#!/usr/bin/env python3
"""Ícono de la webapp: el coronel en pixel art (64x64) con "NORMANDY 1944".

Entrada:  arte_fuente/retratos/retrato_coronel.jpg
Salida:   assets/icons/icon_512.png, icon_180.png, icon_144.png

Uso:  python3 tools/arte/icono.py
"""
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import adaptar_imagenes as a  # noqa: E402

N = 64


def main():
    src = Image.open(RAIZ / "arte_fuente/retratos/retrato_coronel.jpg").convert("RGB")
    W, H = src.size
    ancho = int(W * 0.80)
    x0 = (W - ancho) // 2
    y0 = int(H * 0.02)
    cara = a.reducir(src.crop((x0, y0, x0 + ancho, y0 + int(ancho * 46 / 64))), (64, 46),
                     colores=40, saturacion=0.9, contraste=1.2)
    lienzo = Image.new("RGB", (N, N), (11, 13, 8))
    lienzo.paste(cara, (0, 0))
    d = ImageDraw.Draw(lienzo)
    f = ImageFont.truetype(str(RAIZ / "assets/fonts/normandy.ttf"), 11)
    d.rectangle((0, 45, 63, 63), fill=(20, 25, 16))
    d.line((0, 45, 63, 45), fill=(68, 82, 47))

    def centrado(t, y, col):
        x = (N - d.textlength(t, font=f)) / 2
        d.text((x + 1, y + 1), t, font=f, fill=(11, 13, 8))
        d.text((x, y), t, font=f, fill=col)

    centrado("NORMANDY", 45, (220, 220, 188))
    centrado("1944", 54, (233, 150, 42))
    grande = lienzo.resize((512, 512), Image.NEAREST)
    grande.save(RAIZ / "assets/icons/icon_512.png")
    for t in (180, 144):
        grande.resize((t, t), Image.LANCZOS).save(RAIZ / ("assets/icons/icon_%d.png" % t))
    print("listo")


if __name__ == "__main__":
    main()
