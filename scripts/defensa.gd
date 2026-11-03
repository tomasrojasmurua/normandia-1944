extends Node
class_name Defensa
## La defensa alemana de la misión (sección 5, paso 3: más desafío).
## - Dos nidos de ametralladora MG42 en los flancos (no se mueven, ráfagas largas).
## - Morteros: cada 7–12 s cae uno cerca de algún grupo americano. Se oye el
##   silbido ~1,3 s antes en el lugar donde va a caer: hay tiempo para correr.
##   Rara vez apuntan al jugador, y entonces caen a unos metros (es un aviso).
## - Refuerzos: cada ~30 s llegan 3 alemanes desde atrás, hasta 18 en total.
## La playa queda despejada cuando no queda ningún alemán ni refuerzos por llegar.

## Nidos, refuerzos y morteros vienen de los datos de la misión (Misiones).
static var NIDOS: Array = []

static var restantes := 0
static var actual: Defensa

var nidos: Array = []           # los dos tiradores de MG42 (para los objetivos)
var migrada := -1               # traspaso de anfitrión: refuerzos que quedaban (no crear nidos)

var _rng := RandomNumberGenerator.new()
var _t_mortero := 22.0
var _t_refuerzo := 40.0
var _nidos_listos := false


func _ready() -> void:
	actual = self
	_rng.randomize()
	NIDOS = Misiones.dato("nidos")
	restantes = Misiones.dato("refuerzos_alemanes")
	if migrada >= 0:
		restantes = migrada
		_nidos_listos = true
		_t_mortero = 8.0
		_t_refuerzo = 20.0


func _process(delta: float) -> void:
	if not Navegacion.listo:
		return
	if not _nidos_listos:
		_nidos_listos = true
		for n in NIDOS:
			nidos.append(_aleman(_cobertura_cerca(n, 6.0), "mg42", "fijo"))
	var mort = Misiones.actual().get("morteros", null)
	_t_mortero -= delta
	if mort != null and _t_mortero <= 0.0:
		_t_mortero = _rng.randf_range(mort.x, mort.y)
		_mortero()
	_t_refuerzo -= delta
	if _t_refuerzo <= 0.0 and restantes > 0:
		_t_refuerzo = _rng.randf_range(25.0, 35.0)
		var usados: Array = []
		for i in mini(3, restantes):
			restantes -= 1
			var e := PruebaCarga.nuevo_aleman(get_parent(), _rng, usados)
			var rz: float = Misiones.dato("refuerzo_z")
			if e.global_position.z > rz + 11.0:   # que lleguen desde atrás
				e.global_position = Navegacion.cerca_de(Vector3(e.global_position.x, 0, rz))
		Red.anunciar("[REFUERZOS ALEMANES]", Game.COLOR_BAD)


func _aleman(pos: Vector3, arma: String, rol: String) -> Enemy:
	var e := Enemy.new()
	e.arma = arma
	e.rol = rol
	e.granadas = 0
	var enemigos := get_parent().get_node_or_null("Enemies")
	(enemigos if enemigos else get_parent()).add_child(e)
	e.global_position = pos
	e.rotation.y = PI
	return e


## Otro alemán toma la MG42 de un nido (nadie llegó a tomarlo a tiempo).
func reponer_nido(k: int) -> void:
	if not Navegacion.listo:
		return
	var e := _aleman(_cobertura_cerca(NIDOS[k], 6.0), "mg42", "fijo")
	while nidos.size() <= k:
		nidos.append(null)
	nidos[k] = e


func _cobertura_cerca(pos: Vector3, radio: float) -> Vector3:
	var mejor := pos
	var mejor_d := radio
	for c in Coberturas.puntos:
		var n: Vector3 = c["n"]
		var d: float = pos.distance_to(c["pos"])
		if n.z > 0.5 and d < mejor_d and (c["ocupado"] == null or not is_instance_valid(c["ocupado"])):
			mejor_d = d
			mejor = c["pos"]
	return mejor


## Un mortero: silbido y, 1,3 s después, la explosión.
func _mortero() -> void:
	var blancos := get_tree().get_nodes_in_group("americanos").filter(
		func(b: Node) -> bool: return not b.dead and b.global_position.z < 9.0)
	if blancos.is_empty():
		return
	var b: Node3D = blancos[_rng.randi() % blancos.size()]
	if (b is Player or b is JugadorRemoto) and _rng.randf() < 0.6:   # al jugador lo eligen menos
		b = blancos[_rng.randi() % blancos.size()]
	var lejos := _rng.randf_range(5.0, 9.0) if (b is Player or b is JugadorRemoto) else _rng.randf_range(1.5, 7.0)
	var ang := _rng.randf() * TAU
	var pos := b.global_position + Vector3(cos(ang), 0, sin(ang)) * lejos
	pos.y = 0.1
	Game.play_at("silbido", pos, 2.0)
	Red.silbido(pos)
	await get_tree().create_timer(1.3).timeout
	if is_inside_tree():
		Game.explode(pos, 6.0, 150.0)
