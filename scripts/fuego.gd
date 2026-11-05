extends Node3D
class_name Fuego
## Un fuego que no se apaga (misiones de noche): un planeador estrellado, una
## casa o un granero ardiendo. Llamas y humo con partículas (pocas), una luz
## anaranjada que tiembla y cuenta para la vista de noche (Noche.luces): junto
## a un fuego se te ve.

static var _mat_llama: StandardMaterial3D
static var _mat_humo: StandardMaterial3D

@export var tam := 1.0            # 1 = fogata grande (un planeador); 2 = una casa

var _luz: OmniLight3D
var _t := randf() * 10.0
var _base := 1.8


static func encender(padre: Node3D, pos: Vector3, tamano := 1.0) -> Fuego:
	var f := Fuego.new()
	f.tam = tamano
	padre.add_child(f)
	f.global_position = pos
	return f


func _ready() -> void:
	if _mat_llama == null:
		_mat_llama = StandardMaterial3D.new()
		_mat_llama.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_llama.vertex_color_use_as_albedo = true
		_mat_llama.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_llama.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat_llama.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mat_llama.albedo_texture = Bengala._textura_brillo() if Bengala._tex == null else Bengala._tex
		_mat_humo = StandardMaterial3D.new()
		_mat_humo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_humo.vertex_color_use_as_albedo = true
		_mat_humo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_humo.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mat_humo.albedo_texture = _mat_llama.albedo_texture
	var llamas := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1) * tam
	q.material = _mat_llama
	llamas.mesh = q
	llamas.amount = int(10 * tam)
	llamas.lifetime = 0.9
	llamas.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	llamas.emission_box_extents = Vector3(1.2, 0.2, 1.2) * tam
	llamas.direction = Vector3.UP
	llamas.spread = 15.0
	llamas.gravity = Vector3(0, 2.2, 0)
	llamas.initial_velocity_min = 0.6
	llamas.initial_velocity_max = 1.4
	llamas.scale_amount_min = 0.6
	llamas.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	g.set_color(1, Color(0.7, 0.15, 0.02, 0.0))
	llamas.color_ramp = g
	add_child(llamas)
	var humo := CPUParticles3D.new()
	var qh := QuadMesh.new()
	qh.size = Vector2(2.4, 2.4) * tam
	qh.material = _mat_humo
	humo.mesh = qh
	humo.amount = int(6 * tam)
	humo.lifetime = 4.0
	humo.position = Vector3(0, 1.5 * tam, 0)
	humo.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	humo.emission_sphere_radius = 0.8 * tam
	humo.direction = Vector3.UP
	humo.spread = 10.0
	humo.gravity = Vector3(0.4, 1.0, 0)
	humo.initial_velocity_min = 0.5
	humo.initial_velocity_max = 1.0
	humo.scale_amount_min = 0.8
	humo.scale_amount_max = 1.8
	var gh := Gradient.new()
	gh.set_color(0, Color(0.12, 0.11, 0.1, 0.45))
	gh.set_color(1, Color(0.08, 0.08, 0.09, 0.0))
	humo.color_ramp = gh
	add_child(humo)
	_luz = OmniLight3D.new()
	_luz.light_color = Color(1.0, 0.55, 0.22)
	_luz.omni_range = 13.0 * sqrt(tam)
	_luz.omni_attenuation = 1.1
	_luz.shadow_enabled = false
	_luz.position = Vector3(0, 1.4 * tam, 0)
	_base = 1.7 * sqrt(tam)
	add_child(_luz)
	Noche.agregar_luz(self, 10.0 * sqrt(tam))


func _process(delta: float) -> void:
	_t += delta
	_luz.light_energy = _base * (0.8 + 0.12 * sin(_t * 9.0) + 0.08 * sin(_t * 23.0 + 1.3))


func _exit_tree() -> void:
	Noche.quitar_luz(self)
