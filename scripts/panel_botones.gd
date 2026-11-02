extends Control
class_name PanelBotones
## Base para pantallas con botones dibujados (menú principal, pausa):
## funciona igual con mouse (PC) y con el dedo (celular).
## Las pantallas hijas definen:
##   _botones() -> Array de [id, Rect2, texto, activo (bool), nota (texto chico)]
##   _pulsado(id)  qué hacer al tocar un botón

var _encima := ""     # botón bajo el mouse


func _botones() -> Array:
	return []


func _pulsado(_id: String) -> void:
	pass


func _boton_en(pos: Vector2) -> Array:
	for b in _botones():
		if (b[1] as Rect2).grow(3).has_point(pos):
			return b
	return []


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var pos := Vector2.ZERO
	var toque := false
	if event is InputEventMouseMotion:
		var b := _boton_en(event.position)
		var nuevo: String = b[0] if not b.is_empty() and b[3] else ""
		if nuevo != _encima:
			_encima = nuevo
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		toque = true
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
		toque = true
	if not toque:
		return
	var b := _boton_en(pos)
	if b.is_empty() or not b[3]:
		return
	get_viewport().set_input_as_handled()
	Game.play("click", -6.0)
	_pulsado(b[0])
	queue_redraw()


func _dibujar_botones() -> void:
	for b in _botones():
		var estado := "normal"
		if not b[3]:
			estado = "apagado"
		elif b[0] == _encima:
			estado = "encima"
		Estilo.boton(self, b[1], b[2], estado, b[4] if b.size() > 4 else "")
