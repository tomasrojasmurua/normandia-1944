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
var _sala_vieja := ""         # sala de una partida cooperativa que se cortó (recarga)


const LOGO := preload("res://assets/ui/logo.png")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Red.actual:   # volvió de una partida cooperativa: se sale de la sala
		Red.actual.queue_free()
		Game.olvidar_sala()
	_sala_vieja = Game.sala_reciente()
	Game.modo_red = false
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_confirmar = maxf(_confirmar - delta, 0.0)
	queue_redraw()
	# Al saber tu puesto pasas a la sala de espera. El anfitrión empieza
	# cuando quiere (solo o con los que hayan entrado); los invitados entran
	# en cuanto empieza (o directo, si la misión ya estaba en curso).
	if pantalla == "conectando" and Red.actual and Red.actual.mi_id != "":
		pantalla = "espera"
	if pantalla == "espera":
		if Red.actual == null:
			pantalla = "coop"
		elif not Red.actual.anfitrion and Red.actual.en_curso:
			Game.empezar_mision(Misiones.PRIMERA)    # el cooperativo, por ahora, solo en Omaha


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
			] + ([["volver_sala", Rect2(X + ANCHO + 16, y0 + paso * 2, ANCHO + 20, ALTO),
				"VOLVER A LA SALA %s" % _sala_vieja, true, "LA PARTIDA SIGUE"]]
				if _sala_vieja != "" else [])
		"controles":
			var lista := [["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""]]
			if _tactil:
				lista.append(["garra", Rect2(X, 96, 220, ALTO), "BOTONES", true, TouchControls.ESQUEMAS[Game.esquema]])
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
		"espera":
			var lista := [["salir_sala", Rect2(X, size.y - 44, 120, ALTO), "SALIR", true, ""]]
			if Red.actual and Red.actual.anfitrion:
				lista.append(["empezar", Rect2(X, 236, ANCHO, ALTO), "¡EMPEZAR!", true,
					"%d JUGADOR%s" % [_jugadores(), "ES" if _jugadores() > 1 else ""]])
			return lista
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
			Game.empezar_mision(Misiones.PRIMERA)
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
		"empezar":
			Red.empezar_partida()
			Game.empezar_mision(Misiones.PRIMERA)    # el cooperativo, por ahora, solo en Omaha
		"volver_sala":
			_entrar_sala(_sala_vieja)
		"salir_sala":
			Game.olvidar_sala()
			_sala_vieja = ""
			if Red.actual:
				Red.actual.queue_free()
			pantalla = "coop"
		"garra":
			Game.cambiar_esquema()
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
		"espera":
			_espera()
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


func _jugadores() -> int:
	return 1 + (Red.actual.sala.size() if Red.actual else 0)


## Sala de espera: el código, los 4 puestos y quién está.
func _espera() -> void:
	var r := Red.actual
	if r == null:
		return
	Estilo.texto(self, "SALA %s" % Game.sala, Vector2(X, 66), Estilo.CREMA, 33)
	Estilo.texto(self, "DILES EL CÓDIGO: COOPERATIVO > UNIRSE A UNA SALA", Vector2(X, 92), Estilo.AMBAR_CLARO)
	var puestos := ["", "", "", ""]
	var anf := [false, false, false, false]
	puestos[r.puesto] = "TÚ"
	anf[r.puesto] = r.anfitrion
	var sin_puesto := 0
	for id in r.sala:
		var pu: int = r.sala[id][0]
		if pu >= 0 and pu < 4 and puestos[pu] == "":
			puestos[pu] = "LISTO"
			anf[pu] = r.sala[id][1]
		else:
			sin_puesto += 1
	for i in 4:   # los que aún no dijeron su puesto, en los libres
		if sin_puesto > 0 and puestos[i] == "":
			puestos[i] = "ENTRANDO..."
			sin_puesto -= 1
	for i in 4:
		var y := 118.0 + i * 24.0
		var fila := Rect2(X, y - 14, 300, 20)
		Estilo.marco(self, fila, "hundido" if puestos[i] != "" else "chapa")
		var col := Estilo.AMBAR if puestos[i] == "TÚ" else (Estilo.CREMA if puestos[i] != "" else Color(Estilo.CREMA, 0.4))
		Estilo.texto(self, "%d. SGT. %s" % [i + 1, Red.NOMBRES[i]], Vector2(X + 8, y), col)
		var estado: String = puestos[i] if puestos[i] != "" else "LIBRE"
		if anf[i]:
			estado += " - ANFITRIÓN"
		Estilo.texto(self, estado, Vector2(X + 130, y), col)
	if r.anfitrion:
		Estilo.texto(self, "EMPIEZA CUANDO QUIERAS: LOS QUE LLEGUEN DESPUÉS ENTRAN EN MARCHA.", Vector2(X, 226),
			Color(Estilo.CREMA, 0.75))
	else:
		Estilo.texto(self, "ESPERANDO A QUE EL ANFITRIÓN EMPIECE LA MISIÓN...", Vector2(X, 226), Estilo.AMBAR_CLARO)
	if r.estado == "sin conexión":
		Estilo.texto(self, "SE CORTÓ LA CONEXIÓN. SAL Y VUELVE A ENTRAR.", Vector2(X, 280), Estilo.ROJO)


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
			"MANTÉN AGACHAR (SE LLENA EL ANILLO): CUERPO A TIERRA",
			"TOCA EL ARMA 1 O 2 DE LA BARRA PARA CAMBIAR",
			"BOTONES: ELIGE LA DISTRIBUCIÓN (MIRA EL DIBUJO)",
			"AL SOLTAR: MANTÉN FUEGO PARA APUNTAR, SUELTA PARA DISPARAR",
			"BOTONES DE LA BARRA, A LA IZQUIERDA: ÓRDENES",
			"A LA ESCUADRA (SÍGANME, AVANCEN, ALTO)",
			"TOCA LA CARA DE UN HOMBRE: SU ORDEN (MÉDICO, BAZUCA...)",
		]
		for i in lineas.size():
			Estilo.texto(self, lineas[i], Vector2(X, 140 + i * 15), Estilo.CREMA)
		_vista_botones(Rect2(size.x - 236, 96, 208, 117))
	else:
		var teclas := [
			["W A S D", "CAMINAR"], ["SHIFT", "CORRER"], ["MOUSE", "MIRAR"],
			["CLIC IZQUIERDO", "DISPARAR"], ["CLIC DERECHO", "MIRAR POR LA MIRA"],
			["R", "RECARGAR"], ["G", "GRANADA"], ["ESPACIO", "SALTAR"],
			["C / CTRL", "AGACHARSE"], ["E", "RECOGER ARMA"], ["1 / 2 / Q", "CAMBIAR DE ARMA"],
			["Z / X / V", "ESCUADRA: SÍGANME / AVANCEN / ALTO"],
			["7 / 8 / 9", "ORDEN A UN HOMBRE (MÉDICO, BAZUCA...)"],
			["ESC", "PAUSA"],
		]
		for i in teclas.size():
			var y := 76.0 + i * 15.0
			Estilo.texto(self, teclas[i][0], Vector2(X, y), Estilo.AMBAR_CLARO)
			Estilo.texto(self, teclas[i][1], Vector2(X + 120, y), Estilo.CREMA)


## Dibujo chico de la pantalla con los botones de la distribución elegida.
func _vista_botones(r: Rect2) -> void:
	Estilo.marco(self, r.grow(3), "hundido")
	draw_rect(r, Color(0.16, 0.2, 0.13))
	var pant := Vector2(780, 360)     # un celular apaisado típico (en píxeles del juego)
	var k := r.size.x / pant.x
	draw_rect(Rect2(r.position + Vector2(0, (pant.y - 52) * k), Vector2(r.size.x, 52 * k)), Color(Estilo.NEGRO, 0.6))
	var zurdo := Game.esquema == 3
	var cam := Rect2(r.position + Vector2(r.size.x * (0.5 if zurdo else 0.0), 0), Vector2(r.size.x * 0.5, (pant.y - 52) * k))
	draw_rect(cam, Color(Estilo.AMBAR, 0.1))
	Estilo.texto_c(self, "CAMINAR", cam.get_center().x, cam.get_center().y + 3, Color(Estilo.CREMA, 0.55))
	for b in TouchControls.disposicion(Game.esquema, pant, true):
		var c: Vector2 = r.position + (b[2] as Vector2) * k
		var col := Estilo.ROJO if b[0] in ["fire", "fire_left"] else (Estilo.AMBAR_CLARO if b[0] == "use" else Estilo.CREMA)
		draw_circle(c, b[3] * k, Color(col, 0.75))
	Estilo.texto_c(self, TouchControls.ESQUEMAS[Game.esquema], r.get_center().x, r.end.y + 14, Estilo.AMBAR_CLARO)


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
