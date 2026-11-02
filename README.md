# Normandy 1944

FPS cooperativo retro de la Segunda Guerra Mundial, hecho en **Godot 4.7** y jugable en el navegador del celular.

**Jugar:** https://tomasrojasmurua.github.io/normandia-1944/

## Controles

| Acción | En el celular | En el computador |
|---|---|---|
| Caminar | Dedo en la mitad izquierda (joystick) | W A S D |
| Correr | Joystick empujado a fondo hacia adelante | Shift |
| Mirar | Deslizar en la mitad derecha | Mouse (clic para capturarlo, Esc para soltarlo) |
| Disparar | Botón FUEGO (arrastra desde él para seguir mirando). En modo GARRA hay otro FUEGO arriba a la izquierda para el índice | Clic izquierdo |
| Apuntar por la mira | Botón MIRA (activa / desactiva) | Mantener clic derecho |
| Recargar | Botón RECARGA (también recarga solo al vaciarse) | R |
| Cambiar arma | Tocar el arma 1 o 2 en la barra inferior | 1 / 2, Q o rueda del mouse |
| Granada | Botón GRANADA | G |
| Agacharse | Botón AGACHAR | C o Ctrl |
| Saltar | Botón SALTAR | Barra espaciadora |
| Modo de controles | En CONTROLES del menú o en la pausa: MODO TÁCTIL (2 DEDOS o GARRA) y DISPARO (AL TOCAR o AL SOLTAR). Quedan guardados | — |
| Disparo AL SOLTAR | Mantén FUEGO: el arma sube a la mira (puedes seguir apuntando); suelta para disparar. Con automáticas, mantener = mira + ráfaga | — |

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
scripts/
  game.gd              servicios globales: sonidos (generados por código), efectos, mensajes, reloj
  player.gd            soldado: movimiento, correr, agacharse, vida, granadas
  weapons.gd           M1 Garand y Colt M1911: disparo, mira, recarga, munición (números ajustables arriba)
  enemy.gd             soldado alemán simple: recibe daño y dispara si te ve
  grenade.gd           granada Mk 2
  hud.gd               barra inferior estilo Hamburger Hill, cruz, indicadores de daño
  touch_controls.gd    controles táctiles
  beach_decor.gd       escenario de prueba (erizos, búnker, sacos de arena)
assets/icons/          íconos de la app en el celular
.github/workflows/     publicación automática
```

## Decisiones técnicas

- Renderizador **Compatibility** (WebGL 2): el único que funciona en navegadores.
- Exportación **de un solo hilo**: funciona en cualquier hosting y en Safari de iPhone.
- Resolución interna **640×360** escalada a la pantalla: da el look pixelado retro y rinde bien en celulares.
- Hosting en **GitHub Pages**: el motor pesa ~39 MB y Cloudflare Pages solo acepta archivos de hasta 25 MB.
  Cloudflare queda para el servidor del modo cooperativo.
