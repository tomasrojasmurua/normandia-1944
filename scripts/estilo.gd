class_name Estilo
## Guía de estilo del juego en un solo lugar: colores, letra pixelada,
## marcos de chapa, números ámbar e íconos. El HUD, los controles táctiles
## y (más adelante) los menús dibujan todo a través de esta clase.
## El arte se genera con tools/arte/generar_arte.py.

# --- Paleta (igual que en el generador; ver docs/arte/paleta.png)
const NEGRO := Color("#0b0d08")
const OLIVA_0 := Color("#141910")
const OLIVA_1 := Color("#1f2717")
const OLIVA_2 := Color("#2f3a22")
const OLIVA_3 := Color("#44522f")
const OLIVA_4 := Color("#66744a")
const OLIVA_5 := Color("#8d9a6a")
const CREMA := Color("#dcdcbc")
const AMBAR := Color("#e9962a")
const AMBAR_CLARO := Color("#ffd47e")
const ROJO := Color("#c4321f")
const VERDE_LED := Color("#6cc04a")

const FUENTE: FontFile = preload("res://assets/fonts/normandy.ttf")
const TAM := 11          # tamaño de letra normal (1 píxel de letra = 1 píxel de pantalla)
const TAM_GRANDE := 22   # el doble, para títulos

const _CHAPA := preload("res://assets/ui/chapa.png")
const _CHAPA_LISA := preload("res://assets/ui/chapa_lisa.png")
const _HUNDIDO := preload("res://assets/ui/hundido.png")
const _DIG_G_ON := preload("res://assets/ui/digitos_g_on.png")
const _DIG_G_OFF := preload("res://assets/ui/digitos_g_off.png")
const _DIG_M_ON := preload("res://assets/ui/digitos_m_on.png")
const _DIG_M_OFF := preload("res://assets/ui/digitos_m_off.png")

const ICONO_GARAND := preload("res://assets/ui/icono_garand.png")
const ICONO_COLT := preload("res://assets/ui/icono_colt.png")
const ICONO_GRANADA := preload("res://assets/ui/icono_granada.png")
const ICONO_NIEBLA := preload("res://assets/ui/icono_niebla.png")
const ICONO_BALA := preload("res://assets/ui/icono_bala.png")
const ICONO_AGACHADO := preload("res://assets/ui/icono_agachado.png")
const RETRATO_PROVISIONAL := preload("res://assets/ui/retrato_provisional.png")

const DIG_CHARS := "0123456789:|-"
# [hoja encendida, hoja apagada, ancho de celda, alto]
const DIG_GRANDE := 0
const DIG_MEDIANO := 1

static var _cajas := {}


## Marco 9-patch: "chapa" (con tornillos), "lisa" o "hundido".
static func caja(tipo: String) -> StyleBoxTexture:
	if _cajas.has(tipo):
		return _cajas[tipo]
	var sb := StyleBoxTexture.new()
	var m := 5
	match tipo:
		"chapa":
			sb.texture = _CHAPA
		"lisa":
			sb.texture = _CHAPA_LISA
			m = 3
		_:
			sb.texture = _HUNDIDO
			m = 2
	sb.texture_margin_left = m
	sb.texture_margin_top = m
	sb.texture_margin_right = m
	sb.texture_margin_bottom = m
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	_cajas[tipo] = sb
	return sb


static func marco(ci: CanvasItem, r: Rect2, tipo := "chapa") -> void:
	caja(tipo).draw(ci.get_canvas_item(), r)


## Texto con sombra dura de 1 píxel (como en los juegos de los 90).
static func texto(ci: CanvasItem, t: String, pos: Vector2, col: Color, tam := TAM, ancho := -1.0) -> void:
	var sombra := Color(NEGRO, col.a)
	var d := 1.0 if tam < TAM_GRANDE else 2.0
	ci.draw_string(FUENTE, pos.round() + Vector2(d, d), t, HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, sombra)
	ci.draw_string(FUENTE, pos.round(), t, HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, col)


static func ancho_texto(t: String, tam := TAM) -> float:
	return FUENTE.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x


static func texto_c(ci: CanvasItem, t: String, centro_x: float, base_y: float, col: Color, tam := TAM) -> void:
	texto(ci, t, Vector2(roundf(centro_x - ancho_texto(t, tam) / 2.0), base_y), col, tam)


## Números ámbar de 7 segmentos. "celdas" fija cuántos dígitos ocupa (los
## que sobran se ven apagados, como un display real). Devuelve el ancho.
static func numero(ci: CanvasItem, t: String, pos: Vector2, tam := DIG_GRANDE, celdas := 0,
		tinte := Color.WHITE) -> float:
	var on: Texture2D = _DIG_G_ON if tam == DIG_GRANDE else _DIG_M_ON
	var off: Texture2D = _DIG_G_OFF if tam == DIG_GRANDE else _DIG_M_OFF
	var cw := on.get_width() / DIG_CHARS.length()
	var h := on.get_height()
	var n := maxi(celdas, t.length())
	t = t.lpad(n, " ")
	var x := pos.x
	for ch in t:
		var i := DIG_CHARS.find(ch)
		if ch != ":" and ch != "|":   # el "8" apagado de fondo
			ci.draw_texture_rect_region(off, Rect2(Vector2(x, pos.y), Vector2(cw, h)), Rect2(8 * cw, 0, cw, h))
		if i >= 0:
			ci.draw_texture_rect_region(on, Rect2(Vector2(x, pos.y), Vector2(cw, h)),
				Rect2(i * cw, 0, cw, h), tinte)
		x += cw
	return x - pos.x


static func alto_numero(tam := DIG_GRANDE) -> int:
	return (_DIG_G_ON if tam == DIG_GRANDE else _DIG_M_ON).get_height()


## Dibuja una textura centrada en un punto (en píxeles enteros).
static func icono(ci: CanvasItem, tex: Texture2D, centro: Vector2, tinte := Color.WHITE) -> void:
	ci.draw_texture(tex, (centro - tex.get_size() / 2.0).floor(), tinte)
