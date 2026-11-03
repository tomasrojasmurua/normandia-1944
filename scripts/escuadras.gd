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

const SECTORES := [Vector2(-6, 22), Vector2(-45, -20), Vector2(18, 45), Vector2(-22, -4)]
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


func _ready() -> void:
	actual = self
	_rng.randomize()
	ordenes = ["seguir", "avanzar", "avanzar", "avanzar"]
	jefes = [null, null, null, null]
	ordenes_jugador = ["seguir", "seguir", "seguir", "seguir"]
	if adoptar.is_empty():
		Aliado.orden = "seguir"
	for i in 4:
		datos.append({"ranuras": [null, null, null], "lider": null,
			"refuerzos": 1000000 if Game.prueba_carga else REFUERZOS_POR_ESCUADRA, "llegan": []})
	if not adoptar.is_empty():
		_adoptar()
		return
	# Escuadra del jugador: los de siempre
	var mia := [[Vector3(-9, 0, -3), "thompson", "DELUCA"], [Vector3(11, 0, -6), "garand", "HAYES"],
		[Vector3(-6, 0, 3), "bar", "BRENNAN"]]
	for k in 3:
		datos[0]["ranuras"][k] = _soldado(0, mia[k][0], mia[k][1], mia[k][2], false)
	# Las otras tres, con su sargento, repartidas en su sector
	for i in range(1, 4):
		var s: Vector2 = SECTORES[i]
		var cx := (s.x + s.y) / 2.0
		datos[i]["lider"] = _soldado(i, Vector3(cx, 0, 5), "thompson", NOMBRES_SARGENTO[i], true)
		for k in 3:
			var p := Vector3(cx + (k - 1) * 4.0 + _rng.randf_range(-1, 1), 0, _rng.randf_range(6.5, 9.0))
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


static func sector(esc: int) -> Vector2:
	return SECTORES[clampi(esc, 0, 3)]


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


static func relevo_de(esc: int, cerca: Vector3) -> Aliado:
	if actual == null:
		return null
	var mejor: Aliado = null
	for a in actual.datos[esc]["ranuras"] + [actual.datos[esc]["lider"]]:
		if a and is_instance_valid(a) and not a.dead:
			if mejor == null or a.global_position.distance_to(cerca) < mejor.global_position.distance_to(cerca):
				mejor = a
	return mejor


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
	for a in d["ranuras"] + [d["lider"]]:
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
			var p := Vector3(_rng.randf_range(s.x, s.y), 0, _rng.randf_range(7.0, 9.5))
			d["ranuras"][k] = _soldado(i, p, ["garand", "garand", "bar", "thompson", "carbine"][_rng.randi() % 5],
				_nombre_nuevo(), false)
			return true
	return false
