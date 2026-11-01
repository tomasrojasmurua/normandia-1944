extends CharacterBody3D
## Soldado controlado por el jugador (vista en primera persona).
## Funciona con teclado + mouse en PC y con los controles táctiles en el celular.

@export var walk_speed := 4.5
@export var jump_velocity := 4.2
@export var mouse_sensitivity := 0.0025
@export var touch_look_sensitivity := 0.006

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Valores que escriben los controles táctiles (touch_controls.gd).
var touch_move := Vector2.ZERO
var touch_jump := false

var _bob_time := 0.0


func _unhandled_input(event: InputEvent) -> void:
	# En PC: clic para capturar el mouse, Esc para soltarlo.
	if event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * mouse_sensitivity)


## Gira la cámara. `delta` en radianes (x = horizontal, y = vertical).
func look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	head.rotate_x(-delta.y)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))


func look_touch(pixels: Vector2) -> void:
	look(pixels * touch_look_sensitivity)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var wants_jump := Input.is_action_just_pressed("jump") or touch_jump
	touch_jump = false
	if wants_jump and is_on_floor():
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > 0.05:
		input = touch_move
	var direction := (transform.basis * Vector3(input.x, 0, input.y))
	if direction.length() > 1.0:
		direction = direction.normalized()

	velocity.x = direction.x * walk_speed
	velocity.z = direction.z * walk_speed
	move_and_slide()

	_update_head_bob(delta, direction.length())


func _update_head_bob(delta: float, amount: float) -> void:
	# Pequeño balanceo de cámara al caminar, como en los FPS de los 90.
	if is_on_floor() and amount > 0.1:
		_bob_time += delta * 9.0
	camera.position.y = sin(_bob_time) * 0.04 * amount
	camera.position.x = cos(_bob_time * 0.5) * 0.03 * amount
