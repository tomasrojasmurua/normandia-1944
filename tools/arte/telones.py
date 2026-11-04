"""Telones de los costados (sección 6) y logotipo del juego.

    arte_fuente/telones/<nombre>.jpg -> assets/telones/<nombre>.png
        Cielo magenta (#FF00FF) recortado (transparente), bordes de humo sin
        tinte magenta, 640 px de ancho y 64 colores. Solo se guarda desde lo
        más alto que tiene algo (humo, árboles) hasta abajo.
        También escribe assets/telones/telones.json con la altura del
        horizonte de cada uno (fracción desde arriba), que va a la altura de
        los ojos en el juego.
    arte_fuente/fondos/logo.png -> assets/ui/logo.png  (verde recortado, 320 px)

Uso: cd tools/arte && python3 telones.py
"""
import json
from pathlib import Path
from PIL import Image, ImageEnhance

RAIZ = Path(__file__).resolve().parents[2]
FUENTE = RAIZ / "arte_fuente"
ASSETS = RAIZ / "assets"

# Fila del horizonte en la imagen original (1536x1024), medida a ojo
HORIZONTE = {"telon_playa_izq": 525, "telon_playa_der": 525, "telon_meseta": 410, "telon_pueblo": 430}
ANCHO = 640
# Árbol en primer plano arriba a la izquierda: se borra (de lejos parecería
# un árbol gigante). [x máx, y máx] como fracción de la imagen original.
BORRAR = {"telon_meseta": (0.40, 0.385), "telon_pueblo": (0.34, 0.40)}


def recortar_color(img, es_fondo, gris):
    """Alfa 0 donde es_fondo(r,g,b) da fuerte; en los bordes, gris (sin tinte)."""
    img = img.convert("RGBA")
    px = img.load()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            k = es_fondo(r, g, b)
            if k > 110:
                px[x, y] = (0, 0, 0, 0)
            elif k > 30:
                v = gris(r, g, b)
                px[x, y] = (v, v, v, 255 if k < 70 else 0)
    return img


def magenta(r, g, b):
    return min(r, b) - g


def verde(r, g, b):
    return g - max(r, b)


def reducir_rgba(img, tam, colores):
    img = img.resize(tam, Image.LANCZOS)
    alfa = img.getchannel("A").point(lambda v: 255 if v > 140 else 0)
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(0.85)
    rgb = rgb.quantize(colors=colores, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(alfa)
    return out


if __name__ == "__main__":
    (ASSETS / "telones").mkdir(parents=True, exist_ok=True)
    datos = {}
    for f in sorted((FUENTE / "telones").glob("*.jpg")):
        img = recortar_color(Image.open(f), magenta, lambda r, g, b: g + 10)
        if f.stem in BORRAR:
            bx, by = BORRAR[f.stem]
            img.paste((0, 0, 0, 0), (0, 0, int(img.width * bx), int(img.height * by)))
        caja = img.getchannel("A").getbbox()
        arriba = max(caja[1] - 8, 0)
        img = img.crop((0, arriba, img.width, img.height))
        h = round(img.height * ANCHO / img.width)
        reducir_rgba(img, (ANCHO, h), 64).save(ASSETS / "telones" / (f.stem + ".png"))
        datos[f.stem] = {"horizonte": (HORIZONTE.get(f.stem, 512) - arriba) / img.height,
                         "proporcion": img.height / img.width}
        print("telón", f.stem, datos[f.stem])
    (ASSETS / "telones" / "telones.json").write_text(json.dumps(datos, indent=1))
    logo = FUENTE / "fondos" / "logo.png"
    if logo.exists():
        img = recortar_color(Image.open(logo), verde, lambda r, g, b: (r + b) // 2)
        img = img.crop(img.getchannel("A").getbbox())
        h = round(img.height * 320 / img.width)
        reducir_rgba(img, (320, h), 48).save(ASSETS / "ui" / "logo.png")
        print("logo", (320, h))
