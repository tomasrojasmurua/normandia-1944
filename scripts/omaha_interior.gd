extends RefCounted
class_name OmahaInterior
## Lo que hay detrás de la playa de Omaha (sección 6: la misión por fases).
## Lo arma beach_decor.gd al cargar el mapa (en todos los celulares):
##   Fase 2, LA LADERA: alambre de púas al pie del acantilado (sin paso hasta
##     volar la brecha con el bangalore), parapetos alemanes en la ladera y la
##     trinchera del borde de arriba.
##   Fase 3, LA MESETA: la casamata del cañón al borde del acantilado y los
##     campos de setos (bocage): taludes de tierra con huecos para pasar.
##   Fase 4, VIERVILLE: casas en ruinas alrededor del cruce, la iglesia y el
##     bosque del fondo, de donde sale el contraataque.
## Todo es caja + textura (como la playa) y las plantas son mallas múltiples,
## para que ande en el celular. Las coberturas se registran en Coberturas.
## Cambios durante la misión (Objetivos los aplica en todos los celulares):
##   abrir_brecha()       el bangalore abre el alambre (se puede pasar)
##   destruir_casamata()  la casamata queda en ruinas

const Z_ALAMBRE := -52.6
const BRECHA := Vector2(8.0, 16.0)      # X donde está el tramo que vuela el bangalore
const ARRIBA := 14.0                    # altura de la meseta
const DECOR := preload("res://scripts/beach_decor.gd")

static var _brecha_cuerpo: StaticBody3D
static var _brecha_alambre: MultiMeshInstance3D
static var _casamata: MeshInstance3D
static var _canon: MeshInstance3D
static var _casamata_rota := false


static func construir(d: Node3D, rng: RandomNumberGenerator) -> void:
	_casamata_rota = false
	_alambre(d, rng)
	_ladera(d, rng)
	_casamata_y_borde(d, rng)
	_setos(d, rng)
	_pueblo(d, rng)
	_bosque(d, rng)
	# Que nadie se caiga por el fondo de la meseta
	var muro := StaticBody3D.new()
	muro.position = Vector3(0, ARRIBA + 2.0, -214.0)
	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(500, 4, 1)
	col.shape = forma
	muro.add_child(col)
	d.add_child(muro)


# ================================================================ fase 2

## Alambre de púas al pie del acantilado: cerrado salvo el tramo de la brecha,
## que choca con todos pero no está en el mapa de caminos (capa 7) hasta volarlo.
static func _alambre(d: Node3D, rng: RandomNumberGenerator) -> void:
	for tramo in [Vector2(-250.0, BRECHA.x), Vector2(BRECHA.y, 250.0)]:
		var b: StaticBody3D = d._add_box(Vector3((tramo.x + tramo.y) / 2.0, 0.45, Z_ALAMBRE),
			Vector3(tramo.y - tramo.x, 0.9, 1.2), d._dark)
		b.get_child(0).visible = false
	_brecha_cuerpo = StaticBody3D.new()
	_brecha_cuerpo.collision_layer = 64
	_brecha_cuerpo.collision_mask = 0
	_brecha_cuerpo.position = Vector3((BRECHA.x + BRECHA.y) / 2.0, 0.45, Z_ALAMBRE)
	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(BRECHA.y - BRECHA.x, 0.9, 1.2)
	col.shape = forma
	_brecha_cuerpo.add_child(col)
	d.add_child(_brecha_cuerpo)
	# Las rollos de alambre (dos filas, la de la brecha aparte para poder sacarla)
	var lugares := []
	var en_brecha := []
	for fila in [Z_ALAMBRE - 0.35, Z_ALAMBRE + 0.35]:
		var x := -75.0
		while x < 75.0:
			var t := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)),
				Vector3(x, 0, fila + rng.randf_range(-0.2, 0.2)))
			if x > BRECHA.x - 2.0 and x < BRECHA.y + 2.0:
				en_brecha.append(t)
			else:
				lugares.append(t)
			x += rng.randf_range(2.6, 3.6)
	_multi_alambre(d, lugares)
	_brecha_alambre = _multi_alambre(d, en_brecha)
	# Un cartel de madera junto a la brecha (para encontrarla desde lejos)
	Game.box(d, Vector3(0.12, 2.2, 0.12), Vector3(BRECHA.x - 1.0, 1.1, Z_ALAMBRE + 1.2), d._wood)
	Game.box(d, Vector3(1.1, 0.5, 0.06), Vector3(BRECHA.x - 1.0, 1.9, Z_ALAMBRE + 1.25), d._wood)


static func _multi_alambre(d: Node3D, lugares: Array) -> MultiMeshInstance3D:
	var tex: Texture2D = load(Ambiente.DIR + "alambre.png")
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
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = lugares.size()
	for i in lugares.size():
		mm.set_instance_transform(i, lugares[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.add_child(mi)
	return mi


static func abrir_brecha() -> void:
	if _brecha_cuerpo and is_instance_valid(_brecha_cuerpo):
		_brecha_cuerpo.queue_free()
	if _brecha_alambre and is_instance_valid(_brecha_alambre):
		_brecha_alambre.queue_free()
	_brecha_cuerpo = null
	_brecha_alambre = null


## Parapetos de sacos en la ladera (las coberturas quedan a la altura del
## terreno, ver Coberturas._agregar) y la trinchera del borde de arriba.
static func _ladera(d: Node3D, rng: RandomNumberGenerator) -> void:
	# [x, z, largo, giro]
	var parapetos := [
		# La trinchera de la ladera (objetivo), en zigzag
		[-3.0, -64.0, 6.0, 0.0], [6.0, -64.6, 5.0, 10.0], [-7.5, -66.0, 3.0, 60.0],
		# El nido de la MG42 de la ladera (objetivo)
		[23.0, -70.2, 4.0, -8.0], [19.8, -69.6, 2.6, 35.0],
		# Sueltos: sirven a los dos bandos para subir
		[-12.0, -61.0, 3.0, 0.0], [15.0, -59.5, 3.0, -10.0], [30.0, -64.0, 3.0, 5.0],
		[-14.0, -71.5, 4.0, 0.0], [8.0, -73.5, 4.0, 0.0], [33.0, -75.0, 3.0, -5.0],
		[-2.0, -77.0, 3.0, 0.0], [20.0, -78.0, 3.0, 0.0],
	]
	for p in parapetos:
		var z: float = p[1]
		d._sandbag_wall(Vector3(p[0], Ambiente.alto_acantilado(z) - 0.15, z), p[2], 6, 2, p[3], rng)
	# La trinchera alemana del borde (los que disparan hacia abajo)
	for p in [[-14.0, -82.4], [2.0, -82.9], [18.0, -82.5], [34.0, -82.7], [-30.0, -82.4]]:
		d._sandbag_wall(Vector3(p[0], ARRIBA, p[1]), 5.0, 6, 2, rng.randf_range(-6.0, 6.0), rng)


# ================================================================ fase 3

static func _casamata_y_borde(d: Node3D, _rng: RandomNumberGenerator) -> void:
	_casamata = Ambiente.modelo(d, "bunker", Vector3(-26, ARRIBA, -84), 90.0, Vector3(3.2, 2.85, 3.8), true, true)
	_canon = Game.box(d, Vector3(0.28, 0.28, 3.4), Vector3(-26, ARRIBA + 1.5, -80.6), d._steel)


static func destruir_casamata() -> void:
	if _casamata_rota:
		return
	_casamata_rota = true
	if _casamata and is_instance_valid(_casamata):
		_casamata.scale.y *= 0.55
		_casamata.rotation_degrees.z = 4.0
		var m := Ambiente.material_modelo()
		m.albedo_color = Color(0.32, 0.3, 0.28)    # tiznada por la explosión
		_casamata.material_override = m
	if _canon and is_instance_valid(_canon):
		_canon.rotation_degrees.x = -18.0
		_canon.position.y -= 0.9


## Campos de setos (bocage): taludes de tierra de 1,1 m con el seto encima y
## huecos para pasar de un campo a otro. Se ve por encima del talud de rodillas.
static func _setos(d: Node3D, rng: RandomNumberGenerator) -> void:
	var tierra: StandardMaterial3D = DECOR.textured("pasto_duna", 2.0, Color(0.5, 0.55, 0.4))
	var setos := []
	# [z, huecos (centro X de cada paso de 4 m)]
	var filas := [[-97.0, [-30.0, 0.0, 28.0]], [-112.0, [-18.0, 12.0, 38.0]], [-128.0, [-36.0, -4.0, 24.0]]]
	for fila in filas:
		var z: float = fila[0]
		var cortes: Array = [-54.0]
		for h in fila[1]:
			cortes.append(h - 2.0)
			cortes.append(h + 2.0)
		cortes.append(54.0)
		for k in range(0, cortes.size(), 2):
			var a: float = cortes[k]
			var b: float = cortes[k + 1]
			var largo := b - a
			var centro := Vector3((a + b) / 2.0, ARRIBA + 0.55, z)
			d._add_box(centro, Vector3(largo, 1.1, 1.8), tierra)
			Coberturas.agregar_muro(Vector3(centro.x, ARRIBA, z), largo, 0.0, 1.8, 1.1)
			# El seto tapa la vista; donde falta (1 de cada 3) se puede tirar por encima del talud
			var x := a + 1.5
			while x < b - 1.0:
				if rng.randf() > 0.33:
					setos.append([Vector3(x, ARRIBA + 1.05, z + rng.randf_range(-0.2, 0.2)), rng.randf_range(0.55, 0.7)])
				x += rng.randf_range(3.2, 4.2)
	# Un par de carros y pilas de heno como cobertura en los campos
	for c in [[6.0, -105.0], [-24.0, -120.0], [30.0, -121.0], [-6.0, -138.0]]:
		d._add_box(Vector3(c[0], ARRIBA + 0.55, c[1]), Vector3(2.6, 1.1, 1.4), d._wood, Vector3(0, rng.randf_range(-30, 30), 0))
		Coberturas.agregar_muro(Vector3(c[0], ARRIBA, c[1]), 2.6, 0.0, 1.4, 1.1)
	Ambiente._plantas(d, "seto", setos)


# ================================================================ fase 4

## Vierville: casas de piedra en ruinas alrededor del cruce (0, -152), la
## iglesia con su torre (se ve desde lejos) y los caminos.
static func _pueblo(d: Node3D, rng: RandomNumberGenerator) -> void:
	var piedra: StandardMaterial3D = DECOR.textured("piedra", 2.6)
	var camino: StandardMaterial3D = DECOR.textured("guijarros", 2.5, Color(0.72, 0.64, 0.52))
	# Caminos (solo se ven: no chocan)
	Game.box(d, Vector3(4.0, 0.04, 120.0), Vector3(0, ARRIBA + 0.02, -145.0), camino)
	Game.box(d, Vector3(100.0, 0.04, 4.0), Vector3(0, ARRIBA + 0.03, -152.0), camino)
	# [centro X, centro Z, ancho, fondo]
	var casas := [[-13.0, -143.0, 9.0, 7.0], [13.5, -142.0, 8.0, 7.0], [-14.0, -162.0, 8.0, 8.0],
		[15.0, -163.0, 10.0, 7.0], [-32.0, -149.0, 8.0, 7.0], [33.0, -153.0, 8.0, 8.0],
		[7.0, -178.0, 8.0, 6.0], [36.0, -170.0, 7.0, 6.0], [-36.0, -136.0, 7.0, 6.0]]
	for c in casas:
		_casa(d, Vector3(c[0], ARRIBA, c[1]), c[2], c[3], piedra, rng)
	# La iglesia: nave en ruinas y la torre entera
	_casa(d, Vector3(-26.0, ARRIBA, -175.0), 10.0, 16.0, piedra, rng, 5.5)
	d._add_box(Vector3(-26.0, ARRIBA + 8.0, -165.0), Vector3(4.2, 16.0, 4.2), piedra)
	Coberturas.agregar_muro(Vector3(-26.0, ARRIBA, -165.0), 4.2, 0.0, 4.2, 3.0)
	Game.box(d, Vector3(2.6, 3.0, 2.6), Vector3(-26.0, ARRIBA + 17.5, -165.0), d._dark)
	# Escombros sueltos en las calles
	for e in [[4.0, -147.0], [-5.0, -157.0], [21.0, -151.0], [-21.0, -153.5], [2.0, -167.0]]:
		d._add_box(Vector3(e[0], ARRIBA + 0.4, e[1]), Vector3(2.2, 0.8, 1.2), piedra, Vector3(0, rng.randf_range(-40, 40), 0))
		Coberturas.agregar_muro(Vector3(e[0], ARRIBA, e[1]), 2.2, 0.0, 1.2, 0.8)


## Una casa de piedra sin techo: cuatro paredes con puerta y ventanas, y
## partes derrumbadas (más bajas: sirven de cobertura para disparar).
static func _casa(d: Node3D, centro: Vector3, ancho: float, fondo: float, mat: Material,
		rng: RandomNumberGenerator, alto := 3.4) -> void:
	var g := 0.5
	# [inicio, fin] de cada pared (en coordenadas de la casa), su giro y su lado
	var paredes := [
		[Vector3(-ancho / 2.0, 0, fondo / 2.0), Vector3(ancho / 2.0, 0, fondo / 2.0)],     # frente (+Z)
		[Vector3(-ancho / 2.0, 0, -fondo / 2.0), Vector3(ancho / 2.0, 0, -fondo / 2.0)],   # fondo
		[Vector3(-ancho / 2.0, 0, -fondo / 2.0), Vector3(-ancho / 2.0, 0, fondo / 2.0)],   # izquierda
		[Vector3(ancho / 2.0, 0, -fondo / 2.0), Vector3(ancho / 2.0, 0, fondo / 2.0)],     # derecha
	]
	for k in paredes.size():
		var a: Vector3 = paredes[k][0]
		var b: Vector3 = paredes[k][1]
		var largo := a.distance_to(b)
		var dir := (b - a) / largo
		var yaw := 0.0 if absf(dir.x) > 0.5 else 90.0
		# Tramos: puerta (frente y fondo) o ventana, separados por paredes
		var huecos: Array = []
		if k <= 1:
			huecos.append([largo * rng.randf_range(0.35, 0.65), 1.6])
		else:
			huecos.append([largo * rng.randf_range(0.3, 0.7), 1.4])
		var t := 0.0
		var cortes: Array = []
		for h in huecos:
			cortes.append([t, h[0] - h[1] / 2.0])
			t = h[0] + h[1] / 2.0
		cortes.append([t, largo])
		for c in cortes:
			var l: float = c[1] - c[0]
			if l < 0.4:
				continue
			var h := alto
			var r := rng.randf()
			if r < 0.3:
				h = 1.1          # derrumbada: se asoma por encima
			elif r < 0.5:
				h = alto * 0.65
			var medio: Vector3 = centro + a + dir * ((c[0] + c[1]) / 2.0)
			var tam := Vector3(l + (g if c[0] == 0.0 or c[1] == largo else 0.0), h, g)
			d._add_box(medio + Vector3(0, h / 2.0, 0), tam, mat, Vector3(0, yaw, 0))
			Coberturas.agregar_muro(medio, l, yaw, g, h)
	# Escombros adentro
	d._add_box(centro + Vector3(rng.randf_range(-1.5, 1.5), 0.35, rng.randf_range(-1.5, 1.5)),
		Vector3(1.8, 0.7, 1.2), mat, Vector3(0, rng.randf_range(0, 90), 0))


## El bosque del fondo (de ahí sale el contraataque) y árboles por el pueblo.
static func _bosque(d: Node3D, rng: RandomNumberGenerator) -> void:
	var arboles := {"arbol_1": [], "arbol_2": [], "arbol_3": []}
	for i in 70:
		var z := rng.randf_range(-210.0, -192.0)
		var t: String = ["arbol_1", "arbol_1", "arbol_2", "arbol_3"][rng.randi() % 4]
		arboles[t].append([Vector3(rng.randf_range(-80, 80), ARRIBA, z), rng.randf_range(0.9, 1.3)])
	for p in [[-44.0, -160.0], [44.0, -140.0], [24.0, -132.0], [-20.0, -186.0], [26.0, -184.0],
			[-46.0, -120.0], [46.0, -108.0], [-8.0, -92.0]]:
		arboles["arbol_1" if rng.randf() < 0.5 else "arbol_3"].append([Vector3(p[0], ARRIBA, p[1]), rng.randf_range(0.9, 1.1)])
	for t in arboles:
		Ambiente._plantas(d, t, arboles[t])
