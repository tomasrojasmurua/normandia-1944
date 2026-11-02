extends Node
## Hornea los sprites de los soldados (estilo Doom / Hamburger Hill): pone el
## soldado 3D (soldado.gd) en un estudio, lo fotografía en cada animación
## desde 8 ángulos y guarda las fotos recortadas en
##   assets/sprites/<bando>/<arma>/<anim>_<dirección>.png   (una tira por dirección)
##   assets/sprites/<bando>/muertes/<anim>_<dirección>.png  (al morir suelta el arma)
##   assets/sprites/<bando>/datos.tres   (cuadros, origen, cabeza y boca de cada cuadro)
## soldado_sprite.gd las usa en el juego.
##
## Uso (necesita pantalla; en un servidor, con xvfb-run):
##   godot --path . res://tools/sprites/hornear.tscn -- aliado garand,thompson,bar
##   godot --path . res://tools/sprites/hornear.tscn -- aleman kar98k,mp40,stg44,mg42,luger
## Después: godot --headless --path . --import  (y python3 tools/sprites/importar.py)

const PX_POR_M := 40.0          # 40 píxeles por metro (la pantalla del juego mide 640x360)
const ALTO_M := 2.4             # alto de la foto, en metros (de -0.2 a 2.2)
const CENTRO_Y := 1.0
const DIRS := 8

## nombre: [cuadros, pose, andar]. La pose y el andar son los de soldado.gd.
const ANIMS_ARMA := {
	"reposo": [4, "reposo", ""],
	"apunta": [1, "pie", ""],
	"rodilla": [1, "rodilla", ""],
	"agachado": [1, "agachado", ""],
	"corre": [8, "pie", "corre"],
}
## Muertes: [cuadros, pose antes de morir, de dónde vino la bala (local)]
const ANIMS_MUERTE := {
	"muere_atras": [7, "pie", Vector3(0, 0, 1)],
	"muere_golpe": [7, "pie", Vector3(0, 0, 1)],
	"muere_rodilla": [7, "rodilla", Vector3(0, 0, 1)],
	"muere_corriendo": [7, "pie", Vector3(0, 0, -1)],
}

var _vp: SubViewport
var _cam: Camera3D
var _luz: DirectionalLight3D
var _datos := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var bando: String = args[0] if args.size() > 0 else "aliado"
	var armas: PackedStringArray = (args[1] if args.size() > 1 else "garand").split(",")
	_armar_estudio()
	var carpeta := "res://assets/sprites/%s/" % bando
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(carpeta))
	var previo := carpeta + "datos.tres"
	if ResourceLoader.exists(previo):
		_datos = load(previo).get_meta("datos", {})
	for arma in armas:
		print("arma ", arma)
		_datos[arma] = await _hornear_set(bando, arma, carpeta + arma + "/", ANIMS_ARMA, false)
	if args.size() <= 2 or args[2] != "sin_muertes":
		print("muertes")
		_datos["muertes"] = await _hornear_set(bando, armas[0], carpeta + "muertes/", ANIMS_MUERTE, true)
	var res := Resource.new()
	res.set_meta("datos", _datos)
	ResourceSaver.save(res, previo)
	print("listo: ", previo)
	get_tree().quit()


func _armar_estudio() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.82)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ALTO_M
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_vp.add_child(_cam)
	# Luz de arriba y un poco desde el que mira (gira con la cámara): todas
	# las direcciones quedan iluminadas parecido, como en los juegos viejos.
	_luz = DirectionalLight3D.new()
	_luz.light_energy = 0.75
	_vp.add_child(_luz)


## Un juego de animaciones de un arma (o las muertes). Devuelve sus datos.
func _hornear_set(bando: String, arma: String, carpeta: String, anims: Dictionary, muertes: bool) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(carpeta))
	var datos := {}
	for nombre in anims:
		var spec: Array = anims[nombre]
		var cuadros: int = spec[0]
		var ancho_m := 6.4 if muertes else 2.8
		_vp.size = Vector2i(int(ancho_m * PX_POR_M), int(ALTO_M * PX_POR_M))
		var info := {"cuadros": cuadros, "dirs": [], "cabeza": [], "boca": []}
		# Fotos de cada dirección: [dir][cuadro] = Image
		var fotos := []
		for d in DIRS:
			_mirar_desde(d)
			var s := await _soldado_nuevo(bando, arma)
			await _preparar(s, nombre, spec, muertes)
			var largo: float = s._ap.current_animation_length
			info["largo"] = largo
			var tiras: Array[Image] = []
			for k in cuadros:
				var t := 0.0
				if muertes:
					t = largo * float(k) / float(cuadros - 1) * 0.98
				elif cuadros > 1:
					t = largo * float(k) / float(cuadros)
				await _pose_en(s, t, largo, muertes)
				await RenderingServer.frame_post_draw
				tiras.append(_vp.get_texture().get_image())
				if d == 0:   # cabeza y boca en coordenadas del soldado
					info["cabeza"].append(s.to_local(s.pos_cabeza()))
					info["boca"].append(s.to_local(s.boca.global_position) if not muertes else Vector3.ZERO)
			fotos.append(tiras)
			s.queue_free()
			await get_tree().process_frame
		# Recortar cada dirección al rectángulo que ocupan todos sus cuadros
		for d in DIRS:
			var caja := Rect2i()
			for img: Image in fotos[d]:
				var u := img.get_used_rect()
				if u.size.x > 0:
					caja = u if caja.size.x == 0 else caja.merge(u)
			caja = caja.grow(1).intersection(Rect2i(Vector2i.ZERO, _vp.size))
			var hoja := Image.create(caja.size.x * cuadros, caja.size.y, false, Image.FORMAT_RGBA8)
			for k in cuadros:
				var img: Image = fotos[d][k]
				img.convert(Image.FORMAT_RGBA8)
				hoja.blit_rect(img, caja, Vector2i(caja.size.x * k, 0))
			_limpiar_alfa(hoja)
			hoja.save_png(ProjectSettings.globalize_path(carpeta + "%s_%d.png" % [nombre, d]))
			# Dónde queda el origen (los pies) dentro del recorte
			var origen := Vector2(_vp.size.x / 2.0, (CENTRO_Y + ALTO_M / 2.0) * PX_POR_M) - Vector2(caja.position)
			info["dirs"].append([origen.x, origen.y, caja.size.x, caja.size.y])
		datos[nombre] = info
		print("  ", nombre)
	return datos


## Bordes nítidos: cada píxel es opaco o transparente (estilo retro).
func _limpiar_alfa(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif c.a < 1.0:
				c.a = 1.0
				img.set_pixel(x, y, c)


func _soldado_nuevo(bando: String, arma: String) -> Soldado:
	var s := Soldado.new()
	s.bando = bando
	s.arma = arma
	_vp.add_child(s)
	s.set_process(false)       # lo avanzamos a mano
	await get_tree().process_frame
	return s


## Pone la pose y deja que termine la mezcla entre animaciones.
func _preparar(s: Soldado, nombre: String, spec: Array, muertes: bool) -> void:
	s.pose = spec[1]
	s.andar = "" if muertes else spec[2]
	for i in 20:
		s._acumulado = 1.0
		s._process(0.05)
	if muertes:
		var dir: Vector3 = spec[2]
		s.morir(s.global_basis * dir, false)
		s._poner_anim(nombre, 0.0)
	await get_tree().process_frame


## Deja al soldado en el instante t de su animación (con los retoques de
## soldado.gd: encorvado, arma entre las manos).
func _pose_en(s: Soldado, t: float, largo: float, muertes: bool) -> void:
	s._ap.seek(fposmod(t - 0.5, largo) if not muertes else maxf(t - 0.5, 0.0), true)
	s._acumulado = 0.5
	s._process(0.0)
	if muertes:
		s._ap.seek(t, true)
	await get_tree().process_frame
	await get_tree().process_frame


## Cámara a 10 m del soldado, en el ángulo de la dirección d (0 = de frente,
## 2 = desde su derecha, 4 = de espaldas, 6 = desde su izquierda).
func _mirar_desde(d: int) -> void:
	var a := TAU * d / DIRS
	var donde := Vector3(sin(a), 0, -cos(a)) * 10.0 + Vector3(0, CENTRO_Y, 0)
	_cam.look_at_from_position(donde, Vector3(0, CENTRO_Y, 0))
	_luz.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	_luz.look_at_from_position(donde + Vector3(0, 8, 0) + _cam.global_basis.x * 4.0, Vector3.ZERO)
