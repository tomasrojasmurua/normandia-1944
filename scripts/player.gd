extends CharacterBody3D
class_name Player
## Soldado controlado por el jugador (vista en primera persona).
## PC: WASD moverse, mouse mirar, clic izq. disparar, clic der. apuntar,
##     R recargar, 1/2 o rueda cambiar arma, G granada, Shift correr,
##     C agacharse, espacio saltar.
## Celular: ver touch_controls.gd.

@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var crouch_speed := 2.2
@export var jump_velocity := 4.2
@export var mouse_sensitivity := 0.0025
@export var touch_look_sensitivity := 0.006
@export var aim_friction := 0.55      # 1 = sin asistencia al apuntar en el celular
@export var max_health := 100.0
@export var regen_delay := 5.0        # segundos sin recibir daño antes de recuperarse
@export var regen_per_second := 8.0   # 0 = sin recuperación
## Daño máximo de un solo tiro: un balazo de fusil te deja grave (30 de vida),
## el segundo te mata. Los alemanes, en cambio, caen de un tiro.
const DANO_MAX_TIRO := 70.0
@export var grenades := 3

const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.15
const STAND_HEAD := 1.6
const CROUCH_HEAD := 1.0
## Cuerpo a tierra: manteniendo AGACHAR ~0,6 s. Se arrastra lento, casi no
## asoma (las balas pegan mucho menos) y detrás de un talud no lo ven.
const PRONE_HEIGHT := 0.72
const PRONE_HEAD := 0.38
const PRONE_SPEED := 0.9
const PRONE_HOLD := 0.6

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapons: Weapons = $Head/Camera3D/Weapons
@onready var collision: CollisionShape3D = $Collision

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var health := 100.0
var supresion := 0.0                  # 0..1: balas pasando cerca (oscurece la vista y abre la puntería)
var nombre := "MURPHY"                # el soldado que manejas (cambia al tomar el lugar de otro)
var dead := false
var crouching := false
var prone := false
var touch_crouch_held := false        # el botón AGACHAR del celular, apretado
var _agachar_desde := -1.0            # segundos que lleva apretado AGACHAR (-1 = suelto)
var sprinting := false
var aiming := false
var touch_fire := false              # el dedo está sobre FUEGO (para las automáticas)
var pickup_near: Node = null         # arma en el suelo que se puede recoger (ArmaSuelta)
var bob_time := 0.0
var damage_flash := 0.0     # el HUD pinta la pantalla de rojo
var hit_angle := 0.0        # dirección del último disparo recibido (HUD)
var hit_indicator := 0.0

# Valores que escriben los controles táctiles (touch_controls.gd).
var touch_move := Vector2.ZERO
var touch_jump := false
var touch_aim := false
var touch_hold_aim := false          # FUEGO mantenido en modo "al soltar": apunta mientras dure
var touch_sprint := false

var _since_hit := 99.0
var _shake := 0.0
var _capsule: CapsuleShape3D
var _base_fov := 70.0
var _throw_pending := false


func _ready() -> void:
	add_to_group("player")
	add_to_group("americanos")
	collision_layer = 2          # capa 2: jugador
	collision_mask = 1 | 4 | 64 | 256  # 256 = caja de los modelos; choca con escenario (1), enemigos (3) y el alambre de púas (7)
	health = max_health
	_capsule = collision.shape.duplicate()
	collision.shape = _capsule
	_base_fov = camera.fov
	Game.reset_mission()
	Game.say("[DESEMBARCO - OMAHA]")


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# En PC: clic para capturar el mouse (ese clic no dispara). Esc = pausa (pausa.gd).
	if event is InputEventMouseButton and event.pressed and not captured \
			and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and captured:
		var d: Vector2 = event.relative * mouse_sensitivity * (0.55 if aiming else 1.0)
		weapons.player_looked(d.y)
		look(d)
	elif event.is_action_pressed("fire") and captured:
		weapons.pull_trigger()
	elif event.is_action_pressed("reload"):
		weapons.reload()
	elif event.is_action_pressed("weapon_1"):
		weapons.select(0)
	elif event.is_action_pressed("weapon_2"):
		weapons.select(1)
	elif event.is_action_pressed("weapon_next"):
		weapons.next_weapon()
	elif event.is_action_pressed("grenade"):
		preparar_granada()
	elif event.is_action_released("grenade"):
		soltar_granada()
	elif event.is_action_pressed("use"):
		recoger()
	elif event.is_action_pressed("crouch"):
		crouch_press()
	elif event.is_action_released("crouch"):
		_agachar_desde = -1.0
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G:
		grillo()


## Misión 2: el grillo de los paracaidistas (clic-clac). Los compañeros que
## quedaron dispersos tras el choque contestan con dos clics desde donde
## están: se oye hacia dónde ir (y sale escrito, por si no hay audífonos).
var _grillo_listo := 0.0


func grillo() -> void:
	if dead or Game.elapsed < _grillo_listo:
		return
	_grillo_listo = Game.elapsed + 2.5
	Game.play("grillo", 0.0)
	var n := 0
	for a in get_tree().get_nodes_in_group("aliados"):
		if a.dead or not a.has_meta("perdido"):
			continue
		if global_position.distance_to(a.global_position) > 120.0:
			continue
		n += 1
		_contesta_grillo(a, 0.8 + n * 0.7)
	if n == 0:
		Game.say("[CLIC-CLAC... NADIE CONTESTA]", Game.COLOR_INFO)


func _contesta_grillo(a: Node3D, retraso: float) -> void:
	await get_tree().create_timer(retraso).timeout
	if not is_instance_valid(a) or a.dead or not a.has_meta("perdido"):
		return
	Game.play_at("grillo2", a.global_position + Vector3(0, 1.0, 0), 8.0)
	var d := a.global_position - global_position
	var dist := Vector2(d.x, d.z).length()
	var plano := Vector3(d.x, 0, d.z).normalized()
	var ang := rad_to_deg((-global_basis.z).angle_to(plano))
	var donde := "ADELANTE"
	if ang > 120.0:
		donde = "ATRÁS"
	elif ang > 35.0:
		donde = "A TU DERECHA" if plano.dot(global_basis.x) > 0.0 else "A TU IZQUIERDA"
	Game.say("[CLIC-CLAC, CLIC-CLAC: %s, ~%d M]" % [donde, int(roundf(dist / 10.0) * 10.0)], Game.COLOR_GOOD)


## Gira la cámara. `delta` en radianes (x = horizontal, y = vertical).
func look(delta: Vector2) -> void:
	if dead:
		return
	rotate_y(-delta.x)
	head.rotate_x(-delta.y)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))


func look_touch(pixels: Vector2) -> void:
	var d := pixels * touch_look_sensitivity * (0.5 if aiming else 1.0)
	# Asistencia leve: la mira se frena al pasar sobre un enemigo (no apunta sola)
	if weapons.enemy_under_crosshair():
		d *= aim_friction
	weapons.player_looked(d.y)
	look(d)


## Recoge el arma del suelo que está más cerca (tecla E o botón TOMAR).
func recoger() -> void:
	if dead or pickup_near == null or not is_instance_valid(pickup_near) or weapons.busy():
		return
	pickup_near.tomar(self)


func toggle_crouch() -> void:
	if not dead:
		_set_crouch(not crouching)


## AGACHAR: un toque agacha o levanta; mantenido, cuerpo a tierra. Desde el
## piso, un toque te deja agachado.
func crouch_press() -> void:
	if dead:
		return
	if prone:
		_set_crouch(true)
		return
	toggle_crouch()
	_agachar_desde = 0.0


func _set_crouch(on: bool) -> void:
	crouching = on
	prone = false
	_capsule.height = CROUCH_HEIGHT if on else STAND_HEIGHT
	collision.position.y = _capsule.height / 2.0


func _set_prone() -> void:
	crouching = true
	prone = true
	_capsule.height = PRONE_HEIGHT
	collision.position.y = _capsule.height / 2.0
	Game.say("[CUERPO A TIERRA]", Game.COLOR_INFO)


## Granada en dos tiempos: al apretar GRANADA se saca el seguro y queda en la
## mano (se ve la curva de por dónde va a ir); al soltar, se lanza. Como la
## Mk 2 de verdad, la mecha no corre mientras se aprieta la palanca.
func preparar_granada() -> void:
	if dead or grenades <= 0 or weapons.busy() or _throw_pending:
		if grenades <= 0 and not dead:
			Game.say("[SIN GRANADAS]", Game.COLOR_BAD)
		return
	weapons.sacar_granada()
	Game.play("click", -2.0, 0.7)      # el seguro


func soltar_granada() -> void:
	if not weapons.granada_en_mano:
		return
	weapons.soltar_granada()
	grenades -= 1
	_throw_pending = true
	Game.play("throw", -2.0)
	await get_tree().create_timer(0.1).timeout
	_throw_pending = false
	if dead:
		return
	var g := Grenade.new()
	get_tree().current_scene.add_child(g)
	var salida := granada_salida()
	g.global_position = salida[0]
	g.linear_velocity = salida[1]
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	Game.say("[GRANADA!]")
	g.del_jugador = true


## Dónde sale la granada y con qué velocidad (el HUD dibuja su curva con esto).
func granada_salida() -> Array:
	var fwd := -camera.global_basis.z
	return [camera.global_position + fwd * 0.5 - camera.global_basis.y * 0.1,
		fwd * 13.0 + Vector3.UP * 3.5 + velocity * 0.5]


## Toque corto (sin mantener): saca y lanza enseguida.
func throw_grenade() -> void:
	preparar_granada()
	soltar_granada()


## Para los soldados de IA: dónde apuntar y cuánto cuesta pegarte.
func pos_cabeza() -> Vector3:
	return head.global_position


func factor_blanco() -> float:
	var f := 1.0
	if prone:
		f *= 0.35
	elif crouching:
		f *= 0.6
	if sprinting:
		f *= 0.6
	elif Vector2(velocity.x, velocity.z).length() > 2.0:
		f *= 0.75   # moverse también ayuda
	return f


func take_damage(amount: float, from_pos: Vector3, es_bala := true) -> void:
	if dead or amount <= 0.0:
		return
	if not Game.prueba_carga:   # en la prueba de carga el jugador no muere
		health -= minf(amount, DANO_MAX_TIRO) if es_bala else amount
	_since_hit = 0.0
	damage_flash = 1.0
	shake(0.25)
	var local := global_transform.basis.inverse() * (from_pos - global_position)
	hit_angle = atan2(local.x, -local.z)
	hit_indicator = 1.5
	Game.play("hurt")
	if health <= 0.0:
		_die()


## Una bala pasó cerca (a `dist` metros de la cabeza): asusta.
func casi(dist: float) -> void:
	if dead:
		return
	var f := clampf(1.0 - dist / 2.5, 0.15, 1.0)
	supresion = minf(supresion + 0.18 * f, 1.0)
	shake(0.12 * f)
	Game.play("zumbido", -8.0 + 6.0 * f, randf_range(0.85, 1.2))
	Fragor.casi(global_position)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Al caer, como en Hamburger Hill: tomas el lugar del compañero vivo más
## cercano de tu escuadra. Si no queda ninguno, vuelves desde la orilla con
## un refuerzo de tu escuadra; si tampoco quedan, quedas fuera (y si todos los
## jugadores están fuera, la misión fracasa: objetivos.gd).
## En un invitado del cooperativo lo decide el anfitrión (Red.pedir_relevo).
var esperando_relevo := false


func _die() -> void:
	if weapons.granada_en_mano:   # cae con la granada sin seguro: queda en el suelo, viva
		weapons.granada_en_mano = false
		var g := Grenade.new()
		get_tree().current_scene.add_child(g)
		g.global_position = global_position + Vector3(0, 0.8, 0)
		g.linear_velocity = Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1))
		g.del_jugador = true
		grenades -= 1
	dead = true
	health = 0.0
	weapons.visible = false
	Game.caidos += 1
	Game.say("[%s CAÍDO]" % nombre, Game.COLOR_BAD)
	var donde := global_transform
	esperando_relevo = true
	# Un médico de tu compañía cerca te levanta (una vez por misión cada uno)
	var med := Escuadras.especialista("medico", global_position, 30.0) if not Red.es_invitado() else null
	if med and not med.has_meta("uso_medico"):
		med.set_meta("uso_medico", true)
		Game.say("[%s: ¡AGUANTA, SARGENTO! TE ESTOY ATENDIENDO]" % med.nombre, Game.COLOR_GOOD)
		await get_tree().create_timer(5.0).timeout
		if not is_inside_tree():
			return
		if is_instance_valid(med) and not med.dead:
			_reaparecer(global_position, 0.5)
			Game.say("[%s TE LEVANTÓ. SOLO TIENE PARA UNA VEZ]" % med.nombre, Game.COLOR_GOOD)
			return
	if Compania.en_mision:
		Compania.caido(nombre)    # si eras un hombre de tu compañía, ese cayó
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree():
		return
	_dejar_cuerpo(donde)
	if Red.es_invitado():
		Red.pedir_relevo()
		await get_tree().create_timer(5.0).timeout
		if is_inside_tree() and dead and esperando_relevo:
			_reaparecer()      # el anfitrión no contestó: a la orilla
		return
	var relevo := Escuadras.relevo_jugador()
	if relevo:
		_tomar_lugar(relevo)
	elif Escuadras.gastar_refuerzo(Escuadras.mi_escuadra):
		volver_desde_orilla()
	else:
		sin_relevo()


## Sin compañeros vivos: refuerzo desde la orilla en 5 s.
func volver_desde_orilla() -> void:
	esperando_relevo = true
	Game.say("[SIN COMPAÑEROS: LLEGAS CON UN REFUERZO EN 5 S]", Game.COLOR_INFO)
	await get_tree().create_timer(5.0).timeout
	if is_inside_tree() and dead:
		_reaparecer()


func sin_relevo() -> void:
	esperando_relevo = false
	Game.say("[TU ESCUADRA NO TIENE MÁS HOMBRES]", Game.COLOR_BAD)


## Pasa a manejar a este compañero: su lugar, su arma, su nombre y su cara.
func _tomar_lugar(a: Aliado) -> void:
	var pos := a.global_position
	Escuadras.quitar_de_escuadra(a)
	if Red.es_anfitrion():
		Red.evento(["q", Red.actual.rid_de(a)])
	a.queue_free()
	tomar_lugar_en(pos, a.arma, a.nombre)


func tomar_lugar_en(pos: Vector3, arma: String, nuevo_nombre: String) -> void:
	global_position = pos
	rotation.y = 0.0     # mirando hacia el búnker
	head.rotation = Vector3.ZERO
	head.position.y = STAND_HEAD
	camera.h_offset = 0
	camera.v_offset = 0
	_set_crouch(false)
	velocity = Vector3.ZERO
	var d := Armas.datos(arma)
	weapons.equip(arma, int(d["mag"]), int(d["mag"]) * 3)
	weapons.visible = true
	nombre = nuevo_nombre
	health = max_health
	_since_hit = 0.0
	damage_flash = 0.0
	hit_indicator = 0.0
	grenades = maxi(grenades, 2)
	dead = false
	esperando_relevo = false
	Game.say("[AHORA ERES %s]" % nombre, Game.COLOR_GOOD)


## Cooperativo: vuelve a la orilla con vida y munición llenas.
func _reaparecer(aqui := Vector3.INF, vida := 1.0) -> void:
	if aqui == Vector3.INF:
		var inicio: Vector3 = get_meta("inicio", global_position)
		global_position = inicio + Vector3(randf_range(-6.0, 6.0), 0.5, 0)
	else:
		global_position = aqui + Vector3(0, 0.2, 0)
	rotation.y = 0.0
	head.rotation = Vector3.ZERO
	head.position.y = STAND_HEAD
	_set_crouch(false)
	velocity = Vector3.ZERO
	var d := Armas.datos(weapons.id())
	weapons.equip(weapons.id(), int(d["mag"]), int(d["mag"]) * 3)
	weapons.visible = true
	health = max_health * vida
	_since_hit = 0.0
	damage_flash = 0.0
	hit_indicator = 0.0
	grenades = maxi(grenades, 2)
	dead = false
	esperando_relevo = false
	if aqui == Vector3.INF:
		Game.say("[DE VUELTA AL COMBATE]", Game.COLOR_GOOD)


## Tu cuerpo queda en la arena (un soldado de sprites, ya caído).
func _dejar_cuerpo(donde: Transform3D) -> void:
	var c := SoldadoSprite.new()
	c.bando = "aliado"
	c.arma = weapons.id()
	get_parent().add_child(c)
	c.global_transform = Transform3D(Basis(Vector3.UP, rotation.y), Vector3(donde.origin.x, global_position.y, donde.origin.z))
	c.morir(-global_basis.z, false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	damage_flash = maxf(damage_flash - delta * 1.5, 0.0)
	supresion = maxf(supresion - delta * 0.35, 0.0)
	hit_indicator = maxf(hit_indicator - delta, 0.0)

	if dead:
		velocity.x = move_toward(velocity.x, 0, delta * 10)
		velocity.z = move_toward(velocity.z, 0, delta * 10)
		move_and_slide()
		# La cámara cae al suelo
		head.position.y = lerpf(head.position.y, 0.25, delta * 3.0)
		head.rotation.z = lerpf(head.rotation.z, 1.3, delta * 3.0)
		camera.h_offset = 0
		camera.v_offset = 0
		return

	# Recuperación lenta de vida
	_since_hit += delta
	if _since_hit > regen_delay and health < max_health:
		health = minf(health + regen_per_second * delta, max_health)

	# Mantener AGACHAR: cuerpo a tierra
	if _agachar_desde >= 0.0 and not prone:
		_agachar_desde += delta     # cuánto lleva apretado
		if not (Input.is_action_pressed("crouch") or touch_crouch_held):
			_agachar_desde = -1.0
		elif _agachar_desde > PRONE_HOLD:
			_agachar_desde = -1.0
			_set_prone()

	var wants_jump := Input.is_action_just_pressed("jump") or touch_jump
	touch_jump = false
	if wants_jump and is_on_floor():
		if prone:
			_set_crouch(true)
		elif crouching:
			_set_crouch(false)
		else:
			velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > 0.05:
		input = touch_move

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = touch_aim or touch_hold_aim or (captured and Input.is_action_pressed("aim"))
	# En modo "al soltar", las automáticas empiezan la ráfaga recién cuando la mira ya subió
	var touch_trigger := touch_fire and (not Game.disparo_soltar or weapons.ads_amount > 0.85)
	weapons.trigger_held = touch_trigger or (captured and Input.is_action_pressed("fire"))
	var wants_sprint := Input.is_action_pressed("sprint") or touch_sprint
	sprinting = wants_sprint and input.y < -0.3 and not aiming and is_on_floor() and not weapons.busy()
	if sprinting and crouching:
		_set_crouch(false)

	var speed := walk_speed
	if sprinting:
		speed = sprint_speed
	elif prone:
		speed = PRONE_SPEED
	elif crouching:
		speed = crouch_speed
	if aiming:
		speed *= 0.6

	var direction := transform.basis * Vector3(input.x, 0, input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	# Altura de la cabeza (agachado / de pie)
	var alto_cabeza := PRONE_HEAD if prone else (CROUCH_HEAD if crouching else STAND_HEAD)
	head.position.y = lerpf(head.position.y, alto_cabeza, delta * (6.0 if prone else 10.0))

	# Zoom al apuntar, algo más abierto al correr
	var target_fov := _base_fov
	if weapons.ads_amount > 0.0:
		target_fov = lerpf(_base_fov, weapons.def()["ads_fov"], weapons.ads_amount)
	elif sprinting:
		target_fov = _base_fov * 1.08
	camera.fov = lerpf(camera.fov, target_fov, delta * 12.0)

	_update_head_bob(delta, direction.length() * speed / walk_speed)


func _update_head_bob(delta: float, amount: float) -> void:
	# Balanceo de cámara al caminar, como en los FPS de los 90.
	if is_on_floor() and amount > 0.1:
		bob_time += delta * (12.0 if sprinting else 9.0)
	var calm := 1.0 - weapons.ads_amount * 0.8
	camera.position.y = sin(bob_time) * 0.04 * minf(amount, 1.6) * calm
	camera.position.x = cos(bob_time * 0.5) * 0.03 * minf(amount, 1.6) * calm
	# Temblor por explosiones o impactos
	_shake = maxf(_shake - delta * 2.0, 0.0)
	camera.h_offset = randf_range(-1, 1) * _shake * 0.06
	camera.v_offset = randf_range(-1, 1) * _shake * 0.06
