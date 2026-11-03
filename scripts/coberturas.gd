extends RefCounted
class_name Coberturas
## Puntos de cobertura del escenario: dónde puede esconderse un soldado.
## beach_decor.gd los registra al construir la playa (sacos de arena, erizos,
## búnker). Cada punto sabe desde qué lado protege (`n`: dirección del punto
## hacia el obstáculo) y quién lo ocupa, para que dos soldados no se pisen.
##
## Punto = {pos: Vector3, n: Vector3, bajo: bool, parcial: bool, ocupado: Node}
##   bajo    = obstáculo bajo: se esconde agachado y se asoma de rodillas.
##   parcial = solo tapa una parte (erizo checo): ayuda, pero no del todo.

static var puntos: Array[Dictionary] = []


static func limpiar() -> void:
	puntos.clear()


static func _agregar(pos: Vector3, n: Vector3, bajo: bool, parcial: bool) -> void:
	if pos.y > 0.3 and pos.z < -56.3 and pos.z > -80.5:   # en la ladera: a la altura del terreno
		pos.y = Ambiente.alto_acantilado(pos.z)
	puntos.append({"pos": pos, "n": n.normalized(), "bajo": bajo, "parcial": parcial, "ocupado": null})


## Muro (sacos de arena, concreto): puntos a lo largo de los dos lados.
## `yaw` en grados, como en beach_decor; `prof` = grosor; `alto` = altura.
static func agregar_muro(centro: Vector3, largo: float, yaw: float, prof: float, alto: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var cuantos := maxi(1, int(largo / 1.4))
	var piso := Vector3(centro.x, centro.y, centro.z)
	for lado in [-1.0, 1.0]:
		var fuera: Vector3 = b.z * lado * (prof / 2.0 + 0.5)
		for i in cuantos:
			var x := (i - (cuantos - 1) / 2.0) * 1.4
			_agregar(piso + b.x * x + fuera, -fuera, alto < 1.3, false)


## Erizo checo: cuatro puntos alrededor, solo tapan en parte.
static func agregar_erizo(pos: Vector3) -> void:
	for d in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		_agregar(pos + d * 1.35, -d, true, true)


## ¿Cuánto protege el punto contra alguien en `amenaza`? 1 = de frente,
## 0 = de lado, negativo = te ven por la espalda.
static func protege(p: Dictionary, amenaza: Vector3) -> float:
	var d: Vector3 = amenaza - p["pos"]
	d.y = 0.0
	if d.length_squared() < 0.01:
		return 0.0
	var valor: float = d.normalized().dot(p["n"])
	return valor * (0.6 if p["parcial"] else 1.0)


## El mejor punto libre según `puntaje` (Callable(p) -> float; -INF = no sirve).
## Con `radio`, solo mira los puntos a menos de `radio` m de `cerca` (mucho
## más barato: el mapa tiene más de mil puntos).
static func mejor(quien: Node, puntaje: Callable, cerca := Vector3.ZERO, radio := INF) -> Dictionary:
	var mejor_p: Dictionary = {}
	var mejor_v := -INF
	var r2 := radio * radio
	for p in puntos:
		if radio < INF and (p["pos"] as Vector3).distance_squared_to(cerca) > r2:
			continue
		var ocupante: Variant = p["ocupado"]
		if ocupante != null and ocupante != quien and is_instance_valid(ocupante):
			continue
		var v: float = puntaje.call(p)
		if v > mejor_v:
			mejor_v = v
			mejor_p = p
	return mejor_p


static func ocupar(p: Dictionary, quien: Node) -> void:
	liberar(quien)
	if not p.is_empty():
		p["ocupado"] = quien


static func liberar(quien: Node) -> void:
	for p in puntos:
		if p["ocupado"] == quien:
			p["ocupado"] = null


## El punto libre más cercano a `pos` (a menos de `radio` m), o vacío.
static func cercano(quien: Node, pos: Vector3, radio: float) -> Dictionary:
	return mejor(quien, func(p: Dictionary) -> float:
		var d := pos.distance_to(p["pos"])
		return -d if d < radio else -INF, pos, radio)


## ¿Se puede ir de `desde` a este punto? A la misma altura, o subiendo/bajando
## por la ladera del acantilado (tierra adentro, sin pasar por techos).
static func alcanzable(desde: Vector3, pos: Vector3) -> bool:
	var dy := absf(pos.y - desde.y)
	if dy <= 1.5:
		return true
	if pos.y < 4.0 and desde.y < 4.0:
		return false       # el techo del búnker (otra isla del mapa)
	return Vector2(pos.x - desde.x, pos.z - desde.z).length() >= dy * 1.4
