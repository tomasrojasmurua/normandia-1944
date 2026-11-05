"""Sonidos de ElevenLabs y música (sección 6) -> assets/sonidos/*.ogg

    arte_fuente/sonidos/<nombre>.mp3  ->  assets/sonidos/<nombre>.ogg

- Efectos sueltos: se corta el silencio del principio y del final, fundido
  corto al terminar, volumen parejo por tipo, mono, Ogg Vorbis.
- Ambientes (amb_*): bucle sin costura (los últimos 2 s se funden con el
  principio), estéreo.
- Música (musica_*): estéreo, fundido final de 1 s.
Uso: python3 tools/audio/sonidos.py   (desde la raíz del repo; necesita ffmpeg y numpy)
"""
import subprocess
from pathlib import Path
import numpy as np

RAIZ = Path(__file__).resolve().parents[2]
FUENTE = RAIZ / "arte_fuente" / "sonidos"
DESTINO = RAIZ / "assets" / "sonidos"
RATE = 44100

# Volumen objetivo (RMS de la parte con sonido, en dBFS) por tipo
NIVEL = {"grito": -17.0, "muerte": -17.0, "explosion_cerca": -14.0, "explosion_lejos": -18.0,
         "mg42": -18.0, "bala": -18.0, "impacto": -20.0, "silbido": -17.0, "rampa": -14.0,
         "maquina": -20.0, "amb": -24.0, "musica": -20.0,
         "orden": -16.0, "pedir": -16.0, "resp": -18.0,   # voces del sargento y su escuadra
         "grillo": -16.0, "bengala": -16.0}               # misión 2 (el planeador)


def leer(f, canales):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(f), "-ac", str(canales), "-ar", str(RATE),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, canales).copy()


def escribir(x, destino, calidad):
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", str(x.shape[1]),
                    "-i", "-", "-c:a", "libvorbis", "-q:a", str(calidad), str(destino)],
                   input=x.tobytes(), check=True)


def nivel(nombre):
    for k, v in NIVEL.items():
        if nombre.startswith(k):
            return v
    return -18.0


def rms_activo(x):
    m = np.abs(x).max(axis=1)
    v = x[m > 0.02]
    if len(v) == 0:
        v = x
    return 20 * np.log10(np.sqrt(np.mean(v ** 2)) + 1e-9)


def ajustar(x, objetivo):
    g = 10 ** ((objetivo - rms_activo(x)) / 20)
    pico = np.abs(x).max() * g
    if pico > 0.95:            # sin saturar
        g *= 0.95 / pico
    return x * g


def recortar(x, umbral_db=-42.0):
    env = np.abs(x).max(axis=1)
    on = np.where(env > 10 ** (umbral_db / 20))[0]
    if len(on) == 0:
        return x
    a = max(on[0] - int(0.01 * RATE), 0)
    b = min(on[-1] + int(0.15 * RATE), len(x))
    x = x[a:b]
    f = min(int(0.08 * RATE), len(x) // 4)
    x[-f:] *= np.linspace(1, 0, f)[:, None]
    return x


def bucle(x, cruce=2.0):
    n = int(cruce * RATE)
    cola, cuerpo = x[-n:], x[:-n].copy()
    t = np.linspace(0, 1, n)[:, None]
    cuerpo[:n] = cuerpo[:n] * np.sqrt(t) + cola * np.sqrt(1 - t)
    return cuerpo


if __name__ == "__main__":
    DESTINO.mkdir(parents=True, exist_ok=True)
    for f in sorted(FUENTE.glob("*.mp3")):
        n = f.stem
        if n.startswith("amb_"):
            x = bucle(ajustar(leer(f, 2), nivel(n)))
            escribir(x, DESTINO / (n + ".ogg"), 3)
        elif n.startswith("musica_"):
            x = ajustar(leer(f, 2), nivel(n))
            k = RATE
            x[-k:] *= np.linspace(1, 0, k)[:, None]
            escribir(x, DESTINO / (n + ".ogg"), 3)
        else:
            x = ajustar(recortar(leer(f, 1)), nivel(n))
            escribir(x, DESTINO / (n + ".ogg"), 2)
        print(n, round(len(x) / RATE, 2), "s")
