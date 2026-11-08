extends PanelBotones
class_name VersusFin
## Fin de una partida de VERSUS: quién ganó, refuerzos que quedaron y caídos
## de cada bando. El anfitrión puede pedir la REVANCHA (el mismo mapa) u OTRO
## MAPA; los invitados siguen al anfitrión. Cualquiera puede volver al menú.
## La partida no se pausa (la red sigue).


static func mostrar(arbol: SceneTree) -> void:
	var escena := arbol.current_scene
	if escena == null or escena.get_node_or_null("VersusFin"):
		return
	var capa := CanvasLayer.new()
	capa.name = "VersusFin"
	capa.layer = 30
	capa.process_mode = Node.PROCESS_MODE_ALWAYS
	capa.add_child(VersusFin.new())
	escena.add_child(capa)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.play("click", 0.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _botones() -> Array:
	var c := size / 2.0
	if Red.es_anfitrion():
		return [
			["menu", Rect2(c.x - 160, c.y + 76, 100, 26), "MENÚ", true, ""],
			["revancha", Rect2(c.x - 50, c.y + 76, 100, 26), "REVANCHA", true, ""],
			["otro", Rect2(c.x + 60, c.y + 76, 100, 26), "OTRO MAPA", true, ""],
		]
	return [["menu", Rect2(c.x - 50, c.y + 76, 100, 26), "MENÚ", true, ""]]


func _pulsado(id: String) -> void:
	match id:
		"menu":
			Game.ir_al_menu()
		"revancha":
			Red.revancha(Game.mision)
		"otro":
			var l: Array = Red.MISIONES_VS
			Red.revancha(l[(l.find(Game.mision) + 1) % l.size()])


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Estilo.NEGRO, 0.72))
	var c := size / 2.0
	var panel := Rect2(c.x - 180, c.y - 100, 360, 212)
	Estilo.marco(self, panel, "chapa")
	var g := Versus.ganador
	var mio := Versus.mi_bando()
	var titulo := "EMPATE"
	var col := Estilo.AMBAR
	if g == Versus.US or g == Versus.DE:
		titulo = "¡VICTORIA!" if g == mio else "DERROTA"
		col = Estilo.VERDE_LED if g == mio else Estilo.ROJO
	Estilo.texto_c(self, titulo, c.x, c.y - 66, col, Estilo.TAM_GRANDE)
	var sub := "GANA %s" % Versus.NOMBRES_BANDO[g] if g == Versus.US or g == Versus.DE else "LOS DOS BANDOS IGUALADOS"
	Estilo.texto_c(self, "%s - %s" % [sub, Misiones.dato("nombre")], c.x, c.y - 46, Color(Estilo.CREMA, 0.8))
	var x := panel.position.x + 40
	var y := c.y - 18
	Estilo.texto(self, "", Vector2(x, y), Estilo.CREMA)
	Estilo.texto(self, "REFUERZOS", Vector2(x + 130, y), Estilo.AMBAR_CLARO)
	Estilo.texto(self, "CAÍDOS", Vector2(x + 220, y), Estilo.AMBAR_CLARO)
	for b in 2:
		var yy := y + 18 + b * 16
		var cb := Estilo.AMBAR if b == mio else Estilo.CREMA
		Estilo.texto(self, Versus.NOMBRES_BANDO[b] + (" (TÚ)" if b == mio else ""), Vector2(x, yy), cb)
		Estilo.texto(self, str(Versus.tickets[b]), Vector2(x + 130, yy), cb)
		Estilo.texto(self, str(Versus.bajas_de[b]), Vector2(x + 220, yy), cb)
	var t := int(Versus.tiempo)
	Estilo.texto(self, "DURACIÓN: %d:%02d" % [t / 60, t % 60], Vector2(x, y + 60), Color(Estilo.CREMA, 0.7))
	if not Red.es_anfitrion():
		Estilo.texto_c(self, "EL ANFITRIÓN PUEDE PEDIR LA REVANCHA...", c.x, c.y + 66, Estilo.AMBAR_CLARO)
	_dibujar_botones()
