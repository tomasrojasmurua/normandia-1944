extends Node
class_name Red
## Prototipo del cooperativo (sección 5, paso 5): conecta este juego con los
## demás de la misma sala a través del servidor de Cloudflare (servidor/).
## Por ahora comparte solo a los jugadores: dónde están, hacia dónde miran, si
## corren o se agachan, y sus disparos. Cada celular dibuja a los demás con
## un soldado de sprites que se mueve suave entre las posiciones recibidas
## (se muestran con 120 ms de atraso para tener siempre dos posiciones entre
## las que interpolar). También mide el retraso (ping) al servidor.

## Dirección del servidor (la da Cloudflare al instalarlo). Para pruebas
## locales se puede cambiar con la variable de entorno SERVIDOR_RED.
const SERVIDOR := "wss://normandy-1944.tomasrojasmurua.workers.dev"
const ENVIOS_POR_SEGUNDO := 15.0
const ATRASO := 0.12

static var actual: Red

var mi_id := ""
var anfitrion := false
var ping_ms := -1
var estado := "conectando"     # conectando / conectado / sala llena / sin conexión
var remotos := {}              # id → JugadorRemoto

var _ws := WebSocketPeer.new()
var _t_envio := 0.0
var _t_ping := 0.0
var _abierto := false


func _ready() -> void:
	actual = self
	var base := OS.get_environment("SERVIDOR_RED") if OS.get_environment("SERVIDOR_RED") != "" else SERVIDOR
	var url := "%s/sala/%s" % [base, Game.sala]
	if _ws.connect_to_url(url) != OK:
		estado = "sin conexión"


func _exit_tree() -> void:
	_ws.close()
	if actual == self:
		actual = null


static func activo() -> bool:
	return actual != null and actual._abierto


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
				_t_envio = 1.0 / ENVIOS_POR_SEGUNDO
				_enviar_posicion()
			_t_ping -= delta
			if _t_ping <= 0.0:
				_t_ping = 1.0
				_ws.send_text('{"t":"ping","k":%d}' % Time.get_ticks_msec())
		WebSocketPeer.STATE_CLOSED:
			if _abierto or estado == "conectando":
				if estado != "sala llena":
					estado = "sin conexión"
			_abierto = false
			for id in remotos.keys():
				_quitar(id)


func _enviar_posicion() -> void:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null:
		return
	var v := Vector2(p.velocity.x, p.velocity.z).length()
	_ws.send_text(JSON.stringify({"t": "pos", "id": mi_id, "n": p.nombre, "a": p.weapons.id(),
		"x": snappedf(p.global_position.x, 0.01), "y": snappedf(p.global_position.y, 0.01),
		"z": snappedf(p.global_position.z, 0.01), "r": snappedf(p.rotation.y, 0.01),
		"c": 1 if p.crouching else 0, "v": snappedf(v, 0.1), "m": 1 if p.dead else 0}))


## Avisa a los demás de un disparo (desde, hasta), para que vean la trazadora.
static func disparo(desde: Vector3, hasta: Vector3) -> void:
	if not activo() or actual.mi_id == "":
		return
	actual._ws.send_text(JSON.stringify({"t": "tiro", "id": actual.mi_id,
		"f": [snappedf(desde.x, 0.01), snappedf(desde.y, 0.01), snappedf(desde.z, 0.01)],
		"e": [snappedf(hasta.x, 0.01), snappedf(hasta.y, 0.01), snappedf(hasta.z, 0.01)]}))


func _recibir(texto: String) -> void:
	var d: Variant = JSON.parse_string(texto)
	if not d is Dictionary:
		return
	match str(d.get("t", "")):
		"hola":
			mi_id = d["id"]
			anfitrion = d["anfitrion"]
			Game.say("[SALA %s: %s]" % [Game.sala, "ERES EL ANFITRIÓN" if anfitrion else "CONECTADO"], Game.COLOR_GOOD)
		"llena":
			estado = "sala llena"
			Game.say("[LA SALA %s ESTÁ LLENA]" % Game.sala, Game.COLOR_BAD)
		"entra":
			Game.say("[ENTRÓ UN JUGADOR]", Game.COLOR_GOOD)
		"sale":
			_quitar(str(d["id"]))
			Game.say("[UN JUGADOR SE FUE]", Game.COLOR_BAD)
		"pong":
			ping_ms = Time.get_ticks_msec() - int(d["k"])
		"pos":
			var id := str(d["id"])
			if not remotos.has(id):
				var r := JugadorRemoto.new()
				r.arma = str(d.get("a", "garand"))
				get_parent().add_child(r)
				remotos[id] = r
			remotos[id].recibir(d)
		"tiro":
			var f: Array = d["f"]
			var e: Array = d["e"]
			var desde := Vector3(f[0], f[1], f[2])
			var hasta := Vector3(e[0], e[1], e[2])
			Game.tracer(desde, hasta)
			Game.play_at("rifle_far", desde, 0.0)
			var r: JugadorRemoto = remotos.get(str(d["id"]))
			if r:
				r.disparo()


func _quitar(id: String) -> void:
	if remotos.has(id):
		var r: Node = remotos[id]
		if is_instance_valid(r):
			r.queue_free()
		remotos.erase(id)


## Texto para el medidor: "RED 85 MS · 2 JUGADORES".
static func texto() -> String:
	if actual == null:
		return ""
	if not actual._abierto:
		return "SALA %s · %s" % [Game.sala, actual.estado.to_upper()]
	return "SALA %s · %s · RED %s MS · %d JUGADORES" % [Game.sala, "ANFITRIÓN" if actual.anfitrion else "INVITADO",
		str(actual.ping_ms) if actual.ping_ms >= 0 else "--", actual.remotos.size() + 1]
