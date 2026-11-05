extends Control
class_name Cinematica
## Cinemáticas (sección 6): antes de cada misión y el prólogo de la campaña.
## Hechas dentro del juego, sin video: cada "plano" es una imagen de ChatGPT
## pixelada (assets/cinematicas/, con tools/arte/cinematicas.py) con un
## movimiento lento de cámara, efectos encima (lluvia, farol, fogonazos,
## sacudidas, grano), una tarjeta escrita a máquina con lugar y hora, y
## subtítulos con el retrato de quien habla. Música y ambientes grabados
## (assets/sonidos/, ver tools/audio/sonidos.py) y efectos de Game.
##
## Se salta tocando dos veces. Al terminar va al mapa (prólogo) o empieza la
## misión. Solo jugando solo (en el cooperativo no hay cinemáticas).
##
## Campos de cada plano:
##   img            nombre en assets/cinematicas/ ("" = pantalla negra)
##   dur            segundos
##   z, c           zoom (inicio, fin) y centro (inicio, fin, de 0 a 1) del encuadre
##   tarjeta        líneas escritas a máquina arriba a la izquierda
##   titulo         texto grande al centro (pantalla negra)
##   subs           [segundo, quién, texto]; quién "" = narrador; "@0".."@2" = los
##                  hombres que elegiste en la pantalla previa
##   fx             "lluvia", "farol", "fogonazos", "sacudida", "oscuro"
##   amb            ambientes en bucle {nombre: dB}: assets/sonidos/amb_<nombre>.ogg
##                  (lluvia_carpa, puerto, lancha, playa_batalla, campo_batalla)
##   amb_rapido     los ambientes cambian de golpe (no con fundido)
##   musica         [pista, dB]: pista nueva ("musica_prologo"), "" = sigue la
##                  que suena (solo cambia el volumen), "corte" = se corta en seco
##   sonidos        [segundo, sonido de Game, dB, tono]

const DATOS := {
	"prologo": [
		{"img": "prologo_1", "dur": 10.0, "z": Vector2(1.0, 1.12), "c": [Vector2(0.5, 0.5), Vector2(0.56, 0.5)],
			"tarjeta": ["SUR DE INGLATERRA", "5 DE JUNIO DE 1944 - 18:40"],
			"subs": [[3.0, "", "LLUEVE DESDE HACE TRES DÍAS."],
				[6.0, "", "AYER EL MANDO APLAZÓ LA INVASIÓN 24 HORAS."]],
			"fx": ["lluvia"], "amb": {"lluvia_carpa": -2.0}, "musica": ["musica_prologo", -10.0]},
		{"img": "prologo_2", "dur": 12.0, "z": Vector2(1.15, 1.4), "c": [Vector2(0.6, 0.58), Vector2(0.64, 0.62)],
			"subs": [[1.0, "MURPHY", "QUERIDA RUTH: NO PUEDO DECIRTE DÓNDE ESTOY."],
				[4.5, "MURPHY", "LOS MUCHACHOS ESTÁN BIEN. DELUCA NO PARA DE HABLAR."],
				[8.0, "MURPHY", "NO TE PREOCUPES POR MÍ. TE ESCRIBO PRONTO."]],
			"fx": ["farol"], "amb": {"lluvia_carpa": -14.0}, "musica": ["", -6.0]},
		{"img": "prologo_3", "dur": 10.0, "z": Vector2(1.3, 1.0), "c": [Vector2(0.72, 0.62), Vector2(0.5, 0.5)],
			"tarjeta": ["PUERTO DE PORTLAND", "5 DE JUNIO DE 1944 - 21:30"],
			"subs": [[3.0, "", "LLEGA LA ORDEN: EMBARCAR."],
				[6.0, "CORONEL", "LA INVASIÓN ES MAÑANA, SEÑORES. BUENA SUERTE."]],
			"amb": {"puerto": -4.0}, "musica": ["", -12.0]},
		{"img": "prologo_4", "dur": 11.0, "z": Vector2(1.0, 1.15), "c": [Vector2(0.5, 0.55), Vector2(0.6, 0.45)],
			"tarjeta": ["EL CANAL DE LA MANCHA", "6 DE JUNIO DE 1944 - 02:15"],
			"subs": [[2.5, "", "CINCO MIL BARCOS CRUZAN EN SILENCIO."], [6.5, "", "NADIE DUERME."]],
			"amb": {"lancha": -14.0}, "musica": ["", -5.0]},
		{"img": "", "dur": 6.0, "logo": true, "amb": {"lancha": -30.0}, "musica": ["", -4.0]},
	],
	"omaha": [
		{"img": "prologo_5", "dur": 10.0, "z": Vector2(1.0, 1.12), "c": [Vector2(0.5, 0.42), Vector2(0.46, 0.48)],
			"tarjeta": ["PLAYA OMAHA - SECTOR DOG GREEN", "6 DE JUNIO DE 1944 - 06:25"],
			"subs": [[3.0, "", "EL BOMBARDEO NAVAL PASA SOBRE LAS LANCHAS."],
				[6.5, "@0", "¿ESOS SON NUESTROS BARCOS? NO SE VE NADA EN LA PLAYA."]],
			"fx": ["fogonazos"], "amb": {"lancha": -4.0, "playa_batalla": -20.0}, "musica": ["musica_omaha", -9.0],
			"sonidos": [[1.2, "explosion_lejos", -4.0, 1.0], [4.0, "explosion_lejos", -2.0, 0.9], [7.5, "explosion_lejos", -4.0, 1.0]]},
		{"img": "prologo_5", "dur": 10.0, "z": Vector2(1.7, 1.9), "c": [Vector2(0.5, 0.8), Vector2(0.5, 0.78)],
			"subs": [[0.5, "TIMONEL", "¡UN MINUTO!"],
				[2.6, "MURPHY", "¡CABEZAS ABAJO! CUANDO BAJE LA RAMPA, NO SE DETENGAN."],
				[5.8, "@1", "PADRE NUESTRO, QUE ESTÁS EN LOS CIELOS..."],
				[8.0, "@2", "¡AGÁRRENSE!"]],
			"fx": ["fogonazos", "sacudida"], "amb": {"lancha": -3.0, "playa_batalla": -9.0}, "musica": ["", -4.0],
			"sonidos": [[0.2, "silbido_proyectil", -6.0, 1.0], [1.4, "explosion_cerca", -7.0, 1.0],
				[3.2, "mg42_lejos", -6.0, 1.0], [4.6, "bala_pasa", -4.0, 1.0], [6.2, "hit", -4.0, 0.8],
				[6.5, "hit", -6.0, 0.9], [6.9, "bala_pasa", -4.0, 1.1], [7.0, "grito_medico", -14.0, 1.0],
				[7.6, "silbido_proyectil", -4.0, 1.0], [8.6, "explosion_cerca", -5.0, 1.0]]},
		# "¡RAMPA!": la música se corta, la rampa cae y entra la playa de golpe
		{"img": "", "dur": 3.0, "subs": [[0.2, "MURPHY", "¡RAMPA!"]], "amb": {"playa_batalla": 0.0},
			"musica": ["corte", 0.0], "amb_rapido": true,
			"sonidos": [[0.5, "rampa", 2.0, 1.0], [1.6, "mg42_lejos", -2.0, 1.0], [2.2, "bala_pasa", -4.0, 1.0]]},
	],
}

# Misión 2: imágenes provisorias (planeador_1/2 dibujadas con código, planeador_3
# sacada del mapa del juego) hasta que lleguen las de ChatGPT (ver docs/09).
const _PLANEADOR := [
	{"img": "planeador_1", "dur": 9.0, "z": Vector2(1.0, 1.14), "c": [Vector2(0.45, 0.5), Vector2(0.55, 0.46)],
		"tarjeta": ["SOBRE NORMANDÍA - PLANEADOR WACO CG-4A", "6 DE JUNIO DE 1944 - 22:58"],
		"subs": [[2.0, "", "LOS C-47 REMOLCAN LOS PLANEADORES SOBRE LA COSTA."],
			[5.6, "@0", "¿ESO DE ALLÁ ABAJO ES LA ANTIAÉREA?"]],
		"fx": ["fogonazos", "sacudida"], "amb": {"lancha": -10.0, "campo_batalla": -24.0},
		"musica": ["musica_omaha", -12.0],
		"sonidos": [[1.5, "explosion_lejos", -8.0, 1.2], [4.2, "explosion_lejos", -6.0, 1.0], [7.4, "explosion_lejos", -5.0, 1.1]]},
	{"img": "planeador_2", "dur": 9.5, "z": Vector2(1.08, 1.3), "c": [Vector2(0.5, 0.5), Vector2(0.52, 0.56)],
		"subs": [[0.5, "PILOTO", "¡SOLTAMOS EL CABLE! ¡AGÁRRENSE, VAMOS A BAJAR!"],
			[3.6, "MURPHY", "¡CASCOS PUESTOS! ¡PIES ARRIBA, BRAZOS ADENTRO!"],
			[6.6, "@1", "DIOS MÍO... NO SE VE NADA AHÍ AFUERA."]],
		"fx": ["sacudida", "farol"], "amb": {"lancha": -16.0, "campo_batalla": -18.0}, "musica": ["", -7.0],
		"sonidos": [[1.0, "throw", -4.0, 0.4], [4.8, "bala_pasa", -4.0, 0.9], [5.0, "hit", -2.0, 0.6],
			[5.3, "bala_pasa", -6.0, 1.1], [8.0, "explosion_lejos", -4.0, 0.9]]},
	{"img": "planeador_3", "dur": 6.0, "z": Vector2(1.0, 1.5), "c": [Vector2(0.5, 0.4), Vector2(0.48, 0.62)],
		"subs": [[0.8, "@2", "¡ÁRBOLES! ¡ÁRBOLES!"], [3.4, "PILOTO", "¡SUJÉTENSE!"]],
		"fx": ["sacudida", "fogonazos"], "amb": {"lancha": -12.0, "campo_batalla": -10.0}, "musica": ["", -3.0],
		"sonidos": [[2.0, "mg42_lejos", -4.0, 1.0], [4.0, "bala_pasa", -2.0, 1.0]]},
	# El choque contra el seto, a oscuras. Después, el silencio y el grillo.
	{"img": "", "dur": 5.0, "subs": [[2.6, "MURPHY", "...¿DELUCA? ¿HAYES? ¿BRENNAN?"]],
		"amb": {"campo_batalla": -12.0}, "musica": ["corte", 0.0], "amb_rapido": true,
		"sonidos": [[0.1, "explosion_cerca", 0.0, 0.7], [0.2, "hit", 2.0, 0.5], [0.45, "hit", 0.0, 0.4],
			[0.7, "bounce", 0.0, 0.6], [4.2, "grillo", -2.0, 1.0]]},
]

const LOGO := preload("res://assets/ui/logo.png")
const BARRA := 40.0        # franjas negras de arriba y abajo
const FUNDIDO := 0.6       # segundos de fundido a negro entre planos
const TECLA := 0.045       # segundos por letra de la tarjeta

static var actual := ""          # cinemática a mostrar
static var despues := "mision"   # "mision" o "mapa"

var _planos: Array = []
var _i := 0
var _t := 0.0
var _imagenes := {}
var _retratos := {}
var _equipo: Array = []
var _amb := {}                   # nombre -> AudioStreamPlayer
var _musica: AudioStreamPlayer
var _musica_db := -60.0
var _tecla: AudioStreamPlayer      # máquina de escribir de la tarjeta
var _plano_visto := -1
var _letras := 0
var _sonados := {}
var _saltar := 0.0
var _flash := 0.0
var _terminada := false
var _rng := RandomNumberGenerator.new()
var _vineta: Texture2D


static func tiene(id: String) -> bool:
	return DATOS.has(id) or id == "planeador"


static func _planos_de(id: String) -> Array:
	if id == "planeador":
		return _PLANEADOR
	return DATOS.get(id, [])


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rng.randomize()
	_planos = _planos_de(actual)
	for e in Compania.equipo():
		_equipo.append(e[0])
	while _equipo.size() < 3:
		_equipo.append(["DELUCA", "HAYES", "BRENNAN"][_equipo.size()])
	for p in _planos:
		if p["img"] != "" and not _imagenes.has(p["img"]):
			var ruta := "res://assets/cinematicas/%s.png" % p["img"]
			_imagenes[p["img"]] = load(ruta) if ResourceLoader.exists(ruta) else null
	_vineta = _crear_vineta()
	_crear_ambientes()
	if _planos.is_empty():
		_terminar()


# ================================================================ tiempo

func _process(delta: float) -> void:
	if _terminada:
		return
	_t += delta
	_saltar = maxf(_saltar - delta, 0.0)
	_flash = maxf(_flash - delta * 3.0, 0.0)
	var p: Dictionary = _planos[_i]
	if _plano_visto != _i:
		_plano_visto = _i
		_empieza_plano(p)
	# Letras de la tarjeta (con sonido de máquina de escribir)
	var total := _total_letras(p)
	var debe := mini(int(maxf(_t - 0.4, 0.0) / TECLA), total)
	if debe > _letras:
		if _tecla.stream == null:
			Game.play("click", -16.0, _rng.randf_range(1.6, 2.2))
		elif not _tecla.playing:
			_tecla.play()
		_letras = debe
	if _letras >= total and _tecla.playing and _t > 0.5:
		_tecla.stop()
	# Sonidos del plano
	for k in p.get("sonidos", []).size():
		var s: Array = p["sonidos"][k]
		if _t >= s[0] and not _sonados.has(k):
			_sonados[k] = true
			Game.play(s[1], s[2], s[3])
			if s[1].begins_with("explosion") and "fogonazos" in p.get("fx", []):
				_flash = 0.5
	# Fogonazos sueltos de los barcos
	if "fogonazos" in p.get("fx", []) and _rng.randf() < delta * 0.5:
		_flash = maxf(_flash, 0.25)
		Game.play("rifle_far", -20.0, _rng.randf_range(0.4, 0.6))
	_volumenes(p, delta)
	if _t >= p["dur"]:
		_siguiente()
	queue_redraw()


func _siguiente() -> void:
	_i += 1
	_t = 0.0
	_letras = 0
	_sonados = {}
	if _i >= _planos.size():
		_terminar()


func _terminar() -> void:
	if _terminada:
		return
	_terminada = true
	# El ambiente de la playa sigue sonando mientras carga la misión
	if despues == "mision" and _amb.has("playa_batalla") and _amb["playa_batalla"].volume_db > -20.0:
		Game.seguir_sonando(_amb["playa_batalla"])
	for a in _amb.values():
		a.stop()
	if _musica:
		_musica.stop()
	if despues == "mapa":
		Game.ir_al_mapa()
	else:
		# Que se vea "PREPARANDO..." antes de que se trabe cargando la misión
		queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		Game.empezar_mision(Game.mision, true)


func _input(event: InputEvent) -> void:
	var toque: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed) or \
		(event is InputEventKey and event.pressed and not event.echo)
	if not toque:
		return
	get_viewport().set_input_as_handled()
	if _saltar > 0.0:
		_terminar()
	else:
		_saltar = 2.5


# ================================================================ sonido

## Ambientes en bucle (grabados; si falta el archivo, uno generado con código).
func _crear_ambientes() -> void:
	var usados := {}
	for p in _planos:
		for k in p.get("amb", {}):
			usados[k] = true
	var viejo := {"lluvia_carpa": "lluvia", "puerto": "mar", "lancha": "motor", "playa_batalla": "mar"}
	for k in usados:
		var a := Game.reproductor_largo("amb_" + k, true)
		if a.stream == null:
			a.playback_type = AudioServer.PLAYBACK_TYPE_DEFAULT
			a.stream = _bucle(viejo.get(k, "mar"))
		a.volume_db = -60.0
		add_child(a)
		a.play(_rng.randf() * 10.0)
		_amb[k] = a
	_musica = Game.reproductor_largo("")
	add_child(_musica)
	_tecla = AudioStreamPlayer.new()
	_tecla.stream = Game.pista("maquina_escribir")
	_tecla.volume_db = -6.0
	add_child(_tecla)


## Al empezar cada plano: la música (nueva, sigue o se corta).
func _empieza_plano(p: Dictionary) -> void:
	if not p.has("musica"):
		return
	var m: Array = p["musica"]
	match m[0]:
		"":
			pass
		"corte":
			_musica.stop()
		_:
			_musica.stream = Game.pista(m[0])
			_musica.volume_db = m[1]
			if _musica.stream:
				_musica.play()
	_musica_db = m[1]


func _bucle(tipo: String) -> AudioStreamWAV:
	var rate := 11025
	var seg := 4.0
	var n := int(seg * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var brillo: float = {"lluvia": 0.55, "mar": 0.05, "motor": 0.02}.get(tipo, 0.1)
	for i in n:
		var t := float(i) / rate
		var ruido := _rng.randf_range(-1.0, 1.0)
		lp += (ruido - lp) * brillo
		lp2 += (lp - lp2) * 0.3
		var v := 0.0
		match tipo:
			"lluvia":
				v = (lp - lp2) * 0.9 + (0.3 if _rng.randf() < 0.002 else 0.0) * ruido
			"mar":      # oleaje: ruido grave que sube y baja (dos olas cada 4 s)
				v = lp * 2.2 * (0.55 + 0.45 * sin(TAU * t / 2.0))
			"motor":    # motor de la lancha: zumbido grave con algo de ruido
				v = sin(TAU * 46.0 * t) * 0.35 + sin(TAU * 92.0 * t) * 0.18 + lp * 3.0
		# Fundido en los bordes del bucle para que no haga clic
		var borde := clampf(minf(t, seg - t) / 0.05, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * borde, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _volumenes(p: Dictionary, delta: float) -> void:
	var amb: Dictionary = p.get("amb", {})
	var fundido := _fundido(p)
	for k in _amb:
		var meta: float = amb.get(k, -60.0)
		if fundido > 0.0 and _i == _planos.size() - 1 and despues == "mapa":
			meta = lerpf(meta, -60.0, fundido)
		var a: AudioStreamPlayer = _amb[k]
		a.volume_db = meta if p.get("amb_rapido", false) else move_toward(a.volume_db, meta, delta * 30.0)
	if _musica and _musica.playing:
		var mm := _musica_db
		if _i == _planos.size() - 1:       # último plano: la música se apaga despacio
			mm = lerpf(_musica_db, -40.0, clampf(_t / p["dur"], 0.0, 1.0))
		_musica.volume_db = move_toward(_musica.volume_db, mm, delta * 12.0)


# ================================================================ dibujo

## 0 = imagen a pleno, 1 = negro (fundido al empezar y al terminar el plano).
func _fundido(p: Dictionary) -> float:
	var d: float = p["dur"]
	return clampf(1.0 - minf(_t, d - _t) / FUNDIDO, 0.0, 1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if _terminada and despues == "mision":
		Estilo.texto_c(self, "PREPARANDO %s..." % Misiones.dato("nombre"), size.x / 2, size.y / 2, Estilo.AMBAR)
	if _terminada or _i >= _planos.size():
		return
	var p: Dictionary = _planos[_i]
	var vista := Rect2(0, BARRA, size.x, size.y - BARRA * 2)
	var tex: Texture2D = _imagenes.get(p["img"])
	var k := clampf(_t / p["dur"], 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)     # suave al empezar y al terminar
	if tex:
		var z := lerpf(p["z"].x, p["z"].y, k)
		var c: Vector2 = p["c"][0].lerp(p["c"][1], k)
		var tam := tex.get_size()
		# Encuadre con la proporción de la vista, recortado dentro de la imagen
		var w := tam.x / z
		var h := w * vista.size.y / vista.size.x
		if h > tam.y:
			h = tam.y / z
			w = h * vista.size.x / vista.size.y
		var o := (c * tam - Vector2(w, h) / 2.0).clamp(Vector2.ZERO, tam - Vector2(w, h))
		if "sacudida" in p.get("fx", []):
			o += Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0)) * (1.0 + _flash * 4.0)
			o = o.clamp(Vector2.ZERO, tam - Vector2(w, h))
		var tinte := Color.WHITE
		if "farol" in p.get("fx", []):
			var luz := 0.88 + 0.12 * sin(_t * 9.0) * sin(_t * 3.7) + _rng.randf_range(-0.03, 0.03)
			tinte = Color(luz, luz * 0.97, luz * 0.9)
		draw_texture_rect_region(tex, vista, Rect2(o, Vector2(w, h)), tinte)
		_efectos(p, vista)
		draw_texture_rect(_vineta, vista, false)
	if p.get("logo", false):
		var a := 1.0 - _fundido(p)
		var lw := minf(size.x * 0.55, 420.0)
		var lh := lw * LOGO.get_height() / LOGO.get_width()
		var k2 := 1.0 + 0.04 * clampf(_t / p["dur"], 0.0, 1.0)      # se acerca apenas
		var r := Rect2(size / 2.0 - Vector2(lw, lh) * k2 / 2.0, Vector2(lw, lh) * k2)
		draw_texture_rect(LOGO, r, false, Color(1, 1, 1, a))
	if p.has("titulo"):
		var a := 1.0 - _fundido(p)
		Estilo.texto_c(self, p["titulo"], size.x / 2.0, size.y / 2.0 + 8, Color(Estilo.AMBAR, a), 44)
	# Fundido a negro
	var f := _fundido(p)
	if f > 0.0:
		draw_rect(vista, Color(0, 0, 0, f))
	_tarjeta(p)
	_subtitulo(p)
	if _saltar > 0.0:
		var t := "TOCA OTRA VEZ PARA SALTAR"
		Estilo.texto(self, t, Vector2(size.x - 12 - Estilo.ancho_texto(t), 24), Color(Estilo.CREMA, 0.7))


func _efectos(p: Dictionary, v: Rect2) -> void:
	var fx: Array = p.get("fx", [])
	if "lluvia" in fx:
		for i in 140:
			var x := fmod(i * 97.13 + _t * 40.0, v.size.x + 60.0) - 30.0
			var y := fmod(i * 53.71 + _t * (260.0 + (i % 5) * 30.0), v.size.y)
			var a := Vector2(v.position.x + x, v.position.y + y)
			draw_line(a, a + Vector2(-3, 9), Color(Estilo.CREMA, 0.22), 1.0)
	if _flash > 0.0:
		draw_rect(v, Color(1.0, 0.85, 0.6, _flash * 0.35))
	# Grano de película
	for i in 220:
		var q := Vector2(_rng.randf_range(v.position.x, v.end.x), _rng.randf_range(v.position.y, v.end.y)).floor()
		draw_rect(Rect2(q, Vector2.ONE), Color(0, 0, 0, 0.25) if i % 2 == 0 else Color(1, 1, 1, 0.08))


func _tarjeta(p: Dictionary) -> void:
	var lineas: Array = p.get("tarjeta", [])
	if lineas.is_empty():
		return
	var queda := _letras
	var y := BARRA + 22.0
	for l in lineas:
		var s: String = l
		var parte := s.substr(0, clampi(queda, 0, s.length()))
		queda -= s.length()
		if parte != "":
			Estilo.texto(self, parte + ("_" if queda < 0 and fmod(_t, 0.5) < 0.25 else ""), Vector2(16, y),
				Estilo.AMBAR_CLARO if y < BARRA + 30 else Estilo.CREMA)
		y += 14.0


func _total_letras(p: Dictionary) -> int:
	var n := 0
	for l in p.get("tarjeta", []):
		n += (l as String).length()
	return n


func _subtitulo(p: Dictionary) -> void:
	var sub: Array = []
	for s in p.get("subs", []):
		if _t >= s[0]:
			sub = s
	if sub.is_empty():
		return
	var quien: String = sub[1]
	if quien.begins_with("@"):
		quien = _equipo[int(quien.substr(1)) % _equipo.size()]
	var texto: String = sub[2]
	var y := size.y - BARRA + 4
	var a := clampf((_t - sub[0]) / 0.25, 0.0, 1.0) * (1.0 - _fundido(p) * 0.7)
	if quien == "":
		Estilo.texto_c(self, texto, size.x / 2.0, y + 20, Color(Estilo.CREMA, a))
		return
	var tex := _retrato(quien)
	var x := 16.0
	if tex:
		draw_texture_rect(tex, Rect2(x, y, 38, 33), false, Color(1, 1, 1, a))
		x += 46.0
	Estilo.texto(self, quien, Vector2(x, y + 12), Color(Estilo.AMBAR_CLARO, a))
	Estilo.texto(self, texto, Vector2(x, y + 26), Color(Estilo.CREMA, a), Estilo.TAM, size.x - x - 12)


func _retrato(nombre: String) -> Texture2D:
	var clave := nombre.to_lower()
	if not _retratos.has(clave):
		var ruta := "res://assets/ui/retratos/retrato_%s.png" % clave
		if ResourceLoader.exists(ruta):
			_retratos[clave] = load(ruta)
		elif Compania.hombre(nombre).size() > 0:
			_retratos[clave] = Estilo.RETRATO_PROVISIONAL
		else:
			_retratos[clave] = null     # TIMONEL u otros sin cara: solo el nombre
	return _retratos[clave]


## Oscurece los bordes de la imagen (como una película vieja).
func _crear_vineta() -> Texture2D:
	var img := Image.create(160, 90, false, Image.FORMAT_RGBA8)
	for y in 90:
		for x in 160:
			var d := Vector2((x - 79.5) / 80.0, (y - 44.5) / 45.0).length()
			img.set_pixel(x, y, Color(0, 0, 0, clampf((d - 0.65) * 1.3, 0.0, 0.7)))
	return ImageTexture.create_from_image(img)
