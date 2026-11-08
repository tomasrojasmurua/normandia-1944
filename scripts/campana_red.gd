extends RefCounted
class_name CampanaRed
## La campaña en cooperativo (v0.41): el mapa, los recursos, la compañía, el
## diario y las cinemáticas, para todos los de la sala.
##
## - El ANFITRIÓN decide (elige la misión, recluta, descansa, compra apoyo) y
##   guarda la campaña en su celular, aparte de la de un jugador
##   (user://campana_coop.cfg). Para seguirla otro día, crea la sala el mismo.
## - Los INVITADOS ven lo mismo en vivo: un reflejo (espejo) que no se guarda.
##   Siguen al anfitrión de pantalla en pantalla (mapa, previa, cinemática,
##   misión) y solo pueden tocar lo suyo: elegir sus 3 hombres en la previa
##   y cambiarles el arma (se le pide al anfitrión).
## - La compañía es UNA para todos: cada jugador elige sus 3 de los que quedan.
##   Las escuadras de los puestos sin jugador van con soldados sin nombre.
##
## Mensajes (por el servidor, que solo reenvía):
##   {"t":"cp", "d": {"p": pantalla, "u": estado de la pantalla, "s": Campana,
##    "c": Compania, "e": elecciones, "pu": puestos con jugador, "g": misión}}
##       ("d" va con JSON.from_native, para que lleguen enteros y no decimales)
##       del anfitrión, al cambiar algo y cada tanto (para el que llega tarde).
##       pantalla: "mapa", "previa", "cine:<id>:<después>" o "mision:<id>".
##   {"t":"cpe", "pu": puesto, "n": nombre}   invitado: elijo / suelto a un hombre
##   {"t":"cpa", "pu": puesto, "n": nombre}   invitado: otra arma para uno de los míos

const ARCHIVO_COOP := "user://campana_coop.cfg"
const CADA := 1.0               # segundos entre envíos en el mapa y la previa
const CADA_MISION := 3.0        # durante la misión (solo para el que entra tarde)

static var coop := false         # hay una campaña cooperativa en curso (anfitrión o invitado)
static var espejo := false       # soy invitado: la campaña es un reflejo de la del anfitrión
static var pantalla := ""        # la pantalla en que está el anfitrión
static var ui := {}              # lo que se ve en esa pantalla (mapa: carta elegida, diario...)
static var elecciones := {}      # "0".."3" → nombres elegidos por ese jugador en la previa
static var _puestos_anf: Array = [0]
static var _t := 0.0
static var _sucio := false


# ================================================================ consultas

static func activa() -> bool:
	return coop and Game.modo_red and Red.actual != null


static func anfitrion() -> bool:
	return coop and not espejo


static func mi_puesto() -> int:
	return Red.actual.puesto if Red.actual else 0


## Puestos con jugador (siempre ordenados; el anfitrión manda la lista).
static func puestos() -> Array:
	if espejo or Red.actual == null:
		return _puestos_anf
	var l := [Red.actual.puesto]
	for id in Red.actual.sala:
		var pu: int = Red.actual.sala[id][0]
		if pu >= 0 and pu < 4 and not pu in l:
			l.append(pu)
	l.sort()
	return l


static func elegidos_de(pu: int) -> Array:
	return elecciones.get(str(pu), [])


static func nombre_de(pu: int) -> String:
	return Red.NOMBRES[clampi(pu, 0, 3)]


## El puesto del anfitrión (el que decide).
static func puesto_anfitrion() -> int:
	if not espejo or Red.actual == null:
		return mi_puesto()
	for id in Red.actual.sala:
		if Red.actual.sala[id][1]:
			return int(Red.actual.sala[id][0])
	return 0


## ¿Quién eligió a este hombre? (-1 = nadie)
static func dueno(nombre: String) -> int:
	for pu in 4:
		if nombre in elegidos_de(pu):
			return pu
	return -1


# ================================================================ anfitrión

## El anfitrión empieza (o sigue) la campaña cooperativa desde la sala de espera.
static func empezar_anfitrion() -> void:
	coop = true
	espejo = false
	elecciones = {}
	Campana.usar(ARCHIVO_COOP)
	Campana.cargar()
	Red.actual.mision_sala = "campana"
	Red.empezar_partida()
	Game.ir_al_mapa()


## El anfitrión avisa en qué pantalla está (Game lo llama al cambiar de escena).
static func ir_a(p: String) -> void:
	if not anfitrion():
		return
	pantalla = p
	if p.begins_with("mision:") and Red.actual:
		Red.actual._cuerpos.clear()     # los cuerpos de la misión anterior no van
	publicar()


## Algo cambió (una decisión en el mapa, una elección en la previa): se manda ya.
static func cambio() -> void:
	_sucio = true


static func publicar() -> void:
	_sucio = false
	_t = 0.0
	if not anfitrion() or not Red.activo():
		return
	var d := {"p": pantalla, "u": ui, "s": Campana.estado_red(), "c": Compania.estado_red(),
		"e": elecciones, "pu": puestos(), "g": Game.mision}
	# from_native conserva los tipos (enteros, listas) al pasar por JSON
	Red.actual.enviar(JSON.stringify({"t": "cp", "d": JSON.from_native(d)}))


## Cada cuadro (desde Red): manda lo pendiente y repite cada tanto.
static func procesar(delta: float) -> void:
	if not anfitrion() or pantalla == "":
		return
	_t += delta
	var cada := CADA_MISION if pantalla.begins_with("mision") else CADA
	if _sucio or _t >= cada:
		publicar()


## Un invitado elige o suelta a un hombre (o el anfitrión, para su puesto).
static func alternar(pu: int, nombre: String) -> void:
	var h := Compania.hombre(nombre)
	if h.is_empty() or h["estado"] != "ok":
		return
	var k := str(pu)
	var mios: Array = elecciones.get(k, []).duplicate()
	if nombre in mios:
		mios.erase(nombre)
	elif dueno(nombre) < 0 and mios.size() < 3:
		mios.append(nombre)
	elecciones[k] = mios
	cambio()


## Otra arma para uno de los hombres de ese puesto.
static func otra_arma(pu: int, nombre: String) -> void:
	for e in Compania.equipo_de(pu):
		if e[0] == nombre:
			Compania.otra_arma(nombre)
			cambio()
			return


## Mensajes de los invitados (solo los atiende el anfitrión).
static func pedido(d: Dictionary) -> void:
	if not anfitrion() or pantalla != "previa":
		return
	match str(d.get("t", "")):
		"cpe":
			alternar(int(d.get("pu", -1)), str(d.get("n", "")))
		"cpa":
			otra_arma(int(d.get("pu", -1)), str(d.get("n", "")))


# ================================================================ invitado

## El invitado entra a la campaña (desde la sala de espera, o al volver a la sala).
static func entrar_invitado() -> void:
	coop = true
	espejo = true
	pantalla = ""
	Campana._cargada = true
	Compania._cargada = true
	Game.prueba_carga = false
	Game.mision_suelta = false
	# Mientras llega el primer mensaje, el mapa (con lo que haya)
	Game.ir_al_mapa()


## Lo que mandó el anfitrión: el estado y la pantalla a la que hay que ir.
static func recibir(d: Dictionary) -> void:
	if Red.actual == null or Red.actual.anfitrion:
		return
	var v: Variant = JSON.to_native(d.get("d", {}))
	if not v is Dictionary:
		return
	var x: Dictionary = v
	if not espejo:
		if Red.actual.mision_sala != "campana":
			return       # no estoy en una campaña (por ejemplo, sigo en el menú)
		entrar_invitado()
	Campana.aplicar_red(x.get("s", {}))
	Compania.aplicar_red(x.get("c", {}))
	ui = x.get("u", {})
	elecciones = x.get("e", {})
	_puestos_anf = x.get("pu", [0])
	var g := str(x.get("g", ""))
	if Misiones.existe(g):
		Game.mision = g
	_seguir(str(x.get("p", "")))


## Ir a la pantalla del anfitrión (si no estoy ya ahí).
static func _seguir(p: String) -> void:
	if p == "" or p == pantalla and _escena_coincide(p):
		pantalla = p
		return
	pantalla = p
	if _escena_coincide(p):
		return
	if p == "mapa":
		Game.ir_al_mapa()
	elif p == "previa":
		Game.ir_a_previa()
	elif p.begins_with("cine:"):
		var partes := p.split(":")
		if partes.size() >= 3 and Cinematica.tiene(partes[1]):
			Game.ver_cinematica(partes[1], partes[2])
	elif p.begins_with("mision:"):
		var id := p.substr(7)
		if Misiones.existe(id):
			Game.empezar_mision(id, true)


static func _escena_coincide(p: String) -> bool:
	var e := Engine.get_main_loop() as SceneTree
	if e == null or e.current_scene == null:
		return false
	var ruta := e.current_scene.scene_file_path
	if p == "mapa":
		return ruta.ends_with("mapa.tscn")
	if p == "previa":
		return ruta.ends_with("previa.tscn")
	if p.begins_with("cine:"):
		return ruta.ends_with("cinematica.tscn") and Cinematica.actual == p.split(":")[1]
	if p.begins_with("mision:"):
		return e.current_scene.name == "Main" and Game.mision == p.substr(7)
	return false


## Invitado: pedirle algo al anfitrión.
static func pedir(t: String, nombre: String) -> void:
	if espejo and Red.activo():
		Red.actual.enviar(JSON.stringify({"t": t, "pu": mi_puesto(), "n": nombre}))


# ================================================================ salir

## Al volver al menú: se acaba la campaña cooperativa; la de un jugador vuelve
## a cargarse de su archivo la próxima vez.
static func salir() -> void:
	coop = false
	espejo = false
	pantalla = ""
	ui = {}
	elecciones = {}
	_puestos_anf = [0]
	Campana.usar(Campana.ARCHIVO)
	Campana._cargada = false
	Compania._cargada = false
