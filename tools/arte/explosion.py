"""Explosión en píxeles (retro, estilo Doom / Hamburger Hill) para el juego.

Dos usos:
  python3 tools/arte/explosion.py
      genera assets/efectos/explosion.png con código (10 cuadros de 64x64 en una tira)
  python3 tools/arte/explosion.py arte_fuente/efectos/explosion_chatgpt.png COLUMNAS FILAS
      adapta una hoja de ChatGPT (fondo verde o magenta liso): la corta en
      cuadros, quita el fondo, la achica a 64x64 por cuadro y la deja en 32 colores

El juego (Game._explosion_fx) lee la tira de izquierda a derecha.
"""
import sys
import numpy as np
from PIL import Image

N = 10        # cuadros
T = 64        # píxeles por cuadro
SALIDA = "assets/efectos/explosion.png"

# De caliente a frío: blanco, amarillo, naranja, rojo, marrón, humo
PALETA = [
    (255, 250, 220), (255, 230, 120), (255, 190, 60), (245, 140, 35), (215, 90, 25),
    (160, 55, 20), (100, 45, 25), (70, 55, 45), (88, 82, 74), (110, 104, 96), (132, 126, 118),
]


def ruido(rng, tam, escala):
    """Ruido suave (valor interpolado) en [0, 1]."""
    g = rng.random((tam // escala + 2, tam // escala + 2))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((tam + escala * 2, tam + escala * 2), Image.BICUBIC)
    return np.asarray(img, dtype=float)[:tam, :tam] / 255.0


def generar():
    rng = np.random.default_rng(1944)
    n1 = ruido(rng, T, 8)
    n2 = ruido(rng, T, 4)
    n3 = ruido(rng, T, 16)
    # bolas que forman la nube (dirección, tamaño)
    bolas = [(rng.uniform(0, 2 * np.pi), rng.uniform(0.35, 0.6), rng.uniform(0.5, 0.85)) for _ in range(9)]
    yy, xx = np.mgrid[0:T, 0:T].astype(float)
    hoja = Image.new("RGBA", (T * N, T), (0, 0, 0, 0))
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
    umbral = np.tile(bayer, (T // 4, T // 4))
    for f in range(N):
        t = f / (N - 1)
        crece = 1 - (1 - min(t * 1.6, 1.0)) ** 3        # se abre rápido
        sube = t * t * 10.0                                # el humo sube al final
        dens = np.full((T, T), -5.0)
        for ang, dist, tam in bolas:
            cx = T / 2 + np.cos(ang) * dist * 14 * crece
            cy = T / 2 + 6 + np.sin(ang) * dist * 9 * crece - sube - dist * 6 * t
            r = (5 + tam * 16 * crece) * (1 + 0.15 * t)
            d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
            dens = np.maximum(dens, 1 - d)
        dens = dens + (n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.25
        # se deshace al final (agujeros)
        dens = dens - np.clip(t - 0.55, 0, 1) * 1.3 * n3
        calor = np.clip(dens * 1.6 - t * 1.25 + (n2 - 0.5) * 0.4, 0, 1)
        img = np.zeros((T, T, 4), dtype=np.uint8)
        visible = dens > 0.05 + umbral * 0.18
        idx = np.where(calor > 0.02, (1 - calor) * 6.0, 7 + np.clip((n1 + t) * 2, 0, 3))
        idx = np.clip(idx.round().astype(int), 0, len(PALETA) - 1)
        for k, c in enumerate(PALETA):
            m = visible & (idx == k)
            img[m, :3] = c
            img[m, 3] = 255
        # chispas los primeros cuadros
        if f < 4:
            for _ in range(14 - f * 3):
                a = rng.uniform(0, 2 * np.pi)
                rr = rng.uniform(14, 30) * (0.6 + t * 2)
                x, y = int(T / 2 + np.cos(a) * rr), int(T / 2 + 6 + np.sin(a) * rr * 0.7 - rr * 0.3)
                if 0 <= x < T and 0 <= y < T:
                    img[y, x] = (255, 220, 120, 255)
        hoja.paste(Image.fromarray(img, "RGBA"), (f * T, 0))
    return hoja


def adaptar(ruta, cols, filas):
    src = Image.open(ruta).convert("RGBA")
    w, h = src.size
    cw, ch = w // cols, h // filas
    hoja = Image.new("RGBA", (T * cols * filas, T), (0, 0, 0, 0))
    for i in range(cols * filas):
        c = src.crop(((i % cols) * cw, (i // cols) * ch, (i % cols + 1) * cw, (i // cols + 1) * ch))
        a = np.asarray(c).astype(int)
        fondo = a[2, 2, :3]
        dif = np.abs(a[:, :, :3] - fondo).sum(axis=2)
        a[:, :, 3] = np.where(dif < 90, 0, 255)
        c = Image.fromarray(a.astype(np.uint8), "RGBA").resize((T, T), Image.LANCZOS)
        al = np.asarray(c)[:, :, 3]
        rgb = c.convert("RGB").quantize(32, dither=Image.Dither.NONE).convert("RGB")
        out = np.dstack([np.asarray(rgb), np.where(al > 128, 255, 0)]).astype(np.uint8)
        hoja.paste(Image.fromarray(out, "RGBA"), (i * T, 0))
    return hoja


if __name__ == "__main__":
    if len(sys.argv) >= 4:
        h = adaptar(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]))
    else:
        h = generar()
    import os
    os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
    h.save(SALIDA)
    print(SALIDA, h.size)
