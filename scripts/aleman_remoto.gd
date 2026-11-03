extends StaticBody3D
class_name AlemanRemoto
## Un alemán visto en el celular de un INVITADO del cooperativo: un "títere".
## El alemán de verdad vive en el anfitrión; este solo lo imita (posición,
## giro, pose), moviéndose suave entre las posiciones que llegan 10 veces por
## segundo. Tiene formas de choque como los alemanes (capa 3: cuerpo y
## cabeza) para que las balas le peguen; el golpe se manda al anfitrión.
## Está en el grupo "enemies" para que las granadas propias le hagan daño
## (Game.explode llama a hit) y para la ayuda de puntería táctil.

var rid := 0
var arma := "kar98k"
var dead := false
var cuerpo: SoldadoSprite
var ultimo := 0.0                 # cuándo llegó la última posición (tiempo local)
var _fotos: Array = []            # [tiempo local, pos, giro]
var _capsula: CapsuleShape3D
var _col_cuerpo: CollisionShape3D
var _col_cabeza: CollisionShape3D


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 0
	cuerpo = SoldadoSprite.new()
	cuerpo.bando = "aleman"
	cuerpo.arma = arma
	add_child(cuerpo)
	# Forma 0 = cuerpo, forma 1 = cabeza (como en combatiente.gd)
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


func recibir(t: float, pos: Vector3, giro: float, pose: String, andar: String) -> void:
	ultimo = t
	if dead:
		return
	_fotos.append([t, pos, giro])
	if _fotos.size() > 12:
		_fotos.pop_front()
	if _fotos.size() == 1:
		global_position = pos
		rotation.y = giro
	cuerpo.pose = pose
	cuerpo.andar = andar


func pos_cabeza() -> Vector3:
	return cuerpo.pos_cabeza()


func factor_blanco() -> float:
	return 1.0


func disparo() -> void:
	if cuerpo and not dead:
		cuerpo.disparo()


## Le pegó una bala o una explosión de este celular.
func hit(amount: float, headshot: bool, pos: Vector3, dir: Vector3, _por_jugador := true) -> void:
	if dead:
		return
	Game.blood(pos)
	cuerpo.impacto(dir)
	Red.golpe(rid, amount, headshot, pos, dir)


func morir(dir: Vector3, cabeza: bool) -> void:
	if dead:
		return
	dead = true
	remove_from_group("enemies")
	collision_layer = 0
	cuerpo.andar = ""
	cuerpo.morir(dir, cabeza)


func _process(_delta: float) -> void:
	if dead or _fotos.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - Red.ATRASO
	var a: Array = _fotos[0]
	var b: Array = _fotos[0]
	for i in _fotos.size():
		if _fotos[i][0] <= t:
			a = _fotos[i]
			b = _fotos[mini(i + 1, _fotos.size() - 1)]
	var f := 0.0
	if b[0] > a[0]:
		f = clampf((t - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	global_position = (a[1] as Vector3).lerp(b[1], f)
	rotation.y = lerp_angle(a[2], b[2], f)
	# La cabeza sigue a la pose (agachado no se le puede pegar igual)
	var alto: float = {"reposo": 1.48, "pie": 1.48, "rodilla": 1.12, "agachado": 0.8}.get(cuerpo.pose, 1.48)
	if absf(_capsula.height - alto) > 0.02:
		_capsula.height = alto
		_col_cuerpo.position.y = alto / 2.0
	var cabeza: Vector3 = to_local(cuerpo.pos_cabeza())
	if cabeza.distance_squared_to(_col_cabeza.position) > 0.03 * 0.03:
		_col_cabeza.position = cabeza
