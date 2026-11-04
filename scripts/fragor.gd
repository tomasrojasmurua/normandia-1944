extends Node
class_name Fragor
## El "director de sonido" de la misión (sección 6): sin música, pero con la
## batalla sonando alrededor todo el tiempo.
## - Base continua: batalla lejana de la playa o del campo (según dónde ande
##   la cámara), en bucle, con un fundido al cambiar.
## - Encima, cada pocos segundos (más seguido si hay alemanes cerca): MG42 y
##   explosiones lejanas, gritos de "¡Médico!" y de heridos detrás, órdenes
##   alemanas desde donde están los alemanes.
## - Reacciones (las llaman otros guiones): alemán herido, muertes, granadas,
##   balas que pegan en la arena junto al jugador.
## Los sonidos son de ElevenLabs (assets/sonidos/, ver Game.ARCHIVOS).

const BASE_DB := -4.0
const VOZ_CADA := 2.5          # segundos mínimos entre dos voces

static var actual: Fragor

var _playa: AudioStreamPlayer
var _campo: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _t_evento := 4.0
var _t_voz := 0.0
var _t_muerte := 0.0
var _inicio := 6.0             # el grito de "¡vienen por la playa!" al empezar


func _ready() -> void:
	actual = self
	_rng.randomize()
	_playa = _base("amb_playa_batalla")
	_campo = _base("amb_campo_batalla")
	# Viene de la cinemática: retoma la playa donde iba, sin corte
	var pu: AudioStreamPlayer = Game.puente
	if pu and pu.playing and _playa.stream:
		_playa.play(pu.get_playback_position())
		_playa.volume_db = pu.volume_db
		pu.stop()


func _exit_tree() -> void:
	if actual == self:
		actual = null


func _base(nombre: String) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = Game.pista(nombre, true)
	a.volume_db = -60.0
	add_child(a)
	if a.stream:
		a.play(_rng.randf() * 15.0)
	return a


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Base: playa abajo, campo arriba (en la meseta)
	var arriba := cam.global_position.y > 8.0
	_playa.volume_db = move_toward(_playa.volume_db, -60.0 if arriba else BASE_DB, delta * 20.0)
	_campo.volume_db = move_toward(_campo.volume_db, BASE_DB if arriba else -60.0, delta * 20.0)
	_t_voz -= delta
	_t_muerte -= delta
	if _inicio > 0.0:
		_inicio -= delta
		if _inicio <= 0.0 and Objetivos.fase() == 0:
			var e := _aleman_cerca(cam.global_position, 20.0, 90.0)
			if e:
				voz("grito_aleman_3", e.global_position + Vector3(0, 1.6, 0), 4.0)
	_t_evento -= delta
	if _t_evento <= 0.0:
		var cerca := _alemanes_a(cam.global_position, 45.0)
		_t_evento = _rng.randf_range(2.5, 5.0) if cerca > 2 else _rng.randf_range(4.0, 9.0)
		_evento(cam)


## Algo que pasa en la batalla, alrededor del jugador.
func _evento(cam: Camera3D) -> void:
	var yo := cam.global_position
	var r := _rng.randf()
	if r < 0.3:
		Game.play_at("mg42_lejos", _alrededor(yo, 60.0, 110.0), _rng.randf_range(-2.0, 4.0))
	elif r < 0.55:
		Game.play_at("explosion_lejos", _alrededor(yo, 70.0, 130.0), 4.0)
	elif r < 0.8:
		# Americanos heridos detrás o a los costados (no adelante, donde están los alemanes)
		var p := yo + Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(8, 35))
		voz("grito_medico" if _rng.randf() < 0.55 else "grito_herido", p, -2.0)
	else:
		var e := _aleman_cerca(yo, 25.0, 80.0)
		if e:
			voz("grito_aleman_1", e.global_position + Vector3(0, 1.6, 0), 0.0)


## Una voz en un lugar, sin pisar a otra (si hay una sonando, se descarta).
func voz(nombre: String, pos: Vector3, db := 0.0, forzar := false) -> void:
	if _t_voz > 0.0 and not forzar:
		return
	_t_voz = VOZ_CADA
	Game.play_at(nombre, pos, db)


# ================================================================ reacciones

## Un alemán recibió un tiro y sigue vivo.
static func aleman_herido(pos: Vector3) -> void:
	if actual and randf() < 0.3:
		actual.voz("grito_aleman_4", pos + Vector3(0, 1.4, 0), 2.0)


## Cayó un soldado (de cualquier bando). Los americanos a veces piden médico.
static func muerte(pos: Vector3, americano: bool) -> void:
	if actual == null or actual._t_muerte > 0.0:
		return
	var cam := actual.get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(pos) > 50.0 or randf() > 0.6:
		return
	actual._t_muerte = 1.2
	Game.play_at("muerte", pos + Vector3(0, 1.0, 0), 0.0)
	if americano and randf() < 0.5:
		actual.get_tree().create_timer(1.6).timeout.connect(func() -> void:
			if actual:
				actual.voz("grito_medico", pos + Vector3(randf_range(-6, 6), 1.5, randf_range(2, 8)), 0.0))


## Una granada del jugador cayó cerca de alemanes: "¡Granada! ¡Todos abajo!"
static func granada(pos: Vector3) -> void:
	if actual == null:
		return
	var e := actual._aleman_cerca(pos, 0.0, 12.0)
	if e:
		actual.voz("grito_aleman_2", e.global_position + Vector3(0, 1.6, 0), 4.0, true)


## Una bala pasó cerca del jugador: a veces pega en la arena a su lado.
static func casi(pos: Vector3) -> void:
	if actual and randf() < 0.35 and pos.y < 8.0:
		var lado := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		Game.play_at("impacto_arena", pos + lado, -2.0)


# ================================================================ utilidades

func _alrededor(yo: Vector3, d0: float, d1: float) -> Vector3:
	var ang := _rng.randf() * TAU
	return yo + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(d0, d1)


func _alemanes_a(yo: Vector3, radio: float) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(yo) < radio:
			n += 1
	return n


func _aleman_cerca(yo: Vector3, d0: float, d1: float) -> Node3D:
	var lista: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = e.global_position.distance_to(yo)
		if d >= d0 and d <= d1:
			lista.append(e)
	return lista[_rng.randi() % lista.size()] if not lista.is_empty() else null
