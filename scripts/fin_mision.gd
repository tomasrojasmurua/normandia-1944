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
	Compania.cerrar_mision(res, Escuadras.reemplazos_vivos())
	Campana.cerrar_mision(res)
	CampanaRed.cambio()     # campaña cooperativa: el informe de la compañía, a los invitados


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


## Ancho del panel: más ancho si hay informe de la compañía (columna derecha).
func _ancho() -> float:
	return 470.0 if not Compania.informe.is_empty() else 340.0


func _botones() -> Array:
	var c := size / 2.0
	var l := [["menu", Rect2(c.x - 105, c.y + 92, 100, 26), "MENÚ", true, ""]]
	if not Game.modo_red or CampanaRed.anfitrion():   # campaña cooperativa: sigue el anfitrión
		l.append(["otra", Rect2(c.x + 5, c.y + 92, 100, 26), "CONTINUAR" if resultado > 0 else "OTRA VEZ", true, ""])
	else:
		l[0][1] = Rect2(c.x - 50, c.y + 92, 100, 26)
	return l


func _pulsado(id: String) -> void:
	match id:
		"menu":
			Game.ir_al_menu()
		"otra":
			if Game.mision_suelta:
				Game.empezar_mision(Game.mision, true)
			elif resultado > 0 and Compania.activa():
				Game.ir_al_mapa()
			else:
				Game.ir_a_previa()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Estilo.NEGRO, 0.72))
	var c := size / 2.0
	var w := _ancho()
	var panel := Rect2(c.x - w / 2.0, c.y - 110, w, 240)
	var x := panel.position.x + 30
	Estilo.marco(self, panel, "chapa")
	var titulo := "MISIÓN CUMPLIDA" if resultado > 0 else "MISIÓN FRACASADA"
	Estilo.texto_c(self, titulo, c.x, c.y - 78, Estilo.AMBAR if resultado > 0 else Estilo.ROJO, Estilo.TAM_GRANDE)
	Estilo.texto_c(self, "%s - %s" % [Misiones.dato("nombre"), Misiones.dato("fecha")], c.x, c.y - 58, Color(Estilo.CREMA, 0.75))
	var y := c.y - 36
	var fases := Misiones.fases()
	for f in fases.size():
		var hechos := 0
		var total := 0
		for i in Objetivos.LISTA.size():
			if Objetivos.LISTA[i]["fase"] == f:
				total += 1
				if Objetivos.hecho[i]:
					hechos += 1
		var ok := hechos == total
		Estilo.texto(self, "%s  FASE %d: %s  (%d/%d)" % ["OK" if ok else "--", f + 1, fases[f]["nombre"], hechos, total],
			Vector2(x, y), Estilo.VERDE_LED if ok else Color(Estilo.CREMA, 0.5))
		y += 14
	y += 8
	Estilo.texto(self, "TIEMPO: %d:%02d" % [segundos / 60, segundos % 60], Vector2(x, y), Estilo.CREMA)
	Estilo.texto(self, "ALEMANES ABATIDOS: %d" % bajas, Vector2(x, y + 14), Estilo.CREMA)
	Estilo.texto(self, "AMERICANOS CAÍDOS: %d" % caidos, Vector2(x, y + 28), Estilo.CREMA)
	# La compañía: quién murió, quién quedó herido, ascensos, reclutas
	if not Compania.informe.is_empty():
		var xi := panel.position.x + 250
		var yi := c.y - 36
		Estilo.texto(self, "LA COMPAÑÍA", Vector2(xi, yi), Estilo.AMBAR_CLARO)
		yi += 15
		var colores := {"mal": Estilo.ROJO, "aviso": Estilo.AMBAR, "bien": Estilo.VERDE_LED, "normal": Estilo.CREMA}
		for linea in Compania.informe.slice(0, 9):
			Estilo.texto(self, linea[0], Vector2(xi, yi), colores.get(linea[1], Estilo.CREMA), Estilo.TAM, panel.end.x - xi - 10)
			yi += 13
	if CampanaRed.espejo:
		Estilo.texto_c(self, "EL ANFITRIÓN DECIDE CÓMO SEGUIR...", c.x, c.y + 84, Estilo.AMBAR_CLARO)
	_dibujar_botones()
