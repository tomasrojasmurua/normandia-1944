extends Control
## Controles táctiles para el celular.
## - Mitad izquierda de la pantalla: joystick para caminar (aparece donde pones el dedo).
## - Mitad derecha: deslizar el dedo para mirar.
## - Botón "SALTAR" abajo a la derecha.
## En PC se ocultan solos.

@export var player_path: NodePath
@export var stick_radius := 40.0

var _player: Node
var _move_finger := -1
var _move_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _look_finger := -1
var _look_last := Vector2.ZERO

@onready var _jump_button: Button = $JumpButton


func _ready() -> void:
	_player = get_node_or_null(player_path)
	visible = DisplayServer.is_touchscreen_available()
	_jump_button.button_down.connect(func(): if _player: _player.touch_jump = true)


func _input(event: InputEvent) -> void:
	if not visible or _player == null:
		return

	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if _jump_button.get_global_rect().has_point(pos):
				return
			if pos.x < size.x * 0.5 and _move_finger == -1:
				_move_finger = event.index
				_move_origin = pos
				_move_pos = pos
			elif pos.x >= size.x * 0.5 and _look_finger == -1:
				_look_finger = event.index
				_look_last = pos
		else:
			if event.index == _move_finger:
				_move_finger = -1
				_player.touch_move = Vector2.ZERO
			elif event.index == _look_finger:
				_look_finger = -1
		queue_redraw()

	elif event is InputEventScreenDrag:
		if event.index == _move_finger:
			_move_pos = event.position
			var offset := (_move_pos - _move_origin).limit_length(stick_radius)
			_player.touch_move = offset / stick_radius
			queue_redraw()
		elif event.index == _look_finger:
			_player.look_touch(event.position - _look_last)
			_look_last = event.position


func _draw() -> void:
	if _move_finger == -1:
		return
	var knob := _move_origin + (_move_pos - _move_origin).limit_length(stick_radius)
	draw_circle(_move_origin, stick_radius, Color(1, 1, 1, 0.15))
	draw_arc(_move_origin, stick_radius, 0, TAU, 24, Color(1, 1, 1, 0.4), 1.0)
	draw_circle(knob, stick_radius * 0.4, Color(1, 1, 1, 0.45))
