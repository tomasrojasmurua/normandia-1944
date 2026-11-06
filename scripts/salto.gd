extends Node3D
class_name Salto
## El salto en paracaídas (misión 2): el comienzo jugable de la misión.
## La cinemática termina en la puerta del C-47 alcanzado y el juego empieza en
## el aire, a ~135 m:
##   1. Caída libre (1,3 s): viento fuerte, todo se sacude.
##   2. El tirón del paracaídas: se abre y el tirón te arranca el arma principal
##      (se la ve caer). Te queda la pistola (weapons.perder_principal).
##   3. El descenso (~22 s): mirar libre con el dedo; con el stick te inclinas
##      un poco hacia dónde caer, pero el viento empuja. Alrededor, la guerra:
##      tu avión ardiendo que se va a pique y se estrella lejos, la formación
##      de C-47 pasando por encima con sus paracaidistas, antiaérea estallando,
##      trazadoras subiendo desde el suelo (algunas pasan a tu lado), reflectores,
##      fuegos y bengalas sobre los potreros y el pueblo, un compañero alcanzado
##      en el aire. El corazón late cada vez más fuerte.
##   4. El aterrizaje: golpe, negro un instante, y estás solo en un potrero
##      con el paracaídas en el suelo. Toda tu escuadra quedó dispersa.
## Todo lo lejano (el "panorama") vive solo durante el salto y se borra al
## aterrizar. Mientras se cae no te pueden matar (los alemanes disparan igual).
## Lo crea MapaPlaneador si la misión tiene "salto".

static var activo := false
static var actual: Salto

const CAIDA_LIBRE := 1.3
const VEL_PARACAIDAS := 5.4
const VEL_LADO := 3.0
const RATE := 22050

var desde := Vector3(-6, 135, 22)
var viento := Vector3(0.35, 0, -0.75)
# Dónde se puede caer (x, z): el potrero del medio, lejos de la MG42 del seto
# (z -34) y de la granja (x < -24). Tuviste suerte: nadie te dispara al llegar.
var zona := Rect2(-14, -4, 30, 14)

var _p: Player
var _t := 0.0
var _vel := Vector3.ZERO
var _abierto := false
var _aterrizado := false
var _sacudida := 0.0
var _negro := 0.0
var _capa: Control
var _rng := RandomNumberGenerator.new()

# Panorama
var _lejos: Node3D
var _mm_luz: MultiMesh            # todas las luces aditivas (fuegos, trazadoras, flak, bengalas lejanas)
var _luces: Array = []            # [{pos, color, tam, vida, vel, tipo}] — una por instancia
var _mm_humo: MultiMesh
var _humos: Array = []
var _paracaidistas: Array = []    # [Sprite3D, vel_y, abre_t]
var _aviones: Array = []          # [Node3D, vel, motor]
var _mi_avion: Node3D
var _mi_avion_vel := Vector3.ZERO
var _choco := false
var _reflectores: Array = []
var _emisores: Array = []         # [pos, t_siguiente, color]
var _t_flak := 0.6
var _t_cerca := 3.0
var _t_tierra := 0.5
var _t_latido := 1.0
var _herido_hecho := false
var _arma_perdida := "garand"
var _walsh: Node3D
var _walsh_visto := false
var _bengala_hecha := false
var _arma_cae: Node3D
var _viento_snd: AudioStreamPlayer
var _latido: AudioStream
var _tex_para: Texture2D

const N_LUCES := 360
const N_HUMO := 40


func _ready() -> void:
	actual = self
	activo = true
	_rng.randomize()
	_p = get_tree().get_first_node_in_group("player") as Player
	if _p == null:
		queue_free()
		return
	_p.set_physics_process(false)
	_p.global_position = desde
	_p.rotation.y = atan2(-viento.x, -viento.z) + 0.25   # mirando hacia el pueblo, un poco de lado
	_p.head.rotation.x = deg_to_rad(-35.0)
	_vel = Vector3(0, -2.0, 0)
	_armar_capa()
	_armar_panorama()
	_armar_sonidos()
	Noche.niebla_mult = 0.1


func _exit_tree() -> void:
	if actual == self:
		actual = null
		activo = false
		Noche.niebla_mult = 1.0


func _process(delta: float) -> void:
	if Game.warming:                  # mientras dice PREPARANDO, quieto arriba
		_p.global_position = desde
		return
	if _aterrizado:
		_negro = maxf(_negro - delta * 0.8, 0.0)
		_capa.queue_redraw()
		_t += delta
		if _t < 3.0:
			_p.health = _p.max_health
		_mirar_walsh()
		if _t > 3.0 and _negro <= 0.0 and (_walsh_visto or _t > 120.0):
			queue_free()
		return
	_t += delta
	_p.health = _p.max_health          # en el aire no te matan
	_mover(delta)
	_actualizar_panorama(delta)
	# Sacudida de la cámara (el jugador tiene la física apagada: la hacemos aquí)
	_sacudida = maxf(_sacudida - delta * 1.6, 0.0)
	var s := _sacudida * (2.0 if not _abierto else 1.0)
	_p.camera.h_offset = _rng.randf_range(-1, 1) * s * 0.08
	_p.camera.v_offset = _rng.randf_range(-1, 1) * s * 0.08
	# Niebla: casi nada arriba, la de siempre al llegar al suelo
	var y := _p.global_position.y
	Noche.niebla(lerpf(1.0, 0.1, smoothstep(6.0, 70.0, y)))
	# El corazón, cada vez más rápido
	_t_latido -= delta
	if _t_latido <= 0.0:
		_t_latido = lerpf(0.42, 0.85, smoothstep(5.0, 120.0, y))
		Game.play("latido", lerpf(-2.0, -14.0, smoothstep(5.0, 120.0, y)))
	_capa.queue_redraw()


# ================================================================ el jugador

func _mover(delta: float) -> void:
	var pos := _p.global_position
	if not _abierto:
		_vel.y = maxf(_vel.y - 9.8 * delta, -30.0)
		_sacudida = maxf(_sacudida, 0.6)
		if _t >= CAIDA_LIBRE:
			_abrir()
	else:
		_vel.y = move_toward(_vel.y, -VEL_PARACAIDAS, delta * 30.0)
		var entrada := _p.touch_move
		if entrada == Vector2.ZERO:
			entrada = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var lado := _p.global_basis * Vector3(entrada.x, 0, entrada.y)
		lado.y = 0.0
		var quiere := viento + lado.normalized() * VEL_LADO * minf(entrada.length(), 1.0)
		_vel.x = move_toward(_vel.x, quiere.x, delta * 2.0)
		_vel.z = move_toward(_vel.z, quiere.z, delta * 2.0)
		# Cerca del suelo, el viento te deja dentro de los potreros
		if pos.y < 60.0:
			var cx := clampf(pos.x, zona.position.x, zona.end.x)
			var cz := clampf(pos.z, zona.position.y, zona.end.y)
			_vel.x += (cx - pos.x) * delta * 0.8
			_vel.z += (cz - pos.z) * delta * 0.8
	pos += _vel * delta
	# El suelo (o lo que haya debajo: un seto, un techo)
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2, 0), pos + Vector3(0, -3, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and pos.y <= hit["position"].y + 0.05:
		pos.y = hit["position"].y + 0.05
		_p.global_position = pos
		_aterrizar()
		return
	if pos.y < -1.0:
		pos.y = 0.1
		_p.global_position = pos
		_aterrizar()
		return
	_p.global_position = pos


func _abrir() -> void:
	_abierto = true
	_vel.y = -9.0
	_sacudida = 1.4
	Game.play("tela", 2.0)
	Game.play("hit", -4.0, 0.5)
	_viento_snd.volume_db = -14.0
	# El tirón te arranca el arma principal
	var w := _p.weapons
	if w.slots[0] != "nada":
		var perdida := w.perder_principal()
		_arma_perdida = perdida
		Game.say("[¡EL TIRÓN TE ARRANCA EL %s! SOLO TE QUEDA LA PISTOLA]" % Armas.datos(perdida)["name"], Game.COLOR_BAD)
		_arma_cae = Node3D.new()
		var mi := Armas.modelo_3d(perdida)
		mi.scale = Vector3.ONE * 1.4
		_arma_cae.add_child(mi)
		add_child(_arma_cae)
		_arma_cae.global_position = _p.camera.global_position + _p.global_basis * Vector3(0.4, -1.2, -1.4)
		_arma_cae.set_meta("vel", Vector3(_rng.randf_range(-1, 1), -4.0, _rng.randf_range(-1, 1)))


func _aterrizar() -> void:
	_aterrizado = true
	activo = false
	_t = 0.0
	_negro = 1.0
	_p.set_physics_process(true)
	_p.velocity = Vector3.ZERO
	_p.camera.h_offset = 0.0
	_p.camera.v_offset = 0.0
	_p.head.rotation.x = deg_to_rad(-8.0)
	_p.set_meta("inicio", _p.global_position)
	# Tuviste suerte: los alemanes no te vieron caer. Por un rato no te ven de
	# lejos (salvo que dispares o te les acerques): ver Noche.factor_vista
	_p.set_meta("gracia_hasta", Game.elapsed + 45.0)
	_p.shake(1.0)
	Game.play("hit", 4.0, 0.45)
	Game.play("bounce", 0.0, 0.5)
	_viento_snd.stop()
	Noche.niebla(1.0)
	# El paracaídas queda en el suelo, arrastrado por el viento
	if MapaPlaneador.actual:
		MapaPlaneador.actual._paracaidas(_p.global_position + viento.normalized() * 4.0 + Vector3(0, 0.05, 0), 0.9, 0.12)
	if _lejos:
		_lejos.queue_free()
		_lejos = null
	Game.say("[ESTÁS EN EL SUELO. TU ESCUADRA ESTÁ DISPERSA: USA EL GRILLO]", Game.COLOR_INFO)
	_colgar_walsh()


## Walsh, al que le dieron en el aire: su paracaídas quedó enganchado en un
## árbol cerca de donde caíste y él cuelga del arnés, sin vida. Su arma está
## en el suelo, debajo (él no la perdió): se puede recoger.
func _colgar_walsh() -> void:
	var escena := get_parent()
	var frente := -_p.global_basis.z
	frente.y = 0.0
	frente = frente.normalized() if frente.length() > 0.1 else Vector3(0, 0, -1)
	# Hacia el centro del potrero y un poco hacia atrás: lejos de la MG42 del seto
	var hacia_centro := -1.0 if _p.global_position.x > 0.0 else 1.0
	var base := _p.global_position + Vector3(hacia_centro * 11.0, 0, 4.0)
	base.x = clampf(base.x, -16.0, 16.0)
	base.z = clampf(base.z, -2.0, 11.0)
	if Navegacion.listo:
		base = Navegacion.cerca_de(base)
	base.y = 0.0
	_walsh = Node3D.new()
	_walsh.name = "Walsh"
	escena.add_child(_walsh)
	_walsh.global_position = base
	Ambiente._plantas(_walsh, "arbol_1", [[Vector3.ZERO, 0.8]])
	# Lo primero que ves al levantarte: él
	var ver := base - _p.global_position
	_p.rotation.y = atan2(-ver.x, -ver.z)
	# Hacia donde caíste (para que el árbol no lo tape) y un poco al costado
	var hacia := _p.global_position - base
	hacia.y = 0.0
	hacia = hacia.normalized() if hacia.length() > 0.1 else Vector3(0, 0, 1)
	var costado := hacia.cross(Vector3.UP)
	var junto := hacia * 1.4 + costado * 2.6     # fuera del tronco: se recorta contra el cielo
	# La tela enredada en la copa
	var tela_pos := junto * 0.6 + Vector3(0, 7.6, 0)
	if MapaPlaneador.actual:
		var t := MapaPlaneador.actual._paracaidas(base + tela_pos, 0.85, 0.5, Vector3(-30, 35, 20))
		t.reparent(_walsh)
	# Él, colgando del arnés
	var cuerpo := Salto.colgado(_walsh, junto + Vector3(0, 2.0, 0))
	# Los cordones, de las bandas a la tela
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.55, 0.55, 0.5)
	var arriba: Vector3 = cuerpo.get_meta("arriba")
	for lado in [-0.2, 0.2]:
		var a := arriba + Vector3(lado, 0, 0)
		var b := tela_pos + Vector3(lado * 4.0, -0.8, 0)
		var m := Game.box(_walsh, Vector3(0.03, a.distance_to(b), 0.03), (a + b) / 2.0, cord)
		m.look_at_from_position(_walsh.global_position + (a + b) / 2.0, _walsh.global_position + b, Vector3.FORWARD)
		m.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	# Su arma, caída al pie del árbol, cargada
	var d := Armas.datos(_arma_perdida)
	ArmaSuelta.soltar(escena, base + junto + hacia * 0.8 + Vector3(0, 0.05, 0), _arma_perdida, int(d["mag"]), int(d["reserve"]))
	# Los alemanes se oyen cerca, pero no te vieron
	get_tree().create_timer(3.5).timeout.connect(func() -> void:
		if is_instance_valid(self):
			Game.play_at("grito_aleman", _p.global_position + frente.rotated(Vector3.UP, 1.9) * 40.0, -4.0))


func _mirar_walsh() -> void:
	if _walsh_visto or _walsh == null or not is_instance_valid(_walsh):
		return
	var d := _p.global_position.distance_to(_walsh.global_position)
	if d < 9.0:
		_walsh_visto = true
		Game.say("[ES WALSH... CUELGA DEL ÁRBOL, SIN VIDA. SU ARMA ESTÁ EN EL SUELO]", Game.COLOR_INFO)


# ================================================================ lo que se ve en pantalla

## Las correas (bandas) del paracaídas a los lados y, al mirar arriba, la tela.
## Al aterrizar, negro que se aclara.
func _armar_capa() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 1
	add_child(cl)
	_capa = Control.new()
	_capa.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa.draw.connect(_dibujar)
	cl.add_child(_capa)


const TEX_BANDAS := "res://assets/salto/bandas.png"
const TEX_TELA := "res://assets/salto/tela.png"
static var _bandas: Texture2D
static var _tela: Texture2D


func _dibujar() -> void:
	var s := _capa.size
	if not _aterrizado and _abierto:
		if _bandas == null and ResourceLoader.exists(TEX_BANDAS):
			_bandas = load(TEX_BANDAS)
			_tela = load(TEX_TELA)
		var mira := _p.head.rotation.x          # >0 mirando arriba
		var luna := Noche.tinte.lerp(Color.WHITE, 0.45)
		# La tela, si se mira hacia arriba (detrás de las manos)
		if mira > 0.45 and _tela:
			var k := clampf((mira - 0.45) / 0.7, 0.0, 1.0)
			var lado_t := s.x * 0.95
			var y := lerpf(-lado_t * 0.95, -lado_t * 0.2, k)
			_capa.draw_texture_rect(_tela, Rect2((s.x - lado_t) / 2.0, y, lado_t, lado_t), false, luna)
		# Las manos agarrando las bandas
		if _bandas:
			var alto := s.y * 0.92
			var ancho := alto * 1.5
			var baja := clampf(-mira, 0.0, 0.6) * s.y * 0.25     # mirando abajo, las manos quedan más arriba
			_capa.draw_texture_rect(_bandas, Rect2((s.x - ancho) / 2.0, s.y - alto - baja + s.y * 0.04, ancho, alto), false, luna)
	if _negro > 0.0:
		_capa.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, clampf(_negro * 1.3, 0.0, 1.0)))


# ================================================================ el panorama

func _armar_panorama() -> void:
	_lejos = Node3D.new()
	_lejos.name = "Panorama"
	add_child(_lejos)
	_suelo_lejano()
	_pueblo_lejano()
	# Luces: una sola MultiMesh de resplandores aditivos (fuegos, trazadoras, flak, bengalas)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Bengala._textura_brillo()
	mat.disable_fog = true
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.material = mat
	_mm_luz = MultiMesh.new()
	_mm_luz.transform_format = MultiMesh.TRANSFORM_3D
	_mm_luz.use_colors = true
	_mm_luz.mesh = q
	_mm_luz.instance_count = N_LUCES
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm_luz
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 2000, 10000))
	_lejos.add_child(mmi)
	for i in N_LUCES:
		_luces.append({"vida": 0.0})
		_mm_luz.set_instance_color(i, Color(0, 0, 0, 0))
		_mm_luz.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0)))
	# Humo de la antiaérea (manchas oscuras)
	var mh := StandardMaterial3D.new()
	mh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mh.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mh.billboard_keep_scale = true
	mh.vertex_color_use_as_albedo = true
	mh.albedo_texture = mat.albedo_texture
	mh.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var qh := QuadMesh.new()
	qh.material = mh
	_mm_humo = MultiMesh.new()
	_mm_humo.transform_format = MultiMesh.TRANSFORM_3D
	_mm_humo.use_colors = true
	_mm_humo.mesh = qh
	_mm_humo.instance_count = N_HUMO
	var mmh := MultiMeshInstance3D.new()
	mmh.multimesh = _mm_humo
	mmh.custom_aabb = mmi.custom_aabb
	_lejos.add_child(mmh)
	for i in N_HUMO:
		_humos.append({"vida": 0.0})
		_mm_humo.set_instance_color(i, Color(0, 0, 0, 0))
		_mm_humo.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0)))
	# Fuegos fijos en el suelo: granjas, planeadores, aviones caídos; y el pueblo ardiendo
	for i in 60:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(160.0, 1700.0)
		var pos := Vector3(cos(ang) * r, 2.0, -100.0 + sin(ang) * r)
		_luz_nueva(pos, Color(1.0, 0.45, 0.12), _rng.randf_range(16.0, 40.0) * (1.0 + r / 900.0), INF, Vector3.ZERO, "fuego")
	for i in 7:
		_luz_nueva(Vector3(_rng.randf_range(-30, 30), 6.0, -140.0 + _rng.randf_range(-25, 25)), Color(1.0, 0.5, 0.15),
			_rng.randf_range(10.0, 18.0), INF, Vector3.ZERO, "fuego")
	# Emisores de trazadoras (ametralladoras y antiaéreas en el suelo)
	for i in 26:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(100.0, 900.0)
		var color := Color(1.0, 0.35, 0.15) if _rng.randf() < 0.6 else Color(0.6, 1.0, 0.55)
		_emisores.append([Vector3(cos(ang) * r, 1.5, -100.0 + sin(ang) * r), _rng.randf_range(0.0, 2.0), color])
	# Reflectores alemanes
	for i in 3:
		var ang := _rng.randf_range(-2.6, -0.5)
		var r := _rng.randf_range(600.0, 1200.0)
		_reflector(Vector3(cos(ang) * r, 0, -100.0 + sin(ang) * r))
	# Paracaidistas alrededor (la textura se dibuja con código: tela + hombre)
	_tex_para = load("res://assets/salto/paracaidistas.png") if ResourceLoader.exists("res://assets/salto/paracaidistas.png") \
		else _textura_paracaidista()
	for i in 26:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(18.0, 320.0)
		var alto := desde.y + _rng.randf_range(-70.0, 50.0)
		_paracaidista(desde + Vector3(cos(ang) * r, alto - desde.y, sin(ang) * r), _rng.randf_range(-0.5, 0.0))
	# La formación de C-47 que sigue pasando y tu avión alcanzado
	for v in 3:
		for k in 3:
			var x := -60.0 + v * 70.0 + (k - 1) * 22.0
			var pos := Vector3(x * 0.7 + desde.x, 160.0 + v * 22.0 + absf(k - 1) * 6.0, desde.z + 140.0 + v * 420.0 + absf(k - 1) * 30.0)
			_avion(pos, Vector3(0, 0, -58.0))
	_mi_avion = _avion(desde + Vector3(6, 22, -18), Vector3(4, -2, -46), true)
	_mi_avion_vel = Vector3(4, -2, -46)


func _luz_nueva(pos: Vector3, color: Color, tam: float, vida: float, vel: Vector3, tipo: String) -> int:
	for i in N_LUCES:
		if _luces[i]["vida"] <= 0.0:
			_luces[i] = {"pos": pos, "color": color, "tam": tam, "vida": vida, "total": vida, "vel": vel, "tipo": tipo,
				"fase": _rng.randf() * 10.0}
			return i
	return -1


func _humo_nuevo(pos: Vector3, tam: float) -> void:
	for i in N_HUMO:
		if _humos[i]["vida"] <= 0.0:
			_humos[i] = {"pos": pos, "tam": tam, "vida": 5.0}
			return


func _actualizar_panorama(delta: float) -> void:
	if _lejos == null:
		return
	var yo := _p.global_position
	# --- Trazadoras desde el suelo (ráfagas hacia el cielo)
	for e in _emisores:
		e[1] -= delta
		if e[1] <= 0.0:
			e[1] = _rng.randf_range(0.5, 2.2)
			var blanco := Vector3(_rng.randf_range(-300, 300), _rng.randf_range(120, 280), _rng.randf_range(-400, 500))
			_rafaga(e[0], blanco, e[2], _rng.randi_range(10, 18))
	# --- Algunas pasan cerca tuyo (desde abajo, a pocos metros)
	_t_cerca -= delta
	if _t_cerca <= 0.0 and _abierto:
		_t_cerca = _rng.randf_range(1.8, 3.6)
		var ang := _rng.randf() * TAU
		var origen := Vector3(yo.x + cos(ang) * 90.0, 1.0, yo.z + sin(ang) * 90.0)
		var paso := yo + Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-3, 4), _rng.randf_range(-6, 6))
		_rafaga(origen, origen + (paso - origen) * 2.2, Color(1.0, 0.4, 0.15), 7)
		var tarda := origen.distance_to(paso) / 160.0
		get_tree().create_timer(tarda).timeout.connect(func() -> void:
			if is_instance_valid(self) and not _aterrizado:
				Game.play("bala_pasa", 2.0)
				_sacudida = maxf(_sacudida, 0.25))
	# --- Antiaérea estallando (más cerca de los aviones; a veces cerca tuyo)
	_t_flak -= delta
	if _t_flak <= 0.0:
		_t_flak = _rng.randf_range(0.12, 0.45)
		var p: Vector3
		if _rng.randf() < 0.18 and yo.y > 50.0:
			p = yo + Vector3(_rng.randf_range(-45, 45), _rng.randf_range(5, 40), _rng.randf_range(-45, 45))
		else:
			p = Vector3(_rng.randf_range(-350, 350), _rng.randf_range(130, 260), _rng.randf_range(-500, 300))
		_flak(p)
	# --- Artillería y explosiones en el suelo (fogonazos lejanos)
	_t_tierra -= delta
	if _t_tierra <= 0.0:
		_t_tierra = _rng.randf_range(0.3, 1.2)
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(250.0, 1800.0)
		_luz_nueva(Vector3(cos(ang) * r, 4.0, -100.0 + sin(ang) * r), Color(1.0, 0.75, 0.4), _rng.randf_range(25, 60), 0.35, Vector3.ZERO, "flash")
	# --- Bengalas lejanas que cuelgan sobre los potreros
	if _rng.randf() < delta * 0.6:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(150.0, 1000.0)
		_luz_nueva(Vector3(cos(ang) * r, _rng.randf_range(60, 110), -100.0 + sin(ang) * r), Color(1.0, 0.97, 0.85),
			_rng.randf_range(14, 22), 10.0, Vector3(0, -2.2, 0), "bengala")
	# --- Mover y dibujar las luces
	var tiempo := Time.get_ticks_msec() / 1000.0
	for i in N_LUCES:
		var l: Dictionary = _luces[i]
		if l["vida"] <= 0.0:
			continue
		l["vida"] -= delta
		if l["vida"] <= 0.0:
			_mm_luz.set_instance_color(i, Color(0, 0, 0, 0))
			continue
		l["pos"] += l["vel"] * delta
		var c: Color = l["color"]
		var tam: float = l["tam"]
		match l["tipo"]:
			"fuego":
				c = c * (0.75 + 0.25 * sin(tiempo * 7.0 + l["fase"]) * sin(tiempo * 3.1 + l["fase"] * 2.0))
			"traza":
				l["vel"].y -= 9.8 * delta * 0.4
			"flash":
				c.a = clampf(l["vida"] / l["total"], 0.0, 1.0)
			"bengala":
				c.a = clampf(l["vida"] / 1.5, 0.0, 1.0)
		# Lo muy lejano se ve más chico pero nunca desaparece del todo
		var d: float = yo.distance_to(l["pos"])
		var esc := maxf(tam, d * (0.016 if l["tipo"] != "traza" else 0.008))
		_mm_luz.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * esc), l["pos"]))
		_mm_luz.set_instance_color(i, c)
	for i in N_HUMO:
		var h: Dictionary = _humos[i]
		if h["vida"] <= 0.0:
			continue
		h["vida"] -= delta
		var a := clampf(h["vida"] / 5.0, 0.0, 1.0) * 0.5
		_mm_humo.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * h["tam"] * (1.6 - a)), h["pos"]))
		_mm_humo.set_instance_color(i, Color(0.06, 0.06, 0.07, a))
	# --- Paracaidistas
	for par in _paracaidistas:
		var s: Sprite3D = par[0]
		par[2] -= delta
		if par[2] > 0.0:          # todavía en caída libre
			s.position.y -= 22.0 * delta
			s.frame = 1
		else:
			s.frame = 0
			s.position.y -= par[1] * delta
			s.position += viento * delta
		if s.position.y < 1.0:
			s.visible = false
	if not _herido_hecho and _abierto and _t > 9.0:
		_herido()
	if not _bengala_hecha and _t > 7.0:
		_bengala_hecha = true
		var b := Bengala.disparar(get_parent(), Vector3(yo.x + 30, 1.5, yo.z - 60), Vector3(yo.x + 10, 0, yo.z - 30))
		b._arriba.y = 75.0
	# --- Aviones
	for av in _aviones:
		var n: Node3D = av[0]
		n.position += av[1] * delta
		if av[2] and n.position.z < yo.z + 60.0 and not n.get_meta("salto", false):
			n.set_meta("salto", true)        # sus paracaidistas saltan al pasar
			for k in 5:
				_paracaidista(n.position + Vector3(0, -2, 6 + k * 9), 0.9 + k * 0.25)
	_mover_mi_avion(delta)
	if _arma_cae:
		var v: Vector3 = _arma_cae.get_meta("vel")
		v.y -= 9.8 * delta
		_arma_cae.set_meta("vel", v)
		_arma_cae.position += v * delta
		_arma_cae.rotate_x(delta * 7.0)
		_arma_cae.rotate_z(delta * 4.0)
		if _arma_cae.position.y < -2.0:
			_arma_cae.queue_free()
			_arma_cae = null


func _rafaga(desde_p: Vector3, hacia: Vector3, color: Color, n: int) -> void:
	var dir := (hacia - desde_p).normalized()
	for k in n:
		var i := _luz_nueva(desde_p - dir * k * 9.0, color, 3.0, 3.4, dir * 150.0, "traza")
		if i < 0:
			return


func _flak(p: Vector3) -> void:
	_luz_nueva(p, Color(1.0, 0.8, 0.5), 42.0, 0.35, Vector3.ZERO, "flash")
	_luz_nueva(p, Color(1.0, 0.95, 0.85), 10.0, 0.12, Vector3.ZERO, "flash")
	_humo_nuevo(p, 14.0)
	var d := _p.global_position.distance_to(p)
	if d < 70.0:
		Game.play("explosion_cerca", -2.0 - d * 0.15, 1.2)
		_sacudida = maxf(_sacudida, 1.0 - d / 80.0)
	elif d < 400.0:
		var tarda := d / 340.0
		get_tree().create_timer(tarda).timeout.connect(func() -> void:
			if is_instance_valid(self) and not _aterrizado:
				Game.play("explosion_lejos", -6.0 - d * 0.02, 1.3))


## Un compañero alcanzado en el aire: las trazadoras se juntan sobre él.
func _herido() -> void:
	_herido_hecho = true
	var yo := _p.global_position
	var mejor: Array = []
	var md := 80.0
	for par in _paracaidistas:
		var s: Sprite3D = par[0]
		var d := s.position.distance_to(yo)
		if par[2] <= 0.0 and s.visible and d < md and d > 12.0:
			md = d
			mejor = par
	if mejor.is_empty():
		return
	var s: Sprite3D = mejor[0]
	for k in 3:
		var ang := _rng.randf() * TAU
		_rafaga(Vector3(s.position.x + cos(ang) * 70.0, 1.0, s.position.z + sin(ang) * 70.0), s.position + Vector3(0, 30, 0), Color(1.0, 0.4, 0.15), 8)
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if is_instance_valid(s) and not _aterrizado:
			Game.play("muerte", -2.0)
			s.modulate = s.modulate.darkened(0.3)
			mejor[1] = 7.5             # cae colgando, sin manejar
			Game.say("[¡LE DIERON A WALSH EN EL AIRE!]", Game.COLOR_BAD))


func _mover_mi_avion(delta: float) -> void:
	if _mi_avion == null or _choco:
		return
	# Se va de lado y a pique, con el motor izquierdo ardiendo
	_mi_avion_vel.y -= 2.6 * delta
	_mi_avion.position += _mi_avion_vel * delta
	_mi_avion.rotation.z = lerpf(_mi_avion.rotation.z, 0.75, delta * 0.3)
	_mi_avion.rotation.x = lerpf(_mi_avion.rotation.x, -0.35, delta * 0.2)
	if _rng.randf() < delta * 30.0:
		var fuego := _mi_avion.position + _mi_avion.global_basis * Vector3(-5.2, -0.4, -2.0)
		_luz_nueva(fuego, Color(1.0, 0.55, 0.15), _rng.randf_range(2.0, 4.0), 0.8, Vector3(0, 1.5, 8), "flash")
		_humo_nuevo(fuego + Vector3(0, 0, 4), 3.5)
	if _mi_avion.position.y < 3.0:
		_choco = true
		var p := _mi_avion.position
		_mi_avion.queue_free()
		_mi_avion = null
		_luz_nueva(p + Vector3(0, 10, 0), Color(1.0, 0.7, 0.35), 90.0, 1.2, Vector3.ZERO, "flash")
		_luz_nueva(p + Vector3(0, 4, 0), Color(1.0, 0.5, 0.15), 28.0, INF, Vector3.ZERO, "fuego")
		var d := _p.global_position.distance_to(p)
		get_tree().create_timer(d / 340.0).timeout.connect(func() -> void:
			if is_instance_valid(self):
				Game.play("explosion_lejos", 4.0, 0.7)
				_sacudida = maxf(_sacudida, 0.3))


# ---------------------------------------------------------------- piezas

## Un paracaidista colgado del arnés, sin vida (Walsh en el árbol; el del
## campanario). Devuelve el Sprite3D; meta "arriba": dónde terminan sus bandas
## (para atar los cordones). `pies`: posición local de los pies.
static func colgado(padre: Node3D, pies: Vector3) -> Sprite3D:
	var s := Sprite3D.new()
	var ruta := "res://assets/salto/colgado.png"
	if ResourceLoader.exists(ruta):
		s.texture = load(ruta)
	s.pixel_size = 0.024
	s.centered = false
	s.offset = Vector2(-s.texture.get_width() / 2.0 if s.texture else 0.0, 0)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.modulate = Noche.tinte.lerp(Color.WHITE, 0.45)
	s.position = pies
	padre.add_child(s)
	var alto := (s.texture.get_height() if s.texture else 100) * s.pixel_size
	s.set_meta("arriba", pies + Vector3(0, alto, 0))
	return s

## El suelo de varios km alrededor: un dibujo de potreros, setos y caminos (y
## el río Merderet, inundado, al oeste), visto de noche. Queda debajo del suelo
## de verdad (600 m): solo se ve más allá.
func _suelo_lejano() -> void:
	var n := 256
	var metros := 4800.0
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19440606
	var paso := 6        # píxeles por potrero (~110 m)
	var tonos := []
	for i in 64:
		tonos.append(Color(0.2, 0.26, 0.16).lerp(Color(0.32, 0.33, 0.2), rng.randf()).lerp(Color(0.16, 0.2, 0.15), rng.randf() * 0.5))
	for y in n:
		for x in n:
			var cx := x / paso
			var cy := y / paso
			var c: Color = tonos[(cx * 7 + cy * 13 + int(sin(cx * 1.7) * 5.0)) % 64]
			if x % paso == 0 or y % paso == 0:
				c = Color(0.08, 0.1, 0.07)         # setos
			img.set_pixel(x, y, c)
	# Caminos (la carretera de norte a sur y algunos cruzados)
	var col_camino := Color(0.42, 0.4, 0.34)
	for y in n:
		img.set_pixel(n / 2 + 0, y, col_camino)
	for k in 6:
		var y0 := rng.randi_range(10, n - 10)
		for x in n:
			img.set_pixel(x, clampi(y0 + int(sin(x * 0.05 + k) * 4.0), 0, n - 1), col_camino)
	# El Merderet inundado (lámina plateada al oeste)
	for y in n:
		var x0 := int(n * 0.3 + sin(y * 0.04) * 8.0)
		for x in range(x0 - 5, x0 + 5 + int(absf(sin(y * 0.02)) * 10.0)):
			if x >= 0 and x < n:
				img.set_pixel(x, y, Color(0.3, 0.34, 0.42))
	# Pueblos (manchas oscuras con techos)
	for pueblo in [Vector2(0.5, 0.5 - 140.0 / metros), Vector2(0.62, 0.3), Vector2(0.36, 0.72), Vector2(0.7, 0.68)]:
		var px := int(pueblo.x * n)
		var py := int(pueblo.y * n)
		for k in 30:
			var hx := px + rng.randi_range(-4, 4)
			var hy := py + rng.randi_range(-4, 4)
			if hx >= 0 and hx < n and hy >= 0 and hy < n:
				img.set_pixel(hx, hy, Color(0.13, 0.13, 0.14))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.62, 0.7, 0.92)
	var pl := PlaneMesh.new()
	pl.size = Vector2(metros, metros)
	var mi := MeshInstance3D.new()
	mi.mesh = pl
	mi.material_override = m
	mi.position = Vector3(0, -0.6, -100.0 + 140.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lejos.add_child(mi)


## Siluetas del pueblo (las casas de verdad solo se dibujan de cerca).
func _pueblo_lejano() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.22, 0.24)
	var techo := StandardMaterial3D.new()
	techo.albedo_color = Color(0.16, 0.17, 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 40:
		var p := Vector3(rng.randf_range(-60, 50), 0, -140.0 + rng.randf_range(-55, 50))
		if absf(p.x + 14.0) < 12.0 and absf(p.z + 140.0) < 18.0:
			continue          # la plaza y la iglesia
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(6, 10), 3.6, rng.randf_range(6, 9))
		var mi := MeshInstance3D.new()
		mi.mesh = b
		mi.material_override = m
		mi.position = p + Vector3(0, 1.8, 0)
		mi.visibility_range_begin = 70.0      # de cerca, el pueblo de verdad
		_lejos.add_child(mi)
		var pr := PrismMesh.new()
		pr.size = Vector3(b.size.x + 0.6, 2.4, b.size.z + 0.6)
		var mt := MeshInstance3D.new()
		mt.mesh = pr
		mt.material_override = techo
		mt.position = p + Vector3(0, 4.8, 0)
		mt.visibility_range_begin = 70.0
		_lejos.add_child(mt)


func _reflector(base: Vector3) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 28.0
	c.height = 900.0
	c.radial_segments = 10
	c.cap_top = false
	c.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_fog = true
	var g := Gradient.new()
	g.set_color(0, Color(0.7, 0.75, 0.85, 0.0))
	g.set_color(1, Color(0.8, 0.85, 0.95, 0.35))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	m.albedo_texture = gt
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	var pivote := Node3D.new()
	pivote.position = base
	_lejos.add_child(pivote)
	pivote.add_child(mi)
	mi.position = Vector3(0, 450, 0)
	pivote.rotation = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf() * TAU, _rng.randf_range(-0.5, 0.5))
	var tw := pivote.create_tween().set_loops()
	tw.tween_property(pivote, "rotation:x", _rng.randf_range(-0.6, -0.2), _rng.randf_range(4, 7)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(pivote, "rotation:x", _rng.randf_range(0.2, 0.6), _rng.randf_range(4, 7)).set_trans(Tween.TRANS_SINE)


func _paracaidista(pos: Vector3, abre_en: float) -> void:
	var s := Sprite3D.new()
	s.texture = _tex_para
	s.hframes = 2
	s.pixel_size = 0.14 if _tex_para.get_width() == 128 else 0.24
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = Noche.tinte.lerp(Color.WHITE, 0.45)
	s.shaded = false
	s.position = pos
	_lejos.add_child(s)
	_paracaidistas.append([s, _rng.randf_range(4.8, 6.2), abre_en])


## Paracaidista (32×48): la tela arriba, los cordones y el hombre colgando.
## Cuadro 2: el hombre solo, cayendo (antes de abrirse).
static func _textura_paracaidista() -> Texture2D:
	var img := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	var tela := Color(0.86, 0.85, 0.78)
	var sombra := Color(0.62, 0.62, 0.58)
	var hombre := Color(0.1, 0.11, 0.09)
	for y in 15:
		var ancho := int(sqrt(maxf(0.0, 1.0 - pow((14 - y) / 14.0, 2.0))) * 15.0)
		for x in range(16 - ancho, 16 + ancho):
			img.set_pixel(x, y + 2, tela if (x / 4) % 2 == 0 else sombra)
	for k in 5:
		var x0 := 2 + k * 7
		for t in 22:
			var x := int(lerpf(x0, 16, t / 22.0))
			img.set_pixel(clampi(x, 0, 31), 17 + t, Color(0.5, 0.5, 0.48, 0.8))
	for y in range(38, 47):
		for x in range(14, 18):
			img.set_pixel(x, y, hombre)
	img.set_pixel(15, 37, hombre)
	img.set_pixel(16, 37, hombre)
	# cuadro 2: cayendo (brazos y piernas abiertos)
	for y in range(20, 30):
		for x in range(46, 50):
			img.set_pixel(x, y, hombre)
	for k in 4:
		img.set_pixel(45 - k, 21 + k, hombre)
		img.set_pixel(50 + k, 21 + k, hombre)
		img.set_pixel(46 - k / 2, 30 + k, hombre)
		img.set_pixel(49 + k / 2, 30 + k, hombre)
	return ImageTexture.create_from_image(img)


## Un C-47 (forma simple de una pieza, oscura, con las luces azules de
## formación y el resplandor de los escapes). `ardiendo`: tu avión.
func _avion(pos: Vector3, vel: Vector3, ardiendo := false) -> Node3D:
	var n := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var piezas := []
	var fus := CylinderMesh.new()
	fus.top_radius = 0.9
	fus.bottom_radius = 1.25
	fus.height = 19.0
	fus.radial_segments = 8
	fus.rings = 1
	piezas.append([fus, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0, 0))])
	var ala := BoxMesh.new()
	ala.size = Vector3(29.0, 0.35, 3.4)
	piezas.append([ala, Transform3D(Basis(), Vector3(0, -0.5, -1.5))])
	var cola := BoxMesh.new()
	cola.size = Vector3(9.0, 0.25, 2.0)
	piezas.append([cola, Transform3D(Basis(), Vector3(0, 0.3, 8.6))])
	var deriva := BoxMesh.new()
	deriva.size = Vector3(0.25, 3.4, 2.6)
	piezas.append([deriva, Transform3D(Basis(), Vector3(0, 1.9, 8.6))])
	for lado in [-1.0, 1.0]:
		var mot := CylinderMesh.new()
		mot.top_radius = 0.7
		mot.bottom_radius = 0.6
		mot.height = 4.2
		mot.radial_segments = 8
		mot.rings = 1
		piezas.append([mot, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(5.2 * lado, -0.4, -3.4))])
	for par in piezas:
		st.append_from(par[0], 0, par[1])
	var mi := MeshInstance3D.new()
	if ResourceLoader.exists(C47):
		# El modelo de Meshy (la nariz mira a -X como los demás: se gira para mirar a -Z)
		if _c47 == null:
			_c47 = load(C47)
		mi.mesh = _c47
		var e := 29.0 / maxf(_c47.get_aabb().size.x, _c47.get_aabb().size.z)
		mi.scale = Vector3.ONE * e
		mi.rotation.y = -PI / 2.0
		mi.position.y = -_c47.get_aabb().size.y * e * 0.45
		var mm := Ambiente.material_modelo()
		mm.albedo_color = Color(1.25, 1.25, 1.3)       # la luna les da de lleno arriba
		mi.material_override = mm
	else:
		mi.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.44, 0.36)
		m.roughness = 0.6
		mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	# Luces azules de formación (arriba) y escapes
	var luz_mat := StandardMaterial3D.new()  # (luces del avión)
	luz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	luz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	luz_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	luz_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	luz_mat.albedo_texture = Bengala._textura_brillo()
	luz_mat.disable_fog = true
	for p in [[Vector3(0, 1.2, -4), Color(0.35, 0.55, 1.0), 2.6], [Vector3(-13, 0, -1.5), Color(0.35, 0.55, 1.0), 2.2],
			[Vector3(13, 0, -1.5), Color(0.35, 0.55, 1.0), 2.2], [Vector3(-5.2, -0.6, -1.0), Color(1.0, 0.5, 0.2), 3.2],
			[Vector3(5.2, -0.6, -1.0), Color(1.0, 0.5, 0.2), 3.2]]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(p[2], p[2])
		q.mesh = qm
		var lm: StandardMaterial3D = luz_mat.duplicate()
		lm.albedo_color = p[1]
		q.material_override = lm
		q.position = p[0]
		n.add_child(q)
	# Los motores (se oyen al pasar)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = _motores()
	snd.unit_size = 30.0
	snd.max_distance = 700.0
	snd.volume_db = 2.0
	snd.autoplay = true
	n.add_child(snd)
	n.position = pos
	n.rotation.y = atan2(-vel.x, -vel.z)
	_lejos.add_child(n)
	if not ardiendo:
		_aviones.append([n, vel, true])
	return n


# ---------------------------------------------------------------- sonidos

const C47 := "res://assets/decorado/c47.res"
static var _c47: Mesh
static var _snd_motores: AudioStreamWAV
static var _snd_viento: AudioStreamWAV


func _armar_sonidos() -> void:
	if _snd_viento == null:
		_snd_viento = _generar(3.0, func(t: float, lp: float) -> float:
			return lp * 1.6 * (0.75 + 0.25 * sin(TAU * 0.7 * t)), 0.08)
	_viento_snd = AudioStreamPlayer.new()
	_viento_snd.stream = _snd_viento
	# Si existe el ambiente grabado (ElevenLabs), se usa ese
	if ResourceLoader.exists("res://assets/sonidos/amb_salto.ogg"):
		var g: AudioStream = load("res://assets/sonidos/amb_salto.ogg")
		if g is AudioStreamOggVorbis:
			g.loop = true
		_viento_snd.stream = g
		_viento_snd.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_viento_snd.volume_db = -2.0
	_viento_snd.bus = "Master"
	add_child(_viento_snd)
	_viento_snd.play()


static func _motores() -> AudioStreamWAV:
	if _snd_motores == null:
		_snd_motores = _generar(2.0, func(t: float, lp: float) -> float:
			var f := 54.0
			var serr := fmod(t * f, 1.0) * 2.0 - 1.0
			var serr2 := fmod(t * f * 1.02, 1.0) * 2.0 - 1.0
			return (serr * 0.25 + serr2 * 0.2) * (0.8 + 0.2 * sin(TAU * 9.0 * t)) + lp * 0.5, 0.12)
	return _snd_motores


## Genera un sonido en bucle (`f(t, ruido_filtrado)`).
static func _generar(seg: float, f: Callable, brillo: float) -> AudioStreamWAV:
	var n := int(seg * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * brillo
		var v: float = f.call(t, lp)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w
