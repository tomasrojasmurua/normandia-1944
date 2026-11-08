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


const MISIONES_COOP := ["campana", "omaha", "planeador"]    # "campana": la campaña cooperativa (v0.41)
static var _url_revisada := false    # el enlace de invitación (?sala=1234) se usa una sola vez
var _reconectar_t := 0.0
var _invitado_t := 0.0               # >0: se acaba de tocar INVITAR (aviso en pantalla)
const LOGO := preload("res://assets/ui/logo.png")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Red.actual:   # volvió de una partida cooperativa: se sale de la sala
		Red.actual.queue_free()
		Game.olvidar_sala()
	CampanaRed.salir()    # la campaña de un jugador vuelve a ser la de este celular
	_sala_vieja = Game.sala_reciente()
	Game.modo_red = false
	Game.mision_suelta = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_revisar_enlace()


## v0.42: si el juego se abrió con un enlace de invitación (WhatsApp), entra
## directo a esa sala. Se borra de la dirección para no volver a entrar.
const JS_ENLACE := "(function(){try{var s=new URLSearchParams(location.search).get('sala')||'';" \
	+ "if(s){history.replaceState(null,'',location.pathname);} return s;}catch(e){return '';}})()"

func _revisar_enlace() -> void:
	if _url_revisada or not OS.has_feature("web"):
		return
	_url_revisada = true
	var c = JavaScriptBridge.eval(JS_ENLACE, true)
	if c is String and (c as String).length() == 4 and (c as String).is_valid_int():
		Game.aviso_menu = ""
		_entrar_sala.call_deferred(c)


## v0.42: invitar por WhatsApp con un enlace que abre el juego y entra a la
## sala. En el navegador, abrir otra página solo se permite durante un toque
## de verdad: el botón reacciona al apoyar el dedo, así que WhatsApp se abre al
## LEVANTARLO (escuchando "touchend"/"mouseup" desde JavaScript).
const JS_INVITAR := "(function(c){var url=location.origin+location.pathname+'?sala='+c;" \
	+ "var txt='¡Únete a mi sala de NORMANDY 1944! Código '+c+': '+url;" \
	+ "var wa='https://wa.me/?text='+encodeURIComponent(txt);var hecho=false;" \
	+ "var quitar=function(){window.removeEventListener('touchend',abrir,true);window.removeEventListener('mouseup',abrir,true);};" \
	+ "var abrir=function(){if(hecho){return;}hecho=true;quitar();window.open(wa,'_blank');};" \
	+ "window.addEventListener('touchend',abrir,true);window.addEventListener('mouseup',abrir,true);" \
	+ "setTimeout(quitar,2500);})('%s')"

func _invitar() -> void:
	_invitado_t = 4.0
	if OS.has_feature("web"):
		JavaScriptBridge.eval(JS_INVITAR % Game.sala, true)
	else:
		OS.shell_open("https://wa.me/?text=" + ("¡Únete a mi sala de NORMANDY 1944! Código %s" % Game.sala).uri_encode())


func _process(delta: float) -> void:
	_confirmar = maxf(_confirmar - delta, 0.0)
	queue_redraw()
	# Al saber tu puesto pasas a la sala de espera. El anfitrión empieza
	# cuando quiere (solo o con los que hayan entrado); los invitados entran
	# en cuanto empieza (o directo, si la misión ya estaba en curso).
	if pantalla == "conectando" and Red.actual and Red.actual.mi_id != "":
		pantalla = "espera"
	_invitado_t = maxf(_invitado_t - delta, 0.0)
	# En la sala de espera, si se cortó (p. ej. al ir a WhatsApp a invitar), se
	# vuelve a entrar solo a la misma sala, con la misma misión elegida
	if pantalla == "espera" and Red.actual and Red.actual.estado == "sin conexión" and not Red.actual.en_curso:
		_reconectar_t += delta
		if _reconectar_t > 1.5:
			_reconectar_t = 0.0
			_entrar_sala(Game.sala, Red.actual.mision_sala if Red.actual.anfitrion else "")
			return
	if pantalla == "espera":
		if Red.actual == null:
			pantalla = "coop"
		elif not Red.actual.anfitrion and Red.actual.en_curso:
			if Red.actual.mision_sala == "campana":
				CampanaRed.entrar_invitado()     # la campaña cooperativa: se sigue al anfitrión
			else:
				Game.empezar_mision(Red.actual.mision_sala)    # la que eligió el anfitrión


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
				["versus", Rect2(X + ANCHO + 16, y0 + paso * 2, ANCHO, ALTO), "VERSUS", true, "EE.UU. CONTRA ALEMANIA"],
				["controles", Rect2(X, y0 + paso * 3, ANCHO, ALTO), "CONTROLES", true, ""],
				["creditos", Rect2(X, y0 + paso * 4, ANCHO, ALTO), "CRÉDITOS", true, ""],
				["carga", Rect2(X, y0 + paso * 5, ANCHO, ALTO), "PRUEBA DE CARGA", true, ""],
				["salto", Rect2(X + ANCHO + 16, y0 + paso * 5, ANCHO, ALTO), "PROBAR EL SALTO", true, "SIN CAMPAÑA"],
			] + ([["volver_sala", Rect2(X + ANCHO + 16, y0 + paso * 3, ANCHO + 20, ALTO),
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
		"versus":
			return [
				["crear_vs", Rect2(X, y0, ANCHO, ALTO), "CREAR SALA", true, ""],
				["unirse", Rect2(X, y0 + paso, ANCHO, ALTO), "UNIRSE A UNA SALA", true, ""],
				["volver", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""],
			]
		"conectando":
			return [["salir_sala", Rect2(X, size.y - 44, 120, ALTO), "VOLVER", true, ""]]
		"espera":
			var lista := [["salir_sala", Rect2(X, size.y - 44, 120, ALTO), "SALIR", true, ""]]
			if Red.actual and Versus.es_versus(Red.actual.mision_sala):
				return lista + _botones_versus()
			lista.append(["invitar", Rect2(X + 320, 140, ANCHO, ALTO), "INVITAR", true, "POR WHATSAPP"])
			if Red.actual and Red.actual.anfitrion:
				lista.append(["mision_coop", Rect2(X + 320, 118 - 14, ANCHO, ALTO), "MISIÓN", true,
					_nombre_coop(Red.actual.mision_sala)])
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


## Sala de espera del versus: invitar, cambiar de bando y (el anfitrión)
## elegir el mapa y empezar.
func _botones_versus() -> Array:
	var r := Red.actual
	var n := r.por_bando()
	var otro := 1 - maxi(r.bando, 0)
	var l := [
		["bando", Rect2(X, 186, ANCHO, ALTO), "CAMBIAR DE BANDO", n[otro] < 2,
			"A " + Versus.NOMBRES_BANDO[otro] if n[otro] < 2 else Versus.NOMBRES_BANDO[otro] + " ESTÁ LLENO"],
		["invitar", Rect2(X + ANCHO + 12, 186, ANCHO, ALTO), "INVITAR", true, "POR WHATSAPP"],
	]
	if r.anfitrion:
		l.append(["mision_vs", Rect2(X + 340, 104, ANCHO, ALTO), "MAPA", true, _nombre_coop(r.mision_sala).replace("VERSUS: ", "")])
		l.append(["empezar", Rect2(X, 236, ANCHO, ALTO), "¡EMPEZAR!", true,
			"%d JUGADOR%s" % [_jugadores(), "ES" if _jugadores() > 1 else ""]])
	return l


func _pulsado(id: String) -> void:
	if id.begins_with("n") and id.length() == 2:
		_codigo += id.substr(1)
		return
	match id:
		"versus":
			pantalla = "versus"
			Game.aviso_menu = ""
		"crear_vs":
			_entrar_sala("%04d" % (randi() % 10000), "vs_playa")
		"bando":
			if Red.actual:
				Red.actual.cambiar_bando()
		"invitar":
			_invitar()
		"mision_vs":
			if Red.actual:
				var l: Array = Red.MISIONES_VS
				Red.actual.mision_sala = l[(l.find(Red.actual.mision_sala) + 1) % l.size()]
		"coop":
			pantalla = "coop"
			Game.aviso_menu = ""
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
		"salto":
			# La misión 2 aparte: no cuenta en la campaña ni arriesga a la compañía
			Game.modo_red = false
			Game.prueba_carga = false
			Game.mision_suelta = true
			Game.empezar_mision("planeador")
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
			if Red.actual.mision_sala == "campana":
				CampanaRed.empezar_anfitrion()    # el mapa (y el prólogo, si es nueva)
			else:
				Red.empezar_partida()
				Game.empezar_mision(Red.actual.mision_sala)
		"mision_coop":   # el anfitrión elige: Omaha o el salto (las dos que se juegan en cooperativo)
			if Red.actual:
				var i := MISIONES_COOP.find(Red.actual.mision_sala)
				Red.actual.mision_sala = MISIONES_COOP[(i + 1) % MISIONES_COOP.size()]
		"volver_sala":
			_entrar_sala(_sala_vieja)
		"salir_sala":
			Game.olvidar_sala()
			_sala_vieja = ""
			var era_vs := Red.actual != null and Versus.es_versus(Red.actual.mision_sala)
			if Red.actual:
				Red.actual.queue_free()
			pantalla = "versus" if era_vs else "coop"
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
		"versus":
			_pantalla_versus()
		"unirse":
			_unirse()
		"conectando":
			_conectando()
		"espera":
			_espera()
	if Game.aviso_menu != "" and pantalla in ["inicio", "coop", "versus"]:
		Estilo.texto(self, Game.aviso_menu, Vector2(X, s.y - 52), Estilo.ROJO)
	_dibujar_botones()


## `mision`: la que quedará elegida si este jugador resulta ser el anfitrión
## (si la sala ya existía, manda la del anfitrión de siempre).
func _entrar_sala(codigo: String, mision := "") -> void:
	Game.prueba_carga = false
	Game.modo_red = true
	Red.conectar(get_tree(), codigo)
	if mision != "" and Red.actual:
		Red.actual.mision_sala = mision
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
	if _invitado_t > 0.0:
		Estilo.texto(self, "ABRIENDO WHATSAPP... (SI NO SE ABRE, TOCA INVITAR DE NUEVO)", Vector2(X, size.y - 58), Estilo.VERDE_LED)
	if Versus.es_versus(r.mision_sala):
		_espera_versus()
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
	if not r.anfitrion:
		Estilo.texto(self, "MISIÓN: %s" % _nombre_coop(r.mision_sala), Vector2(X + 320, 118), Estilo.AMBAR)
	if r.anfitrion and r.mision_sala == "campana":
		Estilo.texto(self, "LA CAMPAÑA SE GUARDA EN TU CELULAR (APARTE DE LA DE UN JUGADOR).", Vector2(X, 214),
			Color(Estilo.CREMA, 0.75))
		Estilo.texto(self, "TÚ DECIDES EN EL MAPA; LOS DEMÁS LO VEN EN VIVO.", Vector2(X, 226), Color(Estilo.CREMA, 0.75))
	elif r.anfitrion:
		Estilo.texto(self, "EMPIEZA CUANDO QUIERAS: LOS QUE LLEGUEN DESPUÉS ENTRAN EN MARCHA.", Vector2(X, 226),
			Color(Estilo.CREMA, 0.75))
	else:
		Estilo.texto(self, "ESPERANDO A QUE EL ANFITRIÓN EMPIECE LA MISIÓN...", Vector2(X, 226), Estilo.AMBAR_CLARO)
	if r.estado == "sin conexión":
		Estilo.texto(self, "SE CORTÓ LA CONEXIÓN. SAL Y VUELVE A ENTRAR.", Vector2(X, 280), Estilo.ROJO)


## Sala de espera del versus: los dos bandos, con quién está en cada uno.
func _espera_versus() -> void:
	var r := Red.actual
	Estilo.texto(self, "SALA %s" % Game.sala, Vector2(X, 66), Estilo.CREMA, 33)
	Estilo.texto(self, "VERSUS - DILES EL CÓDIGO O INVÍTALOS POR WHATSAPP", Vector2(X, 92), Estilo.AMBAR_CLARO)
	if not r.anfitrion:
		Estilo.texto(self, "MAPA: %s" % _nombre_coop(r.mision_sala).replace("VERSUS: ", ""), Vector2(X + 340, 118), Estilo.AMBAR)
	# Quién está en cada bando: yo y los demás (con su puesto, para el nombre)
	var filas := [[], []]
	filas[maxi(r.bando, 0)].append([r.puesto, "TÚ", r.anfitrion])
	for id in r.sala:
		var e: Array = r.sala[id]
		var pu := int(e[0])
		var b := int(e[2]) if e.size() > 2 and int(e[2]) >= 0 else (pu % 2 if pu >= 0 else -1)
		if b < 0:
			continue
		filas[b].append([pu, "LISTO" if pu >= 0 else "ENTRANDO...", bool(e[1])])
	for b in 2:
		var x := X + b * 166.0
		Estilo.texto(self, Versus.NOMBRES_BANDO[b], Vector2(x, 118), [Color(0.55, 0.68, 1.0), Color(1.0, 0.45, 0.38)][b])
		for k in 2:
			var y := 138.0 + k * 22.0
			var fila := Rect2(x, y - 14, 158, 20)
			var hay: bool = k < filas[b].size()
			Estilo.marco(self, fila, "hundido" if hay else "chapa")
			if not hay:
				Estilo.texto(self, "LIBRE (IA)", Vector2(x + 8, y), Color(Estilo.CREMA, 0.4))
				continue
			var f: Array = filas[b][k]
			var nombre: String = Versus.NOMBRES_JUGADOR[b][clampi(int(f[0]), 0, 3)] if int(f[0]) >= 0 else "?"
			var col := Estilo.AMBAR if f[1] == "TÚ" else Estilo.CREMA
			Estilo.texto(self, nombre, Vector2(x + 8, y), col)
			Estilo.texto(self, str(f[1]) + (" - ANF." if f[2] else ""), Vector2(x + 76, y), col)
	if r.anfitrion:
		Estilo.texto(self, "CADA UNO MANDA SU ESCUADRA. LOS PUESTOS LIBRES LOS LLEVA LA IA.", Vector2(X, 228),
			Color(Estilo.CREMA, 0.75))
	else:
		Estilo.texto(self, "ESPERANDO A QUE EL ANFITRIÓN EMPIECE LA PARTIDA...", Vector2(X, 228), Estilo.AMBAR_CLARO)
	if r.estado == "sin conexión":
		Estilo.texto(self, "SE CORTÓ LA CONEXIÓN: VOLVIENDO A ENTRAR...", Vector2(X, 280), Estilo.ROJO)


func _pantalla_versus() -> void:
	Estilo.texto(self, "VERSUS", Vector2(X, 66), Estilo.CREMA, 33)
	Estilo.texto(self, "EE.UU. CONTRA ALEMANIA: HASTA 2 JUGADORES POR BANDO, CADA UNO CON SU ESCUADRA.", Vector2(X, 96), Estilo.AMBAR_CLARO)
	Estilo.texto(self, "TOMA EL PUNTO DEL MEDIO Y DEJA AL OTRO BANDO SIN REFUERZOS. MAPAS: LA PLAYA Y EL BOSQUE.", Vector2(X, 110), Estilo.CREMA)


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


## Nombre de lo que se juega en la sala: una misión o la campaña cooperativa.
func _nombre_coop(id: String) -> String:
	if id == "campana":
		return "CAMPAÑA" + (" (TURNO %d)" % _turno_coop() if _turno_coop() > 0 else "")
	return Misiones.DATOS[id]["nombre"] if Misiones.existe(id) else id


## Turno de la campaña cooperativa guardada en este celular (0 = no hay).
func _turno_coop() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(CampanaRed.ARCHIVO_COOP) != OK or not cfg.has_section_key("campana", "turnos"):
		return 0
	return int(cfg.get_value("campana", "turnos", 0)) + 1


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
