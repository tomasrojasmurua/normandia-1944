extends Node
class_name Red
## Cooperativo (sección 5): conecta este juego con los demás de la misma sala
## a través del servidor de Cloudflare (servidor/).
##
## - Cada jugador tiene un PUESTO (0–3, lo da el servidor): manda esa escuadra
##   y lleva el nombre de su jefe (MURPHY, KOWALSKI, REYES, COLE).
## - El ANFITRIÓN es el único que tiene la IA de verdad: los alemanes, los
##   compañeros de las cuatro escuadras, los nidos de MG42, los morteros, los
##   refuerzos y los objetivos. Los invitados ven "títeres" (AlemanRemoto).
## - Cada celular manda UN paquete por envío (12 por segundo):
##     {"t":"est","id", "p":[mi jugador], "l":[sucesos],
##      "a":[alemanes], "b":[compañeros], "o":[objetivos], "dr":refuerzos}
##   (a, b, o y dr solo el anfitrión). Menos mensajes = menos atascos.
## - Sucesos: t disparo de jugador - s tiro de IA - d murió un soldado de IA ·
##   x explosión - w silbido de mortero - m aviso - h daño a un jugador ·
##   g golpe a un títere - o orden a mi escuadra - r pido relevo - R respuesta
##   - q quitar títere - c cuerpos (para el que recién entra) - gr granada
##   alemana - ex (v0.40) "te tienen en la mira" a un invitado - fin fin de misión.
## - Armas del suelo: cada celular tiene las suyas. Cuando cae un soldado, cada
##   uno deja caer su arma en su propio celular (v0.40: antes solo en el
##   anfitrión, y los invitados se quedaban sin munición).
## - Si un invitado le pega a un títere, el golpe va al anfitrión; si la IA le
##   pega a un invitado, el daño va a ese jugador. Las explosiones las calcula
##   cada uno para su propio jugador.
## - Si el anfitrión se va, el servidor elige otro: ese celular convierte los
##   títeres en soldados de verdad y sigue la partida (traspaso).
##
## Red vive fuera de la escena (en la raíz) para conectarse desde el menú y
## saber quién es el anfitrión ANTES de armar la misión.

## Dirección del servidor (la da Cloudflare al instalarlo). Para pruebas
## locales se puede cambiar con la variable de entorno SERVIDOR_RED.
const SERVIDOR := "wss://normandy-1944.tomasrojasmurua.workers.dev"
const ENVIOS_POR_SEGUNDO := 12.0
const ATRASO := 0.15
const NOMBRES := ["MURPHY", "KOWALSKI", "REYES", "COLE"]
const POSES := ["reposo", "pie", "rodilla", "agachado"]
const ANDARES := ["", "camina", "corre"]
const MAX_CUERPOS := 60

static var actual: Red

var mi_id := ""
var puesto := 0
var mi_nombre := "MURPHY"
var anfitrion := false
var ping_ms := -1
var estado := "conectando"     # conectando / conectado / sala llena / sin conexión
var remotos := {}              # id → JugadorRemoto
var titeres := {}              # rid → AlemanRemoto (en los invitados; alemanes y compañeros)
var soldados := {}             # rid → Enemy / Aliado (en el anfitrión)

var _ws := WebSocketPeer.new()
var _t_envio := 0.0
var _t_ping := 0.0
var _t_limpiar := 0.0
var _abierto := false
var _eventos: Array = []
var _rid_sig := 1
var _cuerpos: Array = []       # [bando, arma, x, y, z, giro] (anfitrión: para los que entran tarde)
var _vuelven := {}             # id → hasta cuándo vuelve desde la orilla (anfitrión)
var _ultimo_dr := 9            # refuerzos alemanes que quedaban (por si hay traspaso)
# Sala de espera (antes de la misión): quién más está y si ya empezaron
var sala := {}                 # id → [puesto (-1 = aún no se sabe), anfitrión]
var en_curso := false          # el anfitrión ya empezó la misión
var mision_sala := "omaha"     # la misión que eligió el anfitrión (Misiones), la que juegan todos
var _t_lob := 0.0
var _avisos_bengala := 0


## El anfitrión empieza la misión desde la sala de espera: avisa a los demás.
static func empezar_partida() -> void:
	if actual:
		actual.en_curso = true
		actual._ws.send_text(JSON.stringify({"t": "ir", "m": actual.mision_sala}))


## Se conecta a la sala (desde el menú). Queda en la raíz del árbol.
static func conectar(arbol: SceneTree, codigo: String) -> void:
	if actual:
		actual.queue_free()
	Game.sala = codigo
	var r := Red.new()
	r.name = "Red"
	arbol.root.add_child(r)


func _ready() -> void:
	actual = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	var base := OS.get_environment("SERVIDOR_RED") if OS.get_environment("SERVIDOR_RED") != "" else SERVIDOR
	if _ws.connect_to_url("%s/sala/%s" % [base, Game.sala]) != OK:
		estado = "sin conexión"


func _exit_tree() -> void:
	_ws.close()
	if actual == self:
		actual = null


static func activo() -> bool:
	return actual != null and actual._abierto


static func es_anfitrion() -> bool:
	return activo() and actual.anfitrion


static func es_invitado() -> bool:
	return activo() and not actual.anfitrion


func _process(delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_abierto = true
			if estado == "conectando":
				estado = "conectado"
			while _ws.get_available_packet_count() > 0:
				_recibir(_ws.get_packet().get_string_from_utf8())
			# En la sala de espera (sin jugador): "aquí estoy" cada segundo
			_t_lob -= delta
			if _t_lob <= 0.0 and mi_id != "" and _jugador() == null:
				_t_lob = 1.0
				var lob := {"t": "lob", "id": mi_id, "pu": puesto, "a": anfitrion}
				if anfitrion:
					lob["m"] = mision_sala
				_ws.send_text(JSON.stringify(lob))
			_t_envio -= delta
			if _t_envio <= 0.0 and mi_id != "":
				_t_envio += 1.0 / ENVIOS_POR_SEGUNDO
				if _t_envio < 0.0:
					_t_envio = 0.0
				_enviar_paquete()
			_t_ping -= delta
			if _t_ping <= 0.0:
				_t_ping = 1.0
				_ws.send_text('{"t":"ping","k":%d}' % Time.get_ticks_msec())
			_t_limpiar -= delta
			if _t_limpiar <= 0.0:
				_t_limpiar = 1.0
				_limpiar_titeres()
			CampanaRed.procesar(delta)     # campaña cooperativa: el anfitrión manda el mapa
		WebSocketPeer.STATE_CLOSED:
			if _abierto or estado == "conectando":
				if estado != "sala llena":
					estado = "sin conexión"
			_abierto = false
			for id in remotos.keys():
				_quitar(id)


func _jugador() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _escena() -> Node:
	var e := get_tree().current_scene
	return e if e and e.name == "Main" else null


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _vec(a: Array, i := 0) -> Vector3:
	return Vector3(a[i], a[i + 1], a[i + 2])


# ================================================================ enviar

## El paquete de cada envío: mi jugador, mis sucesos y (anfitrión) la IA.
func _enviar_paquete() -> void:
	var paq := {"t": "est", "id": mi_id}
	var p := _jugador()
	if p:
		var v := Vector2(p.velocity.x, p.velocity.z).length()
		paq["p"] = [p.nombre, p.weapons.id(), snappedf(p.global_position.x, 0.01),
			snappedf(p.global_position.y, 0.01), snappedf(p.global_position.z, 0.01),
			snappedf(p.rotation.y, 0.01), 1 if p.crouching else 0, snappedf(v, 0.1), 1 if p.dead else 0, puesto]
	if not _eventos.is_empty():
		paq["l"] = _eventos
		_eventos = []
	if anfitrion and p:
		paq["a"] = _lista_alemanes()
		paq["b"] = _lista_aliados()
		paq["o"] = Objetivos.estado()
		paq["dr"] = Defensa.restantes
		paq["m"] = mision_sala
		var tq := Tanque.actual
		if tq and is_instance_valid(tq):
			paq["tk"] = [snappedf(tq.global_position.x, 0.01), snappedf(tq.global_position.y, 0.01),
				snappedf(tq.global_position.z, 0.01), snappedf(tq.rotation.y, 0.01), 1 if tq.dead else 0]
	if paq.size() > 2:
		_ws.send_text(JSON.stringify(paq))


## Número de un soldado de IA en la red (se lo da la primera vez que se lo pide).
func rid_de(n: Node) -> int:
	if not n.has_meta("rid"):
		n.set_meta("rid", _rid_sig)
		soldados[_rid_sig] = n
		_rid_sig += 1
	return n.get_meta("rid")


func _lista_alemanes() -> Array:
	var lista := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e is Enemy or e.dead or e.cuerpo == null:
			continue
		var q: Vector3 = e.global_position
		lista.append([rid_de(e), snappedf(q.x, 0.01), snappedf(q.y, 0.01), snappedf(q.z, 0.01),
			snappedf(e.rotation.y, 0.01), maxi(POSES.find(e.cuerpo.pose), 0),
			maxi(ANDARES.find(e.cuerpo.andar), 0), e.arma])
	return lista


func _lista_aliados() -> Array:
	var lista := []
	for a in get_tree().get_nodes_in_group("aliados"):
		if not a is Aliado or a.dead or a.cuerpo == null:
			continue
		var q: Vector3 = a.global_position
		lista.append([rid_de(a), snappedf(q.x, 0.01), snappedf(q.y, 0.01), snappedf(q.z, 0.01),
			snappedf(a.rotation.y, 0.01), maxi(POSES.find(a.cuerpo.pose), 0),
			maxi(ANDARES.find(a.cuerpo.andar), 0), a.arma, a.escuadra, Escuadras.puesto_de(a),
			a.nombre, int(a.health), (1 if a.has_meta("perdido") else 0) + (2 if a.has_meta("fue_perdido") else 0)])
	return lista


## Un suceso para los demás (sale en el próximo envío, junto con otros).
static func evento(ev: Array) -> void:
	if activo():
		actual._eventos.append(ev)


## Aviso en el HUD de todos (si soy el anfitrión) o solo en el mío.
static func anunciar(texto: String, color: Color = Game.COLOR_INFO) -> void:
	Game.say(texto, color)
	if es_anfitrion():
		evento(["m", texto, color.to_html(false)])


## Tiro de un soldado de IA (alemán o compañero), para que lo vean los invitados.
static func tiro_ia(n: Node, desde: Vector3, hasta: Vector3) -> void:
	if es_anfitrion():
		evento(["s", actual.rid_de(n)] + _v(desde) + _v(hasta))


## Murió un soldado de IA: los invitados ven caer a su títere y el cuerpo
## queda anotado para los que entren después.
static func murio(n: Node3D, dir: Vector3, cabeza: bool) -> void:
	if not es_anfitrion():
		return
	evento(["d", actual.rid_de(n), snappedf(dir.x, 0.01), snappedf(dir.z, 0.01), 1 if cabeza else 0])
	actual._anotar_cuerpo("aleman" if n is Enemy else "aliado", n.arma, n.global_position, n.rotation.y)


func _anotar_cuerpo(bando: String, arma: String, pos: Vector3, giro: float) -> void:
	_cuerpos.append([bando, arma] + _v(pos) + [snappedf(giro, 0.01)])
	if _cuerpos.size() > MAX_CUERPOS:
		_cuerpos.pop_front()


## Bengala alemana (misión de noche): los invitados la ven subir e iluminar.
static func bengala(desde: Vector3, hacia: Vector3) -> void:
	if es_anfitrion():
		evento(["bg"] + _v(desde) + _v(hacia))


## Tanque alemán (misión 2): ráfaga de su ametralladora o cañonazo, para verlo
## en los invitados (el daño llega aparte: "h" y "x").
static func tiro_tanque(desde: Vector3, hasta: Vector3, canon: bool) -> void:
	if es_anfitrion():
		evento(["tt"] + _v(desde) + _v(hasta) + [1 if canon else 0])


## Invitado: le pegué al tanque (lo que de verdad cuenta pasa en el anfitrión).
static func golpe_tanque(dano: float) -> void:
	evento(["tg", snappedf(dano, 0.1)])


static func silbido(pos: Vector3) -> void:
	if es_anfitrion():
		evento(["w"] + _v(pos))


static func granada(desde: Vector3, vel: Vector3) -> void:
	if es_anfitrion():
		evento(["gr"] + _v(desde) + _v(vel))


## Una explosión hecha aquí (granada, cohete, mortero): los demás la ven y
## cada uno calcula el daño a su propio jugador.
static func explosion(pos: Vector3, radio: float, dano: float) -> void:
	evento(["x"] + _v(pos) + [radio, dano])


## Un soldado de IA (en el anfitrión) le pegó a otro jugador.
static func dano(id: String, cantidad: float, desde: Vector3) -> void:
	evento(["h", id, cantidad] + _v(desde))


## Le pegué a un títere: que el anfitrión se lo aplique al alemán de verdad.
static func golpe(rid: int, cantidad: float, cabeza: bool, pos: Vector3, dir: Vector3) -> void:
	evento(["g", rid, snappedf(cantidad, 0.1), 1 if cabeza else 0] + _v(pos) + _v(dir))


## Disparo mío (desde, hasta), para que los demás vean la trazadora.
static func disparo(desde: Vector3, hasta: Vector3) -> void:
	evento(["t"] + _v(desde) + _v(hasta))


## Invitado: caí; que el anfitrión me diga a qué compañero tomo (o si vuelvo
## desde la orilla, o si no queda nadie).
static func pedir_relevo() -> void:
	evento(["r"])


# ================================================================ recibir

## La misión que eligió el anfitrión (solo las que existen).
func _tomar_mision(m: Variant) -> void:
	if Misiones.existe(str(m)) or str(m) == "campana":     # "campana": la campaña cooperativa (v0.41)
		mision_sala = str(m)


## Manda un mensaje suelto (la campaña cooperativa usa los suyos: CampanaRed).
func enviar(texto: String) -> void:
	if _abierto:
		_ws.send_text(texto)


func _recibir(texto: String) -> void:
	var d: Variant = JSON.parse_string(texto)
	if not d is Dictionary:
		return
	match str(d.get("t", "")):
		"hola":
			mi_id = d["id"]
			anfitrion = d["anfitrion"]
			puesto = clampi(int(d.get("puesto", 0)), 0, 3)
			mi_nombre = NOMBRES[puesto]
			for o in d.get("otros", []):
				sala[str(o)] = [-1, false]
		"lob":
			sala[str(d["id"])] = [int(d.get("pu", -1)), bool(d.get("a", false))]
			if d.has("m") and not anfitrion:
				_tomar_mision(d["m"])
		"ir":
			if d.has("m"):
				_tomar_mision(d["m"])
			en_curso = true
		"llena":
			estado = "sala llena"
		"entra":
			sala[str(d["id"])] = [-1, false]
			if anfitrion and en_curso:   # la misión ya empezó: que entre directo
				_ws.send_text(JSON.stringify({"t": "ir", "m": mision_sala}))
			Game.say("[ENTRÓ UN JUGADOR]", Game.COLOR_GOOD)
			if anfitrion and not _cuerpos.is_empty():
				evento(["c", str(d["id"]), _cuerpos])
		"cp":       # campaña cooperativa: el mapa, la previa... del anfitrión
			CampanaRed.recibir(d)
		"cpe", "cpa":   # campaña cooperativa: un invitado elige a sus hombres
			CampanaRed.pedido(d)
		"sale":
			sala.erase(str(d["id"]))
			_quitar(str(d["id"]))
			if d.get("anfitrion", false) and CampanaRed.coop:
				# La campaña vive en el celular del anfitrión: sin él no se puede seguir
				Game.aviso_menu = "SE FUE EL ANFITRIÓN: LA CAMPAÑA QUEDÓ GUARDADA EN SU CELULAR."
				Game.ir_al_menu.call_deferred()
				return
			if d.get("anfitrion", false):
				Game.say("[SE FUE EL ANFITRIÓN: OTRO JUGADOR TOMA SU LUGAR]", Game.COLOR_BAD)
			else:
				Game.say("[UN JUGADOR SE FUE]", Game.COLOR_BAD)
		"anfitrion":
			if CampanaRed.coop:
				return       # (ya se vuelve al menú: ver "sale")
			if str(d["id"]) == mi_id and not anfitrion:
				if _jugador() == null:   # aún en la sala de espera: solo cambia el papel
					anfitrion = true
				else:
					_volverse_anfitrion()
			elif sala.has(str(d["id"])):
				sala[str(d["id"])][1] = true
		"pong":
			ping_ms = Time.get_ticks_msec() - int(d["k"])
		"est":
			var id := str(d["id"])
			if d.has("a"):     # el anfitrión ya está en la misión
				if d.has("m"):
					_tomar_mision(d["m"])
				en_curso = true
			if d.has("p"):
				sala[id] = [int(d["p"][9]) if d["p"].size() > 9 else -1, d.has("a")]
				_recibir_jugador(id, d["p"])
			if not anfitrion:
				if d.has("a"):
					_recibir_titeres(d["a"], "aleman")
				if d.has("b"):
					_recibir_titeres(d["b"], "aliado")
				if d.has("o"):
					Objetivos.recibir(d["o"])
				if d.has("tk"):
					_recibir_tanque(d["tk"])
				if d.has("dr"):
					_ultimo_dr = int(d["dr"])
			if d.has("l"):
				for ev in d["l"]:
					_suceso(ev, id)


func _recibir_jugador(id: String, p: Array) -> void:
	var escena := _escena()
	if escena == null:
		return
	if not remotos.has(id) or not is_instance_valid(remotos[id]):
		var r := JugadorRemoto.new()
		r.id = id
		r.arma = str(p[1])
		escena.add_child(r)
		remotos[id] = r
	var r: JugadorRemoto = remotos[id]
	var esc := int(p[9]) if p.size() > 9 else 1
	r.escuadra = esc
	if anfitrion and Escuadras.actual and Escuadras.jefes[esc] != r:
		Escuadras.poner_jefe(esc, r)    # ese jugador manda su escuadra
	r.recibir({"n": p[0], "x": p[2], "y": p[3], "z": p[4], "r": p[5], "c": p[6], "v": p[7], "m": p[8]})


func _recibir_titeres(lista: Array, bando: String) -> void:
	var escena := _escena()
	if escena == null:
		return
	var ahora := Time.get_ticks_msec() / 1000.0
	for a in lista:
		var rid := int(a[0])
		var t = titeres.get(rid)
		if t == null or not is_instance_valid(t):
			t = AlemanRemoto.new()
			t.rid = rid
			t.bando = bando
			t.arma = str(a[7])
			escena.add_child(t)
			titeres[rid] = t
		if bando == "aliado":
			t.escuadra = int(a[8])
			t.puesto = int(a[9])
			t.nombre = str(a[10])
			t.health = float(a[11])
			if a.size() > 12:     # misión 2: disperso tras el salto (para el grillo)
				var f := int(a[12])
				if f & 2:
					t.set_meta("fue_perdido", true)
				if f & 1:
					t.set_meta("perdido", true)
				elif t.has_meta("perdido"):
					t.remove_meta("perdido")
					if t.escuadra == puesto:      # lo encontraste (o te encontró otro jugador)
						Game.say("[%s: %s]" % [t.nombre, Objetivos.FRASES_REUNIR[randi() % Objetivos.FRASES_REUNIR.size()]], Game.COLOR_GOOD)
		t.recibir(ahora, Vector3(a[1], a[2], a[3]), float(a[4]), POSES[int(a[5])], ANDARES[int(a[6])])


## Invitado: el tanque del anfitrión (se crea la primera vez que llega).
func _recibir_tanque(a: Array) -> void:
	var escena := _escena()
	if escena == null:
		return
	var pos := Vector3(a[0], a[1], a[2])
	var tq := Tanque.actual
	if tq == null or not is_instance_valid(tq):
		tq = Tanque.crear(escena, [pos])
		tq.titere = true
		tq.rotation.y = float(a[3])
	tq.recibir(pos, float(a[3]), int(a[4]) == 1)


## Un caído que se borra (Game._retirar_caido): se saca de las listas.
func olvidar(n: Node) -> void:
	if n.has_meta("rid"):
		soldados.erase(int(n.get_meta("rid")))
	if n is AlemanRemoto:
		titeres.erase(n.rid)


## Un títere vivo del que no llega nada hace rato: se quita (por las dudas).
func _limpiar_titeres() -> void:
	var ahora := Time.get_ticks_msec() / 1000.0
	for rid in titeres.keys():
		var t = titeres[rid]
		if not is_instance_valid(t):
			titeres.erase(rid)
		elif not t.dead and ahora - t.ultimo > 2.0:
			t.queue_free()
			titeres.erase(rid)


## Invitado: los tres puestos de mi escuadra (títeres), para el HUD.
func ranuras_mias() -> Array:
	var r := [null, null, null]
	for rid in titeres:
		var t = titeres[rid]
		if is_instance_valid(t) and t.bando == "aliado" and not t.dead \
				and t.escuadra == puesto and t.puesto >= 0 and t.puesto < 3:
			r[t.puesto] = t
	return r


func _suceso(ev: Array, de: String) -> void:
	if ev.is_empty():
		return
	match str(ev[0]):
		"t":   # disparo de otro jugador
			var desde := _vec(ev, 1)
			var hasta := _vec(ev, 4)
			# La trazadora sale del fusil del soldado que se ve (no de sus ojos),
			# más gruesa y con el disparo cercano: que se note quién dispara
			var r = remotos.get(de)
			if r and is_instance_valid(r) and r.cuerpo and r.cuerpo.boca:
				desde = r.cuerpo.boca.global_position
				r.disparo()
			Game.tracer(desde, hasta, Color(1.0, 0.85, 0.5), 2.5)
			Game.play_at("rifle", desde, 2.0)
		"s":   # tiro de un soldado de IA
			var t = titeres.get(int(ev[1]))
			var desde := _vec(ev, 2)
			var hasta := _vec(ev, 5)
			var arma := "kar98k"
			var aliado := false
			if t and is_instance_valid(t):
				arma = t.arma
				aliado = t.bando == "aliado"
				if t.cuerpo and t.cuerpo.boca:
					desde = t.cuerpo.boca.global_position
				t.disparo()
			if aliado:
				Game.tracer(desde, hasta, Color(1.0, 0.8, 0.45))
			else:
				Game.tracer(desde, hasta)
			Game.fogonazo(desde, not aliado)
			var sonido := "pistol" if arma in ["mp40", "luger", "stg44", "thompson", "colt"] else "rifle_far"
			Game.play_at(sonido, desde, -6.0 if aliado else 2.0)
			# ¿un tiro alemán pasó cerca de mi cabeza? (supresión)
			var p := _jugador()
			if p and not p.dead and not aliado:
				var dir := (hasta - desde).normalized()
				var cab := p.pos_cabeza()
				var u := clampf((cab - desde).dot(dir), 0.0, desde.distance_to(hasta))
				var cerca := (desde + dir * u).distance_to(cab)
				if cerca < 2.5 and cerca > 0.3:
					p.casi(cerca)
		"d":   # murió un soldado de IA
			var t = titeres.get(int(ev[1]))
			if t and is_instance_valid(t):
				t.morir(Vector3(ev[2], 0, ev[3]), int(ev[4]) == 1)
		"q":   # un compañero dejó de estar (un jugador tomó su lugar)
			var t = titeres.get(int(ev[1]))
			if t and is_instance_valid(t):
				t.queue_free()
			titeres.erase(int(ev[1]))
		"x":   # explosión hecha en otro celular
			Game.explode(_vec(ev, 1), float(ev[4]), float(ev[5]), true)
		"w":   # silbido de mortero
			Game.play_at("silbido", _vec(ev, 1), 2.0)
		"bg":  # bengala alemana
			var escena := _escena()
			if escena:
				Bengala.disparar(escena, _vec(ev, 1), _vec(ev, 4))
				_avisos_bengala += 1
				if _avisos_bengala <= 3:
					Game.say("[¡BENGALA! ¡CUERPO A TIERRA! (MANTÉN AGACHAR)]", Game.COLOR_BAD)
		"tt":  # tiro del tanque
			var desde := _vec(ev, 1)
			if int(ev[7]) == 1:
				Game.play_at("explosion_cerca", desde, 2.0)
				Game.fogonazo(desde, true)
			else:
				Game.tracer(desde, _vec(ev, 4))
				Game.play_at("rifle_far", desde, 0.0)
		"tg":  # un invitado le pegó al tanque
			if anfitrion and Tanque.actual and is_instance_valid(Tanque.actual):
				Tanque.actual.danar(float(ev[1]))
		"gr":  # granada alemana volando (solo se ve: la explosión llega aparte)
			var escena := _escena()
			if escena:
				var g := Grenade.new()
				g.modelo_aleman()
				g.solo_vista = true
				escena.add_child(g)
				g.global_position = _vec(ev, 1)
				g.linear_velocity = _vec(ev, 4)
				Game.play_at("throw", _vec(ev, 1), 0.0)
		"ex":  # (v0.40) llevo rato corriendo al descubierto: me tienen en la mira
			if str(ev[1]) == mi_id:
				Game.say(Enemy.AVISO_EXPUESTO, Game.COLOR_BAD)
		"m":   # aviso del anfitrión
			Game.say(str(ev[1]), Color.html(str(ev[2])))
		"h":   # un soldado de IA (del anfitrión) le pegó a alguien
			if str(ev[1]) == mi_id:
				var p := _jugador()
				if p:
					p.take_damage(float(ev[2]), _vec(ev, 3))
		"g":   # un invitado le pegó a un títere: al soldado de verdad
			if anfitrion:
				var e = soldados.get(int(ev[1]))
				if e and is_instance_valid(e) and e is Enemy and not e.dead:
					e.hit(float(ev[2]), int(ev[3]) == 1, _vec(ev, 4), _vec(ev, 7), false)
		"o":   # un invitado le dio una orden a su escuadra
			if anfitrion:
				var r = remotos.get(de)
				if r and is_instance_valid(r):
					Escuadras.dar_orden_remota(r.escuadra, str(ev[1]))
		"r":   # un invitado cayó y pide relevo
			if anfitrion:
				_dar_relevo(de)
		"R":   # respuesta del anfitrión a mi pedido de relevo
			if str(ev[1]) == mi_id:
				var p := _jugador()
				if p:
					match str(ev[2]):
						"a":
							p.tomar_lugar_en(_vec(ev, 3), str(ev[6]), str(ev[7]))
						"o":
							p.volver_desde_orilla()
						_:
							p.sin_relevo()
		"c":   # cuerpos que ya había (para el que recién entra)
			if str(ev[1]) == mi_id:
				_poner_cuerpos(ev[2])
		"fin":
			Objetivos.terminado = int(ev[1])
			FinMision.mostrar(get_tree(), int(ev[1]), int(ev[2]), int(ev[3]), int(ev[4]))


## Anfitrión: un invitado cayó. Toma al compañero vivo más cercano de su
## escuadra; si no hay, vuelve desde la orilla (gasta un refuerzo); si no
## queda nada, queda fuera hasta el fin de la misión.
var _relevos := {}             # campaña cooperativa: id del invitado → hombre de la compañía que tomó

func _dar_relevo(id: String) -> void:
	var r = remotos.get(id)
	if r == null or not is_instance_valid(r):
		return
	if _relevos.has(id):        # era un hombre de la compañía (tomó su lugar) y cayó: ese cuenta
		Compania.caido(_relevos[id])
		_relevos.erase(id)
	var a := Escuadras.relevo_de(r.escuadra, r.global_position)
	if a and a.has_meta("compania"):
		_relevos[id] = a.nombre.replace("SGT. ", "")
	if a:
		evento(["R", id, "a"] + _v(a.global_position) + [a.arma, a.nombre])
		evento(["q", rid_de(a)])
		Escuadras.quitar_de_escuadra(a)
		a.queue_free()
	elif Escuadras.gastar_refuerzo(r.escuadra):
		evento(["R", id, "o"])
		_vuelven[id] = Time.get_ticks_msec() / 1000.0 + 9.0
	else:
		evento(["R", id, "f"])


## ¿Este jugador está por volver desde la orilla? (para no dar la misión por perdida)
func vuelve_pronto(id: String) -> bool:
	return _vuelven.get(id, 0.0) > Time.get_ticks_msec() / 1000.0


func _poner_cuerpos(lista: Array) -> void:
	var escena := _escena()
	if escena == null:
		return
	for c in lista:
		var s := SoldadoSprite.new()
		s.bando = str(c[0])
		s.arma = str(c[1])
		escena.add_child(s)
		s.global_position = _vec(c, 2)
		s.rotation.y = float(c[5])
		s.morir(-s.global_basis.z, false)


## El anfitrión se fue y el servidor me eligió: los títeres pasan a ser
## soldados de verdad (con el mismo número, así los demás siguen viendo los
## mismos) y este celular corre la IA desde ahora.
func _volverse_anfitrion() -> void:
	anfitrion = true
	var escena := _escena()
	if escena == null:
		return
	var enemigos: Node = escena.get_node_or_null("Enemies")
	if enemigos == null:
		enemigos = Node3D.new()
		enemigos.name = "Enemies"
		escena.add_child(enemigos)
	var adoptar := []
	var mgs := []
	for rid in titeres.keys():
		var t = titeres[rid]
		if not is_instance_valid(t) or t.dead:
			continue
		var n: Combatiente
		if t.bando == "aleman":
			var e := Enemy.new()
			e.arma = t.arma
			e.rol = "fijo" if t.arma == "mg42" else "defensor"
			e.granadas = 0
			enemigos.add_child(e)
			n = e
			if t.arma == "mg42":
				mgs.append(e)
		else:
			var a := Aliado.new()
			a.arma = t.arma
			a.nombre = t.nombre
			a.escuadra = maxi(t.escuadra, 0)
			escena.add_child(a)
			n = a
			adoptar.append([a, a.escuadra, t.puesto])
		n.global_position = t.global_position
		n.rotation.y = t.rotation.y
		n.set_meta("rid", rid)
		soldados[rid] = n
		_rid_sig = maxi(_rid_sig, rid + 1)
		t.queue_free()
	titeres.clear()
	var esc := Escuadras.new()
	esc.adoptar = adoptar
	escena.add_child(esc)
	for id in remotos:
		var r = remotos[id]
		if is_instance_valid(r):
			Escuadras.poner_jefe(r.escuadra, r)
	var def := Defensa.new()
	def.migrada = _ultimo_dr
	escena.add_child(def)
	def.adoptar_nidos(mgs)
	Game.say("[AHORA TU CELULAR MANDA A LOS ALEMANES]", Game.COLOR_GOOD)


func _quitar(id: String) -> void:
	if remotos.has(id):
		var r = remotos[id]       # (sin tipo: puede estar ya liberado si se cambió de escena)
		if is_instance_valid(r):
			r.queue_free()
		remotos.erase(id)


## Texto para el medidor: "SALA 1234 - ANFITRIÓN - RED 85 MS - 2 JUGADORES".
static func texto() -> String:
	if actual == null:
		return ""
	if not actual._abierto:
		return "SALA %s - %s" % [Game.sala, actual.estado.to_upper()]
	var n := 1
	for id in actual.remotos:
		if is_instance_valid(actual.remotos[id]):
			n += 1
	return "SALA %s - %s - RED %s MS - %d JUGADORES" % [Game.sala, "ANFITRIÓN" if actual.anfitrion else "INVITADO",
		str(actual.ping_ms) if actual.ping_ms >= 0 else "--", n]
