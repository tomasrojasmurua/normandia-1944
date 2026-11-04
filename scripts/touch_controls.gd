extends Control
## Controles táctiles para el celular (en PC se ocultan solos).
## - Mitad izquierda: joystick para caminar (aparece donde pones el dedo).
##   Empujarlo a fondo hacia adelante = correr (el aro se pone naranjo).
## - Mitad derecha: deslizar el dedo para mirar.
## - Botones a la derecha: FUEGO (puedes arrastrar el dedo desde él para
##   seguir apuntando), MIRA (activa/desactiva), RECARGA, GRANADA,
##   SALTAR y AGACHAR (los chicos se ven con ícono:
##   balas = recarga, granada, flecha arriba = saltar, flecha abajo = agachar).
## - Tocar las armas 1 / 2 de la barra inferior cambia de arma.
## - Modo "GARRA" (se elige en el menú o en la pausa, Game.garra): agrega un
##   segundo FUEGO arriba a la izquierda para el índice izquierdo, así el
##   pulgar derecho queda libre para apuntar.
## - Disparo "AL SOLTAR" (Game.disparo_soltar, se elige en el menú o la pausa):
##   mantener FUEGO sube el arma a la mira (puedes seguir arrastrando para
##   apuntar) y al soltar sale el tiro. Con armas automáticas, mantener FUEGO
##   sube la mira y dispara en ráfaga mientras sigas presionando.

@export var player_path: NodePath
@export var stick_radius := 40.0

const HUD_H := 52
const _BOTON_G := preload("res://assets/ui/boton_g.png")
const _BOTON_G_ON := preload("res://assets/ui/boton_g_on.png")
const _BOTON_M := preload("res://assets/ui/boton_m.png")
const _BOTON_M_ON := preload("res://assets/ui/boton_m_on.png")
const _BOTON_C := preload("res://assets/ui/boton_c.png")
const _BOTON_C_ON := preload("res://assets/ui/boton_c_on.png")

var _player: Player
var _hud: Node
var _fingers := {}          # índice del dedo -> {"role": ..., "last": Vector2, "origin": Vector2}
var _move_pos := Vector2.ZERO
var _move_origin := Vector2.ZERO
var _pressed := {}          # botón -> true mientras se mantiene presionado


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	visible = DisplayServer.is_touchscreen_available()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Se redibuja solo si cambió algo de lo que se ve (dedos, botones apretados,
## el botón TOMAR): antes se redibujaba en cada cuadro.
var _firma: Array = []


func _process(_delta: float) -> void:
	if not visible or _player == null:
		return
	var f: Array = [size, _has_role("move"), _move_origin, _move_pos, _player.touch_sprint, _player.touch_aim,
		_player.crouching, _player.pickup_near != null, Game.garra, _pressed.keys()]
	if f != _firma:
		_firma = f
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
	]
	if _player and _player.pickup_near != null:
		list.append(["use", "TOMAR", Vector2(w - 150, b - 82), 17.0])
	if Game.garra:
		list.append(["fire_left", "FUEGO", Vector2(58, 64), 30.0])
	return list


func _button_at(pos: Vector2) -> String:
	for btn in _buttons():
		if pos.distance_to(btn[2]) <= btn[3] + 4.0:
			return btn[0]
	return ""


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
			"fire", "fire_left":
				_player.touch_fire = true
				if Game.disparo_soltar:
					_player.touch_hold_aim = true
				else:
					_player.weapons.pull_trigger()
			"use": _player.recoger()
			"aim": _player.touch_aim = not _player.touch_aim
			"reload": _player.weapons.reload()
			"grenade": _player.throw_grenade()
			"jump": _player.touch_jump = true
			"crouch":
				_player.crouch_press()
				_player.touch_crouch_held = true
		return
	if pos.y > size.y - HUD_H:
		if _hud:
			var slot: int = _hud.slot_at(pos)
			if slot >= 0:
				_player.weapons.select(slot)
			var orden: String = _hud.orden_at(pos)
			if orden != "":
				Aliado.dar_orden(orden)
			elif _hud.apoyo_at(pos):
				Escuadras.pedir_artilleria()
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
		if f["btn"] == "crouch":
			_player.touch_crouch_held = false
		if f["btn"] in ["fire", "fire_left"] and not _pressed.has("fire") and not _pressed.has("fire_left"):
			_player.touch_fire = false
			if _player.touch_hold_aim:
				_player.touch_hold_aim = false
				# Al soltar: un tiro (las automáticas ya dispararon mientras se mantenía)
				if not _player.weapons.def().get("auto", false):
					_player.weapons.pull_trigger()
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
	# Botones (discos de chapa; los chicos llevan ícono en vez de texto)
	for btn in _buttons():
		var name: String = btn[0]
		var c: Vector2 = (btn[2] as Vector2).round()
		var r: float = btn[3]
		var active: bool = _pressed.has(name) or (name == "aim" and _player.touch_aim) \
			or (name == "crouch" and _player.crouching)
		var label: String = btn[1]
		var tex: Texture2D = _BOTON_G_ON if active else _BOTON_G
		if r < 16.5:
			tex = _BOTON_C_ON if active else _BOTON_C
		elif r < 25.0:
			tex = _BOTON_M_ON if active else _BOTON_M
		var d := roundf(r * 2.0 + 2.0)
		draw_texture_rect(tex, Rect2(c - Vector2(d, d) / 2.0, Vector2(d, d)), false)
		var tinte := Color(1, 1, 1, 0.9)
		match name:
			"reload":
				for k in 3:
					draw_texture(Estilo.ICONO_BALA, c + Vector2(-6 + k * 4, -4), tinte)
			"grenade":
				Estilo.icono(self, Estilo.ICONO_GRANADA, c, tinte)
			"crouch":
				Estilo.icono(self, Estilo.ICONO_AGACHADO, c + Vector2(0, 1), tinte)
			"jump":
				draw_set_transform(c, PI, Vector2.ONE)
				Estilo.icono(self, Estilo.ICONO_AGACHADO, Vector2(0, 1), tinte)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_:
				Estilo.texto_c(self, label, c.x, c.y + 4, Estilo.CREMA)
