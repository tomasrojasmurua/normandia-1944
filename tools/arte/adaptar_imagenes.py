#!/usr/bin/env python3
"""Adapta las imágenes generadas en ChatGPT al estilo del juego.

Entrada:  arte_fuente/  (originales; Godot ignora esta carpeta por el .gdignore)
Salida:   assets/ui/retratos/   retratos de 38x33 para el HUD
          assets/texturas/      texturas repetibles de 64x64 (look de los 90)
          assets/ui/fondo_menu.png  fondo de 320x180

Qué hace con cada imagen: recorta, reduce con un filtro suave, sube un poco
el contraste, baja la saturación y limita los colores (posterizado), para
que parezcan fotos pixeladas como las de Hamburger Hill.

Uso:  python3 tools/arte/adaptar_imagenes.py
"""
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

RAIZ = Path(__file__).resolve().parents[2]
FUENTE = RAIZ / "arte_fuente"
RETRATOS = RAIZ / "assets" / "ui" / "retratos"
TEXTURAS = RAIZ / "assets" / "texturas"
UI = RAIZ / "assets" / "ui"

RETRATO_TAM = (38, 33)
TEXTURA_TAM = 64


def reducir(img, tam, colores, saturacion=0.85, contraste=1.12, nitidez=1.6):
    """Reducción en dos pasos: a 4x con Lanczos, nitidez, y luego a 1x en promedio."""
    w, h = tam
    img = img.convert("RGB").resize((w * 4, h * 4), Image.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=80, threshold=2))
    img = img.resize((w, h), Image.BOX)
    img = ImageEnhance.Color(img).enhance(saturacion)
    img = ImageEnhance.Contrast(img).enhance(contraste)
    img = ImageEnhance.Sharpness(img).enhance(nitidez)
    return img.quantize(colors=colores, method=Image.Quantize.MEDIANCUT,
                        dither=Image.Dither.NONE).convert("RGB")


def retrato(origen, destino):
    img = Image.open(origen)
    W, H = img.size
    w, h = RETRATO_TAM
    # Recorte: desde el casco (cortando la punta) hasta el mentón, como en Hamburger Hill
    ancho = int(W * 0.66)
    alto = int(ancho * h / w)
    x0 = (W - ancho) // 2
    y0 = int(H * 0.13)
    img = img.crop((x0, y0, x0 + ancho, y0 + alto))
    img = ImageEnhance.Brightness(img).enhance(1.15)
    out = reducir(img, RETRATO_TAM, colores=40, saturacion=0.9, contraste=1.2)
    out.save(destino)


def textura(origen, destino):
    img = Image.open(origen).convert("RGB")
    # La imagen completa se repite sin costuras: reducirla entera mantiene la repetición
    t = TEXTURA_TAM
    big = img.resize((t * 4, t * 4), Image.LANCZOS)
    # Igualar la luz (quitar manchas grandes de luz/sombra que delatan la repetición)
    blur = big.filter(ImageFilter.GaussianBlur(t))
    media = tuple(int(v) for v in big.resize((1, 1), Image.BOX).getpixel((0, 0)))
    px, pb = big.load(), blur.load()
    for y in range(big.height):
        for x in range(big.width):
            c, b = px[x, y], pb[x, y]
            px[x, y] = tuple(max(0, min(255, c[i] - b[i] + media[i])) for i in range(3))
    out = big.resize((t, t), Image.BOX)
    out = ImageEnhance.Color(out).enhance(0.85)
    out = ImageEnhance.Contrast(out).enhance(1.35)
    out = out.quantize(colors=24, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out.save(destino)


# Armas en primera persona: imagen de 1536x1024 con fondo verde puro.
# ESCALA_ARMA = cuánto se achica para el juego (la pantalla mide 640x360).
ESCALA_ARMA = 0.36
ARMAS_SPRITES = RAIZ / "assets" / "armas"


def quitar_verde(img):
    """Fondo verde -> transparente, y quita el reflejo verde de los bordes."""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            exceso = g - max(r, b)
            if exceso > 60 and g > 120:
                px[x, y] = (0, 0, 0, 0)
            elif exceso > 0:
                # borde: bajar el verde al nivel de los otros canales
                px[x, y] = (r, max(r, b) + exceso // 4, b, 255 if exceso < 30 else 160)
    return img


def arma(origen, destino):
    img = quitar_verde(Image.open(origen))
    w, h = int(img.width * ESCALA_ARMA), int(img.height * ESCALA_ARMA)
    # Reducir color y alfa por separado; el alfa queda todo o nada (bordes de píxel nítidos)
    big = img.resize((w * 4, h * 4), Image.LANCZOS)
    small = big.resize((w, h), Image.BOX)
    a = small.split()[3].point(lambda v: 255 if v > 110 else 0)
    rgb_ = small.convert("RGB")
    rgb_ = ImageEnhance.Contrast(rgb_).enhance(1.12)
    rgb_ = ImageEnhance.Color(rgb_).enhance(0.9)
    rgb_ = ImageEnhance.Sharpness(rgb_).enhance(1.5)
    rgb_ = rgb_.quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = rgb_.convert("RGBA")
    out.putalpha(a)
    out.save(destino)


def fondo(origen, destino):
    img = Image.open(origen)
    W, H = img.size
    alto = int(W * 9 / 16)
    img = img.crop((0, (H - alto) // 2, W, (H - alto) // 2 + alto))
    reducir(img, (320, 180), colores=48, saturacion=0.8, nitidez=1.3).save(destino)


if __name__ == "__main__":
    RETRATOS.mkdir(parents=True, exist_ok=True)
    TEXTURAS.mkdir(parents=True, exist_ok=True)
    for f in sorted((FUENTE / "retratos").glob("*.jpg")):
        retrato(f, RETRATOS / (f.stem + ".png"))
        print("retrato", f.stem)
    for f in sorted((FUENTE / "texturas").glob("*.jpg")):
        textura(f, TEXTURAS / (f.stem + ".png"))
        print("textura", f.stem)
    for f in sorted((FUENTE / "armas").glob("*.png")):
        arma(f, ARMAS_SPRITES / (f.stem + ".png"))
        print("arma", f.stem)
    m = FUENTE / "fondos" / "fondo_menu.jpg"
    if m.exists():
        fondo(m, UI / "fondo_menu.png")
        print("fondo menu")
