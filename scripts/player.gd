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
@export var max_health := 100.0
@export var regen_delay := 6.0        # segundos sin recibir daño antes de recuperarse
@export var regen_per_second := 4.0   # 0 = sin recuperación
@export var grenades := 3

const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.15
const STAND_HEAD := 1.6
const CROUCH_HEAD := 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapons: Weapons = $Head/Camera3D/Weapons
@onready var collision: CollisionShape3D = $Collision

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var health := 100.0
var dead := false
var crouching := false
var sprinting := false
var aiming := false
var bob_time := 0.0
var damage_flash := 0.0     # el HUD pinta la pantalla de rojo
var hit_angle := 0.0        # dirección del último disparo recibido (HUD)
var hit_indicator := 0.0

# Valores que escriben los controles táctiles (touch_controls.gd).
var touch_move := Vector2.ZERO
var touch_jump := false
var touch_aim := false
var touch_sprint := false

var _since_hit := 99.0
var _shake := 0.0
var _capsule: CapsuleShape3D
var _base_fov := 70.0
var _throw_pending := false


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2          # capa 2: jugador
	collision_mask = 1 | 4       # choca con escenario (1) y enemigos (3)
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
	# En PC: clic para capturar el mouse (ese clic no dispara), Esc para soltarlo.
	if event is InputEventMouseButton and event.pressed and not captured \
			and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and captured:
		look(event.relative * mouse_sensitivity * (0.55 if aiming else 1.0))
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
		throw_grenade()
	elif event.is_action_pressed("crouch"):
		toggle_crouch()


## Gira la cámara. `delta` en radianes (x = horizontal, y = vertical).
func look(delta: Vector2) -> void:
	if dead:
		return
	rotate_y(-delta.x)
	head.rotate_x(-delta.y)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))


func look_touch(pixels: Vector2) -> void:
	look(pixels * touch_look_sensitivity * (0.5 if aiming else 1.0))


func toggle_crouch() -> void:
	if not dead:
		_set_crouch(not crouching)


func _set_crouch(on: bool) -> void:
	crouching = on
	_capsule.height = CROUCH_HEIGHT if on else STAND_HEIGHT
	collision.position.y = _capsule.height / 2.0


func throw_grenade() -> void:
	if dead or grenades <= 0 or weapons.busy() or _throw_pending:
		if grenades <= 0 and not dead:
			Game.say("[SIN GRANADAS]", Game.COLOR_BAD)
		return
	grenades -= 1
	_throw_pending = true
	weapons.start_throw()
	Game.play("throw", -2.0)
	await get_tree().create_timer(0.25).timeout
	_throw_pending = false
	if dead:
		return
	var g := Grenade.new()
	get_tree().current_scene.add_child(g)
	var fwd := -camera.global_basis.z
	g.global_position = camera.global_position + fwd * 0.5 - camera.global_basis.y * 0.1
	g.linear_velocity = fwd * 13.0 + Vector3.UP * 3.5 + velocity * 0.5
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	Game.say("[GRANADA!]")


func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	health -= amount
	_since_hit = 0.0
	damage_flash = 1.0
	shake(0.25)
	var local := global_transform.basis.inverse() * (from_pos - global_position)
	hit_angle = atan2(local.x, -local.z)
	hit_indicator = 1.5
	Game.play("hurt")
	if health <= 0.0:
		_die()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _die() -> void:
	dead = true
	health = 0.0
	weapons.visible = false
	Game.say("[HAS CAIDO]", Game.COLOR_BAD)
	await get_tree().create_timer(4.0).timeout
	get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	damage_flash = maxf(damage_flash - delta * 1.5, 0.0)
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

	var wants_jump := Input.is_action_just_pressed("jump") or touch_jump
	touch_jump = false
	if wants_jump and is_on_floor():
		if crouching:
			_set_crouch(false)
		else:
			velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > 0.05:
		input = touch_move

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = touch_aim or (captured and Input.is_action_pressed("aim"))
	var wants_sprint := Input.is_action_pressed("sprint") or touch_sprint
	sprinting = wants_sprint and input.y < -0.3 and not aiming and is_on_floor() and not weapons.busy()
	if sprinting and crouching:
		_set_crouch(false)

	var speed := walk_speed
	if sprinting:
		speed = sprint_speed
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
	head.position.y = lerpf(head.position.y, CROUCH_HEAD if crouching else STAND_HEAD, delta * 10.0)

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
