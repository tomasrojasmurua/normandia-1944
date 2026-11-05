extends Node
class_name Noche
## Misiones de noche (sección 6, misión 2: el planeador). Se crea si la misión
## tiene "clima": "noche" y se encarga de:
## - La luz: luna llena (luz direccional fría con su disco en el cielo), cielo
##   y niebla azul oscuros, luz ambiente baja. Las imágenes que no reciben luz
##   (setos, árboles, pasto, alambre: "unshaded") se tiñen con `tinte` para
##   que no brillen como de día (ver `tenir`).
## - Las luces que importan: bengalas alemanas (bengala.gd) y fuegos (los
##   planeadores estrellados, casas): en `luces`. Iluminan de verdad (OmniLight)
##   y dicen quién se ve.
## - La vista de noche (`factor_vista`): de pie se te ve a ~la mitad de lo
##   normal; agachado, menos; cuerpo a tierra, casi nada. Bajo una bengala o
##   junto a un fuego, de pie te ven como de día; tirado al suelo, no. Al
##   disparar, el fogonazo te delata unos segundos. Vale para los dos bandos.
## - El amanecer (`amanecer` 0 → 1): en la última fase el cielo se va aclarando
##   mientras dura la defensa; al final es de día (y la vista, normal).
## Todo es estático (como Objetivos o Coberturas): lo leen los soldados y el
## HUD sin buscar el nodo.

static var actual: Noche
static var activa := false
static var amanecer := 0.0           # 0 = noche cerrada, 1 = ya amaneció
## Bengalas y fuegos encendidos: {"nodo": Node3D, "radio": m, "fuerza": 0..1}
static var luces: Array = []
## Materiales "unshaded" teñidos: [material, color de día]
static var _tenidos: Array = []
static var tinte := Color.WHITE      # color por el que se multiplican

# --- Los dos extremos (se mezclan con `amanecer`)
const NOCHE := {
	"cielo_arriba": Color(0.012, 0.018, 0.04), "cielo_horizonte": Color(0.07, 0.09, 0.15),
	"suelo": Color(0.01, 0.012, 0.018),
	"ambiente": Color(0.3, 0.36, 0.55), "ambiente_e": 0.4,
	"niebla": Color(0.04, 0.055, 0.095), "niebla_d": 0.021,
	"luz": Color(0.58, 0.68, 1.0), "luz_e": 0.32,
	"tinte": Color(0.3, 0.35, 0.48),
}
const ALBA := {
	"cielo_arriba": Color(0.3, 0.37, 0.5), "cielo_horizonte": Color(0.92, 0.62, 0.42),
	"suelo": Color(0.22, 0.2, 0.18),
	"ambiente": Color(0.66, 0.62, 0.6), "ambiente_e": 0.6,
	"niebla": Color(0.6, 0.54, 0.52), "niebla_d": 0.013,
	"luz": Color(1.0, 0.78, 0.58), "luz_e": 0.8,
	"tinte": Color(0.8, 0.76, 0.74),
}
## Dirección de donde viene la luz (luna al suroeste, alta; sol saliendo por el este)
const DIR_LUNA := Vector3(-0.45, 0.62, 0.65)
const DIR_SOL := Vector3(0.95, 0.12, -0.1)

const VISTA := [0.5, 0.34, 0.16]          # de noche, de pie / agachado / cuerpo a tierra
const VISTA_LUZ := [1.0, 0.62, 0.16]      # bajo una bengala o junto a un fuego
const DELATA_DISPARO := 2.5               # segundos que el fogonazo te deja a la vista

var _env: Environment
var _cielo: ProceduralSkyMaterial
var _luz: DirectionalLight3D
var _visto := -1.0


## ¿La misión en curso es de noche?
static func de_noche() -> bool:
	return str(Misiones.actual().get("clima", "")) == "noche"


## Prepara la noche en la escena (lo llama el mapa ANTES de armar el decorado,
## para que `tenir` ya tiña lo que se crea).
static func preparar(escena: Node) -> Noche:
	activa = de_noche()
	amanecer = 0.0
	luces.clear()
	_tenidos.clear()
	tinte = NOCHE["tinte"] if activa else Color.WHITE
	var n := Noche.new()
	n.name = "Noche"
	escena.add_child.call_deferred(n)
	return n


func _ready() -> void:
	actual = self
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		_env = we.environment
		_cielo = ProceduralSkyMaterial.new()
		_cielo.sun_angle_max = 6.0
		_cielo.sun_curve = 0.05
		_cielo.sky_curve = 0.25
		_cielo.ground_curve = 0.1
		var sky := Sky.new()
		sky.sky_material = _cielo
		_env.sky = sky
		_env.background_mode = Environment.BG_SKY
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.fog_enabled = true
		_env.fog_sky_affect = 0.35
	_luz = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if _luz:
		_luz.light_angular_distance = 1.6     # el disco de la luna en el cielo
		_luz.shadow_enabled = false
	_aplicar(0.0)


func _exit_tree() -> void:
	if actual == self:
		actual = null
		activa = false
		luces.clear()
		_tenidos.clear()


func _process(_delta: float) -> void:
	if not activa:
		return
	# El amanecer sigue a la defensa de la última fase (o al reloj, si no hay)
	var meta := 0.0
	if Objetivos.actual and Objetivos.terminado == 0:
		var f := Objetivos.fase()
		if f == Objetivos.n_fases() - 1:
			for i in Objetivos.LISTA.size():
				var o: Dictionary = Objetivos.LISTA[i]
				if o["fase"] == f and o["tipo"] == "defender":
					meta = maxf(meta, 0.12 + 0.88 * smoothstep(0.0, 1.0, clampf(Objetivos.progreso[i], 0.0, 1.0)))
	elif Objetivos.terminado == 1:
		meta = 1.0
	if meta < amanecer:
		meta = amanecer        # no vuelve a oscurecer
	amanecer = move_toward(amanecer, meta, _delta * 0.05)
	if absf(amanecer - _visto) > 0.004:
		_aplicar(amanecer)
	# Se olvidan las luces que se apagaron
	for i in range(luces.size() - 1, -1, -1):
		if not is_instance_valid(luces[i]["nodo"]):
			luces.remove_at(i)


func _aplicar(t: float) -> void:
	_visto = t
	var k := t
	if not activa:
		return
	var c := func(clave: String):
		var a = NOCHE[clave]
		var b = ALBA[clave]
		return lerp(a, b, k)
	if _cielo:
		_cielo.sky_top_color = c.call("cielo_arriba")
		_cielo.sky_horizon_color = c.call("cielo_horizonte")
		_cielo.ground_horizon_color = c.call("cielo_horizonte")
		_cielo.ground_bottom_color = c.call("suelo")
		_cielo.sun_angle_max = lerpf(6.0, 30.0, k)
		_cielo.sky_energy_multiplier = lerpf(1.0, 1.0, k)
	if _env:
		_env.ambient_light_color = c.call("ambiente")
		_env.ambient_light_energy = c.call("ambiente_e")
		_env.fog_light_color = c.call("niebla")
		_env.fog_density = c.call("niebla_d")
	if _luz:
		_luz.light_color = c.call("luz")
		_luz.light_energy = c.call("luz_e")
		# La luna se pone y el sol sale: la luz pasa por el horizonte (con poca fuerza)
		var dir: Vector3 = DIR_LUNA.slerp(DIR_SOL, k).normalized() if k < 1.0 else DIR_SOL.normalized()
		_luz.look_at_from_position(Vector3(0, 30, 0), Vector3(0, 30, 0) - dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	tinte = c.call("tinte")
	for par in _tenidos:
		var m: BaseMaterial3D = par[0]
		if is_instance_valid(m):
			m.albedo_color = par[1] * tinte


## Tiñe un material "unshaded" (no recibe luz) para la noche: guarda su color de
## día y lo multiplica por el tinte (también al amanecer). Sin noche, no hace nada.
static func tenir(m: BaseMaterial3D) -> void:
	if not activa or m == null:
		return
	var base := m.albedo_color
	_tenidos.append([m, base])
	m.albedo_color = base * tinte


# ================================================================ luces y vista

static func agregar_luz(nodo: Node3D, radio: float) -> Dictionary:
	var l := {"nodo": nodo, "radio": radio, "fuerza": 1.0}
	luces.append(l)
	return l


static func quitar_luz(nodo: Node3D) -> void:
	for i in range(luces.size() - 1, -1, -1):
		if luces[i]["nodo"] == nodo:
			luces.remove_at(i)


## Cuánta luz (bengala o fuego) hay en un punto: 0 = solo la luna, 1 = a pleno.
static func luz_en(pos: Vector3) -> float:
	var mejor := 0.0
	for l in luces:
		var n: Node3D = l["nodo"]
		if not is_instance_valid(n):
			continue
		var r: float = l["radio"]
		var d := n.global_position.distance_to(pos)
		if d < r:
			mejor = maxf(mejor, clampf((1.0 - d / r) * 2.2, 0.0, 1.0) * float(l["fuerza"]))
	return mejor


## 0 de pie, 1 agachado (o de rodillas), 2 cuerpo a tierra (o escondido tras la cobertura).
static func _pose(b: Node3D) -> int:
	if b is Player:
		return 2 if b.prone else (1 if b.crouching else 0)
	var cuerpo = b.get("cuerpo")
	if cuerpo:
		match str(cuerpo.pose):
			"agachado":
				return 2 if b.get("en_cobertura") and not b.get("moviendo") else 1
			"rodilla":
				return 1
	if b.get("prone"):
		return 2
	if b.get("crouching"):
		return 1
	return 0


## Por cuánto se multiplica el alcance de la vista para ver a `b` (1 de día).
static func factor_vista(b: Node3D) -> float:
	if not activa or amanecer >= 1.0:
		return 1.0
	var pose := _pose(b)
	var f: float = VISTA[pose]
	var luz := luz_en(b.global_position)
	if luz > 0.0:
		f = maxf(f, lerpf(f, VISTA_LUZ[pose], luz))
	if Game.elapsed - float(b.get_meta("disparo_t", -100.0)) < DELATA_DISPARO and pose < 2:
		f = maxf(f, 0.9)
	elif Game.elapsed - float(b.get_meta("disparo_t", -100.0)) < DELATA_DISPARO:
		f = maxf(f, 0.6)
	return lerpf(f, 1.0, amanecer)


## El color con que se ve el arma en la mano (HUD): oscuro de noche, más claro
## junto a una luz, y blanco al disparar (el fogonazo).
static func tinte_vista(p: Node3D) -> Color:
	if not activa:
		return Color.WHITE
	var c := tinte.lerp(Color.WHITE, 0.15)
	var luz := luz_en(p.global_position)
	c = c.lerp(Color(1.0, 0.95, 0.86), luz * 0.7)
	if Game.elapsed - float(p.get_meta("disparo_t", -100.0)) < 0.07:
		c = Color.WHITE
	return c
