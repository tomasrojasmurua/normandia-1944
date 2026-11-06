"""Imágenes del salto en paracaídas (misión 2) -> assets/salto/

    arte_fuente/salto/paracaidista.png        (fondo verde)  \\
    arte_fuente/salto/paracaidista_caida.png  (fondo verde)   >  paracaidistas.png  (2 cuadros de 64x64)
    arte_fuente/salto/steele.png              (fondo verde)  ->  colgado.png  (paracaidista colgado del arnés)
    arte_fuente/salto/bandas_manos.png        (fondo verde)  ->  bandas.png   (manos en las bandas, 480x320)
    arte_fuente/salto/tela_desde_abajo.png    (fondo verde)  ->  tela.png     (la tela vista desde abajo, 256x256)

Uso: python3 tools/arte/salto.py
"""
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter

RAIZ = Path(__file__).resolve().parents[2]
FUENTE = RAIZ / "arte_fuente" / "salto"
DESTINO = RAIZ / "assets" / "salto"


def quitar_verde(img):
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            exceso = g - max(r, b)
            if exceso > 60 and g > 120:
                px[x, y] = (0, 0, 0, 0)
            elif exceso > 0:
                px[x, y] = (r, max(r, b) + exceso // 4, b, 255 if exceso < 30 else 160)
    return img


def quitar_negro(img, desde=0.17, hasta=0.32):
    """Fondo negro (con un halo) -> transparente según el brillo."""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255.0
            k = min(max((lum - desde) / (hasta - desde), 0.0), 1.0)
            px[x, y] = (r, g, b, int(255 * k))
    return img


def quitar_halo(img):
    """Fondo negro con un halo cálido alrededor de las manos -> transparente.
    Queda lo claro (bandas, manos) y lo verdoso (las mangas); el halo es pardo rojizo."""
    img = img.convert("RGBA")
    px = img.load()
    alfa = Image.new("L", img.size, 0)
    pa = alfa.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255.0
            halo = lum < 0.3 and r > g * 1.3
            # las mangas entran en diagonal desde las esquinas de abajo
            borde = (y / img.height - 0.55) * img.width * 0.55
            manga = (x < borde or x > img.width - borde) and lum > 0.09 and not halo
            if lum > 0.34 or manga or (r > g * 1.1 and lum > 0.27):
                pa[x, y] = 255
    # cerrar huecos (sombras de los dedos) y limpiar puntos sueltos
    alfa = alfa.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MinFilter(11))
    alfa = alfa.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    img.putalpha(alfa)
    return img


def recortar(img):
    caja = img.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    return img.crop(caja) if caja else img


def reducir(img, tam, colores=48, contraste=1.1, nitidez=1.4):
    """Achica a `tam` (en dos pasos) y pasa a pocos colores; el alfa queda en 0 o 255."""
    w, h = tam
    img = img.resize((w * 4, h * 4), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2, percent=70, threshold=2))
    img = img.resize((w, h), Image.BOX)
    alfa = img.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rgb = ImageEnhance.Contrast(img.convert("RGB")).enhance(contraste)
    rgb = ImageEnhance.Sharpness(rgb).enhance(nitidez)
    rgb = rgb.quantize(colors=colores, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(alfa)
    return out


def encajar(img, celda):
    """Achica manteniendo la proporción para que entre en `celda` (w, h), centrado abajo."""
    w, h = img.size
    e = min(celda[0] / w, celda[1] / h)
    t = (max(1, int(w * e)), max(1, int(h * e)))
    return reducir(img, t), t


if __name__ == "__main__":
    DESTINO.mkdir(parents=True, exist_ok=True)
    # Paracaidistas: cuadro 1 con la tela abierta, cuadro 2 en caída libre
    hoja = Image.new("RGBA", (128, 64), (0, 0, 0, 0))
    a = recortar(quitar_verde(Image.open(FUENTE / "paracaidista.png")))
    a, t = encajar(a, (62, 64))
    hoja.paste(a, ((64 - t[0]) // 2, 64 - t[1]), a)
    # Los cordones son muy finos y se pierden al achicar: se dibujan de nuevo,
    # del borde de la tela a las manos del hombre.
    from PIL import ImageDraw
    al = hoja.crop((0, 0, 64, 64)).getchannel("A")
    filas = [any(al.getpixel((x, y)) > 0 for x in range(64)) for y in range(64)]
    tela_fin = next(y for y in range(64) if filas[y]) 
    while tela_fin < 63 and filas[tela_fin + 1]:
        tela_fin += 1
    hombre = next(y for y in range(tela_fin + 2, 64) if filas[y])
    xs = [x for x in range(64) if al.getpixel((x, tela_fin)) > 0]
    xs_h = [x for x in range(64) if al.getpixel((x, hombre)) > 0] or [32]
    mano = (min(xs_h) + max(xs_h)) / 2.0
    d = ImageDraw.Draw(hoja)
    for k in range(6):
        x0 = min(xs) + (max(xs) - min(xs)) * k / 5.0
        lado = -1 if k < 3 else 1
        d.line([(x0, tela_fin), (mano + lado * 1.5, hombre)], fill=(178, 170, 140, 255), width=1)
    b = recortar(quitar_verde(Image.open(FUENTE / "paracaidista_caida.png")))
    b, t = encajar(b, (40, 26))
    hoja.paste(b, (64 + (64 - t[0]) // 2, 64 - t[1] - 18), b)
    hoja.save(DESTINO / "paracaidistas.png")
    print("paracaidistas")
    # Colgado del arnés: las cuerdas salen por arriba (alto ~ 1 px = 2,5 cm, como los soldados)
    c = recortar(quitar_verde(Image.open(FUENTE / "steele.png")))
    c, t = encajar(c, (60, 112))
    c.save(DESTINO / "colgado.png")
    print("colgado", t)
    # Las manos en las bandas (primera persona)
    m = quitar_verde(Image.open(FUENTE / "bandas_manos.png"))
    m = reducir(m, (480, 320), colores=48, nitidez=1.0)
    m.save(DESTINO / "bandas.png")
    print("bandas")
    # La tela desde abajo
    tela = recortar(quitar_verde(Image.open(FUENTE / "tela_desde_abajo.png")))
    tela = reducir(tela, (256, 256), colores=40, nitidez=1.0)
    tela.save(DESTINO / "tela.png")
    print("tela")
