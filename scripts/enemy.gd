extends CharacterBody3D
class_name Enemy
## Soldado alemán (todavía sin moverse de su puesto).
## - Si ve al jugador, se gira y le dispara según su arma: el Kar98k tiro a
##   tiro, la MP40 y el StG44 en ráfagas cortas, la MG42 en ráfagas largas.
## - Si tiene sacos de arena o un muro bajo delante, se esconde detrás y se
##   asoma de rodillas para disparar.
## - Algunos lanzan granadas de palo cuando el jugador está a media distancia.
## - Un tiro de Garand en el cuerpo lo derriba; en la cabeza vale doble (y el
##   casco sale volando).
## El cuerpo y sus animaciones están en soldado.gd.

@export var health := 100.0
@export var sight_range := 55.0
@export var damage := 12.0                  # daño de un tiro que acierta (fusil)
@export var reaction_time := 1.4            # segundos que tarda en disparar tras verte
@export var fire_interval := Vector2(3.0, 5.0)
@export var accuracy := 1.0                 # multiplicador de puntería (1 = normal)
## Arma que lleva (y que bota al morir). Vacío = al azar (Armas.BOTIN_ALEMAN).
@export var arma := ""
@export var granadas := -1                  # -1 = al azar (0 o 1)

var dead := false
var cuerpo: Soldado

var _player: Player
var _sees := false
var _alert := 0.0
var _los_timer := 0.0
var _fire_timer := 0.0
var _rafaga := 0                # balas que quedan en la ráfaga en curso
var _rafaga_t := 0.0
var _cobertura := false         # hay algo bajo delante para esconderse
var _asomado := 0.0             # >0: tiempo que le queda asomado
var _capsula: CapsuleShape3D
var _col_cuerpo: CollisionShape3D
var _col_cabeza: CollisionShape3D

static var _ultima_granada := -100.0   # segundos (Game.elapsed) de la última granada alemana


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4          # capa 3: enemigos
	collision_mask = 1 | 2
	_fire_timer = randf_range(fire_interval.x, fire_interval.y) * 0.5
	if arma == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		arma = Armas.botin_aleman(rng)
	if granadas < 0:
		granadas = 1 if randf() < 0.5 else 0
	_los_timer = randf() * 0.3
	cuerpo = Soldado.new()
	cuerpo.bando = "aleman"
	cuerpo.arma = arma
	add_child(cuerpo)
	_crear_colisiones()
	_buscar_cobertura.call_deferred()


func _crear_colisiones() -> void:
	# Forma 0 = cuerpo, forma 1 = cabeza (tiro a la cabeza). Siguen a la pose.
	_col_cuerpo = CollisionShape3D.new()
	_capsula = CapsuleShape3D.new()
	_capsula.radius = 0.3
	_capsula.height = 1.48
	_col_cuerpo.shape = _capsula
	_col_cuerpo.position.y = 0.74
	add_child(_col_cuerpo)
	_col_cabeza = CollisionShape3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = 0.17
	_col_cabeza.shape = esfera
	_col_cabeza.position.y = 1.64
	add_child(_col_cabeza)


## ¿Hay un obstáculo bajo (sacos, muro) justo delante, hacia la playa?
func _buscar_cobertura() -> void:
	var space := get_world_3d().direct_space_state
	var frente := -global_basis.z
	var bajo := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0),
		global_position + Vector3(0, 0.5, 0) + frente * 2.0, 1)
	var alto := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.15, 0),
		global_position + Vector3(0, 1.15, 0) + frente * 2.0, 1)
	_cobertura = not space.intersect_ray(bajo).is_empty() and space.intersect_ray(alto).is_empty()
	cuerpo.pose = "agachado" if _cobertura else "reposo"


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	_seguir_pose()
	if _player.dead:
		cuerpo.pose = "agachado" if _cobertura else "reposo"
		return

	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.3
		_sees = _can_see_player()

	if _rafaga > 0:   # ráfaga en curso
		_rafaga_t -= delta
		if _rafaga_t <= 0.0:
			_rafaga -= 1
			_rafaga_t = Armas.datos(arma)["interval"] * randf_range(1.0, 1.4)
			_shoot()

	if _sees:
		_alert += delta
		var to := _player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), delta * 4.0)
		cuerpo.apuntar_a = _player.head.global_position - Vector3(0, 0.3, 0)
		if not _cobertura:
			cuerpo.pose = "pie" if _alert > 0.3 else "reposo"
		if _alert >= reaction_time:
			_fire_timer -= delta
			# Desde la cobertura se asoma un poco antes de disparar
			if _cobertura and _fire_timer < 0.7 and _asomado <= 0.0:
				_asomado = 0.7 + _duracion_rafaga() + randf_range(0.4, 1.0)
			if _fire_timer <= 0.0 and _rafaga == 0:
				_fire_timer = randf_range(fire_interval.x, fire_interval.y)
				if not _intentar_granada(to.length()):
					_empezar_rafaga()
	else:
		_alert = maxf(_alert - delta * 0.5, 0.0)
		if not _cobertura and _alert < 0.2:
			cuerpo.pose = "reposo"

	if _cobertura:
		_asomado -= delta
		cuerpo.pose = "rodilla" if _asomado > 0.0 or _rafaga > 0 else "agachado"


## Las formas de choque siguen al cuerpo (agachado no se le puede pegar igual).
func _seguir_pose() -> void:
	var alto: float = {"reposo": 1.48, "pie": 1.48, "rodilla": 1.12, "agachado": 0.8}[cuerpo.pose]
	_capsula.height = lerpf(_capsula.height, alto, 0.15)
	_col_cuerpo.position.y = _capsula.height / 2.0
	_col_cabeza.global_position = cuerpo.pos_cabeza()


func _duracion_rafaga() -> float:
	var d := Armas.datos(arma)
	return d["interval"] * _balas_por_rafaga() * 1.2 if d["auto"] else 0.0


func _balas_por_rafaga() -> int:
	match arma:
		"mg42": return randi_range(8, 14)
		"mp40", "stg44": return randi_range(3, 6)
		_: return 1


func _empezar_rafaga() -> void:
	_rafaga = _balas_por_rafaga()
	_rafaga_t = 0.0 if not _cobertura else 0.35   # si se está asomando, espera a apuntar


func _can_see_player() -> bool:
	# Desde la cobertura mira por encima de los sacos (altura de rodillas)
	var eye := global_position + Vector3(0, 1.15 if _cobertura else 1.6, 0)
	var target := _player.head.global_position
	if eye.distance_to(target) > sight_range:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, target, 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == _player


func _shoot() -> void:
	var d := Armas.datos(arma)
	var auto: bool = d["auto"]
	var from := cuerpo.boca.global_position
	var target := _player.head.global_position - Vector3(0, 0.35, 0)
	var dist := from.distance_to(target)
	var chance := lerpf(0.35, 0.05, clampf(dist / sight_range, 0.0, 1.0)) * accuracy
	if auto:
		chance *= 0.4      # las ráfagas son menos precisas, pero son muchas balas
	if _player.crouching:
		chance *= 0.6
	if _player.sprinting:
		chance *= 0.6
	elif Vector2(_player.velocity.x, _player.velocity.z).length() > 2.0:
		chance *= 0.75   # moverse también ayuda
	var hits := randf() < chance

	if not hits:  # tiro errado: pasa cerca y pega en otra parte
		var side := (target - from).cross(Vector3.UP).normalized()
		target += side * randf_range(-1.6, 1.6) + Vector3(0, randf_range(-0.9, 0.6), 0)

	var dir := (target - from).normalized()
	var end := from + dir * (dist + (0.0 if hits else 30.0))
	if not hits:
		var q := PhysicsRayQueryParameters3D.create(from, end, 1)
		var w := get_world_3d().direct_space_state.intersect_ray(q)
		if not w.is_empty():
			end = w["position"]
			Game.dust(end, w["normal"])

	Game.play_at("pistol" if arma in ["mp40", "luger"] else "rifle_far", from, 2.0 if not auto else 0.0)
	Game.tracer(from, end)
	cuerpo.disparo()
	if hits:
		_player.take_damage(damage * (0.55 if auto else 1.0), global_position)


## Granada de palo: si el jugador está entre 9 y 26 m, y nadie lanzó una hace poco.
func _intentar_granada(dist: float) -> bool:
	if granadas <= 0 or dist < 9.0 or dist > 26.0 or Game.elapsed - _ultima_granada < 9.0:
		return false
	if randf() > 0.35:
		return false
	granadas -= 1
	_ultima_granada = Game.elapsed
	_asomado = 1.2
	var g := Grenade.new()
	g.modelo_aleman()
	get_parent().add_child(g)
	var desde := cuerpo.pos_cabeza() + Vector3(0, 0.3, 0) - global_basis.z * 0.5
	g.global_position = desde
	g.add_collision_exception_with(self)
	# Tiro parabólico al jugador (con error de hasta 3 m)
	var blanco := _player.global_position + Vector3(randf_range(-3, 3), 0.1, randf_range(-3, 3))
	var t := clampf(dist / 13.0, 0.9, 2.2)
	var v := (blanco - desde - 0.5 * Vector3(0, -9.8, 0) * t * t) / t
	g.linear_velocity = v
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))
	Game.play_at("throw", desde, 0.0)
	Game.say("[¡GRANADA!]", Game.COLOR_BAD)
	return true


## Recibe un impacto (bala o explosión).
func hit(amount: float, headshot: bool, pos: Vector3, dir: Vector3) -> void:
	if dead:
		return
	health -= amount * (2.0 if headshot else 1.0)
	Game.blood(pos)
	cuerpo.impacto(dir)
	_alert = maxf(_alert, reaction_time * 0.5)  # se pone alerta al recibir fuego
	if health <= 0.0:
		_die(dir, headshot)


func _die(dir: Vector3, headshot: bool) -> void:
	dead = true
	_rafaga = 0
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	Game.say("[ENEMIGO ABATIDO]" if not headshot else "[ABATIDO - TIRO A LA CABEZA]")
	if get_tree().get_nodes_in_group("enemies").is_empty():
		Game.say("[ZONA DESPEJADA]", Game.COLOR_GOOD)
	cuerpo.morir(dir, headshot)
	# Suelta su arma al lado (con algo de munición)
	var d := Armas.datos(arma)
	var lado := global_basis.x * randf_range(-0.6, 0.6) + dir.normalized() * 0.5
	ArmaSuelta.soltar(get_parent(), global_position + Vector3(lado.x, 0.05, lado.z), arma,
		randi_range(int(d["mag"]) / 2, int(d["mag"])), int(d["mag"]))
