extends RefCounted
class_name Campana
## La campaña (sección 6, paso 3): el mapa estratégico de Normandía.
##
## - Un turno = una misión. Cada misión se gana UNA vez y queda saldada (solo
##   se repite si se pierde). La fecha salta a la fecha histórica de la misión.
## - Las misiones van en etapas. En cada etapa el coronel ofrece 2; la que dejas
##   para después se refuerza (más alemanes). La etapa termina al ganarlas todas.
## - Recursos: SUMINISTROS (reclutar, entran según las zonas tomadas) y APOYO
##   DEL MANDO (si llega a 0, te relevan y la campaña termina).
## - Las misiones que todavía no están construidas aparecen "EN PREPARACIÓN"
##   y no se pueden jugar todavía: todas las misiones las hace el jugador.
## - Entre misiones sale el diario THE NORMANDY DISPATCH (en español).
## Se guarda junto a la compañía en user://campana.cfg. Solo jugando solo.

const ARCHIVO := "user://campana.cfg"
## v0.32: recursos más escasos. Antes sobraban (una campaña simulada terminaba
## con ~4.400 suministros sin haber bajado nunca de 400): solo servían para
## reclutar. Ahora la compañía cuesta mantenerla cada turno y antes de cada
## misión se puede comprar apoyo; no alcanza para todo.
const SUMINISTROS_INICIO := 200
const APOYO_INICIO := 80
const APOYO_MAX := 150
const INGRESO_BASE := 40          # suministros que llegan cada turno, más el valor de las zonas
const GASTO_POR_HOMBRE := 10      # raciones y munición de cada hombre vivo, cada turno
const APOYO_GANAR := 12
const APOYO_PERDER := 20
const APOYO_POR_MUERTO := 4
const APOYO_DESCANSAR := 8
const APOYO_OTRA_UNIDAD := 5
const FALTA_POR_APOYO := 10       # si no alcanza para el gasto: -1 de apoyo por cada 10 que falten
const PRESION_PROB := 0.4         # probabilidad de presión alemana tras cada turno (desde la etapa II)
const PRESION_COSTO := 80
const PRESION_APOYO := 12

const COSTO_RECLUTA := {"fusilero": 60, "bar": 90, "medico": 120, "radio": 120, "ingeniero": 120, "bazuca": 140}

## Apoyo que se compra en la pantalla previa, solo para esa misión:
##   artilleria  los alemanes reciben 40 % menos refuerzos y sus morteros caen más espaciados
##   refuerzos   +2 refuerzos americanos por escuadra en cada fase
const COMPRAS := {
	"artilleria": {"n": "ARTILLERÍA", "costo": 100,
		"info": "ARTILLERÍA: 40 % MENOS REFUERZOS ALEMANES Y MENOS MORTEROS."},
	"refuerzos": {"n": "REFUERZOS", "costo": 80,
		"info": "REFUERZOS: +2 HOMBRES DE RELEVO POR ESCUADRA EN CADA FASE."},
}

const ETAPAS := ["DÍA D", "LA CABEZA DE PLAYA", "LA TORMENTA Y EL PUERTO", "LOS SETOS", "LA RUPTURA"]

## Las misiones de la campaña, en el orden de la historia.
##   etapa      0–4 (la etapa I va en orden fijo)
##   dia        días desde el 31 de mayo (6 = 6 de junio; 42 = 12 de julio)
##   pos        longitud, latitud (para el mapa dibujado con código)
##   img        lugar en la imagen del mapa (assets/campana/mapa.png), de 0 a 1
##   fuerza     fuerza alemana de partida (1–3); sube si la dejas para después
##   premio     suministros al cumplirla
##   valor      suministros que da cada turno una vez tomada (playas y puertos, más)
const LISTA := [
	{"id": "omaha", "img": Vector2(0.750, 0.474), "n": "PLAYA OMAHA", "sub": "DESEMBARCO", "etapa": 0, "dia": 6, "pos": Vector2(-0.90, 49.37),
		"fuerza": 3, "premio": 120, "valor": 30, "clima": "NUBLADO", "hora": "06:30",
		"resumen": "VOLAR EL BÚNKER, SUBIR EL ACANTILADO Y TOMAR VIERVILLE."},
	{"id": "planeador", "img": Vector2(0.461, 0.396), "n": "SAINTE-MÈRE-ÉGLISE", "sub": "PLANEADOR", "etapa": 0, "dia": 7, "fecha": "NOCHE DEL 6 AL 7 DE JUNIO",
		"pos": Vector2(-1.32, 49.41), "fuerza": 2, "premio": 90, "valor": 10, "clima": "NOCHE", "hora": "23:00",
		"resumen": "EL PLANEADOR SE ESTRELLA ENTRE SETOS. REÚNA A LOS PARACAIDISTAS."},
	{"id": "pointe", "img": Vector2(0.660, 0.431), "n": "POINTE DU HOC", "sub": "RELEVAR A LOS RANGERS", "etapa": 1, "dia": 8, "pos": Vector2(-0.99, 49.40),
		"fuerza": 2, "premio": 90, "valor": 10, "clima": "NUBLADO", "hora": "08:00",
		"resumen": "LOS RANGERS LLEVAN DOS DÍAS AISLADOS EN EL ACANTILADO."},
	{"id": "lafiere", "img": Vector2(0.396, 0.482), "n": "PUENTE DE LA FIÈRE", "sub": "LA CALZADA", "etapa": 1, "dia": 9, "pos": Vector2(-1.37, 49.39),
		"fuerza": 2, "premio": 90, "valor": 15, "clima": "NUBLADO", "hora": "10:30",
		"resumen": "CRUZAR LA CALZADA SOBRE EL PANTANO DEL MERDERET."},
	{"id": "carentan", "img": Vector2(0.476, 0.504), "n": "CARENTAN", "sub": "UNIR LAS PLAYAS", "etapa": 1, "dia": 12, "pos": Vector2(-1.25, 49.30),
		"fuerza": 3, "premio": 120, "valor": 20, "clima": "DESPEJADO", "hora": "05:00",
		"resumen": "TOMAR CARENTAN PARA UNIR UTAH Y OMAHA."},
	{"id": "tormenta", "img": Vector2(0.415, 0.287), "n": "SETOS DE MONTEBOURG", "sub": "BAJO LA TORMENTA", "etapa": 2, "dia": 20, "pos": Vector2(-1.38, 49.49),
		"fuerza": 2, "premio": 90, "valor": 10, "clima": "TORMENTA", "hora": "07:00",
		"resumen": "AVANZAR ENTRE SETOS SIN APOYO AÉREO."},
	{"id": "cherbourg", "img": Vector2(0.257, 0.142), "n": "CHERBOURG", "sub": "EL PUERTO", "etapa": 2, "dia": 26, "pos": Vector2(-1.62, 49.63),
		"fuerza": 3, "premio": 150, "valor": 50, "clima": "NUBLADO", "hora": "09:00",
		"resumen": "TOMAR LOS FUERTES Y EL PUERTO ANTES DE QUE LO DESTRUYAN."},
	{"id": "colina192", "img": Vector2(0.702, 0.706), "n": "COLINA 192", "sub": "LOS SETOS", "etapa": 3, "dia": 42, "pos": Vector2(-0.97, 49.15),
		"fuerza": 3, "premio": 120, "valor": 15, "clima": "DESPEJADO", "hora": "06:00",
		"resumen": "LA COLINA VIGILA TODO EL VALLE HASTA SAINT-LÔ."},
	{"id": "saintlo", "img": Vector2(0.582, 0.815), "n": "SAINT-LÔ", "sub": "LA CIUDAD EN RUINAS", "etapa": 3, "dia": 48, "pos": Vector2(-1.09, 49.115),
		"fuerza": 3, "premio": 150, "valor": 25, "clima": "NUBLADO", "hora": "06:30",
		"resumen": "ENTRAR A SAINT-LÔ Y LIMPIARLA CASA POR CASA."},
	{"id": "cobra", "img": Vector2(0.486, 0.793), "n": "OPERACIÓN COBRA", "sub": "LA RUPTURA", "etapa": 4, "dia": 55, "pos": Vector2(-1.19, 49.085),
		"fuerza": 3, "premio": 180, "valor": 0, "clima": "DESPEJADO", "hora": "11:00",
		"resumen": "DESPUÉS DEL BOMBARDEO, ROMPER EL FRENTE ALEMÁN."},
]

const MESES := ["", "JUNIO", "JULIO", "AGOSTO"]

# --- Estado guardado
static var suministros := SUMINISTROS_INICIO
static var apoyo := APOYO_INICIO
static var dia := 5                       # 5 de junio: la flota zarpa
static var hechas: Array = []             # ids cumplidas
static var refuerzo := {}                 # id -> veces que se dejó para después
static var turnos := 0
static var estado := "en_curso"           # "en_curso", "relevado", "victoria"
static var diario: Array = []             # ediciones sin leer
static var ultimo_diario: Dictionary = {}
static var presion := ""                  # id de una zona propia bajo presión (decisión pendiente)
static var prologo := false               # ¿ya se vio la cinemática del prólogo?
static var tutorial := false              # ¿ya explicó el coronel el mapa?
static var _cargada := false

# --- La misión en curso
static var en_mision := false
static var _ofrecidas: Array = []
static var compras: Array = []            # apoyo comprado para la misión que viene (COMPRAS)
static var ultimo_gasto := 0              # lo que costó mantener la compañía el último turno
static var falto := 0                     # suministros que faltaron el último turno


static func activa() -> bool:
	return Compania.activa()


static func cargar() -> void:
	if _cargada:
		return
	_cargada = true
	Compania.cargar()
	var cfg := ConfigFile.new()
	if cfg.load(ARCHIVO) != OK or not cfg.has_section_key("campana", "dia"):
		_estado_inicial()
		guardar()
		return
	suministros = cfg.get_value("campana", "suministros", SUMINISTROS_INICIO)
	apoyo = cfg.get_value("campana", "apoyo", APOYO_INICIO)
	dia = cfg.get_value("campana", "dia", 5)
	hechas = cfg.get_value("campana", "hechas", [])
	refuerzo = cfg.get_value("campana", "refuerzo", {})
	turnos = cfg.get_value("campana", "turnos", 0)
	estado = cfg.get_value("campana", "estado", "en_curso")
	diario = cfg.get_value("campana", "diario", [])
	ultimo_diario = cfg.get_value("campana", "ultimo_diario", {})
	presion = cfg.get_value("campana", "presion", "")
	prologo = cfg.get_value("campana", "prologo", false)
	tutorial = cfg.get_value("campana", "tutorial", false)


static func guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.load(ARCHIVO)
	for k in ["suministros", "apoyo", "dia", "hechas", "refuerzo", "turnos", "estado", "diario",
			"ultimo_diario", "presion", "prologo", "tutorial"]:
		cfg.set_value("campana", k, _valor(k))
	cfg.save(ARCHIVO)


static func _valor(k: String) -> Variant:
	match k:
		"suministros": return suministros
		"apoyo": return apoyo
		"dia": return dia
		"hechas": return hechas
		"refuerzo": return refuerzo
		"turnos": return turnos
		"estado": return estado
		"diario": return diario
		"ultimo_diario": return ultimo_diario
		"prologo": return prologo
		"tutorial": return tutorial
		_: return presion


static func _estado_inicial() -> void:
	suministros = SUMINISTROS_INICIO
	apoyo = APOYO_INICIO
	dia = 5
	hechas = []
	refuerzo = {}
	turnos = 0
	estado = "en_curso"
	presion = ""
	prologo = false
	ultimo_diario = {}
	diario = [{
		"fecha": fecha_texto(5),
		"titular": ["LA FLOTA ZARPA", "HACIA FRANCIA"],
		"bajada": ["EL MANDO APLAZÓ LA INVASIÓN 24 HORAS", "POR EL MAL TIEMPO EN EL CANAL"],
		"cuerpo": ["MILES DE BARCOS CRUZAN ESTA NOCHE.", "AL AMANECER, CINCO PLAYAS DE NORMANDÍA.",
			"LA COMPAÑÍA DEL SARGENTO MURPHY", "DESEMBARCA EN OMAHA CON LA PRIMERA OLA."],
		"foto": "inicio",
	}]


## Empieza de cero: la compañía completa y el mapa como el 5 de junio.
static func nueva() -> void:
	Compania.nueva()
	_estado_inicial()
	_cargada = true
	guardar()


# ================================================================ consultas

static func mision(id: String) -> Dictionary:
	for m in LISTA:
		if m["id"] == id:
			return m
	return {}


static func construida(id: String) -> bool:
	return Misiones.existe(id)


static func hecha(id: String) -> bool:
	return id in hechas


## Etapa en curso: la primera con misiones sin cumplir.
static func etapa() -> int:
	for m in LISTA:
		if not hecha(m["id"]):
			return m["etapa"]
	return ETAPAS.size()


static func pendientes() -> Array:
	var e := etapa()
	return LISTA.filter(func(m: Dictionary) -> bool: return m["etapa"] == e and not hecha(m["id"]))


## Las misiones que ofrece el coronel este turno: las 2 más tempranas de la etapa
## (en la etapa I, solo la siguiente: van en orden fijo).
static func ofrecidas() -> Array:
	if estado != "en_curso":
		return []
	var p := pendientes()
	if p.is_empty():
		return []
	if p[0]["etapa"] == 0:
		return [p[0]]
	return p.slice(0, 2)


static func fuerza(id: String) -> int:
	return mini(int(mision(id).get("fuerza", 1)) + int(refuerzo.get(id, 0)), 5)


## Multiplicador de los refuerzos alemanes de la misión en curso (lo usa Defensa).
static func factor_refuerzos() -> float:
	if not activa():
		return 1.0
	var f := 1.0 + 0.25 * float(refuerzo.get(Game.mision, 0))
	if en_mision and "artilleria" in compras:
		f *= 0.6
	return f


## Morteros alemanes: con artillería propia caen más espaciados (lo usa Defensa).
static func factor_morteros() -> float:
	return 1.5 if activa() and en_mision and "artilleria" in compras else 1.0


## Refuerzos americanos extra por escuadra y fase (lo usa Escuadras).
static func refuerzos_extra() -> int:
	return 2 if activa() and en_mision and "refuerzos" in compras else 0


## Comprar o devolver un apoyo antes de la misión (pantalla previa). Se paga
## al salir al ataque; mientras tanto solo se reserva.
static func alternar_compra(id: String) -> bool:
	if id in compras:
		compras.erase(id)
		return true
	if disponibles() < int(COMPRAS[id]["costo"]):
		return false
	compras.append(id)
	return true


## Suministros que quedan sin lo reservado en compras.
static func disponibles() -> int:
	var total := suministros
	for id in compras:
		total -= int(COMPRAS[id]["costo"])
	return total


## Lo que cuesta mantener la compañía cada turno.
static func gasto() -> int:
	return GASTO_POR_HOMBRE * Compania.vivos().size()


static func ingreso() -> int:
	var total := INGRESO_BASE
	for id in hechas:
		total += int(mision(id).get("valor", 0))
	if etapa() == 2:
		total /= 2      # la tormenta del 19 al 22 de junio destruyó el puerto artificial
	return total


static func fecha_texto(d: int) -> String:
	var mes := 1
	var n := d
	if n > 30:
		n -= 30
		mes = 2
		if n > 31:
			n -= 31
			mes = 3
	return "%d DE %s DE 1944" % [n, MESES[mes]]


static func fecha_mision(m: Dictionary) -> String:
	return m.get("fecha", fecha_texto(int(m["dia"])))


# ================================================================ el turno

## Antes de jugar una misión (desde el mapa): la elegida y la otra ofrecida.
static func elegir(id: String) -> void:
	_ofrecidas = ofrecidas().map(func(m: Dictionary) -> String: return m["id"])
	Game.mision = id


## Al empezar la misión (Game.empezar_mision).
static func empezar_mision() -> void:
	en_mision = activa() and estado == "en_curso" and mision(Game.mision).size() > 0 and not hecha(Game.mision)
	if en_mision:
		for id in compras:          # el apoyo comprado se paga al salir
			suministros -= int(COMPRAS[id]["costo"])
		suministros = maxi(suministros, 0)
		guardar()
	else:
		compras = []


## Fin de la misión. Se llama después de Compania.cerrar_mision (usa sus caídos).
static func cerrar_mision(resultado: int) -> void:
	if not en_mision:
		return
	en_mision = false
	var m := mision(Game.mision)
	var muertos: Array = Compania.ultimos_muertos
	var antes := apoyo
	if resultado > 0:
		hechas.append(m["id"])
		suministros += int(m["premio"])
		apoyo += APOYO_GANAR + (5 if refuerzo.get(m["id"], 0) > 0 else 0)
		_dejadas(m["id"])
		dia = maxi(dia, int(m["dia"]))
	else:
		apoyo -= APOYO_PERDER
	apoyo -= APOYO_POR_MUERTO * muertos.size()
	compras = []
	_fin_de_turno()
	_edicion(m, resultado > 0, muertos, Compania.ultimos_heridos, apoyo - antes)
	_revisar_final()
	guardar()


## Descansar: los heridos sanan un turno; baja el apoyo y lo ofrecido se refuerza.
static func descansar() -> void:
	if estado != "en_curso":
		return
	for m in ofrecidas():
		refuerzo[m["id"]] = int(refuerzo.get(m["id"], 0)) + 1
	apoyo -= APOYO_DESCANSAR
	dia += 1
	var sanos := Compania.descanso()
	_fin_de_turno()
	var cuerpo: Array = ["EL MANDO PIDE MÁS EMPUJE.", "LOS ALEMANES APROVECHAN LA PAUSA", "PARA REFORZARSE."]
	if sanos.size() > 0:
		cuerpo.append("VUELVEN DEL HOSPITAL: " + ", ".join(sanos.slice(0, 3)))
	if falto > 0:
		cuerpo.append("FALTARON %d SUMINISTROS." % falto)
	_publicar({"fecha": fecha_texto(dia), "titular": ["LA COMPAÑÍA", "DESCANSA"],
		"bajada": ["UN DÍA DE CALMA EN EL FRENTE"], "cuerpo": cuerpo, "foto": "descanso",
		"apoyo": -APOYO_DESCANSAR})
	_revisar_final()
	guardar()


## La presión alemana: mandar suministros o arriesgarse (perder apoyo).
static func resolver_presion(pagar: bool) -> void:
	if presion == "":
		return
	if pagar and suministros >= PRESION_COSTO:
		suministros -= PRESION_COSTO
	else:
		apoyo -= PRESION_APOYO
	presion = ""
	_revisar_final()
	guardar()


static func reclutar(esp: String) -> bool:
	var costo: int = COSTO_RECLUTA.get(esp, 999)
	if suministros < costo or not Compania.puede_reclutar():
		return false
	if Compania.reclutar(esp) == "":
		return false
	suministros -= costo
	guardar()
	return true


## La misión que dejaste para después se refuerza.
static func _dejadas(elegida: String) -> void:
	for id in _ofrecidas:
		if id != elegida and not hecha(id):
			refuerzo[id] = int(refuerzo.get(id, 0)) + 1
	_ofrecidas = []


static func _fin_de_turno() -> void:
	turnos += 1
	ultimo_gasto = gasto()
	suministros += ingreso() - ultimo_gasto
	falto = 0
	if suministros < 0:            # no alcanzó: la tropa pasa hambre y el mando lo nota
		falto = -suministros
		suministros = 0
		apoyo -= ceili(float(falto) / FALTA_POR_APOYO)
	apoyo = mini(apoyo, APOYO_MAX)
	# Presión alemana sobre una zona tomada (no la última)
	presion = ""
	if etapa() >= 1 and etapa() < ETAPAS.size() and hechas.size() >= 2 and randf() < PRESION_PROB:
		presion = hechas[randi() % (hechas.size() - 1)]


static func _revisar_final() -> void:
	if estado != "en_curso":
		apoyo = maxi(apoyo, 0)
		return
	if apoyo <= 0:
		apoyo = 0
		estado = "relevado"
		presion = ""
		_publicar({"fecha": fecha_texto(dia), "titular": ["EL SARGENTO MURPHY,", "RELEVADO DEL MANDO"],
			"bajada": ["EL MANDO PIERDE LA CONFIANZA", "EN LA COMPAÑÍA"],
			"cuerpo": ["DEMASIADAS BAJAS Y POCO AVANCE.", "OTRO OFICIAL TOMA LA COMPAÑÍA.",
				"PARA EL SARGENTO, LA GUERRA", "CONTINÚA LEJOS DEL FRENTE."], "foto": "relevado"})
	elif etapa() >= ETAPAS.size():
		estado = "victoria"
		presion = ""
		var vivos := Compania.vivos().size()
		_publicar({"fecha": "AGOSTO DE 1944", "titular": ["NORMANDÍA ES", "NUESTRA"],
			"bajada": ["EL FRENTE ALEMÁN SE DERRUMBA", "LOS BLINDADOS CORREN HACIA BRETAÑA Y PARÍS"],
			"cuerpo": ["LA COMPAÑÍA DEL SARGENTO MURPHY", "TERMINA LA CAMPAÑA CON %d HOMBRES." % vivos,
				"MISIONES: %d - TURNOS: %d" % [hechas.size(), turnos], "GRACIAS POR JUGAR."], "foto": "victoria"})


# ================================================================ el diario

## Titulares históricos al cumplir cada misión (en español).
const TITULARES := {
	"omaha": [["CABEZA DE PLAYA", "EN OMAHA"], ["VIERVILLE, EN MANOS AMERICANAS", "DURAS BAJAS EN LA PRIMERA OLA"]],
	"planeador": [["LLEGAN LOS", "PLANEADORES"], ["SAINTE-MÈRE-ÉGLISE RESISTE", "LA 82.A SE REAGRUPA EN LA NOCHE"]],
	"pointe": [["RELEVADOS LOS", "RANGERS"], ["POINTE DU HOC RESISTIÓ DOS DÍAS", "LOS CAÑONES NO ESTABAN EN SU LUGAR"]],
	"lafiere": [["CRUZAN LA CALZADA", "DE LA FIÈRE"], ["EL PUENTE DEL MERDERET ES NUESTRO"]],
	"carentan": [["CAE", "CARENTAN"], ["UTAH Y OMAHA SE DAN LA MANO", "EL FRENTE AMERICANO YA ES UNO SOLO"]],
	"tormenta": [["TEMPORAL", "EN EL CANAL"], ["DESTRUIDO EL PUERTO ARTIFICIAL", "SE AVANZA ENTRE SETOS BAJO LA LLUVIA"]],
	"cherbourg": [["CHERBOURG", "SE RINDE"], ["LOS ALEMANES VOLARON EL PUERTO", "LLEVARÁ SEMANAS REPARARLO"]],
	"colina192": [["TOMADA LA", "COLINA 192"], ["SAINT-LÔ A LA VISTA"]],
	"saintlo": [["SAINT-LÔ", "LIBERADA"], ["LA CAPITAL DE LOS ESCOMBROS"]],
	"cobra": [["¡RUPTURA EN", "NORMANDÍA!"], ["MIL QUINIENTOS BOMBARDEROS ABREN PASO", "LOS BLINDADOS AVANZAN HACIA EL SUR"]],
}


static func _edicion(m: Dictionary, gano: bool, muertos: Array, heridos: Array, dif_apoyo: int) -> void:
	var e := {"fecha": fecha_mision(m) if gano else fecha_texto(dia), "foto": m["id"], "apoyo": dif_apoyo}
	if gano:
		var t: Array = TITULARES.get(m["id"], [[m["n"]], []])
		e["titular"] = t[0]
		e["bajada"] = t[1]
		e["cuerpo"] = ["LA COMPAÑÍA DEL SARGENTO MURPHY", "CUMPLIÓ SU MISIÓN: " + m["n"] + "."]
	else:
		e["titular"] = ["REVÉS EN", m["n"]]
		e["bajada"] = ["LA COMPAÑÍA SE RETIRA", "EL OBJETIVO SIGUE EN MANOS ALEMANAS"]
		e["cuerpo"] = ["EL MANDO EXIGE VOLVER A INTENTARLO."]
	e["cuerpo"].append("RACIONES Y MUNICIÓN: -%d SUMINISTROS." % ultimo_gasto)
	if falto > 0:
		e["cuerpo"].append("FALTARON %d: LA TROPA PASA HAMBRE." % falto)
	if not muertos.is_empty():
		e["caidos"] = muertos
	if not heridos.is_empty():
		e["heridos"] = heridos
	_publicar(e)


static func _publicar(e: Dictionary) -> void:
	diario.append(e)


## La próxima edición sin leer (vacío si no hay).
static func siguiente_edicion() -> Dictionary:
	return diario[0] if not diario.is_empty() else {}


static func leida() -> void:
	if not diario.is_empty():
		ultimo_diario = diario.pop_front()
		guardar()
