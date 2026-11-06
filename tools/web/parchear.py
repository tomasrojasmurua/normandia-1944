"""Arreglos al motor web de Godot, aplicados al index.js ya exportado.

Uso: python3 tools/web/parchear.py build/web/index.js
(lo corre publicar.yml después de exportar; si un arreglo no encaja, falla
para que no se publique sin él: revisar al cambiar de versión de Godot).

1. Sonidos sin copias (v0.36.1). Godot 4.7 copia el sonido ENTERO cada vez que
   lo reproduce (getAudioBuffer -> _duplicateAudioBuffer): cada disparo crea
   dos copias nuevas de la muestra. En Omaha son ~5 por segundo y varios MB de
   basura por segundo. El iPhone (WebKit) no alcanza a liberarlas y a los pocos
   minutos Safari cierra la pestaña por memoria y la recarga (lo que vio Tomás:
   "se resetea y aparece la pantalla de Godot cargando", fase 1, ~3 min, iPhone
   12, web app). Un mismo AudioBuffer puede sonar en varios reproductores a la
   vez (lo permite la norma Web Audio), así que se usa el original.
"""
import sys

ARREGLOS = [
    ("sonidos sin copias",
     "getAudioBuffer(){return this._duplicateAudioBuffer()}",
     "getAudioBuffer(){return this._audioBuffer}"),
]

ruta = sys.argv[1]
texto = open(ruta, encoding="utf-8").read()
for nombre, viejo, nuevo in ARREGLOS:
    n = texto.count(viejo)
    if n != 1:
        sys.exit(f"ERROR: el arreglo '{nombre}' no encaja (aparece {n} veces) en {ruta}")
    texto = texto.replace(viejo, nuevo)
    print("ok:", nombre)
open(ruta, "w", encoding="utf-8").write(texto)
