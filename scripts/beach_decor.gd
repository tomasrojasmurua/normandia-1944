extends Node3D
## Escenario de prueba: coloca erizos checos (obstáculos antitanque) y un
## búnker en la playa. Es provisional: en la sección de mapas se reemplaza
## por el nivel de verdad.

@export var hedgehog_count := 18
@export var area := Vector2(60, 30)
@export var seed_value := 1944

var _steel := StandardMaterial3D.new()
var _concrete := StandardMaterial3D.new()
var _sand_bags := StandardMaterial3D.new()


func _ready() -> void:
	_steel.albedo_color = Color(0.22, 0.2, 0.18)
	_steel.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_concrete.albedo_color = Color(0.5, 0.49, 0.45)
	_concrete.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_sand_bags.albedo_color = Color(0.56, 0.5, 0.36)
	_sand_bags.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in hedgehog_count:
		var pos := Vector3(rng.randf_range(-area.x / 2, area.x / 2), 0, rng.randf_range(-area.y, -4))
		_add_hedgehog(pos, rng.randf() * TAU)

	_add_box(Vector3(0, 1.5, -42), Vector3(14, 3, 5), _concrete)  # búnker
	_add_box(Vector3(0, 3.2, -42), Vector3(15, 0.5, 6), _concrete)  # techo

	# Sacos de arena donde se cubren los enemigos
	_add_box(Vector3(-4.5, 0.45, -36), Vector3(6, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(5, 0.45, -36), Vector3(6, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(-14, 0.45, -24), Vector3(3, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(13, 0.45, -20), Vector3(3, 0.9, 0.6), _sand_bags)
	_add_box(Vector3(2, 3.9, -39.6), Vector3(3, 0.5, 0.4), _sand_bags)  # parapeto en el techo


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


func _add_box(pos: Vector3, box_size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
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
