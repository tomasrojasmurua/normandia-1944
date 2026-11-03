extends Combatiente
class_name Aliado
## Soldado americano con IA, de una de las cuatro escuadras (escuadras.gd).
## Obedece la orden de su escuadra (la 0 es la del jugador: `Aliado.orden`, la
## cambia el jugador desde el HUD; las otras las maneja su sargento):
## - "seguir":   se mantiene cerca de su jefe (el jugador o su sargento), en
##               una cobertura que lo tape.
## - "avanzar":  salta de cobertura en cobertura hacia los alemanes, esperando
##               unos segundos en cada una (avanzan escalonados, no todos juntos).
## - "mantener": se queda donde está (solo cambia si lo flanquean).
## Dispara de verdad a los alemanes que ve (sus balas matan) y puede morir.
## Las balas del jugador lo atraviesan (sin fuego amigo), las explosiones no.
## En el cooperativo, los otros jugadores ocuparán estos lugares.

@export var nombre := "HAYES"
@export var escuadra := 0          # 0 = la del jugador
@export var es_lider := false      # sargento con IA de una escuadra 1–3
var esp := ""                      # especialidad (hombres de tu compañía): "medico", "radio", "bazuca"...
var rango := 0                     # 0 PVT … 3 SGT: los veteranos tiran un poco mejor
var _t_bazuca := 12.0

const ALCANCE := 60.0
const BUNKER := Vector3(0, 0, -42)

static var orden := "seguir"      # orden de la escuadra del jugador

var max_health := 100.0
var _player: Player
var _vista_t := 0.0
var _pensar_t := 0.0
var _fuego_t := 0.0
var _rafaga := 0
var _rafaga_t := 0.0
var _asomado := 0.0
var _espera_hasta := 0.0
var _ultimo_dano := -100.0
var _indice := 0
var _alemanes: Array[Vector3] = []   # dónde están (para no meterse encima)


static func dar_orden(o: String) -> void:
	orden = o
	Game.say({"seguir": "[ESCUADRA: SÍGANME]", "avanzar": "[ESCUADRA: AVANCEN]",
		"mantener": "[ESCUADRA: MANTENGAN POSICIÓN]"}.get(o, ""), Game.COLOR_GOOD)
	if Red.es_invitado():   # mi escuadra la corre el anfitrión: que él la mande
		Red.evento(["o", o])
		return
	# Que reaccionen enseguida (cada uno un poco desfasado); solo los del jugador
	var i := 0
	for a in Engine.get_main_loop().get_nodes_in_group("aliados"):
		if a.escuadra != Escuadras.mi_escuadra:
			continue
		a._pensar_t = 0.2 + i * 0.35
		a._espera_hasta = 0.0
		i += 1


func _ready() -> void:
	add_to_group("americanos")
	add_to_group("aliados")
	collision_layer = 16         # capa 5: compañeros (las balas del jugador no los tocan)
	collision_mask = 1 | 64      # 64 = alambre de púas
	if arma == "":
		arma = "garand"
	_indice = get_tree().get_nodes_in_group("aliados").size()
	_vista_t = randf() * 0.35
	_pensar_t = randf_range(0.5, 1.5)
	_fuego_t = randf_range(1.0, 3.0)
	amenaza = Objetivos.rumbo(escuadra) if Objetivos.actual else BUNKER
	_crear_cuerpo("aliado")
	tomar_cobertura_inicial.call_deferred()


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	_seguir_pose()
	if Game.elapsed - _ultimo_dano > 8.0 and health < max_health:
		health = minf(health + 3.0 * delta, max_health)

	_vista_t -= delta
	if _vista_t <= 0.0:
		_vista_t = 0.35
		var antes := objetivo
		objetivo = elegir_objetivo("enemies", ALCANCE)
		amenaza = objetivo.global_position if objetivo else _enemigo_conocido()
		if objetivo and objetivo != antes and escuadra == Escuadras.mi_escuadra:
			_cantar(objetivo)

	if esp == "bazuca":
		_bazuca(delta)

	if moviendo:     # corre en _process (combatiente.gd), cuadro a cuadro
		_rafaga = 0
		return

	_pensar_t -= delta
	if _pensar_t <= 0.0:
		_pensar_t = randf_range(0.8, 1.2)
		_pensar()
		if moviendo:
			return

	if _rafaga > 0:
		_rafaga_t -= delta
		if _rafaga_t <= 0.0:
			_rafaga -= 1
			_rafaga_t = Armas.datos(arma)["interval"] * randf_range(1.1, 1.5)
			if objetivo and not objetivo.dead:
				_disparar()

	if objetivo:
		var to := objetivo.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), delta * 5.0)
		cuerpo.apuntar_a = objetivo.pos_cabeza() - Vector3(0, 0.3, 0)
		if not en_cobertura:
			cuerpo.pose = "pie"
		_fuego_t -= delta
		if en_cobertura and _fuego_t < 0.6 and _asomado <= 0.0:
			_asomado = 0.6 + randf_range(1.0, 2.0)
		if _fuego_t <= 0.0 and _rafaga == 0:
			var d := Armas.datos(arma)
			if d["auto"]:
				_rafaga = randi_range(3, 6)
				_fuego_t = randf_range(2.0, 3.5)
			else:
				_rafaga = 1
				_fuego_t = randf_range(1.3, 2.6)
			_rafaga_t = 0.3 if en_cobertura else 0.0
	elif not en_cobertura:
		cuerpo.pose = "reposo"
		cuerpo.apuntar_a = Vector3.ZERO

	if en_cobertura:
		_asomado -= delta
		cuerpo.pose = "rodilla" if _asomado > 0.0 or _rafaga > 0 else "agachado"


## Avisa dónde vio a un alemán que el jugador no está mirando:
## "[HAYES: ¡ALEMÁN A LA IZQUIERDA, 40 M!]". Uno cada 7 s como mucho, y no
## repite el mismo alemán antes de 20 s.
static var _ultimo_canto := -100.0
static var _cantados := {}


func _cantar(e: Node3D) -> void:
	if Game.elapsed - _ultimo_canto < 7.0 or _player == null or _player.dead:
		return
	var id := e.get_instance_id()
	if Game.elapsed - float(_cantados.get(id, -100.0)) < 20.0:
		return
	var a := e.global_position - _player.global_position
	var dist := Vector2(a.x, a.z).length()
	var adelante := -_player.global_basis.z
	var plano := Vector3(a.x, 0, a.z).normalized()
	var ang := rad_to_deg(adelante.angle_to(plano))
	if ang < 25.0 and dist < 30.0:
		return          # lo tiene enfrente y cerca: ya lo ve
	var donde := "ADELANTE"
	if ang > 120.0:
		donde = "ATRÁS"
	elif ang > 30.0:
		donde = "A LA DERECHA" if plano.dot(_player.global_basis.x) > 0.0 else "A LA IZQUIERDA"
	if a.y > 4.0:
		donde += ", ARRIBA"
	_ultimo_canto = Game.elapsed
	_cantados[id] = Game.elapsed
	var quien := "MG42" if e.arma == "mg42" else "ALEMÁN"
	Game.say("[%s: ¡%s %s, %d M!]" % [nombre, quien, donde, int(roundf(dist / 5.0) * 5.0)], Game.COLOR_INFO)


## Bazuca: cada tanto le dispara un cohete a una MG42 o a un grupo de alemanes
## que vea (no a uno suelto: los cohetes son pocos).
func _bazuca(delta: float) -> void:
	_t_bazuca -= delta
	if _t_bazuca > 0.0 or objetivo == null or not is_instance_valid(objetivo) or objetivo.dead or moviendo:
		return
	var dist := global_position.distance_to(objetivo.global_position)
	if dist < 12.0 or dist > 70.0:
		_t_bazuca = 1.0
		return
	var juntos := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(objetivo.global_position) < 5.0:
			juntos += 1
	if objetivo.arma != "mg42" and juntos < 2:
		_t_bazuca = 2.0
		return
	_t_bazuca = randf_range(18.0, 26.0)
	var desde: Vector3 = cuerpo.boca.global_position
	var blanco: Vector3 = objetivo.global_position + Vector3(randf_range(-1.2, 1.2), 0.8, randf_range(-1.2, 1.2))
	Cohete.lanzar(get_parent(), desde, (blanco - desde).normalized(), 220.0)
	Game.play_at("throw", desde, 0.0)
	if escuadra == Escuadras.mi_escuadra:
		Game.say("[%s: ¡BAZUCA!]" % nombre, Game.COLOR_INFO)


## Dónde está el alemán vivo más cercano (aunque no lo vea): la escuadra sabe
## más o menos dónde está la línea enemiga.
## Solo cuentan los que están por donde va la escuadra (cerca de su objetivo):
## un rezagado atrás no la hace volver. Sin ninguno, va hacia su objetivo.
func _enemigo_conocido() -> Vector3:
	var rumbo := Objetivos.rumbo(escuadra) if Objetivos.actual else BUNKER
	var mejor := rumbo
	var mejor_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(rumbo) > 45.0:
			continue
		var d := global_position.distance_to(e.global_position)
		if d < mejor_d:
			mejor_d = d
			mejor = e.global_position
	return mejor


# ================================================================ decidir

func _pensar() -> void:
	if not Navegacion.listo:
		return
	_alemanes.clear()
	for e in get_tree().get_nodes_in_group("enemies"):
		_alemanes.append(e.global_position)
	var flanqueado := not cobertura.is_empty() and Coberturas.protege(cobertura, amenaza) < 0.2
	var jefe: Node3D = Escuadras.lider_de(self)
	var o := Escuadras.orden_de(self)
	if o == "seguir" and jefe == null:
		o = "avanzar"      # su sargento cayó y todavía no asciende otro
	var sec := Escuadras.sector(escuadra)
	match o:
		"mantener":
			if flanqueado:
				_ir(_buscar(func(p: Dictionary, viaje: float) -> float:
					return -INF if viaje > 8.0 else -viaje))
		"seguir":
			var jugador := jefe.global_position
			var lejos := global_position.distance_to(jugador)
			if lejos > 10.0 or cobertura.is_empty() or flanqueado:
				if not _ir(_buscar(func(p: Dictionary, viaje: float) -> float:
						var dj := jugador.distance_to(p["pos"])
						if dj < 2.0 or dj > 9.0:
							return -INF
						return -dj * 0.3 - viaje * 0.1)) and lejos > 10.0:
					_ir_suelto(jefe)
		"avanzar":
			if Game.elapsed < _espera_hasta and not flanqueado:
				return
			var mio := global_position.distance_to(amenaza)
			var propio := escuadra != Escuadras.mi_escuadra   # las otras escuadras se quedan en su sector
			if not _ir(_buscar(func(p: Dictionary, viaje: float) -> float:
					var avance := mio - amenaza.distance_to(p["pos"])
					if viaje < 2.5 or viaje > 14.0 or avance < 2.5:
						return -INF
					var fuera := 0.0
					if propio:
						var px: float = p["pos"].x
						fuera = maxf(sec.x - px, 0.0) + maxf(px - sec.y, 0.0)
					return avance * 0.4 - viaje * 0.15 - fuera * 0.6)):
				_espera_hasta = Game.elapsed + 3.0   # no hay dónde: espera y vuelve a mirar
				if propio and mio > 16.0 and randf() < 0.5:
					_avance_suelto(sec)   # sin coberturas cerca: corre unos metros al descubierto


## Mejor cobertura que lo tape de la amenaza; `extra(p, viaje)` agrega su criterio.
func _buscar(extra: Callable) -> Dictionary:
	var yo := global_position
	return Coberturas.mejor(self, func(p: Dictionary) -> float:
		var pos: Vector3 = p["pos"]
		if not Coberturas.alcanzable(yo, pos):
			return -INF
		var prot := Coberturas.protege(p, amenaza)
		if prot < 0.35:
			return -INF
		for a in _alemanes:
			if a.distance_to(pos) < 11.0:
				return -INF      # demasiado cerca de un alemán
		var e: float = extra.call(p, yo.distance_to(pos))
		return e + prot * 2.0, yo, 26.0)


func _ir(p: Dictionary) -> bool:
	if p.is_empty() or p == cobertura:
		return false
	return ir_a(p)


## Sin coberturas cerca: va a un lado de su jefe, aunque quede al descubierto.
func _ir_suelto(jefe: Node3D) -> void:
	var lado := jefe.global_basis.x * (-3.0 + 3.0 * (_indice % 3)) + jefe.global_basis.z * 2.5
	ir_a({"pos": Navegacion.cerca_de(jefe.global_position + lado)})


## Avanza unos metros hacia los alemanes dentro de su sector, aunque no haya
## dónde cubrirse (en la playa abierta no siempre hay un erizo cerca).
func _avance_suelto(sec: Vector2) -> void:
	var dir := amenaza - global_position
	dir.y = 0.0
	var meta := global_position + dir.normalized() * randf_range(6.0, 10.0)
	meta.x = clampf(meta.x, sec.x, sec.y)
	ir_a({"pos": Navegacion.cerca_de(meta)})


func _al_llegar() -> void:
	_espera_hasta = Game.elapsed + randf_range(4.0, 8.0)
	_fuego_t = minf(_fuego_t, randf_range(0.5, 1.5))


# ================================================================ disparar y recibir

func _disparar() -> void:
	var auto: bool = Armas.datos(arma)["auto"]
	var dist := global_position.distance_to(objetivo.global_position)
	var chance := lerpf(0.13, 0.025, clampf(dist / ALCANCE, 0.0, 1.0))
	if auto:
		chance *= 0.45
	chance *= 1.0 + 0.1 * rango
	chance *= objetivo.factor_blanco()
	if tiro_ia(objetivo, chance, -6.0):
		var pecho: Vector3 = objetivo.global_position + Vector3(0, 1.1, 0)
		var dir: Vector3 = (pecho - cuerpo.boca.global_position).normalized()
		objetivo.hit(Armas.datos(arma)["damage"], randf() < 0.1, pecho, dir, false)


func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	health -= amount
	_ultimo_dano = Game.elapsed
	var dir := (global_position - from_pos).normalized()
	cuerpo.impacto(dir)
	Game.blood(global_position + Vector3(0, 1.1, 0))
	if health <= 0.0:
		_morir(dir)


func _morir(dir: Vector3) -> void:
	dead = true
	moviendo = false
	_rafaga = 0
	Coberturas.liberar(self)
	remove_from_group("americanos")
	remove_from_group("aliados")
	collision_layer = 0
	collision_mask = 0
	if escuadra == Escuadras.mi_escuadra:    # de las otras no se avisa (serían demasiados)
		Game.say("[%s CAÍDO]" % nombre, Game.COLOR_BAD)
	cuerpo.andar = ""
	cuerpo.morir(dir, false)
	_soltar_arma(dir)
	Game.caidos += 1
	Red.murio(self, dir, false)
	if has_meta("compania"):
		Compania.caido(nombre)
