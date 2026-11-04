extends Node3D
## Escenario de prueba: coloca erizos checos (obstáculos antitanque), un
## búnker, sacos de arena y el acantilado del fondo, y viste todo con las
## texturas (assets/texturas, hechas con tools/arte/adaptar_imagenes.py).
## La forma del nivel es provisional: en la sección de mapas se reemplaza
## por el nivel de verdad, pero los materiales se reutilizan.

@export var hedgehog_count := 18
@export var area := Vector2(60, 30)
@export var seed_value := 1944

## Ancho jugable: de −LIMITE_X a +LIMITE_X (paredes invisibles a los costados).
## Más allá hay una franja de decorado hasta el telón.
const LIMITE_X := 40.0
var _erizos: Array = []      # transformaciones de todos los erizos (se dibujan juntos)
const ALEMANES_EXTRA := 13

const TEX := "res://assets/texturas/textura_%s.png"

var _steel: StandardMaterial3D
var _concrete: StandardMaterial3D
var _sand_bags: StandardMaterial3D
var _grass: StandardMaterial3D
var _wood: StandardMaterial3D
var _dark := Game.material(Color(0.04, 0.04, 0.035))
var _burlap: StandardMaterial3D
var _bags: Array[Transform3D] = []   # todos los sacos, se dibujan juntos (MultiMesh)


## Material con la textura proyectada desde el mundo (no hace falta UV):
## "metros" = cuántos metros cubre una repetición de la textura de 64 px.
static func textured(nombre: String, metros: float, tinte := Color.WHITE) -> StandardMaterial3D:
	return _material_tex(TEX % nombre, metros, tinte)


static func _material_tex(path: String, metros: float, tinte := Color.WHITE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(path)
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
	_burlap = _material_tex("res://assets/texturas/arpillera.png", 0.45)
	_grass = textured("pasto_duna", 2.5, Color(0.85, 0.85, 0.8))
	_wood = textured("madera", 2.0)
	Coberturas.limpiar()
	_dress_ground_and_sea()
	Game.sea_from_z = 10.0   # el mar empieza en z = 10 (igual que z_orilla en los shaders)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in hedgehog_count:
		var pos := Vector3(rng.randf_range(-area.x / 2, area.x / 2), 0, rng.randf_range(-area.y, -4))
		_add_hedgehog(pos, rng.randf() * TAU)
		Coberturas.agregar_erizo(pos)

	# Búnker: dos casamatas de concreto (modelo de Meshy) con la tronera hacia
	# el mar. Las cajas de siempre quedan invisibles: son las que chocan y
	# sostienen a la MG42 del techo.
	_add_box(Vector3(0, 1.5, -42), Vector3(14, 3, 5), _concrete).get_child(0).visible = false
	# Techo: a la altura del techo plano del modelo (3,42 m entre z −43,8 y −40,4;
	# hacia los bordes el modelo baja y antes se caminaba flotando)
	_add_box(Vector3(0, 3.17, -42.1), Vector3(14.4, 0.5, 3.4), _concrete).get_child(0).visible = false
	# Rampa de tablones por detrás (lado de tierra) para subir al techo
	_add_box(Vector3(5.6, 1.62, -46.6), Vector3(1.8, 0.25, 6.0), _wood, Vector3(35, 0, 0))
	for x in [-3.6, 3.6]:
		Ambiente.modelo(self, "bunker", Vector3(x, 0, -42), 90.0, Vector3(3.2, 2.85, 3.8), false)

	# Parapetos de sacos de arena donde se cubren los enemigos (saco por saco)
	_sandbag_wall(Vector3(-4.5, 0, -36), 6.0, 6, 2, 0.0, rng)
	_sandbag_wall(Vector3(5, 0, -36), 6.0, 6, 2, 0.0, rng)
	_sandbag_wall(Vector3(-14, 0, -24), 3.0, 6, 2, 8.0, rng)
	_sandbag_wall(Vector3(13, 0, -20), 3.0, 6, 2, -10.0, rng)
	_sandbag_wall(Vector3(2, 3.42, -40.7), 3.0, 3, 1, 0.0, rng)   # parapeto en el techo
	# (los parapetos nuevos van al final, con su propio azar, para no mover
	# los postes y cajas de siempre)

	# Postes de madera clavados en la arena (obstáculos de playa)
	for i in 10:
		var p := Vector3(rng.randf_range(-area.x / 2, area.x / 2), 0, rng.randf_range(-9, 0))
		var tilt := Vector3(rng.randf_range(-25, -10), 0, rng.randf_range(-12, 12))
		_add_box(p + Vector3(0, 1.0, 0), Vector3(0.22, 2.6, 0.22), _wood, tilt)

	_add_bluffs()
	# Tierra adentro: alambre, ladera, casamata, setos y Vierville (fases 2–4)
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = seed_value + 400
	OmahaInterior.construir(self, rng4)

	# Ambiente del desembarco: vegetación, alambre, cráteres, horizonte, cielo
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = seed_value + 6
	Ambiente.crear(self, rng3)
	# Telones a los costados: la batalla sigue más allá de la zona de juego
	add_child(Telones.new())
	if not Game.prueba_carga:
		add_child(Fragor.new())
	# Tanques Sherman quemados en la arena (sirven de cobertura)
	Ambiente.modelo(self, "sherman", Vector3(-22, 0, -7), 25.0, Vector3.ONE * 3.0, true, true)
	Ambiente.modelo(self, "sherman", Vector3(21, 0, -15), -40.0, Vector3.ONE * 3.0, true, true)
	# Lanchas Higgins en la orilla, con la rampa hacia la playa
	for l in [[-30.0, 13.0, 95.0], [-12.0, 16.5, 85.0], [9.0, 12.5, 100.0], [27.0, 15.0, 80.0], [44.0, 19.0, 90.0]]:
		Ambiente.modelo(self, "higgins", Vector3(l[0], -0.7, l[1]), l[2], Vector3.ONE * 5.8, true)

	# Cajas de suministros con armas aliadas (para probarlas) y una Luger junto al búnker
	var cajas := {"thompson": Vector3(4, 0, 2), "bar": Vector3(-5, 0, -1), "carbine": Vector3(-12, 0, -8),
		"springfield": Vector3(10, 0, -12), "bazooka": Vector3(-8, 0, -18)}
	for arma_id in cajas:
		_add_crate(cajas[arma_id], arma_id, rng)
	ArmaSuelta.soltar(self, Vector3(8.4, 0.05, -39.0), "luger", -1, -1)

	# Más parapetos alemanes: flancos (para contraatacar) y a los lados del
	# búnker (para replegarse)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = seed_value + 44
	_sandbag_wall(Vector3(-24, 0, -31), 4.0, 6, 2, 15.0, rng2)
	_sandbag_wall(Vector3(23, 0, -29), 4.0, 6, 2, -15.0, rng2)
	_sandbag_wall(Vector3(-11.5, 0, -41), 4.0, 6, 2, 0.0, rng2)
	_sandbag_wall(Vector3(11.5, 0, -41), 4.0, 6, 2, 0.0, rng2)
	_sandbag_wall(Vector3(0, 0, -29), 3.0, 6, 2, 0.0, rng2)
	# Trincheras al pie del acantilado y a media playa para más alemanes
	for x in [-36.0, -26.0, -18.0, 18.0, 26.0, 36.0, -6.0, 6.0]:
		_sandbag_wall(Vector3(x, 0, -48.0 + absf(x) * 0.05), 5.0, 6, 2, 0.0, rng2)
	for x in [-34.0, -14.0, 14.0, 34.0]:
		_sandbag_wall(Vector3(x, 0, -36.0), 4.0, 6, 2, 0.0, rng2)
	_costados(rng2)
	_build_bags()
	_dibujar_erizos()

	# Cooperativo: la IA (alemanes, escuadras, defensa) solo existe en el
	# anfitrión; los invitados ven títeres que él manda. Cada jugador manda la
	# escuadra de su puesto y empieza en su sector de la playa.
	Escuadras.mi_escuadra = Red.actual.puesto if Game.modo_red and Red.actual else 0
	var con_ia := not Game.modo_red or _soy_anfitrion()
	if not con_ia:
		var enemigos := get_parent().get_node_or_null("Enemies")
		if enemigos:
			enemigos.queue_free()
	else:
		# Las cuatro escuadras americanas (la del jugador y tres con sargento IA)
		get_parent().add_child.call_deferred(Escuadras.new())
		# La defensa alemana: nidos de MG42, morteros y refuerzos
		if not Game.prueba_carga:
			get_parent().add_child.call_deferred(Defensa.new())
	if not Game.prueba_carga:
		get_parent().add_child.call_deferred(Objetivos.new())
	var p := get_parent().get_node_or_null("Player") as Player
	if p:
		if Game.modo_red and Escuadras.mi_escuadra != 0:
			var s: Vector2 = Misiones.dato("sectores")[Escuadras.mi_escuadra]
			p.position.x = (s.x + s.y) / 2.0 + randf_range(-3.0, 3.0)
		elif Game.modo_red:
			p.position.x += randf_range(-3.0, 3.0)
		p.set_meta("inicio", p.position)
		if Game.modo_red and Red.actual:
			p.nombre = Red.actual.mi_nombre

	# Mapa de caminos para la IA, con todo lo de arriba ya puesto
	_hornear_navegacion.call_deferred()
	if Game.prueba_carga:
		var pc := PruebaCarga.new()
		get_parent().add_child.call_deferred(pc)


func _soy_anfitrion() -> bool:
	return Red.actual != null and Red.actual.anfitrion


func _exit_tree() -> void:
	Navegacion.olvidar()
	Coberturas.limpiar()


func _hornear_navegacion() -> void:
	Navegacion.hornear(get_parent(), AABB(Vector3(-LIMITE_X, -2, -208), Vector3(LIMITE_X * 2.0, 34, 221)))
	if not Game.prueba_carga and (not Game.modo_red or _soy_anfitrion()):
		# Defensa alemana: los 7 de la escena + 13 en las trincheras (20 en total)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + 99
		var usados: Array = []
		for i in ALEMANES_EXTRA:
			PruebaCarga.nuevo_aleman(get_parent(), rng, usados)


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
## Caja de madera de suministros con un arma encima.
func _add_crate(pos: Vector3, arma_id: String, rng: RandomNumberGenerator) -> void:
	var giro := rng.randf_range(-30.0, 30.0)
	_add_box(pos + Vector3(0, 0.27, 0), Vector3(1.1, 0.54, 0.55), _wood, Vector3(0, giro, 0))
	Game.box(self, Vector3(1.12, 0.05, 0.57), pos + Vector3(0, 0.12, 0), _dark, Vector3(0, giro, 0))   # zunchos
	Game.box(self, Vector3(1.12, 0.05, 0.57), pos + Vector3(0, 0.42, 0), _dark, Vector3(0, giro, 0))
	var a := ArmaSuelta.soltar(self, pos + Vector3(0, 0.55, 0), arma_id, -1, -1)
	a.rotation.y = deg_to_rad(giro)


func _add_bluffs() -> void:
	var slope := 30.0
	var h := 14.0
	var depth := h / tan(deg_to_rad(slope))
	_add_box(Vector3(0, h / 2.0 - 0.6, -56 - depth / 2.0), Vector3(500, 1.0, h / sin(deg_to_rad(slope))),
		_grass, Vector3(slope, 0, 0))
	# La meseta de arriba llega hasta el bosque detrás de Vierville (sección 6)
	_add_box(Vector3(0, h - 0.5, -56 - depth - 75), Vector3(500, 1.0, 150), _grass)

## Erizo checo: tres vigas de acero en ángulo (perfil L) cruzadas en el centro,
## perpendiculares entre sí, unidas con cartelas. Se apoya sobre tres puntas y
## las otras tres apuntan hacia arriba (por eso la diagonal (1,1,1) va vertical).
func _add_hedgehog(pos: Vector3, yaw: float, choque := true) -> void:
	var largo := 2.3
	var ala := 0.13       # ancho de cada ala del perfil L
	var parado := Basis(Quaternion(Vector3.ONE.normalized(), Vector3.UP))
	var t := Transform3D(Basis(Vector3.UP, yaw) * parado,
		pos + Vector3(0, largo / (2.0 * sqrt(3.0)) - 0.06, 0))   # un poco hundido en la arena
	_erizos.append(t)
	if not choque:
		return
	var root := StaticBody3D.new()
	root.transform = t
	add_child(root)
	var ejes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var beam_shape := BoxShape3D.new()
	beam_shape.size = Vector3(ala, ala, largo)
	for k in 3:
		var col := CollisionShape3D.new()
		col.shape = beam_shape
		col.basis = Basis(ejes[(k + 1) % 3], ejes[(k + 2) % 3], ejes[k])
		root.add_child(col)


## La malla de un erizo (tres vigas en L y las cartelas), hecha una vez.
func _malla_erizo() -> Mesh:
	var largo := 2.3
	var ala := 0.13
	var espesor := 0.022
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ejes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var caja := func(tam: Vector3, tr: Transform3D) -> void:
		var bm := BoxMesh.new()
		bm.size = tam
		st.append_from(bm, 0, tr)
	for k in 3:
		var eje: Vector3 = ejes[k]
		var u: Vector3 = ejes[(k + 1) % 3]
		var v: Vector3 = ejes[(k + 2) % 3]
		var b := Basis(u, v, eje)   # la viga corre a lo largo de "eje" (z local)
		caja.call(Vector3(ala, espesor, largo), Transform3D(b, u * (ala / 2.0 - 0.03) - v * 0.03))
		caja.call(Vector3(espesor, ala, largo), Transform3D(b, v * (ala / 2.0 - 0.03) - u * 0.03))
	for k in 3:
		var e: Vector3 = ejes[k]
		caja.call(Vector3(0.34, 0.34, 0.015), Transform3D(Basis(ejes[(k + 1) % 3], ejes[(k + 2) % 3], e).rotated(e, PI / 4.0), Vector3.ZERO))
	var m := st.commit()
	m.surface_set_material(0, _steel)
	return m


## Dibuja todos los erizos (jugables y de decorado) en una sola llamada.
func _dibujar_erizos() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _malla_erizo()
	mm.instance_count = _erizos.size()
	for i in _erizos.size():
		mm.set_instance_transform(i, _erizos[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _plate(parent: Node3D, b: Basis, size: Vector3, offset: Vector3) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = _steel
	m.transform = Transform3D(b, offset)
	parent.add_child(m)


## Muro de sacos de arena: hileras trabadas (cada hilera corrida medio saco),
## "filas" sacos de fondo, con pequeñas diferencias de giro y tamaño para que
## no se vea perfecto. La colisión es una sola caja del tamaño del muro.
func _sandbag_wall(center: Vector3, length: float, courses: int, rows: int, yaw_deg: float,
		rng: RandomNumberGenerator, solido := true) -> void:
	var bag_len := 0.62
	var bag_h := 0.15
	var bag_d := 0.36
	var yaw := deg_to_rad(yaw_deg)
	var wall := Basis(Vector3.UP, yaw)
	for c in courses:
		var corrido := 0.5 * bag_len if c % 2 == 1 else 0.0
		var n := int(length / bag_len)
		var ancho_hilera := (n - (1 if c % 2 == 1 else 0)) * bag_len
		for r in rows:
			for i in n - (1 if c % 2 == 1 else 0):
				var x := -ancho_hilera / 2.0 + (i + 0.5) * bag_len
				var z := (r - (rows - 1) / 2.0) * bag_d
				var local := Vector3(x + rng.randf_range(-0.03, 0.03), (c + 0.5) * bag_h * 0.92,
					z + rng.randf_range(-0.03, 0.03))
				var s := Vector3(rng.randf_range(0.92, 1.05), rng.randf_range(0.9, 1.15), rng.randf_range(0.95, 1.05))
				var giro := Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)) \
					* Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05))
				# cápsula acostada: su eje (y) pasa a ser el largo del saco (x)
				var forma := Basis(Vector3.BACK, PI / 2.0) * Basis.from_scale(
					Vector3(bag_h * s.y, bag_len * 0.5 * s.x, bag_d * s.z))
				_bags.append(Transform3D(wall * giro * forma, center + wall * local))
	if not solido:
		return      # decorado lejano: solo los sacos, sin choque ni cobertura
	var body := StaticBody3D.new()
	body.transform = Transform3D(wall, center + Vector3(0, courses * bag_h * 0.92 / 2.0, 0))
	add_child(body)
	Coberturas.agregar_muro(center, length, yaw_deg, rows * bag_d, courses * bag_h * 0.92)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, courses * bag_h * 0.92, rows * bag_d)
	col.shape = shape
	body.add_child(col)


func _build_bags() -> void:
	var mesh := CapsuleMesh.new()   # radio 0,5 y alto 2: se escala por saco
	mesh.radius = 0.5
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _bags.size()
	for i in _bags.size():
		mm.set_instance_transform(i, _bags[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = _burlap
	add_child(inst)


func _add_box(pos: Vector3, box_size: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> StaticBody3D:
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
	return body



# ================================================================ costados

## La playa jugable va de −40 a +40. Los carriles de los costados (donde
## avanzan las escuadras de Kowalski y Reyes) se llenan de obstáculos para
## cubrirse; más allá de las paredes invisibles sigue el decorado (erizos,
## postes, sacos, restos) hasta el telón, para que no se vea el fin del mundo.
func _costados(rng: RandomNumberGenerator) -> void:
	# Paredes invisibles (capa 7: paran a la gente, no a las balas ni la vista)
	for lado in [-1.0, 1.0]:
		var muro := StaticBody3D.new()
		muro.collision_layer = 64
		muro.collision_mask = 0
		muro.position = Vector3(lado * (LIMITE_X + 0.5), 10.0, -95.0)
		var col := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = Vector3(1.0, 40.0, 250.0)
		col.shape = forma
		muro.add_child(col)
		add_child(muro)
	# Carriles de los costados (x 24…38): erizos, postes y parapetos
	for lado in [-1.0, 1.0]:
		for i in 9:
			var pos := Vector3(lado * rng.randf_range(24.0, 38.0), 0, rng.randf_range(-30.0, -3.0))
			_add_hedgehog(pos, rng.randf() * TAU)
			Coberturas.agregar_erizo(pos)
		for i in 5:
			var p := Vector3(lado * rng.randf_range(22.0, 38.0), 0, rng.randf_range(-9.0, 2.0))
			var tilt := Vector3(rng.randf_range(-25, -10), 0, rng.randf_range(-12, 12))
			_add_box(p + Vector3(0, 1.0, 0), Vector3(0.22, 2.6, 0.22), _wood, tilt)
		_sandbag_wall(Vector3(lado * 31.0, 0, -14.0), 3.0, 5, 2, lado * 12.0, rng)
		_sandbag_wall(Vector3(lado * 36.0, 0, -24.0), 3.0, 5, 2, -lado * 8.0, rng)
		_sandbag_wall(Vector3(lado * 27.0, 0, -6.0), 2.5, 4, 2, lado * 5.0, rng)
	# Decorado más allá de las paredes (sin choque: no se llega)
	for lado in [-1.0, 1.0]:
		for i in 22:
			var pos := Vector3(lado * rng.randf_range(LIMITE_X + 2.0, 95.0), 0, rng.randf_range(-48.0, 4.0))
			_add_hedgehog(pos, rng.randf() * TAU, false)
		for i in 10:
			var p := Vector3(lado * rng.randf_range(LIMITE_X + 2.0, 90.0), 0, rng.randf_range(-12.0, 3.0))
			var tilt := Vector3(rng.randf_range(-25, -10), 0, rng.randf_range(-12, 12))
			Game.box(self, Vector3(0.22, 2.6, 0.22), p + Vector3(0, 1.0, 0), _wood, tilt)
		for k in 4:
			var c := Vector3(lado * rng.randf_range(48.0, 85.0), 0, rng.randf_range(-48.0, -30.0))
			_sandbag_wall(c, rng.randf_range(4.0, 7.0), 5, 2, rng.randf_range(-15.0, 15.0), rng, false)
		# Restos grandes: un Sherman quemado y una lancha varada por lado
		Ambiente.modelo(self, "sherman", Vector3(lado * rng.randf_range(52.0, 70.0), 0, rng.randf_range(-24.0, -8.0)),
			rng.randf_range(0.0, 360.0), Vector3.ONE * 3.0, false)
		Ambiente.modelo(self, "higgins", Vector3(lado * rng.randf_range(55.0, 80.0), -0.7, rng.randf_range(12.0, 17.0)),
			rng.randf_range(70.0, 110.0), Vector3.ONE * 5.8, false)
