# Normandy 1944

FPS cooperativo retro de la Segunda Guerra Mundial, hecho en **Godot 4.7** y jugable en el navegador del celular.

**Jugar:** https://tomasrojasmurua.github.io/normandia-1944/

## Controles

| En el celular | En el computador |
|---|---|
| Dedo en la mitad izquierda: caminar | W A S D |
| Deslizar en la mitad derecha: mirar | Mouse (clic para capturarlo, Esc para soltarlo) |
| Botón SALTAR | Barra espaciadora |

Para jugar a pantalla completa en el celular: abre el link y usa **Compartir → Agregar a pantalla de inicio** (iPhone) o **⋮ → Instalar app** (Android).

## Cómo se publica

Cada vez que se sube un cambio a la rama `main`, GitHub exporta el juego con Godot y lo publica solo
(archivo `.github/workflows/publicar.yml`). El avance se ve en la pestaña **Actions** del repositorio:
punto amarillo = trabajando, ✔ verde = publicado (tarda unos 2–4 minutos), ✖ rojo = algo falló.

## Estructura

```
project.godot          configuración del proyecto
export_presets.cfg     configuración de exportación web (PWA, un solo hilo)
scenes/                escenas (main = escena de prueba, player = soldado)
scripts/               código del jugador, controles táctiles y escenario de prueba
assets/icons/          íconos de la app en el celular
.github/workflows/     publicación automática
```

## Decisiones técnicas

- Renderizador **Compatibility** (WebGL 2): el único que funciona en navegadores.
- Exportación **de un solo hilo**: funciona en cualquier hosting y en Safari de iPhone.
- Resolución interna **640×360** escalada a la pantalla: da el look pixelado retro y rinde bien en celulares.
- Hosting en **GitHub Pages**: el motor pesa ~39 MB y Cloudflare Pages solo acepta archivos de hasta 25 MB.
  Cloudflare queda para el servidor del modo cooperativo.
