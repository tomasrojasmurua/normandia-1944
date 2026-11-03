extends RigidBody3D
class_name Grenade
## Granada de mano Mk 2 ("piña"). Rebota y explota cuando se acaba la mecha.

@export var fuse := 4.0
@export var radius := 7.0
@export var damage := 170.0

var _bounces := 0
var solo_vista := false      # cooperativo: copia de una granada del anfitrión (la explosión llega por la red)


func _init() -> void:
	collision_layer = 8          # capa 4: granadas
	collision_mask = 1 | 4       # rebota en el escenario y en enemigos
	mass = 0.6
	continuous_cd = true
	angular_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.9
	physics_material_override = pm

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.06
	shape.shape = sphere
	add_child(shape)

	var olive := Game.material(Color(0.27, 0.31, 0.18))
	var steel := Game.material(Color(0.4, 0.4, 0.38))
	Game.box(self, Vector3(0.075, 0.1, 0.075), Vector3.ZERO, olive)
	Game.box(self, Vector3(0.085, 0.07, 0.085), Vector3.ZERO, olive, Vector3(0, 45, 0))
	Game.box(self, Vector3(0.025, 0.03, 0.025), Vector3(0, 0.06, 0), steel)      # espoleta
	Game.box(self, Vector3(0.012, 0.09, 0.02), Vector3(0.035, 0.03, 0), steel)   # palanca

	body_entered.connect(_on_bounce)


## Cambia el aspecto a granada de palo alemana (Stielhandgranate 24):
## mango de madera con la cabeza de lata. Mecha un poco más larga.
func modelo_aleman() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.queue_free()
	fuse = 4.5
	var lata := Game.material(Color(0.3, 0.33, 0.29))
	var madera := Game.material(Color(0.55, 0.38, 0.2))
	Game.box(self, Vector3(0.07, 0.1, 0.07), Vector3(0, 0.09, 0), lata)
	Game.box(self, Vector3(0.075, 0.08, 0.075), Vector3(0, 0.09, 0), lata, Vector3(0, 45, 0))
	Game.box(self, Vector3(0.028, 0.28, 0.028), Vector3(0, -0.09, 0), madera)
	Game.box(self, Vector3(0.034, 0.02, 0.034), Vector3(0, -0.23, 0), lata)


func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		if solo_vista:
			queue_free()
			return
		Game.explode(global_position + Vector3(0, 0.15, 0), radius, damage)
		queue_free()


func _on_bounce(_body: Node) -> void:
	if _bounces < 4 and linear_velocity.length() > 1.5:
		_bounces += 1
		Game.play_at("bounce", global_position, -4.0)
