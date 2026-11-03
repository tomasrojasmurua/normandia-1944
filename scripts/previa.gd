extends PanelBotones
## Pantalla previa a la misión (sección 6, paso 2), como la de Hamburger Hill:
## a la izquierda el coronel y los datos fijos de la misión (lugar, fecha,
## hora, clima, cómo se entra); a la derecha la compañía. Se tocan 3 hombres
## para llevarlos y, abajo, el arma de cada uno para cambiarla.

const CLIMA := {"nublado": "NUBLADO", "lluvia": "LLUVIA", "noche": "NOCHE DESPEJADA"}
const ENTRADA := {"playa": "LANCHA", "paracaidas": "PARACAÍDAS", "a_pie": "A PIE"}
const COLS := 3
const CARTA := Vector2(126, 36)

var _info := ""            # descripción de la especialidad del último tocado
var _confirmar_nueva := 0.0
var _retratos := {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Compania.cargar()


func _process(delta: float) -> void:
	_confirmar_nueva = maxf(_confirmar_nueva - delta, 0.0)
	queue_redraw()


func _x0() -> float:
	return maxf(size.x - COLS * (CARTA.x + 4) - 8, 236.0)


## Los que se muestran: primero los disponibles, después los heridos y al
## final los caídos (si cabe).
func _lista() -> Array:
	var ok: Array = []
	var her: Array = []
	var muertos: Array = []
	for h in Compania.hombres:
		match h["estado"]:
			"ok": ok.append(h)
			"herido": her.append(h)
			_: muertos.append(h)
	return (ok + her + muertos).slice(0, 15)


func _botones() -> Array:
	var l := []
	var x0 := _x0()
	var lista := _lista()
	for i in lista.size():
		var h: Dictionary = lista[i]
		var r := Rect2(x0 + (i % COLS) * (CARTA.x + 4), 40 + (i / COLS) * (CARTA.y + 3), CARTA.x, CARTA.y)
		l.append(["h:" + h["n"], r, h["n"], h["estado"] == "ok", ""])
	# Tu escuadra: Murphy y los 3 elegidos (tocar el arma la cambia)
	var eq := Compania.equipo()
	for k in eq.size():
		var r := Rect2(x0 + 96 + k * 98, 250, 94, 46)
		l.append(["a:" + eq[k][0], r, eq[k][0], Compania.ESPECIALIDADES[eq[k][2]]["armas"].size() > 1, ""])
	var by := size.y - 34
	l.append(["volver", Rect2(8, by, 96, 26), "VOLVER", true, ""])
	l.append(["nueva", Rect2(112, by, 116, 26), "NUEVA CAMPAÑA", true, "¿SEGURO?" if _confirmar_nueva > 0.0 else ""])
	l.append(["atacar", Rect2(size.x - 168, by, 160, 26), "¡AL ATAQUE!", Compania.equipo().size() > 0, ""])
	return l


func _pulsado(id: String) -> void:
	if id.begins_with("h:"):
		var n := id.substr(2)
		Compania.alternar(n)
		_info = Compania.ESPECIALIDADES[Compania.hombre(n)["esp"]]["info"]
		return
	if id.begins_with("a:"):
		Compania.otra_arma(id.substr(2))
		return
	match id:
		"volver":
			Game.ir_al_menu()
		"nueva":
			if _confirmar_nueva > 0.0:
				Compania.nueva()
				_confirmar_nueva = 0.0
				_info = "NUEVA CAMPAÑA: LA COMPAÑÍA ESTÁ COMPLETA"
			else:
				_confirmar_nueva = 3.0
		"atacar":
			Game.prueba_carga = false
			Game.modo_red = false
			Game.empezar_mision(Game.mision)


func _retrato(nombre: String) -> Texture2D:
	var clave := nombre.to_lower()
	if not _retratos.has(clave):
		var ruta := "res://assets/ui/retratos/retrato_%s.png" % clave
		_retratos[clave] = load(ruta) if ResourceLoader.exists(ruta) else Estilo.RETRATO_PROVISIONAL
	return _retratos[clave]


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Estilo.OLIVA_0)
	var m := Misiones.actual()
	# --- Izquierda: el coronel y la misión
	var izq := Rect2(6, 6, _x0() - 14, s.y - 46)
	Estilo.marco(self, izq, "chapa")
	Estilo.texto(self, m["nombre"], Vector2(16, 30), Estilo.AMBAR, Estilo.TAM_GRANDE)
	Estilo.texto(self, m["lugar"], Vector2(16, 43), Color(Estilo.CREMA, 0.8), Estilo.TAM, izq.end.x - 22)
	Estilo.texto(self, m["fecha"], Vector2(16, 55), Color(Estilo.CREMA, 0.8))
	var cara := Rect2(14, 62, 78, 70)
	Estilo.marco(self, cara, "hundido")
	draw_texture_rect(_retrato("coronel"), cara.grow(-2), false)
	# Datos fijos de la misión, al lado del coronel
	var hora: int = m["hora"]
	var datos := [
		["HORA", "%02d:%02d" % [hora / 60, hora % 60]],
		["CLIMA", CLIMA.get(m["clima"], str(m["clima"]).to_upper())],
		["ENTRADA", ENTRADA.get(m["entrada"], str(m["entrada"]).to_upper())],
	]
	var y := 74.0
	Estilo.texto(self, "CORONEL", Vector2(98, y), Estilo.AMBAR_CLARO)
	y += 16.0
	for d in datos:
		Estilo.texto(self, d[0], Vector2(98, y), Estilo.AMBAR_CLARO)
		Estilo.texto(self, d[1], Vector2(156, y), Estilo.CREMA)
		y += 13.0
	# Las órdenes del coronel
	y = 148.0
	for linea in m.get("briefing", []):
		Estilo.texto(self, linea, Vector2(16, y), Estilo.CREMA, Estilo.TAM, izq.end.x - 22)
		y += 12.0
	y += 8.0
	Estilo.texto(self, "FASES", Vector2(16, y), Estilo.AMBAR_CLARO)
	y += 13.0
	var fases := Misiones.fases()
	for f in fases.size():
		Estilo.texto(self, "%d. %s" % [f + 1, fases[f]["nombre"]], Vector2(24 + (f % 2) * 100, y), Estilo.CREMA)
		if f % 2 == 1:
			y += 12.0
	Estilo.texto(self, "MISIONES DE LA COMPAÑÍA: %d" % Compania.misiones_jugadas, Vector2(16, izq.end.y - 10),
		Color(Estilo.CREMA, 0.55))

	# --- Derecha: la compañía
	var x0 := _x0()
	var listos := Compania.listos().size()
	Estilo.texto(self, "LA COMPAÑÍA - ELIGE 3 HOMBRES (%d DISPONIBLES)" % listos, Vector2(x0, 32), Estilo.AMBAR)
	for b in _botones():
		var id: String = b[0]
		if id.begins_with("h:"):
			_carta(Compania.hombre(id.substr(2)), b[1], id == "h:" + _encima.substr(2) and _encima.begins_with("h:"))
	# Tu escuadra
	Estilo.texto(self, "TU ESCUADRA", Vector2(x0, 244), Estilo.AMBAR)
	var murphy := Rect2(x0, 250, 92, 46)
	_ranura(murphy, "MURPHY", "SGT - TÚ", "")
	for b in _botones():
		var id: String = b[0]
		if id.begins_with("a:"):
			var h := Compania.hombre(id.substr(2))
			var arma: String = Armas.datos(h["arma"])["name"]
			_ranura(b[1], h["n"], Compania.descripcion(h), arma + (" >" if b[3] else ""), _encima == id)
	if _info != "":
		Estilo.texto(self, _info, Vector2(x0, 312), Estilo.AMBAR_CLARO)
	for b in _botones():
		var id: String = b[0]
		if not id.begins_with("h:") and not id.begins_with("a:"):
			var estado := "normal"
			if not b[3]:
				estado = "apagado"
			elif id == _encima:
				estado = "encima"
			Estilo.boton(self, b[1], b[2], estado, b[4])


func _carta(h: Dictionary, r: Rect2, encima: bool) -> void:
	var elegido: bool = h["n"] in Compania.elegidos
	Estilo.marco(self, r, "hundido" if elegido else "chapa")
	if elegido:
		draw_rect(r.grow(-2), Estilo.AMBAR, false, 1.0)
	elif encima and h["estado"] == "ok":
		draw_rect(r.grow(-3), Color(Estilo.AMBAR, 0.15))
	var tinte := Color.WHITE
	var col := Estilo.CREMA
	var estado := Compania.descripcion(h)
	match h["estado"]:
		"herido":
			tinte = Color(1.0, 0.55, 0.5)
			col = Estilo.AMBAR
			estado = "HERIDO (%d)" % h["herido"]
		"muerto":
			tinte = Color(0.3, 0.3, 0.3)
			col = Color(Estilo.CREMA, 0.4)
			estado = "MUERTO"
	var tex := _retrato(h["n"])
	draw_texture_rect(tex, Rect2(r.position + Vector2(2, 2), Vector2(38, 32)), false, tinte)
	if h["estado"] == "muerto":
		var c := r.position + Vector2(21, 18)
		draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), Estilo.ROJO, 2.0)
		draw_line(c + Vector2(8, -8), c + Vector2(-8, 8), Estilo.ROJO, 2.0)
	Estilo.texto(self, h["n"], Vector2(r.position.x + 44, r.position.y + 15), Estilo.AMBAR_CLARO if elegido else col)
	Estilo.texto(self, estado, Vector2(r.position.x + 44, r.position.y + 28), col)


func _ranura(r: Rect2, nombre: String, linea: String, arma: String, encima := false) -> void:
	Estilo.marco(self, r, "lisa" if encima else "chapa")
	draw_texture_rect(_retrato(nombre), Rect2(r.position + Vector2(3, 3), Vector2(38, 32)), false)
	Estilo.texto(self, nombre.substr(0, 8), Vector2(r.position.x + 44, r.position.y + 13), Estilo.CREMA)
	Estilo.texto(self, linea, Vector2(r.position.x + 44, r.position.y + 25), Color(Estilo.CREMA, 0.7))
	if arma != "":
		Estilo.texto(self, arma, Vector2(r.position.x + 4, r.position.y + 43), Estilo.AMBAR_CLARO)
