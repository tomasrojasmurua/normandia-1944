#!/usr/bin/env python3
"""Genera el arte base de Normandy 1944 (guía de estilo + HUD).

Todo se dibuja con código para que sea reproducible. Salidas:
  assets/fonts/normandy.ttf      letra pixelada (11 px por línea, mayúsculas)
  assets/ui/*.png                marcos, números ámbar, íconos y retrato provisional
  docs/arte/paleta.png           la paleta del juego (32 colores)
  docs/arte/guia_estilo.png      lámina con todo junto, para revisar

Uso:  python3 tools/arte/generar_arte.py   (requiere Pillow y fontTools)
"""
from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFilter

RAIZ = Path(__file__).resolve().parents[2]
UI = RAIZ / "assets" / "ui"
FUENTES = RAIZ / "assets" / "fonts"
DOCS = RAIZ / "docs" / "arte"
for d in (UI, FUENTES, DOCS):
    d.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# PALETA: amanecer nublado en Normandía + interfaz verde oliva militar.
# Todo el arte (y las imágenes de ChatGPT, al adaptarlas) usa estos colores.
# ---------------------------------------------------------------------------
PALETA = {
    # Interfaz
    "negro":        "#0b0d08",
    "oliva_0":      "#141910",
    "oliva_1":      "#1f2717",
    "oliva_2":      "#2f3a22",
    "oliva_3":      "#44522f",
    "oliva_4":      "#66744a",
    "oliva_5":      "#8d9a6a",
    "crema":        "#dcdcbc",
    "ambar_osc":    "#6b3a0e",
    "ambar":        "#e9962a",
    "ambar_claro":  "#ffd47e",
    "rojo":         "#c4321f",
    "verde_led":    "#6cc04a",
    # Mundo
    "cielo":        "#a2a9a8",
    "niebla":       "#8a9293",
    "mar_osc":      "#34423f",
    "mar":          "#566760",
    "arena_moj":    "#7d725d",
    "arena":        "#a8977a",
    "arena_clara":  "#c8b896",
    "concreto_osc": "#55554e",
    "concreto":     "#86847a",
    "acero":        "#45494a",
    "acero_claro":  "#7b8083",
    "oxido":        "#7a4528",
    "madera_osc":   "#4f3019",
    "madera":        "#865426",
    "madera_clara": "#b37a3d",
    "laton":        "#c99a3e",
    "piel":         "#c08868",
    "piel_osc":     "#7d5040",
    "sangre":       "#6e0d0a",
}
assert len(PALETA) == 32, len(PALETA)


def rgb(nombre, a=255):
    h = PALETA[nombre]
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), a)


def mezcla(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))


# ---------------------------------------------------------------------------
# LETRA PIXELADA (5x7, en negrita se ensancha 1 px). Se exporta como TTF para
# que Godot la use como cualquier fuente; cada píxel es un cuadrado.
# ---------------------------------------------------------------------------
G = {
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".###.", "#...#", "#....", ".###.", "....#", "#...#", ".###."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": [".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###"],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
    ".": [".", ".", ".", ".", ".", ".", "#"],
    ",": ["..", "..", "..", "..", "..", ".#", ".#", "#."],
    ":": [".", ".", "#", ".", ".", "#", "."],
    ";": ["..", "..", ".#", "..", "..", ".#", "#."],
    "!": ["#", "#", "#", "#", "#", ".", "#"],
    "¡": ["#", ".", "#", "#", "#", "#", "#"],
    "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
    "¿": ["..#..", ".....", "..#..", ".#...", "#....", "#...#", ".###."],
    "'": ["#", "#", ".", ".", ".", ".", "."],
    '"': ["#.#", "#.#", "...", "...", "...", "...", "..."],
    "-": ["...", "...", "...", "###", "...", "...", "..."],
    "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
    "=": ["....", "....", "####", "....", "####", "....", "...."],
    "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
    "(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
    ")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
    "[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
    "]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
    "|": ["#", "#", "#", "#", "#", "#", "#"],
    "_": ["....", "....", "....", "....", "....", "....", "####"],
    "%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
    "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
    "*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
    "<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
    ">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
    "°": [".#.", "#.#", ".#.", "...", "...", "...", "..."],
    "x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
}
# Letras con tilde: la letra base con una marca encima (filas -2 y -1).
ACENTOS = {"Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U", "Ü": "U", "Ñ": "N"}


def glifo(ch):
    """Devuelve (filas, desplazamiento_y) con filas de arriba hacia abajo."""
    if ch in G:
        return G[ch], 0
    base = ACENTOS.get(ch)
    if base is None:
        return None, 0
    filas = G[base]
    w = len(filas[0])
    if ch == "Ü":
        marca = [".#.#."[:w].ljust(w, ".")]
    elif ch == "Ñ":
        marca = [".##.#", "#.##."]
    else:
        marca = ["...#."[:w].ljust(w, ".") if w == 5 else "..#"]
    if len(marca) == 1:
        marca = marca + ["." * w]
    return marca + filas, -2


def negrita(filas):
    """Ensancha cada trazo 1 px hacia la derecha (letra más legible en celular)."""
    w = len(filas[0]) + 1
    out = []
    for f in filas:
        f = f + "."
        out.append("".join("#" if f[x] == "#" or (x > 0 and f[x - 1] == "#") else "." for x in range(w)))
    return out


def construir_ttf(destino):
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen

    U = 100              # unidades por píxel
    ASC, DESC = 9, 2     # píxeles sobre y bajo la línea base (tamaño de dibujo = 11)
    em = (ASC + DESC) * U
    nombres = [".notdef", "space"]
    glyphs, metrics, cmap = {}, {}, {}

    pen = TTGlyphPen(None)
    glyphs[".notdef"] = pen.glyph()
    metrics[".notdef"] = (4 * U, 0)
    glyphs["space"] = TTGlyphPen(None).glyph()
    metrics["space"] = (4 * U, 0)
    cmap[ord(" ")] = "space"

    caracteres = list(G.keys()) + list(ACENTOS.keys())
    for i, ch in enumerate(caracteres):
        filas, dy = glifo(ch)
        filas = negrita(filas)
        nombre = "g%d" % i
        pen = TTGlyphPen(None)
        alto = len(filas)
        for fy, fila in enumerate(filas):
            # fila 0 (sin acento) es la de arriba: cap height = 7 px
            y_px = 7 - 1 - (fy + dy)          # fila inferior de la letra = 0
            x = 0
            while x < len(fila):
                if fila[x] == "#":
                    x2 = x
                    while x2 < len(fila) and fila[x2] == "#":
                        x2 += 1
                    y0, y1 = y_px * U, (y_px + 1) * U
                    pen.moveTo((x * U, y0))
                    pen.lineTo((x * U, y1))
                    pen.lineTo((x2 * U, y1))
                    pen.lineTo((x2 * U, y0))
                    pen.closePath()
                    x = x2
                else:
                    x += 1
        glyphs[nombre] = pen.glyph()
        ancho = len(filas[0]) + 1   # 1 px de separación
        metrics[nombre] = (ancho * U, 0)
        nombres.append(nombre)
        cmap[ord(ch)] = nombre
        if ch.lower() != ch and len(ch.lower()) == 1:
            cmap[ord(ch.lower())] = nombre   # las minúsculas se ven en mayúscula

    fb = FontBuilder(em, isTTF=True)
    fb.setupGlyphOrder(nombres)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASC * U, descent=-DESC * U)
    fb.setupNameTable({"familyName": "Normandy Pixel", "styleName": "Bold"})
    fb.setupOS2(sTypoAscender=ASC * U, sTypoDescender=-DESC * U, usWinAscent=ASC * U,
                usWinDescent=DESC * U, sTypoLineGap=0)
    fb.setupPost()
    fb.save(str(destino))


def texto_px(img, x, y, txt, color, sombra=None):
    """Dibuja texto con la letra pixelada directamente en una imagen (para la lámina)."""
    for ch in txt.upper():
        if ch == " ":
            x += 4
            continue
        filas, dy = glifo(ch)
        if filas is None:
            continue
        filas = negrita(filas)
        for fy, fila in enumerate(filas):
            for fx, c in enumerate(fila):
                if c == "#":
                    if sombra:
                        img.putpixel((x + fx + 1, y + fy + dy + 1), sombra)
        for fy, fila in enumerate(filas):
            for fx, c in enumerate(fila):
                if c == "#":
                    img.putpixel((x + fx, y + fy + dy), color)
        x += len(filas[0]) + 1
    return x


# ---------------------------------------------------------------------------
# NÚMEROS ÁMBAR estilo display de 7 segmentos (con el "8" apagado de fondo).
# Hoja: 0-9, ":" y "|" en una fila. Una hoja encendida y una apagada.
# ---------------------------------------------------------------------------
SEG = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
       "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g"}


def dibujar_digito(img, ox, oy, w, h, t, segs, c_borde, c_centro):
    px = img.load()
    mid = h // 2

    def horiz(y0):
        for i in range(t):
            d = abs(i - (t - 1) / 2.0)
            ins = int(d + 0.5) + 1
            for x in range(ins, w - ins):
                col = c_centro if (t > 2 and 0 < i < t - 1) else c_borde
                px[ox + x, oy + y0 + i] = col

    def vert(x0, y0, y1):
        for i in range(t):
            d = abs(i - (t - 1) / 2.0)
            ins = int(d + 0.5) + 1
            for y in range(y0 + ins, y1 - ins):
                col = c_centro if (t > 2 and 0 < i < t - 1) else c_borde
                px[ox + x0 + i, oy + y] = col

    yg = mid - t // 2
    if "a" in segs: horiz(0)
    if "g" in segs: horiz(yg)
    if "d" in segs: horiz(h - t)
    if "f" in segs: vert(0, 0, yg + t)
    if "b" in segs: vert(w - t, 0, yg + t)
    if "e" in segs: vert(0, yg, h)
    if "c" in segs: vert(w - t, yg, h)


def hoja_digitos(w, h, t, nombre):
    chars = "0123456789:|-"
    celda = w + 2
    for estado in ("on", "off"):
        img = Image.new("RGBA", (celda * len(chars), h + 2), (0, 0, 0, 0))
        for i, ch in enumerate(chars):
            ox, oy = i * celda + 1, 1
            if estado == "on":
                borde, centro = rgb("ambar"), rgb("ambar_claro")
            else:
                borde = centro = rgb("ambar_osc", 70)
            if ch == ":":
                if estado == "on":
                    s = max(2, t)
                    for cy in (h // 3, 2 * h // 3):
                        for yy in range(s):
                            for xx in range(s):
                                img.putpixel((ox + w // 2 - s // 2 + xx, oy + cy - s // 2 + yy), borde)
            elif ch == "|":
                if estado == "on":
                    for yy in range(1, h - 1):
                        for xx in range(max(1, t - 1)):
                            img.putpixel((ox + w // 2 + xx, oy + yy), borde)
            else:
                segs = SEG[ch] if estado == "on" else SEG["8"]
                dibujar_digito(img, ox, oy, w, h, t, segs, borde, centro)
        if estado == "on":
            # Brillo: halo tenue alrededor de los segmentos encendidos
            a = img.split()[3].filter(ImageFilter.MaxFilter(3))
            halo = Image.new("RGBA", img.size, rgb("ambar", 0))
            halo.putalpha(a.point(lambda v: 45 if v else 0))
            halo.alpha_composite(img)
            img = halo
        img.save(UI / f"{nombre}_{estado}.png")
    return celda


# ---------------------------------------------------------------------------
# MARCOS: chapa verde oliva con relieve y tornillos, y hundido oscuro.
# Se usan como 9-patch (las esquinas no se estiran, el centro se repite).
# ---------------------------------------------------------------------------
def chapa(tam=24, borde=5):
    rnd = random.Random(44)
    img = Image.new("RGBA", (tam, tam))
    px = img.load()
    for y in range(tam):
        for x in range(tam):
            c = rgb("oliva_2")
            n = rnd.random()
            if n < 0.18:
                c = mezcla(c, rgb("oliva_1"), 0.6)
            elif n > 0.9:
                c = mezcla(c, rgb("oliva_3"), 0.5)
            px[x, y] = c
    for i in range(tam):
        px[i, 0] = px[0, i] = px[i, tam - 1] = px[tam - 1, i] = rgb("negro")
    for i in range(1, tam - 1):
        px[i, 1] = rgb("oliva_4")
        px[1, i] = rgb("oliva_3")
        px[i, tam - 2] = rgb("oliva_1")
        px[tam - 2, i] = rgb("oliva_1")
    px[1, 1] = rgb("oliva_5")
    # Tornillos en las esquinas
    for cx, cy in ((3, 3), (tam - 4, 3), (3, tam - 4), (tam - 4, tam - 4)):
        px[cx - 1, cy - 1] = rgb("oliva_5")
        px[cx, cy - 1] = rgb("oliva_4")
        px[cx - 1, cy] = rgb("oliva_4")
        px[cx, cy] = rgb("oliva_1")
        px[cx + 1, cy] = rgb("oliva_1")
        px[cx, cy + 1] = rgb("oliva_1")
        px[cx + 1, cy + 1] = rgb("negro")
        px[cx - 1, cy + 1] = rgb("oliva_3")
        px[cx + 1, cy - 1] = rgb("oliva_3")
    img.save(UI / "chapa.png")


def chapa_lisa(tam=24):
    """Igual que la chapa, sin tornillos (para paneles chicos)."""
    rnd = random.Random(7)
    img = Image.new("RGBA", (tam, tam))
    px = img.load()
    for y in range(tam):
        for x in range(tam):
            c = rgb("oliva_2")
            n = rnd.random()
            if n < 0.18:
                c = mezcla(c, rgb("oliva_1"), 0.6)
            elif n > 0.9:
                c = mezcla(c, rgb("oliva_3"), 0.5)
            px[x, y] = c
    for i in range(tam):
        px[i, 0] = px[0, i] = px[i, tam - 1] = px[tam - 1, i] = rgb("negro")
    for i in range(1, tam - 1):
        px[i, 1] = rgb("oliva_4")
        px[1, i] = rgb("oliva_3")
        px[i, tam - 2] = rgb("oliva_1")
        px[tam - 2, i] = rgb("oliva_1")
    img.save(UI / "chapa_lisa.png")


def hundido(tam=12):
    img = Image.new("RGBA", (tam, tam), rgb("oliva_0"))
    px = img.load()
    for i in range(tam):
        px[i, 0] = px[0, i] = rgb("negro")
        px[i, tam - 1] = px[tam - 1, i] = rgb("oliva_3")
    for i in range(1, tam - 1):
        px[i, 1] = mezcla(rgb("oliva_0"), rgb("negro"), 0.6)
        px[1, i] = mezcla(rgb("oliva_0"), rgb("negro"), 0.6)
    px[tam - 1, 0] = rgb("oliva_1")
    px[0, tam - 1] = rgb("oliva_1")
    img.save(UI / "hundido.png")


def boton_redondo(r, nombre, activo):
    """Botón táctil: disco de chapa con aro y relieve. Se dibuja a 4x y se reduce."""
    S = 4
    d = r * 2 + 2
    big = Image.new("RGBA", (d * S, d * S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(big)
    c = (d * S) / 2
    R = r * S
    base = rgb("ambar", 150) if activo else rgb("oliva_2", 150)
    luz = rgb("ambar_claro", 170) if activo else rgb("oliva_4", 170)
    sombra = rgb("ambar_osc", 170) if activo else rgb("oliva_0", 170)
    dr.ellipse([c - R, c - R, c + R, c + R], fill=rgb("negro", 190))
    dr.ellipse([c - R + S, c - R + S, c + R - S, c + R - S], fill=sombra)
    dr.ellipse([c - R + S, c - R + S, c + R - 2 * S, c + R - 2 * S], fill=luz)
    dr.ellipse([c - R + 2 * S, c - R + 2 * S, c + R - 2 * S, c + R - 2 * S], fill=base)
    img = big.resize((d, d), Image.NEAREST)
    img.save(UI / f"{nombre}.png")


# ---------------------------------------------------------------------------
# ÍCONOS: se dibujan con formas y luego se les pone contorno negro de 1 px.
# ---------------------------------------------------------------------------
def contorno(img):
    a = img.split()[3].point(lambda v: 255 if v > 0 else 0)
    borde = a.filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    negro = Image.new("RGBA", img.size, rgb("negro"))
    out.paste(negro, (0, 0), borde)
    out.alpha_composite(img)
    return out


def rect(px, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px[x, y] = c


def icono_garand():
    img = Image.new("RGBA", (66, 15), (0, 0, 0, 0))
    px = img.load()
    W, Wo, Wc = rgb("madera"), rgb("madera_osc"), rgb("madera_clara")
    m, M, g = rgb("acero_claro"), mezcla(rgb("acero_claro"), rgb("crema"), 0.5), rgb("acero")
    o = (1, 2)
    def R(x0, y0, x1, y1, c): rect(px, x0 + o[0], y0 + o[1], x1 + o[0], y1 + o[1], c)
    # Culata
    for x in range(0, 22):
        top = 4 if x > 2 else 3
        bot = 10 - (x * 3) // 22
        R(x, top, x, bot, W)
        R(x, top, x, top, Wc)
        R(x, bot, x, bot, Wo)
    R(0, 3, 1, 10, g)                  # cantonera
    # Cajón de mecanismos
    R(22, 3, 33, 6, m); R(22, 3, 33, 3, M); R(26, 5, 30, 5, g)
    R(22, 7, 35, 8, W); R(22, 8, 35, 8, Wo)
    R(25, 9, 28, 9, g); R(25, 10, 27, 10, g)      # guardamonte
    R(31, 1, 32, 2, g)                            # alza
    # Guardamanos y cañón
    R(34, 3, 49, 5, W); R(34, 3, 49, 3, Wc)
    R(34, 6, 51, 7, Wo)
    R(41, 3, 41, 7, g); R(50, 3, 51, 7, g)        # abrazaderas
    R(50, 4, 62, 5, m); R(52, 4, 62, 4, M)
    R(60, 2, 61, 3, g)                            # punto de mira
    img = contorno(img)
    img.save(UI / "icono_garand.png")
    return img


def icono_colt():
    img = Image.new("RGBA", (30, 20), (0, 0, 0, 0))
    px = img.load()
    m, M, g = rgb("acero_claro"), mezcla(rgb("acero_claro"), rgb("crema"), 0.5), rgb("acero")
    W, Wc, Wo = rgb("madera"), rgb("madera_clara"), rgb("madera_osc")
    o = (1, 1)
    def R(x0, y0, x1, y1, c): rect(px, x0 + o[0], y0 + o[1], x1 + o[0], y1 + o[1], c)
    R(4, 2, 26, 6, m); R(4, 2, 26, 2, M); R(5, 6, 26, 6, g)    # corredera
    for x in range(8, 13): R(x, 3, x, 5, g) if x % 2 == 0 else None  # estrías
    R(2, 1, 3, 3, g)                                           # martillo
    R(4, 7, 18, 8, g)                                          # armazón
    R(13, 9, 17, 9, g); R(17, 9, 17, 11, g); R(13, 11, 17, 11, g); R(14, 9, 14, 10, m)  # guardamonte
    for y in range(7, 17):                                      # empuñadura
        x0 = 4 - (y - 7) // 3
        R(x0, y, x0 + 7, y, W)
        if y % 2 == 0:
            R(x0 + 2, y, x0 + 2, y, Wc); R(x0 + 5, y, x0 + 5, y, Wc)
    R(1, 17, 8, 17, g)
    img = contorno(img)
    img.save(UI / "icono_colt.png")
    return img


def icono_granada():
    img = Image.new("RGBA", (16, 21), (0, 0, 0, 0))
    px = img.load()
    O, Oc, Oo = rgb("oliva_4"), rgb("oliva_5"), rgb("oliva_2")
    m, g = rgb("acero_claro"), rgb("acero")
    # Cuerpo ovalado con cuadrícula ("piña")
    for y in range(7, 20):
        t = (y - 13) / 6.5
        half = int(6.2 * (1 - t * t) ** 0.5 + 0.5)
        for x in range(8 - half, 8 + half):
            c = O
            if (y - 7) % 3 == 0 or (x - 1) % 3 == 0:
                c = Oo
            elif x < 7 and y < 12:
                c = Oc
            px[x, y] = c
    rect(px, 6, 4, 9, 6, g); rect(px, 6, 4, 9, 4, m)            # espoleta
    rect(px, 10, 4, 11, 4, m); rect(px, 11, 5, 11, 12, m)       # palanca
    px[4, 4] = px[3, 5] = px[4, 6] = px[5, 5] = m               # anilla
    img = contorno(img)
    img.save(UI / "icono_granada.png")
    return img


def icono_niebla():
    img = Image.new("RGBA", (16, 10), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.ellipse([1, 2, 7, 7], fill=rgb("cielo"))
    dr.ellipse([5, 0, 12, 7], fill=rgb("cielo"))
    dr.rectangle([2, 5, 13, 7], fill=rgb("cielo"))
    dr.line([0, 9, 7, 9], fill=rgb("niebla"))
    dr.line([9, 9, 15, 9], fill=rgb("niebla"))
    dr.point([6, 2], fill=rgb("crema"))
    dr.point([7, 1], fill=rgb("crema"))
    img.save(UI / "icono_niebla.png")
    return img


def icono_bala():
    img = Image.new("RGBA", (3, 8), (0, 0, 0, 0))
    px = img.load()
    rect(px, 0, 2, 2, 7, rgb("laton"))
    px[0, 2] = mezcla(rgb("laton"), rgb("crema"), 0.5)
    rect(px, 0, 1, 2, 1, rgb("oxido"))
    px[1, 0] = rgb("oxido")
    img.save(UI / "icono_bala.png")
    return img


def icono_agachado():
    img = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
    px = img.load()
    a = rgb("ambar")
    for x, y in ((0, 2), (1, 3), (2, 4), (3, 5), (4, 6), (5, 5), (6, 4), (7, 3), (8, 2),
                 (1, 2), (2, 3), (3, 4), (4, 5), (5, 4), (6, 3), (7, 2)):
        px[x, y] = a
    return contorno(img).save(UI / "icono_agachado.png")


# ---------------------------------------------------------------------------
# RETRATO PROVISIONAL (hasta que lleguen los de ChatGPT): se pinta suave a
# tamaño grande y se reduce, para que quede "foto pixelada".
# ---------------------------------------------------------------------------
def retrato_provisional():
    S = 6
    W, H = 38, 30
    big = Image.new("RGBA", (W * S, H * S), rgb("oliva_0"))
    dr = ImageDraw.Draw(big)
    # Fondo con luz desde arriba a la izquierda
    for y in range(H * S):
        dr.line([0, y, W * S, y], fill=mezcla(rgb("oliva_1"), rgb("oliva_0"), y / (H * S)))
    cx = W * S // 2
    # Hombros / chaqueta
    dr.ellipse([cx - 120, 150, cx + 120, 300], fill=mezcla(rgb("oliva_3"), rgb("madera_osc"), 0.3))
    dr.polygon([(cx - 22, 150), (cx + 22, 150), (cx, 180)], fill=rgb("oliva_2"))
    # Cuello
    dr.rectangle([cx - 18, 125, cx + 18, 160], fill=rgb("piel_osc"))
    # Cara
    dr.ellipse([cx - 40, 48, cx + 40, 150], fill=rgb("piel"))
    dr.ellipse([cx + 4, 52, cx + 44, 150], fill=mezcla(rgb("piel"), rgb("piel_osc"), 0.55))
    dr.ellipse([cx - 30, 60, cx + 2, 100], fill=mezcla(rgb("piel"), rgb("crema"), 0.25))
    # Barba de días
    dr.ellipse([cx - 34, 108, cx + 34, 152], fill=mezcla(rgb("piel_osc"), rgb("piel"), 0.45))
    dr.ellipse([cx - 28, 100, cx + 28, 140], fill=mezcla(rgb("piel"), rgb("piel_osc"), 0.25))
    # Cejas y ojos (en sombra bajo el casco)
    dr.rectangle([cx - 34, 74, cx + 34, 88], fill=mezcla(rgb("piel_osc"), rgb("negro"), 0.2))
    dr.rectangle([cx - 30, 80, cx - 8, 92], fill=rgb("negro"))
    dr.rectangle([cx + 8, 80, cx + 30, 92], fill=rgb("negro"))
    dr.rectangle([cx - 26, 84, cx - 20, 90], fill=rgb("crema"))
    dr.rectangle([cx + 12, 84, cx + 18, 90], fill=mezcla(rgb("crema"), rgb("piel_osc"), 0.4))
    # Nariz y boca
    dr.polygon([(cx - 2, 88), (cx + 8, 116), (cx - 8, 116)], fill=mezcla(rgb("piel"), rgb("piel_osc"), 0.5))
    dr.rectangle([cx - 14, 126, cx + 14, 130], fill=rgb("piel_osc"))
    # Barboquejo
    dr.line([cx - 40, 80, cx - 30, 150], fill=mezcla(rgb("madera_osc"), rgb("oliva_2"), 0.5), width=6)
    dr.line([cx + 40, 80, cx + 30, 150], fill=mezcla(rgb("madera_osc"), rgb("oliva_2"), 0.5), width=6)
    # Casco M1 con red
    big2 = Image.new("RGBA", big.size, (0, 0, 0, 0))
    d2 = ImageDraw.Draw(big2)
    d2.ellipse([cx - 66, 6, cx + 66, 128], fill=rgb("oliva_3"))
    d2.rectangle([0, 72, W * S, H * S], fill=(0, 0, 0, 0))
    d2.ellipse([cx - 58, 10, cx + 20, 60], fill=rgb("oliva_4"))
    d2.rectangle([cx - 74, 66, cx + 74, 76], fill=rgb("oliva_2"))   # ala del casco
    d2.line([cx - 74, 66, cx + 74, 66], fill=rgb("oliva_4"), width=3)
    rnd = random.Random(3)
    for _ in range(140):                                          # red del casco
        x = rnd.randint(cx - 60, cx + 60)
        y = rnd.randint(8, 66)
        if big2.getpixel((x, y))[3]:
            d2.rectangle([x, y, x + 4, y + 4], fill=rgb("oliva_1"))
    base = Image.new("RGBA", big.size)
    base = big.copy()
    # repintar zona del casco sobre la cara
    base.alpha_composite(big2)
    img = base.resize((W, H), Image.BOX)
    img = cuantizar(img)
    img.save(UI / "retrato_provisional.png")
    return img


def cuantizar(img):
    """Reduce los colores a la paleta del juego (así combina con todo)."""
    pal = Image.new("P", (1, 1))
    cols = []
    for h in PALETA.values():
        cols += [int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)]
    # Agregar tonos intermedios de piel y oliva para que la cara no quede plana
    extra = [mezcla(rgb("piel"), rgb("piel_osc"), t)[:3] for t in (0.25, 0.5, 0.75)]
    extra += [mezcla(rgb("piel"), rgb("crema"), 0.3)[:3]]
    for e in extra:
        cols += list(e)
    cols += [0, 0, 0] * (256 - len(cols) // 3)
    pal.putpalette(cols)
    a = img.split()[3]
    q = img.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGBA")
    q.putalpha(a)
    return q


# ---------------------------------------------------------------------------
# TEXTURAS DE LAS ARMAS EN LA MANO (32x32, se repiten). Se proyectan sobre
# las cajas del modelo; el eje horizontal de la textura va a lo largo del arma.
# ---------------------------------------------------------------------------
ARMAS = RAIZ / "assets" / "armas"


def _ruido_img(tam, semilla, base, claro, oscuro, p_claro, p_oscuro):
    rnd = random.Random(semilla)
    img = Image.new("RGB", (tam, tam))
    px = img.load()
    for y in range(tam):
        for x in range(tam):
            n = rnd.random()
            c = base
            if n < p_oscuro:
                c = oscuro
            elif n > 1 - p_claro:
                c = claro
            px[x, y] = c[:3]
    return img, px, rnd


def tex_madera_arma():
    """Nogal aceitado: vetas horizontales onduladas."""
    import math
    t = 32
    base = mezcla(rgb("madera"), rgb("madera_osc"), 0.35)
    img, px, rnd = _ruido_img(t, 11, base, rgb("madera"), mezcla(base, rgb("madera_osc"), 0.5), 0.08, 0.08)
    for k in range(7):
        y0 = rnd.uniform(0, t)
        fase = rnd.uniform(0, 6.28)
        col = rgb("madera_osc") if k % 2 == 0 else mezcla(rgb("madera"), rgb("madera_clara"), 0.5)
        for x in range(t):
            # la onda completa un número entero de ciclos para que se repita sin costura
            y = int(y0 + 1.6 * math.sin(2 * math.pi * x / t * 2 + fase)) % t
            px[x, y] = col[:3]
    img.save(ARMAS / "madera.png")


def tex_metal_arma():
    """Acero fosfatado (gris verdoso mate) con desgaste en claro."""
    base = mezcla(rgb("acero"), rgb("oliva_1"), 0.35)
    img, px, rnd = _ruido_img(32, 12, base, mezcla(rgb("acero_claro"), base, 0.7),
                              mezcla(base, rgb("negro"), 0.3), 0.06, 0.12)
    img.save(ARMAS / "metal.png")


def tex_piel():
    base = rgb("piel")
    img, px, rnd = _ruido_img(32, 13, base, mezcla(base, rgb("crema"), 0.15),
                              mezcla(base, rgb("piel_osc"), 0.3), 0.08, 0.14)
    # suciedad y arena
    for _ in range(12):
        x, y = rnd.randrange(32), rnd.randrange(32)
        px[x, y] = mezcla(rgb("piel"), rgb("arena_moj"), 0.5)[:3]
    img.save(ARMAS / "piel.png")


def tex_manga():
    """Sarga verde oliva de la chaqueta M1941, con pliegues."""
    base = mezcla(rgb("oliva_3"), rgb("arena_moj"), 0.35)
    img, px, rnd = _ruido_img(32, 14, base, mezcla(base, rgb("oliva_4"), 0.6),
                              mezcla(base, rgb("oliva_1"), 0.5), 0.06, 0.06)
    for y in range(32):
        for x in range(32):
            if (x + y) % 4 == 0:   # tejido diagonal
                px[x, y] = mezcla(tuple(list(px[x, y]) + [255]), rgb("oliva_1"), 0.25)[:3]
    for k in range(3):             # pliegues
        x0 = rnd.randrange(32)
        for y in range(32):
            x = (x0 + y // 3) % 32
            px[x, y] = mezcla(tuple(list(px[x, y]) + [255]), rgb("oliva_0"), 0.35)[:3]
    img.save(ARMAS / "manga.png")


# ---------------------------------------------------------------------------
# LÁMINA DE LA GUÍA DE ESTILO
# ---------------------------------------------------------------------------
def lamina(iconos, celda_g, celda_m):
    W, H = 320, 200
    img = Image.new("RGBA", (W, H), rgb("oliva_0"))
    sombra = rgb("negro")
    texto_px(img, 6, 6, "NORMANDY 1944 - GUIA DE ESTILO", rgb("ambar"), sombra)
    # Paleta
    texto_px(img, 6, 20, "PALETA", rgb("crema"), sombra)
    for i, (n, h) in enumerate(PALETA.items()):
        x, y = 6 + (i % 16) * 19, 30 + (i // 16) * 13
        ImageDraw.Draw(img).rectangle([x, y, x + 17, y + 11], fill=rgb(n), outline=rgb("negro"))
    # Letra
    texto_px(img, 6, 62, "LETRA", rgb("crema"), sombra)
    texto_px(img, 6, 74, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", rgb("crema"), sombra)
    texto_px(img, 6, 86, "0123456789 ÁÉÍÓÚÑ ¡¿?! [ZONA DESPEJADA]", rgb("crema"), sombra)
    # Números
    texto_px(img, 6, 102, "NUMEROS", rgb("crema"), sombra)
    on = Image.open(UI / "digitos_g_on.png")
    off = Image.open(UI / "digitos_g_off.png")
    x = 6
    for ch in "08|80":
        i = "0123456789:|-".index(ch)
        img.alpha_composite(off.crop((i * celda_g, 0, (i + 1) * celda_g, off.height)), (x, 112))
        img.alpha_composite(on.crop((i * celda_g, 0, (i + 1) * celda_g, on.height)), (x, 112))
        x += celda_g
    on = Image.open(UI / "digitos_m_on.png")
    off = Image.open(UI / "digitos_m_off.png")
    x = 80
    for ch in "06:30":
        i = "0123456789:|-".index(ch)
        if ch != ":":
            img.alpha_composite(off.crop((i * celda_m, 0, (i + 1) * celda_m, off.height)), (x, 116))
        img.alpha_composite(on.crop((i * celda_m, 0, (i + 1) * celda_m, on.height)), (x, 116))
        x += celda_m
    # Marcos
    texto_px(img, 130, 102, "MARCOS", rgb("crema"), sombra)
    img.alpha_composite(Image.open(UI / "chapa.png"), (130, 112))
    img.alpha_composite(Image.open(UI / "chapa_lisa.png"), (158, 112))
    img.alpha_composite(Image.open(UI / "hundido.png"), (186, 118))
    # Íconos
    texto_px(img, 6, 142, "ICONOS", rgb("crema"), sombra)
    x = 6
    for ic in iconos:
        img.alpha_composite(ic, (x, 154))
        x += ic.width + 6
    texto_px(img, 220, 102, "RETRATO", rgb("crema"), sombra)
    r = Image.open(UI / "retrato_provisional.png")
    img.alpha_composite(r, (220, 112))
    img.save(DOCS / "guia_estilo.png")
    img.resize((W * 3, H * 3), Image.NEAREST).save(DOCS / "guia_estilo_x3.png")


def paleta_png():
    img = Image.new("RGB", (16 * 8, 2 * 8))
    for i, n in enumerate(PALETA):
        ImageDraw.Draw(img).rectangle([(i % 16) * 8, (i // 16) * 8, (i % 16) * 8 + 7, (i // 16) * 8 + 7],
                                      fill=rgb(n)[:3])
    img.save(DOCS / "paleta.png")


if __name__ == "__main__":
    construir_ttf(FUENTES / "normandy.ttf")
    cg = hoja_digitos(11, 19, 3, "digitos_g")
    cm = hoja_digitos(7, 12, 2, "digitos_m")
    chapa()
    chapa_lisa()
    hundido()
    for r, n in ((28, "boton_g"), (17, "boton_m"), (15, "boton_c")):
        boton_redondo(r, n, False)
        boton_redondo(r, n + "_on", True)
    iconos = [icono_garand(), icono_colt(), icono_granada(), icono_niebla(), icono_bala()]
    icono_agachado()
    retrato_provisional()
    ARMAS.mkdir(parents=True, exist_ok=True)
    tex_madera_arma(); tex_metal_arma(); tex_piel(); tex_manga()
    paleta_png()
    lamina(iconos, cg, cm)
    print("listo:", cg, cm)
