extends Node
class_name Defensa
## La defensa alemana de la misión (sección 5, paso 3: más desafío).
## - Dos nidos de ametralladora MG42 en los flancos (no se mueven, ráfagas largas).
## - Morteros: cada 7–12 s cae uno cerca de algún grupo americano. Se oye el
##   silbido ~1,3 s antes en el lugar donde va a caer: hay tiempo para correr.
##   Rara vez apuntan al jugador, y entonces caen a unos metros (es un aviso).
## - Refuerzos: cada ~30 s llegan 3 alemanes desde atrás, hasta 18 en total.
## La playa queda despejada cuando no queda ningún alemán ni refuerzos por llegar.

const REFUERZOS := 18
const NIDOS := [Vector3(-24, 0, -31), Vector3(23, 0, -29)]

static var restantes := 0

var _rng := RandomNumberGenerator.new()
var _t_mortero := 22.0
var _t_refuerzo := 40.0
var _nidos_listos := false


func _ready() -> void:
	_rng.randomize()
	restantes = REFUERZOS


func _process(delta: float) -> void:
	if not Navegacion.listo:
		return
	if not _nidos_listos:
		_nidos_listos = true
		for n in NIDOS:
			_aleman(_cobertura_cerca(n, 6.0), "mg42", "fijo")
	_t_mortero -= delta
	if _t_mortero <= 0.0:
		_t_mortero = _rng.randf_range(7.0, 12.0)
		_mortero()
	_t_refuerzo -= delta
	if _t_refuerzo <= 0.0 and restantes > 0:
		_t_refuerzo = _rng.randf_range(25.0, 35.0)
		var usados: Array = []
		for i in mini(3, restantes):
			restantes -= 1
			var e := PruebaCarga.nuevo_aleman(get_parent(), _rng, usados)
			if e.global_position.z > -36.0:   # que lleguen desde atrás
				e.global_position = Navegacion.cerca_de(Vector3(e.global_position.x, 0, -47))
		Game.say("[REFUERZOS ALEMANES]", Game.COLOR_BAD)


func _aleman(pos: Vector3, arma: String, rol: String) -> void:
	var e := Enemy.new()
	e.arma = arma
	e.rol = rol
	e.granadas = 0
	var enemigos := get_parent().get_node_or_null("Enemies")
	(enemigos if enemigos else get_parent()).add_child(e)
	e.global_position = pos
	e.rotation.y = PI


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
	if b is Player and _rng.randf() < 0.6:   # al jugador lo eligen menos
		b = blancos[_rng.randi() % blancos.size()]
	var lejos := _rng.randf_range(5.0, 9.0) if b is Player else _rng.randf_range(1.5, 7.0)
	var ang := _rng.randf() * TAU
	var pos := b.global_position + Vector3(cos(ang), 0, sin(ang)) * lejos
	pos.y = 0.1
	Game.play_at("silbido", pos, 2.0)
	await get_tree().create_timer(1.3).timeout
	if is_inside_tree():
		Game.explode(pos, 6.0, 150.0)
