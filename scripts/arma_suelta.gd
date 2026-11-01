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


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	if _player.dead:
		return
	var dist := global_position.distance_to(_player.global_position)
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
	ArmaSuelta.soltar(get_parent(), p.global_position + frente * 1.4 + Vector3(0, 0.05, 0),
		vieja["id"], vieja["mag"], vieja["reserve"])
	p.pickup_near = null
	queue_free()


## Modelo simple tirado en el suelo, según el tipo de arma.
func _build(d: Dictionary) -> void:
	var madera := Game.material(Color(0.42, 0.26, 0.14))
	var metal := Game.material(Color(0.2, 0.2, 0.21))
	var oliva := Game.material(Color(0.33, 0.36, 0.25))
	var tipo: String = d["tipo"]
	var con_madera: bool = arma in ["garand", "carbine", "thompson", "bar", "springfield", "kar98k", "stg44"]
	var y := 0.04
	match tipo:
		"pistola":
			Game.box(self, Vector3(0.2, 0.03, 0.03), Vector3(0, y, 0), metal)
			Game.box(self, Vector3(0.04, 0.03, 0.11), Vector3(-0.07, y, 0.05), madera, Vector3(0, -15, 0))
		"bazuca":
			Game.box(self, Vector3(1.4, 0.09, 0.09), Vector3(0, 0.05, 0), oliva)
			Game.box(self, Vector3(0.05, 0.1, 0.04), Vector3(-0.1, 0.05, 0.08), madera)
		_:
			var largo := 1.1 if tipo == "fusil" else (0.8 if tipo == "subfusil" else 1.2)
			Game.box(self, Vector3(largo * 0.6, 0.05, 0.05), Vector3(largo * 0.1, y, 0), madera if con_madera else metal)
			Game.box(self, Vector3(largo * 0.3, 0.025, 0.025), Vector3(largo * 0.55, y, 0), metal)
			Game.box(self, Vector3(largo * 0.3, 0.08, 0.05), Vector3(-largo * 0.32, y + 0.01, 0), madera if con_madera else metal)
			if tipo != "fusil":
				Game.box(self, Vector3(0.04, 0.03, 0.16), Vector3(0.0, y, 0.09), metal)
