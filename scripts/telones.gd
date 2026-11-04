extends Node3D
class_name Telones
## Telones de los costados (sección 6): la zona de juego es el piso de una
## "caja" y sus paredes muestran la batalla que sigue más allá. Cada telón es
## una imagen de ChatGPT pixelada (assets/telones/, tools/arte/telones.py)
## puesta lejos, detrás del decorado, parada sobre el suelo. Solo se usa la
## parte de arriba de la imagen (lo lejano: horizonte, acantilados, humo,
## pueblos); lo de primer plano no calzaría con la perspectiva. Así el telón
## se ve como el terreno que sigue y sube un poco hacia el horizonte.
## Encima, animación hecha
## en el juego: columnas de humo, explosiones lejanas con su fogonazo y su
## ruido, ráfagas y trazadoras.
## Barato para el celular: 5 planos, unas pocas partículas y nada de física.

## [imagen, centro, giro (grados), ancho en m, altura del suelo, espejo, corte]
## corte = hasta qué fila de la imagen se usa (fracción desde arriba).
## Playa: x ±140, de z +65 a −85. Meseta: x ±140, de z −70 a −230. Fondo: z −229.
const PLANOS := [
	["telon_playa_izq", Vector3(-140, 0, -10), 90.0, 150.0, 0.0, false, 0.43],
	["telon_playa_der", Vector3(140, 0, -10), -90.0, 150.0, 0.0, false, 0.43],
	["telon_meseta", Vector3(-140, 0, -150), 90.0, 160.0, 14.0, false, 0.30],
	["telon_pueblo", Vector3(140, 0, -150), -90.0, 160.0, 14.0, false, 0.33],
	["telon_meseta", Vector3(0, 0, -229), 0.0, 290.0, 14.0, true, 0.22],
]
## Lugares de la batalla lejana (delante de los telones): [centro, ancho z, suelo]
const ZONAS := [
	[Vector3(-118, 0, 0), 60.0, 0.0], [Vector3(118, 0, 0), 60.0, 0.0],
	[Vector3(-122, 14, -150), 90.0, 14.0], [Vector3(122, 14, -150), 90.0, 14.0],
]

var _rng := RandomNumberGenerator.new()
var _t_boom := 3.0
var _t_rafaga := 5.0
var _t_traza := 2.0
var _bocanadas: Array = []       # humo de explosiones (reserva)
var _fogonazos: Array = []
var _mat_humo: StandardMaterial3D
var _columnas: Array = []
var _arriba_visto := -1
static var actual: Telones
static var _shader: Shader          # uno solo para los cinco telones (se compila una vez)


func _exit_tree() -> void:
	if actual == self:
		actual = null


## Para Game.warmup: un fogonazo y una bocanada frente a la cámara mientras
## está la pantalla de "PREPARANDO" (así el navegador compila sus materiales).
func calentar(p: Vector3) -> void:
	var fl: MeshInstance3D = _fogonazos[0]
	fl.global_position = p
	fl.set_meta("t", 0.2)
	fl.visible = true
	var b: CPUParticles3D = _bocanadas[0]
	b.global_position = p
	b.restart()
	var c: CPUParticles3D = _columnas[0]
	var antes := c.global_position
	c.global_position = p
	c.visible = true
	await get_tree().create_timer(0.3).timeout
	c.global_position = antes
	b.global_position = Vector3(0, -50, 0)
	b.restart()
	b.emitting = false
	_arriba_visto = -1


func _ready() -> void:
	actual = self
	_rng.randomize()
	var datos := {}
	var f := FileAccess.open("res://assets/telones/telones.json", FileAccess.READ)
	if f:
		datos = JSON.parse_string(f.get_as_text())
	var niebla := Color(0.6, 0.62, 0.64)
	var env := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if env and env.environment:
		niebla = env.environment.fog_light_color
	for p in PLANOS:
		var ruta := "res://assets/telones/%s.png" % p[0]
		if not ResourceLoader.exists(ruta) or not datos.has(p[0]):
			continue
		var d: Dictionary = datos[p[0]]
		var ancho: float = p[3]
		var corte: float = p[6]
		var alto: float = ancho * float(d["proporcion"]) * corte
		var q := QuadMesh.new()
		q.size = Vector2(ancho, alto)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material(load(ruta), niebla, p[5], corte)
		mi.position = Vector3(p[1].x, p[4] + alto / 2.0 - 0.6, p[1].z)    # apoyado en el suelo
		mi.rotation_degrees.y = p[2]
		add_child(mi)
	_mat_humo = _material_humo()
	# Columnas de humo que no paran (solo se ven las de donde anda el jugador)
	for z in ZONAS:
		for k in 2:
			var pos: Vector3 = z[0] + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-z[1] / 2.0, z[1] / 2.0))
			_columna(pos, z[2] > 5.0)
	# Reservas para las explosiones lejanas
	for i in 4:
		var b := _particulas(14, 3.5, 0.9, Vector3(0, -50, 0), false)
		b.one_shot = true
		add_child(b)
		_bocanadas.append(b)
		var fl := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(9, 9)
		fl.mesh = fq
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.albedo_texture = _textura_redonda(Color(1.0, 0.75, 0.35))
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.disable_fog = true
		fl.material_override = fm
		fl.visible = false
		add_child(fl)
		_fogonazos.append(fl)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var arriba := 1 if cam != null and cam.global_position.y > 8.0 else 0
	if arriba != _arriba_visto:
		_arriba_visto = arriba
		for c in _columnas:
			c.visible = bool(c.get_meta("arriba")) == (arriba == 1)
	_t_boom -= delta
	_t_rafaga -= delta
	_t_traza -= delta
	for fl in _fogonazos:
		if fl.visible:
			var t: float = fl.get_meta("t", 0.0) - delta
			fl.set_meta("t", t)
			fl.scale = Vector3.ONE * clampf(t / 0.35, 0.0, 1.0)
			fl.visible = t > 0.0
	if _t_boom <= 0.0:
		_t_boom = _rng.randf_range(2.0, 5.5)
		_explosion(_lugar())
	if _t_rafaga <= 0.0:
		_t_rafaga = _rng.randf_range(3.0, 7.0)
		_rafaga(_lugar())
	if _t_traza <= 0.0:
		_t_traza = _rng.randf_range(0.6, 1.8)
		var a := _lugar() + Vector3(0, 1.2, 0)
		var b := a + Vector3(_rng.randf_range(-6, 6), _rng.randf_range(0, 3), _rng.randf_range(-40, 40))
		var verde := _rng.randf() < 0.4      # alemanas verdosas, americanas rojizas
		Game.tracer(a, b, Color(0.6, 1.0, 0.5) if verde else Color(1.0, 0.55, 0.3), 2.5)


## Un punto de la batalla lejana, cerca de donde anda el jugador.
func _lugar() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var arriba := cam != null and cam.global_position.y > 8.0
	var opciones: Array = ZONAS.filter(func(z: Array) -> bool: return (z[2] > 5.0) == arriba)
	var z: Array = opciones[_rng.randi() % opciones.size()]
	return z[0] + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-z[1] / 2.0, z[1] / 2.0))


func _explosion(pos: Vector3) -> void:
	var fl: MeshInstance3D = _fogonazos.pop_front()
	_fogonazos.append(fl)
	fl.global_position = pos + Vector3(0, 2.5, 0)
	fl.set_meta("t", 0.35)
	fl.visible = true
	var b: CPUParticles3D = _bocanadas.pop_front()
	_bocanadas.append(b)
	b.global_position = pos + Vector3(0, 1.5, 0)
	b.restart()
	Game.play_at("explosion_lejos", pos, 6.0)


## Ráfaga lejana de ametralladora: varios tiros seguidos.
func _rafaga(pos: Vector3) -> void:
	Game.play_at("mg42_lejos", pos, 4.0)


func _columna(pos: Vector3, arriba: bool) -> void:
	var c := _particulas(7, 1.2, 0.35, pos, true)
	c.lifetime = 12.0
	c.preprocess = 12.0
	c.set_meta("arriba", arriba)
	add_child(c)
	_columnas.append(c)


## Partículas de humo, YA configuradas y en su lugar antes de entrar al árbol
## (si no, el primer cuadro sueltan humo en el origen del mundo, delante del
## jugador: era la mancha negra al empezar la playa).
func _particulas(n: int, vel: float, fuerza: float, pos: Vector3, emitir: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = emitir
	p.position = pos
	p.amount = n
	p.lifetime = 4.0
	var q := QuadMesh.new()
	q.size = Vector2(7, 7)
	q.material = _mat_humo
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0.6, 0.25, 0)
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.explosiveness = fuerza
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.4))
	curva.add_point(Vector2(1, 1.8))
	p.scale_amount_curve = curva
	var grad := Gradient.new()
	grad.set_color(0, Color(0.32, 0.31, 0.3, 0.85))
	grad.set_color(1, Color(0.55, 0.55, 0.55, 0.0))
	p.color_ramp = grad
	return p


func _material(tex: Texture2D, niebla: Color, espejo: bool, corte: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
	shader_type spatial;
	render_mode unshaded, cull_disabled, fog_disabled;
	uniform sampler2D tex : source_color, filter_nearest;
	uniform vec3 niebla : source_color;
	uniform float cuanto = 0.45;
	uniform bool espejo = false;
	uniform float corte = 1.0;
	void fragment() {
		vec2 uv = vec2(UV.x, UV.y * corte);
		if (espejo) { uv.x = 1.0 - uv.x; }
		vec4 c = texture(tex, uv);
		if (c.a < 0.5) { discard; }
		ALBEDO = mix(c.rgb, niebla, cuanto);
	}
	"""

	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("niebla", niebla)
	m.set_shader_parameter("espejo", espejo)
	m.set_shader_parameter("corte", corte)
	return m


func _material_humo() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _textura_redonda(Color.WHITE)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


## Mancha redonda pixelada (humo o fogonazo).
func _textura_redonda(col: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 8.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = 0.0 if a < 0.12 else minf(a * 1.6, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
