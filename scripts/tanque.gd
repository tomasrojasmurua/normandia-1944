extends Node3D
class_name Tanque
## Tanque alemán del contraataque (misión 2, fase 4): baja por la carretera,
## se detiene frente a la barricada y cañonea a los americanos que ve (un
## cañonazo cada 7–10 s: se oye el disparo y hay un instante para tirarse).
## Lo frena la bazuca: aguanta dos cohetes (o una carga). Al destruirlo queda
## ardiendo en la carretera.
## Lo crea MapaPlaneador en quien maneja la IA. Sus explosiones pasan por
## Game.explode (se ven y dañan en todos los celulares).

const VEL := 2.4
const VIDA := 2
const ALCANCE := 90.0

static var actual: Tanque


static func crear(escena: Node, ruta: Array) -> Tanque:
	var t := Tanque.new()
	t._ruta = ruta
	escena.add_child(t)
	t.global_position = ruta[0]
	return t


var dead := false
var _ruta: Array = []
var _i := 1
var _vida := VIDA
var _modelo: MeshInstance3D
var _cuerpo: AnimatableBody3D
var _t_tiro := 6.0
var _t_mg := 3.0
var _rafaga := 0
var _t_rafaga := 0.0
var _blanco: Node3D
# Cooperativo: en los invitados el tanque es un títere que sigue al del
# anfitrión (posición y si ya lo destruyeron); los golpes se los manda a él.
var titere := false
var _meta_pos := Vector3.ZERO
var _meta_giro := 0.0


func _ready() -> void:
	actual = self
	add_to_group("tanques")
	var mesh: Mesh = load("res://assets/decorado/panzer.res")
	var a := mesh.get_aabb()
	var e := 6.6 / maxf(a.size.x, a.size.z)
	_modelo = MeshInstance3D.new()
	_modelo.mesh = mesh
	_modelo.material_override = Ambiente.material_modelo()
	_modelo.scale = Vector3.ONE * e
	_modelo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_modelo)
	# Choque: para la gente, las balas, la vista y los cohetes (capa 1 y la de la forma)
	_cuerpo = AnimatableBody3D.new()
	_cuerpo.collision_layer = 1 | Ambiente.CAPA_FORMA
	_cuerpo.collision_mask = 0
	var col := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = a.size * e * Vector3(0.95, 0.9, 0.95)
	col.shape = forma
	col.position = Vector3(0, forma.size.y / 2.0, 0)
	_cuerpo.add_child(col)
	add_child(_cuerpo)
	Game.play_at("explosion_lejos", global_position, 4.0)


## El punto al que se le apunta (para la IA de la bazuca).
func _exit_tree() -> void:
	if actual == self:
		actual = null


## Títere (invitado): dónde está el del anfitrión.
func recibir(pos: Vector3, giro: float, destruido: bool) -> void:
	if _meta_pos == Vector3.ZERO:
		global_position = pos
	_meta_pos = pos
	_meta_giro = giro
	if destruido and not dead:
		_destruido()


func centro() -> Vector3:
	return global_position + Vector3(0, 1.3, 0)


func _process(delta: float) -> void:
	if dead:
		return
	if titere:
		var d0 := _meta_pos - global_position
		if d0.length() > 0.05:
			global_position = global_position.lerp(_meta_pos, minf(delta * 6.0, 1.0))
			if randf() < delta * 2.0:
				Game._burst(global_position + Vector3(0, 0.4, 0) + global_basis.x * 3.0, Color(0.3, 0.3, 0.3), 1, 0.5, 1.2, 0.2, Vector3.UP, -0.1)
		rotation.y = lerp_angle(rotation.y, _meta_giro, minf(delta * 6.0, 1.0))
		return
	# Avanza por la ruta
	if _i < _ruta.size():
		var meta: Vector3 = _ruta[_i]
		var d := meta - global_position
		d.y = 0.0
		if d.length() < 0.3:
			_i += 1
		else:
			var dir := d.normalized()
			global_position += dir * minf(VEL * delta, d.length())
			# El cañón del modelo apunta a -X: girarlo hacia donde va
			rotation.y = lerp_angle(rotation.y, atan2(dir.z, -dir.x), delta * 2.0)
			if randf() < delta * 2.0:
				Game._burst(global_position + Vector3(0, 0.4, 0) - dir * 3.0, Color(0.3, 0.3, 0.3), 1, 0.5, 1.2, 0.2, Vector3.UP, -0.1)
	if not Objetivos.manda():
		return
	# Busca a quién tirarle (el que tenga más cerca y vea)
	_t_tiro -= delta
	_t_mg -= delta
	if _t_tiro <= 0.0:
		_t_tiro = randf_range(7.0, 10.0)
		_blanco = _elegir()
		if _blanco:
			_canonazo(_blanco)
	if _rafaga > 0:
		_t_rafaga -= delta
		if _t_rafaga <= 0.0:
			_t_rafaga = 0.09
			_rafaga -= 1
			_tiro_mg()
	elif _t_mg <= 0.0:
		_t_mg = randf_range(4.0, 7.0)
		_blanco = _elegir()
		if _blanco:
			_rafaga = randi_range(6, 10)


func _elegir() -> Node3D:
	var yo := centro()
	var mejor: Node3D = null
	var mejor_d := ALCANCE
	for b in get_tree().get_nodes_in_group("americanos"):
		if b.dead:
			continue
		var d: float = yo.distance_to(b.global_position)
		if d < mejor_d * Noche.factor_vista(b) + 10.0 and _libre(yo, b.global_position + Vector3(0, 1.2, 0)):
			mejor = b
			mejor_d = d
	return mejor


func _libre(desde: Vector3, hasta: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(desde, hasta, 1 | 128 | 512)
	q.exclude = [_cuerpo.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _canonazo(b: Node3D) -> void:
	var boca := centro() + (b.global_position - global_position).normalized() * 3.5
	Game.play_at("explosion_cerca", boca, 2.0)
	Game.fogonazo(boca, true)
	Red.tiro_tanque(boca, boca, true)
	Game._burst(boca, Color(0.4, 0.38, 0.35), 8, 2.0, 1.2, 0.3, Vector3.UP, -0.1)
	if b is Player and b.global_position.distance_to(global_position) < 60.0:
		b.shake(0.6)
	var donde: Vector3 = b.global_position + Vector3(randf_range(-3.5, 3.5), 0.2, randf_range(-3.5, 3.5))
	await get_tree().create_timer(0.35).timeout
	if is_inside_tree():
		Game.explode(Navegacion.cerca_de(donde) + Vector3(0, 0.2, 0), 5.5, 170.0)


func _tiro_mg() -> void:
	if _blanco == null or not is_instance_valid(_blanco) or _blanco.dead:
		_rafaga = 0
		return
	var desde := centro() + Vector3(0, 0.3, 0)
	var hasta: Vector3 = _blanco.global_position + Vector3(randf_range(-2, 2), randf_range(0.2, 1.8), randf_range(-2, 2))
	Game.tracer(desde, hasta)
	Game.play_at("rifle_far", desde, 0.0)
	Red.tiro_tanque(desde, hasta, false)
	if randf() < (0.06 if _blanco is Player else 0.12):
		if _blanco is Player:
			_blanco.take_damage(70.0, desde)
		elif _blanco.has_method("take_damage"):
			_blanco.take_damage(100.0, desde)


## Lo alcanzó una explosión (cohete de bazuca, carga, granada) con este daño.
func danar(dano: float) -> void:
	if dead:
		return
	if titere:          # en un invitado: el golpe lo decide el anfitrión
		Red.golpe_tanque(dano)
		return
	if dano < 150.0:
		Red.anunciar("[LA GRANADA NO LE HACE NADA AL TANQUE]", Game.COLOR_INFO)
		return
	_vida -= 2 if dano >= 350.0 else 1
	if _vida > 0:
		Red.anunciar("[¡LE DIMOS AL TANQUE! ¡OTRA VEZ!]", Game.COLOR_GOOD)
		return
	Red.anunciar("[¡TANQUE DESTRUIDO!]", Game.COLOR_GOOD)
	Game.bajas += 4
	_destruido()


## Queda ardiendo en la carretera (también el títere de los invitados).
func _destruido() -> void:
	dead = true
	remove_from_group("tanques")
	var m := Ambiente.material_modelo()
	m.albedo_color = Color(0.25, 0.23, 0.22)
	_modelo.material_override = m
	_modelo.rotation_degrees.z = 3.0
	Fuego.encender(get_parent(), global_position + Vector3(0, 1.0, 0), 1.2)
	Game.play_at("explosion_cerca", centro(), 8.0)
