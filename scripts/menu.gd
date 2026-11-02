extends PanelBotones
## Menú principal: fondo de la playa (ChatGPT), título y botones.
## Pantallas: "inicio", "controles" y "creditos".

const FONDO := preload("res://assets/ui/fondo_menu.png")
const X := 28.0              # margen izquierdo de la columna de botones
const ANCHO := 200.0
const ALTO := 26.0

var pantalla := "inicio"
var _tactil := DisplayServer.is_touchscreen_available()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _botones() -> Array:
	var y0 := 132.0
	var paso := ALTO + 8.0
	match pantalla:
		"inicio":
			return [
				["jugar", Rect2(X, y0, ANCHO, ALTO), "UN JUGADOR", true, ""],
				["coop", Rect2(X, y0 + paso, ANCHO, ALTO), "COOPERATIVO", false, "PRONTO"],
				["controles", Rect2(X, y0 + paso * 2, ANCHO, ALTO), "CONTROLES", true, ""],
				["creditos", Rect2(X, y0 + paso * 3, ANCHO, ALTO), "CRÉDITOS", true, ""],
				["carga", Rect2(X, y0 + paso * 4, ANCHO, ALTO), "PRUEBA DE CARGA", true, ""],
			]
		"controles":
			var lista := [["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""]]
			if _tactil:
				lista.append(["garra", Rect2(X, 96, 220, ALTO), "MODO TÁCTIL", true,
					"GARRA" if Game.garra else "2 DEDOS"])
				lista.append(["disparo", Rect2(X + 230, 96, 220, ALTO), "DISPARO", true,
					"AL SOLTAR" if Game.disparo_soltar else "AL TOCAR"])
			return lista
		_:
			return [["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""]]


func _pulsado(id: String) -> void:
	match id:
		"carga":
			Game.prueba_carga = true
			Game.empezar_mision()
		"jugar":
			Game.prueba_carga = false
			Game.empezar_mision()
		"controles", "creditos":
			pantalla = id
		"volver":
			pantalla = "inicio"
		"garra":
			Game.cambiar_garra()
		"disparo":
			Game.cambiar_disparo()


func _draw() -> void:
	var s := size
	# Fondo cubriendo toda la pantalla (si es más ancha que 16:9, se recorta arriba/abajo)
	var esc := maxf(s.x / FONDO.get_width(), s.y / FONDO.get_height())
	var tam := Vector2(FONDO.get_width(), FONDO.get_height()) * esc
	draw_texture_rect(FONDO, Rect2((s - tam) / 2.0, tam), false)
	# Sombra a la izquierda para que se lea el texto
	for i in 24:
		var a := 0.72 * (1.0 - i / 24.0)
		draw_rect(Rect2(i * 14.0, 0, 14.0, s.y), Color(Estilo.NEGRO, a))

	match pantalla:
		"inicio":
			_titulo()
		"controles":
			_controles()
		"creditos":
			_creditos()
	_dibujar_botones()
	Estilo.texto(self, "V%s" % ProjectSettings.get_setting("application/config/version"),
		Vector2(s.x - 44, s.y - 8), Color(Estilo.CREMA, 0.4))


func _titulo() -> void:
	Estilo.texto(self, "NORMANDY", Vector2(X, 66), Estilo.CREMA, 44)
	Estilo.texto(self, "1944", Vector2(X + 2, 104), Estilo.AMBAR, 33)
	Estilo.texto(self, "6 DE JUNIO DE 1944 - PLAYA OMAHA", Vector2(X + 2, 120), Color(Estilo.CREMA, 0.8))


func _encabezado(t: String) -> void:
	Estilo.texto(self, t, Vector2(X, 46), Estilo.AMBAR, Estilo.TAM_GRANDE)


func _controles() -> void:
	_encabezado("CONTROLES")
	if _tactil:
		var lineas := [
			"MITAD IZQUIERDA: CAMINAR (A FONDO = CORRER)",
			"MITAD DERECHA: MIRAR",
			"FUEGO: DISPARAR (ARRASTRA PARA SEGUIR MIRANDO)",
			"MIRA, RECARGA, GRANADA, SALTAR, AGACHAR",
			"TOCA EL ARMA 1 O 2 DE LA BARRA PARA CAMBIAR",
			"GARRA: AGREGA OTRO FUEGO ARRIBA A LA IZQUIERDA",
			"AL SOLTAR: MANTÉN FUEGO PARA APUNTAR, SUELTA PARA DISPARAR",
			"BOTONES DE LA BARRA, A LA IZQUIERDA: ÓRDENES",
			"A LA ESCUADRA (SÍGANME, AVANCEN, ALTO)",
		]
		for i in lineas.size():
			Estilo.texto(self, lineas[i], Vector2(X, 140 + i * 15), Estilo.CREMA)
	else:
		var teclas := [
			["W A S D", "CAMINAR"], ["SHIFT", "CORRER"], ["MOUSE", "MIRAR"],
			["CLIC IZQUIERDO", "DISPARAR"], ["CLIC DERECHO", "MIRAR POR LA MIRA"],
			["R", "RECARGAR"], ["G", "GRANADA"], ["ESPACIO", "SALTAR"],
			["C / CTRL", "AGACHARSE"], ["E", "RECOGER ARMA"], ["1 / 2 / Q", "CAMBIAR DE ARMA"],
			["Z / X / V", "ESCUADRA: SÍGANME / AVANCEN / ALTO"],
			["ESC", "PAUSA"],
		]
		for i in teclas.size():
			var y := 76.0 + i * 15.0
			Estilo.texto(self, teclas[i][0], Vector2(X, y), Estilo.AMBAR_CLARO)
			Estilo.texto(self, teclas[i][1], Vector2(X + 120, y), Estilo.CREMA)


func _creditos() -> void:
	_encabezado("CRÉDITOS")
	var lineas := [
		["UN JUEGO DE", "TOMÁS ROJAS"],
		["PROGRAMACIÓN", "CLAUDE (ANTHROPIC)"],
		["IMÁGENES", "CREADAS CON CHATGPT (OPENAI)"],
		["MODELOS 3D", "CREADOS CON MESHY AI (MESHY.AI)"],
		["", "LICENCIA CC BY 4.0"],
		["ANIMACIONES", "MIXAMO (ADOBE)"],
		["MOTOR", "GODOT ENGINE - LICENCIA MIT"],
		["", "(C) JUAN LINIETSKY, ARIEL MANZUR"],
		["", "Y COLABORADORES DE GODOT ENGINE"],
	]
	for i in lineas.size():
		var y := 80.0 + i * 15.0
		Estilo.texto(self, lineas[i][0], Vector2(X, y), Estilo.AMBAR_CLARO)
		Estilo.texto(self, lineas[i][1], Vector2(X + 110, y), Estilo.CREMA)
