extends "res://scripts/beach_decor.gd"
class_name MapaPlaneador
## El mapa de la misión 2: EL PLANEADOR (Sainte-Mère-Église, noche del 6 al 7
## de junio de 1944). Se avanza hacia -Z, como en Omaha (así el motor de la
## misión —Escuadras, Defensa, Objetivos— funciona igual):
##   Fase 1, EL CHOQUE (z 14 … -32): la zona de aterrizaje. Tres potreros con
##     los planeadores estrellados (el tuyo, de nariz contra el seto, ardiendo),
##     la granja de la izquierda y la MG42 del seto del fondo.
##   Fase 2, LOS SETOS (z -32 … -100): potreros cerrados por setos (bocage),
##     los contenedores lanzados en paracaídas y el cruce de caminos del
##     camino hundido (z -96).
##   Fase 3, EL PUEBLO (z -108 … -170): Sainte-Mère-Église. La plaza con la
##     iglesia (y el paracaidista colgado del campanario), casas de piedra, un
##     cañón alemán en la calle y una MG42 al norte de la plaza.
##   Fase 4, EL AMANECER (z -170 … -222): la barricada de la salida norte, en
##     la carretera a Neuville. Contraataque alemán con un tanque; al final
##     llegan los Sherman desde Utah.
## Hereda de beach_decor.gd sus herramientas (cajas, sacos de arena, cajas de
## armas, postes) pero arma su propio mapa. Todo es plano (y = 0). La luz de
## noche, las bengalas y los fuegos están en noche.gd, bengala.gd y fuego.gd.

const ANCHO := 46.0              # se juega entre -ANCHO y +ANCHO
const Z_SUR := 14.0
const Z_NORTE := -222.0
const PASO := 4.0                # ancho de un hueco en un seto
const ALTO_TALUD := 0.85         # como los sacos: de rodillas te asomas por encima

var _mt_tierra: StandardMaterial3D
var _mt_camino: StandardMaterial3D
var _mt_tela: StandardMaterial3D
var _mt_techo: StandardMaterial3D
var _mt_metal: StandardMaterial3D
var _plantas := {"seto": [], "arbol_1": [], "arbol_2": [], "arbol_3": [], "pasto": []}
var _canon: MeshInstance3D
var _rng_m := RandomNumberGenerator.new()

static var actual: MapaPlaneador


## Material con textura y luz por píxel (las bengalas iluminan en círculo
## también las cajas grandes, como los taludes de 40 m).
func _pp(nombre: String, metros: float, tinte := Color.WHITE) -> StandardMaterial3D:
	var m := textured(nombre, metros, tinte)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m


func _ready() -> void:
	actual = self
	_rng_m.seed = 7061944
	Noche.preparar(get_parent())
	_steel = _pp("acero_oxidado", 1.2)
	_wood = _pp("madera", 2.0)
	_burlap = _material_tex("res://assets/texturas/arpillera.png", 0.45)
	_burlap.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mt_tierra = _pp("pasto_duna", 2.0, Color(0.42, 0.47, 0.32))
	_mt_camino = _pp("guijarros", 2.5, Color(0.62, 0.56, 0.47))
	_mt_techo = _pp("concreto", 1.6, Color(0.36, 0.38, 0.44))
	_mt_tela = StandardMaterial3D.new()
	_mt_tela.albedo_color = Color(0.78, 0.77, 0.7)
	_mt_tela.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mt_tela.roughness = 1.0
	_mt_metal = StandardMaterial3D.new()
	_mt_metal.albedo_color = Color(0.28, 0.31, 0.22)
	_mt_metal.roughness = 0.9
	Coberturas.limpiar()
	OmahaInterior._kit.clear()
	Game.sea_from_z = INF
	_suelo()
	_setos()
	_caminos()
	_planeadores()
	_paracaidas_sueltos()
	_contenedores()
	_granja()
	_cruce()
	_pueblo()
	_barricada()
	_alrededores()
	_paredes()
	for t in _plantas:
		Ambiente._plantas(self, t, _plantas[t])
	OmahaInterior._armar_kit(self, 75.0)    # de noche, con la niebla, a 75 m del centro del pueblo ya no se ve
	_build_bags()
	_dibujar_postes()
	if not Game.prueba_carga:
		var f := Fragor.new()
		f.noche = true
		add_child(f)

	# Cooperativo: como en Omaha (beach_decor.gd)
	Escuadras.mi_escuadra = Red.actual.puesto if Game.modo_red and Red.actual else 0
	var con_ia := not Game.modo_red or _soy_anfitrion()
	if con_ia:
		get_parent().add_child.call_deferred(Escuadras.new())
		get_parent().add_child.call_deferred(Defensa.new())
	get_parent().add_child.call_deferred(Objetivos.new())
	var p := get_parent().get_node_or_null("Player") as Player
	if p:
		if Game.modo_red and Escuadras.mi_escuadra != 0:
			var s: Vector2 = Misiones.dato("sectores")[Escuadras.mi_escuadra]
			p.position.x = (s.x + s.y) / 2.0 + randf_range(-3.0, 3.0)
			p.position.z = 2.0
		p.set_meta("inicio", p.position)
		if Game.modo_red and Red.actual:
			p.nombre = Red.actual.mi_nombre
	_hornear_navegacion.call_deferred()
	# El salto en paracaídas: el comienzo jugable (salto.gd)
	var salto: Dictionary = Misiones.actual().get("salto", {})
	if not salto.is_empty() and p and not Game.prueba_carga:
		var s := Salto.new()
		s.desde = salto["desde"]
		s.viento = salto["viento"]
		# Cooperativo: cada jugador salta de su propio avión, sobre su sector
		if Game.modo_red and Escuadras.mi_escuadra != 0:
			var sec: Array = Misiones.dato("sectores")
			var mia: Vector2 = sec[Escuadras.mi_escuadra]
			var s0: Vector2 = sec[0]
			var cx := (mia.x + mia.y) / 2.0
			var c0 := (s0.x + s0.y) / 2.0
			s.desde.x += cx - c0
			var x0 := clampf(cx - 8.0, -ANCHO + 3.0, ANCHO - 19.0)
			s.zona = Rect2(x0, 0.0, 16.0, 10.0)
		get_parent().add_child.call_deferred(s)


func _exit_tree() -> void:
	super._exit_tree()
	if actual == self:
		actual = null


func _hornear_navegacion() -> void:
	Navegacion.hornear(get_parent(), AABB(Vector3(-ANCHO, -2, Z_NORTE), Vector3(ANCHO * 2.0, 30, Z_SUR - Z_NORTE)))


# ================================================================ suelo y setos

func _suelo() -> void:
	var g := get_node_or_null("../Ground/Mesh") as MeshInstance3D
	if g:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/campo.gdshader")
		m.set_shader_parameter("pasto", load(TEX % "pasto_duna"))
		m.set_shader_parameter("tierra", load(TEX % "arena_seca"))
		g.material_override = m


## Un seto de Normandía: talud de tierra con arbustos encima (tapan la vista
## pero no las balas) y árboles grandes de vez en cuando. `huecos`: dónde se
## puede pasar (coordenada X en los setos a lo ancho, Z en los a lo largo).
## `anchos`: ancho de cada hueco (por defecto PASO).
func _seto(a: Vector2, b: Vector2, huecos: Array, anchos := {}) -> void:
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
	var desde := minf(a.x, b.x) if horizontal else minf(a.y, b.y)
	var hasta := maxf(a.x, b.x) if horizontal else maxf(a.y, b.y)
	var fijo := a.y if horizontal else a.x
	var cortes: Array = [desde]
	var hs := huecos.duplicate()
	hs.sort()
	for h in hs:
		var w: float = anchos.get(h, PASO)
		cortes.append(h - w / 2.0)
		cortes.append(h + w / 2.0)
	cortes.append(hasta)
	for k in range(0, cortes.size(), 2):
		var c0: float = cortes[k]
		var c1: float = cortes[k + 1]
		var largo := c1 - c0
		if largo < 0.6:
			continue
		var medio := (c0 + c1) / 2.0
		var centro := Vector3(medio, 0, fijo) if horizontal else Vector3(fijo, 0, medio)
		var giro := 0.0 if horizontal else 90.0
		_add_box(centro + Vector3(0, ALTO_TALUD / 2.0, 0), Vector3(largo, ALTO_TALUD, 1.8), _mt_tierra, Vector3(0, giro, 0))
		if absf(centro.x) < ANCHO + 4.0 or not horizontal:
			Coberturas.agregar_muro(centro, largo, giro, 1.8, ALTO_TALUD)
		# Arbustos (2 de cada 3 tramos) y árboles grandes
		var t := c0 + 1.5
		while t < c1 - 1.0:
			var pos := Vector3(t, 0, fijo) if horizontal else Vector3(fijo, 0, t)
			var lado := Vector3(0, 0, 1) if horizontal else Vector3(1, 0, 0)
			if _rng_m.randf() > 0.3:
				_plantas["seto"].append([pos + Vector3(0, 0.8, 0) + lado * _rng_m.randf_range(-0.2, 0.2), _rng_m.randf_range(0.6, 0.78)])
			if _rng_m.randf() < 0.16:
				var tipo: String = ["arbol_1", "arbol_1", "arbol_2", "arbol_3"][_rng_m.randi() % 4]
				_plantas[tipo].append([pos + lado * _rng_m.randf_range(-1.0, 1.0), _rng_m.randf_range(0.95, 1.3)])
			t += _rng_m.randf_range(3.0, 4.0)


func _setos() -> void:
	# A lo ancho: [z, huecos en X]
	var filas := [
		[16.0, []],                              # detrás de la zona de aterrizaje (decorado)
		[-32.0, [-30.0, -2.0, 14.0, 32.0]],      # el de la MG42 (en el hueco de x 14)
		[-64.0, [-34.0, 4.0, 26.0]],
		[-92.0, [-26.0, 4.0, 30.0]],             # el camino hundido: entre z -92 y -100
		[-100.0, [-20.0, 4.0, 24.0]],
		[-186.0, [-28.0, 4.0, 30.0]],            # al norte del pueblo
		[-206.0, [-14.0, 4.0, 22.0, 36.0]],
	]
	for f in filas:
		var anchos := {4.0: 6.0}                 # por donde pasa la carretera, más ancho
		_seto(Vector2(-95.0, f[0]), Vector2(95.0, f[0]), f[1], anchos)
	# A lo largo: [x, z desde, z hasta, huecos en Z]
	for c in [[-20.0, 15.0, -32.0, [-8.0]], [18.0, 15.0, -32.0, [2.0]], [-12.0, -32.0, -64.0, [-46.0]],
			[22.0, -64.0, -92.0, [-80.0]], [-24.0, -186.0, -206.0, [-196.0]], [26.0, -186.0, -206.0, [-194.0]]]:
		_seto(Vector2(c[0], c[1]), Vector2(c[0], c[2]), c[3])
	# Pasto alto en los bordes de los potreros
	for i in 120:
		var z := _rng_m.randf_range(-206.0, 12.0)
		if z < -104.0 and z > -172.0:
			continue      # en el pueblo no
		_plantas["pasto"].append([Vector3(_rng_m.randf_range(-70.0, 70.0), -0.05, z), _rng_m.randf_range(0.6, 1.1)])


func _caminos() -> void:
	# La carretera (N13) de sur a norte por x 4, y el camino hundido (z -96)
	Game.box(self, Vector3(5.0, 0.04, 164.0), Vector3(4, 0.02, -140.0), _mt_camino)
	Game.box(self, Vector3(190.0, 0.04, 4.0), Vector3(0, 0.025, -96.0), _mt_camino)
	# Calles del pueblo: alrededor de la plaza y hacia el oeste
	Game.box(self, Vector3(60.0, 0.04, 4.0), Vector3(-26, 0.025, -120.0), _mt_camino)
	Game.box(self, Vector3(60.0, 0.04, 4.0), Vector3(-26, 0.025, -160.0), _mt_camino)
	# La plaza (empedrada)
	Game.box(self, Vector3(30.0, 0.03, 36.0), Vector3(-13, 0.015, -140.0), _mt_camino)


# ================================================================ planeadores

## Un planeador estrellado. `nariz`: hacia dónde apunta (el modelo mira a -X).
func _planeador(pos: Vector3, nariz: Vector3, fuego := 0.0, choque := true) -> void:
	var giro := rad_to_deg(atan2(nariz.z, -nariz.x))
	var m := OmahaInterior._modelo(self, "planeador", pos, giro, 14.0, choque)
	m.rotation_degrees.x = _rng_m.randf_range(-3.0, 3.0)
	m.rotation_degrees.z = _rng_m.randf_range(-5.0, 2.0)     # la nariz, clavada
	if fuego > 0.0:
		Fuego.encender(self, pos + nariz.normalized() * 5.0 + Vector3(0, 0.2, 0), fuego)


func _planeadores() -> void:
	# El tuyo: de nariz contra el seto del fondo, ardiendo
	_planeador(Vector3(-8, 0, -24.5), Vector3(0.1, 0, -1), 1.0)
	# El de Kowalski (izquierda) y el de Reyes (derecha)
	_planeador(Vector3(-33, 0, -2), Vector3(0.35, 0, -1), 0.7)
	_planeador(Vector3(32, 0, -12), Vector3(-0.5, 0, -0.85))
	# Uno que se estrelló antes, entre los setos del medio
	_planeador(Vector3(-31, 0, -79), Vector3(0.9, 0, -0.3), 0.8)
	# Más allá de las paredes (decorado)
	_planeador(Vector3(66, 0, -40), Vector3(-0.2, 0, -1), 0.0, false)
	_planeador(Vector3(-70, 0, -18), Vector3(0.6, 0, -0.8), 0.9, false)
	_planeador(Vector3(-62, 0, -120), Vector3(0.1, 0, -1), 0.0, false)


## Un paracaídas (tela blanca) caído en el suelo o enganchado en un seto o árbol.
func _paracaidas(pos: Vector3, tam := 1.0, aplastado := 0.35, giro := Vector3.ZERO) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 2.6 * tam
	s.height = 2.6 * tam
	s.is_hemisphere = true
	s.radial_segments = 10
	s.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = _mt_tela
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation_degrees = giro
	mi.scale = Vector3(1.0, aplastado, 1.0)
	add_child(mi)
	return mi


func _paracaidas_sueltos() -> void:
	# Enganchados en los setos (de la noche anterior: los paracaidistas del 6)
	for p in [[Vector3(-26, 1.4, -32.4), 30.0], [Vector3(36, 1.5, -64.2), -20.0], [Vector3(-40, 1.4, -92.5), 15.0],
			[Vector3(10, 1.6, -64.5), 50.0], [Vector3(-21, 1.2, -20), 70.0], [Vector3(30, 1.5, -186.3), -35.0]]:
		_paracaidas(p[0], 0.9, 0.45, Vector3(p[1], _rng_m.randf_range(0, 360), _rng_m.randf_range(-20, 20)))
	# Caídos en el pasto
	for p in [Vector3(6, 0.05, -8), Vector3(-36, 0.05, -40), Vector3(14, 0.05, -76), Vector3(-6, 0.05, -196)]:
		_paracaidas(p, 0.8, 0.12)


## Los contenedores de armas lanzados en paracaídas (objetivos de la fase 2).
func _contenedores() -> void:
	for c in [[Vector3(-28, 0, -48), "bazooka", 25.0], [Vector3(30, 0, -80), "bar", -60.0]]:
		var pos: Vector3 = c[0]
		var cil := CylinderMesh.new()
		cil.top_radius = 0.3
		cil.bottom_radius = 0.3
		cil.height = 1.8
		cil.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = cil
		mi.material_override = _mt_metal
		mi.position = pos + Vector3(0, 0.3, 0)
		mi.rotation_degrees = Vector3(0, c[2], 90)
		add_child(mi)
		_paracaidas(pos + Vector3(2.2, 0.05, 1.0), 0.75, 0.1)
		_add_crate(pos + Vector3(-1.2, 0, 1.4), c[1], _rng_m)
		Coberturas.agregar_erizo(pos)


# ================================================================ fase 1 y 2

## La granja de la izquierda (objetivo de las escuadras de Kowalski y Cole).
func _granja() -> void:
	OmahaInterior._modelo(self, "casa", Vector3(-36, 0, -22), 90.0, 10.0)
	OmahaInterior._modelo(self, "carreta", Vector3(-28, 0, -16), 40.0, 3.6)
	for s in [[-29.0, -26.0, 4.0, 0.0], [-25.0, -21.0, 3.0, 80.0]]:
		_sandbag_wall(Vector3(s[0], 0, s[1]), s[2], 6, 2, s[3], _rng_m)
	# El nido de la MG42 del seto del fondo (en el hueco de x 14)
	_sandbag_wall(Vector3(14, 0, -33.6), 3.6, 6, 2, 0.0, _rng_m)
	_sandbag_wall(Vector3(11.6, 0, -34.6), 2.0, 6, 2, 70.0, _rng_m)
	# Posiciones alemanas detrás del seto
	for s in [[-20.0, -35.0], [0.0, -35.5], [28.0, -35.0], [-36.0, -36.0]]:
		_sandbag_wall(Vector3(s[0], 0, s[1]), 3.0, 6, 2, _rng_m.randf_range(-8, 8), _rng_m)


## El cruce del camino hundido (fase 2): la MG42 y parapetos alemanes.
func _cruce() -> void:
	_sandbag_wall(Vector3(9.5, 0, -97.4), 3.4, 6, 2, 0.0, _rng_m)     # la MG42
	_sandbag_wall(Vector3(-2.0, 0, -97.6), 3.0, 6, 2, 0.0, _rng_m)
	_sandbag_wall(Vector3(17.0, 0, -95.0), 3.0, 6, 2, 90.0, _rng_m)
	OmahaInterior._modelo(self, "carreta", Vector3(-9, 0, -95.5), 10.0, 3.6)
	# Un cartel de madera en el cruce (para encontrarlo)
	Game.box(self, Vector3(0.12, 2.2, 0.12), Vector3(1.0, 1.1, -93.4), _wood)
	Game.box(self, Vector3(1.2, 0.4, 0.06), Vector3(1.3, 1.9, -93.4), _wood)
	# Parapetos sueltos en los potreros (sirven a los dos bandos)
	for s in [[-20.0, -58.0], [12.0, -56.0], [-32.0, -70.0], [10.0, -84.0], [36.0, -88.0], [-14.0, -88.0]]:
		_sandbag_wall(Vector3(s[0], 0, s[1]), 3.0, 5, 2, _rng_m.randf_range(-10, 10), _rng_m)
	OmahaInterior._modelo(self, "carreta", Vector3(-2, 0, -76), -30.0, 3.6)
	OmahaInterior._modelo(self, "camion", Vector3(36, 0, -50), 70.0, 6.0)


# ================================================================ fase 3: el pueblo

## Casa de piedra entera (paredes del kit, con techo de pizarra). `quemada`:
## sin techo (el techo quemado encima) y con fuego adentro.
func _casa(c: Vector3, ancho: float, fondo: float, frente := 0, quemada := false) -> void:
	var paredes := [
		[Vector3(0, 0, fondo / 2.0), ancho, 0.0], [Vector3(0, 0, -fondo / 2.0), ancho, 180.0],
		[Vector3(-ancho / 2.0, 0, 0), fondo, -90.0], [Vector3(ancho / 2.0, 0, 0), fondo, 90.0],
	]
	for k in paredes.size():
		var largo: float = paredes[k][1]
		var giro: float = paredes[k][2]
		var n := maxi(1, roundi(largo / 4.2))
		var w := largo / n
		var b := Basis(Vector3.UP, deg_to_rad(giro))
		var puerta := n / 2 if k == frente else -1
		for i in n:
			var tipo := "muro_puerta" if i == puerta else ("muro_roto" if quemada and _rng_m.randf() < 0.3 else "muro_ventana")
			var x := (i - (n - 1) / 2.0) * w
			OmahaInterior._pieza(self, tipo, c + paredes[k][0] + b * Vector3(x, 0, 0), w, giro)
	if quemada:
		var t: AABB = (load("res://assets/decorado/techo_quemado.res") as Mesh).get_aabb()
		var esc := Vector3((ancho + 0.6) / t.size.x, 2.6 / t.size.y, (fondo + 0.6) / t.size.z)
		if not OmahaInterior._kit.has("techo_quemado"):
			OmahaInterior._kit["techo_quemado"] = []
		OmahaInterior._kit["techo_quemado"].append(Transform3D(Basis.from_scale(esc), c + Vector3(0, 3.3, 0)))
		Fuego.encender(self, c + Vector3(0, 0.3, 0), 1.6)
	else:
		# Techo a dos aguas (no choca: no se llega)
		var pr := PrismMesh.new()
		pr.size = Vector3(fondo + 0.8, 2.6, ancho + 0.8)
		var mi := MeshInstance3D.new()
		mi.mesh = pr
		mi.material_override = _mt_techo
		mi.position = c + Vector3(0, 3.4 + 1.3, 0)
		mi.rotation_degrees.y = 90.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 140.0
		add_child(mi)
	OmahaInterior._modelo(self, "escombros", c + Vector3(_rng_m.randf_range(-1.2, 1.2), 0, _rng_m.randf_range(-1.0, 1.0)),
		_rng_m.randf_range(0, 360), 1.8)


func _pueblo() -> void:
	# [centro X, centro Z, ancho, fondo, pared con la puerta (0 sur, 1 norte, 2 oeste, 3 este), quemada]
	var casas := [
		# Lado sur de la plaza
		[-24.0, -114.0, 9.0, 7.0, 1, false], [-8.0, -113.0, 8.0, 6.0, 1, false],
		# Lado norte de la plaza
		[-24.0, -169.0, 9.0, 7.0, 0, false], [-8.0, -168.0, 8.0, 6.0, 0, true],
		# Lado oeste
		[-38.0, -132.0, 7.0, 8.0, 3, false], [-38.0, -150.0, 7.0, 8.0, 3, false],
		# Al este de la carretera
		[15.0, -116.0, 8.0, 7.0, 2, false], [15.0, -133.0, 8.0, 8.0, 2, true], [15.0, -151.0, 8.0, 7.0, 2, false],
		[31.0, -122.0, 7.0, 7.0, 2, false], [32.0, -160.0, 8.0, 7.0, 2, false],
	]
	for c in casas:
		_casa(Vector3(c[0], 0, c[1]), c[2], c[3], c[4], c[5])
	# La iglesia en medio de la plaza, con el campanario hacia el sur (+Z)
	var ig := OmahaInterior._modelo(self, "iglesia", Vector3(-14, 0, -141), 0.0, 24.0)
	ig.material_override = OmahaInterior.material_piedra()
	# El paracaidista colgado del campanario (John Steele, 82.ª, la noche del 6)
	var esc := 24.0 / 1.9018
	# (la tela enganchada en un costado del techo del campanario; él cuelga debajo)
	var torre := Vector3(-14.0, 1.12 * esc, -141.0 + 0.8 * esc)
	var tela := _paracaidas(torre + Vector3(2.2, 0.2, 0.6), 0.62, 0.55, Vector3(-15, 30, -62))
	tela.visibility_range_end = 0.0
	var steele := Salto.colgado(self, torre + Vector3(3.0, -4.6, 0.9))
	steele.visibility_range_end = 0.0
	var arriba: Vector3 = steele.get_meta("arriba")
	Game.box(self, Vector3(0.04, 2.4, 0.04), arriba + Vector3(0, 1.1, 0), _mt_metal)   # los cordones hasta la tela
	# El cañón de la calle (objetivo de la fase 3) y sus sacos
	_canon = OmahaInterior._modelo(self, "canon", Vector3(26, 0, -140), 90.0, 5.5)
	_sandbag_wall(Vector3(26, 0, -136.6), 4.0, 6, 2, 0.0, _rng_m)
	# La MG42 del norte de la plaza, tirando hacia el sur por la plaza
	_sandbag_wall(Vector3(-26, 0, -155.1), 3.6, 6, 2, 0.0, _rng_m)
	_sandbag_wall(Vector3(-28.4, 0, -153.6), 2.0, 6, 2, 80.0, _rng_m)
	# Parapetos alemanes por el pueblo
	for s in [[-2.0, -150.0, 0.0], [8.0, -126.0, 90.0], [-30.0, -126.0, 0.0], [0.0, -158.0, 0.0], [22.0, -150.0, 0.0],
			[-2.0, -132.0, 90.0]]:
		_sandbag_wall(Vector3(s[0], 0, s[1]), 3.0, 6, 2, s[2], _rng_m)
	# Un camión alemán, carretas y escombros
	OmahaInterior._modelo(self, "camion", Vector3(4, 0, -108), 100.0, 6.0)
	OmahaInterior._modelo(self, "carreta", Vector3(-30, 0, -144), 0.0, 3.6)
	for e in [[6.0, -146.0], [-2.0, -122.0], [24.0, -128.0]]:
		OmahaInterior._modelo(self, "escombros", Vector3(e[0], 0, e[1]), _rng_m.randf_range(0, 360), 2.2)
	# Árboles de la plaza
	for p in [[-28.0, -122.0], [0.0, -122.0], [-28.0, -158.0], [0.0, -162.0]]:
		_plantas["arbol_1"].append([Vector3(p[0], 0, p[1]), 0.9])


## El cañón voló (efecto del objetivo de la fase 3).
func destruir_canon() -> void:
	if _canon and is_instance_valid(_canon):
		_canon.rotation_degrees.z = 12.0
		_canon.scale.y *= 0.7
		var m := Ambiente.material_modelo()
		m.albedo_color = Color(0.3, 0.28, 0.26)
		_canon.material_override = m
		Fuego.encender(self, _canon.global_position + Vector3(0, 0.2, 0), 0.6)
		_canon = null


# ================================================================ fase 4: la barricada

func _barricada() -> void:
	# La barricada cruzada en la carretera a la salida norte del pueblo
	OmahaInterior._modelo(self, "carreta", Vector3(2, 0, -177.5), 0.0, 3.6)
	_sandbag_wall(Vector3(7.5, 0, -177.8), 4.0, 6, 2, 0.0, _rng_m)
	for s in [[-10.0, -178.0, 0.0], [18.0, -178.5, 0.0], [-22.0, -176.0, 15.0], [30.0, -176.0, -15.0],
			[-4.0, -172.0, 0.0], [12.0, -171.0, 0.0]]:
		_sandbag_wall(Vector3(s[0], 0, s[1]), 4.0, 6, 2, s[2], _rng_m)
	_add_crate(Vector3(7, 0, -172.5), "bazooka", _rng_m)
	_add_crate(Vector3(-2, 0, -170.5), "thompson", _rng_m)
	# Lo que usan los alemanes para avanzar: parapetos y restos en los potreros del norte
	for s in [[-30.0, -198.0], [-10.0, -200.0], [14.0, -199.0], [34.0, -200.0], [-36.0, -214.0], [0.0, -214.0],
			[24.0, -215.0], [-18.0, -190.0], [20.0, -190.0]]:
		_sandbag_wall(Vector3(s[0], 0, s[1]), 3.5, 6, 2, _rng_m.randf_range(-12, 12), _rng_m)
	OmahaInterior._modelo(self, "carreta", Vector3(-26, 0, -192), 70.0, 3.6)
	OmahaInterior._modelo(self, "camion", Vector3(30, 0, -212), 20.0, 6.0)


# ================================================================ alrededores y límites

func _alrededores() -> void:
	# Granjas, árboles y un bosque al fondo: más allá de las paredes (sin choque)
	for c in [[-66.0, -60.0, 90.0], [70.0, -96.0, -90.0], [-64.0, -150.0, 30.0], [64.0, -140.0, -20.0],
			[-60.0, -196.0, 0.0], [62.0, -200.0, 0.0], [70.0, 4.0, 180.0]]:
		OmahaInterior._modelo(self, "casa", Vector3(c[0], 0, c[1]), c[2], 9.0, false)
	for i in 70:
		var t: String = ["arbol_1", "arbol_2", "arbol_3", "arbol_1"][_rng_m.randi() % 4]
		var z := _rng_m.randf_range(-250.0, -226.0)
		_plantas[t].append([Vector3(_rng_m.randf_range(-90, 90), 0, z), _rng_m.randf_range(1.0, 1.4)])
	for lado in [-1.0, 1.0]:
		for i in 24:
			var t: String = ["arbol_1", "arbol_2", "arbol_3", "arbol_1"][_rng_m.randi() % 4]
			_plantas[t].append([Vector3(lado * _rng_m.randf_range(52.0, 95.0), 0, _rng_m.randf_range(-220.0, 10.0)),
				_rng_m.randf_range(0.9, 1.3)])


## Paredes invisibles alrededor de la zona de juego (capa 7: paran a la gente,
## no a las balas ni a la vista).
func _paredes() -> void:
	var muros := [
		[Vector3(-ANCHO - 0.5, 10, (Z_SUR + Z_NORTE) / 2.0), Vector3(1, 40, Z_SUR - Z_NORTE + 4)],
		[Vector3(ANCHO + 0.5, 10, (Z_SUR + Z_NORTE) / 2.0), Vector3(1, 40, Z_SUR - Z_NORTE + 4)],
		[Vector3(0, 10, Z_SUR + 0.5), Vector3(ANCHO * 2 + 4, 40, 1)],
		[Vector3(0, 10, Z_NORTE - 0.5), Vector3(ANCHO * 2 + 4, 40, 1)],
	]
	for m in muros:
		var b := StaticBody3D.new()
		b.collision_layer = 64
		b.collision_mask = 0
		b.position = m[0]
		var col := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = m[1]
		col.shape = forma
		b.add_child(col)
		add_child(b)


# ================================================================ lo que pide la misión

## Objetivos: lo que cambia en el mapa al cumplir un objetivo.
func efecto(nombre: String) -> void:
	match nombre:
		"canon":
			destruir_canon()


var _tanque_listo := false
var _shermans := false


func _process(_delta: float) -> void:
	if Objetivos.actual == null or Objetivos.terminado != 0:
		return
	for i in Objetivos.LISTA.size():
		var o: Dictionary = Objetivos.LISTA[i]
		if o["tipo"] != "defender" or not Objetivos.activo(i):
			continue
		var pr: float = Objetivos.progreso[i]
		# El tanque alemán baja por la carretera (lo maneja quien tiene la IA)
		if pr >= 0.3 and not _tanque_listo and Objetivos.manda():
			_tanque_listo = true
			Red.anunciar("[¡TANQUE ALEMÁN POR LA CARRETERA! ¡BAZUCA!]", Game.COLOR_BAD)
			Tanque.crear(get_parent(), [Vector3(4, 0, -262), Vector3(4, 0, -214), Vector3(3, 0, -199)])
		# Los Sherman de Utah entran al pueblo por el sur
		if pr >= 0.85 and not _shermans:
			_shermans = true
			if Objetivos.manda():
				Red.anunciar("[RADIO: ¡TANQUES DE UTAH ENTRANDO AL PUEBLO!]", Game.COLOR_GOOD)
			_llegan_shermans((1.0 - minf(pr, 1.0)) * float(o.get("seg", 120.0)))


func _llegan_shermans(segundos: float) -> void:
	var ruta := [Vector3(4, 0, -66), Vector3(4, 0, -104), Vector3(4, 0, -150)]
	var vel: float = ((ruta[0] as Vector3).distance_to(ruta[2]) + 18.0) / maxf(segundos * 0.7, 8.0)
	for t in [[Vector3(4, 0, -166), 0.0], [Vector3(4, 0, -158), 7.0]]:
		var puntos: Array = ruta + [t[0]]
		var m := OmahaInterior._modelo(self, "sherman_ok", puntos[0], 0.0, 5.9, false)
		m.visible = false
		var tw := m.create_tween()
		tw.tween_interval(t[1])
		tw.tween_callback(m.show)
		for k in range(1, puntos.size()):
			var a: Vector3 = puntos[k - 1]
			var b: Vector3 = puntos[k]
			var dir := (b - a).normalized()
			tw.tween_property(m, "rotation:y", atan2(dir.z, -dir.x), 0.4)
			tw.tween_property(m, "position", b, a.distance_to(b) / vel)
