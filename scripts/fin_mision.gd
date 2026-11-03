extends PanelBotones
class_name FinMision
## Pantalla de fin de misión: CUMPLIDA (los 4 objetivos) o FRACASADA (sin
## nadie que releve a los jugadores). Muestra tiempo, bajas y objetivos.
## Jugando solo pausa el juego y deja reintentar; en el cooperativo la partida
## sigue de fondo (la red no se pausa) y solo se puede volver al menú.

var resultado := 1
var bajas := 0
var caidos := 0
var segundos := 0


static func mostrar(arbol: SceneTree, res: int, b: int, c: int, s: int) -> void:
	var escena := arbol.current_scene
	if escena == null or escena.get_node_or_null("FinMision"):
		return
	var capa := CanvasLayer.new()
	capa.name = "FinMision"
	capa.layer = 30
	capa.process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FinMision.new()
	f.resultado = res
	f.bajas = b
	f.caidos = c
	f.segundos = s
	capa.add_child(f)
	escena.add_child(capa)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.play("click", 0.0)
	if not Game.modo_red:
		arbol.paused = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _botones() -> Array:
	var c := size / 2.0
	var l := [["menu", Rect2(c.x - 105, c.y + 92, 100, 26), "MENÚ", true, ""]]
	if not Game.modo_red:
		l.append(["otra", Rect2(c.x + 5, c.y + 92, 100, 26), "OTRA VEZ", true, ""])
	else:
		l[0][1] = Rect2(c.x - 50, c.y + 92, 100, 26)
	return l


func _pulsado(id: String) -> void:
	match id:
		"menu":
			Game.ir_al_menu()
		"otra":
			Game.empezar_mision()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Estilo.NEGRO, 0.72))
	var c := size / 2.0
	var panel := Rect2(c.x - 170, c.y - 110, 340, 240)
	Estilo.marco(self, panel, "chapa")
	var titulo := "MISIÓN CUMPLIDA" if resultado > 0 else "MISIÓN FRACASADA"
	Estilo.texto_c(self, titulo, c.x, c.y - 78, Estilo.AMBAR if resultado > 0 else Estilo.ROJO, Estilo.TAM_GRANDE)
	Estilo.texto_c(self, "PLAYA OMAHA - 6 DE JUNIO DE 1944", c.x, c.y - 58, Color(Estilo.CREMA, 0.75))
	var y := c.y - 36
	for i in 4:
		var ok: bool = Objetivos.hecho[i]
		Estilo.texto(self, ("OK  " if ok else "--  ") + str(Objetivos.LISTA[i]["n"]), Vector2(c.x - 140, y),
			Estilo.VERDE_LED if ok else Color(Estilo.CREMA, 0.5))
		y += 14
	y += 8
	Estilo.texto(self, "TIEMPO: %d:%02d" % [segundos / 60, segundos % 60], Vector2(c.x - 140, y), Estilo.CREMA)
	Estilo.texto(self, "ALEMANES ABATIDOS: %d" % bajas, Vector2(c.x - 140, y + 14), Estilo.CREMA)
	Estilo.texto(self, "AMERICANOS CAÍDOS: %d" % caidos, Vector2(c.x - 140, y + 28), Estilo.CREMA)
	_dibujar_botones()
