extends StaticBody3D
class_name AlemanRemoto
## Un alemán (o un compañero americano, si bando = "aliado") visto en el
## celular de un INVITADO del cooperativo: un "títere".
## El alemán de verdad vive en el anfitrión; este solo lo imita (posición,
## giro, pose), moviéndose suave entre las posiciones que llegan 10 veces por
## segundo. Tiene formas de choque como los alemanes (capa 3: cuerpo y
## cabeza) para que las balas le peguen; el golpe se manda al anfitrión.
## Está en el grupo "enemies" para que las granadas propias le hagan daño
## (Game.explode llama a hit) y para la ayuda de puntería táctil.

var rid := 0
var bando := "aleman"
var arma := "kar98k"
var dead := false
# Solo los compañeros (para el HUD de la escuadra del invitado):
var nombre := ""
var escuadra := -1
var puesto := -1
var health := 100.0
var max_health := 100.0
var companero := false            # de una escuadra (lista "b" del anfitrión), no un alemán de la defensa
var rival := true                 # versus: es del otro bando que mi jugador (le pegan mis balas)
var moviendo := false
var cuerpo: SoldadoSprite
var ultimo := 0.0                 # cuándo llegó la última posición (tiempo local)
var _fotos: Array = []            # [tiempo local, pos, giro]
var _capsula: CapsuleShape3D
var _col_cuerpo: CollisionShape3D
var _col_cabeza: CollisionShape3D


func _ready() -> void:
	cuerpo = SoldadoSprite.new()
	cuerpo.bando = bando
	cuerpo.arma = arma
	add_child(cuerpo)
	collision_mask = 0
	if Versus.activo:
		# Versus: en el grupo de su bando (para las granadas); los de mi bando
		# no tienen choque (mis balas los atraviesan), los rivales sí
		add_to_group(Versus.grupo(Versus.bando_de_sprite(bando)))
		if companero and not rival:
			add_to_group("aliados_remotos")
		if not rival:
			collision_layer = 0
			return
	elif bando == "aliado":   # las balas del jugador atraviesan a los compañeros
		collision_layer = 0
		add_to_group("aliados_remotos")
		return
	else:
		add_to_group("enemies")
	collision_layer = 4
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
	moviendo = andar != ""


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
	Game.blood(pos, dir)
	cuerpo.impacto(dir)
	Red.golpe(rid, amount, headshot, pos, dir)


func morir(dir: Vector3, cabeza: bool) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	remove_from_group("enemies")
	remove_from_group("americanos")
	collision_layer = 0
	cuerpo.andar = ""
	cuerpo.morir(dir, cabeza)
	Game.cuerpo_caido(self)    # (antes los cuerpos se juntaban sin límite en los invitados)
	_soltar_arma(dir)


## (v0.40) Su arma queda en el suelo también en este celular (antes solo en el
## anfitrión: los invitados no veían armas que recoger y se quedaban sin balas).
## Cada celular tiene su copia: lo que recoge uno no se le quita a otro.
func _soltar_arma(dir: Vector3) -> void:
	if not Armas.DATOS.has(arma):
		return
	var d := Armas.datos(arma)
	var lado := global_basis.x * randf_range(-0.6, 0.6) + dir.normalized() * 0.5
	ArmaSuelta.soltar(get_parent(), global_position + Vector3(lado.x, 0.05, lado.z), arma,
		randi_range(int(d["mag"]) / 2, int(d["mag"])), int(d["mag"]))


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
	if _capsula == null:
		return
	# La cabeza sigue a la pose (agachado no se le puede pegar igual)
	var alto: float = {"reposo": 1.48, "pie": 1.48, "rodilla": 1.12, "agachado": 0.8}.get(cuerpo.pose, 1.48)
	if absf(_capsula.height - alto) > 0.02:
		_capsula.height = alto
		_col_cuerpo.position.y = alto / 2.0
	var cabeza: Vector3 = to_local(cuerpo.pos_cabeza())
	if cabeza.distance_squared_to(_col_cabeza.position) > 0.03 * 0.03:
		_col_cabeza.position = cabeza
