"""Prepara las armas 3D de los soldados a partir de los perfiles de ChatGPT
(arte_fuente/piezas/perfil_<id>.png, fondo verde, cañón a la derecha).

Escribe:
  assets/armas/3d/atlas.png    todas las armas pixeladas en una sola imagen
  assets/armas/3d/armas.json   dónde está cada una en el atlas, su largo real,
                               su grosor y sus marcas (en píxeles del atlas)
Después: godot --headless --path . --script tools/modelos/armas3d.gd
(construye las mallas con volumen, assets/armas/3d/<id>.res).

Marcas (fracción del ancho/alto del recorte, 0..1 desde la culata/arriba):
  agarre = mano derecha (empuñadura), guardamanos = mano izquierda.
  boca (punta del cañón) y culata se detectan solas.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "tools" / "arte"))
from adaptar_imagenes import quitar_verde  # noqa: E402

SALIDA = RAIZ / "assets" / "armas" / "3d"

# id: (largo real en metros, grosor en metros, píxeles de largo en el atlas,
#      agarre (u, v), guardamanos (u, v))
ARMAS = {
    "garand":      (1.10, 0.045, 128, (0.27, 0.50), (0.62, 0.38)),
    "carbine":     (0.90, 0.042, 112, (0.27, 0.48), (0.60, 0.36)),
    "springfield": (1.10, 0.045, 128, (0.29, 0.62), (0.60, 0.45)),
    "kar98k":      (1.11, 0.045, 128, (0.28, 0.48), (0.60, 0.40)),
    "thompson":    (0.86, 0.050, 104, (0.43, 0.55), (0.76, 0.22)),
    "bar":         (1.21, 0.050, 128, (0.33, 0.62), (0.55, 0.40)),
    "mp40":        (0.63, 0.050, 80,  (0.10, 0.55), (0.55, 0.42)),
    "stg44":       (0.94, 0.050, 112, (0.34, 0.60), (0.58, 0.34)),
    "mg42":        (1.22, 0.060, 128, (0.30, 0.62), (0.52, 0.42)),
    "bazooka":     (1.37, 0.090, 128, (0.40, 0.75), (0.58, 0.32)),
    "colt":        (0.22, 0.030, 40,  (0.14, 0.62), (0.18, 0.80)),
    "luger":       (0.22, 0.030, 40,  (0.12, 0.66), (0.16, 0.82)),
}
PADDING = 2
ANCHO_ATLAS = 256


def recortar(nombre):
    img = Image.open(RAIZ / "arte_fuente" / "piezas" / f"perfil_{nombre}.png")
    img = quitar_verde(img.resize((768, 512), Image.LANCZOS))
    a = np.array(img)[:, :, 3]
    ys, xs = np.nonzero(a > 128)
    return img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def pixelar(img, largo_px):
    h = max(4, round(img.height * largo_px / img.width))
    big = img.resize((largo_px * 4, h * 4), Image.LANCZOS)
    small = big.resize((largo_px, h), Image.BOX)
    a = small.split()[3].point(lambda v: 255 if v > 110 else 0)
    rgb = small.convert("RGB")
    rgb = ImageEnhance.Contrast(rgb).enhance(1.1)
    rgb = ImageEnhance.Sharpness(rgb).enhance(1.4)
    rgb = rgb.quantize(colors=32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def extremo(alfa, col):
    ys = np.nonzero(alfa[:, col] > 0)[0]
    return float(ys.mean()) + 0.5


def main():
    SALIDA.mkdir(parents=True, exist_ok=True)
    piezas = {n: pixelar(recortar(n), d[2]) for n, d in ARMAS.items()}
    # Empaquetar en estantes, de la más alta a la más baja
    orden = sorted(piezas, key=lambda n: -piezas[n].height)
    x = y = alto_fila = 0
    lugar = {}
    for n in orden:
        w, h = piezas[n].size
        if x + w + PADDING > ANCHO_ATLAS:
            x, y, alto_fila = 0, y + alto_fila + PADDING, 0
        lugar[n] = (x, y)
        x += w + PADDING
        alto_fila = max(alto_fila, h)
    alto = 1
    while alto < y + alto_fila:
        alto *= 2
    atlas = Image.new("RGBA", (ANCHO_ATLAS, alto), (0, 0, 0, 0))
    datos = {}
    for n, img in piezas.items():
        px, py = lugar[n]
        atlas.paste(img, (px, py))
        largo, grosor, _, agarre, guarda = ARMAS[n]
        w, h = img.size
        alfa = np.array(img)[:, :, 3]
        datos[n] = {
            "rect": [px, py, w, h],
            "largo": largo,
            "grosor": grosor,
            "agarre": [agarre[0] * w, agarre[1] * h],
            "guardamanos": [guarda[0] * w, guarda[1] * h],
            "boca": [float(w), extremo(alfa, w - 1)],
            "culata": [0.0, extremo(alfa, 0)],
        }
    atlas.save(SALIDA / "atlas.png")
    (SALIDA / "armas.json").write_text(json.dumps(datos, indent=1))
    print("atlas", atlas.size)


if __name__ == "__main__":
    main()
