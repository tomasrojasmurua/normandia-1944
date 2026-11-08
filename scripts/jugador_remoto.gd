extends Node3D
class_name JugadorRemoto
## Otro jugador del cooperativo, visto en este celular: un soldado de sprites
## con su nombre encima. Se mueve entre las últimas posiciones recibidas por la
## red, con un pequeño atraso (Red.ATRASO) para que siempre haya dos entre las
## que interpolar: así se ve suave aunque lleguen solo 15 por segundo y con
## distintos retrasos.

var id := ""
var escuadra := 1             # su puesto (la escuadra que manda)
var arma := "garand"
var bando := 0                # versus: 0 = EE.UU., 1 = Alemania (fuera del versus, siempre 0)
var dead := false             # (para la IA alemana del anfitrión)
var cuerpo: SoldadoSprite
var _cartel: Label3D
var _fotos: Array = []        # [tiempo local de llegada, pos, giro, agachado, velocidad, muerto]
var _muerto := false
# Misión con salto: mientras baja en paracaídas se ve colgando de la tela, y al
# llegar al suelo los alemanes no lo vieron caer (gracia, como el jugador local)
var _salto := false
var _en_el_aire := false
var _para: Sprite3D


var _choque: StaticBody3D     # versus: el cuerpo donde pegan las balas (si es rival)
var _capsula: CapsuleShape3D
var _col_cabeza: CollisionShape3D


func _ready() -> void:
	# En el anfitrión, los alemanes también le disparan a los demás jugadores
	# (versus: va en el grupo de su bando)
	add_to_group(Versus.grupo(bando) if Versus.activo else "americanos")
	cuerpo = SoldadoSprite.new()
	cuerpo.bando = Versus.sprite(bando) if Versus.activo else "aliado"
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
	_salto = not Misiones.actual().get("salto", {}).is_empty()
	if Versus.activo and bando != Versus.mi_bando():
		_armar_choque()
		_cartel.visible = false     # al rival no se le ve el nombre (se vería a través de las paredes)


## Versus: un jugador del otro bando tiene cuerpo y cabeza donde pegan mis
## balas (capa 3, como los alemanes). El golpe va a su celular (Red.dano).
func _armar_choque() -> void:
	_choque = StaticBody3D.new()
	_choque.collision_layer = 4
	_choque.collision_mask = 0
	_choque.set_meta("remoto", self)
	var col := CollisionShape3D.new()
	_capsula = CapsuleShape3D.new()
	_capsula.radius = 0.32
	_capsula.height = 1.5
	col.shape = _capsula
	col.position.y = 0.75
	_choque.add_child(col)
	_col_cabeza = CollisionShape3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = 0.18
	_col_cabeza.shape = esfera
	_col_cabeza.position.y = 1.62
	_choque.add_child(_col_cabeza)
	add_child(_choque)


## Versus: la IA (del anfitrión) o mi bala le pegó: el daño va a su celular.
func hit(amount: float, headshot: bool, pos: Vector3, dir: Vector3, _por_jugador := true) -> void:
	if not dead:
		Red.dano(id, amount * (2.0 if headshot else 1.0), pos - dir * 10.0)


func recibir(d: Dictionary) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_fotos.append([t, Vector3(d["x"], d["y"], d["z"]), float(d["r"]), int(d.get("c", 0)) == 1,
		float(d.get("v", 0.0)), int(d.get("m", 0)) == 1])
	if _fotos.size() > 20:
		_fotos.pop_front()
	_cartel.text = str(d.get("n", ""))
	if _fotos.size() == 1:
		global_position = _fotos[0][1]


## Lo que pide la IA alemana (como a cualquier americano).
func pos_cabeza() -> Vector3:
	return cuerpo.pos_cabeza() if cuerpo else global_position + Vector3(0, 1.6, 0)


## Como en player.gd. La foto trae [.., agachado, velocidad en m/s, ..].
## (v0.40: antes cualquier paso de más de 0,6 m/s contaba como correr)
func factor_blanco() -> float:
	if _fotos.is_empty():
		return 1.0
	var f := 1.0
	var v := float(_fotos[-1][4])
	if bool(_fotos[-1][3]):
		f *= 0.6
	if v > 5.5:
		f *= 0.88      # corriendo
	elif v > 2.0:
		f *= 0.92      # caminando
	return f


func en_campo_abierto() -> bool:
	return not _fotos.is_empty() and not bool(_fotos[-1][3]) and float(_fotos[-1][4]) > 3.0


## Un alemán (de este celular, el anfitrión) le pegó: el daño va a su celular.
func take_damage(amount: float, from_pos: Vector3, _es_bala := true) -> void:
	if not dead:
		Red.dano(id, amount, from_pos)


func disparo() -> void:
	set_meta("disparo_t", Game.elapsed)    # de noche, el fogonazo lo delata (Noche.factor_vista)
	if cuerpo:
		cuerpo.disparo()


## Misión con salto: en el aire, el paracaídas; al aterrizar, la gracia.
func _paracaidas() -> void:
	var aire := global_position.y > 2.5
	if aire == _en_el_aire:
		return
	_en_el_aire = aire
	if aire:
		if _para == null:
			_para = Sprite3D.new()
			_para.texture = load("res://assets/salto/paracaidistas.png") if ResourceLoader.exists("res://assets/salto/paracaidistas.png") \
				else Salto._textura_paracaidista()
			_para.hframes = 2
			_para.pixel_size = 0.14 if _para.texture.get_width() == 128 else 0.24
			_para.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_para.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			_para.modulate = Noche.tinte.lerp(Color.WHITE, 0.45)
			_para.shaded = false
			_para.position = Vector3(0, 4.0, 0)
			add_child(_para)
		_para.visible = true
		cuerpo.visible = false
		remove_from_group("americanos")     # en el aire no le disparan (igual no lo pueden matar)
	else:
		if _para:
			_para.visible = false
		cuerpo.visible = true
		add_to_group("americanos")
		set_meta("gracia_hasta", Game.elapsed + 45.0)


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
	if _salto:
		_paracaidas()
	var muerto: bool = b[5]
	if muerto and not _muerto:
		cuerpo.morir(-global_basis.z, false)
		Versus.baja(bando)       # versus: el anfitrión cuenta la caída de los demás jugadores
		if _choque:
			_choque.collision_layer = 0
	elif not muerto and _muerto:
		# volvió como refuerzo: su cuerpo queda en la arena y aparece uno nuevo
		cuerpo.reparent(get_parent())
		_fotos = [_fotos[-1]]
		cuerpo = SoldadoSprite.new()
		cuerpo.bando = Versus.sprite(bando) if Versus.activo else "aliado"
		cuerpo.arma = arma
		add_child(cuerpo)
		if _choque:
			_choque.collision_layer = 4
	_muerto = muerto
	dead = muerto
	if not _muerto:
		var v: float = b[4]
		cuerpo.pose = "agachado" if b[3] else "pie"
		cuerpo.andar = "corre" if v > 0.6 else ""
		if _capsula:      # agachado se le pega menos
			var alto := 1.0 if b[3] else 1.5
			if absf(_capsula.height - alto) > 0.05:
				_capsula.height = alto
				_choque.get_child(0).position.y = alto / 2.0
				_col_cabeza.position.y = alto + 0.12

