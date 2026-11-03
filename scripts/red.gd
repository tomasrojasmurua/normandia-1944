extends Node
class_name Red
## Cooperativo (sección 5, paso 5): conecta este juego con los demás de la
## misma sala a través del servidor de Cloudflare (servidor/).
##
## - Cada jugador manda dónde está, hacia dónde mira, si corre o se agacha,
##   y sus disparos. Los demás lo dibujan con un soldado de sprites que se
##   mueve suave entre las posiciones recibidas (con 120 ms de atraso).
## - El ANFITRIÓN (el primero en entrar) es el único que tiene alemanes de
##   verdad: corre su IA, los nidos de MG42, los morteros y los refuerzos.
##   En cada envío va dónde está cada alemán y los sucesos (tiros alemanes,
##   explosiones, silbidos, avisos, muertes).
## - Cada celular manda UN solo paquete por envío (12 por segundo) con todo
##   junto: su posición, sus sucesos y (el anfitrión) los alemanes. Menos
##   mensajes = menos atascos y menos gasto en el servidor.
## - Los invitados ven "títeres" (AlemanRemoto). Si les disparan, el golpe se
##   manda al anfitrión, que lo aplica al alemán de verdad. Si un alemán le
##   pega a un invitado, el anfitrión le manda el daño a ese jugador.
## - Las explosiones las calcula cada uno para su propio jugador.
##
## Red vive fuera de la escena (en la raíz) para conectarse desde el menú y
## saber quién es el anfitrión ANTES de armar la misión.

## Dirección del servidor (la da Cloudflare al instalarlo). Para pruebas
## locales se puede cambiar con la variable de entorno SERVIDOR_RED.
const SERVIDOR := "wss://normandy-1944.tomasrojasmurua.workers.dev"
const ENVIOS_POR_SEGUNDO := 12.0
const ATRASO := 0.15
const NOMBRES := ["MURPHY", "DELUCA", "HAYES", "BRENNAN"]
const POSES := ["reposo", "pie", "rodilla", "agachado"]
const ANDARES := ["", "camina", "corre"]

static var actual: Red

var mi_id := ""
var mi_nombre := "MURPHY"
var anfitrion := false
var ping_ms := -1
var estado := "conectando"     # conectando / conectado / sala llena / sin conexión
var remotos := {}              # id → JugadorRemoto
var titeres := {}              # rid → AlemanRemoto (en los invitados)
var alemanes := {}             # rid → Enemy (en el anfitrión)

var _ws := WebSocketPeer.new()
var _t_envio := 0.0
var _t_ping := 0.0
var _t_limpiar := 0.0
var _abierto := false
var _eventos: Array = []
var _rid_sig := 1


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
	return get_tree().current_scene


## El paquete de cada envío: mi posición, mis sucesos y (anfitrión) los alemanes.
func _enviar_paquete() -> void:
	var paq := {"t": "est", "id": mi_id}
	var p := _jugador()
	if p:
		var v := Vector2(p.velocity.x, p.velocity.z).length()
		paq["p"] = [p.nombre, p.weapons.id(), snappedf(p.global_position.x, 0.01),
			snappedf(p.global_position.y, 0.01), snappedf(p.global_position.z, 0.01),
			snappedf(p.rotation.y, 0.01), 1 if p.crouching else 0, snappedf(v, 0.1), 1 if p.dead else 0]
	if not _eventos.is_empty():
		paq["l"] = _eventos
		_eventos = []
	if anfitrion and p:
		paq["a"] = _lista_alemanes()
	if paq.size() > 2:
		_ws.send_text(JSON.stringify(paq))


# ================================================================ anfitrión → invitados

## Número de un alemán en la red (se lo da la primera vez que se lo pide).
func rid_de(e: Node) -> int:
	if not e.has_meta("rid"):
		e.set_meta("rid", _rid_sig)
		alemanes[_rid_sig] = e
		_rid_sig += 1
	return e.get_meta("rid")


func _lista_alemanes() -> Array:
	var lista := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e is Enemy or e.dead or e.cuerpo == null:
			continue
		var p: Vector3 = e.global_position
		lista.append([rid_de(e), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
			snappedf(e.rotation.y, 0.01), maxi(POSES.find(e.cuerpo.pose), 0),
			maxi(ANDARES.find(e.cuerpo.andar), 0), e.arma])
	return lista


## Un suceso para los demás (sale en el próximo envío, junto con otros).
static func evento(ev: Array) -> void:
	if activo():
		actual._eventos.append(ev)


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


## Aviso en el HUD de todos (si soy el anfitrión) o solo en el mío.
static func anunciar(texto: String, color: Color = Game.COLOR_INFO) -> void:
	Game.say(texto, color)
	if es_anfitrion():
		evento(["m", texto, color.to_html(false)])


static func tiro_aleman(e: Node, desde: Vector3, hasta: Vector3) -> void:
	if es_anfitrion():
		evento(["s", actual.rid_de(e)] + _v(desde) + _v(hasta))


static func aleman_muerto(e: Node, dir: Vector3, cabeza: bool) -> void:
	if es_anfitrion():
		evento(["d", actual.rid_de(e), snappedf(dir.x, 0.01), snappedf(dir.z, 0.01), 1 if cabeza else 0])


static func silbido(pos: Vector3) -> void:
	if es_anfitrion():
		evento(["w"] + _v(pos))


## Una explosión hecha aquí (granada, cohete, mortero): los demás la ven y
## cada uno calcula el daño a su propio jugador.
static func explosion(pos: Vector3, radio: float, dano: float) -> void:
	evento(["x"] + _v(pos) + [radio, dano])


## Un alemán de verdad (en el anfitrión) le pegó a otro jugador.
static func dano(id: String, cantidad: float, desde: Vector3) -> void:
	evento(["h", id, cantidad] + _v(desde))


## Le pegué a un títere: que el anfitrión se lo aplique al alemán de verdad.
static func golpe(rid: int, cantidad: float, cabeza: bool, pos: Vector3, dir: Vector3) -> void:
	evento(["g", rid, snappedf(cantidad, 0.1), 1 if cabeza else 0] + _v(pos) + _v(dir))


## Avisa a los demás de un disparo mío (desde, hasta), para que vean la trazadora.
static func disparo(desde: Vector3, hasta: Vector3) -> void:
	evento(["t"] + _v(desde) + _v(hasta))


# ================================================================ recibir

func _recibir(texto: String) -> void:
	var d: Variant = JSON.parse_string(texto)
	if not d is Dictionary:
		return
	match str(d.get("t", "")):
		"hola":
			mi_id = d["id"]
			anfitrion = d["anfitrion"]
			# Cada jugador con su propio soldado (y su cara), según el orden de llegada
			mi_nombre = NOMBRES[mini((d["otros"] as Array).size(), NOMBRES.size() - 1)]
		"llena":
			estado = "sala llena"
		"entra":
			Game.say("[ENTRÓ UN JUGADOR]", Game.COLOR_GOOD)
		"sale":
			_quitar(str(d["id"]))
			if d.get("anfitrion", false) and not anfitrion:
				Game.say("[EL ANFITRIÓN SE FUE: LOS ALEMANES QUEDAN QUIETOS]", Game.COLOR_BAD)
			else:
				Game.say("[UN JUGADOR SE FUE]", Game.COLOR_BAD)
		"pong":
			ping_ms = Time.get_ticks_msec() - int(d["k"])
		"est":
			var id := str(d["id"])
			if d.has("p"):
				_recibir_jugador(id, d["p"])
			if d.has("a") and not anfitrion:
				_recibir_alemanes(d["a"])
			if d.has("l"):
				for ev in d["l"]:
					_suceso(ev, id)


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _recibir_jugador(id: String, p: Array) -> void:
	var escena := _escena()
	if escena == null or escena.name != "Main":
		return
	if not remotos.has(id) or not is_instance_valid(remotos[id]):
		var r := JugadorRemoto.new()
		r.id = id
		r.arma = str(p[1])
		escena.add_child(r)
		remotos[id] = r
	remotos[id].recibir({"n": p[0], "x": p[2], "y": p[3], "z": p[4], "r": p[5], "c": p[6], "v": p[7], "m": p[8]})


func _recibir_alemanes(lista: Array) -> void:
	var escena := _escena()
	if escena == null or escena.name != "Main":
		return
	var ahora := Time.get_ticks_msec() / 1000.0
	for a in lista:
		var rid := int(a[0])
		var t = titeres.get(rid)
		if t == null or not is_instance_valid(t):
			t = AlemanRemoto.new()
			t.rid = rid
			t.arma = str(a[7])
			escena.add_child(t)
			titeres[rid] = t
		t.recibir(ahora, Vector3(a[1], a[2], a[3]), float(a[4]), POSES[int(a[5])], ANDARES[int(a[6])])


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


func _suceso(ev: Array, de: String) -> void:
	if ev.is_empty():
		return
	match str(ev[0]):
		"t":   # disparo de otro jugador
			var desde := Vector3(ev[1], ev[2], ev[3])
			var hasta := Vector3(ev[4], ev[5], ev[6])
			# La trazadora sale del fusil del soldado que se ve (no de sus ojos),
			# más gruesa y con el disparo cercano: que se note quién dispara
			var r = remotos.get(de)
			if r and is_instance_valid(r) and r.cuerpo and r.cuerpo.boca:
				desde = r.cuerpo.boca.global_position
				r.disparo()
			Game.tracer(desde, hasta, Color(1.0, 0.85, 0.5), 2.5)
			Game.play_at("rifle", desde, 2.0)
		"h":   # un alemán (del anfitrión) le pegó a alguien
			if str(ev[1]) == mi_id:
				var p := _jugador()
				if p:
					p.take_damage(float(ev[2]), Vector3(ev[3], ev[4], ev[5]))
		"g":   # un invitado le pegó a un títere: al alemán de verdad
			if anfitrion:
				var e = alemanes.get(int(ev[1]))
				if e and is_instance_valid(e) and not e.dead:
					e.hit(float(ev[2]), int(ev[3]) == 1, Vector3(ev[4], ev[5], ev[6]),
						Vector3(ev[7], ev[8], ev[9]), false)
		"s":   # tiro alemán
			var t = titeres.get(int(ev[1]))
			var desde := Vector3(ev[2], ev[3], ev[4])
			var hasta := Vector3(ev[5], ev[6], ev[7])
			var arma := "kar98k"
			if t and is_instance_valid(t):
				arma = t.arma
				if t.cuerpo and t.cuerpo.boca:
					desde = t.cuerpo.boca.global_position
				t.disparo()
			Game.tracer(desde, hasta)
			var sonido := "pistol" if arma in ["mp40", "luger", "stg44"] else "rifle_far"
			Game.play_at(sonido, desde, 2.0 if arma != "mp40" else 0.0)
			# ¿pasó cerca de mi cabeza? (supresión)
			var p := _jugador()
			if p and not p.dead:
				var dir := (hasta - desde).normalized()
				var cab := p.pos_cabeza()
				var u := clampf((cab - desde).dot(dir), 0.0, desde.distance_to(hasta))
				var cerca := (desde + dir * u).distance_to(cab)
				if cerca < 2.5 and cerca > 0.3:
					p.casi(cerca)
		"d":   # murió un alemán
			var t = titeres.get(int(ev[1]))
			if t and is_instance_valid(t):
				t.morir(Vector3(ev[2], 0, ev[3]), int(ev[4]) == 1)
		"x":   # explosión hecha en otro celular
			Game.explode(Vector3(ev[1], ev[2], ev[3]), float(ev[4]), float(ev[5]), true)
		"w":   # silbido de mortero
			Game.play_at("silbido", Vector3(ev[1], ev[2], ev[3]), 2.0)
		"m":   # aviso del anfitrión
			Game.say(str(ev[1]), Color.html(str(ev[2])))


func _quitar(id: String) -> void:
	if remotos.has(id):
		var r: Node = remotos[id]
		if is_instance_valid(r):
			r.queue_free()
		remotos.erase(id)


## Texto para el medidor: "SALA 1234 · ANFITRIÓN · RED 85 MS · 2 JUGADORES".
static func texto() -> String:
	if actual == null:
		return ""
	if not actual._abierto:
		return "SALA %s · %s" % [Game.sala, actual.estado.to_upper()]
	var n := 1
	for id in actual.remotos:
		if is_instance_valid(actual.remotos[id]):
			n += 1
	return "SALA %s · %s · RED %s MS · %d JUGADORES" % [Game.sala, "ANFITRIÓN" if actual.anfitrion else "INVITADO",
		str(actual.ping_ms) if actual.ping_ms >= 0 else "--", n]
