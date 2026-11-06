extends PanelBotones
## Pausa durante la misión: Esc en PC, botón "II" arriba a la derecha en el
## celular. Detiene el juego y ofrece continuar, cambiar el modo táctil o
## volver al menú principal. En el cooperativo NO detiene el juego (los demás
## siguen jugando): solo abre el menú. Se esconde con la pantalla de fin.

var _tactil := DisplayServer.is_touchscreen_available()
var abierta := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


var _firma: Array = []


## Solo se redibuja si cambió algo (abierta/cerrada, tamaño, ajustes).
func _process(_delta: float) -> void:
	var f: Array = [abierta, size, Game.warming, Objetivos.terminado, Game.esquema, Game.disparo_soltar,
		Game.soldados_3d, Game.datos_tecnicos, _encima]
	if f != _firma:
		_firma = f
		queue_redraw()


func pausar(si: bool) -> void:
	abierta = si
	if not Game.modo_red:
		get_tree().paused = si
	if si:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not _tactil:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_encima = ""


func _input(event: InputEvent) -> void:
	if Objetivos.terminado != 0:
		return
	if event.is_action_pressed("ui_cancel") and not Game.warming:
		pausar(not abierta)
		get_viewport().set_input_as_handled()
		return
	super(event)


func _botones() -> Array:
	if Game.warming or Objetivos.terminado != 0:
		return []
	var s := size
	if not abierta:
		return [["pausa", Rect2(s.x - 34, 6, 28, 22), "II", _tactil, ""]] if _tactil else []
	var x := s.x / 2.0 - 110.0
	var y := Y0 + 34.0
	var lista := [["seguir", Rect2(x, Y0, 220, 26), "CONTINUAR", true, ""]]
	if _tactil:
		lista.append(["garra", Rect2(x, y, 220, 26), "BOTONES", true, TouchControls.ESQUEMAS[Game.esquema]])
		lista.append(["disparo", Rect2(x, y + 34, 220, 26), "DISPARO", true, "AL SOLTAR" if Game.disparo_soltar else "AL TOCAR"])
		y += 68.0
	lista.append(["soldados", Rect2(x, y, 220, 26), "SOLDADOS", true, "3D" if Game.soldados_3d else "SPRITES"])
	lista.append(["datos", Rect2(x, y + 34, 220, 26), "DATOS TÉCNICOS", true, "SÍ" if Game.datos_tecnicos else "NO"])
	lista.append(["menu", Rect2(x, y + 68, 220, 26), "SALIR AL MENÚ", true, ""])
	return lista


const Y0 := 112.0   # primer botón del panel


func _pulsado(id: String) -> void:
	match id:
		"pausa":
			pausar(true)
		"seguir":
			pausar(false)
		"garra":
			Game.cambiar_esquema()
		"disparo":
			Game.cambiar_disparo()
		"datos":     # FPS, ms y versión arriba a la izquierda
			Game.cambiar_datos_tecnicos()
		"soldados":   # se nota al recargar la playa
			Game.cambiar_soldados()
			Game.empezar_mision()
		"menu":
			Game.ir_al_menu()


func _draw() -> void:
	if abierta and Objetivos.terminado == 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Estilo.NEGRO, 0.6))
		var n := 6 if _tactil else 4     # botones
		var panel := Rect2(size.x / 2.0 - 130, Y0 - 46, 260, 58 + n * 34)
		Estilo.marco(self, panel, "chapa")
		Estilo.texto_c(self, "PAUSA", size.x / 2.0, Y0 - 14, Estilo.AMBAR, Estilo.TAM_GRANDE)
	_dibujar_botones()
