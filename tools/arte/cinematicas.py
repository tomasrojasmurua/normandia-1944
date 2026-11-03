"""Imágenes de ChatGPT para las cinemáticas y el mapa de la campaña.

    arte_fuente/cinematicas/<nombre>.jpg  ->  assets/cinematicas/<nombre>.png  (480x270, 64 colores)
    arte_fuente/campana/mapa.jpg          ->  assets/campana/mapa.png          (330x326, 64 colores)
    arte_fuente/campana/foto_<clave>.jpg  ->  assets/campana/foto_<clave>.png  (176x99, para el diario)

Uso: python3 tools/arte/cinematicas.py   (desde la raíz del repo)
"""
from pathlib import Path
from PIL import Image
from adaptar_imagenes import reducir

RAIZ = Path(__file__).resolve().parents[2]
FUENTE = RAIZ / "arte_fuente"
ASSETS = RAIZ / "assets"


def a_16_9(img):
    W, H = img.size
    alto = int(W * 9 / 16)
    if alto <= H:
        return img.crop((0, (H - alto) // 2, W, (H - alto) // 2 + alto))
    ancho = int(H * 16 / 9)
    return img.crop(((W - ancho) // 2, 0, (W - ancho) // 2 + ancho, H))


if __name__ == "__main__":
    (ASSETS / "cinematicas").mkdir(parents=True, exist_ok=True)
    (ASSETS / "campana").mkdir(parents=True, exist_ok=True)
    for f in sorted((FUENTE / "cinematicas").glob("*.jpg")):
        img = a_16_9(Image.open(f))
        reducir(img, (480, 270), colores=64, saturacion=0.85, nitidez=1.2).save(ASSETS / "cinematicas" / (f.stem + ".png"))
        print("cinemática", f.stem)
    m = FUENTE / "campana" / "mapa.jpg"
    if m.exists():
        reducir(Image.open(m), (330, 326), colores=64, saturacion=0.8, contraste=1.05, nitidez=1.1).save(ASSETS / "campana" / "mapa.png")
        print("mapa")
    for f in sorted((FUENTE / "campana").glob("foto_*.jpg")):
        reducir(a_16_9(Image.open(f)), (176, 99), colores=32, saturacion=0.0).save(ASSETS / "campana" / (f.stem + ".png"))
        print("foto", f.stem)
