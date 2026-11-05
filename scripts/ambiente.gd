extends RefCounted
class_name Ambiente
## Ambiente del desembarco (sección 5): lo que le da identidad a la playa.
## - Arriba del acantilado: setos de Normandía (bocage), robles, álamos y manzanos.
## - Pasto alto en el acantilado y al pie de las dunas.
## - Alambre de púas delante de las trincheras alemanas y cráteres en la arena.
## - Lanchas Higgins en la orilla y dos tanques Sherman quemados (cobertura).
## - Barcos de guerra en el horizonte y cielo nublado.
## Imágenes: ChatGPT → tools/arte/ambiente.py → assets/ambiente/.
## Modelos: Meshy → tools/modelos/decorado.gd → assets/decorado/ (color por vértice).
## Todo se crea al cargar la playa y con pocas llamadas de dibujo: cada tipo
## de planta, el alambre y los cráteres son UNA sola malla múltiple (MultiMesh).

const DIR := "res://assets/ambiente/"
const PPM := {"arbol_1": 16.0, "arbol_2": 16.0, "arbol_3": 20.0, "seto": 20.0, "pasto": 40.0, "alambre": 64.0}


## Altura del terreno del acantilado (ver beach_decor._add_bluffs).
static func alto_acantilado(z: float) -> float:
	if z > -56.0:
		return 0.0
	return minf(6.83 + (-68.12 - z) * 0.5774, 14.0)


static func crear(padre: Node3D, rng: RandomNumberGenerator) -> void:
	_vegetacion(padre, rng)
	_alambre(padre, rng)
	_crateres(padre, rng)
	_barcos(padre)
	_cielo(padre)


# ================================================================ plantas

## Malla múltiple de una imagen que siempre mira a la cámara (girando en Y).
## Los setos y el pasto alto tapan la vista: cada uno lleva una caja invisible
## en la capa 8 (128), que solo la usan los rayos de "¿lo veo?" de la IA
## (las balas y los soldados la atraviesan; el mapa de caminos no la ve).
const TAPAN := ["seto", "pasto", "arbol_1", "arbol_2", "arbol_3"]


static func _plantas(padre: Node3D, nombre: String, lugares: Array) -> void:
	if lugares.is_empty():
		return
	var tex: Texture2D = load(DIR + nombre + ".png")
	var ppm: float = PPM[nombre]
	var quad := QuadMesh.new()
	quad.size = Vector2(tex.get_width() / ppm, tex.get_height() / ppm)
	quad.center_offset = Vector3(0, quad.size.y / 2.0 - 0.15, 0)   # base apenas enterrada
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.82, 0.84, 0.82)   # un poco apagado por la luz nublada
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = lugares.size()
	for i in lugares.size():
		var l: Array = lugares[i]     # [posición, escala]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * l[1]), l[0]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(mi)
	if nombre in TAPAN:
		var cuerpo := StaticBody3D.new()
		cuerpo.collision_layer = 128
		cuerpo.collision_mask = 0
		padre.add_child(cuerpo)
		for l in lugares:
			var e: float = l[1]
			var col := CollisionShape3D.new()
			var forma := BoxShape3D.new()
			# un poco más chica que el dibujo (los bordes de la imagen son ralos);
			# de los árboles solo tapa el tronco y las ramas bajas
			if nombre.begins_with("arbol"):
				forma.size = Vector3(0.9 * e, 4.0 * e, 0.9 * e)
			elif nombre == "seto":   # el seto tapa casi todo su ancho (si no, se ve entre las ramas)
				forma.size = Vector3(quad.size.x * e * 0.95, (quad.size.y - 0.15) * e * 0.95, 0.7)
			else:
				forma.size = Vector3(quad.size.x * e * 0.75, (quad.size.y - 0.15) * e * 0.95, 0.7)
			col.shape = forma
			col.position = l[0] + Vector3(0, forma.size.y / 2.0, 0)
			cuerpo.add_child(col)


static func _vegetacion(padre: Node3D, rng: RandomNumberGenerator) -> void:
	var setos := []
	var arboles := {"arbol_1": [], "arbol_2": [], "arbol_3": []}
	var pasto := []
	# Arriba del acantilado: hileras de setos (campos de Normandía) con árboles
	for fila_z in [-84.0, -97.0, -112.0, -128.0]:
		var x := -95.0
		while x < 95.0:
			# (en el centro, las filas de setos con talud las pone OmahaInterior)
			if rng.randf() < 0.85 and (fila_z > -90.0 or absf(x) > 56.0):
				var z: float = fila_z + rng.randf_range(-1.5, 1.5)
				setos.append([Vector3(x, alto_acantilado(z), z), rng.randf_range(0.9, 1.2)])
			if rng.randf() < 0.35:
				var tipo: String = ["arbol_1", "arbol_1", "arbol_2", "arbol_3"][rng.randi() % 4]
				var zt: float = fila_z + rng.randf_range(-2.0, 2.0)
				arboles[tipo].append([Vector3(x + rng.randf_range(-2, 2), alto_acantilado(zt), zt),
					rng.randf_range(0.8, 1.15)])
			x += rng.randf_range(4.5, 6.5)
	# Algunos árboles sueltos al borde del acantilado (se ven desde la playa)
	for i in 10:
		var z := rng.randf_range(-82.0, -80.5)
		arboles["arbol_1" if rng.randf() < 0.6 else "arbol_3"].append(
			[Vector3(rng.randf_range(-70, 70), alto_acantilado(z), z), rng.randf_range(0.8, 1.1)])
	# Pasto alto: en la ladera del acantilado, arriba, y al pie de las dunas
	for i in 140:
		var z := rng.randf_range(-82.0, -54.0)
		pasto.append([Vector3(rng.randf_range(-90, 90), alto_acantilado(z) - 0.05, z), rng.randf_range(0.8, 1.6)])
	for i in 40:
		var z := rng.randf_range(-54.0, -47.0)
		pasto.append([Vector3(rng.randf_range(-60, 60), 0.0, z), rng.randf_range(0.6, 1.2)])
	_plantas(padre, "seto", setos)
	for t in arboles:
		_plantas(padre, t, arboles[t])
	_plantas(padre, "pasto", pasto)


# ================================================================ alambre y cráteres

static func _alambre(padre: Node3D, rng: RandomNumberGenerator) -> void:
	var tex: Texture2D = load(DIR + "alambre.png")
	var quad := QuadMesh.new()
	quad.size = Vector2(tex.get_width() / 64.0, tex.get_height() / 64.0)
	quad.center_offset = Vector3(0, quad.size.y / 2.0 - 0.1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.8, 0.8, 0.8)
	quad.material = mat
	# Tramos en líneas cortadas delante de las posiciones alemanas
	var lugares := []
	for fila in [[-19.0, -30.0, 30.0], [-31.0, -40.0, 40.0], [-44.5, -45.0, 45.0]]:
		var x: float = fila[1]
		while x < fila[2]:
			if rng.randf() < 0.75:
				var giro := rng.randf_range(-0.25, 0.25)
				lugares.append(Transform3D(Basis(Vector3.UP, giro), Vector3(x, 0, fila[0] + rng.randf_range(-1.2, 1.2))))
			x += quad.size.x * rng.randf_range(1.0, 1.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = lugares.size()
	for i in lugares.size():
		mm.set_instance_transform(i, lugares[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(mi)


static func _crateres(padre: Node3D, rng: RandomNumberGenerator) -> void:
	var plano := PlaneMesh.new()
	plano.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(DIR + "crater.png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	plano.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plano
	mm.instance_count = 14
	for i in 14:
		var tam := rng.randf_range(2.5, 5.0)
		var pos := Vector3(rng.randf_range(-38, 38), 0.025 + i * 0.001, rng.randf_range(-40, 6))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(tam, 1, tam)), pos))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(mi)


# ================================================================ horizonte

static func _barcos(padre: Node3D) -> void:
	var tex: Texture2D = load(DIR + "barcos.png")
	var ancho := 560.0
	var alto := ancho * tex.get_height() / tex.get_width()
	var quad := QuadMesh.new()
	quad.size = Vector2(ancho, alto)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true           # está muy lejos: la niebla se la "pinta" el color
	mat.albedo_color = Color(0.92, 0.94, 0.95, 0.75)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(mi)
	# Línea de flotación (62 % hacia abajo de la imagen) a la altura del mar
	mi.position = Vector3(0, alto * (0.62 - 0.5), 285.0)
	mi.rotation.y = PI


static func _cielo(padre: Node3D) -> void:
	var we := padre.get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		we = padre.get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load(DIR + "cielo.png")
	pano.filter = false
	var sky := Sky.new()
	sky.sky_material = pano
	env.sky = sky
	env.fog_sky_affect = 0.55    # que se vean las nubes a través de la niebla


# ================================================================ modelos 3D

static func material_modelo() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## Un solo material para todos los modelos (antes, uno nuevo por modelo: el
## motor tenía que cambiar de material entre cada uno al dibujar).
static var _compartido: StandardMaterial3D


static func _mat_modelo() -> StandardMaterial3D:
	if _compartido == null:
		_compartido = material_modelo()
	return _compartido


## Modelo de decorado con su caja de choque (y, si se pide, puntos de cobertura).
## Capas de choque de los modelos de Meshy (ver `modelo`).
const CAPA_VOLUMEN := 256   # capa 9: caja que para a la gente (y entra al mapa de caminos)
const CAPA_FORMA := 512     # capa 10: forma exacta que paran las balas, la vista y las granadas
static var _formas := {}


## Forma de choque con los triángulos del modelo ya escalados (una por
## modelo y escala, compartida entre copias).
static func _forma_exacta(nombre: String, mesh: Mesh, escala: Vector3) -> ConcavePolygonShape3D:
	var clave := "%s_%s" % [nombre, escala]
	if _formas.has(clave):
		return _formas[clave]
	var caras := mesh.get_faces()
	for i in caras.size():
		caras[i] *= escala
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(caras)
	_formas[clave] = forma
	return forma


static func modelo(padre: Node3D, nombre: String, pos: Vector3, giro_deg: float, escala: Vector3,
		choque: bool, cobertura := false) -> MeshInstance3D:
	var mesh: Mesh = load("res://assets/decorado/%s.res" % nombre)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat_modelo()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation_degrees.y = giro_deg
	mi.scale = escala
	# Lejos no se dibuja: un modelo chico a más de ~30 veces su largo mide
	# pocos píxeles y la niebla lo tapa (la iglesia se ve siempre).
	var largo := (mesh.get_aabb().size * escala).length()
	mi.visibility_range_end = clampf(largo * 22.0, 70.0, 260.0) if largo < 15.0 else 0.0
	padre.add_child(mi)
	if choque:
		# Dos choques: la caja (capa 9, 256) para caminar y el mapa de caminos
		# (la gente no se enreda en los rayos de una rueda), y la forma exacta
		# del modelo (capa 10, 512) para balas, vista y granadas: por los huecos
		# de una carreta o unos escombros pasan las balas, como se ve.
		var caja := mesh.get_aabb()
		var tam := caja.size * escala * Vector3(0.9, 0.85, 0.85)
		var body := StaticBody3D.new()
		body.collision_layer = CAPA_VOLUMEN
		body.collision_mask = 0
		body.position = pos + Vector3(0, tam.y / 2.0, 0)
		body.rotation_degrees.y = giro_deg
		padre.add_child(body)
		var col := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = tam
		col.shape = forma
		body.add_child(col)
		var exacto := StaticBody3D.new()
		exacto.collision_layer = CAPA_FORMA
		exacto.collision_mask = 0
		exacto.position = pos
		exacto.rotation_degrees.y = giro_deg
		padre.add_child(exacto)
		var col2 := CollisionShape3D.new()
		col2.shape = _forma_exacta(nombre, mesh, escala)
		exacto.add_child(col2)
		if cobertura:
			Coberturas.agregar_muro(Vector3(pos.x, pos.y, pos.z), tam.x, giro_deg, tam.z, tam.y)
	return mi
