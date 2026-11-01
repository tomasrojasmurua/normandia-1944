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
		"spread_hip": 1.2,        # dispersión en grados sin apuntar
		"spread_ads": 0.15,       # dispersión apuntando por la mira
		"recoil": 2.6,            # grados que sube la vista al disparar
		"sound": "rifle", "ads_fov": 42.0,
		"hip": Vector3(0.16, -0.15, -0.26), "ads": Vector3(0, 0, -0.06),
	},
	{
		"name": "COLT M1911", "mag": 7, "reserve": 28,
		"damage": 45.0, "interval": 0.14, "reload": 1.6,
		"spread_hip": 1.5, "spread_ads": 0.5, "recoil": 2.0,
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
var last_shot := {}        # datos del último disparo (para pruebas)

# --- Arma dibujada en 2D (imágenes de ChatGPT pixeladas), como en los FPS de los 90.
# assets/armas/arma_<id>_cadera.png = desde la cadera; arma_<id>_mira.png = por la
# mira (opcional). Si un arma no tiene imagen, se usa su modelo 3D de cajas.
const SPRITES := ["garand", "colt"]
var sprite_cadera: Array[Texture2D] = []
var sprite_mira: Array[Texture2D] = []
var sprite_granada: Texture2D = null
var view_offset := Vector2.ZERO   # desplazamiento en píxeles de pantalla
var view_angle := 0.0             # giro en grados
var flash_2d := 0.0               # >0 mientras se ve el fogonazo 2D
var shots_fired := 0              # cuenta disparos (el HUD expulsa una vaina por cada uno)
var clips_ejected := 0            # cuenta clips vacíos del Garand expulsados

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
	for id in SPRITES:
		sprite_cadera.append(_load_opt("res://assets/armas/arma_%s_cadera.png" % id))
		sprite_mira.append(_load_opt("res://assets/armas/arma_%s_mira.png" % id))
	sprite_granada = _load_opt("res://assets/armas/arma_granada.png")
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
	# (con imagen 2D, la recarga la anima hud.gd con su propio clip/cargador)
	if _reload_t >= 0.0 and uses_3d_view():
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

	# Lo mismo traducido a la imagen 2D (píxeles de pantalla y grados), sin el
	# paso de cadera a mira, que la imagen hace por su cuenta (hud.gd)
	var d := pos - hip.lerp(ads, t)
	view_offset = Vector2(d.x * 900.0 - (rot.y - lerpf(3.0, 0.0, t)) * 2.0, -d.y * 900.0) \
		+ Vector2(d.z, d.z) * 400.0
	view_angle = rot.z - rot.x * 0.5
	flash_2d = maxf(flash_2d - _delta, 0.0)
	# Modelo 3D solo al apuntar (o si no hay imagen para esta arma)
	if current < _models.size():
		_models[current].visible = uses_3d_view()


## true si ahora se ve el modelo 3D; false si se dibuja la imagen 2D.
func uses_3d_view() -> bool:
	return sprite_cadera[current] == null


## 0..1 mientras se recarga; -1 si no.
func reload_progress() -> float:
	return _reload_t / def()["reload"] if _reload_t >= 0.0 else -1.0


## 0..1 mientras se lanza una granada; -1 si no.
func throw_progress() -> float:
	return _throw_t / 0.6 if _throw_t >= 0.0 else -1.0


static func _load_opt(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _fire() -> void:
	var w := def()
	ammo[current] -= 1
	_cooldown = w["interval"]
	_kick = 1.0
	Game.play(w["sound"], 0.0, randf_range(0.94, 1.06))
	shots_fired += 1
	if current == 0 and ammo[current] == 0:
		clips_ejected += 1
		get_tree().create_timer(0.12).timeout.connect(func() -> void: Game.play("ping", -3.0))

	var flash := _flashes[current]
	flash.visible = uses_3d_view()
	flash_2d = 0.06
	flash.rotation.z = randf() * TAU
	get_tree().create_timer(0.05).timeout.connect(func() -> void: flash.visible = false)

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

	# Retroceso DESPUÉS de calcular el tiro: la bala sale hacia donde apuntabas,
	# luego la vista sube y vuelve casi sola a su lugar
	var r := deg_to_rad(w["recoil"]) * (1.0 - 0.4 * ads_amount)
	if DisplayServer.is_touchscreen_available():
		r *= 0.75   # en el celular se corrige con el dedo: un poco menos de salto
	_player.look(Vector2(randf_range(-0.25, 0.25) * r, -r))
	_recoil_left += r * RECOIL_RECOVERY
	_recoil_wait = 0.06

	last_shot = {"from": from, "dir": dir, "hit": hit}
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

# Texturas pixeladas de 32 px (tools/arte/generar_arte.py) proyectadas sobre
# cada caja. "metros" = cuánto mide una repetición de la textura.
static func _tex(nombre: String, metros: float, tinte := Color.WHITE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/armas/%s.png" % nombre)
	mat.albedo_color = tinte
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE / metros
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat

var _wood := _tex("madera", 0.14)
var _wood_dark := _tex("madera", 0.08, Color(0.6, 0.5, 0.45))
var _metal := _tex("metal", 0.08)
var _metal_dark := _tex("metal", 0.08, Color(0.45, 0.45, 0.45))
var _metal_light := _tex("metal", 0.08, Color(1.35, 1.35, 1.35))
var _brass := Game.material(Color("#c99a3e"))
var _skin := _tex("piel", 0.1)
var _sleeve := _tex("manga", 0.16)
var _cuff := _tex("manga", 0.16, Color(0.7, 0.7, 0.65))


func _build_garand() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	# Cajón de mecanismos, clip de latón y palanca del cerrojo
	Game.box(g, Vector3(0.042, 0.044, 0.22), Vector3(0, -0.034, -0.13), _metal)
	Game.box(g, Vector3(0.02, 0.008, 0.05), Vector3(0, -0.02, -0.15), _brass)
	Game.box(g, Vector3(0.008, 0.012, 0.4), Vector3(0.024, -0.045, -0.42), _metal)
	Game.box(g, Vector3(0.016, 0.014, 0.02), Vector3(0.034, -0.03, -0.19), _metal_light)
	# Alza de agujero (el punto de mira se ve por el centro, en y = 0)
	Game.box(g, Vector3(0.034, 0.012, 0.03), Vector3(0, -0.018, -0.035), _metal)
	# (agujero de 12 mm centrado en y = 0, aro fino de 3-4 mm)
	Game.box(g, Vector3(0.004, 0.022, 0.005), Vector3(0.008, -0.001, -0.045), _metal_dark)
	Game.box(g, Vector3(0.004, 0.022, 0.005), Vector3(-0.008, -0.001, -0.045), _metal_dark)
	Game.box(g, Vector3(0.012, 0.004, 0.005), Vector3(0, 0.008, -0.045), _metal_dark)
	Game.box(g, Vector3(0.012, 0.006, 0.005), Vector3(0, -0.009, -0.045), _metal_dark)
	Game.box(g, Vector3(0.008, 0.01, 0.01), Vector3(0.028, -0.016, -0.04), _metal_light)   # perillas
	Game.box(g, Vector3(0.008, 0.01, 0.01), Vector3(-0.028, -0.016, -0.04), _metal_light)
	# Madera: guardamanos superior, caja, empuñadura y culata
	Game.box(g, Vector3(0.038, 0.026, 0.14), Vector3(0, -0.036, -0.32), _wood)
	Game.box(g, Vector3(0.038, 0.026, 0.2), Vector3(0, -0.04, -0.58), _wood)
	Game.box(g, Vector3(0.048, 0.05, 0.48), Vector3(0, -0.075, -0.48), _wood)
	Game.box(g, Vector3(0.05, 0.06, 0.16), Vector3(0, -0.08, -0.12), _wood)
	Game.box(g, Vector3(0.046, 0.07, 0.1), Vector3(0, -0.1, 0.0), _wood, Vector3(-20, 0, 0))
	Game.box(g, Vector3(0.05, 0.1, 0.26), Vector3(0, -0.11, 0.14), _wood, Vector3(-6, 0, 0))
	Game.box(g, Vector3(0.052, 0.105, 0.012), Vector3(0, -0.122, 0.27), _metal, Vector3(-6, 0, 0))
	Game.box(g, Vector3(0.018, 0.03, 0.06), Vector3(0, -0.12, -0.08), _metal)          # guardamonte
	# Cañón, abrazaderas y punto de mira con orejas
	Game.box(g, Vector3(0.02, 0.02, 0.24), Vector3(0, -0.034, -0.74), _metal)
	Game.box(g, Vector3(0.028, 0.03, 0.06), Vector3(0, -0.045, -0.83), _metal)
	Game.box(g, Vector3(0.05, 0.054, 0.015), Vector3(0, -0.06, -0.56), _metal)
	Game.box(g, Vector3(0.046, 0.05, 0.015), Vector3(0, -0.058, -0.72), _metal)
	Game.box(g, Vector3(0.004, 0.022, 0.006), Vector3(0, -0.011, -0.86), _metal_light)
	Game.box(g, Vector3(0.004, 0.026, 0.012), Vector3(0.011, -0.013, -0.86), _metal)
	Game.box(g, Vector3(0.004, 0.026, 0.012), Vector3(-0.011, -0.013, -0.86), _metal)
	# Mano derecha en la empuñadura
	Game.box(g, Vector3(0.06, 0.06, 0.08), Vector3(0.01, -0.115, 0.0), _skin, Vector3(-20, 0, 0))
	for k in 3:
		Game.box(g, Vector3(0.052, 0.016, 0.018), Vector3(0.004, -0.148, -0.03 + k * 0.021), _skin)
	Game.box(g, Vector3(0.016, 0.016, 0.05), Vector3(-0.028, -0.085, -0.03), _skin)
	Game.box(g, Vector3(0.09, 0.09, 0.03), Vector3(0.035, -0.15, 0.06), _cuff)
	Game.box(g, Vector3(0.085, 0.085, 0.25), Vector3(0.04, -0.16, 0.19), _sleeve)
	# Mano izquierda bajo el guardamanos
	Game.box(g, Vector3(0.06, 0.02, 0.09), Vector3(0, -0.108, -0.44), _skin)
	Game.box(g, Vector3(0.018, 0.06, 0.09), Vector3(-0.032, -0.08, -0.44), _skin)
	for k in 4:
		Game.box(g, Vector3(0.014, 0.04, 0.016), Vector3(0.031, -0.075, -0.41 - k * 0.02), _skin)
	Game.box(g, Vector3(0.095, 0.095, 0.03), Vector3(-0.045, -0.13, -0.37), _cuff, Vector3(0, -25, 0))
	Game.box(g, Vector3(0.09, 0.09, 0.3), Vector3(-0.08, -0.15, -0.24), _sleeve, Vector3(0, -25, 0))
	_flashes.append(_build_flash(g, Vector3(0, -0.035, -0.9)))
	return g


func _build_colt() -> Node3D:
	var c := Node3D.new()
	add_child(c)
	# Corredera con estrías, alza y punto de mira (línea de mira en y = 0)
	Game.box(c, Vector3(0.028, 0.03, 0.2), Vector3(0, -0.018, -0.095), _metal)
	for k in 5:
		Game.box(c, Vector3(0.03, 0.022, 0.003), Vector3(0, -0.018, -0.004 - k * 0.008), _metal_dark)
	Game.box(c, Vector3(0.008, 0.008, 0.008), Vector3(0.007, -0.002, -0.006), _metal_dark)
	Game.box(c, Vector3(0.008, 0.008, 0.008), Vector3(-0.007, -0.002, -0.006), _metal_dark)
	Game.box(c, Vector3(0.004, 0.008, 0.006), Vector3(0, -0.004, -0.19), _metal_light)
	Game.box(c, Vector3(0.02, 0.02, 0.01), Vector3(0, -0.02, -0.199), _metal_light)    # boca
	Game.box(c, Vector3(0.01, 0.014, 0.01), Vector3(0, -0.004, 0.009), _metal_dark, Vector3(-30, 0, 0))  # martillo
	# Armazón, guardamonte, empuñadura y base del cargador
	Game.box(c, Vector3(0.026, 0.022, 0.15), Vector3(0, -0.044, -0.085), _metal_light)
	Game.box(c, Vector3(0.012, 0.004, 0.04), Vector3(0, -0.072, -0.05), _metal)
	Game.box(c, Vector3(0.012, 0.025, 0.004), Vector3(0, -0.06, -0.07), _metal)
	Game.box(c, Vector3(0.03, 0.09, 0.045), Vector3(0, -0.09, 0.0), _wood_dark, Vector3(15, 0, 0))
	Game.box(c, Vector3(0.026, 0.006, 0.04), Vector3(0, -0.135, 0.012), _metal, Vector3(15, 0, 0))
	# Dos manos en la empuñadura
	Game.box(c, Vector3(0.045, 0.07, 0.06), Vector3(0.012, -0.097, 0.008), _skin, Vector3(15, 0, 0))
	Game.box(c, Vector3(0.04, 0.06, 0.065), Vector3(-0.03, -0.102, 0.0), _skin)
	Game.box(c, Vector3(0.014, 0.014, 0.05), Vector3(-0.02, -0.058, -0.04), _skin)
	Game.box(c, Vector3(0.085, 0.085, 0.03), Vector3(0.035, -0.125, 0.06), _cuff, Vector3(0, 10, 0))
	Game.box(c, Vector3(0.085, 0.085, 0.03), Vector3(-0.045, -0.125, 0.05), _cuff, Vector3(0, -15, 0))
	Game.box(c, Vector3(0.08, 0.08, 0.25), Vector3(0.04, -0.13, 0.19), _sleeve, Vector3(0, 10, 0))
	Game.box(c, Vector3(0.08, 0.08, 0.25), Vector3(-0.065, -0.13, 0.18), _sleeve, Vector3(0, -15, 0))
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
