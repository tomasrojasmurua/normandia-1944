extends Node
## "Game": servicios globales del juego (se carga solo, como Autoload).
## - Sonidos: se generan por código al arrancar (no hay archivos de audio todavía).
## - Efectos: sangre, polvo, trazadoras y explosiones.
## - Mensajes para el registro del HUD ("[ENEMIGO ABATIDO]", etc.).
## - Reloj de la misión (empieza a las 06:30, hora H del Día D).

signal message(text: String, color: Color)

const RATE := 22050
const COLOR_INFO := Color(0.95, 0.85, 0.4)
const COLOR_BAD := Color(1.0, 0.35, 0.3)
const COLOR_GOOD := Color(0.55, 0.95, 0.45)

var start_minutes := 6 * 60 + 30
var elapsed := 0.0

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _rng := RandomNumberGenerator.new()
var _mat_cache := {}

## Ajustes guardados en el celular/PC.
const AJUSTES := "user://ajustes.cfg"
## Controles táctiles en modo GARRA (FUEGO extra arriba a la izquierda).
var garra := false
## Disparo táctil "al soltar": mantener FUEGO apunta por la mira, soltarlo dispara.
var disparo_soltar := false
var soldados_3d := false       # true = modelos 3D (pesados); false = sprites

## Desde qué Z empieza el agua (lo fija el escenario). Los impactos ahí salpican.
var sea_from_z := INF
## true mientras se "precalientan" los efectos al empezar (el HUD tapa la pantalla).
var warming := false
var _warmed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1944
	var cfg := ConfigFile.new()
	if cfg.load(AJUSTES) == OK:
		garra = cfg.get_value("controles", "garra", false)
		disparo_soltar = cfg.get_value("controles", "disparo_soltar", false)
		soldados_3d = cfg.get_value("graficos", "soldados_3d", false)
	_build_sounds()
	_crear_marcas()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


# --- Para el medidor: cuánto tarda NUESTRO código (guiones) en cada cuadro.
# Dos marcas: una corre antes que todos los guiones y otra después, en el
# proceso y en la física. Lo que falta para el total del cuadro es el motor
# (física, dibujo) y el navegador.
var codigo_cuadro_us := 0     # guiones del último cuadro completo (proceso + física)
var _t_proc := 0
var _t_fis := 0
var _fis_acum := 0
var _fis_cuadro := 0


class Marca extends Node:
	var fin := false
	var g: Node
	func _process(_d: float) -> void:
		if fin:
			g.codigo_cuadro_us = Time.get_ticks_usec() - g._t_proc + g._fis_cuadro
		else:
			g._t_proc = Time.get_ticks_usec()
			g._fis_cuadro = g._fis_acum
			g._fis_acum = 0
	func _physics_process(_d: float) -> void:
		if fin:
			g._fis_acum += Time.get_ticks_usec() - g._t_fis
		else:
			g._t_fis = Time.get_ticks_usec()


func _crear_marcas() -> void:
	for fin in [false, true]:
		var m := Marca.new()
		m.fin = fin
		m.g = self
		m.process_mode = Node.PROCESS_MODE_ALWAYS
		m.process_priority = 100000 if fin else -100000
		m.process_physics_priority = 100000 if fin else -100000
		add_child(m)


var _players_3d: Array = []
var _next_3d := 0
var _trazadoras: Array = []
var _next_traz := 0
var _emisores := {}           # tipo de estallido → [CPUParticles3D]


func _process(delta: float) -> void:
	if not get_tree().paused:
		elapsed += delta


## Se llama al empezar una misión (y al reiniciar tras morir).
func reset_mission() -> void:
	elapsed = 0.0


## Soldados con sprites (liviano, por defecto) o con los modelos 3D (para comparar).
func cambiar_soldados() -> void:
	soldados_3d = not soldados_3d
	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("graficos", "soldados_3d", soldados_3d)
	cfg.save(AJUSTES)


func cambiar_garra() -> void:
	garra = not garra
	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("controles", "garra", garra)
	cfg.save(AJUSTES)


func cambiar_disparo() -> void:
	disparo_soltar = not disparo_soltar
	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("controles", "disparo_soltar", disparo_soltar)
	cfg.save(AJUSTES)


## Ir al menú principal / empezar la misión.
func ir_al_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func empezar_mision() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func clock_text() -> String:
	var total := start_minutes + int(elapsed / 60.0)
	return "%02d:%02d" % [(total / 60) % 24, total % 60]


func say(text: String, color: Color = COLOR_INFO) -> void:
	message.emit(text, color)


# ---------------------------------------------------------------- sonido

func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(sound):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sounds[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Sonido en un punto del mundo. Usa una reserva fija de reproductores 3D que
## se reciclan (antes se creaba y borraba uno por disparo: en el navegador del
## celular eso cuesta y trababa el juego en los tiroteos).
func play_at(sound: String, pos: Vector3, volume_db := 0.0) -> void:
	if not _sounds.has(sound):
		return
	if _players_3d.is_empty():
		for i in 16:
			var n := AudioStreamPlayer3D.new()
			n.unit_size = 12.0
			n.max_distance = 200.0
			add_child(n)
			_players_3d.append(n)
	# El siguiente libre; si todos suenan, el más antiguo
	var p: AudioStreamPlayer3D = _players_3d[_next_3d]
	for i in _players_3d.size():
		var c: AudioStreamPlayer3D = _players_3d[(_next_3d + i) % _players_3d.size()]
		if not c.playing:
			p = c
			_next_3d = (_next_3d + i) % _players_3d.size()
			break
	_next_3d = (_next_3d + 1) % _players_3d.size()
	p.stream = _sounds[sound]
	p.volume_db = volume_db
	p.pitch_scale = _rng.randf_range(0.92, 1.06)
	p.global_position = pos
	p.play()


func _build_sounds() -> void:
	# nombre: [duración en segundos, brillo del ruido 0..1]
	var specs := {
		"rifle": [0.55, 0.35], "pistol": [0.32, 0.5], "rifle_far": [0.9, 0.08],
		"ping": [0.7, 1.0], "click": [0.06, 1.0], "reload": [0.9, 0.9],
		"explosion": [1.8, 0.06], "hurt": [0.3, 0.2], "hit": [0.07, 1.0],
		"throw": [0.35, 0.25], "bounce": [0.08, 0.5],
	}
	for sound in specs:
		_sounds[sound] = _make(sound, specs[sound][0], specs[sound][1])


## Forma de onda de cada sonido en el instante `t` (segundos); `n` es ruido.
func _sample(sound: String, t: float, n: float) -> float:
	match sound:
		"rifle":
			return n * exp(-t * 13.0) * 0.9 + sin(TAU * 55.0 * t) * exp(-t * 18.0) * 0.8
		"pistol":
			return n * exp(-t * 22.0) * 0.85 + sin(TAU * 90.0 * t) * exp(-t * 30.0) * 0.5
		"rifle_far":
			return n * exp(-t * 7.0) * 0.7 + sin(TAU * 45.0 * t) * exp(-t * 10.0) * 0.4
		"ping":  # el clip del Garand saltando al vaciarse
			return (sin(TAU * 2950.0 * t) * 0.35 + sin(TAU * 4180.0 * t) * 0.18) * exp(-t * 6.5) \
				+ n * exp(-t * 300.0) * 0.4
		"click":
			return n * exp(-t * 180.0) * 0.6 + sin(TAU * 1400.0 * t) * exp(-t * 120.0) * 0.3
		"reload":
			var a := n * exp(-t * 150.0) * 0.5
			var t2 := t - 0.45
			if t2 > 0.0:
				a += n * exp(-t2 * 120.0) * 0.6 + sin(TAU * 900.0 * t2) * exp(-t2 * 80.0) * 0.3
			return a
		"explosion":
			return n * exp(-t * 2.6) + sin(TAU * 38.0 * t) * exp(-t * 4.0) * 0.9
		"hurt":
			return sin(TAU * (140.0 - t * 200.0) * t) * exp(-t * 12.0) * 0.8 + n * exp(-t * 25.0) * 0.3
		"hit":
			return sin(TAU * 1900.0 * t) * exp(-t * 60.0) * 0.35
		"throw":
			return n * sin(PI * t / 0.35) * 0.35
		"bounce":
			return n * exp(-t * 90.0) * 0.5 + sin(TAU * 600.0 * t) * exp(-t * 70.0) * 0.3
	return 0.0


## Genera un sonido. `brightness` (0..1) filtra el ruido: bajo = grave y apagado.
func _make(sound: String, seconds: float, brightness: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * brightness
		var v := _sample(sound, t, lp)
		var fade := clampf((seconds - t) / 0.02, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * fade, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


# ---------------------------------------------------------------- efectos

func blood(pos: Vector3) -> void:
	_burst(pos, Color(0.55, 0.04, 0.03), 14, 2.5, 0.6, 0.06, Vector3.UP, 1.0)


func dust(pos: Vector3, normal := Vector3.UP) -> void:
	if pos.z > sea_from_z and pos.y < 0.3:
		splash(pos)
		return
	_burst(pos, Color(0.7, 0.64, 0.5), 8, 2.0, 0.5, 0.05, normal, 0.6)


## Salpicadura de agua: columna blanca que sube y cae.
func splash(pos: Vector3) -> void:
	pos.y = maxf(pos.y, 0.05)
	_burst(pos, Color(0.85, 0.88, 0.86), 12, 4.0, 0.7, 0.06, Vector3.UP, 1.0, 12.0)
	_burst(pos, Color(0.6, 0.66, 0.64), 6, 1.5, 0.5, 0.09, Vector3.UP, 0.8, 40.0)


## Precalentar: los navegadores compilan cada efecto la primera vez que se
## dibuja, y eso traba el juego un momento. Aquí se dibuja uno de cada uno
## frente a la cámara al empezar, mientras el HUD muestra "PREPARANDO".
func warmup() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _warmed:
		return
	_warmed = true
	warming = true
	var p := cam.global_position - cam.global_basis.z * 3.0
	blood(p)
	_burst(p, Color(0.7, 0.64, 0.5), 8, 2.0, 0.5, 0.05, Vector3.UP, 0.6)
	splash(p)
	tracer(p + cam.global_basis.x, p - cam.global_basis.x)
	_explosion_fx(p)
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	warming = false


## Trazadora de bala. Reserva fija de 32 que se reciclan (ver play_at).
func tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.75, 0.3)) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	if _trazadoras.is_empty():
		var box := BoxMesh.new()
		box.size = Vector3(0.025, 0.025, 1.0)
		for i in 32:
			var n := MeshInstance3D.new()
			n.mesh = box
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			n.material_override = mat
			n.visible = false
			add_child(n)
			_trazadoras.append(n)
	var m: MeshInstance3D = _trazadoras[_next_traz]
	_next_traz = (_next_traz + 1) % _trazadoras.size()
	if m.has_meta("tw"):
		var viejo: Tween = m.get_meta("tw")
		if viejo and viejo.is_valid():
			viejo.kill()
	var mat: StandardMaterial3D = m.material_override
	mat.albedo_color = color
	var largo := minf(length, 6.0)
	var dir := (to - from).normalized()
	m.global_position = from
	m.look_at(from + dir, Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP)
	m.scale = Vector3(1, 1, largo)
	m.visible = true
	var tw := m.create_tween()
	m.set_meta("tw", tw)
	var travel := minf(length / 250.0, 0.25)  # la trazadora "viaja" hasta el blanco
	tw.tween_property(m, "global_position", to - dir * largo * 0.5, travel)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, travel + 0.05)
	tw.tween_callback(func() -> void: m.visible = false)


## Explosión de granada: efecto visual, sonido y daño en un radio.
func explode(pos: Vector3, radius: float, damage: float) -> void:
	play_at("explosion", pos, 6.0)
	_explosion_fx(pos)
	for e in get_tree().get_nodes_in_group("enemies"):
		var chest: Vector3 = e.global_position + Vector3(0, 1.0, 0)
		var d := pos.distance_to(chest)
		if d < radius and _clear_path(pos, chest):
			e.hit(damage * (1.0 - d / radius), false, chest, (chest - pos).normalized())
	for a in get_tree().get_nodes_in_group("aliados"):
		var c: Vector3 = a.global_position + Vector3(0, 1.0, 0)
		var da := pos.distance_to(c)
		if da < radius and _clear_path(pos, c):
			a.take_damage(damage * 0.8 * (1.0 - da / radius), pos)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var center: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		var d := pos.distance_to(center)
		if d < radius and _clear_path(pos, center):
			player.take_damage(damage * 0.8 * (1.0 - d / radius), pos)
		if d < 30.0:
			player.shake(1.2 * (1.0 - d / 30.0))


## Lo visual de la explosión: bola de fuego, humo y tierra (o agua).
func _explosion_fx(pos: Vector3) -> void:
	var fire := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	fire.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.7, 0.25, 0.95)
	fire.material_override = mat
	_scene().add_child(fire)
	fire.global_position = pos
	fire.scale = Vector3.ONE * 0.2
	var tw := fire.create_tween()
	tw.tween_property(fire, "scale", Vector3.ONE * 2.2, 0.12)
	tw.tween_property(mat, "albedo_color", Color(0.3, 0.28, 0.25, 0.0), 0.3)
	tw.tween_callback(fire.queue_free)
	_burst(pos, Color(0.32, 0.31, 0.29), 18, 2.5, 1.6, 0.45, Vector3.UP, -0.15)
	if pos.z > sea_from_z and pos.y < 0.5:
		_burst(pos, Color(0.85, 0.88, 0.86), 30, 9.0, 1.2, 0.12, Vector3.UP, 1.2, 15.0)
	else:
		_burst(pos, Color(0.42, 0.36, 0.26), 26, 7.0, 1.0, 0.12, Vector3.UP, 1.5)


func _clear_path(from: Vector3, to: Vector3) -> bool:
	var space := get_tree().root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.3, 0), to, 1)  # solo escenario
	return space.intersect_ray(q).is_empty()


## Estallido de partículas (polvo, sangre, agua, humo). Cada tipo tiene su
## reserva de emisores que se reciclan (ver play_at).
func _burst(pos: Vector3, color: Color, amount: int, speed: float, life: float,
		size: float, dir: Vector3, gravity_scale: float, spread := 55.0) -> void:
	var clave := "%s|%d|%.2f|%.2f|%.2f|%.2f|%.1f" % [color.to_html(), amount, speed, life, size, gravity_scale, spread]
	if not _emisores.has(clave):
		_emisores[clave] = []
	var lista: Array = _emisores[clave]
	var p: CPUParticles3D = null
	for e: CPUParticles3D in lista:
		if not e.emitting:
			p = e
			break
	if p == null:
		if lista.size() < 12:
			p = CPUParticles3D.new()
			p.one_shot = true
			p.emitting = false
			p.amount = amount
			p.lifetime = life
			p.explosiveness = 1.0
			p.local_coords = false
			var box := BoxMesh.new()
			box.size = Vector3.ONE * size
			box.material = _unshaded(color)
			p.mesh = box
			p.spread = spread
			p.initial_velocity_min = speed * 0.4
			p.initial_velocity_max = speed
			p.gravity = Vector3(0, -9.8 * gravity_scale, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.2
			add_child(p)
			lista.append(p)
		else:
			p = lista.pop_front()   # todos ocupados: se recicla el más antiguo
			lista.append(p)
	p.direction = dir
	p.global_position = pos
	p.restart()


func _unshaded(color: Color) -> StandardMaterial3D:
	if not _mat_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		_mat_cache[color] = mat
	return _mat_cache[color]


func _scene() -> Node:
	var s := get_tree().current_scene
	return s if s else get_tree().root


## Ayudante para construir modelos con cajas (armas, soldados, granadas).
static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot_deg
	parent.add_child(m)
	return m


static func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return mat
