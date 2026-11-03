extends Node
class_name Objetivos
## Los objetivos del desembarco (sección 5, paso 4): uno por escuadra, en su
## sector de la playa. La misión se cumple cuando están los cuatro.
##   0 (centro, escuadra del jugador / MURPHY): VOLAR EL BÚNKER — un jugador
##     se queda 5 s junto al búnker poniendo la carga; explota 6 s después.
##   1 (izquierda, KOWALSKI): CALLAR LA MG42 IZQUIERDA — matar al tirador y
##     tomar el nido (americanos junto a la ametralladora 4 s). Si nadie llega
##     en 20 s, otro alemán toma la MG42.
##   2 (derecha, REYES):      CALLAR LA MG42 DERECHA.
##   3 (centro izq., COLE):   TOMAR LA TRINCHERA — sin alemanes cerca y con
##     americanos dentro durante 8 s (sirven los compañeros con IA).
## Fracaso: todos los jugadores caídos y sin nadie que los releve (ni
## compañeros vivos ni refuerzos en su escuadra).
## Lo decide quien tiene la IA (jugando solo, o el anfitrión); los invitados
## reciben el estado por la red y solo lo muestran.

## Los objetivos vienen de los datos de la misión (Misiones: "objetivos").
static var LISTA: Array = []
const SEG_CARGA := 5.0     # por defecto, si la misión no dice "seg"
const SEG_TOMAR := 8.0

static var hecho := [false, false, false, false]
static var progreso := [0.0, 0.0, 0.0, 0.0]
static var terminado := 0          # 0 = en curso, 1 = cumplida, -1 = fracasada
static var actual: Objetivos

var _marcas: Array = []
var _pos: Array = []
var _t_fracaso := 2.0
var _sin_tirador := [-1.0, -1.0, -1.0, -1.0]   # desde cuándo la MG42 no tiene tirador
var _mecha := -1.0                               # carga del búnker puesta: segundos que faltan


func _ready() -> void:
	actual = self
	LISTA = Misiones.dato("objetivos")
	hecho = [false, false, false, false]
	progreso = [0.0, 0.0, 0.0, 0.0]
	terminado = 0
	for o in LISTA:
		_pos.append(o["pos"])
		var m := Label3D.new()
		m.text = "[ %s ]" % o["corto"]
		m.font = Estilo.FUENTE
		m.font_size = 22
		m.pixel_size = 0.0022
		m.fixed_size = true
		m.no_depth_test = true
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.outline_size = 4
		add_child(m)
		m.global_position = o["pos"] + Vector3(0, 3.0, 0)
		_marcas.append(m)


## ¿Este celular decide (IA local)? Los invitados solo muestran.
static func manda() -> bool:
	return not Red.es_invitado()


static func mio() -> int:
	return clampi(Escuadras.mi_escuadra, 0, 3)


## El objetivo en que debe estar una escuadra: el suyo si falta; si ya lo
## cumplió, el pendiente más cercano al suyo (va a apoyar a los demás).
## -1 si no queda ninguno.
static func foco(esc: int) -> int:
	esc = clampi(esc, 0, 3)
	if LISTA.size() < 4:
		return esc
	if not hecho[esc]:
		return esc
	var mejor := -1
	var mejor_d := INF
	for i in 4:
		if not hecho[i]:
			var d: float = LISTA[esc]["pos"].distance_to(LISTA[i]["pos"])
			if d < mejor_d:
				mejor_d = d
				mejor = i
	return mejor


static func foco_mio() -> int:
	return foco(mio())


static func cumplidos() -> int:
	return hecho.count(true)


func _process(delta: float) -> void:
	for i in 4:
		var m: Label3D = _marcas[i]
		m.visible = not hecho[i] and terminado == 0
		m.modulate = Estilo.AMBAR_CLARO if i == foco_mio() else Color(Estilo.CREMA, 0.45)
	if not manda() or terminado != 0 or not Navegacion.listo:
		return
	for i in 4:
		if hecho[i]:
			continue
		match LISTA[i]["tipo"]:
			"mg":
				var d := Defensa.actual
				var k: int = LISTA[i]["i"]
				if d == null or d.nidos.size() <= k:
					continue
				var n = d.nidos[k]
				if n != null and is_instance_valid(n) and not n.dead:
					_sin_tirador[i] = -1.0
					progreso[i] = 0.0
					continue
				if _sin_tirador[i] < 0.0:
					_sin_tirador[i] = Game.elapsed
					Red.anunciar("[%s SIN TIRADOR: ¡TOMEN EL NIDO!]" % ("MG42 IZQUIERDA" if k == 0 else "MG42 DERECHA"),
						Game.COLOR_GOOD)
				_tomar(i, delta, 4.0, 6.0)
				if progreso[i] >= 1.0:
					_cumplir(i)
				elif Game.elapsed - _sin_tirador[i] > 20.0 and progreso[i] < 0.05:
					d.reponer_nido(k)
					_sin_tirador[i] = -1.0
					Red.anunciar("[OTRO ALEMÁN TOMA LA MG42]", Game.COLOR_BAD)
			"carga":
				if _mecha >= 0.0:   # carga puesta: explota sola, hay que alejarse
					_mecha -= delta
					if _mecha < 0.0:
						Game.explode(_pos[i] + Vector3(0, 0.6, -1.5), 9.0, 400.0)
						_cumplir(i)
					continue
				var cerca := false
				for j in _jugadores():
					if j.global_position.distance_to(_pos[i]) < 2.6:
						cerca = true
				if cerca:
					progreso[i] += delta / float(LISTA[i].get("seg", SEG_CARGA))
				else:
					progreso[i] = maxf(progreso[i] - delta * 0.1, 0.0)
				if progreso[i] >= 1.0:
					progreso[i] = 0.999
					_mecha = 6.0
					Red.anunciar("[CARGA PUESTA: ¡ALÉJENSE DEL BÚNKER!]", Game.COLOR_BAD)
			"tomar":
				_tomar(i, delta, float(LISTA[i].get("seg", SEG_TOMAR)), 6.0)
				if progreso[i] >= 1.0:
					_cumplir(i)
	_t_fracaso -= delta
	if _t_fracaso <= 0.0:
		_t_fracaso = 1.0
		_revisar_fracaso()


## Tomar un lugar: avanza con americanos a menos de `radio` m y sin alemanes
## a menos de 9 m (si vuelven los alemanes, retrocede).
func _tomar(i: int, delta: float, segundos: float, radio: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(_pos[i]) < 9.0:
			progreso[i] = maxf(progreso[i] - delta * 0.25, 0.0)
			return
	for a in get_tree().get_nodes_in_group("americanos"):
		if not a.dead and a.global_position.distance_to(_pos[i]) < radio:
			progreso[i] += delta / segundos
			return


## Los jugadores vivos (el de este celular y, en el anfitrión, los demás).
func _jugadores() -> Array:
	var l := []
	var p := get_tree().get_first_node_in_group("player") as Player
	if p and not p.dead:
		l.append(p)
	if Red.actual:
		for id in Red.actual.remotos:
			var r = Red.actual.remotos[id]
			if is_instance_valid(r) and not r.dead:
				l.append(r)
	return l


func _cumplir(i: int) -> void:
	hecho[i] = true
	progreso[i] = 1.0
	Red.anunciar("[OBJETIVO CUMPLIDO: %s - %d/4]" % [LISTA[i]["n"], cumplidos()], Game.COLOR_GOOD)
	if cumplidos() == 4:
		terminar(1)


## Fracaso: todos los jugadores caídos y sin nadie que los releve.
func _revisar_fracaso() -> void:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or not p.dead or Escuadras.le_queda(Escuadras.mi_escuadra) or p.esperando_relevo:
		return
	if Red.actual:
		for id in Red.actual.remotos:
			var r = Red.actual.remotos[id]
			if is_instance_valid(r) and (not r.dead or Escuadras.le_queda(r.escuadra) or Red.actual.vuelve_pronto(id)):
				return
	terminar(-1)


func terminar(resultado: int) -> void:
	if terminado != 0:
		return
	terminado = resultado
	if Red.es_anfitrion():
		Red.evento(["fin", resultado, Game.bajas, Game.caidos, int(Game.elapsed)])
	FinMision.mostrar(get_tree(), resultado, Game.bajas, Game.caidos, int(Game.elapsed))


## Invitado: el estado que manda el anfitrión.
static func recibir(o: Array) -> void:
	for i in 4:
		hecho[i] = int(o[i]) == 1
		progreso[i] = float(o[4 + i])


static func estado() -> Array:
	var o := []
	for i in 4:
		o.append(1 if hecho[i] else 0)
	for i in 4:
		o.append(snappedf(progreso[i], 0.01))
	return o


## Línea para el HUD: el objetivo de mi escuadra.
static func texto() -> String:
	if actual == null:
		return ""
	var i := mio()
	if hecho[i]:
		var f := foco(i)
		if f < 0:
			return "OBJETIVOS CUMPLIDOS (%d/4)" % cumplidos()
		return "FALTA: %s - VE A APOYAR (%d/4)" % [LISTA[f]["n"], cumplidos()]
	return "OBJETIVO: %s (%d/4)" % [LISTA[i]["n"], cumplidos()]
