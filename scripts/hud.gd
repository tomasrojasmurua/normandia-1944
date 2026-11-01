extends Control
## HUD estilo Hamburger Hill: barra verde inferior con registro de mensajes,
## retrato del soldado (se pone rojo al recibir daño), clima/hora/brújula,
## granadas, munición y las dos armas. También dibuja la cruz de puntería,
## el marcador de impacto, el destello rojo de daño y el indicador de dirección.
## Todo se dibuja con código: no hay imágenes todavía.

const BAR_H := 52
const C_PANEL := Color(0.14, 0.18, 0.11)
const C_EDGE := Color(0.32, 0.38, 0.24)
const C_EDGE_DARK := Color(0.06, 0.08, 0.05)
const C_INNER := Color(0.04, 0.06, 0.04)
const C_TEXT := Color(0.84, 0.9, 0.74)
const C_DIM := Color(0.45, 0.52, 0.4)
const C_ORANGE := Color(0.98, 0.66, 0.16)
const SOLDIER_NAME := "MURPHY"

var _font: Font
var _player: Player
var _messages: Array = []   # [texto, color, tiempo]
var _slot_rects: Array[Rect2] = []


func _ready() -> void:
	add_to_group("hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
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
	var center := Vector2(s.x / 2.0, top / 2.0)

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
		_text_c("HAS CAIDO", Vector2(s.x / 2, top / 2 - 6), 24, Game.COLOR_BAD)
		_text_c("REINICIANDO...", Vector2(s.x / 2, top / 2 + 14), 10, C_TEXT)

	draw_string(_font, Vector2(5, 11), "NORMANDY 1944  v%s" % ProjectSettings.get_setting("application/config/version"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.1, 0.12, 0.08, 0.75))

	# --- Barra inferior
	draw_rect(Rect2(0, top, s.x, BAR_H), C_EDGE_DARK)
	var right_w := 486.0
	var x := s.x - right_w
	_draw_messages(Rect2(3, top + 3, x - 6, BAR_H - 6))
	_draw_portrait(Rect2(x, top + 3, 60, BAR_H - 6))
	_draw_status(Rect2(x + 63, top + 3, 74, BAR_H - 6))
	_draw_grenades(Rect2(x + 140, top + 3, 66, BAR_H - 6))
	_draw_ammo(Rect2(x + 209, top + 3, 104, BAR_H - 6))
	_draw_slots(Rect2(x + 316, top + 3, right_w - 319, BAR_H - 6))


func _panel(r: Rect2) -> void:
	draw_rect(r, C_PANEL)
	draw_rect(r, C_EDGE, false, 1.0)
	draw_line(r.position + Vector2(1, 1), r.position + Vector2(r.size.x - 1, 1), Color(0.42, 0.5, 0.32), 1.0)


func _inner(r: Rect2) -> void:
	draw_rect(r, C_INNER)
	draw_rect(r, C_EDGE_DARK, false, 1.0)


func _text(t: String, pos: Vector2, sz: int, col: Color) -> void:
	draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 2, Color(0, 0, 0, col.a))
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_c(t: String, pos: Vector2, sz: int, col: Color) -> void:
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_text(t, pos - Vector2(tw / 2.0, 0), sz, col)


func _draw_crosshair(c: Vector2, spread_deg: float) -> void:
	var gap := 2.0 + spread_deg * 2.2
	var col := Color(0.95, 0.85, 0.2, 0.9)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * gap, c + d * (gap + 5), col, 1.0)


func _draw_hit_indicator(c: Vector2, angle: float, alpha: float) -> void:
	# Arco rojo alrededor del centro apuntando hacia quien te disparó
	var a := angle - PI / 2.0
	draw_arc(c, 46, a - 0.35, a + 0.35, 8, Color(1, 0.1, 0.05, 0.8 * alpha), 3.0)


func _draw_messages(r: Rect2) -> void:
	_inner(r)
	var y := r.position.y + 10
	for m in _messages:
		var col: Color = m[1]
		col.a = clampf(7.0 - m[2], 0.0, 1.0)
		_text(m[0], Vector2(r.position.x + 4, y), 8, col)
		y += 10


func _draw_portrait(r: Rect2) -> void:
	_panel(r)
	_text_c(SOLDIER_NAME, r.position + Vector2(r.size.x / 2, 9), 8, C_TEXT)
	var hp := clampf(_player.health / _player.max_health, 0.0, 1.0)
	var face := Rect2(r.position + Vector2(13, 12), Vector2(34, 26))
	draw_rect(face, C_INNER)
	# Cara pixelada: se pone roja con el daño y gris al morir
	var skin := Color(0.82, 0.6, 0.45).lerp(Color(0.9, 0.12, 0.08), (1.0 - hp) * 0.8)
	if _player.dead:
		skin = Color(0.45, 0.45, 0.45)
	var o := face.position
	var helmet := Color(0.35, 0.37, 0.22)
	draw_rect(Rect2(o + Vector2(7, 2), Vector2(20, 5)), helmet)        # casco M1
	draw_rect(Rect2(o + Vector2(5, 6), Vector2(24, 3)), helmet)
	draw_rect(Rect2(o + Vector2(10, 9), Vector2(14, 14)), skin)        # cara
	draw_rect(Rect2(o + Vector2(12, 12), Vector2(3, 2)), Color(0.1, 0.08, 0.06))  # ojos
	draw_rect(Rect2(o + Vector2(19, 12), Vector2(3, 2)), Color(0.1, 0.08, 0.06))
	draw_rect(Rect2(o + Vector2(14, 18), Vector2(6, 1)), skin.darkened(0.4))      # boca
	draw_rect(Rect2(o + Vector2(9, 9), Vector2(1, 12)), Color(0.25, 0.2, 0.12))    # barboquejo
	draw_rect(Rect2(o + Vector2(24, 9), Vector2(1, 12)), Color(0.25, 0.2, 0.12))
	draw_rect(Rect2(o + Vector2(6, 23), Vector2(22, 3)), Color(0.36, 0.35, 0.22))  # uniforme
	# Barra de vida segmentada
	var segs := 10
	var bw := (r.size.x - 10) / segs
	for i in segs:
		var filled := float(i) < hp * segs
		var col := Color(0.25, 0.85, 0.25) if hp > 0.35 else Color(0.95, 0.3, 0.15)
		draw_rect(Rect2(r.position + Vector2(5 + i * bw, r.size.y - 6), Vector2(bw - 1, 3)),
			col if filled else Color(0.12, 0.16, 0.1))
	if _player.crouching:
		_text("v", r.position + Vector2(r.size.x - 9, 20), 8, C_ORANGE)


func _draw_status(r: Rect2) -> void:
	_panel(r)
	# Clima
	draw_rect(Rect2(r.position + Vector2(6, 5), Vector2(10, 4)), Color(0.6, 0.62, 0.6))
	draw_rect(Rect2(r.position + Vector2(4, 8), Vector2(14, 3)), Color(0.5, 0.52, 0.5))
	_text("NIEBLA", r.position + Vector2(22, 11), 8, C_TEXT)
	# Hora
	var clock := Rect2(r.position + Vector2(4, 14), Vector2(r.size.x - 8, 15))
	_inner(clock)
	_text_c(Game.clock_text(), clock.position + Vector2(clock.size.x / 2, 13), 14, C_TEXT)
	# Brújula (norte = el mar, como en la playa de Omaha)
	var comp := Rect2(r.position + Vector2(4, 31), Vector2(r.size.x - 8, 12))
	_inner(comp)
	var fwd := -_player.global_basis.z
	var bearing := fmod(rad_to_deg(atan2(-fwd.x, fwd.z)) + 360.0, 360.0)
	var names := ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
	var mid := comp.position.x + comp.size.x / 2
	for i in 16:
		var deg := i * 22.5
		var diff := wrapf(deg - bearing, -180.0, 180.0)
		if absf(diff) > 55.0:
			continue
		var px := mid + diff / 55.0 * (comp.size.x / 2 - 6)
		if i % 2 == 0:
			_text_c(names[i / 2], Vector2(px, comp.position.y + 10), 7, C_TEXT)
		else:
			draw_line(Vector2(px, comp.position.y + 7), Vector2(px, comp.position.y + 10), C_DIM, 1.0)
	draw_line(Vector2(mid, comp.position.y), Vector2(mid, comp.position.y + 3), C_ORANGE, 1.0)


func _draw_grenades(r: Rect2) -> void:
	_panel(r)
	var n := _player.grenades
	_text(str(n), r.position + Vector2(8, 30), 20, C_ORANGE if n > 0 else C_DIM)
	# Icono de granada Mk 2
	var o := r.position + Vector2(34, 12)
	var olive := Color(0.32, 0.38, 0.2) if n > 0 else Color(0.2, 0.24, 0.16)
	draw_rect(Rect2(o + Vector2(2, 6), Vector2(14, 18)), olive)
	draw_rect(Rect2(o + Vector2(0, 9), Vector2(18, 12)), olive)
	for yy in [9, 14, 19]:
		draw_line(o + Vector2(1, yy), o + Vector2(17, yy), olive.darkened(0.4), 1.0)
	draw_rect(Rect2(o + Vector2(6, 2), Vector2(6, 4)), Color(0.5, 0.5, 0.48))
	draw_rect(Rect2(o + Vector2(12, 3), Vector2(3, 12)), Color(0.5, 0.5, 0.48))
	if n > 0:
		draw_line(r.position + Vector2(6, r.size.y - 4), r.position + Vector2(26, r.size.y - 4), C_ORANGE, 2.0)


func _draw_ammo(r: Rect2) -> void:
	_panel(r)
	var w := _player.weapons
	var mag := w.ammo[w.current]
	var res := w.reserve[w.current]
	var col := C_ORANGE if mag > 0 else Color(1, 0.3, 0.2)
	_text(str(mag), r.position + Vector2(8, 32), 22, col)
	_text("|", r.position + Vector2(38, 31), 18, C_ORANGE)
	_text(str(res), r.position + Vector2(48, 32), 22, C_ORANGE if res > 0 else C_DIM)
	if w.is_reloading() and int(Time.get_ticks_msec() / 250) % 2 == 0:
		_text("RECARGANDO", r.position + Vector2(6, r.size.y - 3), 7, C_TEXT)
	elif w.current == 0 and mag > 0:
		# Balas del clip del Garand
		for i in mag:
			draw_rect(Rect2(r.position + Vector2(8 + i * 5, r.size.y - 7), Vector2(3, 5)), Color(0.85, 0.7, 0.3))


func _draw_slots(r: Rect2) -> void:
	var w := _player.weapons
	_slot_rects.clear()
	var sw := (r.size.x - 3) / 2.0
	for i in 2:
		var sr := Rect2(r.position + Vector2(i * (sw + 3), 0), Vector2(sw, r.size.y))
		_slot_rects.append(sr)
		_panel(sr)
		var inner := sr.grow(-3)
		_inner(inner)
		var selected := i == w.current
		_text(str(i + 1), inner.position + Vector2(3, 9), 8, C_ORANGE if selected else C_DIM)
		var o := inner.position + Vector2(inner.size.x / 2, inner.size.y / 2 + 2)
		var wood := Color(0.6, 0.35, 0.18) if selected else Color(0.32, 0.22, 0.15)
		var metal := Color(0.55, 0.55, 0.58) if selected else Color(0.3, 0.3, 0.32)
		if i == 0:  # silueta del Garand
			draw_rect(Rect2(o + Vector2(-36, -2), Vector2(56, 4)), wood)
			draw_rect(Rect2(o + Vector2(14, -3), Vector2(24, 3)), metal)
			draw_rect(Rect2(o + Vector2(-38, -1), Vector2(18, 7)), wood)
			draw_rect(Rect2(o + Vector2(-14, -4), Vector2(14, 3)), metal)
		else:       # silueta del Colt
			draw_rect(Rect2(o + Vector2(-12, -5), Vector2(24, 5)), metal)
			draw_rect(Rect2(o + Vector2(-12, 0), Vector2(7, 10)), wood)
		if selected:
			draw_line(inner.position + Vector2(4, inner.size.y - 2),
				inner.position + Vector2(inner.size.x - 4, inner.size.y - 2), C_ORANGE, 2.0)
