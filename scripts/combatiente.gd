extends CharacterBody3D
class_name Combatiente
## Base común de los soldados con IA (alemanes en enemy.gd, compañeros en
## aliado.gd): vida, formas de choque, correr por la playa siguiendo una ruta,
## usar coberturas, mirar si se ve a alguien y dispararle.
## Aquí y en sus hijos se DECIDE; soldado.gd solo MUESTRA (en el cooperativo,
## solo el anfitrión ejecutará estas decisiones).

@export var health := 100.0
@export var arma := ""

const VEL_CORRER := 5.2
const VEL_TROTE := 3.4
const GRAVEDAD := 9.8

var dead := false
var cuerpo    # SoldadoSprite (o Soldado, el 3D, si se elige en la pausa)
var cobertura: Dictionary = {}    # punto de cobertura donde está (o vacío)
var en_cobertura := false          # está detrás de algo bajo: se agacha y se asoma
var moviendo := false
var objetivo: Node3D = null        # a quién le dispara ahora
var amenaza := Vector3.ZERO        # dónde vio al enemigo por última vez

var _ruta := PackedVector3Array()
var _ruta_i := 0
var _destino: Dictionary = {}
var _vel := VEL_CORRER
var _atasco := 0.0
var _ultima_pos := Vector3.ZERO
var _capsula: CapsuleShape3D
var _col_cuerpo: CollisionShape3D
var _col_cabeza: CollisionShape3D


func _crear_cuerpo(bando: String) -> void:
	cuerpo = Soldado.new() if Game.soldados_3d else SoldadoSprite.new()
	cuerpo.bando = bando
	cuerpo.arma = arma
	add_child(cuerpo)
	# Forma 0 = cuerpo, forma 1 = cabeza (tiro a la cabeza). Siguen a la pose.
	_col_cuerpo = CollisionShape3D.new()
	_capsula = CapsuleShape3D.new()
	_capsula.radius = 0.3
	_capsula.height = 1.48
	_col_cuerpo.shape = _capsula
	_col_cuerpo.position.y = 0.74
	add_child(_col_cuerpo)
	_col_cabeza = CollisionShape3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = 0.17
	_col_cabeza.shape = esfera
	_col_cabeza.position.y = 1.64
	add_child(_col_cabeza)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(42.0)


## Las formas de choque siguen al cuerpo (agachado no se le puede pegar igual).
## Cambiar una forma de choque obliga al motor de física a rehacerla, así que
## solo se tocan cuando la pose cambió de verdad (antes: en cada paso).
func _seguir_pose() -> void:
	var alto: float = {"reposo": 1.48, "pie": 1.48, "rodilla": 1.12, "agachado": 0.8}[cuerpo.pose]
	if absf(_capsula.height - alto) > 0.02:
		_capsula.height = lerpf(_capsula.height, alto, 0.15)
		_col_cuerpo.position.y = _capsula.height / 2.0
	var cabeza: Vector3 = to_local(cuerpo.pos_cabeza())
	if cabeza.distance_squared_to(_col_cabeza.position) > 0.03 * 0.03:
		_col_cabeza.position = cabeza


## Altura de los ojos según la pose (para mirar por encima de los sacos).
func ojos() -> Vector3:
	var h := 1.6
	if en_cobertura and not moviendo:
		h = 1.15
	return global_position + Vector3(0, h, 0)


func pos_cabeza() -> Vector3:
	return cuerpo.pos_cabeza()


## ¿Hay línea de vista limpia (solo cuenta el escenario) entre dos puntos?
func linea_libre(desde: Vector3, hasta: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(desde, hasta, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## ¿Veo a este blanco (cabeza o pecho)?
func veo(blanco: Node3D, alcance: float) -> bool:
	if blanco == null or not is_instance_valid(blanco) or blanco.dead:
		return false
	var cabeza: Vector3 = blanco.pos_cabeza()
	var ojo := ojos()
	if ojo.distance_squared_to(cabeza) > alcance * alcance:
		return false
	return linea_libre(ojo, cabeza) or linea_libre(ojo, cabeza - Vector3(0, 0.45, 0))


## Al más cercano que veo de un grupo ("americanos" o "enemies").
## `preferido` cuenta como más cerca (el jugador atrae más fuego).
func elegir_objetivo(grupo: String, alcance: float, preferido: Node = null, excluir: Node = null) -> Node3D:
	var mejor: Node3D = null
	var mejor_d := INF
	for n in get_tree().get_nodes_in_group(grupo):
		var b := n as Node3D
		if b == null or b.dead or b == excluir:
			continue
		var d := global_position.distance_to(b.global_position)
		if b == preferido:
			d *= 0.75
		if b == objetivo:
			d *= 0.85      # no cambia de blanco a cada rato
		if d < mejor_d and d < alcance and veo(b, alcance):
			mejor_d = d
			mejor = b
	return mejor


# ================================================================ moverse

## Correr hasta un punto de cobertura (o a un lugar suelto si `p` no tiene "n").
func ir_a(p: Dictionary, correr := true) -> bool:
	var hasta: Vector3 = p["pos"]
	var r := Navegacion.ruta(global_position, hasta)
	if r.size() == 0:
		return false
	if r[r.size() - 1].distance_to(hasta) > 1.5:
		return false        # no se llega (otra isla del mapa, como el techo del búnker)
	if p.has("n"):
		Coberturas.ocupar(p, self)
	else:
		Coberturas.liberar(self)
	cobertura = {}
	en_cobertura = false
	_destino = p
	_ruta = r
	_ruta_i = 1 if r.size() > 1 else 0
	_vel = VEL_CORRER if correr else VEL_TROTE
	moviendo = true
	_atasco = 0.0
	_ultima_pos = global_position
	cuerpo.pose = "pie"
	cuerpo.andar = "corre" if correr else "camina"
	cuerpo.apuntar_a = Vector3.ZERO
	return true


## El desplazamiento va en _process (una vez por cada cuadro dibujado) y no
## en _physics_process: así el soldado avanza parejo aunque el celular dibuje
## a un ritmo distinto de la física (si no, se ve a tirones).
func _process(delta: float) -> void:
	if moviendo and not dead:
		_mover(delta)


func _mover(delta: float) -> void:
	if _ruta_i >= _ruta.size():
		_llegar()
		return
	var meta := _ruta[_ruta_i]
	var d := meta - global_position
	d.y = 0.0
	if d.length() < 0.3:
		_ruta_i += 1
		return
	var v := d.normalized() * _vel
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVEDAD * delta
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(delta * 10.0, 1.0))
	# Atascado (otro soldado, una esquina): se rinde y vuelve a pensar
	_atasco += delta
	if _atasco > 1.0:
		if global_position.distance_to(_ultima_pos) < 0.4:
			_detener()
		_atasco = 0.0
		_ultima_pos = global_position


func _llegar() -> void:
	var p := _destino
	_detener()
	if p.has("n"):
		cobertura = p
		en_cobertura = p["bajo"]
		# Mira por encima del obstáculo, hacia donde protege
		var n: Vector3 = p["n"]
		rotation.y = atan2(-n.x, -n.z)
	_al_llegar()


func _detener() -> void:
	moviendo = false
	velocity = Vector3.ZERO
	_ruta = PackedVector3Array()
	cuerpo.andar = ""
	cuerpo.pose = "agachado" if en_cobertura else "pie"


## Para los hijos: qué hacer al llegar a destino.
func _al_llegar() -> void:
	pass


## Toma la cobertura donde está parado al empezar (si hay una a menos de 2 m).
func tomar_cobertura_inicial() -> void:
	var p := Coberturas.cercano(self, global_position, 2.0)
	if not p.is_empty():
		Coberturas.ocupar(p, self)
		cobertura = p
		en_cobertura = p["bajo"]
		var n: Vector3 = p["n"]
		rotation.y = atan2(-n.x, -n.z)
	cuerpo.pose = "agachado" if en_cobertura else "reposo"


# ================================================================ disparar

## Tiro de un soldado de IA a `blanco`: acierta o no según `prob`.
## Dibuja la trazadora y el polvo; devuelve true si acertó.
func tiro_ia(blanco: Node3D, prob: float, sonido_db: float) -> bool:
	var d := Armas.datos(arma)
	var from: Vector3 = cuerpo.boca.global_position
	var target: Vector3 = blanco.pos_cabeza() - Vector3(0, 0.35, 0)
	var dist := from.distance_to(target)
	var acierta := randf() < prob
	if not acierta:   # pasa cerca y pega en otra parte
		var side := (target - from).cross(Vector3.UP).normalized()
		target += side * randf_range(-1.6, 1.6) + Vector3(0, randf_range(-0.9, 0.6), 0)
	var dir := (target - from).normalized()
	var end := from + dir * (dist + (0.0 if acierta else 30.0))
	if not acierta and self is Enemy:
		# ¿pasó cerca del jugador? (supresión)
		var p := get_tree().get_first_node_in_group("player") as Player
		if p:
			var cab := p.pos_cabeza()
			var u := clampf((cab - from).dot(dir), 0.0, dist + 30.0)
			var cerca := (from + dir * u).distance_to(cab)
			if cerca < 2.5:
				p.casi(cerca)
	if not acierta:
		var q := PhysicsRayQueryParameters3D.create(from, end, 1)
		var w := get_world_3d().direct_space_state.intersect_ray(q)
		if not w.is_empty():
			end = w["position"]
			Game.dust(end, w["normal"])
	var sonido := "pistol" if arma in ["mp40", "luger", "thompson", "colt"] else "rifle_far"
	Game.play_at(sonido, from, sonido_db if not d["auto"] else sonido_db - 2.0)
	if self is Aliado:
		Game.tracer(from, end, Color(1.0, 0.8, 0.45))
	else:
		Game.tracer(from, end)
	cuerpo.disparo()
	return acierta


## Factor que reduce las chances de pegarle a este soldado (para los que le disparan).
func factor_blanco() -> float:
	var f := 1.0
	if moviendo:
		f *= 0.7
	elif cuerpo.pose == "rodilla":
		f *= 0.6      # asomado sobre los sacos: solo se ve la cabeza y los hombros
	if not cobertura.is_empty() and cobertura["parcial"]:
		f *= 0.6
	return f


func _soltar_arma(dir: Vector3) -> void:
	var d := Armas.datos(arma)
	var lado := global_basis.x * randf_range(-0.6, 0.6) + dir.normalized() * 0.5
	ArmaSuelta.soltar(get_parent(), global_position + Vector3(lado.x, 0.05, lado.z), arma,
		randi_range(int(d["mag"]) / 2, int(d["mag"])), int(d["mag"]))


func _exit_tree() -> void:
	Coberturas.liberar(self)
