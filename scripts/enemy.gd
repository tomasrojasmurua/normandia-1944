extends CharacterBody3D
class_name Enemy
## Soldado alemán simple (provisional, sin IA de movimiento todavía).
## Se queda en su posición; si ve al jugador, se gira y le dispara.
## Un tiro de Garand en el cuerpo lo derriba; en la cabeza vale doble.
## Para colocarlos: duplica un nodo "Enemy" en main.tscn y muévelo en el editor.

@export var health := 100.0
@export var sight_range := 55.0
@export var damage := 12.0
@export var reaction_time := 1.4            # segundos que tarda en disparar tras verte
@export var fire_interval := Vector2(3.0, 5.0)
@export var accuracy := 1.0                 # multiplicador de puntería (1 = normal)
## Arma que lleva (y que bota al morir). Vacío = al azar (Armas.BOTIN_ALEMAN).
@export var arma := ""

var dead := false

var _model: Node3D
var _rifle: Array[Node3D] = []
var _muzzle: Node3D
var _flash: Node3D
var _player: Player
var _sees := false
var _alert := 0.0
var _los_timer := 0.0
var _fire_timer := 0.0


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4          # capa 3: enemigos
	collision_mask = 1 | 2
	_fire_timer = randf_range(fire_interval.x, fire_interval.y)
	if arma == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		arma = Armas.botin_aleman(rng)
	_los_timer = randf() * 0.3
	_build()


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	if _player.dead:
		return

	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.3
		_sees = _can_see_player()

	if _sees:
		_alert += delta
		var to := _player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), delta * 4.0)
		if _alert >= reaction_time:
			_fire_timer -= delta
			if _fire_timer <= 0.0:
				_fire_timer = randf_range(fire_interval.x, fire_interval.y)
				_shoot()
	else:
		_alert = maxf(_alert - delta * 0.5, 0.0)


func _can_see_player() -> bool:
	var eye := global_position + Vector3(0, 1.6, 0)
	var target := _player.head.global_position
	if eye.distance_to(target) > sight_range:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, target, 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == _player


func _shoot() -> void:
	var from := _muzzle.global_position
	var target := _player.head.global_position - Vector3(0, 0.35, 0)
	var dist := from.distance_to(target)
	var chance := lerpf(0.35, 0.05, clampf(dist / sight_range, 0.0, 1.0)) * accuracy
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

	Game.play_at("rifle_far", from, 2.0)
	Game.tracer(from, end)
	_flash.visible = true
	get_tree().create_timer(0.06).timeout.connect(func() -> void: _flash.visible = false)
	if hits:
		_player.take_damage(damage, global_position)


## Recibe un impacto (bala o explosión).
func hit(amount: float, headshot: bool, pos: Vector3, dir: Vector3) -> void:
	if dead:
		return
	health -= amount * (2.0 if headshot else 1.0)
	Game.blood(pos)
	_alert = maxf(_alert, reaction_time * 0.5)  # se pone alerta al recibir fuego
	if health <= 0.0:
		_die(dir, headshot)


func _die(dir: Vector3, headshot: bool) -> void:
	dead = true
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	_flash.visible = false
	Game.say("[ENEMIGO ABATIDO]" if not headshot else "[ABATIDO - TIRO A LA CABEZA]")
	if get_tree().get_nodes_in_group("enemies").is_empty():
		Game.say("[ZONA DESPEJADA]", Game.COLOR_GOOD)
	# Cae en la dirección del impacto
	var local := global_transform.basis.inverse() * dir
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_model, "rotation", Vector3(signf(local.z if absf(local.z) > 0.1 else 1.0) * PI / 2, 0, randf_range(-0.3, 0.3)), 0.45)
	tw.parallel().tween_property(_model, "position:y", 0.1, 0.45)
	# Suelta su arma al lado (con algo de munición)
	for n in _rifle:
		n.visible = false
	var d := Armas.datos(arma)
	var lado := global_basis.x * randf_range(-0.6, 0.6) + dir.normalized() * 0.5
	ArmaSuelta.soltar(get_parent(), global_position + Vector3(lado.x, 0.05, lado.z), arma,
		randi_range(int(d["mag"]) / 2, int(d["mag"])), int(d["mag"]))


func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	var coat := Game.material(Color(0.37, 0.39, 0.33))      # feldgrau
	var trousers := Game.material(Color(0.32, 0.33, 0.29))
	var helmet := Game.material(Color(0.27, 0.3, 0.26))
	var skin := Game.material(Color(0.78, 0.58, 0.46))
	var black := Game.material(Color(0.09, 0.08, 0.07))
	var wood := Game.material(Color(0.4, 0.25, 0.13))
	var metal := Game.material(Color(0.15, 0.15, 0.16))
	var m := _model
	Game.box(m, Vector3(0.14, 0.12, 0.24), Vector3(0.1, 0.06, -0.03), black)    # botas
	Game.box(m, Vector3(0.14, 0.12, 0.24), Vector3(-0.1, 0.06, -0.03), black)
	Game.box(m, Vector3(0.14, 0.75, 0.16), Vector3(0.1, 0.5, 0), trousers)      # piernas
	Game.box(m, Vector3(0.14, 0.75, 0.16), Vector3(-0.1, 0.5, 0), trousers)
	Game.box(m, Vector3(0.42, 0.58, 0.24), Vector3(0, 1.16, 0), coat)           # torso
	Game.box(m, Vector3(0.44, 0.06, 0.26), Vector3(0, 0.9, 0), black)           # cinturón
	Game.box(m, Vector3(0.1, 0.08, 0.05), Vector3(0.12, 0.95, -0.14), black)    # cartucheras
	Game.box(m, Vector3(0.1, 0.08, 0.05), Vector3(-0.12, 0.95, -0.14), black)
	Game.box(m, Vector3(0.11, 0.11, 0.44), Vector3(0.19, 1.32, -0.2), coat)     # brazos (apuntando)
	Game.box(m, Vector3(0.11, 0.11, 0.5), Vector3(-0.1, 1.3, -0.3), coat, Vector3(0, -20, 0))
	Game.box(m, Vector3(0.2, 0.22, 0.22), Vector3(0, 1.58, 0), skin)            # cabeza
	Game.box(m, Vector3(0.27, 0.12, 0.29), Vector3(0, 1.73, 0), helmet)         # casco Stahlhelm
	Game.box(m, Vector3(0.32, 0.08, 0.34), Vector3(0, 1.66, 0.02), helmet)
	_rifle.append(Game.box(m, Vector3(0.05, 0.07, 0.95), Vector3(0.08, 1.4, -0.45), wood))     # fusil Kar98k
	_rifle.append(Game.box(m, Vector3(0.025, 0.025, 0.25), Vector3(0.08, 1.42, -1.0), metal))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.08, 1.42, -1.14)
	m.add_child(_muzzle)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.4)
	_flash = Game.box(_muzzle, Vector3(0.14, 0.14, 0.2), Vector3(0, 0, -0.08), fmat, Vector3(0, 0, 45))
	_flash.visible = false

	# Colisiones: forma 0 = cuerpo, forma 1 = cabeza (tiro a la cabeza)
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.48
	body.shape = capsule
	body.position.y = 0.74
	add_child(body)
	var head_col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.17
	head_col.shape = sphere
	head_col.position.y = 1.64
	add_child(head_col)
