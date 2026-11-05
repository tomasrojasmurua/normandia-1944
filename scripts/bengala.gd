extends Node3D
class_name Bengala
## Bengala de iluminación alemana (misiones de noche, ver noche.gd). La
## dispara un alemán con su pistola de señales: sube silbando (~1,5 s), se
## enciende arriba y baja despacio meciéndose (~11 s) mientras ilumina el campo
## de blanco. Lo que está bajo su luz se ve como de día (Noche.factor_vista):
## de pie te ven; cuerpo a tierra, no.
## Se dibuja con una luz de verdad (OmniLight3D) y un resplandor que siempre
## mira a la cámara. Hay pocas a la vez (Defensa espera entre una y otra).

const SUBIDA := 1.6
const VIDA := 11.0
const ALTO := Vector2(38.0, 48.0)
const BAJA := 2.0                 # m/s
const RADIO_VISTA := 38.0         # hasta dónde "ilumina" para la vista de la IA
const ALCANCE_LUZ := 62.0

static var _tex: Texture2D
static var _mat_brillo: StandardMaterial3D
static var _mat_nucleo: StandardMaterial3D

var _desde := Vector3.ZERO
var _arriba := Vector3.ZERO
var _t := 0.0
var _luz: OmniLight3D
var _brillo: MeshInstance3D
var _info: Dictionary = {}
var _fase := randf() * 10.0
var _humo := 0.0


static func disparar(escena: Node, desde: Vector3, hacia: Vector3) -> Bengala:
	var b := Bengala.new()
	b._desde = desde
	var alto := randf_range(ALTO.x, ALTO.y)
	b._arriba = Vector3(hacia.x, alto, hacia.z)
	escena.add_child(b)
	b.global_position = desde
	Game.play_at("bengala", desde, 4.0)
	return b


func _ready() -> void:
	if _tex == null:
		_tex = _textura_brillo()
		_mat_brillo = StandardMaterial3D.new()
		_mat_brillo.albedo_texture = _tex
		_mat_brillo.albedo_color = Color(1.0, 0.95, 0.82, 0.85)
		_mat_brillo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_brillo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_brillo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat_brillo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_mat_brillo.disable_fog = true
		_mat_brillo.no_depth_test = false
		_mat_nucleo = _mat_brillo.duplicate()
		_mat_nucleo.albedo_color = Color(1.0, 1.0, 0.95, 1.0)
	_brillo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(11.0, 11.0)
	_brillo.mesh = q
	_brillo.material_override = _mat_brillo
	_brillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_brillo)
	var nucleo := MeshInstance3D.new()
	var qn := QuadMesh.new()
	qn.size = Vector2(1.5, 1.5)
	nucleo.mesh = qn
	nucleo.material_override = _mat_nucleo
	nucleo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(nucleo)
	_luz = OmniLight3D.new()
	_luz.light_color = Color(1.0, 0.95, 0.84)
	_luz.omni_range = ALCANCE_LUZ
	_luz.omni_attenuation = 0.65
	_luz.light_energy = 0.0
	_luz.shadow_enabled = false
	add_child(_luz)
	_brillo.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _t < SUBIDA:
		# Sube con la estela de la pistola (todavía no ilumina)
		var k := _t / SUBIDA
		var p := _desde.lerp(_arriba, 1.0 - (1.0 - k) * (1.0 - k))
		global_position = p
		_humo -= delta
		if _humo <= 0.0:
			_humo = 0.06
			Game._burst(p, Color(0.5, 0.5, 0.5), 1, 0.2, 0.8, 0.12, Vector3.UP, -0.05)
		return
	if _info.is_empty():
		_info = Noche.agregar_luz(self, RADIO_VISTA)
		_brillo.visible = true
		Game.play_at("click", global_position, 0.0)
	var vida := _t - SUBIDA
	# Baja meciéndose con el viento
	_fase += delta
	global_position += Vector3(sin(_fase * 0.9) * 0.6, -BAJA, cos(_fase * 0.7) * 0.25) * delta
	# Parpadea un poco (magnesio ardiendo) y se apaga al final
	var fuerza := clampf(vida / 0.4, 0.0, 1.0) * clampf((VIDA - vida) / 1.6, 0.0, 1.0)
	var parpadeo := 0.9 + 0.1 * sin(_t * 23.0) * sin(_t * 7.3)
	_luz.light_energy = 3.4 * fuerza * parpadeo
	_info["fuerza"] = fuerza
	_brillo.scale = Vector3.ONE * (0.6 + 0.4 * fuerza) * parpadeo
	if vida >= VIDA or global_position.y < 4.0:
		Noche.quitar_luz(self)
		queue_free()


## Un resplandor redondo (blanco en el centro, transparente en los bordes).
static func _textura_brillo() -> Texture2D:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
