extends Combatiente
class_name Enemy
## Soldado alemán. Defiende la playa y reacciona:
## - Ve a los americanos (el jugador y la escuadra), elige al más cercano
##   (el jugador atrae un poco más de fuego) y le dispara según su arma: el
##   Kar98k tiro a tiro, la MP40 y el StG44 en ráfagas cortas, la MG42 larga.
## - Detrás de sacos de arena se agacha y se asoma de rodillas para disparar.
## - Si lo flanquean (lo ven desde un lado donde su cobertura no tapa), corre a
##   otra cobertura que sí lo proteja.
## - Si lo presionan (le pegan y el enemigo está cerca), se repliega hacia el
##   búnker.
## - Los "flanqueador" contraatacan: si te quedas quieto mucho rato, corren a
##   una cobertura de costado para dispararte desde otro ángulo.
## - Los "fijo" no se mueven (el del techo del búnker).
## El cuerpo y sus animaciones están en soldado.gd; lo común, en combatiente.gd.

@export var sight_range := 55.0
@export var damage := 12.0                  # daño de un tiro que acierta (fusil)
@export var reaction_time := 1.4            # segundos que tarda en disparar tras verte
@export var fire_interval := Vector2(3.0, 5.0)
@export var accuracy := 1.0                 # multiplicador de puntería (1 = normal)
@export var granadas := -1                  # -1 = al azar (0 o 1)
## "defensor" (se mueve entre coberturas y se repliega), "flanqueador"
## (además contraataca por los costados) o "fijo" (no se mueve).
@export var rol := "defensor"

const BUNKER := Vector3(0, 0, -42)

var _player: Player
var _sees := false
var _alert := 0.0
var _blanco_desde := 0.0        # desde cuándo apunta al blanco actual
var _los_timer := 0.0
var _fire_timer := 0.0
var _rafaga := 0                # balas que quedan en la ráfaga en curso
var _rafaga_t := 0.0
var _asomado := 0.0             # >0: tiempo que le queda asomado
var _pensar_t := 0.0
var _ultimo_dano := -100.0
var _quieto_desde := 0.0        # Game.elapsed desde que no se mueve
var _prox_flanqueo := 0.0
var _amenaza_quieta := 0.0      # cuánto rato el blanco no se mueve mucho
var _amenaza_ref := Vector3.ZERO

static var _ultima_granada := -100.0   # segundos (Game.elapsed) de la última granada alemana
static var _ultimo_aviso := -100.0


func _ready() -> void:
	add_to_group("enemies")
	health = minf(health, 60.0)   # un tiro de fusil al cuerpo mata (Garand 100, carabina 60)
	collision_layer = 4          # capa 3: enemigos
	collision_mask = 1 | 2
	_fire_timer = randf_range(fire_interval.x, fire_interval.y) * 0.5
	if arma == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		arma = Armas.botin_aleman(rng)
	if granadas < 0:
		granadas = 1 if randf() < 0.5 else 0
	_los_timer = randf() * 0.3
	_pensar_t = randf_range(0.5, 1.5)
	_prox_flanqueo = randf_range(15.0, 25.0)
	amenaza = global_position + Vector3(0, 0, 30)   # hacia el mar
	_crear_cuerpo("aleman")
	tomar_cobertura_inicial.call_deferred()


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	_seguir_pose()

	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.3
		var antes := objetivo
		objetivo = elegir_objetivo("americanos", sight_range)
		# Que no le disparen más de 4 a la vez a un jugador (3 en el cooperativo,
		# donde no hay escuadras con IA que repartan el fuego): el resto busca otro
		if (objetivo is Player or objetivo is JugadorRemoto) and objetivo != antes \
				and _tiradores_a(objetivo) >= (3 if Game.modo_red else 4):
			objetivo = elegir_objetivo("americanos", sight_range, null, objetivo)
		if objetivo != antes:
			_blanco_desde = Game.elapsed
		_sees = objetivo != null
		if _sees:
			_actualizar_amenaza(objetivo.global_position)

	if not is_instance_valid(objetivo):   # sin blanco, o el jugador tomó su lugar (liberado)
		objetivo = null
		_sees = false
	if moviendo:     # corre en _process (combatiente.gd), cuadro a cuadro
		_rafaga = 0
		return

	_pensar_t -= delta
	if _pensar_t <= 0.0:
		_pensar_t = randf_range(0.9, 1.4)
		_pensar()
		if moviendo:
			return

	if _rafaga > 0:   # ráfaga en curso
		_rafaga_t -= delta
		if _rafaga_t <= 0.0:
			_rafaga -= 1
			_rafaga_t = Armas.datos(arma)["interval"] * randf_range(1.0, 1.4)
			if objetivo and not objetivo.dead:
				_shoot()

	if _sees:
		_alert += delta
		var to := objetivo.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), delta * 4.0)
		cuerpo.apuntar_a = objetivo.pos_cabeza() - Vector3(0, 0.3, 0)
		if not en_cobertura:
			cuerpo.pose = "pie" if _alert > 0.3 else "reposo"
		if _alert >= reaction_time:
			_fire_timer -= delta
			# Desde la cobertura se asoma un poco antes de disparar
			if en_cobertura and _fire_timer < 0.7 and _asomado <= 0.0:
				_asomado = 0.7 + _duracion_rafaga() + randf_range(0.4, 1.0)
			if _fire_timer <= 0.0 and _rafaga == 0:
				_fire_timer = randf_range(fire_interval.x, fire_interval.y)
				if not _intentar_granada(to.length()):
					_empezar_rafaga()
	else:
		_alert = maxf(_alert - delta * 0.5, 0.0)
		if not en_cobertura and _alert < 0.2:
			cuerpo.pose = "reposo"

	if en_cobertura:
		_asomado -= delta
		cuerpo.pose = "rodilla" if _asomado > 0.0 or _rafaga > 0 else "agachado"


func _tiradores_a(blanco: Node) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.objetivo == blanco:
			n += 1
	return n


func _actualizar_amenaza(pos: Vector3) -> void:
	if pos.distance_to(_amenaza_ref) > 4.0:
		_amenaza_ref = pos
		_amenaza_quieta = Game.elapsed
	amenaza = pos


# ================================================================ decidir

func _pensar() -> void:
	if rol == "fijo" or not Navegacion.listo:
		return
	var aviso := _alert > 0.1 or Game.elapsed - _ultimo_dano < 6.0
	if not aviso:
		return          # todavía no sabe dónde están los americanos
	var dist := global_position.distance_to(amenaza)
	var presion := Game.elapsed - _ultimo_dano < 4.0

	# 1. Sin cobertura (o lo flanquearon): buscar una que lo tape
	if cobertura.is_empty() or Coberturas.protege(cobertura, amenaza) < 0.35:
		if _ir(_buscar(18.0, 0.0)):
			return
	# 2. Presionado y cerca: replegarse hacia el búnker
	if presion and (dist < 14.0 or health < 50.0):
		if _ir(_buscar(22.0, 5.0)):
			_avisar("[SE REPLIEGAN]", Game.COLOR_INFO)
			return
	# 3. Contraataque por el costado si el blanco lleva rato en el mismo lugar
	if rol == "flanqueador" and Game.elapsed > _prox_flanqueo \
			and Game.elapsed - _amenaza_quieta > 8.0 and dist > 12.0 and dist < 45.0:
		_prox_flanqueo = Game.elapsed + randf_range(20.0, 30.0)
		if _ir(_buscar_flanco()):
			_avisar("[¡NOS FLANQUEAN!]", Game.COLOR_BAD)
			return
	# 4. De vez en cuando cambia a una cobertura vecina (no quedarse clavado)
	if Game.elapsed - _quieto_desde > randf_range(18.0, 30.0) and randf() < 0.25:
		_quieto_desde = Game.elapsed
		_ir(_buscar(9.0, -2.0, 2.5))


## Mensaje en el HUD, sin repetirlo a cada rato.
func _avisar(texto: String, color: Color) -> void:
	if Game.elapsed - _ultimo_aviso > 8.0:
		_ultimo_aviso = Game.elapsed
		Red.anunciar(texto, color)


func _ir(p: Dictionary) -> bool:
	if p.is_empty() or p == cobertura:
		return false
	return ir_a(p)


func _al_llegar() -> void:
	_quieto_desde = Game.elapsed
	_alert = minf(_alert, reaction_time * 0.6)   # tarda un poco en volver a apuntar


## Cobertura que lo tape contra la amenaza, a menos de `radio` m.
## `atras` = cuántos metros más lejos de la amenaza tiene que quedar
## (positivo = replegarse; negativo = puede avanzar un poco).
## `minimo` = distancia mínima (para no elegir la de al lado).
func _buscar(radio: float, atras: float, minimo := 0.0) -> Dictionary:
	var yo := global_position
	var dist_ahora := yo.distance_to(amenaza)
	return Coberturas.mejor(self, func(p: Dictionary) -> float:
		var pos: Vector3 = p["pos"]
		var viaje := yo.distance_to(pos)
		if viaje > radio or viaje < minimo or absf(pos.y - yo.y) > 1.5:
			return -INF
		var prot := Coberturas.protege(p, amenaza)
		if prot < 0.5:
			return -INF
		var lejos := pos.distance_to(amenaza)
		if lejos < dist_ahora + atras or lejos < 7.0:
			return -INF
		# Prefiere: que proteja bien, cerca del búnker, y no correr tanto
		return prot * 4.0 - viaje * 0.25 - pos.distance_to(BUNKER) * 0.05)


## Cobertura de costado: protege del blanco y lo ve desde otro ángulo que el búnker.
func _buscar_flanco() -> Dictionary:
	var yo := global_position
	var frente := (BUNKER - amenaza)
	frente.y = 0.0
	frente = frente.normalized()
	return Coberturas.mejor(self, func(p: Dictionary) -> float:
		var pos: Vector3 = p["pos"]
		var viaje := yo.distance_to(pos)
		if viaje > 30.0 or absf(pos.y - yo.y) > 1.5:
			return -INF
		if Coberturas.protege(p, amenaza) < 0.5:
			return -INF
		var lado := pos - amenaza
		lado.y = 0.0
		var d := lado.length()
		if d < 10.0 or d > 30.0:
			return -INF
		var angulo := rad_to_deg(frente.angle_to(lado / d))
		if angulo < 40.0:
			return -INF
		return angulo * 0.05 - viaje * 0.15)


# ================================================================ disparar

func _duracion_rafaga() -> float:
	var d := Armas.datos(arma)
	return d["interval"] * _balas_por_rafaga() * 1.2 if d["auto"] else 0.0


func _balas_por_rafaga() -> int:
	match arma:
		"mg42": return randi_range(8, 14)
		"mp40", "stg44": return randi_range(3, 6)
		_: return 1


func _empezar_rafaga() -> void:
	_rafaga = _balas_por_rafaga()
	_rafaga_t = 0.0 if not en_cobertura else 0.35   # si se está asomando, espera a apuntar


func _shoot() -> void:
	var auto: bool = Armas.datos(arma)["auto"]
	var dist := global_position.distance_to(objetivo.global_position)
	var chance := lerpf(0.35, 0.05, clampf(dist / sight_range, 0.0, 1.0)) * accuracy
	if auto:
		chance *= 0.4      # las ráfagas son menos precisas, pero son muchas balas
	chance *= objetivo.factor_blanco()
	# Los primeros tiros a un blanco nuevo pasan cerca (avisan): la puntería
	# llega a su máximo después de ~3 s siguiéndolo. Da tiempo a cubrirse.
	chance *= clampf((Game.elapsed - _blanco_desde - 0.5) / 2.0, 0.2, 1.0)
	if tiro_ia(objetivo, chance, 2.0):
		# Letal: un tiro de fusil (Kar98k: 115) mata; las automáticas, 2 o 3 balas
		objetivo.take_damage(Armas.datos(arma)["damage"], global_position)


## Granada de palo: si el blanco está entre 9 y 26 m, y nadie lanzó una hace poco.
func _intentar_granada(dist: float) -> bool:
	if granadas <= 0 or dist < 9.0 or dist > 26.0 or Game.elapsed - _ultima_granada < 9.0:
		return false
	if randf() > 0.35:
		return false
	granadas -= 1
	_ultima_granada = Game.elapsed
	_asomado = 1.2
	var g := Grenade.new()
	g.modelo_aleman()
	get_parent().add_child(g)
	var desde: Vector3 = cuerpo.pos_cabeza() + Vector3(0, 0.3, 0) - global_basis.z * 0.5
	g.global_position = desde
	g.add_collision_exception_with(self)
	# Tiro parabólico al blanco (con error de hasta 3 m)
	var blanco := objetivo.global_position + Vector3(randf_range(-3, 3), 0.1, randf_range(-3, 3))
	var t := clampf(dist / 13.0, 0.9, 2.2)
	var v := (blanco - desde - 0.5 * Vector3(0, -9.8, 0) * t * t) / t
	g.linear_velocity = v
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))
	Red.granada(desde, v)   # que los invitados la vean volar
	Game.play_at("throw", desde, 0.0)
	Red.anunciar("[¡GRANADA!]", Game.COLOR_BAD)
	return true


# ================================================================ recibir

## Recibe un impacto (bala o explosión).
func hit(amount: float, headshot: bool, pos: Vector3, dir: Vector3, por_jugador := true) -> void:
	if dead:
		return
	health -= amount * (2.0 if headshot else 1.0)
	Game.blood(pos)
	cuerpo.impacto(dir)
	_ultimo_dano = Game.elapsed
	_alert = maxf(_alert, reaction_time * 0.5)  # se pone alerta al recibir fuego
	if amenaza.distance_to(global_position) > 60.0 or not _sees:
		amenaza = global_position - dir * 20.0     # sabe más o menos de dónde vino
	if health <= 0.0:
		_die(dir, headshot, por_jugador)


func _die(dir: Vector3, headshot: bool, por_jugador := true) -> void:
	dead = true
	_rafaga = 0
	moviendo = false
	Coberturas.liberar(self)
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	if por_jugador:   # los que abaten las escuadras con IA no se anuncian (serían demasiados)
		Game.say("[ENEMIGO ABATIDO]" if not headshot else "[ABATIDO - TIRO A LA CABEZA]")
	if get_tree().get_nodes_in_group("enemies").is_empty() and (Defensa.restantes <= 0 or Game.prueba_carga):
		Red.anunciar("[ZONA DESPEJADA]", Game.COLOR_GOOD)
	cuerpo.andar = ""
	cuerpo.morir(dir, headshot)
	_soltar_arma(dir)
	Red.murio(self, dir, headshot)
	Game.bajas += 1
