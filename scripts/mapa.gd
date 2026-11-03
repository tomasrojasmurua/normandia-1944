extends PanelBotones
## Mapa de la campaña (sección 6, paso 3), al estilo de Hamburger Hill:
## arriba la fecha y los recursos; a la izquierda el sector americano de
## Normandía con las misiones; a la derecha el coronel con sus órdenes (1 o 2
## misiones), DESCANSAR, LA COMPAÑÍA (reclutar), el DIARIO y el MENÚ.
## Entre misiones aparece el diario THE NORMANDY DISPATCH.
##
## El mapa es provisional (dibujado con código) hasta que llegue la imagen de
## ChatGPT: si existe res://assets/campana/mapa.png se dibuja esa en su lugar.
## Las fotos del diario: res://assets/campana/foto_<clave>.png (si faltan, un
## recuadro "FOTO PENDIENTE").

# --- Proyección: longitud/latitud -> píxeles del recuadro del mapa
const LON0 := -2.0
const LON1 := -0.70
const LAT_ARRIBA := 49.80
const COS_LAT := 0.656        # un grado de longitud mide 0,656 de uno de latitud aquí

## Costa del sector americano (Cotentin y Calvados), sentido antihorario.
const COSTA := [
	Vector2(-1.56, 48.70), Vector2(-1.57, 49.03), Vector2(-1.60, 49.20), Vector2(-1.63, 49.28),
	Vector2(-1.72, 49.33), Vector2(-1.79, 49.37), Vector2(-1.85, 49.48), Vector2(-1.88, 49.55),
	Vector2(-1.86, 49.63), Vector2(-1.95, 49.71), Vector2(-1.85, 49.725), Vector2(-1.72, 49.68),
	Vector2(-1.62, 49.65), Vector2(-1.45, 49.69), Vector2(-1.27, 49.70), Vector2(-1.24, 49.60),
	Vector2(-1.28, 49.55), Vector2(-1.30, 49.51), Vector2(-1.22, 49.45), Vector2(-1.18, 49.42),
	Vector2(-1.17, 49.37), Vector2(-1.14, 49.345), Vector2(-1.10, 49.355), Vector2(-1.07, 49.38),
	Vector2(-1.03, 49.39), Vector2(-0.99, 49.40), Vector2(-0.95, 49.39), Vector2(-0.90, 49.38),
	Vector2(-0.80, 49.365), Vector2(-0.70, 49.35), Vector2(-0.55, 49.34), Vector2(-0.55, 48.70),
]
const RIOS := [
	[Vector2(-1.55, 49.56), Vector2(-1.53, 49.42), Vector2(-1.45, 49.35), Vector2(-1.33, 49.31),
		Vector2(-1.25, 49.31), Vector2(-1.17, 49.35)],                                   # Douve
	[Vector2(-1.43, 49.51), Vector2(-1.38, 49.43), Vector2(-1.36, 49.38), Vector2(-1.38, 49.33)],   # Merderet
	[Vector2(-1.07, 48.90), Vector2(-1.09, 49.11), Vector2(-1.10, 49.24), Vector2(-1.12, 49.32),
		Vector2(-1.13, 49.35)],                                                          # Vire
]
const PANTANOS := [Vector2(-1.37, 49.37), Vector2(-1.27, 49.295), Vector2(-1.45, 49.33)]
## Pueblos de referencia (solo nombre): [nombre, posición]
const PUEBLOS := [["ISIGNY", Vector2(-1.10, 49.32), Vector2(-14, 12)],
	["BAYEUX", Vector2(-0.70, 49.28), Vector2(-46, 4)]]
## Dónde va el nombre de cada misión respecto a su marca (para que no se tapen).
const ETIQUETA := {
	"omaha": ["OMAHA", Vector2(-14, 22)], "planeador": ["STE-MÈRE-ÉGLISE", Vector2(-72, -10)],
	"pointe": ["POINTE DU HOC", Vector2(-30, -12)], "lafiere": ["LA FIÈRE", Vector2(-62, 14)],
	"carentan": ["CARENTAN", Vector2(-28, 22)], "tormenta": ["MONTEBOURG", Vector2(-80, 4)],
	"cherbourg": ["CHERBOURG", Vector2(-30, 22)], "colina192": ["COLINA 192", Vector2(10, -6)],
	"saintlo": ["SAINT-LÔ", Vector2(-20, -10)], "cobra": ["COBRA", Vector2(-40, 18)],
}
const PAPEL := Color("#d8d0b0")
const TINTA := Color("#1d1b14")
const CLIMA_ICONO := {"NOCHE": "LUNA", "TORMENTA": "LLUVIA"}

var pantalla := "mapa"      # "mapa" o "compania"
var _sel := ""              # misión elegida en el panel
var _info := ""
var _t := 0.0
var _confirmar_nueva := 0.0
var _releer := false        # mostrando el diario anterior (botón DIARIO)
var _retratos := {}
var _fotos := {}
var _fondo: Control
var _capa: Control
var _mapa_img: Texture2D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Campana.cargar()
	var ruta := "res://assets/campana/mapa.png"
	_mapa_img = load(ruta) if ResourceLoader.exists(ruta) else null
	_fondo = Control.new()
	_capa = Control.new()
	for c in [_fondo, _capa]:
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
	_fondo.draw.connect(_dibujar_fondo)
	_capa.draw.connect(_dibujar_capa)
	resized.connect(func() -> void: _fondo.queue_redraw())
	_elegir_por_defecto()


func _process(delta: float) -> void:
	_t += delta
	_confirmar_nueva = maxf(_confirmar_nueva - delta, 0.0)
	_capa.queue_redraw()


func _ids_ofrecidas() -> Array:
	return Campana.ofrecidas().map(func(m: Dictionary) -> String: return m["id"])


func _elegir_por_defecto() -> void:
	var ids := _ids_ofrecidas()
	if not _sel in ids:
		_sel = ids[0] if not ids.is_empty() else ""


# ================================================================ geometría

func _rect_mapa() -> Rect2:
	return Rect2(4, 30, 330, size.y - 34)


func _x_panel() -> float:
	return _rect_mapa().end.x + 4


func _k() -> float:
	return _rect_mapa().size.x / (LON1 - LON0)


func _p(lonlat: Vector2) -> Vector2:
	var r := _rect_mapa()
	return Vector2(r.position.x + (lonlat.x - LON0) * _k(),
		r.position.y + (LAT_ARRIBA - lonlat.y) * _k() / COS_LAT).round()


func _modal() -> String:
	if _releer and not Campana.ultimo_diario.is_empty():
		return "diario"
	if not Campana.siguiente_edicion().is_empty():
		return "diario"
	if Campana.presion != "" and Campana.estado == "en_curso":
		return "presion"
	return ""


# ================================================================ botones

func _botones() -> Array:
	var m := _modal()
	if m == "diario":
		return [["leer", Rect2(Vector2.ZERO, size), "", true, ""]]
	if m == "presion":
		var c := size / 2.0
		return [
			["pagar", Rect2(c.x - 156, c.y + 34, 152, 26), "MANDAR AYUDA", Campana.suministros >= Campana.PRESION_COSTO,
				"-%d" % Campana.PRESION_COSTO],
			["aguantar", Rect2(c.x + 4, c.y + 34, 152, 26), "AGUANTAR", true, "-%d APOYO" % Campana.PRESION_APOYO],
		]
	var x := _x_panel() + 6
	var w := size.x - x - 10
	var mitad := (w - 6) / 2.0
	var h := size.y
	var l := []
	if pantalla == "compania":
		var y := 74.0
		for esp in Compania.ESPECIALIDADES:
			var costo: int = Campana.COSTO_RECLUTA[esp]
			l.append(["r:" + esp, Rect2(x + w - 124, y - 12, 124, 20), "RECLUTAR", Campana.suministros >= costo
				and Compania.puede_reclutar() and Campana.estado == "en_curso", str(costo)])
			y += 24.0
		l.append(["nueva", Rect2(x, h - 62, w, 26), "NUEVA CAMPAÑA", true, "¿SEGURO? TOCA OTRA VEZ" if _confirmar_nueva > 0.0 else ""])
		l.append(["volver", Rect2(x, h - 32, w, 26), "VOLVER AL MAPA", true, ""])
		return l
	# Pantalla del mapa: las misiones del mapa se pueden tocar
	for mi in Campana.LISTA:
		l.append(["z:" + mi["id"], Rect2(_p(mi["pos"]) - Vector2(13, 9), Vector2(26, 18)), "", true, ""])
	if Campana.estado != "en_curso":
		l.append(["nueva", Rect2(x, h - 94, w, 26), "NUEVA CAMPAÑA", true, "¿SEGURO? TOCA OTRA VEZ" if _confirmar_nueva > 0.0 else ""])
	else:
		var o := Campana.ofrecidas()
		for i in o.size():
			l.append(["m:" + o[i]["id"], _rect_carta(i), "", true, ""])
		if _sel != "":
			if Campana.construida(_sel):
				l.append(["ir", Rect2(x, h - 94, w, 26), "IR A LA MISIÓN", true, ""])
			else:
				l.append(["otra", Rect2(x, h - 94, w, 26), "OTRA UNIDAD SE ENCARGA", true, "EN PREPARACIÓN"])
		l.append(["descansar", Rect2(x, h - 62, mitad, 26), "DESCANSAR", true, ""])
	l.append(["compania", Rect2(x + mitad + 6, h - 62, mitad, 26), "COMPAÑÍA", true, ""])
	l.append(["diario", Rect2(x, h - 32, mitad, 26), "DIARIO", not Campana.ultimo_diario.is_empty(), ""])
	l.append(["menu", Rect2(x + mitad + 6, h - 32, mitad, 26), "MENÚ", true, ""])
	return l


func _rect_carta(i: int) -> Rect2:
	var x := _x_panel() + 6
	return Rect2(x, 120 + i * 54, size.x - x - 10, 50)


func _pulsado(id: String) -> void:
	_info = ""
	if id.begins_with("z:"):
		var mid := id.substr(2)
		var m := Campana.mision(mid)
		if _ids_ofrecidas().has(mid):
			_sel = mid
		elif Campana.hecha(mid):
			_info = "%s: TOMADA. DA %d DE SUMINISTROS POR TURNO." % [m["n"], m["valor"]]
		else:
			_info = "%s: %s (ETAPA %d)." % [m["n"], Campana.fecha_mision(m), m["etapa"] + 1]
		return
	if id.begins_with("m:"):
		_sel = id.substr(2)
		return
	if id.begins_with("r:"):
		var esp := id.substr(2)
		var antes := Compania.vivos().size()
		if Campana.reclutar(esp) and Compania.vivos().size() > antes:
			var h: Dictionary = Compania.hombres[-1]
			_info = "LLEGA %s (%s)" % [h["n"], Compania.ESPECIALIDADES[esp]["n"]]
		return
	match id:
		"leer":
			if _releer:
				_releer = false
			else:
				Campana.leida()
				_elegir_por_defecto()
		"pagar":
			Campana.resolver_presion(true)
		"aguantar":
			Campana.resolver_presion(false)
		"ir":
			Campana.elegir(_sel)
			Game.ir_a_previa()
		"otra":
			Campana.otra_unidad(_sel)
			_elegir_por_defecto()
		"descansar":
			Campana.descansar()
			_elegir_por_defecto()
		"compania":
			pantalla = "compania"
		"volver":
			pantalla = "mapa"
		"diario":
			_releer = true
		"menu":
			Game.ir_al_menu()
		"nueva":
			if _confirmar_nueva > 0.0:
				Campana.nueva()
				_confirmar_nueva = 0.0
				pantalla = "mapa"
				_sel = ""
				_elegir_por_defecto()
			else:
				_confirmar_nueva = 3.0


# ================================================================ dibujo

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Estilo.OLIVA_0)


## El mapa fijo: mar, tierra, ríos, pantanos y cuadrícula (se dibuja una vez).
func _dibujar_fondo() -> void:
	var ci := _fondo
	var r := _rect_mapa()
	Estilo.marco(ci, r.grow(2), "hundido")
	if _mapa_img:
		ci.draw_texture_rect(_mapa_img, r, false)
		return
	ci.draw_rect(r, Color("#22313a"))
	# Olas: rayitas horizontales en el mar
	var rng := RandomNumberGenerator.new()
	rng.seed = 1944
	for i in 260:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x - 4), rng.randf_range(r.position.y, r.end.y))
		ci.draw_rect(Rect2(p.floor(), Vector2(3, 1)), Color("#2c3f49"))
	# Tierra (recortada al recuadro)
	var costa := PackedVector2Array(COSTA.map(func(v: Vector2) -> Vector2: return _p(v)))
	var caja := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var tierra := Geometry2D.intersect_polygons(costa, caja)
	for poli in tierra:
		ci.draw_colored_polygon(poli, Color("#4a5532"))
	# Textura de campos: manchas de colores de campo dentro de la tierra
	var campos := [Color("#55603a"), Color("#414b2c"), Color("#5c6640"), Color("#3c4528")]
	for i in 900:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y)).floor()
		for poli in tierra:
			if Geometry2D.is_point_in_polygon(p, poli):
				ci.draw_rect(Rect2(p, Vector2(rng.randi_range(3, 7), rng.randi_range(2, 5))), campos[i % campos.size()])
				break
	# Pantanos inundados (la Douve y el Merderet)
	for pt in PANTANOS:
		var c := _p(pt)
		for j in 14:
			var q := c + Vector2(rng.randf_range(-12, 12), rng.randf_range(-5, 5))
			ci.draw_rect(Rect2(q.floor(), Vector2(rng.randi_range(3, 6), 2)), Color("#3e5a5a"))
	# Ríos
	for rio in RIOS:
		var pts := PackedVector2Array(rio.map(func(v: Vector2) -> Vector2: return _p(v)))
		ci.draw_polyline(pts, Color("#34505a"), 2.0)
	# Costa
	for poli in tierra:
		var borde := Array(poli)
		borde.append(poli[0])
		ci.draw_polyline(PackedVector2Array(borde), Color("#7d8a5c"), 1.0)
	# Cuadrícula de carta militar
	for i in range(1, 7):
		var gx := r.position.x + r.size.x * i / 7.0
		ci.draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(Estilo.CREMA, 0.06))
	for i in range(1, 7):
		var gy := r.position.y + r.size.y * i / 7.0
		ci.draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(Estilo.CREMA, 0.06))
	# Nombres fijos
	Estilo.texto(ci, "CANAL DE LA MANCHA", _p(Vector2(-1.22, 49.76)), Color("#5f7a85"))
	Estilo.texto(ci, "BAHÍA DEL SENA", _p(Vector2(-1.10, 49.55)), Color("#5f7a85"))
	for pu in PUEBLOS:
		var c := _p(pu[1])
		ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), Color(Estilo.CREMA, 0.5))
		Estilo.texto(ci, pu[0], c + pu[2], Color(Estilo.CREMA, 0.45))
	Estilo.texto(ci, "SECTOR BRITÁNICO >", Vector2(r.end.x - 116, _p(Vector2(-0.7, 49.205)).y), Color(Estilo.CREMA, 0.35))
	Estilo.texto(ci, "MAPA PROVISIONAL", Vector2(r.position.x + 6, r.end.y - 6), Color(Estilo.CREMA, 0.3))


## Todo lo que cambia: barra de arriba, marcas, panel, diario y diálogos.
func _dibujar_capa() -> void:
	var ci := _capa
	_barra(ci)
	_marcas(ci)
	_panel(ci)
	match _modal():
		"diario":
			_diario(ci, Campana.ultimo_diario if _releer else Campana.siguiente_edicion())
		"presion":
			_presion(ci)


func _barra(ci: CanvasItem) -> void:
	var r := Rect2(4, 4, size.x - 8, 24)
	Estilo.marco(ci, r, "chapa")
	var y := 20.0
	Estilo.texto(ci, Campana.fecha_texto(Campana.dia), Vector2(12, y), Estilo.AMBAR_CLARO)
	Estilo.texto(ci, "SUMINISTROS", Vector2(160, y), Color(Estilo.CREMA, 0.7))
	Estilo.numero(ci, str(Campana.suministros), Vector2(240, 9), Estilo.DIG_MEDIANO, 4)
	Estilo.texto(ci, "APOYO", Vector2(288, y), Color(Estilo.CREMA, 0.7))
	var barra := Rect2(328, 10, 100, 12)
	Estilo.marco(ci, barra, "hundido")
	var f := clampf(float(Campana.apoyo) / Campana.APOYO_MAX, 0.0, 1.0)
	var col := Estilo.VERDE_LED if Campana.apoyo > 60 else (Estilo.AMBAR if Campana.apoyo > 30 else Estilo.ROJO)
	var segs := int(round(f * 12))
	for i in segs:
		ci.draw_rect(Rect2(barra.position.x + 2 + i * 8, barra.position.y + 2, 7, 8), col)
	Estilo.texto(ci, str(Campana.apoyo), Vector2(434, y), col)
	var m := Campana.mision(_sel)
	if not m.is_empty():
		Estilo.texto(ci, "CLIMA " + m["clima"], Vector2(470, y), Color(Estilo.CREMA, 0.8))
	var t := "TURNO %d" % (Campana.turnos + 1)
	Estilo.texto(ci, t, Vector2(r.end.x - 8 - Estilo.ancho_texto(t), y), Color(Estilo.CREMA, 0.6))


func _marcas(ci: CanvasItem) -> void:
	var ofrecidas := _ids_ofrecidas()
	var etapa := Campana.etapa()
	for m in Campana.LISTA:
		var c := _p(m["pos"])
		var hecha := Campana.hecha(m["id"])
		var ofrecida := ofrecidas.has(m["id"])
		var futura: bool = not hecha and m["etapa"] > etapa
		var caja := Rect2(c - Vector2(11, 6), Vector2(22, 12))
		var fondo := Color("#2e4a22") if hecha else (Color("#5a1a12") if not futura else Color("#3a1a14"))
		ci.draw_rect(caja.grow(1), Estilo.NEGRO)
		ci.draw_rect(caja, fondo)
		var borde := Estilo.VERDE_LED if hecha else Color(Estilo.ROJO, 0.5 if futura else 1.0)
		if ofrecida:
			borde = Estilo.AMBAR_CLARO if fmod(_t, 0.8) < 0.5 else Estilo.AMBAR
		ci.draw_rect(caja, borde, false, 1.0)
		# Fuerza alemana: puntitos (verdes si ya es nuestra)
		var n := 3 if hecha else mini(Campana.fuerza(m["id"]), 5)
		var x0 := c.x - (n * 4 - 1) / 2.0
		for i in n:
			ci.draw_rect(Rect2(Vector2(x0 + i * 4, c.y - 1).floor(), Vector2(3, 3)),
				Estilo.VERDE_LED if hecha else Color(Estilo.CREMA, 0.5 if futura else 1.0))
		var et: Array = ETIQUETA.get(m["id"], [m["n"], Vector2(-20, 20)])
		var col := Estilo.VERDE_LED if hecha else (Estilo.AMBAR_CLARO if ofrecida else Color(Estilo.CREMA, 0.45 if futura else 0.8))
		Estilo.texto(ci, et[0], c + et[1], col)
		if m["id"] == _sel and pantalla == "mapa":
			var g := caja.grow(5)
			for esq in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
				var sx := 1.0 if esq.x < c.x else -1.0
				var sy := 1.0 if esq.y < c.y else -1.0
				ci.draw_line(esq, esq + Vector2(4 * sx, 0), Estilo.AMBAR_CLARO)
				ci.draw_line(esq, esq + Vector2(0, 4 * sy), Estilo.AMBAR_CLARO)


func _panel(ci: CanvasItem) -> void:
	var x := _x_panel()
	var r := Rect2(x, 30, size.x - x - 4, size.y - 34)
	Estilo.marco(ci, r, "chapa")
	var tx := x + 8
	var ancho := r.size.x - 16
	if pantalla == "compania":
		_panel_compania(ci, tx, ancho)
		_botones_panel(ci)
		return
	var e := Campana.etapa()
	var titulo := "CAMPAÑA TERMINADA" if e >= Campana.ETAPAS.size() else "ETAPA %d - %s" % [e + 1, Campana.ETAPAS[e]]
	Estilo.texto(ci, titulo, Vector2(tx, 44), Estilo.AMBAR)
	var cara := Rect2(tx, 50, 64, 56)
	Estilo.marco(ci, cara, "hundido")
	ci.draw_texture_rect(_retrato("coronel"), cara.grow(-2), false)
	var dichos: Array
	var o := Campana.ofrecidas()
	match Campana.estado:
		"relevado":
			dichos = ["SARGENTO, EL MANDO LO RELEVA.", "ENTREGUE LA COMPAÑÍA."]
		"victoria":
			dichos = ["BIEN HECHO, SARGENTO.", "NORMANDÍA ES NUESTRA."]
		_:
			dichos = ["¿QUÉ HACEMOS, SARGENTO?", "ELIJA UNA. LA OTRA ESPERA", "Y LOS ALEMANES SE REFUERZAN."] \
				if o.size() > 1 else ["SARGENTO, SU PRÓXIMA ORDEN."]
	Estilo.texto(ci, "CORONEL", Vector2(tx + 70, 62), Estilo.AMBAR_CLARO)
	var y := 76.0
	for d in dichos:
		Estilo.texto(ci, d, Vector2(tx + 70, y), Estilo.CREMA, Estilo.TAM, ancho - 70)
		y += 12.0
	# Las misiones ofrecidas
	for i in o.size():
		_carta(ci, o[i], _rect_carta(i))
	# Resumen de la elegida (o el último aviso)
	var texto := _info
	var col := Estilo.AMBAR_CLARO
	if texto == "" and _sel != "" and Campana.estado == "en_curso":
		texto = Campana.mision(_sel)["resumen"]
		col = Color(Estilo.CREMA, 0.85)
	var ly := 120.0 + o.size() * 54 + 10
	for linea in _envolver(texto, ancho).slice(0, 3):
		Estilo.texto(ci, linea, Vector2(tx, ly), col)
		ly += 12.0
	_botones_panel(ci)


func _carta(ci: CanvasItem, m: Dictionary, r: Rect2) -> void:
	var sel: bool = m["id"] == _sel
	Estilo.marco(ci, r, "lisa" if sel else "chapa")
	if sel:
		ci.draw_rect(r.grow(-2), Estilo.AMBAR, false, 1.0)
	var x := r.position.x + 8
	Estilo.texto(ci, m["n"], Vector2(x, r.position.y + 14), Estilo.AMBAR_CLARO if sel else Estilo.CREMA)
	Estilo.texto(ci, "%s - %s" % [m["sub"], Campana.fecha_mision(m)], Vector2(x, r.position.y + 27),
		Color(Estilo.CREMA, 0.7), Estilo.TAM, r.size.x - 16)
	Estilo.texto(ci, "FUERZA", Vector2(x, r.position.y + 41), Color(Estilo.CREMA, 0.6))
	for i in Campana.fuerza(m["id"]):
		ci.draw_rect(Rect2(x + 46 + i * 6, r.position.y + 34, 4, 4), Estilo.ROJO)
	var premio := "+%d SUM." % (m["premio"] if Campana.construida(m["id"]) else m["premio"] / 2)
	Estilo.texto(ci, premio, Vector2(x + 84, r.position.y + 41), Estilo.VERDE_LED)
	var nota := ""
	if not Campana.construida(m["id"]):
		nota = "EN PREPARACIÓN"
	elif int(Campana.refuerzo.get(m["id"], 0)) > 0:
		nota = "REFORZADA"
	if nota != "":
		Estilo.texto(ci, nota, Vector2(r.end.x - 8 - Estilo.ancho_texto(nota), r.position.y + 14), Estilo.AMBAR)


func _panel_compania(ci: CanvasItem, tx: float, ancho: float) -> void:
	Estilo.texto(ci, "LA COMPAÑÍA", Vector2(tx, 44), Estilo.AMBAR)
	var vivos := Compania.vivos().size()
	var muertos := Compania.hombres.size() - vivos
	Estilo.texto(ci, "HOMBRES %d/%d - CAÍDOS %d" % [vivos, Compania.MAXIMO, muertos], Vector2(tx, 58), Color(Estilo.CREMA, 0.75))
	var y := 74.0
	for esp in Compania.ESPECIALIDADES:
		var listos := 0
		var heridos := 0
		for h in Compania.hombres:
			if h["esp"] == esp:
				if h["estado"] == "ok":
					listos += 1
				elif h["estado"] == "herido":
					heridos += 1
		Estilo.texto(ci, Compania.ESPECIALIDADES[esp]["n"], Vector2(tx, y + 2), Estilo.CREMA)
		var cuenta := "%d" % listos + (" (+%d HER.)" % heridos if heridos > 0 else "")
		Estilo.texto(ci, cuenta, Vector2(tx + 92, y + 2), Estilo.AMBAR_CLARO if listos > 0 else Color(Estilo.CREMA, 0.4))
		y += 24.0
	var t := _info if _info != "" else ("LOS RECLUTAS SE PAGAN CON SUMINISTROS." if Compania.puede_reclutar()
		else "LA COMPAÑÍA ESTÁ COMPLETA: SE RECLUTA CUANDO HAY BAJAS.")
	var ly := y + 4
	for linea in _envolver(t, ancho).slice(0, 2):
		Estilo.texto(ci, linea, Vector2(tx, ly), Estilo.AMBAR_CLARO if _info != "" else Color(Estilo.CREMA, 0.6))
		ly += 12.0


func _botones_panel(ci: CanvasItem) -> void:
	for b in _botones():
		var id: String = b[0]
		if id.begins_with("z:") or id.begins_with("m:") or id == "leer":
			continue
		var estado := "normal"
		if not b[3]:
			estado = "apagado"
		elif id == _encima:
			estado = "encima"
		Estilo.boton(ci, b[1], b[2], estado, b[4])


# ---------------------------------------------------------------- el diario

func _diario(ci: CanvasItem, e: Dictionary) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(Estilo.NEGRO, 0.75))
	var w := 420.0
	var h := minf(size.y - 16, 344.0)
	var p := Rect2((size.x - w) / 2.0, (size.y - h) / 2.0, w, h)
	ci.draw_rect(p.grow(2), Estilo.NEGRO)
	ci.draw_rect(p, PAPEL)
	# Manchas del papel
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(e.get("fecha", ""))
	for i in 60:
		var q := Vector2(rng.randf_range(p.position.x, p.end.x - 3), rng.randf_range(p.position.y, p.end.y - 2)).floor()
		ci.draw_rect(Rect2(q, Vector2(rng.randi_range(1, 3), 1)), Color(TINTA, 0.08))
	var cx := p.get_center().x
	var x := p.position.x + 12
	var y := p.position.y + 26
	_tinta_c(ci, "THE NORMANDY DISPATCH", cx, y, Estilo.TAM_GRANDE)
	y += 6
	ci.draw_rect(Rect2(x, y, w - 24, 2), TINTA)
	ci.draw_rect(Rect2(x, y + 4, w - 24, 1), TINTA)
	y += 15
	_tinta(ci, "EDICIÓN DEL FRENTE", Vector2(x, y))
	_tinta_c(ci, e.get("fecha", ""), cx, y)
	var precio := "5 CENTAVOS"
	_tinta(ci, precio, Vector2(p.end.x - 12 - Estilo.ancho_texto(precio), y))
	y += 5
	ci.draw_rect(Rect2(x, y, w - 24, 1), TINTA)
	y += 24
	for linea in e.get("titular", []):
		_tinta_c(ci, linea, cx, y, Estilo.TAM_GRANDE)
		y += 22
	y -= 4
	for linea in e.get("bajada", []):
		_tinta_c(ci, linea, cx, y)
		y += 12
	y += 2
	ci.draw_rect(Rect2(x, y, w - 24, 1), TINTA)
	y += 8
	# Foto a la izquierda, texto a la derecha
	var foto := Rect2(x, y, 176, 99)
	_foto(ci, e.get("foto", ""), foto)
	var col := foto.end.x + 10
	var ancho := p.end.x - 12 - col
	var ty := y + 9
	for linea in e.get("cuerpo", []):
		for l in _envolver(linea, ancho):
			_tinta(ci, l, Vector2(col, ty))
			ty += 11
	if e.has("caidos"):
		ty += 4
		_tinta(ci, "CAÍDOS DE LA COMPAÑÍA:", Vector2(col, ty), Color("#7a1a10"))
		ty += 11
		for l in _envolver(", ".join(e["caidos"]), ancho):
			_tinta(ci, l, Vector2(col, ty))
			ty += 11
	if e.has("heridos"):
		ty += 2
		_tinta(ci, "HERIDOS: " + ", ".join(e["heridos"]), Vector2(col, ty), TINTA, ancho)
		ty += 11
	if e.has("apoyo") and int(e["apoyo"]) != 0:
		var a := int(e["apoyo"])
		_tinta(ci, "APOYO DEL MANDO: %s%d" % ["+" if a > 0 else "", a], Vector2(x, p.end.y - 10),
			Color("#2d5a1a") if a > 0 else Color("#7a1a10"))
	var seguir := "TOCA PARA SEGUIR"
	var a2 := 0.5 + 0.5 * sin(_t * 4.0)
	_tinta(ci, seguir, Vector2(p.end.x - 12 - Estilo.ancho_texto(seguir), p.end.y - 10), Color(TINTA, 0.4 + 0.5 * a2))


func _foto(ci: CanvasItem, clave: String, r: Rect2) -> void:
	var tex := _textura_foto(clave)
	ci.draw_rect(r.grow(1), TINTA)
	if tex:
		ci.draw_texture_rect(tex, r, false)
		return
	ci.draw_rect(r, Color("#8f8a76"))
	for i in range(-int(r.size.y), int(r.size.x), 6):
		var a := Vector2(r.position.x + maxf(i, 0), r.position.y + maxf(-i, 0))
		var largo := minf(r.size.x - maxf(i, 0), r.size.y - maxf(-i, 0))
		ci.draw_line(a, a + Vector2(largo, largo), Color(TINTA, 0.15))
	_tinta_c(ci, "FOTO PENDIENTE", r.get_center().x, r.get_center().y + 4, Estilo.TAM, Color(TINTA, 0.6))


## Foto del diario en blanco y negro: assets/campana/foto_<clave>.png; para el
## comienzo y Omaha, mientras tanto, el fondo del menú (la playa).
func _textura_foto(clave: String) -> Texture2D:
	if _fotos.has(clave):
		return _fotos[clave]
	var ruta := "res://assets/campana/foto_%s.png" % clave
	var tex: Texture2D = null
	if ResourceLoader.exists(ruta):
		tex = load(ruta)
	elif clave in ["inicio", "omaha"]:
		tex = load("res://assets/ui/fondo_menu.png")
	if tex:
		var img := tex.get_image()
		if img:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			for py in img.get_height():
				for px in img.get_width():
					var c := img.get_pixel(px, py)
					var v := clampf((c.r * 0.3 + c.g * 0.59 + c.b * 0.11) * 1.1, 0.0, 1.0)
					img.set_pixel(px, py, Color(v * 0.95, v * 0.92, v * 0.82))
			tex = ImageTexture.create_from_image(img)
	_fotos[clave] = tex
	return tex


func _tinta(ci: CanvasItem, t: String, pos: Vector2, col := TINTA, ancho := -1.0, tam := Estilo.TAM) -> void:
	ci.draw_string(Estilo.FUENTE, pos.round(), t, HORIZONTAL_ALIGNMENT_LEFT, ancho, tam, col)


func _tinta_c(ci: CanvasItem, t: String, cx: float, y: float, tam := Estilo.TAM, col := TINTA) -> void:
	_tinta(ci, t, Vector2(roundf(cx - Estilo.ancho_texto(t, tam) / 2.0), y), col, -1.0, tam)


# ---------------------------------------------------------------- presión alemana

func _presion(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(Estilo.NEGRO, 0.6))
	var c := size / 2.0
	var r := Rect2(c.x - 164, c.y - 78, 328, 150)
	Estilo.marco(ci, r, "chapa")
	var cara := Rect2(r.position.x + 10, r.position.y + 12, 64, 56)
	Estilo.marco(ci, cara, "hundido")
	ci.draw_texture_rect(_retrato("coronel"), cara.grow(-2), false)
	var m := Campana.mision(Campana.presion)
	var x := r.position.x + 84
	Estilo.texto(ci, "CORONEL", Vector2(x, r.position.y + 22), Estilo.AMBAR_CLARO)
	var y := r.position.y + 38
	for l in _envolver("LOS ALEMANES PRESIONAN EN %s. SI NO MANDAMOS SUMINISTROS, EL MANDO NOS LO VA A COBRAR." % m.get("n", "EL FRENTE"), r.end.x - x - 10):
		Estilo.texto(ci, l, Vector2(x, y), Estilo.CREMA)
		y += 12
	Estilo.texto(ci, "SUMINISTROS: %d" % Campana.suministros, Vector2(r.position.x + 14, c.y + 26), Color(Estilo.CREMA, 0.6))
	for b in _botones():
		var estado := "normal"
		if not b[3]:
			estado = "apagado"
		elif b[0] == _encima:
			estado = "encima"
		Estilo.boton(ci, b[1], b[2], estado, b[4])


# ---------------------------------------------------------------- utilidades

func _retrato(nombre: String) -> Texture2D:
	var clave := nombre.to_lower()
	if not _retratos.has(clave):
		var ruta := "res://assets/ui/retratos/retrato_%s.png" % clave
		_retratos[clave] = load(ruta) if ResourceLoader.exists(ruta) else Estilo.RETRATO_PROVISIONAL
	return _retratos[clave]


## Corta un texto en líneas que caben en `ancho` píxeles.
func _envolver(t: String, ancho: float) -> Array:
	var lineas: Array = []
	var actual := ""
	for palabra in t.split(" ", false):
		var prueba := palabra if actual == "" else actual + " " + palabra
		if Estilo.ancho_texto(prueba) > ancho and actual != "":
			lineas.append(actual)
			actual = palabra
		else:
			actual = prueba
	if actual != "":
		lineas.append(actual)
	return lineas
