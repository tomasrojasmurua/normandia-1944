extends Node3D
## Escenario de prueba: coloca erizos checos (obstáculos antitanque), un
## búnker, sacos de arena y el acantilado del fondo, y viste todo con las
## texturas (assets/texturas, hechas con tools/arte/adaptar_imagenes.py).
## La forma del nivel es provisional: en la sección de mapas se reemplaza
## por el nivel de verdad, pero los materiales se reutilizan.

@export var hedgehog_count := 18
@export var area := Vector2(60, 30)
@export var seed_value := 1944

const TEX := "res://assets/texturas/textura_%s.png"

var _steel: StandardMaterial3D
var _concrete: StandardMaterial3D
var _sand_bags: StandardMaterial3D
var _grass: StandardMaterial3D
var _wood: StandardMaterial3D
var _dark := Game.material(Color(0.04, 0.04, 0.035))


## Material con la textura proyectada desde el mundo (no hace falta UV):
## "metros" = cuántos metros cubre una repetición de la textura de 64 px.
static func textured(nombre: String, metros: float, tinte := Color.WHITE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX % nombre)
	mat.albedo_color = tinte
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / metros
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


func _ready() -> void:
	_steel = textured("acero_oxidado", 1.2)
	_concrete = textured("concreto", 3.0)
	_sand_bags = textured("sacos_arena", 2.4)
	_grass = textured("pasto_duna", 2.5, Color(0.85, 0.85, 0.8))
	_wood = textured("madera", 2.0)
	_dress_ground_and_sea()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in hedgehog_count:
		var pos := Vector3(rng.randf_range(-area.x / 2, area.x / 2), 0, rng.randf_range(-area.y, -4))
		_add_hedgehog(pos, rng.randf() * TAU)

	# Búnker de concreto con tronera (franja oscura) hacia el mar
	_add_box(Vector3(0, 1.5, -42), Vector3(14, 3, 5), _concrete)
	_add_box(Vector3(0, 3.2, -42), Vector3(15, 0.5, 6), _concrete)  # techo
	Game.box(self, Vector3(8, 0.45, 0.1), Vector3(0, 2.0, -39.47), _dark)

	# Sacos de arena donde se cubren los enemigos
	_add_box(Vector3(-4.5, 0.45, -36), Vector3(6, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(5, 0.45, -36), Vector3(6, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(-14, 0.45, -24), Vector3(3, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(13, 0.45, -20), Vector3(3, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(2, 3.9, -39.6), Vector3(3, 0.5, 0.4), _sand_bags)  # parapeto en el techo

	# Postes de madera clavados en la arena (obstáculos de playa)
	for i in 10:
		var p := Vector3(rng.randf_range(-area.x / 2, area.x / 2), 0, rng.randf_range(-9, 0))
		var tilt := Vector3(rng.randf_range(-25, -10), 0, rng.randf_range(-12, 12))
		_add_box(p + Vector3(0, 1.0, 0), Vector3(0.22, 2.6, 0.22), _wood, tilt)

	_add_bluffs()


## Suelo (arena mojada → seca → guijarros → pasto) y mar con espuma.
func _dress_ground_and_sea() -> void:
	var ground := get_node_or_null("../Ground/Mesh") as MeshInstance3D
	if ground:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/terreno.gdshader")
		m.set_shader_parameter("arena_mojada", load(TEX % "arena_mojada"))
		m.set_shader_parameter("arena_seca", load(TEX % "arena_seca"))
		m.set_shader_parameter("guijarros", load(TEX % "guijarros"))
		m.set_shader_parameter("pasto", load(TEX % "pasto_duna"))
		ground.material_override = m
	var sea := get_node_or_null("../Sea") as MeshInstance3D
	if sea:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/mar.gdshader")
		m.set_shader_parameter("agua", load(TEX % "agua_mar"))
		sea.material_override = m


## Acantilado cubierto de pasto detrás del búnker (como los de Omaha).
func _add_bluffs() -> void:
	var slope := 30.0
	var h := 14.0
	var depth := h / tan(deg_to_rad(slope))
	_add_box(Vector3(0, h / 2.0 - 0.6, -56 - depth / 2.0), Vector3(500, 1.0, h / sin(deg_to_rad(slope))),
		_grass, Vector3(slope, 0, 0))
	_add_box(Vector3(0, h - 0.5, -56 - depth - 30), Vector3(500, 1.0, 60), _grass)

func _add_hedgehog(pos: Vector3, yaw: float) -> void:
	var root := StaticBody3D.new()
	root.position = pos + Vector3(0, 0.7, 0)
	root.rotation.y = yaw
	add_child(root)
	var beam := BoxMesh.new()
	beam.size = Vector3(0.18, 0.18, 2.0)
	var rotations := [Vector3(45, 0, 0), Vector3(-45, 90, 0), Vector3(0, 45, 90)]
	# La colisión son las mismas tres vigas que se ven (antes era una caja
	# invisible que bloqueaba las balas que pasaban por los huecos).
	var beam_shape := BoxShape3D.new()
	beam_shape.size = beam.size
	for r in rotations:
		var m := MeshInstance3D.new()
		m.mesh = beam
		m.material_override = _steel
		m.rotation_degrees = r
		root.add_child(m)
		var col := CollisionShape3D.new()
		col.shape = beam_shape
		col.rotation_degrees = r
		root.add_child(col)


func _add_box(pos: Vector3, box_size: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	add_child(body)
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	m.mesh = mesh
	m.material_override = mat
	body.add_child(m)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)
