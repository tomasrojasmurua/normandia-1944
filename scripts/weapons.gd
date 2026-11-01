extends Node3D
class_name Weapons
## Armas del jugador: M1 Garand (slot 1) y Colt M1911 (slot 2).
## Va dentro de la cámara. Construye los modelos con cajas, dispara con un
## rayo desde el centro de la pantalla y maneja munición, recarga, mira y retroceso.
## Para ajustar el juego, cambia los números de WEAPONS (daño, munición, etc.).

const WEAPONS := [
	{
		"name": "M1 GARAND", "mag": 8, "reserve": 80,
		"damage": 100.0,          # 100 = derriba al enemigo de un tiro en el cuerpo
		"interval": 0.17,         # segundos mínimos entre disparos
		"reload": 2.3,            # segundos de recarga
		"spread_hip": 2.6,        # dispersión en grados sin apuntar
		"spread_ads": 0.15,       # dispersión apuntando por la mira
		"recoil": 2.6,            # grados que sube la vista al disparar
		"sound": "rifle", "ads_fov": 42.0,
		"hip": Vector3(0.16, -0.15, -0.26), "ads": Vector3(0, 0, -0.15),
	},
	{
		"name": "COLT M1911", "mag": 7, "reserve": 28,
		"damage": 45.0, "interval": 0.14, "reload": 1.6,
		"spread_hip": 2.0, "spread_ads": 0.5, "recoil": 2.0,
		"sound": "pistol", "ads_fov": 55.0,
		"hip": Vector3(0.1, -0.06, -0.22), "ads": Vector3(0, 0, -0.26),
	},
]

var ammo: Array[int] = []
var reserve: Array[int] = []
var current := 0
var spread_now := 2.0      # grados; el HUD lo usa para abrir la cruz
var hit_marker := 0.0      # >0 cuando acabas de acertar (el HUD dibuja una X)
var ads_amount := 0.0      # 0 = cadera, 1 = apuntando por la mira

var _player: Node
var _camera: Camera3D
var _models: Array[Node3D] = []
var _flashes: Array[Node3D] = []
var _cooldown := 0.0
var _reload_t := -1.0      # >=0 mientras recarga
var _switch_t := -1.0
var _switch_to := 0
var _throw_t := -1.0
var _kick := 0.0
var _recoil_left := 0.0    # radianes de retroceso que la vista aún debe "devolver"
var _recoil_wait := 0.0

## Fracción del retroceso vertical que la vista recupera sola (0 = nada, 1 = todo).
const RECOIL_RECOVERY := 0.8
var _empty_wait := -1.0


func _ready() -> void:
	_player = owner
	_camera = get_parent() as Camera3D
	for w in WEAPONS:
		ammo.append(w["mag"])
		reserve.append(w["reserve"])
	_models.append(_build_garand())
	_models.append(_build_colt())
	_show(current)


func def() -> Dictionary:
	return WEAPONS[current]


func is_reloading() -> bool:
	return _reload_t >= 0.0


func busy() -> bool:
	return _reload_t >= 0.0 or _switch_t >= 0.0 or _throw_t >= 0.0


# ------------------------------------------------------------ acciones

func pull_trigger() -> void:
	if _player.dead or busy() or _player.sprinting or _cooldown > 0.0:
		return
	if ammo[current] <= 0:
		Game.play("click")
		_cooldown = 0.25
		return
	_fire()


func reload() -> void:
	if busy() or ammo[current] >= def()["mag"] or reserve[current] <= 0:
		return
	_reload_t = 0.0
	Game.play("reload", -4.0)


func select(index: int) -> void:
	if index == current or index < 0 or index >= WEAPONS.size() or _switch_t >= 0.0 or _throw_t >= 0.0:
		return
	_reload_t = -1.0  # cambiar de arma cancela la recarga
	_switch_t = 0.0
	_switch_to = index
	Game.play("click", -6.0)


func next_weapon() -> void:
	select((current + 1) % WEAPONS.size())


## Animación de lanzar granada (el arma baja un momento).
func start_throw() -> void:
	_reload_t = -1.0
	_throw_t = 0.0


# ------------------------------------------------------------ lógica

func _process(delta: float) -> void:
	_cooldown -= delta
	hit_marker = maxf(hit_marker - delta * 4.0, 0.0)
	_kick = maxf(_kick - delta * 7.0, 0.0)
	_recover_recoil(delta)
	var w := def()

	if _reload_t >= 0.0:
		_reload_t += delta
		if _reload_t >= w["reload"]:
			var need: int = w["mag"] - ammo[current]
			var take := mini(need, reserve[current])
			ammo[current] += take
			reserve[current] -= take
			_reload_t = -1.0

	if _switch_t >= 0.0:
		var before := _switch_t
		_switch_t += delta
		if before < 0.18 and _switch_t >= 0.18:
			current = _switch_to
			_show(current)
		if _switch_t >= 0.38:
			_switch_t = -1.0

	if _throw_t >= 0.0:
		_throw_t += delta
		if _throw_t >= 0.6:
			_throw_t = -1.0

	# Recarga automática al vaciar el cargador
	if ammo[current] == 0 and reserve[current] > 0 and not busy():
		if _empty_wait < 0.0:
			_empty_wait = 0.45
		_empty_wait -= delta
		if _empty_wait <= 0.0:
			_empty_wait = -1.0
			reload()
	else:
		_empty_wait = -1.0

	var wants_ads: bool = _player.aiming and not busy() and not _player.sprinting
	ads_amount = move_toward(ads_amount, 1.0 if wants_ads else 0.0, delta * 7.0)

	var moving := clampf(Vector2(_player.velocity.x, _player.velocity.z).length() / 4.5, 0.0, 1.5)
	spread_now = lerpf(w["spread_hip"], w["spread_ads"], ads_amount)
	spread_now += moving * 1.6 * (1.0 - ads_amount * 0.85)
	if _player.crouching:
		spread_now *= 0.7
	if not _player.is_on_floor():
		spread_now += 3.0
	spread_now += _kick * 1.5

	_animate(delta, w)


func _animate(_delta: float, w: Dictionary) -> void:
	var t := smoothstep(0.0, 1.0, ads_amount)
	var hip: Vector3 = w["hip"]
	var ads: Vector3 = w["ads"]
	var pos := hip.lerp(ads, t)
	var rot := Vector3(0, lerpf(3.0, 0.0, t), 0)

	# Balanceo al caminar (menos al apuntar)
	var bob: float = _player.bob_time
	var sway := Vector2(_player.velocity.x, _player.velocity.z).length() / 4.5
	pos += Vector3(cos(bob * 0.5) * 0.012, absf(sin(bob)) * -0.012, 0) * sway * (1.0 - t * 0.8)

	if _player.sprinting:
		pos += Vector3(-0.04, -0.07, 0.04)
		rot += Vector3(-12, 35, 8)
	if _reload_t >= 0.0:
		var r := sin(PI * clampf(_reload_t / w["reload"], 0.0, 1.0))
		pos += Vector3(0, -0.1, 0.05) * r
		rot += Vector3(20, 0, 35) * r
	if _switch_t >= 0.0 or _throw_t >= 0.0:
		var s := sin(PI * clampf(_switch_t / 0.38, 0.0, 1.0)) if _switch_t >= 0.0 \
			else sin(PI * clampf(_throw_t / 0.6, 0.0, 1.0))
		pos += Vector3(0, -0.3, 0) * s
		rot += Vector3(-30, 0, 0) * s

	pos.z += _kick * 0.05 * (1.0 - t * 0.5)
	rot.x += _kick * 6.0 * (1.0 - t * 0.6)
	position = pos
	rotation_degrees = rot


func _fire() -> void:
	var w := def()
	ammo[current] -= 1
	_cooldown = w["interval"]
	_kick = 1.0
	Game.play(w["sound"], 0.0, randf_range(0.94, 1.06))
	if current == 0 and ammo[current] == 0:
		get_tree().create_timer(0.12).timeout.connect(func() -> void: Game.play("ping", -3.0))

	var flash := _flashes[current]
	flash.visible = true
	flash.rotation.z = randf() * TAU
	get_tree().create_timer(0.05).timeout.connect(func() -> void: flash.visible = false)

	# Retroceso: la vista sube y luego vuelve casi sola a su lugar
	var r := deg_to_rad(w["recoil"]) * (1.0 - 0.4 * ads_amount)
	if DisplayServer.is_touchscreen_available():
		r *= 0.75   # en el celular se corrige con el dedo: un poco menos de salto
	_player.look(Vector2(randf_range(-0.25, 0.25) * r, -r))
	_recoil_left += r * RECOIL_RECOVERY
	_recoil_wait = 0.06

	# Disparo instantáneo (rayo) desde el centro de la pantalla
	var b := _camera.global_basis
	var spread := tan(deg_to_rad(spread_now))
	var ang := randf() * TAU
	var rad := sqrt(randf()) * spread
	var dir := (-b.z + b.x * cos(ang) * rad + b.y * sin(ang) * rad).normalized()
	var from := _camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0, 1 | 4)
	q.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var target: Object = hit["collider"]
	if target is Enemy:
		target.hit(w["damage"], int(hit["shape"]) == 1, hit["position"], dir)
		hit_marker = 1.0
		Game.play("hit", -4.0)
	else:
		Game.dust(hit["position"], hit["normal"])


func _recover_recoil(delta: float) -> void:
	if _recoil_left <= 0.0:
		return
	if _recoil_wait > 0.0:
		_recoil_wait -= delta
		return
	var step := minf(_recoil_left, maxf(_recoil_left * 10.0, 0.02) * delta)
	_recoil_left -= step
	_player.look(Vector2(0, step))


## Si el jugador mueve la vista hacia abajo por su cuenta, eso ya cuenta
## como recuperación (así no "baja de más").
func player_looked(delta_y: float) -> void:
	if delta_y > 0.0 and _recoil_left > 0.0:
		_recoil_left = maxf(_recoil_left - delta_y, 0.0)


## ¿Hay un enemigo vivo cerca del centro de la mira? (para la asistencia táctil)
func enemy_under_crosshair() -> bool:
	var from := _camera.global_position
	var fwd := -_camera.global_basis.z
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = e.global_position + Vector3(0, 1.1, 0) - from
		var dist := to.length()
		if dist > 80.0 or dist < 0.5:
			continue
		# ángulo que ocupa ~1 metro a esa distancia
		var allowed := atan(0.9 / dist)
		if fwd.angle_to(to) < allowed:
			return true
	return false


func _show(index: int) -> void:
	for i in _models.size():
		_models[i].visible = i == index


# ------------------------------------------------------------ modelos
# La línea de mira de cada arma está en y = 0, x = 0 del modelo: así, al
# apuntar, el alza y el punto de mira quedan justo en el centro de la pantalla.

var _wood := Game.material(Color(0.45, 0.27, 0.14))
var _metal := Game.material(Color(0.15, 0.15, 0.16))
var _metal_light := Game.material(Color(0.3, 0.3, 0.32))
var _skin := Game.material(Color(0.8, 0.57, 0.42))
var _sleeve := Game.material(Color(0.36, 0.35, 0.22))


func _build_garand() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	Game.box(g, Vector3(0.045, 0.05, 0.22), Vector3(0, -0.035, -0.13), _metal)          # cajón de mecanismos
	Game.box(g, Vector3(0.04, 0.012, 0.03), Vector3(0, -0.016, -0.04), _metal)          # base del alza
	Game.box(g, Vector3(0.008, 0.028, 0.012), Vector3(0.013, -0.004, -0.04), _metal_light)   # alza
	Game.box(g, Vector3(0.008, 0.028, 0.012), Vector3(-0.013, -0.004, -0.04), _metal_light)
	Game.box(g, Vector3(0.04, 0.03, 0.38), Vector3(0, -0.04, -0.45), _wood)             # guardamanos
	Game.box(g, Vector3(0.05, 0.05, 0.62), Vector3(0, -0.075, -0.4), _wood)             # caja de madera
	Game.box(g, Vector3(0.05, 0.09, 0.36), Vector3(0, -0.095, 0.08), _wood, Vector3(-6, 0, 0))  # culata
	Game.box(g, Vector3(0.022, 0.022, 0.22), Vector3(0, -0.035, -0.75), _metal)         # cañón
	Game.box(g, Vector3(0.03, 0.03, 0.06), Vector3(0, -0.047, -0.82), _metal)           # cilindro de gases
	Game.box(g, Vector3(0.005, 0.024, 0.006), Vector3(0, -0.012, -0.85), _metal_light)  # punto de mira
	Game.box(g, Vector3(0.005, 0.03, 0.012), Vector3(0.012, -0.014, -0.85), _metal)     # orejas del punto
	Game.box(g, Vector3(0.005, 0.03, 0.012), Vector3(-0.012, -0.014, -0.85), _metal)
	Game.box(g, Vector3(0.02, 0.03, 0.06), Vector3(0, -0.11, -0.08), _metal)            # guardamonte
	Game.box(g, Vector3(0.07, 0.06, 0.09), Vector3(0.01, -0.12, 0.02), _skin)           # mano derecha
	Game.box(g, Vector3(0.09, 0.09, 0.25), Vector3(0.04, -0.16, 0.18), _sleeve)
	Game.box(g, Vector3(0.07, 0.06, 0.1), Vector3(-0.005, -0.095, -0.42), _skin)        # mano izquierda
	Game.box(g, Vector3(0.09, 0.09, 0.3), Vector3(-0.07, -0.15, -0.26), _sleeve, Vector3(0, -25, 0))
	_flashes.append(_build_flash(g, Vector3(0, -0.035, -0.9)))
	return g


func _build_colt() -> Node3D:
	var c := Node3D.new()
	add_child(c)
	Game.box(c, Vector3(0.028, 0.03, 0.19), Vector3(0, -0.02, -0.095), _metal)          # corredera
	Game.box(c, Vector3(0.026, 0.02, 0.15), Vector3(0, -0.044, -0.085), _metal_light)   # armazón
	Game.box(c, Vector3(0.03, 0.085, 0.045), Vector3(0, -0.09, 0.0), _wood, Vector3(15, 0, 0))  # empuñadura
	Game.box(c, Vector3(0.008, 0.01, 0.008), Vector3(0.008, -0.001, -0.005), _metal)    # alza
	Game.box(c, Vector3(0.008, 0.01, 0.008), Vector3(-0.008, -0.001, -0.005), _metal)
	Game.box(c, Vector3(0.004, 0.01, 0.006), Vector3(0, -0.002, -0.18), _metal_light)   # punto de mira
	Game.box(c, Vector3(0.06, 0.08, 0.07), Vector3(0.012, -0.095, 0.005), _skin)        # manos
	Game.box(c, Vector3(0.05, 0.07, 0.07), Vector3(-0.03, -0.1, 0.0), _skin)
	Game.box(c, Vector3(0.08, 0.08, 0.25), Vector3(0.04, -0.13, 0.16), _sleeve, Vector3(0, 10, 0))
	Game.box(c, Vector3(0.08, 0.08, 0.25), Vector3(-0.06, -0.13, 0.15), _sleeve, Vector3(0, -15, 0))
	_flashes.append(_build_flash(c, Vector3(0, -0.02, -0.21)))
	return c


func _build_flash(parent: Node3D, pos: Vector3) -> Node3D:
	var f := Node3D.new()
	f.position = pos
	parent.add_child(f)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	Game.box(f, Vector3(0.09, 0.025, 0.02), Vector3(0, 0, -0.03), mat)
	Game.box(f, Vector3(0.025, 0.09, 0.02), Vector3(0, 0, -0.03), mat)
	Game.box(f, Vector3(0.035, 0.035, 0.1), Vector3(0, 0, -0.07), mat)
	f.visible = false
	return f
