extends Node3D
class_name Aliado
## Compañero americano en la playa (decorado con vida): se cubre de rodillas
## detrás de un obstáculo, se asoma y dispara hacia el búnker. Sus balas son
## solo trazadoras (no hacen daño) y las del jugador lo atraviesan.
## Más adelante, en el cooperativo, los otros jugadores usarán este mismo cuerpo.

@export var arma := "garand"
@export var objetivo := Vector3(0, 2.0, -40)

var cuerpo: Soldado
var _t := 0.0
var _rafaga := 0


func _ready() -> void:
	cuerpo = Soldado.new()
	cuerpo.bando = "aliado"
	cuerpo.arma = arma
	add_child(cuerpo)
	cuerpo.pose = "agachado"
	_t = randf_range(1.0, 4.0)
	var to := objetivo - global_position
	rotation.y = atan2(-to.x, -to.z)


func _process(delta: float) -> void:
	_t -= delta
	cuerpo.apuntar_a = objetivo
	if cuerpo.pose == "agachado":
		if _t <= 0.0:
			cuerpo.pose = "rodilla"
			_t = 0.8
			_rafaga = 6 if Armas.datos(arma)["auto"] else randi_range(1, 3)
	elif _t <= 0.0:
		if _rafaga > 0:
			_rafaga -= 1
			var desde := cuerpo.boca.global_position
			var blanco := objetivo + Vector3(randf_range(-6, 6), randf_range(-1.5, 1.5), 0)
			Game.tracer(desde, blanco, Color(1.0, 0.8, 0.45))
			Game.play_at("rifle_far", desde, -6.0)
			cuerpo.disparo()
			_t = Armas.datos(arma)["interval"] * (1.3 if Armas.datos(arma)["auto"] else randf_range(3.0, 6.0))
		else:
			cuerpo.pose = "agachado"
			_t = randf_range(2.5, 5.0)
