extends Control
## HUD estilo Hamburger Hill: barra de chapa verde oliva abajo con registro de
## mensajes, retrato del soldado (se pone rojo al recibir daño), clima/hora/
## brújula, granadas, munición en números ámbar y las dos armas. También dibuja
## la cruz de puntería, el marcador de impacto, el destello rojo de daño y el
## indicador de dirección. Colores, letra y marcos vienen de Estilo.

const BAR_H := 52
const SOLDIER_NAME := "MURPHY"

var retrato: Texture2D = Estilo.RETRATO_PROVISIONAL   # se cambia por el de cada jugador

var _player: Player
var _messages: Array = []   # [texto, color, tiempo]
var _slot_rects: Array[Rect2] = []


func _ready() -> void:
	add_to_group("hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.message.connect(_on_message)


func _on_message(text: String, color: Color) -> void:
	_messages.append([text, color, 0.0])
	if _messages.size() > 4:
		_messages.pop_front()


func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	for m in _messages:
		m[2] += delta
	_messages = _messages.filter(func(m: Array) -> bool: return m[2] < 7.0)
	queue_redraw()


## Para los controles táctiles: ¿qué ranura de arma hay en este punto? (-1 = ninguna)
func slot_at(pos: Vector2) -> int:
	for i in _slot_rects.size():
		if _slot_rects[i].has_point(pos):
			return i
	return -1


func _draw() -> void:
	if _player == null:
		return
	var s := size
	var w := _player.weapons
	var top := s.y - BAR_H
	var center := Vector2(s.x / 2.0, top / 2.0).floor()

	# --- Efectos sobre la vista
	if _player.damage_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.7, 0.0, 0.0, _player.damage_flash * 0.3))
	if _player.hit_indicator > 0.0 and not _player.dead:
		_draw_hit_indicator(center, _player.hit_angle, minf(_player.hit_indicator, 1.0))
	if not _player.dead and w.ads_amount < 0.5 and not _player.sprinting:
		_draw_crosshair(center, w.spread_now)
	if w.hit_marker > 0.0:
		var c := Color(1, 1, 1, w.hit_marker)
		for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(center + d * 3, center + d * 7, c, 1.0)
	if _player.dead:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.45))
		Estilo.texto_c(self, "HAS CAIDO", s.x / 2, top / 2 + 2, Estilo.ROJO, Estilo.TAM_GRANDE)
		Estilo.texto_c(self, "REINICIANDO...", s.x / 2, top / 2 + 18, Estilo.CREMA)

	Estilo.texto(self, "NORMANDY 1944  V%s" % ProjectSettings.get_setting("application/config/version"),
		Vector2(4, 10), Color(Estilo.CREMA, 0.35))

	# --- Barra inferior
	Estilo.marco(self, Rect2(0, top, s.x, BAR_H), "lisa")
	var right_w := 486.0
	var x := s.x - right_w
	_draw_messages(Rect2(3, top + 3, x - 6, BAR_H - 6))
	_draw_portrait(Rect2(x, top + 2, 60, BAR_H - 4))
	_draw_status(Rect2(x + 62, top + 2, 76, BAR_H - 4))
	_draw_grenades(Rect2(x + 140, top + 2, 67, BAR_H - 4))
	_draw_ammo(Rect2(x + 209, top + 2, 105, BAR_H - 4))
	_draw_slots(Rect2(x + 316, top + 2, right_w - 318, BAR_H - 4))


func _draw_crosshair(c: Vector2, spread_deg: float) -> void:
	var gap := roundf(2.0 + spread_deg * 2.2)
	var col := Color(Estilo.AMBAR_CLARO, 0.9)
	var sombra := Color(Estilo.NEGRO, 0.6)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var a: Vector2 = c + d * gap
		var b: Vector2 = c + d * (gap + 5)
		draw_line(a + Vector2(1, 1), b + Vector2(1, 1), sombra, 1.0)
		draw_line(a, b, col, 1.0)


func _draw_hit_indicator(c: Vector2, angle: float, alpha: float) -> void:
	# Arco rojo alrededor del centro apuntando hacia quien te disparó
	var a := angle - PI / 2.0
	draw_arc(c, 46, a - 0.35, a + 0.35, 8, Color(Estilo.ROJO, 0.85 * alpha), 3.0)


func _draw_messages(r: Rect2) -> void:
	Estilo.marco(self, r, "hundido")
	var y := r.position.y + 11
	for m in _messages:
		var col: Color = m[1]
		col.a = clampf(7.0 - m[2], 0.0, 1.0)
		Estilo.texto(self, m[0], Vector2(r.position.x + 4, y), col, Estilo.TAM, r.size.x - 6)
		y += 10


func _draw_portrait(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	Estilo.texto_c(self, SOLDIER_NAME, r.position.x + r.size.x / 2, r.position.y + 10, Estilo.CREMA)
	var hp := clampf(_player.health / _player.max_health, 0.0, 1.0)
	# Retrato: se tiñe de rojo con el daño y queda gris al morir
	var face := Rect2(r.position + Vector2(4, 12), Vector2(40, 32))
	Estilo.marco(self, face, "hundido")
	var tinte := Color.WHITE.lerp(Color(1.0, 0.35, 0.3), (1.0 - hp) * 0.9)
	if _player.dead:
		tinte = Color(0.45, 0.45, 0.45)
	draw_texture_rect(retrato, Rect2(face.position + Vector2(1, 1), face.size - Vector2(2, 2)), false, tinte)
	if _player.crouching:
		Estilo.icono(self, Estilo.ICONO_AGACHADO, face.position + Vector2(7, face.size.y - 6))
	# Vida: barra vertical de LEDs al lado del retrato
	var bar := Rect2(r.position + Vector2(46, 12), Vector2(9, 32))
	Estilo.marco(self, bar, "hundido")
	var segs := 10
	var col_on := Estilo.VERDE_LED if hp > 0.35 else Estilo.ROJO
	for i in segs:
		var filled := float(i) < hp * segs
		var y := bar.end.y - 3 - (i + 1) * 3
		draw_rect(Rect2(bar.position.x + 2, y + 1, bar.size.x - 4, 2),
			col_on if filled else Color(Estilo.OLIVA_2, 1.0))


func _draw_status(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	# Clima
	Estilo.icono(self, Estilo.ICONO_NIEBLA, r.position + Vector2(14, 8))
	Estilo.texto(self, "NIEBLA", r.position + Vector2(24, 12), Estilo.CREMA)
	# Hora
	var clock := Rect2(r.position + Vector2(5, 15), Vector2(r.size.x - 10, 15))
	Estilo.marco(self, clock, "hundido")
	var t := Game.clock_text()
	var tw := t.length() * 9   # 9 px por dígito mediano
	Estilo.numero(self, t, Vector2(roundf(clock.position.x + (clock.size.x - tw) / 2.0), clock.position.y + 1),
		Estilo.DIG_MEDIANO)
	# Brújula (norte = el mar, como en la playa de Omaha)
	var comp := Rect2(r.position + Vector2(5, 31), Vector2(r.size.x - 10, 13))
	Estilo.marco(self, comp, "hundido")
	var fwd := -_player.global_basis.z
	var bearing := fmod(rad_to_deg(atan2(-fwd.x, fwd.z)) + 360.0, 360.0)
	var names := ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
	var mid := roundf(comp.position.x + comp.size.x / 2)
	for i in 16:
		var deg := i * 22.5
		var diff := wrapf(deg - bearing, -180.0, 180.0)
		if absf(diff) > 60.0:
			continue
		var px := roundf(mid + diff / 60.0 * (comp.size.x / 2 - 7))
		if i % 2 == 0:
			var col := Estilo.CREMA if i != 0 else Estilo.AMBAR_CLARO
			Estilo.texto_c(self, names[i / 2], px, comp.position.y + 11, col)
		else:
			draw_line(Vector2(px, comp.position.y + 7), Vector2(px, comp.position.y + 10), Estilo.OLIVA_4, 1.0)
	draw_rect(Rect2(mid, comp.position.y + 1, 1, 3), Estilo.AMBAR)


func _draw_grenades(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	var n := _player.grenades
	var inner := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10))
	Estilo.marco(self, inner, "hundido")
	var dy := roundf(inner.position.y + (inner.size.y - Estilo.alto_numero()) / 2.0)
	Estilo.numero(self, str(n), Vector2(inner.position.x + 9, dy), Estilo.DIG_GRANDE, 1,
		Color.WHITE if n > 0 else Color(1, 1, 1, 0.0))
	Estilo.icono(self, Estilo.ICONO_GRANADA, inner.position + Vector2(39, inner.size.y / 2.0),
		Color.WHITE if n > 0 else Color(0.4, 0.42, 0.38))
	if n > 0:
		draw_rect(Rect2(inner.position.x + 9, inner.end.y - 4, 13, 2), Estilo.AMBAR)


func _draw_ammo(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	var inner := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10))
	Estilo.marco(self, inner, "hundido")
	var w := _player.weapons
	var mag := w.ammo[w.current]
	var res := w.reserve[w.current]
	# 2 dígitos de cargador | 3 de reserva, centrados
	var ancho := 13 * 5 + 9
	var x := roundf(inner.position.x + (inner.size.x - ancho) / 2.0)
	var y := inner.position.y + 3
	var rojo := Color(1.0, 0.45, 0.4)
	x += Estilo.numero(self, str(mag), Vector2(x, y), Estilo.DIG_GRANDE, 2, Color.WHITE if mag > 0 else rojo)
	draw_rect(Rect2(x + 3, y + 3, 2, Estilo.alto_numero() - 6), Estilo.AMBAR)
	x += 9
	Estilo.numero(self, str(res), Vector2(x, y), Estilo.DIG_GRANDE, 3,
		Color.WHITE if res > 0 else Color(1, 1, 1, 0.25))
	var by := inner.end.y - 11
	if w.is_reloading():
		if int(Time.get_ticks_msec() / 250) % 2 == 0:
			Estilo.texto_c(self, "RECARGANDO", inner.get_center().x, inner.end.y - 3, Estilo.CREMA)
	elif w.current == 0 and mag > 0:
		# Balas del clip del Garand
		for i in mag:
			draw_texture(Estilo.ICONO_BALA, Vector2(roundf(inner.get_center().x - mag * 2.5) + i * 5, by + 1))


func _draw_slots(r: Rect2) -> void:
	var w := _player.weapons
	_slot_rects.clear()
	var sw := floorf((r.size.x - 2) / 2.0)
	for i in 2:
		var sr := Rect2(r.position + Vector2(i * (sw + 2), 0), Vector2(sw, r.size.y))
		_slot_rects.append(sr)
		Estilo.marco(self, sr, "chapa")
		var inner := Rect2(sr.position + Vector2(5, 5), sr.size - Vector2(10, 10))
		Estilo.marco(self, inner, "hundido")
		var selected := i == w.current
		Estilo.texto(self, str(i + 1), inner.position + Vector2(3, 10),
			Estilo.AMBAR if selected else Estilo.OLIVA_4)
		var tex := Estilo.ICONO_GARAND if i == 0 else Estilo.ICONO_COLT
		var tinte := Color.WHITE if selected else Color(0.45, 0.5, 0.42)
		Estilo.icono(self, tex, inner.get_center() + Vector2(1, 1), tinte)
		if selected:
			draw_rect(Rect2(inner.position.x + 3, inner.end.y - 4, inner.size.x - 6, 2), Estilo.AMBAR)
