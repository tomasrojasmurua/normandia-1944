extends RefCounted
class_name Compania
## Tu compañía (sección 6, paso 2): los hombres que van contigo de misión en
## misión. Cada uno tiene nombre (su retrato es retrato_<nombre>.png),
## especialidad, rango y estado. Se guarda en el celular (user://campana.cfg).
##
## - Antes de cada misión eliges a 3 (pantalla previa) y el arma de cada uno.
## - El que cae en la misión queda MUERTO (no vuelve nunca) o HERIDO (se pierde
##   las próximas 1 o 2 misiones). Los que sobreviven suman misiones y ascienden.
## - Los reemplazos que llegan a tu escuadra durante la misión y sobreviven se
##   unen a la compañía. Los reclutas se pagan con SUMINISTROS en el mapa de la
##   campaña (Campana); solo si quedan menos de 3 disponibles llegan gratis.
## - Tú eres el sargento MURPHY: no está en la lista (si caes, sigues como el
##   compañero que te releva; si ese cae, ese sí cuenta como caído).
## Solo cuenta jugando solo (no en el cooperativo ni en la prueba de carga).

const ARCHIVO := "user://campana.cfg"
const MAXIMO := 15            # hombres vivos en la compañía (sin contar a Murphy)
const MINIMO_LISTOS := 3      # si quedan menos disponibles, llegan reclutas gratis
const PROB_MUERTO := 0.55     # el resto de los caídos queda herido

const ESPECIALIDADES := {
	"fusilero": {"n": "FUSILERO", "c": "FUS", "armas": ["garand", "carbine", "springfield", "thompson"],
		"info": "FUSILERO: EL GRUESO DE LA ESCUADRA"},
	"bar": {"n": "TIRADOR BAR", "c": "BAR", "armas": ["bar"],
		"info": "BAR: FUSIL AUTOMÁTICO, MUCHO FUEGO"},
	"medico": {"n": "MÉDICO", "c": "MED", "armas": ["carbine"],
		"info": "MÉDICO: SI CAES CERCA DE ÉL, TE LEVANTA (UNA VEZ)"},
	"radio": {"n": "RADIO", "c": "RAD", "armas": ["carbine", "thompson"],
		"info": "RADIO: PIDE MORTEROS DONDE MIRAS (TOCA SU RETRATO O B)"},
	"ingeniero": {"n": "INGENIERO", "c": "ING", "armas": ["garand", "thompson", "carbine"],
		"info": "INGENIERO: CERCA DE ÉL, LAS CARGAS SE PONEN AL DOBLE"},
	"bazuca": {"n": "BAZUCA", "c": "BAZ", "armas": ["carbine"],
		"info": "BAZUCA: LE DISPARA COHETES A LAS MG42 Y A LOS GRUPOS"},
}
const RANGOS := ["PVT", "PFC", "CPL", "SGT"]
const MISIONES_PARA := [0, 2, 4, 7]     # misiones sobrevividas para cada rango

## [nombre, especialidad, rango, arma]
const INICIAL := [
	["DELUCA", "fusilero", 1, "thompson"], ["HAYES", "fusilero", 0, "garand"],
	["BRENNAN", "bar", 2, "bar"], ["RAMIREZ", "medico", 1, "carbine"],
	["SULLIVAN", "radio", 1, "carbine"], ["KLEIN", "ingeniero", 2, "garand"],
	["MORGAN", "bazuca", 0, "carbine"], ["PETERSON", "fusilero", 0, "garand"],
	["CHAVEZ", "bar", 1, "bar"], ["GRABOWSKI", "fusilero", 1, "garand"],
	["TAYLOR", "medico", 2, "carbine"], ["WHITEHORSE", "radio", 0, "carbine"],
	["ROMANO", "ingeniero", 1, "thompson"], ["HARPER", "bazuca", 0, "carbine"],
	["FLYNN", "fusilero", 0, "springfield"],
]
const RECLUTAS := ["ADAMS", "BROOKS", "COLLINS", "DAVIS", "EVANS", "FOSTER", "GRANT", "HALL",
	"IVERSON", "JAMES", "KELLY", "LEWIS", "MASON", "NELSON", "OWENS", "PRICE", "QUINN", "REED",
	"SHAW", "WARD", "YOUNG", "BELL", "COOK", "DIXON", "ELLIS", "FORD"]

static var hombres: Array = []        # cada uno: {n, esp, rango, estado, herido, misiones, arma}
static var elegidos: Array = []       # nombres de los 3 que van a la próxima misión
static var misiones_jugadas := 0
static var _cargada := false

# Durante la misión
static var en_mision := false
static var companeros: Array = []      # los que fueron
static var caidos: Array = []          # los que cayeron (se decide al final si muerto o herido)
static var informe: Array = []         # [texto, color] del cierre de la última misión
static var ultimos_muertos: Array = [] # nombres (para el diario)
static var ultimos_heridos: Array = []


## ¿Cuenta la compañía en esta partida?
static func activa() -> bool:
	return not Game.modo_red and not Game.prueba_carga


static func cargar() -> void:
	if _cargada:
		return
	_cargada = true
	var cfg := ConfigFile.new()
	if cfg.load(ARCHIVO) != OK or not cfg.has_section_key("compania", "hombres"):
		nueva()
		return
	hombres = cfg.get_value("compania", "hombres", [])
	elegidos = cfg.get_value("compania", "elegidos", [])
	misiones_jugadas = cfg.get_value("compania", "misiones", 0)
	_limpiar_elegidos()


static func guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.load(ARCHIVO)
	cfg.set_value("compania", "hombres", hombres)
	cfg.set_value("compania", "elegidos", elegidos)
	cfg.set_value("compania", "misiones", misiones_jugadas)
	cfg.save(ARCHIVO)


## Empieza de cero: los 15 de siempre, todos sanos.
static func nueva() -> void:
	hombres = []
	for h in INICIAL:
		hombres.append({"n": h[0], "esp": h[1], "rango": h[2], "estado": "ok", "herido": 0,
			"misiones": MISIONES_PARA[h[2]], "arma": h[3]})
	elegidos = ["DELUCA", "HAYES", "BRENNAN"]
	misiones_jugadas = 0
	_cargada = true
	guardar()


static func hombre(nombre: String) -> Dictionary:
	for h in hombres:
		if h["n"] == nombre:
			return h
	return {}


static func listos() -> Array:
	return hombres.filter(func(h: Dictionary) -> bool: return h["estado"] == "ok")


static func vivos() -> Array:
	return hombres.filter(func(h: Dictionary) -> bool: return h["estado"] != "muerto")


## Elegido o no (máximo 3, solo los que están en condiciones).
static func alternar(nombre: String) -> void:
	var h := hombre(nombre)
	if h.is_empty() or h["estado"] != "ok":
		return
	if nombre in elegidos:
		elegidos.erase(nombre)
	elif elegidos.size() < 3:
		elegidos.append(nombre)
	guardar()


## Cambia el arma de un hombre por la siguiente que puede usar.
static func otra_arma(nombre: String) -> void:
	var h := hombre(nombre)
	if h.is_empty():
		return
	var armas: Array = ESPECIALIDADES[h["esp"]]["armas"]
	h["arma"] = armas[(armas.find(h["arma"]) + 1) % armas.size()]
	guardar()


static func _limpiar_elegidos() -> void:
	elegidos = elegidos.filter(func(n: String) -> bool: return hombre(n).get("estado", "") == "ok")


## Los que van a la misión: [nombre, arma, especialidad, rango]. Si eligió
## menos de 3, se completa con los primeros disponibles.
static func equipo() -> Array:
	cargar()
	_limpiar_elegidos()
	var lista: Array = elegidos.duplicate()
	for h in listos():
		if lista.size() >= 3:
			break
		if not h["n"] in lista:
			lista.append(h["n"])
	var out := []
	for n in lista:
		var h := hombre(n)
		out.append([n, h["arma"], h["esp"], h["rango"]])
	return out


# ================================================================ la misión

static func empezar_mision() -> void:
	en_mision = activa()
	caidos = []
	companeros = []
	informe = []
	if en_mision:
		for e in equipo():
			companeros.append(e[0])


## Cayó un hombre de la compañía (compañero con IA o el jugador siendo él).
static func caido(nombre: String) -> void:
	if en_mision and nombre in companeros and not nombre in caidos:
		caidos.append(nombre)


## Fin de la misión (cumplida, fracasada o abandonada): muertos, heridos,
## ascensos, los que se curan, los reemplazos que se unen y los reclutas.
## `reemplazos` = nombres de los refuerzos de tu escuadra que siguen vivos.
static func cerrar_mision(resultado: int, reemplazos: Array = []) -> void:
	if not en_mision:
		return
	en_mision = false
	misiones_jugadas += 1
	informe = []
	ultimos_muertos = []
	ultimos_heridos = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Los que estaban heridos (y no fueron) se van recuperando
	for h in hombres:
		if h["estado"] == "herido" and not h["n"] in companeros:
			h["herido"] -= 1
			if h["herido"] <= 0:
				h["estado"] = "ok"
				informe.append(["%s VUELVE DEL HOSPITAL" % h["n"], "bien"])
	# Los que fueron
	for n in companeros:
		var h := hombre(n)
		if h.is_empty():
			continue
		if n in caidos:
			if rng.randf() < PROB_MUERTO:
				h["estado"] = "muerto"
				ultimos_muertos.append(n)
				informe.append(["%s: MUERTO EN COMBATE" % n, "mal"])
			else:
				h["estado"] = "herido"
				h["herido"] = rng.randi_range(1, 2)
				ultimos_heridos.append(n)
				informe.append(["%s: HERIDO, FUERA %d %s" % [n, h["herido"], "MISIÓN" if h["herido"] == 1 else "MISIONES"], "aviso"])
		else:
			h["misiones"] += 1
			var antes: int = h["rango"]
			while h["rango"] < RANGOS.size() - 1 and h["misiones"] >= MISIONES_PARA[h["rango"] + 1]:
				h["rango"] += 1
			if h["rango"] > antes:
				informe.append(["%s: ASCENDIDO A %s" % [n, RANGOS[h["rango"]]], "bien"])
			else:
				informe.append(["%s: SIN UN RASGUÑO" % n, "normal"])
	# Los reemplazos que sobrevivieron se quedan en la compañía (hasta 2)
	for n in reemplazos.slice(0, 2):
		if vivos().size() < MAXIMO and hombre(n).is_empty():
			_agregar(n, "fusilero" if rng.randf() < 0.6 else ["bar", "medico", "radio", "ingeniero", "bazuca"][rng.randi() % 5], rng)
			informe.append(["%s SE UNE A LA COMPAÑÍA" % n, "bien"])
	# Si quedan pocos disponibles, llegan reclutas
	var llegan := 0
	while listos().size() < MINIMO_LISTOS and vivos().size() < MAXIMO:
		var libres := RECLUTAS.filter(func(r: String) -> bool: return hombre(r).is_empty())
		if libres.is_empty():
			break
		var esp := "fusilero"
		for e in ["medico", "radio", "bar", "ingeniero", "bazuca"]:
			if listos().filter(func(x: Dictionary) -> bool: return x["esp"] == e).is_empty():
				esp = e
				break
		_agregar(libres[rng.randi() % libres.size()], esp, rng)
		llegan += 1
	if llegan > 0:
		informe.append(["LLEGAN %d %s" % [llegan, "RECLUTA" if llegan == 1 else "RECLUTAS"], "bien"])
	_limpiar_elegidos()
	guardar()


## Un turno sin ir a misión (descansar, otra unidad): los heridos sanan un
## turno. Devuelve los que vuelven del hospital.
static func descanso() -> Array:
	cargar()
	var sanos: Array = []
	for h in hombres:
		if h["estado"] == "herido":
			h["herido"] -= 1
			if h["herido"] <= 0:
				h["estado"] = "ok"
				sanos.append(h["n"])
	guardar()
	return sanos


static func puede_reclutar() -> bool:
	return vivos().size() < MAXIMO


## Recluta pagado (desde el mapa). Devuelve el nombre ("" si no se pudo).
static func reclutar(esp: String) -> String:
	if not puede_reclutar() or not ESPECIALIDADES.has(esp):
		return ""
	var libres := RECLUTAS.filter(func(r: String) -> bool: return hombre(r).is_empty())
	if libres.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n: String = libres[rng.randi() % libres.size()]
	_agregar(n, esp, rng)
	guardar()
	return n


static func _agregar(nombre: String, esp: String, rng: RandomNumberGenerator) -> void:
	var armas: Array = ESPECIALIDADES[esp]["armas"]
	hombres.append({"n": nombre, "esp": esp, "rango": 0, "estado": "ok", "herido": 0, "misiones": 0,
		"arma": armas[rng.randi() % armas.size()]})


## Para la pantalla previa: "MÉDICO - PFC".
static func descripcion(h: Dictionary) -> String:
	return "%s %s" % [ESPECIALIDADES[h["esp"]]["c"], RANGOS[h["rango"]]]
