extends Combatiente
class_name Aliado
## Compañero de la escuadra (DeLuca, Hayes, Brennan). Obedece la orden de la
## escuadra (`Aliado.orden`, la cambia el jugador desde el HUD):
## - "seguir":   se mantiene cerca del jugador, en una cobertura que lo tape.
## - "avanzar":  salta de cobertura en cobertura hacia los alemanes, esperando
##               unos segundos en cada una (avanzan escalonados, no todos juntos).
## - "mantener": se queda donde está (solo cambia si lo flanquean).
## Dispara de verdad a los alemanes que ve (sus balas matan) y puede morir.
## Las balas del jugador lo atraviesan (sin fuego amigo), las explosiones no.
## En el cooperativo, los otros jugadores ocuparán estos lugares.

@export var nombre := "HAYES"

const ALCANCE := 60.0
const BUNKER := Vector3(0, 0, -42)

static var orden := "seguir"

var max_health := 100.0
var _player: Player
var _vista_t := 0.0
var _pensar_t := 0.0
var _fuego_t := 0.0
var _rafaga := 0
var _rafaga_t := 0.0
var _asomado := 0.0
var _espera_hasta := 0.0
var _ultimo_dano := -100.0
var _indice := 0
var _alemanes: Array[Vector3] = []   # dónde están (para no meterse encima)


static func dar_orden(o: String) -> void:
	orden = o
	Game.say({"seguir": "[ESCUADRA: SÍGANME]", "avanzar": "[ESCUADRA: AVANCEN]",
		"mantener": "[ESCUADRA: MANTENGAN POSICIÓN]"}.get(o, ""), Game.COLOR_GOOD)
	# Que reaccionen enseguida (cada uno un poco desfasado)
	var i := 0
	for a in Engine.get_main_loop().get_nodes_in_group("aliados"):
		a._pensar_t = 0.2 + i * 0.35
		a._espera_hasta = 0.0
		i += 1


func _ready() -> void:
	add_to_group("americanos")
	add_to_group("aliados")
	collision_layer = 16         # capa 5: compañeros (las balas del jugador no los tocan)
	collision_mask = 1
	if arma == "":
		arma = "garand"
	_indice = get_tree().get_nodes_in_group("aliados").size()
	_vista_t = randf() * 0.35
	_pensar_t = randf_range(0.5, 1.5)
	_fuego_t = randf_range(1.0, 3.0)
	amenaza = BUNKER
	_crear_cuerpo("aliado")
	tomar_cobertura_inicial.call_deferred()


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	_seguir_pose()
	if Game.elapsed - _ultimo_dano > 8.0 and health < max_health:
		health = minf(health + 3.0 * delta, max_health)

	_vista_t -= delta
	if _vista_t <= 0.0:
		_vista_t = 0.35
		objetivo = elegir_objetivo("enemies", ALCANCE)
		amenaza = objetivo.global_position if objetivo else _enemigo_conocido()

	if moviendo:     # corre en _process (combatiente.gd), cuadro a cuadro
		_rafaga = 0
		return

	_pensar_t -= delta
	if _pensar_t <= 0.0:
		_pensar_t = randf_range(0.8, 1.2)
		_pensar()
		if moviendo:
			return

	if _rafaga > 0:
		_rafaga_t -= delta
		if _rafaga_t <= 0.0:
			_rafaga -= 1
			_rafaga_t = Armas.datos(arma)["interval"] * randf_range(1.1, 1.5)
			if objetivo and not objetivo.dead:
				_disparar()

	if objetivo:
		var to := objetivo.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), delta * 5.0)
		cuerpo.apuntar_a = objetivo.pos_cabeza() - Vector3(0, 0.3, 0)
		if not en_cobertura:
			cuerpo.pose = "pie"
		_fuego_t -= delta
		if en_cobertura and _fuego_t < 0.6 and _asomado <= 0.0:
			_asomado = 0.6 + randf_range(1.0, 2.0)
		if _fuego_t <= 0.0 and _rafaga == 0:
			var d := Armas.datos(arma)
			if d["auto"]:
				_rafaga = randi_range(3, 6)
				_fuego_t = randf_range(2.0, 3.5)
			else:
				_rafaga = 1
				_fuego_t = randf_range(1.3, 2.6)
			_rafaga_t = 0.3 if en_cobertura else 0.0
	elif not en_cobertura:
		cuerpo.pose = "reposo"
		cuerpo.apuntar_a = Vector3.ZERO

	if en_cobertura:
		_asomado -= delta
		cuerpo.pose = "rodilla" if _asomado > 0.0 or _rafaga > 0 else "agachado"


## Dónde está el alemán vivo más cercano (aunque no lo vea): la escuadra sabe
## más o menos dónde está la línea enemiga.
func _enemigo_conocido() -> Vector3:
	var mejor := BUNKER
	var mejor_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var d := global_position.distance_to(e.global_position)
		if d < mejor_d:
			mejor_d = d
			mejor = e.global_position
	return mejor


# ================================================================ decidir

func _pensar() -> void:
	if not Navegacion.listo:
		return
	_alemanes.clear()
	for e in get_tree().get_nodes_in_group("enemies"):
		_alemanes.append(e.global_position)
	var flanqueado := not cobertura.is_empty() and Coberturas.protege(cobertura, amenaza) < 0.2
	match orden:
		"mantener":
			if flanqueado:
				_ir(_buscar(func(p: Dictionary, viaje: float) -> float:
					return -INF if viaje > 8.0 else -viaje))
		"seguir":
			var jugador := _player.global_position
			var lejos := global_position.distance_to(jugador)
			if lejos > 10.0 or cobertura.is_empty() or flanqueado:
				if not _ir(_buscar(func(p: Dictionary, viaje: float) -> float:
						var dj := jugador.distance_to(p["pos"])
						if dj < 2.0 or dj > 9.0:
							return -INF
						return -dj * 0.3 - viaje * 0.1)) and lejos > 10.0:
					_ir_suelto(jugador)
		"avanzar":
			if Game.elapsed < _espera_hasta and not flanqueado:
				return
			var mio := global_position.distance_to(amenaza)
			if not _ir(_buscar(func(p: Dictionary, viaje: float) -> float:
					var avance := mio - amenaza.distance_to(p["pos"])
					if viaje < 2.5 or viaje > 14.0 or avance < 2.5:
						return -INF
					return avance * 0.4 - viaje * 0.15)):
				_espera_hasta = Game.elapsed + 3.0   # no hay dónde: espera y vuelve a mirar


## Mejor cobertura que lo tape de la amenaza; `extra(p, viaje)` agrega su criterio.
func _buscar(extra: Callable) -> Dictionary:
	var yo := global_position
	return Coberturas.mejor(self, func(p: Dictionary) -> float:
		var pos: Vector3 = p["pos"]
		if absf(pos.y - yo.y) > 1.5:
			return -INF
		var prot := Coberturas.protege(p, amenaza)
		if prot < 0.35:
			return -INF
		for a in _alemanes:
			if a.distance_to(pos) < 11.0:
				return -INF      # demasiado cerca de un alemán
		var e: float = extra.call(p, yo.distance_to(pos))
		return e + prot * 2.0)


func _ir(p: Dictionary) -> bool:
	if p.is_empty() or p == cobertura:
		return false
	return ir_a(p)


## Sin coberturas cerca: va a un lado del jugador, aunque quede al descubierto.
func _ir_suelto(jugador: Vector3) -> void:
	var lado := _player.global_basis.x * (-3.0 + 3.0 * (_indice % 3)) + _player.global_basis.z * 2.5
	ir_a({"pos": Navegacion.cerca_de(jugador + lado)})


func _al_llegar() -> void:
	_espera_hasta = Game.elapsed + randf_range(4.0, 8.0)
	_fuego_t = minf(_fuego_t, randf_range(0.5, 1.5))


# ================================================================ disparar y recibir

func _disparar() -> void:
	var auto: bool = Armas.datos(arma)["auto"]
	var dist := global_position.distance_to(objetivo.global_position)
	var chance := lerpf(0.13, 0.025, clampf(dist / ALCANCE, 0.0, 1.0))
	if auto:
		chance *= 0.45
	chance *= objetivo.factor_blanco()
	if tiro_ia(objetivo, chance, -6.0):
		var pecho: Vector3 = objetivo.global_position + Vector3(0, 1.1, 0)
		var dir: Vector3 = (pecho - cuerpo.boca.global_position).normalized()
		objetivo.hit(Armas.datos(arma)["damage"], randf() < 0.1, pecho, dir)


func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	health -= amount
	_ultimo_dano = Game.elapsed
	var dir := (global_position - from_pos).normalized()
	cuerpo.impacto(dir)
	Game.blood(global_position + Vector3(0, 1.1, 0))
	if health <= 0.0:
		_morir(dir)


func _morir(dir: Vector3) -> void:
	dead = true
	moviendo = false
	_rafaga = 0
	Coberturas.liberar(self)
	remove_from_group("americanos")
	remove_from_group("aliados")
	collision_layer = 0
	collision_mask = 0
	Game.say("[%s CAÍDO]" % nombre, Game.COLOR_BAD)
	cuerpo.andar = ""
	cuerpo.morir(dir, false)
	_soltar_arma(dir)
