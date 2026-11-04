extends PanelBotones
## Menú principal: fondo de la playa (ChatGPT), título y botones.
## Pantallas: "inicio", "controles" y "creditos".

const FONDO := preload("res://assets/ui/fondo_menu.png")
const X := 28.0              # margen izquierdo de la columna de botones
const ANCHO := 200.0
const ALTO := 26.0

var pantalla := "inicio"
var _confirmar := 0.0         # "NUEVA CAMPAÑA" pide un segundo toque si ya hay una
var _codigo := ""             # código de sala que se está escribiendo
var _tactil := DisplayServer.is_touchscreen_available()


const LOGO := preload("res://assets/ui/logo.png")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Red.actual:   # volvió de una partida cooperativa: se sale de la sala
		Red.actual.queue_free()
	Game.modo_red = false
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_confirmar = maxf(_confirmar - delta, 0.0)
	queue_redraw()
	# Esperando al servidor: al saber si eres el anfitrión, empieza la misión
	if pantalla == "conectando" and Red.actual and Red.actual.mi_id != "":
		Game.empezar_mision()


func _botones() -> Array:
	var y0 := 132.0
	var paso := ALTO + 8.0
	match pantalla:
		"inicio":
			# Un jugador: seguir la campaña guardada o empezar una nueva (con prólogo)
			var hay := _hay_campana()
			paso = ALTO + 6.0
			return [
				["seguir", Rect2(X, y0, ANCHO, ALTO), "CONTINUAR CAMPAÑA", hay, _resumen_campana() if hay else ""],
				["nueva", Rect2(X, y0 + paso, ANCHO, ALTO),
					"¿BORRAR LA ACTUAL?" if _confirmar > 0.0 else "NUEVA CAMPAÑA", true, ""],
				["coop", Rect2(X, y0 + paso * 2, ANCHO, ALTO), "COOPERATIVO", true, "PRUEBA"],
				["controles", Rect2(X, y0 + paso * 3, ANCHO, ALTO), "CONTROLES", true, ""],
				["creditos", Rect2(X, y0 + paso * 4, ANCHO, ALTO), "CRÉDITOS", true, ""],
				["carga", Rect2(X, y0 + paso * 5, ANCHO, ALTO), "PRUEBA DE CARGA", true, ""],
			]
		"controles":
			var lista := [["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""]]
			if _tactil:
				lista.append(["garra", Rect2(X, 96, 220, ALTO), "MODO TÁCTIL", true,
					"GARRA" if Game.garra else "2 DEDOS"])
				lista.append(["disparo", Rect2(X + 230, 96, 220, ALTO), "DISPARO", true,
					"AL SOLTAR" if Game.disparo_soltar else "AL TOCAR"])
			return lista
		"coop":
			return [
				["crear", Rect2(X, y0, ANCHO, ALTO), "CREAR SALA", true, ""],
				["unirse", Rect2(X, y0 + paso, ANCHO, ALTO), "UNIRSE A UNA SALA", true, ""],
				["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""],
			]
		"conectando":
			return [["salir_sala", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""]]
		"unirse":
			# Teclado de números para escribir el código de la sala
			var lista := []
			for i in 10:
				var k := (i + 1) % 10
				var col := (i % 5)
				var fila := i / 5
				lista.append(["n%d" % k, Rect2(X + col * 44, 150 + fila * 40, 38, 32), str(k), _codigo.length() < 4, ""])
			lista.append(["borrar", Rect2(X, 236, 104, ALTO), "BORRAR", _codigo.length() > 0, ""])
			lista.append(["entrar", Rect2(X + 114, 236, 104, ALTO), "ENTRAR", _codigo.length() == 4, ""])
			lista.append(["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""])
			return lista
		_:
			return [["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""]]


func _pulsado(id: String) -> void:
	if id.begins_with("n") and id.length() == 2:
		_codigo += id.substr(1)
		return
	match id:
		"coop":
			pantalla = "coop"
		"crear":
			_entrar_sala("%04d" % (randi() % 10000))
		"unirse":
			_codigo = ""
			pantalla = "unirse"
		"borrar":
			_codigo = _codigo.substr(0, _codigo.length() - 1)
		"entrar":
			_entrar_sala(_codigo)
		"carga":
			Game.modo_red = false
			Game.prueba_carga = true
			Game.empezar_mision()
		"seguir":
			Game.prueba_carga = false
			Game.modo_red = false
			Game.ir_al_mapa()
		"nueva":
			# Si ya hay una campaña, pide confirmar (se pierde lo avanzado)
			if _hay_campana() and _confirmar <= 0.0:
				_confirmar = 3.0
				return
			Game.prueba_carga = false
			Game.modo_red = false
			Campana.nueva()
			Campana.prologo = true
			Campana.tutorial = false      # el coronel vuelve a explicar el mapa
			Campana.guardar()
			Game.ver_cinematica("prologo", "mapa")
		"controles", "creditos":
			pantalla = id
		"volver":
			pantalla = "inicio"
		"salir_sala":
			if Red.actual:
				Red.actual.queue_free()
			pantalla = "coop"
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

	# Versión, abajo a la derecha (para saber si cargó la última)
	# En una placa oscura y a pleno color, en píxeles enteros: nítida sobre la foto
	var v := "VERSIÓN " + str(ProjectSettings.get_setting("application/config/version", "?"))
	var w := Estilo.ancho_texto(v)
	var placa := Rect2(floorf(s.x - w - 22), floorf(s.y - 24), ceilf(w + 16), 18)
	Estilo.marco(self, placa, "hundido")
	Estilo.texto(self, v, Vector2(placa.position.x + 8, placa.position.y + 13), Estilo.AMBAR_CLARO)
	match pantalla:
		"inicio":
			_titulo()
		"controles":
			_controles()
		"creditos":
			_creditos()
		"coop":
			_coop()
		"unirse":
			_unirse()
		"conectando":
			_conectando()
	_dibujar_botones()


func _entrar_sala(codigo: String) -> void:
	Game.prueba_carga = false
	Game.modo_red = true
	Red.conectar(get_tree(), codigo)
	pantalla = "conectando"


func _conectando() -> void:
	Estilo.texto(self, "SALA %s" % Game.sala, Vector2(X, 66), Estilo.CREMA, 33)
	var e := Red.actual.estado if Red.actual else "sin conexión"
	var txt := "CONECTANDO CON EL SERVIDOR..."
	if e == "sala llena":
		txt = "LA SALA ESTÁ LLENA (MÁXIMO 4)."
	elif e == "sin conexión":
		txt = "NO SE PUDO CONECTAR. REVISA INTERNET Y PRUEBA DE NUEVO."
	Estilo.texto(self, txt, Vector2(X, 96), Estilo.AMBAR_CLARO)


func _coop() -> void:
	Estilo.texto(self, "COOPERATIVO", Vector2(X, 66), Estilo.CREMA, 33)
	Estilo.texto(self, "HASTA 4 JUGADORES: CADA UNO MANDA UNA ESCUADRA Y TIENE SU OBJETIVO.", Vector2(X, 96), Estilo.AMBAR_CLARO)
	Estilo.texto(self, "UNO CREA LA SALA Y LES DICTA EL CÓDIGO A LOS DEMÁS.", Vector2(X, 110), Estilo.CREMA)


func _unirse() -> void:
	Estilo.texto(self, "CÓDIGO DE LA SALA", Vector2(X, 96), Estilo.CREMA)
	var txt := ""
	for i in 4:
		txt += (_codigo[i] if i < _codigo.length() else "_") + " "
	Estilo.texto(self, txt, Vector2(X, 134), Estilo.AMBAR, 33)


## ¿Hay una campaña empezada en este celular?
func _hay_campana() -> bool:
	Campana.cargar()
	return Campana.prologo or Campana.turnos > 0


func _resumen_campana() -> String:
	return "TURNO %d" % (Campana.turnos + 1)


func _titulo() -> void:
	# Logotipo (ChatGPT, tools/arte/telones.py): 200 px de ancho
	var w := 200.0
	draw_texture_rect(LOGO, Rect2(X - 4, 12, w, w * LOGO.get_height() / LOGO.get_width()), false)
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
