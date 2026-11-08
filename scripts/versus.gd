extends Node3D
class_name Versus
## Modo VERSUS (v0.42): americanos contra alemanes, hasta 2 jugadores por
## bando, cada uno con su escuadra de IA. Se juega en salas con código (las
## mismas del cooperativo y el mismo servidor de Cloudflare, que solo reenvía).
##
## - Bandos: 0 = EE.UU., 1 = Alemania. En la sala de espera cada jugador elige
##   el suyo (máximo 2 por lado). Al empezar, el anfitrión arma `bandos`: el
##   bando de cada escuadra 0–3 (la escuadra = el puesto del jugador). Las
##   escuadras sin jugador se reparten para que cada bando tenga dos: las manda
##   un sargento con IA.
## - Grupos (en todos los celulares): "americanos" = cuerpos de EE.UU. y
##   "enemies" = cuerpos alemanes (jugadores, compañeros con IA y títeres). Así
##   la IA de siempre (Combatiente.elegir_objetivo) sirve para los dos lados.
## - Capas: en cada celular, lo que es RIVAL del jugador local va en la capa 3
##   (4), donde pegan sus balas; lo amigo, en la capa 5 (16) o sin choque.
## - Como en el cooperativo, el ANFITRIÓN corre toda la IA, la toma del punto y
##   el marcador; los invitados lo reciben en cada paquete ("vs").
## - Se gana dejando al otro bando sin REFUERZOS (cada baja resta uno) o
##   teniendo más al acabarse el tiempo. El bando que tiene el PUNTO del medio
##   le resta uno al otro cada DRENAJE_CADA segundos.

const US := 0
const DE := 1
const TICKETS := 60
const DRENAJE_CADA := 6.0
const TOMA_SEG := 10.0            # segundos para tomar el punto (solo, sin rivales cerca)
const DURACION := 15.0 * 60.0
const NOMBRES_BANDO := ["EE.UU.", "ALEMANIA"]
const NOMBRES_JUGADOR := [["MURPHY", "KOWALSKI", "REYES", "COLE"], ["KRAUSE", "BECKER", "WOLF", "HARTMANN"]]
const SARGENTOS := [["SGT. HARRIS", "SGT. DAWSON"], ["FW. SCHULZ", "FW. RICHTER"]]
const SOLDADOS := [
	["GARCIA", "NOVAK", "BAKER", "JENKINS", "LOPEZ", "O'BRIEN", "WASHINGTON", "FISHER", "MILLER", "DUBOIS",
		"ROSSI", "SANDERS", "PARKER", "HUGHES", "WALSH", "TURNER"],
	["MÜLLER", "SCHMIDT", "FISCHER", "WEBER", "MEYER", "WAGNER", "SCHÄFER", "KOCH", "BAUER", "RICHTER",
		"KLEIN", "SCHRÖDER", "NEUMANN", "ZIMMER", "BRAUN", "HOFMANN"],
]
const ARMAS := [["garand", "garand", "bar", "thompson", "carbine"], ["kar98k", "kar98k", "mp40", "stg44", "kar98k"]]
const ARMA_JUGADOR := ["garand", "kar98k"]
const PISTOLA := ["colt", "luger"]

static var activo := false
static var bandos: Array = [US, DE, US, DE]   # bando de cada escuadra (= puesto)
static var con_jugador: Array = []           # puestos con jugador al empezar (el anfitrión)
static var actual: Versus
static var tickets: Array = [TICKETS, TICKETS]
static var bajas_de: Array = [0, 0]          # caídos de cada bando
static var dueno := -1                        # quién tiene el punto (-1 nadie)
static var toma := 0.0                        # -1 … 1: avance de la toma (+ EE.UU., − Alemania)
static var tiempo := 0.0
static var ganador := -1                      # -1 en curso, 0/1 ganó ese bando, 2 empate
static var _nombre_i := [0, 0]

var _t_punto := 0.0
var _t_drenaje := 0.0
var _bandera: MeshInstance3D
var _mat_bandera: StandardMaterial3D
var _cartel: Label3D
var _dueno_visto := -2


# ================================================================ consultas

## ¿La misión elegida es de versus? (antes de que exista el nodo)
static func de_mision() -> bool:
	return bool(Misiones.actual().get("versus", false))


static func es_versus(id: String) -> bool:
	return Misiones.existe(id) and bool(Misiones.DATOS[id].get("versus", false))


## Mi bando (el de la escuadra de mi puesto).
static func mi_bando() -> int:
	var pu := Red.actual.puesto if Red.actual else 0
	return int(bandos[clampi(pu, 0, 3)])


static func bando_de_escuadra(esc: int) -> int:
	return int(bandos[clampi(esc, 0, 3)])


static func grupo(b: int) -> String:
	return "enemies" if b == DE else "americanos"


## El grupo de los enemigos del jugador local (fuera del versus, los alemanes).
static func grupo_rival() -> String:
	return grupo(1 - mi_bando()) if activo else "enemies"


static func sprite(b: int) -> String:
	return "aleman" if b == DE else "aliado"


static func bando_de_sprite(s: String) -> int:
	return DE if s == "aleman" else US


static func base(b: int) -> Vector3:
	return Misiones.dato("bases")[b]


static func punto() -> Vector3:
	return Misiones.dato("punto")


## Hacia dónde mira un soldado de ese bando al aparecer (hacia la base rival).
static func frente(b: int) -> float:
	var d := base(1 - b) - base(b)
	return atan2(-d.x, -d.z)


## Hacia dónde avanza la IA de un bando: el punto, y si ya es suyo, la base rival.
static func rumbo(b: int) -> Vector3:
	if dueno == b:
		return base(1 - b).lerp(punto(), 0.35)
	return punto()


## Un lugar para aparecer en la base de un bando, en el carril de una escuadra.
static func lugar_base(b: int, esc: int, rng: RandomNumberGenerator) -> Vector3:
	var s := carril(esc)
	var c := base(b)
	var x := clampf(rng.randf_range(s.x, s.y), c.x - float(Misiones.dato("ancho_base")), c.x + float(Misiones.dato("ancho_base")))
	return Vector3(x, c.y, c.z + rng.randf_range(-1.0, 1.0))


## El carril (X) de una escuadra: la primera de su bando va por el primero,
## la segunda por el segundo.
static func carril(esc: int) -> Vector2:
	esc = clampi(esc, 0, 3)
	var antes := 0
	for i in esc:
		if int(bandos[i]) == int(bandos[esc]):
			antes += 1
	var l: Array = Misiones.dato("carriles")
	return l[antes % l.size()]


static func nombre_soldado(b: int) -> String:
	_nombre_i[b] += 1
	var l: Array = SOLDADOS[b]
	return l[(_nombre_i[b] - 1) % l.size()]


## ¿Este celular lleva el marcador? (el anfitrión; un invitado que perdió la
## conexión sigue siendo invitado: no se pone a contar por su cuenta)
static func manda() -> bool:
	return Red.actual == null or Red.actual.anfitrion


static func puede_reforzar(b: int) -> bool:
	return int(tickets[b]) > 0 and ganador < 0


## El anfitrión arma el bando de cada escuadra con lo que eligieron los
## jugadores (`elegidos`: puesto → bando). Las escuadras sin jugador completan
## para que cada bando tenga dos.
static func armar_bandos(elegidos: Dictionary) -> Array:
	var r: Array = [-1, -1, -1, -1]
	var n := [0, 0]
	for pu in elegidos:
		var i := clampi(int(pu), 0, 3)
		r[i] = clampi(int(elegidos[pu]), 0, 1)
		n[r[i]] += 1
	for i in 4:
		if r[i] < 0:
			var b := US if n[US] < 2 and (n[US] <= n[DE]) else DE
			if n[b] >= 2:
				b = 1 - b
			r[i] = b
			n[b] += 1
	return r


## Un caído de ese bando (lo cuenta el anfitrión).
static func baja(b: int) -> void:
	if not activo or not manda() or ganador >= 0:
		return
	b = clampi(b, 0, 1)
	tickets[b] = maxi(int(tickets[b]) - 1, 0)
	bajas_de[b] += 1


# ================================================================ armar

func _ready() -> void:
	actual = self
	activo = true
	name = "Versus"
	tickets = [TICKETS, TICKETS]
	bajas_de = [0, 0]
	dueno = -1
	toma = 0.0
	tiempo = 0.0
	ganador = -1
	_nombre_i = [0, 0]
	# Sin objetivos de misión (el HUD, la pausa y la noche los consultan)
	Objetivos.LISTA = []
	Objetivos.hecho = []
	Objetivos.progreso = []
	Objetivos.terminado = 0
	Objetivos._fase_memo = -1
	_armar_bandera()
	_poner_jugador()


func _exit_tree() -> void:
	if actual == self:
		actual = null
		activo = false


## El jugador de este celular: en su base, mirando al enemigo, con las armas
## y el nombre de su bando, y en el grupo de su bando.
func _poner_jugador() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var b := mi_bando()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var esc := Red.actual.puesto if Red.actual else 0
	var pos := lugar_base(b, esc, rng)
	p.global_position = pos + Vector3(0, 0.3, 0)
	p.rotation.y = frente(b)
	p.set_meta("inicio", pos)
	p.remove_from_group("americanos")
	p.remove_from_group("enemies")
	p.add_to_group(grupo(b))
	p.nombre = NOMBRES_JUGADOR[b][clampi(esc, 0, 3)]
	if Red.actual:
		Red.actual.mi_nombre = p.nombre
	var w = p.weapons
	if w:
		for k in 2:
			var id: String = [ARMA_JUGADOR[b], PISTOLA[b]][k]
			var d := Armas.datos(id)
			w._set_slot(k, id)
			w.ammo[k] = int(d["mag"])
			w.reserve[k] = int(d["reserve"])
		w.current = 0
	Game.say("[JUEGAS POR %s: %s]" % [NOMBRES_BANDO[b], p.nombre], Game.COLOR_GOOD)
	Game.say("[TOMA EL PUNTO DEL MEDIO Y DEJA AL ENEMIGO SIN REFUERZOS]", Game.COLOR_INFO)


## El punto del medio: un mástil con una bandera que toma el color del dueño
## y un cartel que se ve de lejos.
func _armar_bandera() -> void:
	var c := punto()
	var mastil := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 0.06
	cil.bottom_radius = 0.08
	cil.height = 6.0
	cil.radial_segments = 6
	mastil.mesh = cil
	mastil.material_override = Game.material(Color(0.35, 0.3, 0.24))
	mastil.position = c + Vector3(0, 3.0, 0)
	add_child(mastil)
	_bandera = MeshInstance3D.new()
	var tela := BoxMesh.new()
	tela.size = Vector3(1.6, 1.0, 0.05)
	_bandera.mesh = tela
	_mat_bandera = StandardMaterial3D.new()
	_mat_bandera.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_bandera.albedo_color = Color(0.8, 0.8, 0.75)
	_bandera.material_override = _mat_bandera
	_bandera.position = c + Vector3(0.85, 5.4, 0)
	add_child(_bandera)
	_cartel = Label3D.new()
	_cartel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cartel.font = Estilo.FUENTE
	_cartel.font_size = 22
	_cartel.pixel_size = 0.03
	_cartel.outline_size = 5
	_cartel.no_depth_test = true
	_cartel.fixed_size = false
	_cartel.position = c + Vector3(0, 7.2, 0)
	add_child(_cartel)
	# Un anillo de sacos marca el borde del punto (cobertura de paso)
	Coberturas.agregar_erizo(c + Vector3(0, 0, 0))


# ================================================================ cada cuadro

func _process(delta: float) -> void:
	_mostrar_dueno()
	if not manda() or ganador >= 0 or Game.warming:
		return
	tiempo += delta
	_t_punto -= delta
	if _t_punto <= 0.0:
		_t_punto = 0.25
		_revisar_punto(0.25)
	if dueno >= 0:
		_t_drenaje += delta
		if _t_drenaje >= DRENAJE_CADA:
			_t_drenaje = 0.0
			tickets[1 - dueno] = maxi(int(tickets[1 - dueno]) - 1, 0)
	if int(tickets[US]) <= 0 or int(tickets[DE]) <= 0:
		_terminar(US if int(tickets[DE]) <= 0 and int(tickets[US]) > 0 else (DE if int(tickets[US]) <= 0 and int(tickets[DE]) > 0 else 2))
	elif tiempo >= DURACION:
		var a := int(tickets[US])
		var b := int(tickets[DE])
		_terminar(US if a > b else (DE if b > a else 2))


## Quién está en el punto (vivos a menos del radio): si hay de un solo bando,
## la toma avanza hacia él; con los dos, se disputa y no avanza.
func _revisar_punto(dt: float) -> void:
	var c := punto()
	var radio := float(Misiones.dato("radio_punto"))
	var hay := [0, 0]
	for b in 2:
		for n in get_tree().get_nodes_in_group(grupo(b)):
			var q := n as Node3D
			if q == null or q.get("dead"):
				continue
			var d := q.global_position - c
			if absf(d.y) < 4.0 and Vector2(d.x, d.z).length() < radio:
				hay[b] += 1
	var antes := dueno
	if hay[US] > 0 and hay[DE] == 0:
		toma = minf(toma + dt / TOMA_SEG * (1.0 + 0.25 * mini(hay[US] - 1, 3)), 1.0)
	elif hay[DE] > 0 and hay[US] == 0:
		toma = maxf(toma - dt / TOMA_SEG * (1.0 + 0.25 * mini(hay[DE] - 1, 3)), -1.0)
	if toma >= 1.0:
		dueno = US
	elif toma <= -1.0:
		dueno = DE
	elif dueno == US and toma <= 0.0 or dueno == DE and toma >= 0.0:
		dueno = -1        # el otro bando ya la bajó hasta la mitad: queda de nadie
	if dueno != antes:
		_t_drenaje = 0.0
		if dueno >= 0:
			Red.anunciar("[%s TOMA EL PUNTO]" % NOMBRES_BANDO[dueno], Game.COLOR_INFO)
		else:
			Red.anunciar("[EL PUNTO QUEDÓ SIN DUEÑO]", Game.COLOR_INFO)


func _mostrar_dueno() -> void:
	if _cartel == null:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var dist := int(p.global_position.distance_to(punto())) if p else 0
	var mio := mi_bando()
	var txt := "PUNTO %d M" % dist
	var col := Estilo.CREMA
	if dueno >= 0:
		txt = ("PUNTO NUESTRO" if dueno == mio else "PUNTO ENEMIGO") + " %d M" % dist
		col = Estilo.VERDE_LED if dueno == mio else Estilo.ROJO
	elif absf(toma) > 0.02:
		var hacia := US if toma > 0.0 else DE
		txt = "%s TOMANDO %d%%" % ["NOSOTROS" if hacia == mio else "ENEMIGO", int(absf(toma) * 100.0)]
		col = Estilo.AMBAR_CLARO
	_cartel.text = txt
	_cartel.modulate = col
	if dueno != _dueno_visto:
		_dueno_visto = dueno
		_mat_bandera.albedo_color = [Color(0.25, 0.35, 0.75), Color(0.75, 0.12, 0.1)][dueno] if dueno >= 0 \
			else Color(0.8, 0.8, 0.75)


func _terminar(g: int) -> void:
	if ganador >= 0:
		return
	ganador = g
	Objetivos.terminado = 1
	if Red.es_anfitrion():
		Red.evento(["vfin", g, int(tickets[US]), int(tickets[DE]), int(bajas_de[US]), int(bajas_de[DE])])
	VersusFin.mostrar(get_tree())


# ================================================================ red

## Anfitrión: el marcador para los invitados (va en cada paquete).
static func estado() -> Array:
	return [int(tickets[US]), int(tickets[DE]), dueno, snappedf(toma, 0.01), int(tiempo), ganador]


static func recibir(a: Array) -> void:
	if a.size() < 6:
		return
	tickets = [int(a[0]), int(a[1])]
	dueno = int(a[2])
	toma = float(a[3])
	tiempo = float(a[4])


## Invitado: el anfitrión terminó la partida.
static func fin_recibido(ev: Array) -> void:
	if ganador >= 0 or ev.size() < 6:
		return
	ganador = int(ev[1])
	tickets = [int(ev[2]), int(ev[3])]
	bajas_de = [int(ev[4]), int(ev[5])]
	Objetivos.terminado = 1
	var arbol := Engine.get_main_loop() as SceneTree
	VersusFin.mostrar(arbol)


## Texto del marcador para el HUD: "EE.UU. 52  ·  ALEMANIA 47  ·  12:31".
static func texto_marcador() -> String:
	var falta := maxi(int(DURACION - tiempo), 0)
	return "%s %d  -  %s %d   %d:%02d" % [NOMBRES_BANDO[US], int(tickets[US]), NOMBRES_BANDO[DE], int(tickets[DE]),
		falta / 60, falta % 60]


static func texto_punto() -> String:
	var mio := mi_bando()
	if dueno >= 0:
		return "PUNTO: " + ("NUESTRO (EL ENEMIGO PIERDE REFUERZOS)" if dueno == mio else "ENEMIGO (¡RECUPÉRALO!)")
	if absf(toma) > 0.02:
		return "PUNTO: %s %d%%" % ["LO ESTAMOS TOMANDO" if (toma > 0.0) == (mio == US) else "EL ENEMIGO LO TOMA", int(absf(toma) * 100.0)]
	return "PUNTO: SIN DUEÑO (¡TÓMALO!)"
