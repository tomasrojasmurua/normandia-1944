#!/usr/bin/env python3
"""Ajusta la importación de los sprites: sin compresión con pérdida, sin
mipmaps y sin pasar a compresión de 3D (se verían borrosos y manchados).
Correr después de `godot --headless --path . --import`, y volver a importar."""
import glob, os, re
raiz = os.path.join(os.path.dirname(__file__), '..', '..')
for f in glob.glob(os.path.join(raiz, 'assets/sprites/*/*/*.png.import')):
    s = open(f).read()
    n = re.sub(r'compress/mode=\d', 'compress/mode=0', s)
    n = re.sub(r'mipmaps/generate=\w+', 'mipmaps/generate=false', n)
    n = re.sub(r'detect_3d/compress_to=\d', 'detect_3d/compress_to=0', n)
    if n != s:
        open(f, 'w').write(n)
        # obligar a Godot a reimportar
        for m in glob.glob(os.path.join(raiz, '.godot/imported/' + os.path.basename(f)[:-7] + '-*.md5')):
            os.remove(m)
