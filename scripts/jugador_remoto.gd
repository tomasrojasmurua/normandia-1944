extends Node3D
class_name JugadorRemoto
## Otro jugador del cooperativo, visto en este celular: un soldado de sprites
## con su nombre encima. Se mueve entre las últimas posiciones recibidas por la
## red, con un pequeño atraso (Red.ATRASO) para que siempre haya dos entre las
## que interpolar: así se ve suave aunque lleguen solo 15 por segundo y con
## distintos retrasos.

var arma := "garand"
var cuerpo: SoldadoSprite
var _cartel: Label3D
var _fotos: Array = []        # [tiempo local de llegada, pos, giro, agachado, velocidad, muerto]
var _muerto := false


func _ready() -> void:
	cuerpo = SoldadoSprite.new()
	cuerpo.bando = "aliado"
	cuerpo.arma = arma
	add_child(cuerpo)
	_cartel = Label3D.new()
	_cartel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cartel.font = Estilo.FUENTE
	_cartel.font_size = 22
	_cartel.pixel_size = 0.012
	_cartel.modulate = Estilo.AMBAR_CLARO
	_cartel.outline_size = 4
	_cartel.no_depth_test = true
	_cartel.fixed_size = false
	_cartel.position = Vector3(0, 2.15, 0)
	add_child(_cartel)


func recibir(d: Dictionary) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_fotos.append([t, Vector3(d["x"], d["y"], d["z"]), float(d["r"]), int(d.get("c", 0)) == 1,
		float(d.get("v", 0.0)), int(d.get("m", 0)) == 1])
	if _fotos.size() > 20:
		_fotos.pop_front()
	_cartel.text = str(d.get("n", ""))
	if _fotos.size() == 1:
		global_position = _fotos[0][1]


func disparo() -> void:
	if cuerpo:
		cuerpo.disparo()


func _process(_delta: float) -> void:
	if _fotos.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - Red.ATRASO
	# Buscar las dos fotos que rodean el instante t
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
	var muerto: bool = b[5]
	if muerto and not _muerto:
		cuerpo.morir(-global_basis.z, false)
	elif not muerto and _muerto:
		# tomó el lugar de otro compañero: cuerpo nuevo
		cuerpo.queue_free()
		cuerpo = SoldadoSprite.new()
		cuerpo.bando = "aliado"
		cuerpo.arma = arma
		add_child(cuerpo)
	_muerto = muerto
	if not _muerto:
		var v: float = b[4]
		cuerpo.pose = "agachado" if b[3] else "pie"
		cuerpo.andar = "corre" if v > 0.6 else ""
