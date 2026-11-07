extends Node
class_name Escuadras
## Las cuatro escuadras americanas del desembarco (sección 5, paso 2).
## Cada jugador es jefe de una escuadra de 3 compañeros con IA:
##   0 = la del jugador (Murphy + DeLuca, Hayes, Brennan): obedece las órdenes del HUD.
##   1, 2, 3 = jugando solo, van a cargo de un sargento con IA.
## En el cooperativo (lo corre el anfitrión) cada jugador manda la escuadra de
## su puesto (0–3): `jefes[i]` es el jugador (el local o un JugadorRemoto) y
## `ordenes_jugador[i]` su orden. El sargento IA de esa escuadra pasa a ser un
## hombre más que lo sigue. Si el jugador se va, vuelve a mandar un sargento.
## `mi_escuadra` = la del jugador de ESTE celular (0, salvo que este celular
## haya tomado el lugar del anfitrión).
## Cada escuadra tiene su sector de la playa (carril en X). El sargento avanza
## de cobertura en cobertura por su sector y sus hombres lo siguen.
## Cuando caen hombres, llegan refuerzos desde la orilla (otra lancha) después
## de un rato, hasta un máximo por misión (ilimitado en la prueba de carga).

## Sectores de cada escuadra: vienen de los datos de la misión (Misiones).
static var SECTORES: Array = [Vector2(-6, 22), Vector2(-45, -20), Vector2(18, 45), Vector2(-22, -4)]
const NOMBRES_SARGENTO := ["", "SGT. KOWALSKI", "SGT. REYES", "SGT. COLE"]
const NOMBRES := ["GARCIA", "NOVAK", "BAKER", "JENKINS", "LOPEZ", "O'BRIEN", "WASHINGTON",
	"FISHER", "MILLER", "DUBOIS", "ROSSI", "SANDERS", "PARKER", "HUGHES", "WALSH", "TURNER"]
const REFUERZOS_POR_ESCUADRA := 6
const ESPERA_REFUERZO := Vector2(12.0, 20.0)

static var actual: Escuadras
## Orden de cada escuadra (la 0 la da el jugador con Aliado.dar_orden).
static var ordenes := ["seguir", "avanzar", "avanzar", "avanzar"]
static var mi_escuadra := 0
## Cooperativo: el jugador que manda cada escuadra (o null) y su orden.
static var jefes: Array = [null, null, null, null]
static var ordenes_jugador := ["seguir", "seguir", "seguir", "seguir"]

## Por escuadra: {"ranuras": [Aliado x3], "lider": Aliado (o null = el jugador),
##   "refuerzos": restantes, "llegan": [Game.elapsed de cada refuerzo en camino]}
var datos: Array = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _nombre_i := 0


var adoptar: Array = []      # traspaso de anfitrión: soldados ya hechos (no crear los de siempre)
var _fase_lista := 0         # la fase cuyos refuerzos ya se sumaron


func _ready() -> void:
	actual = self
	_rng.randomize()
	apoyo_listo = 0.0
	Aliado._ultimo_canto = -100.0     # los avisos de la misión anterior no cuentan
	Aliado._cantados = {}
	SECTORES = Misiones.dato("sectores")
	ordenes = ["seguir", "avanzar", "avanzar", "avanzar"]
	jefes = [null, null, null, null]
	ordenes_jugador = ["seguir", "seguir", "seguir", "seguir"]
	if adoptar.is_empty():
		Aliado.orden = "seguir"
	for i in 4:
		datos.append({"ranuras": [null, null, null], "lider": null,
			"refuerzos": 1000000 if Game.prueba_carga else int(Misiones.fase(0).get("refuerzos_us", REFUERZOS_POR_ESCUADRA)) + Campana.refuerzos_extra(),
			"llegan": []})
	_fase_lista = Objetivos.fase() if not adoptar.is_empty() and Objetivos.actual else 0
	if not adoptar.is_empty():
		_dispersadas = [0, 1, 2, 3]    # traspaso de anfitrión: nadie se dispersa de nuevo
		_adoptar()
		return
	# Escuadra del jugador: los 3 que eligió de su compañía (jugando solo) o los de siempre
	var mia: Array = Misiones.dato("escuadra_jugador")
	if Compania.activa():
		var eq := Compania.equipo()
		for k in mini(eq.size(), 3):
			var a := _soldado(0, mia[k][0], eq[k][1], eq[k][0], false)
			a.esp = eq[k][2]
			a.rango = eq[k][3]
			a.set_meta("compania", true)
			datos[0]["ranuras"][k] = a
	else:
		for k in 3:
			datos[0]["ranuras"][k] = _soldado(0, mia[k][0], mia[k][1], mia[k][2], false)
	# Misión 2: tras el choque del planeador, algunos quedaron dispersos (hay
	# que encontrarlos: objetivo "reunir"; hasta entonces no siguen órdenes)
	for k in Misiones.actual().get("perdidos", []):
		var a: Aliado = datos[0]["ranuras"][k]
		if a:
			a.set_meta("perdido", true)
			a.set_meta("fue_perdido", true)
			a.set_meta("gracia_hasta", 75.0)    # escondidos: los alemanes casi no los ven (Noche.factor_vista)
	# Las otras tres, con su sargento, repartidas en su sector
	for i in range(1, 4):
		var s: Vector2 = SECTORES[i]
		var cx := (s.x + s.y) / 2.0
		var hz: Vector2 = Misiones.dato("hombres_z")
		datos[i]["lider"] = _soldado(i, Vector3(cx, 0, Misiones.dato("lider_z")), "thompson", NOMBRES_SARGENTO[i], true)
		for k in 3:
			var p := Vector3(cx + (k - 1) * 4.0 + _rng.randf_range(-1, 1), 0, _rng.randf_range(hz.x, hz.y))
			datos[i]["ranuras"][k] = _soldado(i, p, ["garand", "garand", "bar"][k], _nombre_nuevo(), false)


## Traspaso de anfitrión: los compañeros que eran títeres ya son de verdad.
## Cada uno vuelve a su puesto (k = 0..2) o como sargento (k = 3).
func _adoptar() -> void:
	for x in adoptar:
		var a: Aliado = x[0]
		var esc: int = x[1]
		var k: int = x[2]
		if k >= 3:
			if datos[esc]["lider"] == null:
				datos[esc]["lider"] = a
				a.es_lider = true
		elif datos[esc]["ranuras"][k] == null:
			datos[esc]["ranuras"][k] = a
	for i in 4:
		datos[i]["refuerzos"] = REFUERZOS_POR_ESCUADRA / 2
	adoptar = []


func _soldado(esc: int, pos: Vector3, arma: String, nombre: String, lider: bool) -> Aliado:
	var a := Aliado.new()
	a.arma = arma
	a.nombre = nombre
	a.escuadra = esc
	a.es_lider = lider
	get_parent().add_child(a)
	a.global_position = Navegacion.cerca_de(pos) if Navegacion.listo else pos
	return a


func _nombre_nuevo() -> String:
	_nombre_i += 1
	return NOMBRES[(_nombre_i - 1) % NOMBRES.size()]


# ================================================================ consultas

static func orden_de(a: Aliado) -> String:
	if a.escuadra == mi_escuadra:
		return Aliado.orden
	if tiene_jefe(a.escuadra):
		return ordenes_jugador[a.escuadra]
	var o: String = ordenes[a.escuadra]
	if a.es_lider:
		return o
	return "mantener" if o == "mantener" else "seguir"


## A quién sigue un soldado: el jefe de su escuadra (el jugador en la 0).
static func lider_de(a: Aliado) -> Node3D:
	if actual == null or a.escuadra == mi_escuadra:
		return a.get_tree().get_first_node_in_group("player")
	if tiene_jefe(a.escuadra):
		return jefes[a.escuadra]
	if a.es_lider:
		return a.get_tree().get_first_node_in_group("player")
	var l: Aliado = actual.datos[a.escuadra]["lider"]
	return l if l and is_instance_valid(l) and not l.dead else null


## El carril donde avanza la escuadra: el suyo, o el del objetivo que falta
## si ya cumplió el suyo (así no se queda parada mientras otro frente se traba).
static func sector(esc: int) -> Vector2:
	esc = clampi(esc, 0, 3)
	if Objetivos.actual and Objetivos.terminado == 0:
		return Objetivos.carril(esc)
	return SECTORES[esc]


## ¿Esta escuadra la manda un jugador del cooperativo (que no soy yo)?
static func tiene_jefe(esc: int) -> bool:
	var j = jefes[esc]
	return j != null and is_instance_valid(j)


## Un jugador del cooperativo toma el mando de su escuadra: el sargento IA
## pasa a ser un hombre más (lo sigue).
static func poner_jefe(esc: int, jugador: Node3D) -> void:
	jefes[esc] = jugador
	if actual == null:
		return
	var l: Aliado = actual.datos[esc]["lider"]
	if l and is_instance_valid(l):
		l.es_lider = false
		l.nombre = l.nombre.replace("SGT. ", "")
	actual.datos[esc]["lider"] = null
	actual.dispersar(esc)


## Cooperativo, misión con salto: la escuadra de otro jugador también cae
## dispersa por los potreros de su sector (como la del anfitrión). Una sola vez
## por escuadra y solo al empezar (no si el jugador entra con la misión avanzada
## ni en un traspaso de anfitrión).
var _dispersadas: Array = []

func dispersar(esc: int) -> void:
	if esc in _dispersadas or Misiones.actual().get("perdidos", []).is_empty():
		return
	if Game.elapsed > 60.0 or Objetivos.fase() > 0:
		_dispersadas.append(esc)
		return
	if not Navegacion.listo:      # para dejarlos en un lugar caminable (se reintenta)
		return
	var hombres := []
	for a in get_tree().get_nodes_in_group("aliados"):
		if a is Aliado and not a.dead and a.escuadra == esc:
			hombres.append(a)
	if hombres.is_empty():        # sus hombres todavía no estaban: se reintenta (ver _process)
		return
	var lugares := _escondites(esc, hombres.size())
	for k in hombres.size():
		var a: Aliado = hombres[k]
		var quiero: Vector3 = lugares[k]
		var pos := Navegacion.cerca_de(quiero)
		if pos.distance_to(quiero) > 3.0:     # el mapa de caminos aún no responde bien
			pos = quiero
		# Agachado detrás del seto o el planeador más cercano, si hay uno a mano
		Coberturas.liberar(a)
		a.cobertura = {}
		a.en_cobertura = false
		var c := Coberturas.cercano(a, pos, 5.0)
		if not c.is_empty():
			pos = c["pos"]
		a.global_position = pos
		a.velocity = Vector3.ZERO
		a._ruta = PackedVector3Array()     # que no siga camino a donde iba
		a._destino = {}
		a.moviendo = false
		a.tomar_cobertura_inicial()
		if not a.en_cobertura:
			a.cuerpo.pose = "agachado"     # sin seto a mano: agachado en el pasto
		a.set_meta("perdido", true)
		a.set_meta("fue_perdido", true)
		a.set_meta("gracia_hasta", Game.elapsed + 75.0)   # además, mientras sigan perdidos casi no se ven (Noche)
	_dispersadas.append(esc)


## Dónde cae cada jugador en el salto (centro de su zona, como en mapa_planeador.gd).
func _aterrizaje(esc: int) -> Vector3:
	if esc == 0 or not Game.modo_red:
		return Vector3(1, 0, 3)          # Salto.zona por defecto: Rect2(-14, -4, 30, 14)
	var s: Vector2 = SECTORES[esc]
	var x0 := clampf((s.x + s.y) / 2.0 - 8.0, -43.0, 27.0)
	return Vector3(x0 + 8.0, 0, 5)


## v0.39: los escondites de la misión a 22–46 m de donde cae el jugador, al
## azar y uno por potrero si se puede (hay que cruzar los setos para juntarlos).
## Si no alcanzan (cooperativo con 3–4 jugadores), los de 12–22 m, y si tampoco,
## un punto al azar a 15–22 m de donde cae.
var _usados: Array = []

func _escondites(esc: int, n: int) -> Array:
	var cae := _aterrizaje(esc)
	var lista: Array = Misiones.actual().get("escondites", []).duplicate()
	lista.shuffle()
	var buenos := []
	var medios := []
	for e in lista:
		if e in _usados:
			continue
		var d := Vector2(e.x - cae.x, e.y - cae.z).length()
		if d >= 22.0 and d <= 46.0:
			buenos.append(e)
		elif d >= 12.0 and d < 22.0:
			medios.append(e)
	var elegidos := []
	var potreros := []
	for e in buenos:                       # primero, uno por potrero y separados
		if elegidos.size() >= n:
			break
		var p := _potrero(e.x)
		if not p in potreros and _separado(e, elegidos):
			potreros.append(p)
			elegidos.append(e)
	for grupo in [buenos, medios]:         # después, los que falten, separados
		for e in grupo:
			if elegidos.size() >= n:
				break
			if not e in elegidos and _separado(e, elegidos):
				elegidos.append(e)
	var r := []
	for e in elegidos:
		_usados.append(e)
		r.append(Vector3(e.x, 0, e.y))
	while r.size() < n:                    # no quedan escondites: al azar, a 15–22 m
		var mejor := Vector2.ZERO
		for intento in 12:
			var ang := _rng.randf() * TAU
			var dist := _rng.randf_range(15.0, 22.0)
			var qx := clampf(cae.x + cos(ang) * dist, -43.0, 43.0)
			# al sur del potrero, lejos de la MG42 y de la granja (alemanes hasta z -12)
			var q := Vector2(qx, clampf(cae.z + sin(ang) * dist, 2.0 if qx < -20.0 else -6.0, 13.0))
			mejor = q
			if _separado(q, []) and Vector2(q.x - cae.x, q.y - cae.z).length() >= 12.0:
				break
		_usados.append(mejor)
		r.append(Vector3(mejor.x, 0, mejor.y))
	return r


## A más de 12 m de los ya elegidos (y de los de otras escuadras).
func _separado(e: Vector2, elegidos: Array) -> bool:
	for o in elegidos + _usados:
		if e.distance_to(o) < 12.0:
			return false
	return true


static func _potrero(x: float) -> int:
	return 0 if x < -20.0 else (2 if x > 18.0 else 1)


static func dar_orden_remota(esc: int, o: String) -> void:
	ordenes_jugador[esc] = o
	var i := 0
	for a in Engine.get_main_loop().get_nodes_in_group("aliados"):
		if a.escuadra == esc:
			a._pensar_t = 0.2 + i * 0.35
			a._espera_hasta = 0.0
			i += 1


## Los tres puestos de la escuadra del jugador (para el HUD). En un invitado
## del cooperativo son títeres que manda el anfitrión.
static func ranuras_jugador() -> Array:
	if Red.es_invitado():
		return Red.actual.ranuras_mias()
	if actual == null:
		return []
	return actual.datos[mi_escuadra]["ranuras"]


## El compañero vivo que toma el jugador al caer (el más cercano), o null.
static func relevo_jugador() -> Aliado:
	if actual == null:
		return null
	var p := actual.get_tree().get_first_node_in_group("player") as Node3D
	return relevo_de(mi_escuadra, p.global_position)


## Si su escuadra no tiene a nadie, toma al más cercano de otra (la misión
## no se pierde mientras quede algún americano en pie).
static func relevo_de(esc: int, cerca: Vector3) -> Aliado:
	if actual == null:
		return null
	var mejor := _mas_cercano(actual.datos[esc]["ranuras"] + [actual.datos[esc]["lider"]], cerca)
	if mejor == null:
		var todos: Array = []
		for i in 4:
			if i != esc:
				todos += actual.datos[i]["ranuras"] + [actual.datos[i]["lider"]]
		mejor = _mas_cercano(todos, cerca)
	return mejor


static func _mas_cercano(lista: Array, cerca: Vector3) -> Aliado:
	var mejor: Aliado = null
	for a in lista:
		if a and is_instance_valid(a) and not a.dead:
			if mejor == null or a.global_position.distance_to(cerca) < mejor.global_position.distance_to(cerca):
				mejor = a
	return mejor


## Los refuerzos que llegaron a la escuadra del jugador y siguen vivos (al
## terminar la misión se unen a su compañía).
static func reemplazos_vivos() -> Array:
	if actual == null or not is_instance_valid(actual):
		return []
	var l := []
	for a in actual.datos[mi_escuadra]["ranuras"]:
		if a and is_instance_valid(a) and not a.dead and a.has_meta("reemplazo"):
			l.append(a.nombre)
	return l


## Radio: morteros donde mira el jugador (cada 75 s, con el de radio vivo).
static var apoyo_listo := 0.0
const ESPERA_APOYO := 90.0


static func pedir_artilleria() -> bool:
	var p := Engine.get_main_loop().get_first_node_in_group("player") as Player
	if p == null or p.dead or actual == null:
		return false
	var radio := especialista("radio", p.global_position)
	if radio == null:
		Game.say("[NO HAY RADIO EN TU ESCUADRA]", Game.COLOR_BAD)
		return false
	if Game.elapsed < apoyo_listo:
		Game.say("[%s: LA ARTILLERÍA ESTÁ OCUPADA. %d S]" % [radio.nombre, int(apoyo_listo - Game.elapsed)], Game.COLOR_INFO)
		return false
	var cam := p.camera.global_transform
	var q := PhysicsRayQueryParameters3D.create(cam.origin, cam.origin - cam.basis.z * 160.0, 1 | 512)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		Game.say("[%s: ¿DÓNDE? APUNTA AL SUELO]" % radio.nombre, Game.COLOR_INFO)
		return false
	var blanco: Vector3 = hit["position"]
	if blanco.distance_to(p.global_position) < 18.0:
		Game.say("[%s: ¡DEMASIADO CERCA, SARGENTO!]" % radio.nombre, Game.COLOR_BAD)
		return false
	apoyo_listo = Game.elapsed + ESPERA_APOYO
	Game.say("[%s: ¡MORTEROS EN CAMINO! CÚBRANSE]" % radio.nombre, Game.COLOR_GOOD)
	actual._andanada(blanco)
	return true


func _andanada(blanco: Vector3) -> void:
	await get_tree().create_timer(5.0).timeout
	for k in 4:
		if not is_inside_tree():
			return
		var pos := Navegacion.cerca_de(blanco + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))) + Vector3(0, 0.1, 0)
		Game.play_at("silbido", pos, 2.0)
		await get_tree().create_timer(1.1).timeout
		if is_inside_tree():
			Game.explode(pos, 6.5, 170.0)
		await get_tree().create_timer(0.5).timeout


## Un hombre vivo de la escuadra del jugador con esa especialidad, a menos de
## `radio` m de `cerca` (o null).
static func especialista(esp: String, cerca: Vector3, radio := INF) -> Aliado:
	if actual == null:
		return null
	for a in actual.datos[mi_escuadra]["ranuras"]:
		if a and is_instance_valid(a) and not a.dead and a.esp == esp and a.global_position.distance_to(cerca) < radio:
			return a
	return null


## Sin compañeros vivos: ¿quedan refuerzos para que el jugador vuelva desde
## la orilla? (gasta uno). Sirve para el cooperativo.
static func gastar_refuerzo(esc: int) -> bool:
	if actual == null:
		return true
	var d: Dictionary = actual.datos[esc]
	if d["refuerzos"] > 0:
		d["refuerzos"] -= 1
		return true
	if not d["llegan"].is_empty():
		d["llegan"].pop_back()
		return true
	return false


## Puesto de un soldado en su escuadra: 0–2, 3 = sargento, -1 = ninguno.
static func puesto_de(a: Aliado) -> int:
	if actual == null:
		return -1
	var d: Dictionary = actual.datos[a.escuadra]
	if d["lider"] == a:
		return 3
	return (d["ranuras"] as Array).find(a)


## ¿Le queda algo a esta escuadra? (hombres vivos o refuerzos)
static func le_queda(esc: int) -> bool:
	if actual == null:
		return true
	var d: Dictionary = actual.datos[esc]
	if d["refuerzos"] > 0 or not d["llegan"].is_empty():
		return true
	for i in 4:   # cualquier hombre de cualquier escuadra puede relevarlo
		for a in actual.datos[i]["ranuras"] + [actual.datos[i]["lider"]]:
			if a and is_instance_valid(a) and not a.dead:
				return true
	return false


## Saca a un soldado de su puesto (el jugador tomó su lugar): llegará un refuerzo.
static func quitar_de_escuadra(a: Aliado) -> void:
	if actual == null:
		return
	var r: Array = actual.datos[a.escuadra]["ranuras"]
	var i := r.find(a)
	if i >= 0:
		r[i] = null
	if actual.datos[a.escuadra]["lider"] == a:
		actual.datos[a.escuadra]["lider"] = null
	a.dead = true
	a.remove_from_group("americanos")
	a.remove_from_group("aliados")
	Coberturas.liberar(a)


# ================================================================ bajas y refuerzos

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	# Cooperativo, misión con salto: la escuadra de cada jugador cae dispersa
	for esc in 4:
		if (esc == 0 or tiene_jefe(esc)) and not esc in _dispersadas:
			dispersar(esc)
	# Fase nueva: llegan más refuerzos para cada escuadra
	if Objetivos.actual and not Game.prueba_carga:
		var f := Objetivos.fase()
		while _fase_lista < f:
			_fase_lista += 1
			for i in 4:
				datos[i]["refuerzos"] += int(Misiones.fase(_fase_lista).get("refuerzos_us", 0)) + Campana.refuerzos_extra()
	for i in 4:
		var d: Dictionary = datos[i]
		# Si cayó el sargento, asciende el primero que siga vivo
		# (en las escuadras sin jugador al mando)
		if i != mi_escuadra and not tiene_jefe(i):
			var l: Aliado = d["lider"]
			if l == null or not is_instance_valid(l) or l.dead:
				for k in 3:
					var a: Aliado = d["ranuras"][k]
					if a and is_instance_valid(a) and not a.dead:
						a.es_lider = true
						a.nombre = "SGT. " + a.nombre
						d["lider"] = a
						d["ranuras"][k] = null    # su puesto lo ocupará un refuerzo
						break
		# Puestos vacíos → refuerzos en camino
		var vacios := 0
		for k in 3:
			var a: Aliado = d["ranuras"][k]
			if a == null or not is_instance_valid(a) or a.dead:
				vacios += 1
		var en_camino: Array = d["llegan"]
		while en_camino.size() < vacios and d["refuerzos"] > 0:
			en_camino.append(Game.elapsed + _rng.randf_range(ESPERA_REFUERZO.x, ESPERA_REFUERZO.y))
			d["refuerzos"] -= 1
		# Los que ya llegaron desembarcan en la orilla de su sector
		var llegaron := 0
		for t in en_camino.duplicate():
			if Game.elapsed >= t:
				en_camino.erase(t)
				if _desembarcar(i):
					llegaron += 1
		if llegaron > 0 and i == mi_escuadra:
			Game.say("[REFUERZOS: %d %s A TU ESCUADRA]" % [llegaron, "HOMBRE" if llegaron == 1 else "HOMBRES"],
				Game.COLOR_GOOD)
		# Escuadra con IA casi sin hombres: se queda donde está hasta que llegan más
		if i != mi_escuadra and not tiene_jefe(i):
			var vivos := 3 - vacios + (1 if d["lider"] else 0)
			ordenes[i] = "mantener" if vivos <= 1 else "avanzar"


func _desembarcar(i: int) -> bool:
	var d: Dictionary = datos[i]
	for k in 3:
		var a: Aliado = d["ranuras"][k]
		if a == null or not is_instance_valid(a) or a.dead:
			var s: Vector2 = SECTORES[i]
			var rz: Vector2 = Misiones.dato("refuerzos_z")
			var p := Vector3(_rng.randf_range(s.x, s.y), 0, _rng.randf_range(rz.x, rz.y))
			# Tierra adentro llegan detrás del frente (no en la orilla)
			var ll: Array = Misiones.fase(Objetivos.fase()).get("llegada", []) if Objetivos.actual else []
			if not ll.is_empty():
				p = Navegacion.cerca_de(ll[0] + Vector3(_rng.randf_range(-ll[1], ll[1]) / 2.0, 0, _rng.randf_range(-2, 2)))
			d["ranuras"][k] = _soldado(i, p, ["garand", "garand", "bar", "thompson", "carbine"][_rng.randi() % 5],
				_nombre_nuevo(), false)
			if i == mi_escuadra and Compania.en_mision:
				d["ranuras"][k].set_meta("reemplazo", true)   # si sobrevive, se une a la compañía
			return true
	return false
