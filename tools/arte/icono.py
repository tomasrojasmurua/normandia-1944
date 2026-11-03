#!/usr/bin/env python3
"""Ícono de la webapp: el coronel en pixel art (64x64), sin texto.

Entrada:  arte_fuente/retratos/retrato_coronel.jpg
Salida:   assets/icons/icon_512.png, icon_180.png, icon_144.png

Uso:  python3 tools/arte/icono.py
"""
from pathlib import Path
import sys

from PIL import Image

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import adaptar_imagenes as a  # noqa: E402

N = 64


def main():
    src = Image.open(RAIZ / "arte_fuente/retratos/retrato_coronel.jpg").convert("RGB")
    W, H = src.size
    ancho = int(W * 0.80)
    x0 = (W - ancho) // 2
    y0 = int(H * 0.0)
    alto = ancho      # cuadrado: la cara entera, sin texto
    lienzo = a.reducir(src.crop((x0, y0, x0 + ancho, y0 + alto)), (N, N),
                       colores=40, saturacion=0.9, contraste=1.2)
    grande = lienzo.resize((512, 512), Image.NEAREST)
    grande.save(RAIZ / "assets/icons/icon_512.png")
    for t in (180, 144):
        grande.resize((t, t), Image.LANCZOS).save(RAIZ / ("assets/icons/icon_%d.png" % t))
    print("listo")


if __name__ == "__main__":
    main()
