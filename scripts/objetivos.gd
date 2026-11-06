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
##             alemanes lo ocupan sin ningún americano 25 s, se pierde. Textos
##             propios de cada misión: txt_toman, txt_perdido, txt_llegan,
##             txt_fin, txt_recupera (si faltan, los de Vierville).
##   reunir    (misión 2) los compañeros dispersos tras el choque (Escuadras
##             los marca "perdido") se unen cuando el jugador llega a su lado.
##             El GRILLO (Player.grillo) los hace contestar: se oye dónde están.
##             Sin marcador en el mapa.
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
const DIST_APOYO := 45.0       # con un jugador a menos de esto, la IA toma los lugares a ritmo completo
const RADIO_ALEMANES := 9.0    # un alemán vivo a menos de esto impide tomar el lugar

static var LISTA: Array = []
static var hecho: Array = []
static var progreso: Array = []
static var terminado := 0          # 0 = en curso, 1 = cumplida, -1 = fracasada
static var actual: Objetivos
static var banner_t := 0.0         # >0: se muestra el título de la fase que empieza
static var perdiendo := 0.0        # segundos que los alemanes llevan ocupando el lugar a defender
## Cómo va la defensa en curso (para el HUD; los invitados lo reciben en estado()):
## 0 = el reloj corre, 2 = disputado (hay alemanes encima), 3 = sin un jugador cerca (más lento)
static var defensa_estado := 0

var _marcas: Array = []
var _t_fracaso := 2.0
var _sin_tirador := {}             # objetivo "mg" → desde cuándo no tiene tirador
var _mecha := {}                   # objetivo "carga" → segundos que faltan para que explote
var _fase_vista := -1
var _hecho_visto: Array = []
var _reunir_lista := {}            # objetivo "reunir" → [Aliado] los que estaban perdidos
static var reunidos := Vector2i(1, 1)   # para el HUD: hombres juntos / total (contándote a ti)


func _ready() -> void:
	actual = self
	terminado = 0
	banner_t = 0.0
	perdiendo = 0.0
	defensa_estado = 0
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
	_fase_memo = -1
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
## Se guarda (se pide muchísimas veces por cuadro) y se recalcula solo cuando
## cambia `hecho` (_cumplir, recibir y al empezar).
static var _fase_memo := -1


static func fase() -> int:
	if _fase_memo >= 0:
		return _fase_memo
	_fase_memo = maxi(n_fases() - 1, 0)
	for i in LISTA.size():
		if not hecho[i]:
			_fase_memo = LISTA[i]["fase"]
			break
	return _fase_memo


## ¿Este objetivo se puede hacer ahora? (de la fase en curso, sin cumplir y
## con su objetivo previo ya cumplido)
static func activo(i: int) -> bool:
	if i < 0 or i >= LISTA.size() or hecho[i] or LISTA[i]["fase"] != fase():
		return false
	var t: int = LISTA[i]["tras_i"]
	return t < 0 or hecho[t]


## Segundos que le quedan a una carga encendida (0 si no hay ninguna).
static func mecha(i: int) -> float:
	if i < 0 or i >= LISTA.size() or hecho[i] or LISTA[i]["tipo"] != "carga":
		return 0.0
	return maxf(progreso[i] - 1.0, 0.0)


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


## ¿Hay un alemán vivo junto a este lugar? (impide tomarlo)
static func alemanes_cerca(pos: Vector3) -> bool:
	for e in Engine.get_main_loop().get_nodes_in_group("enemies"):
		if not e.get("dead") and e.global_position.distance_to(pos) < RADIO_ALEMANES:
			return true
	return false


## El objetivo que el jugador tiene más cerca (activo, sin cumplir, a menos de
## `radio` m), sea de su escuadra o no: así se puede cumplir en cualquier orden.
static func cercano(pos: Vector3, radio := 22.0) -> int:
	var mejor := -1
	var mejor_d := radio
	for i in LISTA.size():
		if hecho[i] or LISTA[i]["fase"] != fase() or not activo(i):
			continue
		var d: float = (LISTA[i]["pos"] as Vector3).distance_to(pos)
		if d < mejor_d:
			mejor_d = d
			mejor = i
	return mejor


## Un lugar que los compañeros pueden asegurar detrás del jugador: objetivo
## "tomar" o un nido de MG42 ya sin tirador, a menos de DIST_APOYO del jugador
## y sin alemanes alrededor. -1 si no hay.
static func asegurable(jugador: Vector3) -> int:
	if actual == null:
		return -1
	for i in LISTA.size():
		if hecho[i] or LISTA[i]["fase"] != fase() or not activo(i):
			continue
		var o: Dictionary = LISTA[i]
		if o["tipo"] == "mg" and not actual._sin_tirador.has(i):
			continue
		if o["tipo"] != "tomar" and o["tipo"] != "mg":
			continue
		var p: Vector3 = o["pos"]
		if p.distance_to(jugador) < DIST_APOYO and not alemanes_cerca(p):
			return i
	return -1


static func _centro_carril(esc: int) -> float:
	var s: Array = Misiones.dato("sectores")
	var v: Vector2 = s[clampi(esc, 0, s.size() - 1)]
	return (v.x + v.y) / 2.0


static func foco_mio() -> int:
	var p := Engine.get_main_loop().get_first_node_in_group("player") as Node3D
	if p:
		var c := cercano(p.global_position)
		if c >= 0:
			return c
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
		m.visible = activo(i) and terminado == 0 and LISTA[i]["tipo"] != "reunir"
		m.modulate = Estilo.AMBAR_CLARO if i == foco_i else Color(Estilo.CREMA, 0.45)
	# Los Sherman suben por el camino cuando falta poco para aguantar (en todos los celulares)
	for i in LISTA.size():
		if LISTA[i]["tipo"] == "defender" and progreso[i] >= 0.85 and not OmahaInterior._tanques_llegan \
				and Game.mision == "omaha":
			if manda():
				Red.anunciar("[RADIO: ¡LOS SHERMAN ESTÁN SUBIENDO POR EL CAMINO!]", Game.COLOR_GOOD)
			OmahaInterior.llegan_tanques(get_parent(), (1.0 - minf(progreso[i], 1.0)) * float(LISTA[i].get("seg", 120.0)))
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
			"reunir":
				_reunir(i)
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
	defensa_estado = 0
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
		if fmod(_mecha[i], 1.0) > fmod(_mecha[i] + delta, 1.0) or _mecha[i] + delta >= float(o.get("mecha", 6.0)):
			_alejar_ia(o.get("boom", o["pos"]))
		progreso[i] = 1.0 + maxf(_mecha[i], 0.01)   # >1 = mecha encendida (así lo ven también los invitados)
		if _mecha[i] < 0.0:
			_mecha.erase(i)
			Game.explode(o.get("boom", o["pos"]), 9.0, 400.0)
			_cumplir(i)
		return
	var cerca := false
	var radio: float = o.get("radio", 3.0)
	for j in _jugadores():
		var dj: Vector3 = j.global_position - o["pos"]
		if Vector2(dj.x, dj.z).length() < radio and absf(dj.y) < 2.5:
			cerca = true
	if cerca:
		var ritmo := 2.0 if Escuadras.especialista("ingeniero", o["pos"], 15.0) else 1.0
		progreso[i] += delta / float(o.get("seg", SEG_CARGA)) * ritmo
	else:
		progreso[i] = maxf(progreso[i] - delta * 0.1, 0.0)
	if progreso[i] >= 1.0:
		_mecha[i] = float(o.get("mecha", 6.0))
		progreso[i] = 1.0 + _mecha[i]
		Red.anunciar("[CARGA PUESTA: ¡ALÉJENSE! %d S]" % int(_mecha[i]), Game.COLOR_BAD)


## Carga encendida: los compañeros con IA que estén cerca corren a ponerse a salvo.
func _alejar_ia(centro: Vector3) -> void:
	for a in get_tree().get_nodes_in_group("aliados"):
		if not a is Aliado or a.dead:
			continue
		var d: Vector3 = a.global_position - centro
		d.y = 0.0
		if d.length() > 11.0:
			continue
		var fuera := d.normalized() if d.length() > 0.5 else Vector3(0, 0, 1)
		if a.moviendo and Game.elapsed < float(a.get_meta("huye_hasta", 0.0)):
			continue
		a.set_meta("huye_hasta", Game.elapsed + 7.0)   # mientras tanto no vuelve (aliado.gd)
		a.ir_a({"pos": Navegacion.cerca_de(centro + fuera * 14.0)})


## Tomar un lugar: avanza con americanos a menos de `radio` m y sin alemanes
## a menos de 9 m (si vuelven los alemanes, retrocede). Sin un jugador cerca,
## más lento.
func _tomar(i: int, delta: float, segundos: float, radio: float) -> void:
	var pos: Vector3 = LISTA[i]["pos"]
	if alemanes_cerca(pos):
		progreso[i] = maxf(progreso[i] - delta * 0.25, 0.0)
		return
	var ritmo := 0.0
	for j in _jugadores():
		if j.global_position.distance_to(pos) < radio:
			ritmo = 1.0
	if ritmo == 0.0:
		# Si un jugador anda cerca (adelante, en primera línea), sus compañeros
		# aseguran el lugar a ritmo completo; si no, la IA sola va más lenta.
		var apoyo := RITMO_IA
		for j in _jugadores():
			if j.global_position.distance_to(pos) < DIST_APOYO:
				apoyo = 1.0
		for a in get_tree().get_nodes_in_group("americanos"):
			if not a.dead and a.global_position.distance_to(pos) < radio:
				ritmo = apoyo
				break
	progreso[i] += delta / segundos * ritmo


## Defender: el reloj corre parejo mientras el lugar siga en manos americanas
## (v0.32: antes bajaba a la mitad apenas el jugador salía del círculo y
## parecía que la barra se frenaba sola). Se detiene si los alemanes llegan
## encima y son tantos como los nuestros (DISPUTADO), y va a la mitad solo si
## no hay ningún jugador en los alrededores (la IA sola aguanta a medias).
## Si solo quedan alemanes en el lugar, se va perdiendo.
const DEF_ALREDEDOR := 25.0     # metros más allá del radio en que un jugador sigue "defendiendo"

func _defender(i: int, delta: float) -> void:
	var o: Dictionary = LISTA[i]
	var pos: Vector3 = o["pos"]
	var radio: float = o.get("radio", 15.0)
	var nuestros := 0
	for a in get_tree().get_nodes_in_group("americanos"):
		if not a.dead and a.global_position.distance_to(pos) < radio:
			nuestros += 1
	var jugador_cerca := false
	for j in _jugadores():
		var d: float = j.global_position.distance_to(pos)
		if d < radio:
			nuestros += 1          # un jugador vale por dos
		if d < radio + DEF_ALREDEDOR:
			jugador_cerca = true
	var alemanes := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(pos) < radio * 0.6:
			alemanes += 1
	if nuestros == 0 and alemanes > 0:
		if perdiendo == 0.0:
			Red.anunciar(o.get("txt_toman", "[¡LOS ALEMANES TOMAN EL CRUCE! ¡RECUPÉRENLO!]"), Game.COLOR_BAD)
		perdiendo += delta
		defensa_estado = 2
		if perdiendo > SEG_PERDER:
			Red.anunciar(o.get("txt_perdido", "[PERDIMOS VIERVILLE]"), Game.COLOR_BAD)
			terminar(-1)
		return
	perdiendo = maxf(perdiendo - delta * 2.0, 0.0)
	var ritmo := 1.0
	defensa_estado = 0
	if alemanes > 0 and alemanes > nuestros:
		ritmo = 0.0
		defensa_estado = 2
	elif nuestros == 0 or not jugador_cerca:
		ritmo = 0.5
		defensa_estado = 3
	var antes: float = progreso[i]
	progreso[i] += delta / float(o.get("seg", 120.0)) * ritmo
	for marca in [0.5, 0.8]:
		if antes < marca and progreso[i] >= marca:
			var falta := int((1.0 - progreso[i]) * float(o.get("seg", 120.0)))
			Red.anunciar(o.get("txt_llegan", "[RADIO: LOS TANQUES LLEGAN EN %d S. ¡AGUANTEN!]") % falta, Game.COLOR_INFO)
	if progreso[i] >= 1.0:
		defensa_estado = 0
		Red.anunciar(o.get("txt_fin", "[¡LLEGAN LOS SHERMAN! ¡VIERVILLE ES NUESTRA!]"), Game.COLOR_GOOD)
		_cumplir(i)


## Reunir a la escuadra (misión 2): los que quedaron dispersos tras el choque
## se unen cuando un jugador llega a menos de 5,5 m. Los que murieron antes de
## que los encontraras cuentan como resueltos (no traba la misión).
const DIST_REUNIR := 5.5
const FRASES_REUNIR := ["¡SARGENTO! CREÍ QUE ERA UN ALEMÁN", "¡GRACIAS A DIOS! PENSÉ QUE ESTABA SOLO",
	"¡AQUÍ! ¡NO DISPARE, SOY YO!", "¡SARGENTO! LOS DEMÁS SE ESTRELLARON MÁS ALLÁ"]


func _reunir(i: int) -> void:
	if not _reunir_lista.has(i):
		if Escuadras.actual == null:
			return
		var l := []
		for a in Escuadras.actual.datos[Escuadras.mi_escuadra]["ranuras"]:
			if a and is_instance_valid(a) and a.has_meta("perdido"):
				l.append(a)
		_reunir_lista[i] = l
	var lista: Array = _reunir_lista[i]
	var listos := 0
	for a in lista:
		if not is_instance_valid(a) or a.dead:
			listos += 1
			continue
		if not a.has_meta("perdido"):
			listos += 1
			continue
		for j in _jugadores():
			if j.global_position.distance_to(a.global_position) < DIST_REUNIR:
				a.remove_meta("perdido")
				a._pensar_t = 0.3
				Game.say("[%s: %s]" % [a.nombre, FRASES_REUNIR[randi() % FRASES_REUNIR.size()]], Game.COLOR_GOOD)
				Game.respuesta("resp_ok", a, 0.3)
				listos += 1
				break
	reunidos = Vector2i(1 + 3 - lista.size() + listos, 4)
	progreso[i] = 1.0 if lista.is_empty() else float(listos) / lista.size()
	if progreso[i] >= 1.0:
		_cumplir(i)


## ¿Quedan compañeros perdidos? (para el botón GRILLO)
static func hay_perdidos() -> bool:
	if actual == null or terminado != 0:
		return false
	for i in LISTA.size():
		if LISTA[i]["tipo"] == "reunir" and activo(i):
			return true
	return false


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
	_fase_memo = -1
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
				var otro:
					if otro != "" and MapaPlaneador.actual:
						MapaPlaneador.actual.efecto(otro)


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
	Game.anotar_resultado(resultado)
	if Red.es_anfitrion():
		Red.evento(["fin", resultado, Game.bajas, Game.caidos, int(Game.elapsed)])
	FinMision.mostrar(get_tree(), resultado, Game.bajas, Game.caidos, int(Game.elapsed))


## Invitado: el estado que manda el anfitrión (cumplidos y avance de cada uno).
static func recibir(o: Array) -> void:
	var n := o.size() / 2
	if n != LISTA.size():
		return
	defensa_estado = 0
	for i in n:
		hecho[i] = int(o[i]) == 1
		if int(o[i]) >= 2:      # la defensa en curso: 2 = disputada, 3 = lenta
			defensa_estado = int(o[i])
		progreso[i] = float(o[n + i])
	_fase_memo = -1
	if actual:
		actual._aplicar_efectos()


static func estado() -> Array:
	var o := []
	for i in LISTA.size():
		var v := 1 if hecho[i] else 0
		if v == 0 and LISTA[i]["tipo"] == "defender" and defensa_estado != 0 and activo(i):
			v = defensa_estado
		o.append(v)
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
	if (o["tipo"] == "tomar" or (o["tipo"] == "mg" and actual._sin_tirador.has(f))) and alemanes_cerca(o["pos"]):
		var p := Engine.get_main_loop().get_first_node_in_group("player") as Node3D
		if p and p.global_position.distance_to(o["pos"]) < 22.0:
			txt = "%s: QUEDAN ALEMANES CERCA" % o["corto"]
	if o["tipo"] == "carga" and progreso[f] > 1.0:
		txt = "¡CARGA PUESTA! ALÉJATE: %d S" % ceili(progreso[f] - 1.0)
	if o["tipo"] == "defender" and activo(f):
		var falta := int(ceil((1.0 - minf(progreso[f], 1.0)) * float(o.get("seg", 120.0))))
		var reloj := "%d:%02d" % [falta / 60, falta % 60]
		match defensa_estado:
			2: txt = "%s: DISPUTADO - ¡SÁCALOS DE AHÍ! (%s)" % [o["corto"], reloj]
			3: txt = "%s: %s - VUELVE, SIN TI AGUANTAN A MEDIAS" % [o["corto"], reloj]
			_: txt = "%s: AGUANTA %s" % [o["corto"], reloj]
	if o["tipo"] == "defender" and perdiendo > 0.0:
		txt = "%s %d S" % [o.get("txt_recupera", "¡RECUPERA EL CRUCE!"), int(SEG_PERDER - perdiendo)]
	if o["tipo"] == "reunir":
		txt = "REÚNE A TU ESCUADRA (%d/%d): USA EL GRILLO" % [reunidos.x, reunidos.y]
	return txt
