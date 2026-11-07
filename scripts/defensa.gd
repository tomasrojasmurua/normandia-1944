extends Node
class_name Defensa
## La defensa alemana de la misión, por fases (sección 6). Lo que hace en cada
## fase viene de Misiones:
## - Al empezar la fase aparecen sus alemanes ("alemanes") en coberturas libres
##   lejos de los americanos, y un tirador de MG42 en cada nido de sus
##   objetivos "mg" (no se mueve, ráfagas largas).
## - Morteros: cada tanto cae uno cerca de algún grupo americano. Se oye el
##   silbido ~1,3 s antes donde va a caer: hay tiempo para correr. Mientras
##   la casamata del cañón siga en pie, caen más seguido.
## - Refuerzos: durante la fase llegan de a 3 desde atrás, hasta "n".
## - Defender (Vierville): olas de alemanes que avanzan sobre el lugar.
## - Bengalas (misiones de noche, "bengalas" en la fase): cada tanto un alemán
##   dispara una bengala sobre los americanos (ver bengala.gd y noche.gd).
## Los alemanes de la primera fase los pone beach_decor.gd (los de la escena
## y las trincheras de la playa).

static var restantes := 0
static var actual: Defensa
static var fase_lista := -1          # la fase que ya se armó (no repetirla)

var nidos := {}                 # objetivo "mg" → su tirador de MG42 (para los objetivos)
var migrada := -1               # traspaso de anfitrión: refuerzos que quedaban (no crear nada)

var _rng := RandomNumberGenerator.new()
var _t_mortero := 22.0
var _t_refuerzo := 40.0
var _t_ola := 8.0
var _olas := 0
var _t_bengala := 7.0
var _avisos_bengala := 0
var _gran := false              # ya salió el gran contraataque de esta defensa
var _mgs_ola: Array = []        # MG42 que trajeron las olas (máx. 2 vivas)
var _cola: Array = []           # alemanes por aparecer: [pos, arma, rol, meta] (de a uno, para no trabar)
var _t_cola := 0.0


func _ready() -> void:
	actual = self
	_rng.randomize()
	if migrada >= 0:
		fase_lista = Objetivos.fase()
		restantes = migrada
		_t_mortero = 8.0
		_t_refuerzo = 20.0
	else:
		fase_lista = -1
		restantes = 0


func _exit_tree() -> void:
	if actual == self:
		actual = null


## Dónde se repliegan los alemanes en la fase en curso.
static func ancla() -> Vector3:
	return Misiones.fase(Objetivos.fase()).get("ancla", Vector3(0, 0, -42))


func _process(delta: float) -> void:
	if not Navegacion.listo or Objetivos.terminado != 0:
		return
	var f := Objetivos.fase()
	if f != fase_lista:
		_empezar(f)
	_t_cola -= delta
	if not _cola.is_empty() and _t_cola <= 0.0:
		_t_cola = 0.12
		var c: Array = _cola.pop_front()
		var e := _nuevo(c[0], c[1], c[2])
		if c.size() < 5:          # los refuerzos llegan sin granadas
			e.granadas = 1 if _rng.randf() < 0.3 else 0
		if c[2] == "asalto":
			e.meta = c[3]
			e._alert = 0.5
	var d := Misiones.fase(f)
	# Morteros (en la defensa de Vierville, los de las olas)
	var mort = d.get("morteros", null)
	var ola := _defensa_activa()
	if ola >= 0:
		mort = Objetivos.LISTA[ola]["olas"].get("morteros", null)
	_t_mortero -= delta
	if mort != null and _t_mortero <= 0.0:
		var ritmo := 0.6 if Objetivos.pendiente("casamata") else 1.0
		_t_mortero = _rng.randf_range(mort.x, mort.y) * ritmo * Campana.factor_morteros()
		_mortero()
	# Bengalas (de noche, hasta que empieza a clarear)
	var beng = d.get("bengalas", null)
	if beng != null and Noche.activa and Noche.amanecer < 0.45:
		_t_bengala -= delta
		if _t_bengala <= 0.0:
			_t_bengala = _rng.randf_range(beng.x, beng.y)
			_bengala()
	# Refuerzos de la fase
	var r: Dictionary = d.get("refuerzos", {})
	_t_refuerzo -= delta
	if _t_refuerzo <= 0.0 and restantes > 0 and not r.is_empty():
		_t_refuerzo = _rng.randf_range(r["cada"].x, r["cada"].y)
		var usados: Array = []
		for i in mini(3, restantes):
			restantes -= 1
			# Por la cola, de a uno (crear tres en el mismo cuadro trababa)
			_cola.append([_lugar(r["zona"], usados, 30.0), Armas.botin_aleman(_rng),
				"flanqueador" if _rng.randf() < 0.35 else "defensor", Vector3.ZERO, "sin_granadas"])
		Red.anunciar("[REFUERZOS ALEMANES]", Game.COLOR_BAD)
	# Olas del contraataque
	if ola >= 0:
		_t_ola -= delta
		var o: Dictionary = Objetivos.LISTA[ola]["olas"]
		if _t_ola <= 0.0:
			_t_ola = _rng.randf_range(o["cada"].x, o["cada"].y)
			_ola(ola, o)
		if o.has("gran") and not _gran and Objetivos.progreso[ola] >= float(o["gran"]):
			_gran = true
			_gran_contraataque(ola, o)


## Arma la fase: sus alemanes, los nidos de MG42 y los refuerzos.
func _empezar(f: int) -> void:
	var primera := fase_lista < 0
	fase_lista = f
	var d := Misiones.fase(f)
	# Si la misión se dejó para después en la campaña, llegan más refuerzos
	restantes = int(round(float(d.get("refuerzos", {}).get("n", 0)) * Campana.factor_refuerzos()))
	_t_refuerzo = _rng.randf_range(30.0, 45.0)
	_t_mortero = 22.0 if primera else 14.0
	_olas = 0
	_t_ola = 5.0
	_gran = false
	_mgs_ola = []
	var usados: Array = []
	if d.has("retirar_z") and not primera:
		_retirar(float(d["retirar_z"]))
	for g in d.get("alemanes", []):
		for pos in _lugares(g[0], int(g[1]), usados, 25.0):
			_cola.append([pos, Armas.botin_aleman(_rng),
				"flanqueador" if _rng.randf() < 0.3 else "defensor", Vector3.ZERO])
	for i in Objetivos.LISTA.size():
		var o: Dictionary = Objetivos.LISTA[i]
		if o["fase"] == f and o["tipo"] == "mg" and not Objetivos.hecho[i]:
			nidos[i] = _aleman(_cobertura_cerca(o["nido"], 6.0), "mg42", "fijo")


## Los alemanes que quedaron atrás del frente se rinden (salen del mapa), salvo
## los que tienen un jugador cerca: así no se juntan los de todas las fases.
func _retirar(z: float) -> void:
	var jugadores: Array = get_tree().get_nodes_in_group("americanos").filter(
		func(a: Node) -> bool: return a is Player or a is JugadorRemoto)
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e is Enemy or e.dead or e.global_position.z < z:
			continue
		var cerca := false
		for j in jugadores:
			if j.global_position.distance_to(e.global_position) < 25.0:
				cerca = true
		if not cerca:
			e.queue_free()
			n += 1
	if n > 0:
		Red.anunciar("[%d ALEMANES SE RINDEN ATRÁS DEL FRENTE]" % n, Game.COLOR_GOOD)


## El objetivo "defender" que está corriendo (o -1).
func _defensa_activa() -> int:
	for i in Objetivos.LISTA.size():
		if Objetivos.LISTA[i]["tipo"] == "defender" and Objetivos.activo(i):
			return i
	return -1


## Una ola del contraataque: alemanes que salen de uno o dos bordes y avanzan
## sobre el lugar. Si ya hay muchos vivos, esa ola no sale (que se pueda
## aguantar). Opciones de la misión (v0.32):
##   pueblo   con la primera ola, los alemanes que quedaban en el pueblo también
##            salen al contraataque (antes se quedaban quietos en sus casas)
##   mg       desde la 2.a ola, cada dos olas llega un equipo de MG42 que se
##            instala a ~36 m del lugar y lo barre (máx. 2 a la vez)
##   gran     al llegar a esa fracción del reloj sale el gran contraataque
##   crece    cuántos hombres más trae cada ola, como máximo (2 por defecto)
func _ola(i: int, o: Dictionary) -> void:
	var meta: Vector3 = Objetivos.LISTA[i]["pos"]
	if _olas == 0 and o.get("pueblo", false):
		_sale_el_pueblo(meta)
	if get_tree().get_nodes_in_group("enemies").size() >= int(o.get("max_vivos", 16)):
		return
	_olas += 1
	var desde: Array = o["desde"]
	var n := int(o["n"]) + mini(_olas - 1, int(o.get("crece", 2)))
	# Desde la 2.a ola atacan por dos lados a la vez (hay que repartirse)
	var bases := [desde[_rng.randi() % desde.size()]]
	if _olas >= 2 and desde.size() > 1:
		var otra: Vector3 = desde[_rng.randi() % desde.size()]
		while otra == bases[0]:
			otra = desde[_rng.randi() % desde.size()]
		bases.append(otra)
	for k in n:
		_asalto(bases[k % bases.size()], meta)
	if o.get("mg", false) and _olas >= 2 and _olas % 2 == 0:
		_mg_de_ola(bases[0], meta, i)
	Red.anunciar("[¡CONTRAATAQUE ALEMÁN! - OLA %d]" % _olas, Game.COLOR_BAD)


func _asalto(base: Vector3, meta: Vector3) -> void:
	var p := Navegacion.cerca_de(base + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-4, 4)))
	_cola.append([p, ["kar98k", "kar98k", "mp40", "stg44"][_rng.randi() % 4], "asalto",
		meta + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))])


## Los alemanes que siguen en el pueblo (no los de las MG42) salen sobre el lugar.
func _sale_el_pueblo(meta: Vector3) -> void:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and not e.dead and e.rol != "fijo" and e.rol != "asalto" \
				and e.global_position.distance_to(meta) > 14.0:
			e.rol = "asalto"
			e.meta = meta + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
			e._alert = maxf(e._alert, 0.5)
			n += 1
	if n > 0:
		Red.anunciar("[¡LOS DEL PUEBLO SALEN AL CONTRAATAQUE!]", Game.COLOR_BAD)


## Un equipo de MG42 se instala a ~36 m del lugar, del lado de donde vino la ola.
func _mg_de_ola(base: Vector3, meta: Vector3, i: int) -> void:
	_mgs_ola = _mgs_ola.filter(func(e: Variant) -> bool: return is_instance_valid(e) and not e.dead)
	if _mgs_ola.size() >= 2:
		return
	var dir := base - meta
	dir.y = 0.0
	var punto := meta + dir.normalized() * 36.0 + Vector3(_rng.randf_range(-8, 8), 0, 0)
	var pos := _cobertura_cerca(Navegacion.cerca_de(punto), 10.0)
	var e := _aleman(pos, "mg42", "fijo")
	e._alert = 0.5
	_mgs_ola.append(e)
	Red.anunciar(Objetivos.LISTA[i].get("txt_mg", "[¡UNA MG42 SE INSTALA FRENTE AL CRUCE!]"), Game.COLOR_BAD)


## El gran contraataque: por todos los lados a la vez, con más hombres de lo normal.
func _gran_contraataque(i: int, o: Dictionary) -> void:
	var meta: Vector3 = Objetivos.LISTA[i]["pos"]
	var desde: Array = o["desde"]
	var vivos := get_tree().get_nodes_in_group("enemies").size()
	var n := mini(int(o["n"]) * 2 + 2, int(o.get("max_vivos", 16)) + 8 - vivos)
	for k in maxi(n, 4):
		_asalto(desde[k % desde.size()], meta)
	if o.get("mg", false):
		_mg_de_ola(desde[0], meta, i)
	_t_mortero = 2.0
	_t_ola = maxf(_t_ola, 20.0)
	Red.anunciar("[¡GRAN CONTRAATAQUE ALEMÁN! ¡AGUANTEN!]", Game.COLOR_BAD)


func _nuevo(pos: Vector3, arma: String, rol: String) -> Enemy:
	var e := _aleman(pos, arma, rol)
	e.granadas = 0
	return e


func _aleman(pos: Vector3, arma: String, rol: String) -> Enemy:
	var e := Enemy.new()
	e.arma = arma
	e.rol = rol
	e.granadas = 0
	var enemigos := get_parent().get_node_or_null("Enemies")
	(enemigos if enemigos else get_parent()).add_child(e)
	e.global_position = pos
	e.rotation.y = 0.0 if rol == "asalto" else PI
	return e


func _lugar(zona: Array, usados: Array, lejos: float) -> Vector3:
	return _lugares(zona, 1, usados, lejos)[0]


## `n` lugares libres para alemanes dentro de `zona` ([x_min, x_max, z_min, z_max]):
## coberturas que tapen hacia los americanos (hacia +Z) y a más de `lejos` m
## de cualquier americano (que no aparezcan delante de sus narices).
func _lugares(zona: Array, n: int, usados: Array, lejos: float) -> Array:
	var americanos := get_tree().get_nodes_in_group("americanos").map(
		func(a: Node3D) -> Vector3: return a.global_position)
	var libres: Array = []
	for c in Coberturas.puntos:
		var pos: Vector3 = c["pos"]
		if pos.x < zona[0] or pos.x > zona[1] or pos.z < zona[2] or pos.z > zona[3]:
			continue
		if c["n"].z < 0.5 or c["parcial"] or pos in usados:
			continue
		if c["ocupado"] != null and is_instance_valid(c["ocupado"]):
			continue
		var ok := true
		for a in americanos:
			if a.distance_to(pos) < lejos:
				ok = false
				break
		if ok:
			libres.append(pos)
	var lista: Array = []
	for k in n:
		var p: Vector3
		if libres.is_empty():
			p = Navegacion.cerca_de(Vector3(_rng.randf_range(zona[0], zona[1]), float(Misiones.actual().get("suelo", 14.0)), zona[2] + 2.0))
		else:
			p = libres.pop_at(_rng.randi() % libres.size())
			# que no queden dos pegados (los puntos de un muro están cada 1,4 m)
			libres = libres.filter(func(q: Vector3) -> bool: return q.distance_to(p) > 2.5)
		usados.append(p)
		lista.append(p)
	return lista


## Otro alemán toma la MG42 de un nido (nadie llegó a tomarlo a tiempo).
func reponer_nido(i: int) -> void:
	if not Navegacion.listo:
		return
	nidos[i] = _aleman(_cobertura_cerca(Objetivos.LISTA[i]["nido"], 6.0), "mg42", "fijo")


## Traspaso de anfitrión: los tiradores de MG42 que ya había (títeres hechos
## soldados) vuelven a ser los de cada nido de la fase.
func adoptar_nidos(mgs: Array) -> void:
	for i in Objetivos.LISTA.size():
		var o: Dictionary = Objetivos.LISTA[i]
		if o["tipo"] != "mg" or not Objetivos.activo(i):
			continue
		var mejor: Enemy = null
		for e in mgs:
			if e.global_position.distance_to(o["nido"]) < 8.0 and (mejor == null or
					e.global_position.distance_to(o["nido"]) < mejor.global_position.distance_to(o["nido"])):
				mejor = e
		nidos[i] = mejor


func _cobertura_cerca(pos: Vector3, radio: float) -> Vector3:
	var mejor := pos
	var mejor_d := radio
	for c in Coberturas.puntos:
		var n: Vector3 = c["n"]
		var d: float = pos.distance_to(c["pos"])
		if n.z > 0.5 and d < mejor_d and (c["ocupado"] == null or not is_instance_valid(c["ocupado"])):
			mejor_d = d
			mejor = c["pos"]
	return mejor


## Un alemán cerca del frente dispara una bengala sobre un jugador (o cerca).
func _bengala() -> void:
	var jugadores: Array = get_tree().get_nodes_in_group("americanos").filter(
		func(a: Node) -> bool: return (a is Player or a is JugadorRemoto) and not a.dead \
			and Game.elapsed >= float(a.get_meta("gracia_hasta", -1.0)))
	if jugadores.is_empty():
		return
	var j: Node3D = jugadores[_rng.randi() % jugadores.size()]
	var desde := Vector3.INF
	var mejor := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(j.global_position)
		if d > 22.0 and d < 95.0 and absf(d - 50.0) < mejor:
			mejor = absf(d - 50.0)
			desde = e.global_position + Vector3(0, 1.5, 0)
	if desde == Vector3.INF:
		return
	var hacia := j.global_position + Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 6))
	Bengala.disparar(get_parent(), desde, hacia)
	Red.bengala(desde, hacia)
	if _avisos_bengala < 3 and Escuadras.actual:
		_avisos_bengala += 1
		for a in Escuadras.ranuras_jugador():
			if a and is_instance_valid(a) and not a.dead and not a.has_meta("perdido"):
				Game.say("[%s: ¡BENGALA! ¡CUERPO A TIERRA!]" % a.nombre, Game.COLOR_BAD)
				return
		Game.say("[¡BENGALA! ¡CUERPO A TIERRA! (MANTÉN AGACHAR)]", Game.COLOR_BAD)


## Un mortero: silbido y, 1,3 s después, la explosión.
func _mortero() -> void:
	var blancos := get_tree().get_nodes_in_group("americanos").filter(
		func(b: Node) -> bool: return not b.dead and b.global_position.z < 9.0)
	if blancos.is_empty():
		return
	var b: Node3D = blancos[_rng.randi() % blancos.size()]
	if (b is Player or b is JugadorRemoto) and _rng.randf() < 0.6:   # al jugador lo eligen menos
		b = blancos[_rng.randi() % blancos.size()]
	var lejos := _rng.randf_range(5.0, 9.0) if (b is Player or b is JugadorRemoto) else _rng.randf_range(1.5, 7.0)
	var ang := _rng.randf() * TAU
	var pos := b.global_position + Vector3(cos(ang), 0, sin(ang)) * lejos
	pos = Navegacion.cerca_de(pos) + Vector3(0, 0.1, 0)
	Game.play_at("silbido", pos, 2.0)
	Red.silbido(pos)
	await get_tree().create_timer(1.3).timeout
	if is_inside_tree():
		Game.explode(pos, 6.0, 150.0)
