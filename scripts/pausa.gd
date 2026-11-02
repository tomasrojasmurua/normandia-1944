extends PanelBotones
## Pausa durante la misión: Esc en PC, botón "II" arriba a la derecha en el
## celular. Detiene el juego y ofrece continuar, cambiar el modo táctil o
## volver al menú principal.

var _tactil := DisplayServer.is_touchscreen_available()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func pausar(si: bool) -> void:
	get_tree().paused = si
	if si:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not _tactil:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_encima = ""


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not Game.warming:
		pausar(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	super(event)


func _botones() -> Array:
	if Game.warming:
		return []
	var s := size
	if not get_tree().paused:
		return [["pausa", Rect2(s.x - 34, 6, 28, 22), "II", _tactil, ""]] if _tactil else []
	var x := s.x / 2.0 - 110.0
	var lista := [["seguir", Rect2(x, 140, 220, 26), "CONTINUAR", true, ""]]
	if _tactil:
		lista.append(["garra", Rect2(x, 174, 220, 26), "MODO TÁCTIL", true, "GARRA" if Game.garra else "2 DEDOS"])
		lista.append(["disparo", Rect2(x, 208, 220, 26), "DISPARO", true, "AL SOLTAR" if Game.disparo_soltar else "AL TOCAR"])
	var y := 242.0 if _tactil else 174.0
	lista.append(["soldados", Rect2(x, y, 220, 26), "SOLDADOS", true, "3D" if Game.soldados_3d else "SPRITES"])
	lista.append(["menu", Rect2(x, y + 34, 220, 26), "SALIR AL MENÚ", true, ""])
	return lista


func _pulsado(id: String) -> void:
	match id:
		"pausa":
			pausar(true)
		"seguir":
			pausar(false)
		"garra":
			Game.cambiar_garra()
		"disparo":
			Game.cambiar_disparo()
		"soldados":   # se nota al recargar la playa
			Game.cambiar_soldados()
			Game.empezar_mision()
		"menu":
			Game.ir_al_menu()


func _draw() -> void:
	if get_tree().paused:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Estilo.NEGRO, 0.6))
		var panel := Rect2(size.x / 2.0 - 130, 90, 260, 228 if _tactil else 160)
		Estilo.marco(self, panel, "chapa")
		Estilo.texto_c(self, "PAUSA", size.x / 2.0, 124, Estilo.AMBAR, Estilo.TAM_GRANDE)
	_dibujar_botones()
