#!/usr/bin/env python3
"""Adapta las imágenes de ambiente (ChatGPT, sección 5) al estilo del juego.

Entrada:  arte_fuente/ambiente/*.png
Salida:   assets/ambiente/*.png

- Árboles, seto, pasto y alambre: se quita el fondo magenta (#FF00FF), se
  limpia el borde rosado, se reduce a la escala del juego (píxeles por metro)
  y el borde queda opaco o transparente (estilo retro).
- Cráter: se reduce y se le pone un borde que se desvanece, con el color de la
  arena del juego.
- Barcos: se recorta la franja del horizonte con los barcos y se desvanece
  arriba y abajo (se pone lejos en el mar, dentro de la niebla).
- Cielo: se arma un panorama 2:1 (las nubes repetidas en espejo para que no se
  note la unión) para el cielo del juego.

Uso:  python3 tools/arte/ambiente.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

RAIZ = Path(__file__).resolve().parents[2]
FUENTE = RAIZ / "arte_fuente" / "ambiente"
SALIDA = RAIZ / "assets" / "ambiente"

# nombre: (alto en metros en el juego, píxeles por metro)
RECORTES = {
    "arbol_1": (13.0, 16),   # roble
    "arbol_2": (19.0, 16),   # álamo
    "arbol_3": (6.5, 20),    # manzano
    "seto": (3.2, 20),
    "pasto": (0.9, 40),
    "alambre": (1.1, 64),
}


def quitar_magenta(img, umbral_alfa=0.5):
    """Devuelve RGBA con el fondo magenta transparente y sin borde rosado."""
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # "magentidad": cuánto más rojo y azul que verde
    m = np.clip((np.minimum(r, b) - g) * 2.2, 0.0, 1.0)
    alfa = 1.0 - m
    # Quitar el tinte magenta del borde: el rojo y el azul no pueden pasar mucho al verde
    tope = g + 0.15
    r2 = np.minimum(r, np.maximum(tope, r * (1 - m)))
    b2 = np.minimum(b, np.maximum(tope, b * (1 - m)))
    out = np.dstack([r2, g, b2, alfa])
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def recortar_usado(img):
    caja = img.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    return img.crop(caja) if caja else img


def reducir_rgba(img, alto_px, umbral=0.5, colores=48):
    """Reduce con promedio (color premultiplicado) y deja el alfa en 0 o 1."""
    w = max(1, round(img.width * alto_px / img.height))
    arr = np.asarray(img).astype(np.float32) / 255.0
    pre = arr.copy()
    pre[..., :3] *= pre[..., 3:4]
    pim = Image.fromarray((pre * 255).astype(np.uint8), "RGBA")
    chico = np.asarray(pim.resize((w, alto_px), Image.BOX)).astype(np.float32) / 255.0
    al = chico[..., 3:4]
    rgb = np.where(al > 0.01, chico[..., :3] / np.maximum(al, 1e-3), 0.0)
    rgb_img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    rgb_img = ImageEnhance.Color(rgb_img).enhance(0.8)
    rgb_img = ImageEnhance.Contrast(rgb_img).enhance(1.08)
    rgb_img = rgb_img.quantize(colors=colores, method=Image.Quantize.MEDIANCUT,
                               dither=Image.Dither.NONE).convert("RGB")
    alfa = (al[..., 0] >= umbral).astype(np.uint8) * 255
    out = rgb_img.convert("RGBA")
    out.putalpha(Image.fromarray(alfa, "L"))
    return out


def color_arena():
    """Color medio de la arena seca del juego (para teñir el cráter)."""
    t = Image.open(RAIZ / "assets" / "texturas" / "textura_arena_seca.png").convert("RGB")
    return np.asarray(t).reshape(-1, 3).mean(axis=0) / 255.0


def crater():
    img = Image.open(FUENTE / "crater.png").convert("RGB")
    tam = 128
    img = img.resize((tam * 4, tam * 4), Image.LANCZOS).resize((tam, tam), Image.BOX)
    arr = np.asarray(img).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:tam, 0:tam]
    d = np.hypot(xx - tam / 2 + 0.5, yy - tam / 2 + 0.5) / (tam / 2)
    # Teñir: la arena de afuera del cráter pasa a tener el color de la del juego
    anillo = (d > 0.85) & (d < 1.0)
    factor = color_arena() / arr[anillo].mean(axis=0)
    arr = np.clip(arr * factor, 0, 1)
    alfa = np.clip((1.0 - d) / 0.35, 0, 1)
    out = np.dstack([arr, alfa])
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(SALIDA / "crater.png")


def barcos():
    img = Image.open(FUENTE / "barcos.png").convert("RGB")
    # Franja del horizonte (los barcos están entre y≈490 y 545 de 1024)
    franja = img.crop((0, 470, img.width, 560))
    w, h = 768, 45
    franja = franja.resize((w, h), Image.BOX)
    franja = ImageEnhance.Color(franja).enhance(0.7)
    arr = np.asarray(franja).astype(np.float32) / 255.0
    yy = np.mgrid[0:h, 0:w][0] / (h - 1)
    # Opaco en el medio (barcos), transparente arriba y abajo
    alfa = np.clip(1.0 - np.abs(yy - 0.62) / 0.42, 0, 1) ** 0.7
    out = np.dstack([arr, alfa])
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(SALIDA / "barcos.png")


def cielo():
    img = Image.open(FUENTE / "cielo.png").convert("RGB")
    nubes = img.crop((0, 0, img.width, 790))        # solo el cielo, sin el mar
    nubes = ImageEnhance.Color(nubes).enhance(0.6)
    w, h = 1024, 512
    mitad = nubes.resize((w // 2, h // 2), Image.LANCZOS)
    arriba = Image.new("RGB", (w, h // 2))
    arriba.paste(mitad, (0, 0))
    arriba.paste(mitad.transpose(Image.FLIP_LEFT_RIGHT), (w // 2, 0))
    pano = Image.new("RGB", (w, h))
    pano.paste(arriba, (0, 0))
    # Abajo del horizonte: el color de la parte baja del cielo (lo tapa la niebla)
    base = np.asarray(arriba).astype(np.float32)[-8:].mean(axis=(0, 1))
    abajo = Image.new("RGB", (w, h // 2), tuple(int(c) for c in base))
    pano.paste(abajo, (0, h // 2))
    pano = pano.filter(ImageFilter.GaussianBlur(0.6))
    pano.save(SALIDA / "cielo.png")


def main():
    SALIDA.mkdir(parents=True, exist_ok=True)
    for nombre, (alto_m, ppm) in RECORTES.items():
        img = recortar_usado(quitar_magenta(Image.open(FUENTE / f"{nombre}.png")))
        umbral = 0.3 if nombre == "alambre" else 0.5
        chico = reducir_rgba(img, max(8, round(alto_m * ppm)), umbral)
        chico.save(SALIDA / f"{nombre}.png")
        print(nombre, chico.size)
    crater()
    barcos()
    cielo()
    print("listo")


if __name__ == "__main__":
    main()
