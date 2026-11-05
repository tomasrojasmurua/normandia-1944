extends PanelBotones
## Pantalla previa a la misión (sección 6, paso 2), como la de Hamburger Hill:
## a la izquierda el coronel y los datos fijos de la misión (lugar, fecha,
## hora, clima, cómo se entra); a la derecha la compañía. Se tocan 3 hombres
## para llevarlos y, abajo, el arma de cada uno para cambiarla.

const CLIMA := {"nublado": "NUBLADO", "lluvia": "LLUVIA", "noche": "NOCHE DE LUNA LLENA"}
const ENTRADA := {"playa": "LANCHA", "paracaidas": "PARACAÍDAS", "planeador": "PLANEADOR", "a_pie": "A PIE"}
const COLS := 3
const CARTA := Vector2(126, 36)

var _info := ""            # descripción de la especialidad del último tocado
var _visto := ""           # hombre cuya ficha se ve a la izquierda ("" = la misión)
var _retratos := {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Compania.cargar()


func _process(_delta: float) -> void:
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
		# Los heridos y caídos no se pueden llevar, pero se puede leer su ficha
		l.append(["h:" + h["n"] if h["estado"] == "ok" else "f:" + h["n"], r, h["n"], true, ""])
	# Tu escuadra: Murphy y los 3 elegidos (tocar el arma la cambia)
	var eq := Compania.equipo()
	for k in eq.size():
		var r := Rect2(x0 + 96 + k * 98, 250, 94, 46)
		l.append(["a:" + eq[k][0], r, eq[k][0], Compania.ESPECIALIDADES[eq[k][2]]["armas"].size() > 1, ""])
	l.append(["f:MURPHY", Rect2(x0, 250, 92, 46), "MURPHY", true, ""])
	var by := size.y - 34
	# Apoyo para la misión (v0.32): se compra con suministros, solo en la campaña
	if _visto == "" and _con_compras():
		var k := 0
		for id in Campana.COMPRAS:
			var c: Dictionary = Campana.COMPRAS[id]
			var puede: bool = id in Campana.compras or Campana.disponibles() >= int(c["costo"])
			l.append(["c:" + id, Rect2(136 + k * 166, by, 160, 26), c["n"], puede, str(c["costo"])])
			k += 1
	if _visto != "":
		l.append(["mision", Rect2(maxf(_x0() - 112, 136), by, 100, 26), "LA MISIÓN", true, ""])
	l.append(["volver", Rect2(8, by, 120, 26), "AL MAPA", true, ""])
	l.append(["atacar", Rect2(size.x - 168, by, 160, 26), "¡AL ATAQUE!", Compania.equipo().size() > 0, ""])
	return l


func _pulsado(id: String) -> void:
	if id.begins_with("h:"):
		var n := id.substr(2)
		Compania.alternar(n)
		_info = Compania.ESPECIALIDADES[Compania.hombre(n)["esp"]]["info"]
		_visto = n
		return
	if id.begins_with("f:"):    # tocar a alguien de tu escuadra muestra su ficha
		_visto = id.substr(2)
		return
	if id.begins_with("a:"):
		Compania.otra_arma(id.substr(2))
		return
	if id.begins_with("c:"):
		var c := id.substr(2)
		if Campana.alternar_compra(c):
			_info = Campana.COMPRAS[c]["info"] if c in Campana.compras else ""
		return
	match id:
		"mision":
			_visto = ""
		"volver":
			Game.ir_al_mapa()
		"atacar":
			Game.prueba_carga = false
			Game.modo_red = false
			Game.empezar_mision(Game.mision)


## ¿Se puede comprar apoyo? Solo en una misión de la campaña que todavía no se ganó.
func _con_compras() -> bool:
	return Campana.activa() and Campana.estado == "en_curso" and not Campana.hecha(Game.mision) \
		and Campana.mision(Game.mision).size() > 0


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
	if _visto != "":
		_ficha(izq)
	else:
		_mision(izq, m)
	_derecha()


## La ficha del hombre tocado: retrato, de dónde es, qué hacía, por qué está
## aquí, su frase y lo que dice de él un compañero.
func _ficha(izq: Rect2) -> void:
	var h: Dictionary = Compania.hombre(_visto) if _visto != "MURPHY" else {}
	var f := Fichas.de(_visto)
	var ancho := izq.end.x - 16 - 8
	var cara := Rect2(14, 14, 78, 70)
	Estilo.marco(self, cara, "hundido")
	var tinte := Color.WHITE
	if not h.is_empty() and h["estado"] == "muerto":
		tinte = Color(0.35, 0.35, 0.35)
	draw_texture_rect(_retrato(_visto), cara.grow(-2), false, tinte)
	Estilo.texto(self, _visto, Vector2(100, 34), Estilo.AMBAR, Estilo.TAM_GRANDE)
	var linea := "SARGENTO - TÚ"
	if not h.is_empty():
		linea = "%s - %s" % [Compania.RANGOS[h["rango"]], Compania.ESPECIALIDADES[h["esp"]]["n"]]
	Estilo.texto(self, linea, Vector2(100, 48), Estilo.CREMA)
	var y := _parrafo(f["de"], 100, 62, izq.end.x - 108, Color(Estilo.CREMA, 0.75))
	if not h.is_empty():
		var estado := "%d MISIONES CON LA COMPAÑÍA" % h["misiones"]
		match h["estado"]:
			"herido": estado = "HERIDO: VUELVE EN %d MISIÓN%s" % [h["herido"], "ES" if h["herido"] > 1 else ""]
			"muerto": estado = "CAÍDO EN COMBATE"
		Estilo.texto(self, estado, Vector2(100, maxf(y, 76)), Estilo.ROJO if h["estado"] != "ok" else Estilo.AMBAR_CLARO)
	y = 100.0
	Estilo.texto(self, "ANTES DE LA GUERRA", Vector2(16, y), Estilo.AMBAR_CLARO)
	y = _parrafo(f["antes"], 16, y + 12, ancho, Estilo.CREMA) + 6
	Estilo.texto(self, "QUÉ LO TRAE A NORMANDÍA", Vector2(16, y), Estilo.AMBAR_CLARO)
	y = _parrafo(f["porque"], 16, y + 12, ancho, Estilo.CREMA) + 8
	y = _parrafo("- " + f["frase"], 16, y, ancho, Estilo.AMBAR) + 8
	var dicen: Array = f["dicen"]
	Estilo.texto(self, "LO QUE DICE %s" % dicen[0], Vector2(16, y), Estilo.AMBAR_CLARO)
	_parrafo(dicen[1], 16, y + 12, ancho, Color(Estilo.CREMA, 0.85))


## Texto en varias líneas (cortando entre palabras). Devuelve la y siguiente.
func _parrafo(t: String, x: float, y: float, ancho: float, col: Color) -> float:
	var linea := ""
	for p in t.split(" "):
		var prueba := p if linea == "" else linea + " " + p
		if Estilo.ancho_texto(prueba) > ancho and linea != "":
			Estilo.texto(self, linea, Vector2(x, y), col)
			y += 12.0
			linea = p
		else:
			linea = prueba
	if linea != "":
		Estilo.texto(self, linea, Vector2(x, y), col)
		y += 12.0
	return y


func _mision(izq: Rect2, m: Dictionary) -> void:
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
	if _con_compras():
		Estilo.texto(self, "APOYO ABAJO - SUMINISTROS: %d" % Campana.disponibles(), Vector2(16, izq.end.y - 10),
			Estilo.AMBAR_CLARO)
	else:
		Estilo.texto(self, "MISIONES DE LA COMPAÑÍA: %d" % Compania.misiones_jugadas, Vector2(16, izq.end.y - 10),
			Color(Estilo.CREMA, 0.55))
	Estilo.texto(self, "TOCA A UN HOMBRE PARA LEER SU FICHA", Vector2(16, izq.end.y - 22), Color(Estilo.AMBAR_CLARO, 0.7))


func _derecha() -> void:
	# --- Derecha: la compañía
	var x0 := _x0()
	var listos := Compania.listos().size()
	Estilo.texto(self, "LA COMPAÑÍA - ELIGE 3 HOMBRES (%d DISPONIBLES)" % listos, Vector2(x0, 32), Estilo.AMBAR)
	for b in _botones():
		var id: String = b[0]
		if id.begins_with("h:") or (id.begins_with("f:") and id != "f:MURPHY"):
			_carta(Compania.hombre(id.substr(2)), b[1], id == _encima)
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
		if id.begins_with("c:"):        # apoyo comprable: encendido si está comprado
			var comprada: bool = id.substr(2) in Campana.compras
			Estilo.boton(self, b[1], b[2], "encima" if comprada or id == _encima else ("normal" if b[3] else "apagado"), b[4])
			if comprada:
				draw_rect(b[1].grow(-2), Estilo.AMBAR, false, 1.0)
		if not id.begins_with("h:") and not id.begins_with("a:") and not id.begins_with("f:") and not id.begins_with("c:"):
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
