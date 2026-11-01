extends Control
## Controles táctiles para el celular (en PC se ocultan solos).
## - Mitad izquierda: joystick para caminar (aparece donde pones el dedo).
##   Empujarlo a fondo hacia adelante = correr (el aro se pone naranjo).
## - Mitad derecha: deslizar el dedo para mirar.
## - Botones a la derecha: FUEGO (puedes arrastrar el dedo desde él para
##   seguir apuntando), MIRA (activa/desactiva), RECARGA, GRANADA,
##   SALTAR y AGACHAR.
## - Tocar las armas 1 / 2 de la barra inferior cambia de arma.
## - Botón de arriba al centro: cambia entre modo "2 DEDOS" y modo "GARRA".
##   GARRA agrega un segundo FUEGO arriba a la izquierda para el índice
##   izquierdo, así el pulgar derecho queda libre para apuntar.
##   La elección queda guardada en el celular.

@export var player_path: NodePath
@export var stick_radius := 40.0

const HUD_H := 52
const SETTINGS_PATH := "user://ajustes.cfg"

var claw := false           # modo GARRA activado

var _player: Player
var _hud: Node
var _fingers := {}          # índice del dedo -> {"role": ..., "last": Vector2, "origin": Vector2}
var _move_pos := Vector2.ZERO
var _move_origin := Vector2.ZERO
var _pressed := {}          # botón -> true mientras se mantiene presionado
var _font: Font


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	visible = DisplayServer.is_touchscreen_available()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		claw = cfg.get_value("controles", "garra", false)


func _toggle_layout() -> void:
	claw = not claw
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("controles", "garra", claw)
	cfg.save(SETTINGS_PATH)
	Game.say("[CONTROLES: %s]" % ("GARRA" if claw else "2 DEDOS"))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## [nombre, texto, centro, radio]
func _buttons() -> Array:
	var w := size.x
	var b := size.y - HUD_H
	var list := [
		["fire", "FUEGO", Vector2(w - 62, b - 58), 28.0],
		["aim", "MIRA", Vector2(w - 128, b - 26), 17.0],
		["reload", "RECARGA", Vector2(w - 26, b - 112), 16.0],
		["grenade", "GRANADA", Vector2(w - 82, b - 118), 16.0],
		["jump", "SALTAR", Vector2(w - 24, b - 22), 15.0],
		["crouch", "AGACHAR", Vector2(w - 180, b - 20), 15.0],
		["layout", "MODO: " + ("GARRA" if claw else "2 DEDOS"), Vector2(w / 2.0, 14), 12.0],
	]
	if claw:
		list.append(["fire_left", "FUEGO", Vector2(58, 64), 30.0])
	return list


func _button_at(pos: Vector2) -> String:
	for btn in _buttons():
		if btn[0] == "layout":
			if _pill(btn).grow(4).has_point(pos):
				return btn[0]
		elif pos.distance_to(btn[2]) <= btn[3] + 4.0:
			return btn[0]
	return ""


func _pill(btn: Array) -> Rect2:
	var c: Vector2 = btn[2]
	return Rect2(c - Vector2(40, 9), Vector2(80, 18))


func _input(event: InputEvent) -> void:
	if not visible or _player == null:
		return
	if _hud == null:
		_hud = get_tree().get_first_node_in_group("hud")

	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			_touch_down(event.index, pos)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		var f: Dictionary = _fingers[event.index]
		match f["role"]:
			"move":
				_move_pos = event.position
				var offset := (_move_pos - _move_origin).limit_length(stick_radius)
				_player.touch_move = offset / stick_radius
				_player.touch_sprint = offset.length() >= stick_radius * 0.95 and offset.y < -stick_radius * 0.7
			"look", "fire":
				_player.look_touch(event.position - f["last"])
		f["last"] = event.position


func _touch_down(index: int, pos: Vector2) -> void:
	var btn := _button_at(pos)
	if btn != "":
		_pressed[btn] = true
		_fingers[index] = {"role": "fire" if btn == "fire" else "button", "last": pos, "btn": btn}
		match btn:
			"fire", "fire_left": _player.weapons.pull_trigger()
			"layout": _toggle_layout()
			"aim": _player.touch_aim = not _player.touch_aim
			"reload": _player.weapons.reload()
			"grenade": _player.throw_grenade()
			"jump": _player.touch_jump = true
			"crouch": _player.toggle_crouch()
		return
	if pos.y > size.y - HUD_H:
		if _hud:
			var slot: int = _hud.slot_at(pos)
			if slot >= 0:
				_player.weapons.select(slot)
		return
	if pos.x < size.x * 0.5:
		if not _has_role("move"):
			_fingers[index] = {"role": "move", "last": pos}
			_move_origin = pos
			_move_pos = pos
	elif not _has_role("look"):
		_fingers[index] = {"role": "look", "last": pos}


func _touch_up(index: int) -> void:
	if not _fingers.has(index):
		return
	var f: Dictionary = _fingers[index]
	if f["role"] == "move":
		_player.touch_move = Vector2.ZERO
		_player.touch_sprint = false
	if f.has("btn"):
		_pressed.erase(f["btn"])
	_fingers.erase(index)


func _has_role(role: String) -> bool:
	for f in _fingers.values():
		if f["role"] == role:
			return true
	return false


func _draw() -> void:
	# Joystick
	if _has_role("move"):
		var knob := _move_origin + (_move_pos - _move_origin).limit_length(stick_radius)
		var ring := Color(1, 0.65, 0.15, 0.7) if _player.touch_sprint else Color(1, 1, 1, 0.4)
		draw_circle(_move_origin, stick_radius, Color(1, 1, 1, 0.12))
		draw_arc(_move_origin, stick_radius, 0, TAU, 24, ring, 1.0)
		draw_circle(knob, stick_radius * 0.4, Color(1, 1, 1, 0.4))
	# Botones
	for btn in _buttons():
		var name: String = btn[0]
		var c: Vector2 = btn[2]
		var r: float = btn[3]
		var active: bool = _pressed.has(name) or (name == "aim" and _player.touch_aim) \
			or (name == "crouch" and _player.crouching)
		var fill := Color(0.98, 0.66, 0.16, 0.45) if active else Color(0.1, 0.13, 0.08, 0.45)
		var fs := 10 if r > 20 else 8
		if name == "layout":
			var pr := _pill(btn)
			draw_rect(pr, fill)
			draw_rect(pr, Color(0.84, 0.9, 0.74, 0.6), false, 1.0)
			fs = 8
		else:
			draw_circle(c, r, fill)
			draw_arc(c, r, 0, TAU, 20, Color(0.84, 0.9, 0.74, 0.6), 1.0)
		var label: String = btn[1]
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := c + Vector2(-tw / 2.0, fs * 0.35)
		draw_string_outline(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 1, Color.BLACK)
		draw_string(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.95, 0.85))
