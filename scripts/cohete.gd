extends Node3D
class_name Cohete
## Cohete de la bazuca M1: vuela recto (cae un poco), deja humo y explota al chocar.

const VELOCIDAD := 55.0
var _dir := Vector3.FORWARD
var _vel := Vector3.ZERO
var _damage := 220.0
var _vida := 4.0
var _humo := 0.0


static func lanzar(escena: Node, desde: Vector3, dir: Vector3, damage: float) -> void:
	var c := Cohete.new()
	c._dir = dir
	c._vel = dir * VELOCIDAD
	c._damage = damage
	escena.add_child(c)
	c.global_position = desde
	c.look_at(desde + dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)


func _ready() -> void:
	var cuerpo := Game.material(Color(0.33, 0.36, 0.25))
	Game.box(self, Vector3(0.06, 0.06, 0.32), Vector3.ZERO, cuerpo)
	Game.box(self, Vector3(0.1, 0.1, 0.04), Vector3(0, 0, 0.16), cuerpo)   # aletas
	var fuego := StandardMaterial3D.new()
	fuego.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fuego.albedo_color = Color(1.0, 0.75, 0.3)
	Game.box(self, Vector3(0.05, 0.05, 0.12), Vector3(0, 0, 0.24), fuego)
	Game.play("throw", 0.0, 0.5)


func _physics_process(delta: float) -> void:
	_vida -= delta
	_vel.y -= 2.0 * delta
	var desde := global_position
	var hasta := desde + _vel * delta
	var q := PhysicsRayQueryParameters3D.create(desde, hasta, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() or _vida <= 0.0:
		var p: Vector3 = hit["position"] if not hit.is_empty() else hasta
		Game.explode(p, 5.0, _damage)
		queue_free()
		return
	global_position = hasta
	look_at(hasta + _vel, Vector3.UP if absf(_vel.normalized().y) < 0.98 else Vector3.RIGHT)
	_humo -= delta
	if _humo <= 0.0 and _vida < 3.85:   # sin humo pegado a la cara al disparar
		_humo = 0.05
		Game._burst(desde, Color(0.55, 0.55, 0.52), 1, 0.3, 0.6, 0.07, Vector3.UP, -0.05)
