extends Node3D
class_name ArmaSuelta
## Un arma tirada en el suelo (la que bota un enemigo al morir, la que dejas
## al recoger otra, o una dentro de una caja de suministros).
## - Si ya llevas esa misma arma, al pasar encima tomas sus balas.
## - Si no, al acercarte aparece "RECOGER" (tecla E o botón TOMAR).

@export var arma := "kar98k"
@export var mag := -1        # -1 = cargador lleno
@export var reserve := -1    # -1 = la reserva normal del arma

const DISTANCIA := 1.8

var _player: Player


## Deja un arma en el suelo, en "pos".
static func soltar(escena: Node, pos: Vector3, arma_id: String, balas: int, res: int) -> ArmaSuelta:
	var a := ArmaSuelta.new()
	a.arma = arma_id
	a.mag = balas
	a.reserve = res
	escena.add_child(a)
	a.global_position = pos
	a.rotation.y = randf() * TAU
	return a


func _ready() -> void:
	add_to_group("armas_sueltas")
	var d := Armas.datos(arma)
	if mag < 0:
		mag = d["mag"]
	if reserve < 0:
		reserve = d["reserve"]
	_build(d)


func nombre() -> String:
	return Armas.datos(arma)["name"]


var _espera := 0


func _process(_delta: float) -> void:
	if _espera > 0:     # lejos del jugador: se revisa cada tanto, no en cada cuadro
		_espera -= 1
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	if _player.dead:
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist > 6.0:
		_espera = mini(int(dist / 3.0), 30)
		if _player.pickup_near == self:
			_player.pickup_near = null
		return
	var w := _player.weapons
	if arma in w.slots:
		# Misma arma: tomar las balas al pasar encima
		if dist < 1.2:
			var i := w.slots.find(arma)
			var total := mag + reserve
			if total > 0:
				w.reserve[i] += total
				Game.say("[+%d BALAS %s]" % [total, nombre()], Game.COLOR_GOOD)
				Game.play("reload", -8.0)
			queue_free()
		return
	# Arma distinta: ofrecerla si es la más cercana
	if dist < DISTANCIA:
		var actual := _player.pickup_near as ArmaSuelta
		if actual == null or not is_instance_valid(actual) or actual == self \
				or dist < actual.global_position.distance_to(_player.global_position):
			_player.pickup_near = self
	elif _player.pickup_near == self:
		_player.pickup_near = null


## El jugador la recoge: la que llevaba en esa ranura queda en el suelo.
func tomar(p: Player) -> void:
	var vieja := p.weapons.equip(arma, mag, reserve)
	Game.say("[RECOGISTE %s]" % nombre(), Game.COLOR_GOOD)
	Game.play("reload", -4.0, 1.2)
	var frente := -p.global_basis.z
	if vieja["id"] != "nada":          # la ranura vacía (arma perdida en el salto) no se deja en el suelo
		ArmaSuelta.soltar(get_parent(), p.global_position + frente * 1.4 + Vector3(0, 0.05, 0),
			vieja["id"], vieja["mag"], vieja["reserve"])
	p.pickup_near = null
	queue_free()


## Modelo 3D del arma, acostado de lado en el suelo.
func _build(_d: Dictionary) -> void:
	var mi := Armas.modelo_3d(arma)
	mi.visibility_range_end = 45.0     # de más lejos no se distingue (y es una llamada de dibujo menos)
	add_child(mi)
	var aabb := mi.mesh.get_aabb()
	mi.rotation.z = PI / 2.0                 # de lado: el grosor queda hacia arriba
	mi.position = Vector3(0, aabb.size.x / 2.0 + 0.01, 0) - Vector3(0, 0, aabb.get_center().z)
