extends Node
class_name Objetivos
## Los objetivos de la misión, por FASES (sección 6). Vienen de Misiones:
## cada fase tiene su lista y la misión pasa a la siguiente cuando están
## todos los de la actual. La última fase cumplida = misión cumplida.
## LISTA tiene TODOS los objetivos de todas las fases, en orden, cada uno con
## su "fase" (así el estado se manda por la red como dos listas planas).
##
## Tipos de objetivo:
##   carga     un JUGADOR se queda `seg` junto al lugar poniendo la carga;
##             explota `mecha` s después (hay que alejarse). La IA no puede.
##   mg        matar al tirador de la MG42 (lo pone Defensa en el nido) y tomar
##             el nido. Si nadie llega en 20 s, otro alemán toma la MG42.
##   tomar     americanos dentro de `radio` y ningún alemán a menos de 9 m.
##   defender  aguantar `seg` en el lugar mientras llegan olas alemanas. Si los
##             alemanes lo ocupan sin ningún americano 25 s, se pierde.
## En "mg", "tomar" y "defender" la IA ayuda, pero sin un jugador cerca avanza
## a menos de la mitad de velocidad (los objetivos importantes los hace uno).
## Fracaso: todos los jugadores caídos y sin nadie que los releve, o perder
## el lugar que había que defender.
## Lo decide quien tiene la IA (jugando solo, o el anfitrión); los invitados
## reciben el estado por la red y solo lo muestran (y aplican los cambios del
## mapa: el alambre abierto, la casamata destruida).

const SEG_CARGA := 5.0
const SEG_TOMAR := 8.0
const SEG_NIDO := 5.0
const RITMO_IA := 0.4          # la IA sola avanza a este ritmo
const SEG_PERDER := 25.0       # alemanes en el lugar a defender sin americanos

static var LISTA: Array = []
static var hecho: Array = []
static var progreso: Array = []
static var terminado := 0          # 0 = en curso, 1 = cumplida, -1 = fracasada
static var actual: Objetivos
static var banner_t := 0.0         # >0: se muestra el título de la fase que empieza
static var perdiendo := 0.0        # segundos que los alemanes llevan ocupando el lugar a defender

var _marcas: Array = []
var _t_fracaso := 2.0
var _sin_tirador := {}             # objetivo "mg" → desde cuándo no tiene tirador
var _mecha := {}                   # objetivo "carga" → segundos que faltan para que explote
var _fase_vista := -1
var _hecho_visto: Array = []


func _ready() -> void:
	actual = self
	terminado = 0
	banner_t = 0.0
	perdiendo = 0.0
	LISTA = []
	var ids := {}
	var fases := Misiones.fases()
	for f in fases.size():
		for o in fases[f]["objetivos"]:
			var x: Dictionary = o.duplicate()
			x["fase"] = f
			ids[x["id"]] = LISTA.size()
			LISTA.append(x)
	for x in LISTA:
		x["tras_i"] = ids.get(x.get("tras", ""), -1)
	hecho = []
	progreso = []
	_hecho_visto = []
	for x in LISTA:
		hecho.append(false)
		progreso.append(0.0)
		_hecho_visto.append(false)
		var m := Label3D.new()
		m.text = "[ %s ]" % x["corto"]
		m.font = Estilo.FUENTE
		m.font_size = 22
		m.pixel_size = 0.0022
		m.fixed_size = true
		m.no_depth_test = true
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.outline_size = 4
		m.visible = false
		add_child(m)
		m.global_position = x["pos"] + Vector3(0, 3.0, 0)
		_marcas.append(m)


func _exit_tree() -> void:
	if actual == self:
		actual = null


## ¿Este celular decide (IA local)? Los invitados solo muestran.
static func manda() -> bool:
	return not Red.es_invitado()


static func mio() -> int:
	return clampi(Escuadras.mi_escuadra, 0, 3)


# ================================================================ fases

static func n_fases() -> int:
	return Misiones.fases().size()


## La fase en curso: la primera que tiene algún objetivo sin cumplir.
static func fase() -> int:
	for i in LISTA.size():
		if not hecho[i]:
			return LISTA[i]["fase"]
	return maxi(n_fases() - 1, 0)


## ¿Este objetivo se puede hacer ahora? (de la fase en curso, sin cumplir y
## con su objetivo previo ya cumplido)
static func activo(i: int) -> bool:
	if i < 0 or i >= LISTA.size() or hecho[i] or LISTA[i]["fase"] != fase():
		return false
	var t: int = LISTA[i]["tras_i"]
	return t < 0 or hecho[t]


## Los objetivos de la fase en curso: [cumplidos, total].
static func cuenta_fase() -> Vector2i:
	var f := fase()
	var c := Vector2i.ZERO
	for i in LISTA.size():
		if LISTA[i]["fase"] == f:
			c.y += 1
			if hecho[i]:
				c.x += 1
	return c


## Compatibilidad: objetivos cumplidos en total.
static func cumplidos() -> int:
	return hecho.count(true)


## El objetivo en que debe estar una escuadra: uno activo que le toque; si no
## hay, el activo más cercano a su carril; si no, uno de la fase que espera a
## otro (va a ese lugar a esperar). -1 si no queda ninguno.
static func foco(esc: int) -> int:
	esc = clampi(esc, 0, 3)
	var mejor := -1
	var mejor_v := INF
	for i in LISTA.size():
		if hecho[i] or LISTA[i]["fase"] != fase():
			continue
		var o: Dictionary = LISTA[i]
		var v := 0.0
		if not activo(i):
			v += 1000.0                     # todavía no se puede: solo si no hay otro
		if not esc in o.get("esc", []):
			var c: Vector2 = o.get("carril", Vector2(-10, 10))
			v += 100.0 + absf((c.x + c.y) / 2.0 - _centro_carril(esc))
		if v < mejor_v:
			mejor_v = v
			mejor = i
	return mejor


static func _centro_carril(esc: int) -> float:
	var s: Array = Misiones.dato("sectores")
	var v: Vector2 = s[clampi(esc, 0, s.size() - 1)]
	return (v.x + v.y) / 2.0


static func foco_mio() -> int:
	return foco(mio())


## Hacia dónde avanza una escuadra cuando no ve alemanes.
static func rumbo(esc: int) -> Vector3:
	var f := foco(esc)
	if f < 0:
		return Misiones.fase(fase()).get("ancla", Vector3(0, 0, -42))
	return LISTA[f]["pos"]


## Carril X de una escuadra (el de su objetivo).
static func carril(esc: int) -> Vector2:
	var f := foco(esc)
	if f < 0:
		return Misiones.dato("sectores")[clampi(esc, 0, 3)]
	return LISTA[f].get("carril", Vector2(-10, 10))


## ¿Sigue en pie el objetivo con este efecto? (p. ej. la casamata del cañón)
static func pendiente(efecto: String) -> bool:
	for i in LISTA.size():
		if LISTA[i].get("efecto", "") == efecto:
			return not hecho[i]
	return false


# ================================================================ cada cuadro

func _process(delta: float) -> void:
	banner_t = maxf(banner_t - delta, 0.0)
	var f := fase()
	if f != _fase_vista and terminado == 0:
		_empezar_fase(f)
	var foco_i := foco_mio()
	for i in LISTA.size():
		var m: Label3D = _marcas[i]
		m.visible = activo(i) and terminado == 0
		m.modulate = Estilo.AMBAR_CLARO if i == foco_i else Color(Estilo.CREMA, 0.45)
	if not manda() or terminado != 0 or not Navegacion.listo:
		return
	for i in LISTA.size():
		if not activo(i):
			continue
		var o: Dictionary = LISTA[i]
		match o["tipo"]:
			"mg":
				_nido(i, delta)
			"carga":
				_carga(i, delta)
			"tomar":
				_tomar(i, delta, float(o.get("seg", SEG_TOMAR)), float(o.get("radio", 6.0)))
				if progreso[i] >= 1.0:
					_cumplir(i)
			"defender":
				_defender(i, delta)
	_t_fracaso -= delta
	if _t_fracaso <= 0.0:
		_t_fracaso = 1.0
		_revisar_fracaso()


## Empieza una fase (en todos los celulares): título, reloj, radio, municiones
## y dónde vuelve el jugador si cae sin compañeros.
func _empezar_fase(f: int) -> void:
	var primera := _fase_vista < 0
	_fase_vista = f
	var d := Misiones.fase(f)
	perdiendo = 0.0
	Game.start_minutes = int(d.get("hora", Game.start_minutes)) - int(Game.elapsed / 60.0)
	if primera and f == 0:
		return
	banner_t = 5.0
	Game.play("click", 2.0)
	if str(d.get("radio", "")) != "":
		Game.say(d["radio"], Game.COLOR_INFO)
	var p := get_tree().get_first_node_in_group("player") as Player
	if p:
		var w := p.weapons
		for k in w.slots.size():
			var a := Armas.datos(w.slots[k])
			w.reserve[k] = maxi(w.reserve[k], int(a["mag"]) * 3)
		p.grenades = maxi(p.grenades, 2)
		var ll: Array = d.get("llegada", [])
		if not ll.is_empty():
			p.set_meta("inicio", Navegacion.cerca_de(ll[0]))
		Game.say("[MUNICIONES REPUESTAS]", Game.COLOR_GOOD)


func _nido(i: int, delta: float) -> void:
	var d := Defensa.actual
	if d == null:
		return
	var n = d.nidos.get(i)
	if n != null and is_instance_valid(n) and not n.dead:
		_sin_tirador.erase(i)
		progreso[i] = 0.0
		return
	if not _sin_tirador.has(i):
		if not d.nidos.has(i):
			return      # Defensa todavía no puso al tirador
		_sin_tirador[i] = Game.elapsed
		Red.anunciar("[%s SIN TIRADOR: ¡TOMEN EL NIDO!]" % LISTA[i]["n"].replace("CALLAR LA ", ""), Game.COLOR_GOOD)
	_tomar(i, delta, SEG_NIDO, 6.0)
	if progreso[i] >= 1.0:
		_cumplir(i)
	elif Game.elapsed - _sin_tirador[i] > 20.0 and progreso[i] < 0.05:
		d.reponer_nido(i)
		_sin_tirador.erase(i)
		Red.anunciar("[OTRO ALEMÁN TOMA LA MG42]", Game.COLOR_BAD)


func _carga(i: int, delta: float) -> void:
	var o: Dictionary = LISTA[i]
	if _mecha.has(i):   # carga puesta: explota sola, hay que alejarse
		_mecha[i] -= delta
		if _mecha[i] < 0.0:
			_mecha.erase(i)
			Game.explode(o.get("boom", o["pos"]), 9.0, 400.0)
			_cumplir(i)
		return
	var cerca := false
	for j in _jugadores():
		if j.global_position.distance_to(o["pos"]) < 2.6:
			cerca = true
	if cerca:
		progreso[i] += delta / float(o.get("seg", SEG_CARGA))
	else:
		progreso[i] = maxf(progreso[i] - delta * 0.1, 0.0)
	if progreso[i] >= 1.0:
		progreso[i] = 0.999
		_mecha[i] = float(o.get("mecha", 6.0))
		Red.anunciar("[CARGA PUESTA: ¡ALÉJENSE! %d S]" % int(_mecha[i]), Game.COLOR_BAD)


## Tomar un lugar: avanza con americanos a menos de `radio` m y sin alemanes
## a menos de 9 m (si vuelven los alemanes, retrocede). Sin un jugador cerca,
## más lento.
func _tomar(i: int, delta: float, segundos: float, radio: float) -> void:
	var pos: Vector3 = LISTA[i]["pos"]
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(pos) < 9.0:
			progreso[i] = maxf(progreso[i] - delta * 0.25, 0.0)
			return
	var ritmo := 0.0
	for j in _jugadores():
		if j.global_position.distance_to(pos) < radio:
			ritmo = 1.0
	if ritmo == 0.0:
		for a in get_tree().get_nodes_in_group("americanos"):
			if not a.dead and a.global_position.distance_to(pos) < radio:
				ritmo = RITMO_IA
				break
	progreso[i] += delta / segundos * ritmo


## Defender: el tiempo corre mientras haya americanos en el lugar (más lento
## sin un jugador). Si solo hay alemanes, se va perdiendo.
func _defender(i: int, delta: float) -> void:
	var o: Dictionary = LISTA[i]
	var pos: Vector3 = o["pos"]
	var radio: float = o.get("radio", 15.0)
	var ritmo := 0.0
	for j in _jugadores():
		if j.global_position.distance_to(pos) < radio:
			ritmo = 1.0
	if ritmo == 0.0:
		for a in get_tree().get_nodes_in_group("americanos"):
			if not a.dead and a.global_position.distance_to(pos) < radio:
				ritmo = 0.5
				break
	var alemanes := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(pos) < radio * 0.6:
			alemanes += 1
	if ritmo == 0.0 and alemanes > 0:
		if perdiendo == 0.0:
			Red.anunciar("[¡LOS ALEMANES TOMAN EL CRUCE! ¡RECUPÉRENLO!]", Game.COLOR_BAD)
		perdiendo += delta
		if perdiendo > SEG_PERDER:
			Red.anunciar("[PERDIMOS VIERVILLE]", Game.COLOR_BAD)
			terminar(-1)
		return
	perdiendo = maxf(perdiendo - delta * 2.0, 0.0)
	var antes: float = progreso[i]
	progreso[i] += delta / float(o.get("seg", 120.0)) * ritmo
	for marca in [0.5, 0.8]:
		if antes < marca and progreso[i] >= marca:
			var falta := int((1.0 - progreso[i]) * float(o.get("seg", 120.0)))
			Red.anunciar("[RADIO: LOS TANQUES LLEGAN EN %d S. ¡AGUANTEN!]" % falta, Game.COLOR_INFO)
	if progreso[i] >= 1.0:
		Red.anunciar("[¡LLEGAN LOS SHERMAN! ¡VIERVILLE ES NUESTRA!]", Game.COLOR_GOOD)
		_cumplir(i)


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
	_aplicar_efectos()
	var c := cuenta_fase()
	if fase() == LISTA[i]["fase"]:
		Red.anunciar("[OBJETIVO CUMPLIDO: %s - %d/%d]" % [LISTA[i]["n"], c.x, c.y], Game.COLOR_GOOD)
	else:
		Red.anunciar("[OBJETIVO CUMPLIDO: %s]" % LISTA[i]["n"], Game.COLOR_GOOD)
	if hecho.count(false) == 0:
		terminar(1)


## Lo que cambia en el mapa al cumplir un objetivo (en todos los celulares).
func _aplicar_efectos() -> void:
	for i in LISTA.size():
		if hecho[i] and not _hecho_visto[i]:
			_hecho_visto[i] = true
			match str(LISTA[i].get("efecto", "")):
				"brecha":
					OmahaInterior.abrir_brecha()
				"casamata":
					OmahaInterior.destruir_casamata()


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


## Invitado: el estado que manda el anfitrión (cumplidos y avance de cada uno).
static func recibir(o: Array) -> void:
	var n := o.size() / 2
	if n != LISTA.size():
		return
	for i in n:
		hecho[i] = int(o[i]) == 1
		progreso[i] = float(o[n + i])
	if actual:
		actual._aplicar_efectos()


static func estado() -> Array:
	var o := []
	for i in LISTA.size():
		o.append(1 if hecho[i] else 0)
	for i in LISTA.size():
		o.append(snappedf(progreso[i], 0.01))
	return o


## Línea para el HUD: la fase en curso.
static func texto_fase() -> String:
	if actual == null:
		return ""
	return "FASE %d/%d: %s" % [fase() + 1, n_fases(), Misiones.fase(fase())["nombre"]]


## Línea para el HUD: el objetivo de mi escuadra.
static func texto() -> String:
	if actual == null:
		return ""
	var f := foco_mio()
	var c := cuenta_fase()
	if f < 0:
		return "OBJETIVOS CUMPLIDOS"
	var o: Dictionary = LISTA[f]
	var txt := "OBJETIVO: %s (%d/%d)" % [o["n"], c.x, c.y]
	if not mio() in o.get("esc", []):
		txt = "APOYA: %s (%d/%d)" % [o["n"], c.x, c.y]
	if not activo(f):
		txt = "ESPERA: %s" % LISTA[o["tras_i"]]["n"]
	if o["tipo"] == "defender" and perdiendo > 0.0:
		txt = "¡RECUPERA EL CRUCE! %d S" % int(SEG_PERDER - perdiendo)
	return txt
