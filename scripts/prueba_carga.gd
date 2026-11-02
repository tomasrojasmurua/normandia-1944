extends Node
class_name PruebaCarga
## Prueba de carga (menú principal → PRUEBA DE CARGA): llena la playa como
## quedaría con 4 jugadores, para medir en el celular si aguanta.
## - 16 americanos: el jugador + 15 con IA (las 4 escuadras de escuadras.gd).
## - 30 alemanes en las trincheras y sacos de arena.
## - Artillería cayendo por la playa cada 1–2,5 s (solo efecto y sonido).
## - Cuando muere alguien, llega otro: alemanes desde atrás, americanos desde
##   la orilla (como nuevas oleadas), así el combate no se acaba.
## - El jugador no muere (para poder medir tranquilo).
## El medidor de arriba a la izquierda muestra cuántos soldados hay vivos.

const ALEMANES := 30

var _t_refuerzo := 0.0
var _t_artilleria := 2.0
var _listo := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Game.say("[PRUEBA DE CARGA: 16 AMERICANOS, 30 ALEMANES]", Game.COLOR_INFO)


func _process(delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p:
		p.health = p.max_health
	if not Navegacion.listo:
		return
	if not _listo:
		_listo = true
		Aliado.dar_orden("avanzar")
	_t_refuerzo -= delta
	if _t_refuerzo <= 0.0:
		_t_refuerzo = 1.5
		_reponer()
	_t_artilleria -= delta
	if _t_artilleria <= 0.0:
		_t_artilleria = _rng.randf_range(1.0, 2.5)
		_granada_de_artilleria(p)


## Mantiene la cantidad de soldados (de a poco, para no trabar).
func _reponer() -> void:
	var main := get_parent()
	var alemanes := get_tree().get_nodes_in_group("enemies").size()
	var americanos := get_tree().get_nodes_in_group("aliados").size()
	Game.carga_texto = "SOLDADOS %d US + %d AL" % [americanos + 1, alemanes]
	var usados: Array = []
	for i in mini(3, ALEMANES - alemanes):
		nuevo_aleman(main, _rng, usados)
	# Los americanos los repone escuadras.gd (refuerzos ilimitados en esta prueba)


## Un alemán nuevo en una cobertura libre del lado alemán.
static func nuevo_aleman(main: Node, rng: RandomNumberGenerator, usados: Array) -> Enemy:
	var e := Enemy.new()
	e.arma = Armas.botin_aleman(rng)
	e.rol = "flanqueador" if rng.randf() < 0.2 else "defensor"
	e.granadas = 1 if rng.randf() < 0.3 else 0
	var pos := lugar_aleman(rng, usados)
	usados.append(pos)
	var enemigos := main.get_node_or_null("Enemies")
	(enemigos if enemigos else main).add_child(e)
	e.global_position = pos
	e.rotation.y = PI    # mirando al mar
	return e


## Un punto de cobertura libre del lado alemán que proteja hacia el mar.
static func lugar_aleman(rng: RandomNumberGenerator, usados: Array) -> Vector3:
	var libres: Array = []
	for c in Coberturas.puntos:
		var pos: Vector3 = c["pos"]
		var n: Vector3 = c["n"]
		if pos.z < -20.0 and n.z > 0.5 and not c["parcial"] and not pos in usados \
				and (c["ocupado"] == null or not is_instance_valid(c["ocupado"])):
			libres.append(pos)
	if libres.is_empty():
		return Navegacion.cerca_de(Vector3(rng.randf_range(-35, 35), 0, -46))
	return libres[rng.randi() % libres.size()]


## Explosión de artillería en la playa, lejos del jugador (solo efecto).
func _granada_de_artilleria(p: Player) -> void:
	var pos := Vector3(_rng.randf_range(-40, 40), 0.1, _rng.randf_range(-30, 9))
	if p and pos.distance_to(p.global_position) < 12.0:
		pos.x += 20.0 * signf(pos.x - p.global_position.x + 0.01)
	Game.play_at("explosion", pos, 4.0)
	Game._explosion_fx(pos)
	if p:
		var d := pos.distance_to(p.global_position)
		if d < 30.0:
			p.shake(0.8 * (1.0 - d / 30.0))
