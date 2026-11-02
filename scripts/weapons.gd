extends Node3D
class_name Weapons
## Armas del jugador: dos ranuras (1 = arma principal, 2 = pistola). Empiezan
## con el M1 Garand y el Colt M1911; se cambian al recoger armas del suelo.
## Va dentro de la cámara. Dispara con un rayo desde el centro de la pantalla
## (o un cohete, la bazuca) y maneja munición, recarga, mira y retroceso.
## Los números de cada arma (daño, munición, etc.) están en armas.gd.

## Qué arma hay en cada ranura (ids de Armas.DATOS): 0 = principal, 1 = pistola.
## Se cambian al recoger armas del suelo (equip()).
var slots: Array[String] = ["garand", "colt"]
var trigger_held := false   # gatillo apretado (para las automáticas); lo pone player.gd

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
var sprite_cadera: Array[Texture2D] = [null, null]
var sprite_mira: Array[Texture2D] = [null, null]
var sprite_granada: Texture2D = null
var view_offset := Vector2.ZERO   # desplazamiento en píxeles de pantalla
var view_angle := 0.0             # giro en grados
var flash_2d := 0.0               # >0 mientras se ve el fogonazo 2D
var shots_fired := 0              # cuenta disparos (el HUD expulsa una vaina por cada uno)
var clips_ejected := 0            # cuenta clips vacíos del Garand expulsados

var _player: Node
var _camera: Camera3D
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
	for i in slots.size():
		var d := Armas.datos(slots[i])
		ammo.append(d["mag"])
		reserve.append(d["reserve"])
		_set_slot(i, slots[i])
	sprite_granada = _load_opt("res://assets/armas/arma_granada.png")


func def() -> Dictionary:
	return Armas.datos(slots[current])


func id() -> String:
	return slots[current]


## Pone el arma "id" en la ranura i (con sus imágenes).
func _set_slot(i: int, arma_id: String) -> void:
	slots[i] = arma_id
	sprite_cadera[i] = Armas.imagen("arma_%s_cadera" % arma_id)
	sprite_mira[i] = Armas.imagen("arma_%s_mira" % arma_id)


## Recoge un arma: va a su ranura (principal o pistola) y devuelve la que
## había ahí, para dejarla en el suelo: {"id", "mag", "reserve"}.
func equip(arma_id: String, mag: int, res: int) -> Dictionary:
	var i: int = Armas.datos(arma_id)["ranura"]
	var vieja := {"id": slots[i], "mag": ammo[i], "reserve": reserve[i]}
	if i == current:
		_reload_t = -1.0
	_set_slot(i, arma_id)
	ammo[i] = mag
	reserve[i] = res
	if i != current:
		select(i)
	else:
		_switch_t = 0.0      # la animación de cambio, para que se note
		_switch_to = i
	return vieja


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
	if index == current or index < 0 or index >= slots.size() or _switch_t >= 0.0 or _throw_t >= 0.0:
		return
	_reload_t = -1.0  # cambiar de arma cancela la recarga
	_switch_t = 0.0
	_switch_to = index
	Game.play("click", -6.0)


func next_weapon() -> void:
	select((current + 1) % slots.size())


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

	# Automáticas: siguen disparando mientras el gatillo esté apretado
	if trigger_held and w.get("auto", false) and _cooldown <= 0.0 and ammo[current] > 0 \
			and not busy() and not _player.sprinting and not _player.dead:
		_fire()

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
	spread_now += _player.supresion * 2.5   # con balas pasando cerca cuesta apuntar

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
	# (la recarga la anima hud.gd con su propio clip/cargador)
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


## true mientras se mira por una mira telescópica (el HUD dibuja el círculo).
func scoped() -> bool:
	return def().get("scope", false) and ads_amount > 0.6


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
	Game.play(w["sound"], 0.0, w.get("pitch", 1.0) * randf_range(0.94, 1.06))
	if not w.get("rocket", false):
		shots_fired += 1
	if w.get("recarga", "") == "clip" and ammo[current] == 0:
		clips_ejected += 1
		get_tree().create_timer(0.12).timeout.connect(func() -> void: Game.play("ping", -3.0))

	flash_2d = 0.06

	# Disparo instantáneo (rayo) desde el centro de la pantalla
	var b := _camera.global_basis
	var spread := tan(deg_to_rad(spread_now))
	var ang := randf() * TAU
	var rad := sqrt(randf()) * spread
	var dir := (-b.z + b.x * cos(ang) * rad + b.y * sin(ang) * rad).normalized()
	var from := _camera.global_position
	if w.get("rocket", false):
		Cohete.lanzar(get_tree().current_scene, from + dir * 0.6, dir, w["damage"])
		_player.look(Vector2(0, -deg_to_rad(w["recoil"])))
		_recoil_left += deg_to_rad(w["recoil"]) * RECOIL_RECOVERY
		return
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
	if Red.activo():   # que los demás jugadores vean la trazadora
		Red.disparo(from + dir * 0.6, hit["position"] if not hit.is_empty() else from + dir * 120.0)
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
