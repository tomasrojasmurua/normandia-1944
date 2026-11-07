extends Node
## "Game": servicios globales del juego (se carga solo, como Autoload).
## - Sonidos: se generan por código al arrancar (no hay archivos de audio todavía).
## - Efectos: sangre, polvo, trazadoras y explosiones.
## - Mensajes para el registro del HUD ("[ENEMIGO ABATIDO]", etc.).
## - Reloj de la misión (empieza a las 06:30, hora H del Día D).

signal message(text: String, color: Color)

const RATE := 22050
const COLOR_INFO := Color(0.95, 0.85, 0.4)
const COLOR_BAD := Color(1.0, 0.35, 0.3)
const COLOR_GOOD := Color(0.55, 0.95, 0.45)

var start_minutes := 6 * 60 + 30   # hora de la misión en curso (Misiones)
var mision := Misiones.PRIMERA     # id de la misión en curso (ver misiones.gd)
var elapsed := 0.0
var fallos := {}              # misión → intentos fracasados seguidos (ver factor_punteria)
var _fase_desde := 0.0        # cuándo empezó la fase actual (para la "gracia")
var _fase_vista := -1

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _rng := RandomNumberGenerator.new()
var _mat_cache := {}

## Ajustes guardados en el celular/PC.
const AJUSTES := "user://ajustes.cfg"
## Distribución de los botones táctiles (ver TouchControls.ESQUEMAS):
## 0 2 DEDOS, 1 DOBLE FUEGO, 2 GARRA, 3 ZURDO.
var esquema := 0
var datos_tecnicos := false    # FPS, ms y versión arriba a la izquierda (se activan en la pausa)
## Disparo táctil "al soltar": mantener FUEGO apunta por la mira, soltarlo dispara.
var disparo_soltar := false
var modo_red := false
var bajas := 0        # alemanes abatidos en la misión (para la pantalla final)
var caidos := 0       # americanos caídos (compañeros y jugadores)         # prototipo del cooperativo (ver red.gd)
var sala := ""                # código de la sala (4 números)
var mision_suelta := false    # menú "PROBAR EL SALTO": la misión aparte, sin campaña ni compañía
var prueba_carga := false     # menú "PRUEBA DE CARGA": playa llena (ver prueba_carga.gd)
var soldados_3d := false       # true = modelos 3D (pesados); false = sprites

## Desde qué Z empieza el agua (lo fija el escenario). Los impactos ahí salpican.
var sea_from_z := INF
## true mientras se "precalientan" los efectos al empezar (el HUD tapa la pantalla).
var warming := false
var _warmed := 0               # id de la escena ya preparada (ver warmup)


# Sangre en el suelo y caídos (ver mancha() y cuerpo_caido())
const MAX_CAIDOS := 26
var _manchas: Array = []
var _charcos: Array = []
var _creciendo: Array = []
var _caidos: Array = []
var _mat_sangre: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1944
	var cfg := ConfigFile.new()
	if cfg.load(AJUSTES) == OK:
		esquema = int(cfg.get_value("controles", "esquema", 2 if cfg.get_value("controles", "garra", false) else 0))
		disparo_soltar = cfg.get_value("controles", "disparo_soltar", false)
		soldados_3d = cfg.get_value("graficos", "soldados_3d", false)
		datos_tecnicos = cfg.get_value("pantalla", "datos_tecnicos", false)
	_build_sounds()
	_cargar_archivos()
	_solo_horizontal()
	# Limitador en la salida: con muchas explosiones juntas no se satura
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)
	_crear_marcas()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


# --- Para el medidor: cuánto tarda NUESTRO código (guiones) en cada cuadro.
# Dos marcas: una corre antes que todos los guiones y otra después, en el
# proceso y en la física. Lo que falta para el total del cuadro es el motor
# (física, dibujo) y el navegador.
var codigo_cuadro_us := 0     # guiones del último cuadro completo (proceso + física)
var _t_proc := 0
var _t_fis := 0
var _fis_acum := 0
var _fis_cuadro := 0


class Marca extends Node:
	var fin := false
	var g: Node
	func _process(_d: float) -> void:
		if fin:
			g.codigo_cuadro_us = Time.get_ticks_usec() - g._t_proc + g._fis_cuadro
		else:
			g._t_proc = Time.get_ticks_usec()
			g._fis_cuadro = g._fis_acum
			g._fis_acum = 0
	func _physics_process(_d: float) -> void:
		if fin:
			g._fis_acum += Time.get_ticks_usec() - g._t_fis
		else:
			g._t_fis = Time.get_ticks_usec()


func _crear_marcas() -> void:
	for fin in [false, true]:
		var m := Marca.new()
		m.fin = fin
		m.g = self
		m.process_mode = Node.PROCESS_MODE_ALWAYS
		m.process_priority = 100000 if fin else -100000
		m.process_physics_priority = 100000 if fin else -100000
		add_child(m)


var _players_3d: Array = []
var _next_3d := 0
var _trazadoras: Array = []
var _next_traz := 0
var _emisores := {}           # tipo de estallido → [CPUParticles3D]
var _fuegos: Array = []
var _next_fuego := 0
var carga_texto := ""         # para el medidor en la prueba de carga


func _process(delta: float) -> void:
	_preparar_sonidos(delta)
	_anotar_fluidez(delta)
	if not get_tree().paused:
		elapsed += delta
		# Los charcos crecen despacio
		for i in range(_creciendo.size() - 1, -1, -1):
			var m: MeshInstance3D = _creciendo[i]
			var t: float = minf(float(m.get_meta("t", 1.0)) + delta / 7.0, 1.0)
			m.set_meta("t", t)
			m.scale = Vector3.ONE * float(m.get_meta("tam", 1.0)) * (0.25 + 0.75 * sqrt(t))
			if t >= 1.0:
				_creciendo.remove_at(i)
	if _fogonazos_vivos > 0:
		var ahora := Time.get_ticks_msec()
		var cuadro := Engine.get_frames_drawn()
		_fogonazos_vivos = 0
		for f in _fogonazos:
			if f.visible:
				if ahora >= int(f.get_meta("hasta", 0)) and cuadro >= int(f.get_meta("cuadro", 0)):
					f.visible = false
				else:
					_fogonazos_vivos += 1


# --- Informe de fluidez: cómo corrió cada fase de la misión en curso. Se ve
# en la pausa con DATOS TÉCNICOS (para mandar una captura). Por fase:
# [nombre, cuadros, segundos, cuadros lentos (<25 FPS), tirones (>100 ms), peor ms]
var informe: Array = []
var _inf_clave := ""
var _inf_ignorar := 0.0


func _anotar_fluidez(delta: float) -> void:
	# Al bajar el centro de notificaciones (o salir de la app) Safari frena la
	# página: eso no es el juego, no se anota (ni el medio segundo siguiente)
	if _inf_ignorar > 0.0:
		_inf_ignorar -= minf(delta, 0.1)
		return
	if warming or get_tree().paused or Objetivos.actual == null or Objetivos.terminado != 0:
		return
	var en_aire := Salto.activo and Salto.actual != null and not Salto.actual._aterrizado
	var clave := "SALTO" if en_aire else "F%d" % (Objetivos.fase() + 1)
	if clave != _inf_clave:
		_inf_clave = clave
		informe.append([clave, 0, 0.0, 0, 0, 0.0])
	var r: Array = informe[-1]
	r[1] += 1
	r[2] += delta
	if delta > 0.04:
		r[3] += 1
	if delta > 0.1:
		r[4] += 1
	r[5] = maxf(r[5], delta * 1000.0)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN,
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		_inf_ignorar = 0.6


## Una línea por fase, para la pausa.
func informe_lineas() -> Array:
	var l: Array = []
	for r in informe:
		if r[2] < 1.0:
			continue
		l.append("%s  %d FPS  %d%% LENTO  %d TIR  %d MS" % [r[0], roundi(r[1] / r[2]),
			roundi(100.0 * r[3] / maxf(r[1], 1.0)), r[4], roundi(r[5])])
	return l


## Se llama al empezar una misión (y al reiniciar tras morir).
func reset_mission() -> void:
	_crear_sangre()
	for m in _manchas + _charcos:
		m.visible = false
	_creciendo.clear()
	_caidos.clear()
	elapsed = 0.0
	_fase_vista = -1
	bajas = 0
	caidos = 0


## Soldados con sprites (liviano, por defecto) o con los modelos 3D (para comparar).
func cambiar_soldados() -> void:
	soldados_3d = not soldados_3d
	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("graficos", "soldados_3d", soldados_3d)
	cfg.save(AJUSTES)


func cambiar_esquema() -> void:
	esquema = (esquema + 1) % TouchControls.ESQUEMAS.size()
	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("controles", "esquema", esquema)
	cfg.save(AJUSTES)


func cambiar_datos_tecnicos() -> void:
	datos_tecnicos = not datos_tecnicos
	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("pantalla", "datos_tecnicos", datos_tecnicos)
	cfg.save(AJUSTES)


func cambiar_disparo() -> void:
	disparo_soltar = not disparo_soltar
	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("controles", "disparo_soltar", disparo_soltar)
	cfg.save(AJUSTES)


## Ir al menú principal / empezar la misión.
func ir_al_menu() -> void:
	_cerrar_compania()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Cinemática (prólogo o antes de una misión). `despues`: "mision" o "mapa".
func ver_cinematica(id: String, despues: String) -> void:
	Cinematica.actual = id
	Cinematica.despues = despues
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/cinematica.tscn")


## Mapa de la campaña (jugando solo): el coronel, las misiones y el diario.
func ir_al_mapa() -> void:
	_cerrar_compania()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/mapa.tscn")


## Pantalla previa a la misión (jugando solo): elegir a los hombres.
func ir_a_previa() -> void:
	_cerrar_compania()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/previa.tscn")


## Si se deja una misión a medias (menú, reiniciar), sus caídos cuentan igual.
func _cerrar_compania() -> void:
	if Compania.en_mision:
		Compania.cerrar_mision(0, Escuadras.reemplazos_vivos())
		Campana.cerrar_mision(0)


## Cooperativo: se anota la sala al empezar. Si el celular recarga la página
## en medio de la partida (Safari a veces cierra la pestaña por memoria), el
## menú ofrece "VOLVER A LA SALA" y se entra directo a la partida en curso.
const SALA_EN_CURSO := "user://sala_en_curso.cfg"


func anotar_sala() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sala", "codigo", sala)
	cfg.set_value("sala", "hora", Time.get_unix_time_from_system())
	cfg.save(SALA_EN_CURSO)


func sala_reciente() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SALA_EN_CURSO) != OK:
		return ""
	if Time.get_unix_time_from_system() - float(cfg.get_value("sala", "hora", 0.0)) > 20.0 * 60.0:
		return ""
	return str(cfg.get_value("sala", "codigo", ""))


func olvidar_sala() -> void:
	if FileAccess.file_exists(SALA_EN_CURSO):
		DirAccess.remove_absolute(SALA_EN_CURSO)


## Cuánto se afina la puntería alemana contra los jugadores ahora:
## - la fase puede ser más perdonadora (`punteria` en misiones.gd) y tener
##   unos segundos de gracia al empezar (`gracia`: en el desembarco hay cien
##   blancos a la vez);
## - cada intento fracasado seguido de la misma misión la baja un 12 %
##   (hasta −36 %): el que recién aprende no se estrella siempre contra lo mismo.
func factor_punteria() -> float:
	var i := Objetivos.fase()
	if i != _fase_vista:
		_fase_vista = i
		_fase_desde = elapsed
	var f: Dictionary = Misiones.fase(i)
	var k := float(f.get("punteria", 1.0))
	if elapsed - _fase_desde < float(f.get("gracia", 0.0)):
		k *= 0.5
	return k * maxf(0.64, 1.0 - 0.12 * int(fallos.get(mision, 0)))


func anotar_resultado(resultado: int) -> void:
	if resultado < 0:
		fallos[mision] = int(fallos.get(mision, 0)) + 1
	elif resultado > 0:
		fallos.erase(mision)


func empezar_mision(id := "", sin_cinematica := false) -> void:
	_cerrar_compania()
	if modo_red:
		anotar_sala()
	if id != "" and Misiones.existe(id):
		mision = id
	# Jugando solo, antes de la misión va su cinemática (que después vuelve aquí)
	if not sin_cinematica and not modo_red and not prueba_carga and Cinematica.tiene(mision):
		ver_cinematica(mision, "mision")
		return
	Compania.empezar_mision()
	if Compania.activa():
		Campana.cargar()
	Campana.empezar_mision()
	start_minutes = Misiones.dato("hora")
	get_tree().paused = false
	get_tree().change_scene_to_file(Misiones.dato("escena"))


func clock_text() -> String:
	var total := start_minutes + int(elapsed / 60.0)
	return "%02d:%02d" % [(total / 60) % 24, total % 60]


## Rumbo de una dirección en grados (0 = norte, 90 = este). El norte de cada
## misión está en sus datos ("norte"; Omaha: +Z, el mar; Sainte-Mère-Église: -Z).
static func rumbo(dir: Vector3) -> float:
	var n: Vector3 = Misiones.actual().get("norte", Vector3(0, 0, 1))
	var e := n.cross(Vector3.UP)
	return fmod(rad_to_deg(atan2(dir.dot(e), dir.dot(n))) + 360.0, 360.0)


static func cardinal(dir: Vector3) -> String:
	return ["N", "NE", "E", "SE", "S", "SO", "O", "NO"][int(roundf(rumbo(dir) / 45.0)) % 8]


func say(text: String, color: Color = COLOR_INFO) -> void:
	message.emit(text, color)


# ---------------------------------------------------------------- sonido

func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var st := _stream(sound)
	if st == null:
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Sonido en un punto del mundo. Usa una reserva fija de reproductores 3D que
## se reciclan (antes se creaba y borraba uno por disparo: en el navegador del
## celular eso cuesta y trababa el juego en los tiroteos).
func play_at(sound: String, pos: Vector3, volume_db := 0.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var lejos := cam != null and cam.global_position.distance_to(pos) > 55.0
	var st := _stream(sound, lejos)
	if st == null:
		return
	if _players_3d.is_empty():
		for i in 16:
			var n := AudioStreamPlayer3D.new()
			n.unit_size = 12.0
			n.max_distance = 200.0
			add_child(n)
			_players_3d.append(n)
	# El siguiente libre; si todos suenan, el más antiguo
	var p: AudioStreamPlayer3D = _players_3d[_next_3d]
	for i in _players_3d.size():
		var c: AudioStreamPlayer3D = _players_3d[(_next_3d + i) % _players_3d.size()]
		if not c.playing:
			p = c
			_next_3d = (_next_3d + i) % _players_3d.size()
			break
	_next_3d = (_next_3d + 1) % _players_3d.size()
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = _rng.randf_range(0.92, 1.06)
	p.global_position = pos
	p.play()


## Sonidos grabados (ElevenLabs, tools/audio/sonidos.py): nombre -> variantes.
## Si un sonido tiene archivo, se usa en vez del generado con código; con
## varias variantes se elige una al azar. ALIAS: los nombres viejos que ahora
## suenan con un archivo.
const ARCHIVOS := {
	"explosion_cerca": 3, "explosion_lejos": 2, "silbido_proyectil": 2, "bala_pasa": 3,
	"impacto_arena": 2, "mg42_lejos": 1, "rampa": 1, "maquina_escribir": 1,
	"grito_aleman": 4, "grito_medico": 3, "grito_herido": 3, "muerte": 3,
	# Voces del sargento (órdenes) y de su escuadra (respuestas). Si falta el
	# archivo, no suena nada (el mensaje igual sale en pantalla).
	"orden_seguir": 2, "orden_avanzar": 2, "orden_mantener": 2,
	"pedir_medico": 2, "pedir_bazuca": 1, "pedir_radio": 1, "pedir_fuego": 2, "pedir_ingeniero": 1,
	"resp_ok": 3, "resp_medico": 2, "resp_bazuca": 1, "resp_radio": 1, "resp_fuego": 2, "resp_ingeniero": 1,
	# Misión 2: el grillo (uno = clic-clac, dos = la respuesta) y la bengala.
	# Mientras no estén grabados suenan los hechos con código.
	"grillo": 1, "grillo2": 1, "bengala": 1, "tela": 1, "latido": 1,
}
const ALIAS := {"explosion": "explosion_cerca", "silbido": "silbido_proyectil", "zumbido": "bala_pasa"}
var _archivos := {}


func _cargar_archivos() -> void:
	for n in ARCHIVOS:
		var lista: Array = []
		var k: int = ARCHIVOS[n]
		for i in k:
			var ruta := "res://assets/sonidos/%s.ogg" % (n if k == 1 else "%s_%d" % [n, i + 1])
			if ResourceLoader.exists(ruta):
				lista.append(load(ruta))
				if OS.has_feature("web"):
					_por_preparar.append(lista[-1])
		if not lista.is_empty():
			_archivos[n] = lista


## El sonido a tocar: una variante grabada si hay, si no el generado.
## `lejos`: para las explosiones, la versión lejana.
func _stream(sound: String, lejos := false) -> AudioStream:
	var n: String = ALIAS.get(sound, sound)
	if n == "explosion_cerca" and lejos:
		n = "explosion_lejos"
	# Una variante en particular: "grito_aleman_3"
	var corte := n.rfind("_")
	if not _archivos.has(n) and corte > 0 and n.substr(corte + 1).is_valid_int():
		var base := n.substr(0, corte)
		var i := int(n.substr(corte + 1)) - 1
		if _archivos.has(base) and i >= 0 and i < (_archivos[base] as Array).size():
			return _archivos[base][i]
	if _archivos.has(n):
		var l: Array = _archivos[n]
		return l[_rng.randi() % l.size()]
	return _sounds.get(sound)


## Un compañero contesta (su voz sale de donde está), un poco después de la orden.
func respuesta(sonido: String, quien: Node3D, retraso := 0.8) -> void:
	await get_tree().create_timer(retraso).timeout
	if is_instance_valid(quien) and quien.is_inside_tree() and not quien.get("dead"):
		play_at(sonido, quien.global_position + Vector3(0, 1.5, 0), 2.0)


## Puente de sonido: el ambiente de la cinemática sigue sonando mientras carga
## la misión (si no, hay unos segundos de silencio); Fragor lo retoma.
var puente: AudioStreamPlayer


func seguir_sonando(origen: AudioStreamPlayer) -> void:
	if puente == null:
		puente = AudioStreamPlayer.new()
		puente.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(puente)
	puente.stream = origen.stream
	puente.volume_db = origen.volume_db
	puente.play(origen.get_playback_position())


## En el navegador, cada sonido se decodifica entero la primera vez que suena
## (eso trababa el juego). Aquí se preparan de a uno, en el menú y el mapa,
## antes de que hagan falta.
var _por_preparar: Array = []
var _t_preparar := 1.0


func _preparar_sonidos(delta: float) -> void:
	if _por_preparar.is_empty():
		return
	_t_preparar -= delta
	if _t_preparar > 0.0:
		return
	_t_preparar = 0.12
	AudioServer.register_stream_as_sample(_por_preparar.pop_front())


## Reproductor para música y ambientes largos: en el navegador se tocan como
## "stream" (se decodifican de a poco) y no como muestra (habría que
## decodificar 20–90 s de una vez y guardarlos sin comprimir en memoria).
func reproductor_largo(nombre: String, bucle := false) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	a.stream = pista(nombre, bucle)
	return a


## Música o ambiente (archivo entero, para las cinemáticas y el ambiente).
func pista(nombre: String, bucle := false) -> AudioStream:
	var ruta := "res://assets/sonidos/%s.ogg" % nombre
	if not ResourceLoader.exists(ruta):
		return null
	var st: AudioStream = load(ruta)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = bucle
	return st


func _build_sounds() -> void:
	# nombre: [duración en segundos, brillo del ruido 0..1]
	var specs := {
		"rifle": [0.55, 0.35], "pistol": [0.32, 0.5], "rifle_far": [0.9, 0.08],
		"ping": [0.7, 1.0], "click": [0.06, 1.0], "reload": [0.9, 0.9],
		"explosion": [1.8, 0.06], "hurt": [0.3, 0.2], "hit": [0.07, 1.0],
		"throw": [0.35, 0.25], "bounce": [0.08, 0.5],
		"zumbido": [0.22, 0.9], "silbido": [1.3, 1.0],
		"grillo": [0.3, 1.0], "grillo2": [0.75, 1.0], "bengala": [1.6, 0.8],
		"tela": [0.9, 0.5], "latido": [0.45, 0.2],
	}
	for sound in specs:
		_sounds[sound] = _make(sound, specs[sound][0], specs[sound][1])


## Forma de onda de cada sonido en el instante `t` (segundos); `n` es ruido.
func _sample(sound: String, t: float, n: float) -> float:
	match sound:
		"rifle":
			return n * exp(-t * 13.0) * 0.9 + sin(TAU * 55.0 * t) * exp(-t * 18.0) * 0.8
		"pistol":
			return n * exp(-t * 22.0) * 0.85 + sin(TAU * 90.0 * t) * exp(-t * 30.0) * 0.5
		"rifle_far":
			return n * exp(-t * 7.0) * 0.7 + sin(TAU * 45.0 * t) * exp(-t * 10.0) * 0.4
		"ping":  # el clip del Garand saltando al vaciarse
			return (sin(TAU * 2950.0 * t) * 0.35 + sin(TAU * 4180.0 * t) * 0.18) * exp(-t * 6.5) \
				+ n * exp(-t * 300.0) * 0.4
		"click":
			return n * exp(-t * 180.0) * 0.6 + sin(TAU * 1400.0 * t) * exp(-t * 120.0) * 0.3
		"reload":
			var a := n * exp(-t * 150.0) * 0.5
			var t2 := t - 0.45
			if t2 > 0.0:
				a += n * exp(-t2 * 120.0) * 0.6 + sin(TAU * 900.0 * t2) * exp(-t2 * 80.0) * 0.3
			return a
		"explosion":
			return n * exp(-t * 2.6) + sin(TAU * 38.0 * t) * exp(-t * 4.0) * 0.9
		"hurt":
			return sin(TAU * (140.0 - t * 200.0) * t) * exp(-t * 12.0) * 0.8 + n * exp(-t * 25.0) * 0.3
		"hit":
			return sin(TAU * 1900.0 * t) * exp(-t * 60.0) * 0.35
		"throw":
			return n * sin(PI * t / 0.35) * 0.35
		"bounce":
			return n * exp(-t * 90.0) * 0.5 + sin(TAU * 600.0 * t) * exp(-t * 70.0) * 0.3
		"zumbido":   # bala que pasa cerca: chasquido seco y un zumbido que se aleja
			return n * exp(-t * 60.0) * 0.6 + sin(TAU * (2300.0 - t * 4000.0) * t) * exp(-t * 14.0) * 0.25
		"silbido":   # mortero cayendo: tono que baja y sube de volumen
			return sin(TAU * (1500.0 - t * 700.0) * t) * minf(t / 1.1, 1.0) * 0.32 + n * 0.03
		"bengala":   # pistola de señales: estampido seco y el silbido de la bengala que sube
			return n * exp(-t * 40.0) * 0.8 + sin(TAU * 70.0 * t) * exp(-t * 30.0) * 0.5 \
				+ n * clampf(t * 4.0, 0.0, 1.0) * exp(-t * 1.6) * 0.18
		"tela":      # el paracaídas que se abre: un chasquido de tela y un golpe de aire
			return n * 2.2 * exp(-t * 4.0) * clampf(t * 30.0, 0.0, 1.0) + sin(TAU * 55.0 * t) * exp(-t * 9.0) * 0.6
		"latido":    # el corazón: dos golpes graves
			return sin(TAU * 52.0 * t) * (exp(-t * 28.0) + exp(-maxf(t - 0.17, 0.0) * 30.0) * 0.75 * float(t > 0.17)) * 0.9
		"grillo":    # el grillo de los paracaidistas: clic-clac (lámina de metal)
			return _clic(t) + _clic(t - 0.11) * 0.8
		"grillo2":   # la respuesta: dos clic-clac
			return _clic(t) + _clic(t - 0.11) * 0.8 + _clic(t - 0.38) + _clic(t - 0.49) * 0.8
	return 0.0


func _clic(t: float) -> float:
	if t < 0.0:
		return 0.0
	return (sin(TAU * 3100.0 * t) * 0.5 + sin(TAU * 4700.0 * t) * 0.3) * exp(-t * 85.0) \
		+ _rng.randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.5


## Genera un sonido. `brightness` (0..1) filtra el ruido: bajo = grave y apagado.
func _make(sound: String, seconds: float, brightness: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * brightness
		var v := _sample(sound, t, lp)
		var fade := clampf((seconds - t) / 0.02, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * fade, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


# ---------------------------------------------------------------- efectos

## Sangre al recibir un tiro: chorro hacia donde va la bala, gotas oscuras y
## una mancha en el suelo detrás (si hay suelo cerca).
func blood(pos: Vector3, dir := Vector3.ZERO) -> void:
	var d := (dir + Vector3(0, 0.35, 0)).normalized() if dir != Vector3.ZERO else Vector3.UP
	_burst(pos, Color(0.55, 0.04, 0.03), 18, 3.2, 0.7, 0.07, d, 1.0, 40.0)
	_burst(pos, Color(0.32, 0.02, 0.02), 10, 1.6, 0.9, 0.05, Vector3.UP, 1.2)
	if dir != Vector3.ZERO:
		var atras := Vector3(dir.x, 0, dir.z).normalized() * randf_range(0.8, 1.8)
		mancha(pos + atras, 0.7 + randf() * 0.6, false)


## Mancha de sangre en el suelo (reserva fija que se recicla). `charco`: crece
## despacio debajo de un caído.
func mancha(pos: Vector3, tam: float, charco: bool) -> void:
	var esc := _scene()
	if esc == null or not esc is Node3D or _manchas.is_empty():
		return
	var espacio := (esc as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos - Vector3(0, 3.0, 0), 1)
	var r := espacio.intersect_ray(q)
	if r.is_empty():
		return
	var lista: Array = _charcos if charco else _manchas
	var m: MeshInstance3D = lista.pop_front()
	lista.append(m)
	var n: Vector3 = r["normal"]
	var b := Basis.looking_at(-n, Vector3.FORWARD if absf(n.y) < 0.9 else Vector3.RIGHT)
	b = b.rotated(n, randf() * TAU)
	m.global_transform = Transform3D(b, r["position"] + n * (0.03 + randf() * 0.02))
	m.material_override = _mat_sangre[randi() % _mat_sangre.size()]
	m.visible = true
	m.set_meta("tam", tam)
	m.set_meta("t", 0.0 if charco else 1.0)
	m.scale = Vector3.ONE * (tam * 0.25 if charco else tam)
	if charco:
		_creciendo.append(m)


## Un soldado cayó: charco debajo y, si ya hay muchos caídos, el más viejo se
## esconde (no se borra: otros guiones pueden tener la referencia).
func cuerpo_caido(c: Node3D) -> void:
	mancha(c.global_position + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3)),
		randf_range(1.1, 1.6), true)
	_caidos.append(c)
	while _caidos.size() > MAX_CAIDOS:
		var viejo = _caidos.pop_front()
		if is_instance_valid(viejo):
			_retirar_caido(viejo)


## Un caído viejo deja de verse. Los alemanes (de verdad o títeres) se borran
## del todo: en partidas largas se juntaban cientos de cuerpos ocultos (cada
## uno con su esqueleto) y la memoria del celular no paraba de subir. Los
## compañeros y los tiradores de MG42 solo se ocultan (el HUD y los objetivos
## los siguen mirando).
func _retirar_caido(viejo: Node3D) -> void:
	var borrar := false
	if viejo is Enemy:
		borrar = viejo.rol != "fijo"
	elif viejo is AlemanRemoto:
		borrar = viejo.bando == "aleman"
	if borrar:
		if Red.actual:
			Red.actual.olvidar(viejo)
		viejo.queue_free()
	else:
		viejo.visible = false
		viejo.process_mode = Node.PROCESS_MODE_DISABLED


func _crear_sangre() -> void:
	if not _manchas.is_empty():
		return
	for k in 4:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + k
		var gotas := [[Vector2(16, 16), rng.randf_range(7.0, 10.0)]]
		for g in 9:
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(6.0, 14.0)
			gotas.append([Vector2(16, 16) + Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(1.0, 3.5)])
		for y in 32:
			for x in 32:
				var dentro := 0.0
				for g in gotas:
					dentro = maxf(dentro, 1.0 - Vector2(x, y).distance_to(g[0]) / g[1])
				if dentro > 0.0:
					var osc := 0.75 + 0.25 * dentro
					img.set_pixel(x, y, Color(0.38 * osc, 0.03, 0.02, 1.0) if dentro > 0.25 else Color(0.25, 0.02, 0.02, 1.0))
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.roughness = 0.35
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_sangre.append(mat)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i in 48 + 24:
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		(_manchas if i < 48 else _charcos).append(m)


func dust(pos: Vector3, normal := Vector3.UP) -> void:
	if pos.z > sea_from_z and pos.y < 0.3:
		splash(pos)
		return
	_burst(pos, Color(0.7, 0.64, 0.5), 8, 2.0, 0.5, 0.05, normal, 0.6)


## Salpicadura de agua: columna blanca que sube y cae.
func splash(pos: Vector3) -> void:
	pos.y = maxf(pos.y, 0.05)
	_burst(pos, Color(0.85, 0.88, 0.86), 12, 4.0, 0.7, 0.06, Vector3.UP, 1.0, 12.0)
	_burst(pos, Color(0.6, 0.66, 0.64), 6, 1.5, 0.5, 0.09, Vector3.UP, 0.8, 40.0)


## Precalentar: los navegadores compilan cada efecto la primera vez que se
## dibuja, y eso traba el juego un momento. Aquí se dibuja uno de cada uno
## frente a la cámara al empezar, mientras el HUD muestra "PREPARANDO".
func warmup() -> void:
	var cam := get_viewport().get_camera_3d()
	var escena := get_tree().current_scene
	# Una vez por MISIÓN (antes era una vez por sesión: la segunda misión, o
	# volver a jugar desde el menú, empezaba sin preparar). Reintentar tras
	# caer sigue en la misma escena y no repite.
	if cam == null or escena == null or _warmed == escena.get_instance_id():
		return
	_warmed = escena.get_instance_id()
	warming = true
	informe.clear()
	_inf_clave = ""
	var p := cam.global_position - cam.global_basis.z * 3.0
	blood(p)
	_burst(p, Color(0.7, 0.64, 0.5), 8, 2.0, 0.5, 0.05, Vector3.UP, 0.6)
	splash(p)
	tracer(p + cam.global_basis.x, p - cam.global_basis.x)
	_explosion_fx(p)
	# Las reservas de fogonazos (24) y de sonidos 3D (16) se armaban en el
	# primer tiroteo; en el salto, justo mientras caías (trababa)
	fogonazo(p, true)
	fogonazo(p + cam.global_basis.x * 0.5, false)
	play_at("click", p, -80.0)
	mancha(p, 0.5, false)
	if Telones.actual:
		Telones.actual.calentar(p)
	# Lo que se deja de dibujar a lo lejos (ruinas de Vierville, sacos, modelos)
	# se dibuja igual estos cuadros: el navegador prepara su sombreador ahora y
	# no en medio de la misión, cuando aparece por primera vez.
	var rangos := {}
	for n in get_tree().current_scene.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.visibility_range_end > 0.0:
			rangos[g] = g.visibility_range_end
			g.visibility_range_end = 0.0
	# Los modelos de las armas del jugador (en el salto, la que se cae al
	# abrirse el paracaídas; en combate, las que quedan en el suelo)
	var modelos: Array = []
	var jug := get_tree().get_first_node_in_group("player") as Player
	if jug and jug.weapons:
		for k in jug.weapons.slots.size():
			var id: String = jug.weapons.slots[k]
			if id != "nada" and Armas.DATOS.has(id):
				var mi := Armas.modelo_3d(id)
				escena.add_child(mi)
				mi.global_position = p + cam.global_basis.x * (0.6 * k - 0.3)
				modelos.append(mi)
	# Bengala (noche): su resplandor aditivo se prepara ahora, no al primer disparo
	var bengala: Bengala = null
	if str(Misiones.dato("clima")) == "noche":
		bengala = Bengala.new()
		bengala._desde = p
		bengala._arriba = p
		escena.add_child(bengala)
		bengala.global_position = p
		bengala.set_process(false)
		bengala._brillo.visible = true
	# Una luz de paso que alcanza todo: el navegador prepara también la versión
	# "iluminada por una luz cercana" de cada material (bengalas, fuegos). Sin
	# esto se preparaba en plena misión, al encenderse la primera bengala.
	var luz := OmniLight3D.new()
	luz.omni_range = 400.0
	luz.light_energy = 0.05
	luz.shadow_enabled = false
	escena.add_child(luz)
	luz.global_position = cam.global_position
	# Vuelta completa con una cámara de paso (8 direcciones, mirando un poco
	# abajo): así se dibuja una vez lo que queda a la espalda y a los lados.
	var vuelta := Camera3D.new()
	vuelta.fov = maxf(cam.fov, 75.0)
	vuelta.near = cam.near
	vuelta.far = cam.far
	escena.add_child(vuelta)
	vuelta.global_position = cam.global_position
	vuelta.current = true
	for i in 8:
		vuelta.global_rotation = Vector3(deg_to_rad(-12.0), cam.global_rotation.y + TAU * i / 8.0, 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_instance_valid(cam):
			break
	if is_instance_valid(cam):
		cam.current = true
	vuelta.queue_free()
	luz.queue_free()
	if bengala:
		bengala.queue_free()
	for mi in modelos:
		mi.queue_free()
	for i in 2:
		await get_tree().process_frame
	for g: GeometryInstance3D in rangos:
		if is_instance_valid(g):
			g.visibility_range_end = rangos[g]
	# Los sonidos grabados que aún no se registraron (en la web se registran de
	# a uno desde que se abre el juego): ahora, tapados por el negro, y no la
	# primera vez que suenan (en el salto trababa al salir del avión).
	while not _por_preparar.is_empty():
		AudioServer.register_stream_as_sample(_por_preparar.pop_front())
	await get_tree().create_timer(1.2).timeout     # que caigan los escombros antes de mostrar la playa
	warming = false


## Trazadora de bala. Reserva fija de 32 que se reciclan (ver play_at).
func tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.75, 0.3), grosor := 1.0) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	if _trazadoras.is_empty():
		var box := BoxMesh.new()
		box.size = Vector3(0.025, 0.025, 1.0)
		for i in 32:
			var n := MeshInstance3D.new()
			n.mesh = box
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			n.material_override = mat
			n.visible = false
			add_child(n)
			_trazadoras.append(n)
	var m: MeshInstance3D = _trazadoras[_next_traz]
	_next_traz = (_next_traz + 1) % _trazadoras.size()
	if m.has_meta("tw"):
		var viejo: Tween = m.get_meta("tw")
		if viejo and viejo.is_valid():
			viejo.kill()
	var mat: StandardMaterial3D = m.material_override
	mat.albedo_color = color
	var largo := minf(length, 6.0)
	var dir := (to - from).normalized()
	m.global_position = from
	m.look_at(from + dir, Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP)
	m.scale = Vector3(grosor, grosor, largo)
	m.visible = true
	var tw := m.create_tween()
	m.set_meta("tw", tw)
	var travel := minf(length / 250.0, 0.25)  # la trazadora "viaja" hasta el blanco
	tw.tween_property(m, "global_position", to - dir * largo * 0.5, travel)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, travel + 0.05)
	tw.tween_callback(func() -> void: m.visible = false)


## Explosión de granada: efecto visual, sonido y daño en un radio.
## `desde_red` = la explosión pasó en otro celular del cooperativo: aquí solo
## se ve y se calcula el daño a mi jugador (a los alemanes ya se lo hizo allá).
func explode(pos: Vector3, radius: float, damage: float, desde_red := false) -> void:
	play_at("explosion", pos, 6.0)
	_explosion_fx(pos)
	if not desde_red and Red.activo():
		Red.explosion(pos, radius, damage)
	for e in get_tree().get_nodes_in_group("enemies") if not desde_red else []:
		var chest: Vector3 = e.global_position + Vector3(0, 1.0, 0)
		var d := pos.distance_to(chest)
		if d < radius and _clear_path(pos, chest):
			e.hit(damage * (1.0 - d / radius), false, chest, (chest - pos).normalized())
	for t in get_tree().get_nodes_in_group("tanques") if not desde_red else []:
		if pos.distance_to(t.centro()) < radius * 0.5 + 2.8:
			t.danar(damage)
	for a in get_tree().get_nodes_in_group("aliados"):
		var c: Vector3 = a.global_position + Vector3(0, 1.0, 0)
		var da := pos.distance_to(c)
		if da < radius and _clear_path(pos, c):
			a.take_damage(damage * 0.8 * (1.0 - da / radius), pos)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var center: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		var d := pos.distance_to(center)
		if d < radius and _clear_path(pos, center):
			player.take_damage(damage * 0.8 * (1.0 - d / radius), pos, false)
		if d < 30.0:
			player.shake(1.2 * (1.0 - d / 30.0))


## Fogonazo de un disparo de la IA que se ve de lejos: una estrella de
## tamaño fijo en pantalla (siempre ~10 px, esté a 5 o a 80 m) y una
## bocanada de humo. Así se ve de dónde vienen los tiros. Los alemanes, más
## grande y blanco amarillento; los compañeros, más chico y anaranjado.
var _fogonazos: Array = []
var _fogonazos_vivos := 0     # cuántos están encendidos (si no hay, no se revisan)
var _next_fogonazo := 0
var _tex_fogonazo: ImageTexture


func fogonazo(pos: Vector3, aleman: bool) -> void:
	if _fogonazos.is_empty():
		_tex_fogonazo = _estrella()
		for i in 24:
			var s := Sprite3D.new()
			s.texture = _tex_fogonazo
			s.fixed_size = true
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.shaded = false
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			s.render_priority = 10
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.visible = false
			add_child(s)
			_fogonazos.append(s)
	var f: Sprite3D = _fogonazos[_next_fogonazo]
	_next_fogonazo = (_next_fogonazo + 1) % _fogonazos.size()
	f.global_position = pos
	f.pixel_size = (0.007 if aleman else 0.0042) * randf_range(0.85, 1.15)
	f.modulate = Color(1.0, 0.9, 0.5) if aleman else Color(1.0, 0.7, 0.35)
	f.rotation.z = randf() * TAU
	f.visible = true
	# Se apaga a los 0,07 s, pero no antes de 2 cuadros dibujados (en un
	# celular lento, un temporizador lo apagaría antes de que se llegue a ver)
	f.set_meta("hasta", Time.get_ticks_msec() + 70)
	f.set_meta("cuadro", Engine.get_frames_drawn() + 2)
	_fogonazos_vivos += 1
	if aleman:
		_burst(pos, Color(0.6, 0.6, 0.58), 1, 0.4, 0.9, 0.22, Vector3.UP, -0.04)


## Estrella de 4 puntas de 15x15 (el fogonazo).
func _estrella() -> ImageTexture:
	var img := Image.create(15, 15, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 15:
		var d := absi(i - 7)
		var a := clampf(1.0 - d / 7.5, 0.0, 1.0)
		img.set_pixel(i, 7, Color(1, 1, 1, a))
		img.set_pixel(7, i, Color(1, 1, 1, a))
	for y in range(5, 10):
		for x in range(5, 10):
			if absi(x - 7) + absi(y - 7) <= 2:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


## Lo visual de la explosión: bola de fuego, humo y tierra (o agua).
const _EXPLOSION := preload("res://assets/efectos/explosion.png")   # tools/arte/explosion.py
const _EXPLOSION_CUADROS := 10


func _explosion_fx(pos: Vector3) -> void:
	# Bola de fuego en píxeles (tira de 10 cuadros, de frente a la cámara):
	# reserva de 8 que se reciclan (ver play_at)
	if _fuegos.is_empty():
		for i in 8:
			var sp := Sprite3D.new()
			sp.texture = _EXPLOSION
			sp.hframes = _EXPLOSION_CUADROS
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.shaded = false
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sp.visible = false
			add_child(sp)
			_fuegos.append(sp)
	var fire: Sprite3D = _fuegos[_next_fuego]
	_next_fuego = (_next_fuego + 1) % _fuegos.size()
	if fire.has_meta("tw"):
		var viejo: Tween = fire.get_meta("tw")
		if viejo and viejo.is_valid():
			viejo.kill()
	var tam := randf_range(0.1, 0.125)          # 64 px → 6,4–8 m
	fire.pixel_size = tam
	fire.global_position = pos + Vector3(0, 64.0 * tam * 0.5 - 0.7, 0)   # la nube apoyada en el suelo
	fire.flip_h = randf() < 0.5
	fire.frame = 0
	fire.visible = true
	var tw := fire.create_tween()
	fire.set_meta("tw", tw)
	tw.tween_method(func(v: float) -> void: fire.frame = mini(int(v), _EXPLOSION_CUADROS - 1),
		0.0, float(_EXPLOSION_CUADROS), 0.8)
	tw.tween_callback(func() -> void: fire.visible = false)
	_burst(pos, Color(0.32, 0.31, 0.29), 18, 2.5, 1.6, 0.45, Vector3.UP, -0.15)
	if pos.z > sea_from_z and pos.y < 0.5:
		_burst(pos, Color(0.85, 0.88, 0.86), 30, 9.0, 1.2, 0.12, Vector3.UP, 1.2, 15.0)
	else:
		_burst(pos, Color(0.42, 0.36, 0.26), 26, 7.0, 1.0, 0.12, Vector3.UP, 1.5)


func _clear_path(from: Vector3, to: Vector3) -> bool:
	var space := get_tree().root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.3, 0), to, 1 | 512)  # solo escenario
	return space.intersect_ray(q).is_empty()


## Estallido de partículas (polvo, sangre, agua, humo). Cada tipo tiene su
## reserva de emisores que se reciclan (ver play_at).
func _burst(pos: Vector3, color: Color, amount: int, speed: float, life: float,
		size: float, dir: Vector3, gravity_scale: float, spread := 55.0) -> void:
	var clave := "%s|%d|%.2f|%.2f|%.2f|%.2f|%.1f" % [color.to_html(), amount, speed, life, size, gravity_scale, spread]
	if not _emisores.has(clave):
		_emisores[clave] = []
	var lista: Array = _emisores[clave]
	var p: CPUParticles3D = null
	for e: CPUParticles3D in lista:
		if not e.emitting:
			p = e
			break
	if p == null:
		if lista.size() < 12:
			p = CPUParticles3D.new()
			p.one_shot = true
			p.emitting = false
			p.amount = amount
			p.lifetime = life
			p.explosiveness = 1.0
			p.local_coords = false
			var box := BoxMesh.new()
			box.size = Vector3.ONE * size
			box.material = _unshaded(color)
			p.mesh = box
			p.spread = spread
			p.initial_velocity_min = speed * 0.4
			p.initial_velocity_max = speed
			p.gravity = Vector3(0, -9.8 * gravity_scale, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.2
			add_child(p)
			lista.append(p)
		else:
			p = lista.pop_front()   # todos ocupados: se recicla el más antiguo
			lista.append(p)
	p.direction = dir
	p.global_position = pos
	p.restart()


func _unshaded(color: Color) -> StandardMaterial3D:
	if not _mat_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		_mat_cache[color] = mat
	return _mat_cache[color]


func _scene() -> Node:
	var s := get_tree().current_scene
	return s if s else get_tree().root


## Ayudante para construir modelos con cajas (armas, soldados, granadas).
static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot_deg
	parent.add_child(m)
	return m


static func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return mat


# ---------------------------------------------------------------- solo horizontal

## El juego se juega solo en horizontal. En el navegador no siempre se puede
## bloquear el giro (iPhone no deja), así que con el celular vertical se tapa
## todo con un aviso y se pausa hasta que se gire.
var _aviso_giro: Control
var _pausado_por_giro := false


func _solo_horizontal() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {}", true)
	var capa := CanvasLayer.new()
	capa.layer = 120
	add_child(capa)
	_aviso_giro = Control.new()
	_aviso_giro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aviso_giro.mouse_filter = Control.MOUSE_FILTER_STOP
	_aviso_giro.visible = false
	_aviso_giro.process_mode = Node.PROCESS_MODE_ALWAYS
	_aviso_giro.draw.connect(_dibujar_aviso_giro)
	capa.add_child(_aviso_giro)
	get_window().size_changed.connect(_revisar_giro)
	_revisar_giro()


func _revisar_giro() -> void:
	var t := get_window().size
	var vertical := t.y > t.x
	if vertical == _aviso_giro.visible:
		return
	_aviso_giro.visible = vertical
	_aviso_giro.queue_redraw()
	if vertical and not get_tree().paused:
		get_tree().paused = true
		_pausado_por_giro = true
	elif not vertical and _pausado_por_giro:
		get_tree().paused = false
		_pausado_por_giro = false


func _dibujar_aviso_giro() -> void:
	var c := _aviso_giro
	var s := c.size
	c.draw_rect(Rect2(Vector2.ZERO, s), Estilo.OLIVA_0)
	var centro := s / 2.0
	# Un celular acostado, con una flecha de giro
	var tel := Rect2(centro + Vector2(-34, -70), Vector2(68, 40))
	c.draw_rect(tel, Estilo.AMBAR, false, 3.0)
	c.draw_rect(Rect2(tel.position + Vector2(6, 6), tel.size - Vector2(12, 12)), Color(Estilo.AMBAR, 0.25))
	c.draw_arc(centro + Vector2(0, -50), 48.0, deg_to_rad(200), deg_to_rad(330), 16, Estilo.AMBAR_CLARO, 2.0)
	Estilo.texto_c(c, "GIRA EL CELULAR", centro.x, centro.y + 10, Estilo.AMBAR, Estilo.TAM_GRANDE)
	Estilo.texto_c(c, "NORMANDY 1944 SE JUEGA EN HORIZONTAL", centro.x, centro.y + 34, Estilo.CREMA)
