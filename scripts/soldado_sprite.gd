extends Node3D
class_name SoldadoSprite
## Cuerpo de un soldado hecho con sprites (como Doom o Hamburger Hill): una
## imagen plana que siempre mira a la cámara y cambia según desde qué lado lo
## miras (8 direcciones). Las imágenes salen de los modelos 3D de soldado.gd,
## fotografiados con tools/sprites/hornear.gd, y están en assets/sprites/.
##
## Hace lo mismo que soldado.gd (las mismas poses y órdenes), pero dibujarlo
## cuesta casi nada: no hay esqueleto que mover ni malla que deformar.
## enemy.gd / aliado.gd (vía combatiente.gd) eligen cuál usar.

@export var bando := "aleman"      # "aleman" o "aliado"
@export var arma := "kar98k"

var pose := "reposo"               # "reposo", "pie", "rodilla", "agachado"
var andar := ""                    # "" o cualquier animación de moverse (todas usan "corre")
var apuntar_a := Vector3.ZERO      # (los sprites no se inclinan; se guarda por compatibilidad)
var muerto := false
var boca: Node3D                   # punta del cañón (fogonazo y trazadoras)

const PIXEL := 0.025               # 40 píxeles por metro (como al hornear)
const ANIM_POSE := {"pie": "apunta", "rodilla": "rodilla", "agachado": "agachado"}
## Armas sin sprites propios: se usa la más parecida.
const PARECIDA := {"carbine": "garand", "springfield": "garand", "colt": "garand",
	"bazooka": "garand", "luger": "kar98k"}

var _spr: Sprite3D
var _fogonazo: Node3D
var _base := ""                    # carpeta del bando
var _carpeta := ""                 # carpeta del arma
var _set: Dictionary = {}          # datos de las animaciones del arma
var _muertes: Dictionary = {}
var _anim := ""
var _info: Dictionary = {}
var _cuadro := -1
var _dir := -1
var _t := randf() * 10.0
var _muerte := ""
var _muerte_t := 0.0
var _sacudon := Vector3.ZERO

static var _datos := {}            # por bando: lo que dejó hornear.gd
static var _texturas := {}


func _ready() -> void:
	var lado := "aleman" if bando == "aleman" else "aliado"
	_base = "res://assets/sprites/%s/" % lado
	if not _datos.has(lado):
		_datos[lado] = load(_base + "datos.tres").get_meta("datos")
	var todo: Dictionary = _datos[lado]
	var id := arma
	if not todo.has(id):
		id = PARECIDA.get(id, "")
	if not todo.has(id):
		for k in todo:
			if k != "muertes":
				id = k
				break
	_set = todo[id]
	_muertes = todo["muertes"]
	_carpeta = _base + id + "/"
	_precargar(_carpeta, _set)
	_precargar(_base + "muertes/", _muertes)

	_spr = Sprite3D.new()
	_spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_spr.pixel_size = PIXEL
	_spr.centered = false
	_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spr)
	boca = Node3D.new()
	add_child(boca)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.4)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_fogonazo = Game.box(boca, Vector3(0.16, 0.16, 0.16), Vector3.ZERO, fmat, Vector3(0, 0, 45))
	_fogonazo.visible = false
	_actualizar(0.0)


# ================================================================ lo que piden los demás

var _fogonazo_t := 0.0


func disparo() -> void:
	_fogonazo.visible = true
	_fogonazo.scale = Vector3.ONE * randf_range(0.7, 1.2)
	_fogonazo_t = 0.05      # (antes, un temporizador nuevo por cada tiro)


## Sacudón al recibir un balazo (dir = dirección de la bala, global).
func impacto(dir: Vector3) -> void:
	_sacudon = Vector3(dir.x, 0, dir.z).normalized() * 0.08


## Muere con una animación según la pose y de dónde vino la bala.
func morir(dir: Vector3, _cabeza_tiro: bool) -> void:
	muerto = true
	_fogonazo.visible = false
	_fogonazo_t = 0.0
	_spr.visibility_range_end = 80.0    # tendido a lo lejos mide un par de píxeles
	var local := global_basis.inverse() * dir
	if pose == "rodilla" or pose == "agachado":
		_muerte = "muere_rodilla"
	elif local.z < 0.0:     # la bala venía de frente
		_muerte = ["muere_atras", "muere_golpe"][randi() % 2]
	else:
		_muerte = "muere_corriendo"
	_muerte_t = 0.0
	_cuadro = -1


## Posición de la cabeza (para el tiro a la cabeza y la línea de vista).
func pos_cabeza() -> Vector3:
	if _info.is_empty():
		return to_global(Vector3(0, 1.62, 0))
	var c: Array = _info["cabeza"]
	var l: Vector3 = c[clampi(_cuadro, 0, c.size() - 1)]
	if escala > 1.0:   # dibujado más grande desde el pecho: la cabeza queda más arriba
		l = Vector3(l.x * escala, 1.1 + (l.y - 1.1) * escala, l.z * escala)
	return to_global(l) + Vector3(0, 0.08 * escala, 0)


# ================================================================ dibujo

func _process(delta: float) -> void:
	_actualizar(delta)


func _actualizar(delta: float) -> void:
	_t += delta
	if _fogonazo_t > 0.0:
		_fogonazo_t -= delta
		if _fogonazo_t <= 0.0:
			_fogonazo.visible = false
	var nombre: String
	var info: Dictionary
	var k := 0
	if muerto:
		nombre = _muerte
		info = _muertes[nombre]
		_muerte_t += delta
		var n: int = info["cuadros"]
		var paso: float = info["largo"] * 0.98 / float(n - 1)
		k = mini(int(_muerte_t / paso), n - 1)
	else:
		if andar != "":
			nombre = "corre"
		else:
			nombre = ANIM_POSE.get(pose, "reposo")
		info = _set[nombre]
		var n: int = info["cuadros"]
		if n > 1:
			var largo: float = info["largo"]
			k = int(fposmod(_t, largo) / largo * n) % n

	# Desde qué lado lo mira la cámara (0 = de frente, 2 = su derecha, 4 = espalda)
	var d := _dir
	var cam := get_viewport().get_camera_3d()
	if cam:
		var yo := global_transform
		var local := yo.basis.inverse() * (cam.global_position - yo.origin)
		d = posmod(roundi(atan2(local.x, -local.z) / (TAU / 8.0)), 8)
		_escala_lejos(cam.global_position.distance_to(yo.origin))

	if nombre != _anim or d != _dir:
		_anim = nombre
		_info = info
		_dir = d
		var carpeta := _carpeta if not muerto else _base + "muertes/"
		_spr.texture = _textura(carpeta + "%s_%d.png" % [nombre, d])
		_spr.hframes = info["cuadros"]
		var r: Array = info["dirs"][d]     # [origen x, origen y, ancho, alto]
		_spr.offset = Vector2(-r[0], r[1] - r[3])
		_cuadro = -1
	if k != _cuadro:
		_cuadro = k
		_spr.frame = k
		if not muerto:
			boca.position = info["boca"][k]
	if _sacudon != Vector3.ZERO:
		_sacudon = _sacudon.move_toward(Vector3.ZERO, delta * 0.6)
	var pos := _sacudon + Vector3(0, _bajar, 0)
	if pos != _spr.position:      # tocar la posición (o el tamaño) obliga al motor a rehacer el dibujo
		_spr.position = pos
	if muerto and k == int(info["cuadros"]) - 1:
		set_process(false)      # ya cayó: queda quieto para siempre


## Tamaño mínimo en pantalla: más allá de 28 m un alemán vivo se dibuja un
## poco más grande (hasta 1,6 veces a 45 m), para que se distinga aunque solo
## asome la cabeza. Crece alrededor del pecho, así la cabeza dibujada queda
## casi donde está la de verdad (la que recibe los tiros).
var _bajar := 0.0
const LEJOS := 28.0
const MAX_ESCALA := 1.6


var escala := 1.0      # lo usa combatiente.gd: la caja de choque crece con el dibujo


func _escala_lejos(dist: float) -> void:
	var e := 1.0
	if bando == "aleman" and not muerto:
		e = clampf(dist / LEJOS, 1.0, MAX_ESCALA)
	e = snappedf(e, 0.02)
	if e == escala and _spr.pixel_size == PIXEL * e:
		return
	escala = e
	_spr.pixel_size = PIXEL * e
	_bajar = -1.1 * (e - 1.0)


## Carga de una vez todas las imágenes de un juego de animaciones (al crear
## el soldado, mientras la playa se prepara). Cargarlas recién al verlas por
## primera vez trababa el juego en medio del combate: cada imagen nueva hay que
## leerla y subirla a la tarjeta de video.
static func _precargar(carpeta: String, anims: Dictionary) -> void:
	for nombre in anims:
		for d in 8:
			_textura(carpeta + "%s_%d.png" % [nombre, d])


static func _textura(ruta: String) -> Texture2D:
	if not _texturas.has(ruta):
		_texturas[ruta] = load(ruta)
	return _texturas[ruta]
