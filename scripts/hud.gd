extends Control
## HUD estilo Hamburger Hill: barra de chapa verde oliva abajo con registro de
## mensajes, retrato del soldado (se pone rojo al recibir daño), clima/hora/
## brújula, granadas, munición en números ámbar y las dos armas. También dibuja
## la cruz de puntería, el marcador de impacto, el destello rojo de daño y el
## indicador de dirección. Colores, letra y marcos vienen de Estilo.

const BAR_H := 52
const SOLDIER_NAME := "MURPHY"

## Retratos de 38x33 en assets/ui/retratos/ (hechos con tools/arte/adaptar_imagenes.py).
## Si existe retrato_<nombre>_herido.png se muestra con poca vida; si no, se tiñe de rojo.
var soldado := "murphy"
var _retrato: Texture2D
var _retrato_herido: Texture2D

var _player: Player
var _messages: Array = []   # [texto, color, tiempo]
var _slot_rects: Array[Rect2] = []


func _ready() -> void:
	add_to_group("hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.message.connect(_on_message)
	_cargar_retratos()
	Game.warmup.call_deferred()


func _cargar_retratos() -> void:
	var base := "res://assets/ui/retratos/retrato_%s" % soldado
	_retrato = load(base + ".png") if ResourceLoader.exists(base + ".png") else null
	_retrato_herido = load(base + "_herido.png") if ResourceLoader.exists(base + "_herido.png") else null
	if _retrato == null:
		_retrato = _retrato_herido if _retrato_herido else Estilo.RETRATO_PROVISIONAL


func _on_message(text: String, color: Color) -> void:
	_messages.append([text, color, 0.0])
	if _messages.size() > 4:
		_messages.pop_front()


func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	for m in _messages:
		m[2] += delta
	_messages = _messages.filter(func(m: Array) -> bool: return m[2] < 7.0)
	if _player and _player.weapons:
		_expulsar(_player.weapons, delta)
	_medir(delta)
	queue_redraw()


# --- Medidor de fluidez (para comparar celulares): cuadros por segundo del
# último segundo y el cuadro más lento (los tirones se notan ahí).
var _med_cuadros := 0
var _med_t := 0.0
var _med_peor := 0.0
var _med_texto := ""
var _med_desglose := ""
var _med_codigo := 0.0        # ms de nuestros guiones en el cuadro más lento
var _med_color := Color.WHITE


func _medir(delta: float) -> void:
	_med_cuadros += 1
	_med_t += delta
	if delta > _med_peor:
		# Desglose del cuadro más lento (para encontrar qué traba): cuánto fue
		# nuestro código (guiones) y cuánto el motor (física, dibujo, navegador).
		_med_peor = delta
		_med_codigo = Game.codigo_cuadro_us / 1000.0
	if _med_t >= 1.0:
		var fps := roundi(_med_cuadros / _med_t)
		_med_texto = "%d FPS  PEOR %d MS" % [fps, roundi(_med_peor * 1000.0)]
		_med_desglose = "CODIGO %d  MOTOR %d" % [roundi(_med_codigo),
			maxi(0, roundi(_med_peor * 1000.0 - _med_codigo))]
		_med_color = Estilo.VERDE_LED if fps >= 50 else (Estilo.AMBAR if fps >= 30 else Estilo.ROJO)
		_med_cuadros = 0
		_med_t = 0.0
		_med_peor = 0.0


## Para los controles táctiles: ¿qué ranura de arma hay en este punto? (-1 = ninguna)
func slot_at(pos: Vector2) -> int:
	for i in _slot_rects.size():
		if _slot_rects[i].has_point(pos):
			return i
	return -1


func _draw() -> void:
	if _player == null:
		return
	var s := size
	var w := _player.weapons
	_draw_viewmodel(w)
	_draw_volando()
	var top := s.y - BAR_H
	if w.scoped() and not _player.dead:
		_draw_scope((s / 2.0).floor(), top)
	# El centro de la cámara es el centro de TODA la pantalla (la barra se dibuja
	# encima de la vista 3D), y por ahí salen las balas.
	var center := (s / 2.0).floor()

	# --- Efectos sobre la vista
	if _player.damage_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.7, 0.0, 0.0, _player.damage_flash * 0.3))
	if _player.hit_indicator > 0.0 and not _player.dead:
		_draw_hit_indicator(center, _player.hit_angle, minf(_player.hit_indicator, 1.0))
	if not _player.dead and w.ads_amount < 0.5 and not _player.sprinting:
		_draw_crosshair(center, w.spread_now)
	if w.hit_marker > 0.0:
		var c := Color(1, 1, 1, w.hit_marker)
		for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(center + d * 3, center + d * 7, c, 1.0)
	if _player.dead:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.45))
		Estilo.texto_c(self, "HAS CAIDO", s.x / 2, top / 2 + 2, Estilo.ROJO, Estilo.TAM_GRANDE)
		Estilo.texto_c(self, "REINICIANDO...", s.x / 2, top / 2 + 18, Estilo.CREMA)

	if Game.warming:   # pantalla de espera mientras se preparan los efectos
		# Dibuja todas las letras una vez (tapadas por el negro): la fuente
		# prepara cada letra la primera vez que se usa, y eso trababa un
		# cuadro cuando aparecía un mensaje nuevo en medio del combate.
		for tam in [Estilo.TAM, Estilo.TAM_GRANDE]:
			Estilo.texto(self, "ABCDEFGHIJKLMNÑOPQRSTUVWXYZÁÉÍÓÚÜ0123456789[]:-.,!¡?¿+/|%()'", Vector2(0, 40), Estilo.CREMA, tam)
		draw_rect(Rect2(Vector2.ZERO, s), Estilo.NEGRO)
		Estilo.texto_c(self, "PREPARANDO LA PLAYA...", s.x / 2, s.y / 2, Estilo.AMBAR)
		return
	Estilo.texto(self, "NORMANDY 1944  V%s" % ProjectSettings.get_setting("application/config/version"),
		Vector2(4, 10), Color(Estilo.CREMA, 0.35))
	Estilo.texto(self, _med_texto, Vector2(4, 21), Color(_med_color, 0.7))
	Estilo.texto(self, _med_desglose, Vector2(4, 32), Color(Estilo.CREMA, 0.55))
	if Game.prueba_carga:
		Estilo.texto(self, Game.carga_texto, Vector2(4, 43), Color(Estilo.AMBAR_CLARO, 0.8))

	# Arma en el suelo para recoger
	var suelta := _player.pickup_near as ArmaSuelta
	if suelta and is_instance_valid(suelta) and not _player.dead:
		var tecla := "[TOMAR]" if DisplayServer.is_touchscreen_available() else "[E]"
		Estilo.texto_c(self, "%s RECOGER %s" % [tecla, suelta.nombre()], s.x / 2, top - 40, Estilo.AMBAR_CLARO)

	# --- Barra inferior
	Estilo.marco(self, Rect2(0, top, s.x, BAR_H), "lisa")
	var right_w := 486.0
	var x := s.x - right_w
	_draw_messages(Vector2(4, top - 4))
	_draw_escuadra(Rect2(3, top + 2, x - 6, BAR_H - 4))
	_draw_portrait(Rect2(x, top + 2, 60, BAR_H - 4))
	_draw_status(Rect2(x + 62, top + 2, 76, BAR_H - 4))
	_draw_grenades(Rect2(x + 140, top + 2, 67, BAR_H - 4))
	_draw_ammo(Rect2(x + 209, top + 2, 105, BAR_H - 4))
	_draw_slots(Rect2(x + 316, top + 2, right_w - 318, BAR_H - 4))


# Arma en la mano dibujada como imagen (estilo Doom / Hamburger Hill).
# Los datos de cada arma (vm_pos, vm_boca, vm_mira, mira_pos, mira_poste,
# recarga_punto, expulsion) están en armas.gd. mira_pos se ajusta para que el
# punto de mira quede justo en el centro de la pantalla (320, 180), por donde
# salen las balas. VM_PIVOT = punto de giro de la imagen (las manos).
const VM_PIVOT := Vector2(420, 330)
# Recarga dibujada: dónde entra el clip del Garand (cajón abierto) y dónde
# entra el cargador del Colt (base de la empuñadura), en píxeles de la imagen.
const _CLIP := preload("res://assets/armas/pieza_clip_garand.png")      # foto de ChatGPT pixelada
const _CARGADOR := preload("res://assets/armas/pieza_cargador_colt.png")   # si el arma no tiene el suyo
var _cargador_pantalla := Vector2.ZERO
const _VAINA := preload("res://assets/armas/pieza_vaina.png")
const _CLIP_VACIO := preload("res://assets/armas/pieza_clip_vacio.png")
# Dónde salen las vainas (en la imagen de cada arma): la ventana del cajón / corredera
var _volando: Array = []    # piezas en el aire: [textura, pos, vel, ángulo, giro, vida, escala]
var _shots_vistos := -1
var _clips_vistos := -1


## Vainas y clips vacíos que saltan del arma (en 2D, sobre la vista).
func _expulsar(w: Weapons, delta: float) -> void:
	if _shots_vistos < 0:
		_shots_vistos = w.shots_fired
		_clips_vistos = w.clips_ejected
	var origen: Vector2 = _v(w, "vm_pos") + _v(w, "expulsion") + w.view_offset
	if w.ads_amount > 0.5:
		origen = Vector2(size.x / 2.0 + 40, size.y / 2.0 + 30)
	while _shots_vistos < w.shots_fired:
		_shots_vistos += 1
		var esc := 0.65 if w.def()["tipo"] in ["pistola", "subfusil"] else 1.0
		_volando.append([_VAINA, origen, Vector2(randf_range(70, 120), randf_range(-190, -140)),
			randf_range(-0.3, 0.3), randf_range(-14, -8), 0.9, esc])
	while _clips_vistos < w.clips_ejected:
		_clips_vistos += 1
		_volando.append([_CLIP_VACIO, origen + Vector2(-6, -6), Vector2(randf_range(10, 40), -300),
			0.0, randf_range(5, 9), 1.2, 1.0])
	for v in _volando:
		v[2].y += 650.0 * delta
		v[1] += v[2] * delta
		v[3] += v[4] * delta
		v[5] -= delta
	_volando = _volando.filter(func(v: Array) -> bool: return v[5] > 0.0 and v[1].y < size.y)


func _draw_volando() -> void:
	for v in _volando:
		var tex: Texture2D = v[0]
		draw_set_transform(v[1].round(), v[3], Vector2.ONE * v[6])
		draw_texture(tex, (-tex.get_size() / 2.0).round())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
const GRANADA_POS := Vector2(120, 40)


## Dato de imagen del arma actual (ver armas.gd); Vector2.ZERO si no lo tiene.
func _v(w: Weapons, campo: String) -> Vector2:
	return w.def().get(campo, Vector2.ZERO)


func _draw_viewmodel(w: Weapons) -> void:
	if w.sprite_cadera[w.current] == null or _player.dead or w.scoped():   # con mira telescópica solo se ve el círculo
		return
	var centro := (size / 2.0).floor()
	var off := w.view_offset.round()
	# Granada en la mano mientras se lanza: sube y vuelve a bajar
	var tp := w.throw_progress()
	if tp >= 0.0 and w.sprite_granada:
		var sube := sin(PI * clampf(tp * 1.4, 0.0, 1.0))
		draw_texture(w.sprite_granada, GRANADA_POS + Vector2(-40.0 * sube, 230.0 * (1.0 - sube)).round())
		return
	var a := w.ads_amount
	var mira: Texture2D = w.sprite_mira[w.current]
	if mira and a >= 0.5:
		# Por la mira: la imagen sube desde abajo y queda fija con el poste al centro
		var pos: Vector2 = _v(w, "mira_pos") + Vector2(0, roundf((1.0 - a) * 2.0 * 120.0)) + off * 0.5
		pos += centro - Vector2(320, 180)
		draw_texture(mira, pos.round())
		if w.flash_2d > 0.0:
			_draw_flash_2d(pos + _v(w, "mira_poste") + Vector2(0, -3), 0.6)
		return
	# Desde la cadera; al apuntar se desliza hasta que su punto de mira llega al centro
	var t := smoothstep(0.0, 1.0, a)
	var hacia: Vector2 = centro - (_v(w, "vm_pos") + _v(w, "vm_mira"))
	var desliz := hacia * (t * 0.6 if mira else t)
	var giro := deg_to_rad(w.view_angle) * (1.0 - t)
	var o: Vector2 = _v(w, "vm_pos") - VM_PIVOT
	# Recarga: el arma se mueve y aparece el clip o el cargador
	var rp := w.reload_progress()
	var pieza := Vector4.ZERO   # x, y = posición de la pieza (imagen); z = 1 si se ve; w = 1 si va detrás
	if rp >= 0.0:
		var baja := smoothstep(0.0, 0.18, rp) * (1.0 - smoothstep(0.8, 1.0, rp))
		var k := smoothstep(0.25, 0.6, rp)      # la pieza llega a su lugar
		var golpe := 3.0 if rp > 0.6 and rp < 0.66 else 0.0
		var punto: Vector2 = o + _v(w, "recarga_punto")
		if w.def().get("recarga", "") == "clip":   # Garand: baja e inclina a la izquierda; el clip entra desde arriba
			off += Vector2(-30, 60 + golpe) * baja
			giro -= deg_to_rad(14.0) * baja
			if rp > 0.2 and rp < 0.64:
				var desde := punto + Vector2(70, -110)
				var p2 := desde.lerp(punto, k) + Vector2(0, 8.0 * smoothstep(0.58, 0.64, rp))
				pieza = Vector4(p2.x - 17, p2.y - 24, 1, 0)
		elif w.def().get("recarga", "") == "cohete":   # bazuca: baja para meter el cohete por atrás
			off += Vector2(40, 110 + golpe) * baja
			giro += deg_to_rad(10.0) * baja
		elif w.id() != "colt":   # cargador a la vista (Carbine, Thompson...): entra por abajo hasta su lugar
			off += Vector2(-20, -55 + golpe) * baja      # sube el arma para que se vea el cargador
			giro += deg_to_rad(8.0) * baja
			if rp > 0.25 and rp < 0.62:
				var cg := Armas.imagen("pieza_cargador_" + w.id())
				var ancho := cg.get_width() if cg else 20
				pieza = Vector4(punto.x - ancho / 2.0, punto.y + 100.0 * (1.0 - k), 1, 2)
		else:                # Colt: baja e inclina; el cargador nuevo sube desde abajo
			var hondo := smoothstep(0.0, 0.25, rp) * (1.0 - smoothstep(0.72, 0.95, rp))
			off += Vector2(30, 55 * hondo + golpe)
			giro += deg_to_rad(12.0) * hondo
			if rp > 0.3 and rp < 0.62:
				var sube := smoothstep(0.3, 0.6, rp)
				pieza = Vector4(0, 0, 1, 1)
				_cargador_pantalla = Vector2(446, 345 - 95.0 * sube).round()
	draw_set_transform((VM_PIVOT + off + desliz).round(), giro, Vector2.ONE)
	draw_texture(w.sprite_cadera[w.current], o.round())
	if pieza.z > 0.0 and pieza.w == 0.0:
		draw_texture(_CLIP, Vector2(pieza.x, pieza.y).round())
	if pieza.z > 0.0 and pieza.w == 2.0:
		var cg2 := Armas.imagen("pieza_cargador_" + w.id())
		draw_texture(cg2 if cg2 else _CARGADOR, Vector2(pieza.x, pieza.y).round())
	if pieza.z > 0.0 and pieza.w == 1.0:   # cargador del Colt subiendo hacia la empuñadura, al doble
		draw_set_transform(_cargador_pantalla, deg_to_rad(12.0), Vector2.ONE)
		var cargador := Armas.imagen("pieza_cargador_" + w.id())
		draw_texture(cargador if cargador else _CARGADOR, Vector2.ZERO)
	if w.flash_2d > 0.0:
		_draw_flash_2d(o + _v(w, "vm_boca"), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Fogonazo de píxeles: estrella amarilla con centro blanco, al azar cada vez.
func _draw_flash_2d(c: Vector2, escala: float) -> void:
	var largo := randf_range(14.0, 22.0) * escala
	for i in 5:
		var a := -PI * 0.85 + i * 0.35 + randf_range(-0.1, 0.1)
		var d := Vector2(cos(a), sin(a))
		draw_line(c, c + d * largo * (1.0 if i % 2 == 0 else 0.6), Color(1.0, 0.75, 0.25), 3.0)
	draw_circle(c, 5.0 * escala, Color(1.0, 0.85, 0.4))
	draw_circle(c, 2.5 * escala, Color(1.0, 1.0, 0.85))


## Mira telescópica (Springfield): todo negro salvo un círculo, con retícula.
func _draw_scope(c: Vector2, top: float) -> void:
	var r := minf(c.y, top / 2.0) * 0.95
	draw_arc(c, r + 300.0, 0, TAU, 72, Estilo.NEGRO, 600.0)
	draw_arc(c, r, 0, TAU, 72, Color(0.02, 0.02, 0.02), 3.0)
	var neg := Color(0.02, 0.02, 0.02)
	draw_line(c - Vector2(r, 0), c - Vector2(6, 0), neg, 1.0)
	draw_line(c + Vector2(6, 0), c + Vector2(r, 0), neg, 1.0)
	draw_rect(Rect2(c.x - 1, c.y + 2, 3, r - 2), neg)          # poste grueso desde abajo
	draw_line(c - Vector2(0, r), c - Vector2(0, 6), neg, 1.0)


func _draw_crosshair(c: Vector2, spread_deg: float) -> void:
	var gap := roundf(2.0 + spread_deg * 2.2)
	var col := Color(Estilo.AMBAR_CLARO, 0.9)
	var sombra := Color(Estilo.NEGRO, 0.6)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var a: Vector2 = c + d * gap
		var b: Vector2 = c + d * (gap + 5)
		draw_line(a + Vector2(1, 1), b + Vector2(1, 1), sombra, 1.0)
		draw_line(a, b, col, 1.0)


func _draw_hit_indicator(c: Vector2, angle: float, alpha: float) -> void:
	# Arco rojo alrededor del centro apuntando hacia quien te disparó
	var a := angle - PI / 2.0
	draw_arc(c, 46, a - 0.35, a + 0.35, 8, Color(Estilo.ROJO, 0.85 * alpha), 3.0)


## Mensajes encima de la barra, a la izquierda (el más nuevo abajo).
func _draw_messages(abajo: Vector2) -> void:
	var y := abajo.y - (_messages.size() - 1) * 10
	for m in _messages:
		var col: Color = m[1]
		col.a = clampf(7.0 - m[2], 0.0, 1.0)
		var sombra := Color(0, 0, 0, col.a * 0.8)
		Estilo.texto(self, m[0], Vector2(abajo.x + 1, y + 1), sombra)
		Estilo.texto(self, m[0], Vector2(abajo.x, y), col)
		y += 10


# --- Escuadra: retratos de los compañeros y las tres órdenes (como los
# botones » → ‖ de Hamburger Hill). Se tocan con el dedo o con Z / X / V.
const ORDENES := ["seguir", "avanzar", "mantener"]
var _orden_rects: Array[Rect2] = []
var _retratos_escuadra := {}


func orden_at(pos: Vector2) -> String:
	for i in _orden_rects.size():
		if _orden_rects[i].grow(2).has_point(pos):
			return ORDENES[i]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	for i in 3:
		if event.is_action_pressed(["order_follow", "order_advance", "order_hold"][i]):
			Aliado.dar_orden(ORDENES[i])


func _retrato_de(nombre: String) -> Texture2D:
	var clave := nombre.to_lower()
	if not _retratos_escuadra.has(clave):
		var ruta := "res://assets/ui/retratos/retrato_%s.png" % clave
		_retratos_escuadra[clave] = load(ruta) if ResourceLoader.exists(ruta) else Estilo.RETRATO_PROVISIONAL
	return _retratos_escuadra[clave]


func _draw_escuadra(r: Rect2) -> void:
	var aliados: Array[Aliado] = []
	for n in get_tree().current_scene.get_children():
		if n is Aliado:
			aliados.append(n)
	# Las tres órdenes van lado a lado, a todo el alto de la barra (antes eran
	# tres franjas finitas). En pantallas angostas los retratos se recortan
	# para que cada botón tenga al menos ~24 px de ancho.
	var paso := 42.0
	if r.size.x - 3 * paso < 3 * 32:
		paso = maxf(26.0, floorf((r.size.x - 3 * 24) / 3.0))
	for i in 3:
		var col := Rect2(r.position.x + i * paso, r.position.y, paso - 1, r.size.y)
		Estilo.marco(self, col, "chapa")
		if i >= aliados.size():
			continue
		var a := aliados[i]
		_nombre_angosto(a.nombre, col.position.x + col.size.x / 2, col.position.y + 9,
			Estilo.ROJO if a.dead else Estilo.CREMA, col.size.x - 6)
		var face := Rect2(col.position + Vector2(1, 11), Vector2(col.size.x - 2, 35))
		Estilo.marco(self, face, "hundido")
		var hp := clampf(a.health / a.max_health, 0.0, 1.0)
		var tinte := Color.WHITE.lerp(Color(1.0, 0.35, 0.3), (1.0 - hp) * 0.9)
		if a.dead:
			tinte = Color(0.35, 0.35, 0.35)
		var tex := _retrato_de(a.nombre)
		var ancho := minf(tex.get_width(), face.size.x - 2)
		var fuente := Rect2((tex.get_width() - ancho) / 2.0, 0, ancho, tex.get_height())
		draw_texture_rect_region(tex, Rect2(face.position + Vector2(1, 1), fuente.size), fuente, tinte)
		if a.dead:   # una cruz roja sobre el retrato
			var c := face.get_center()
			draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), Estilo.ROJO, 2.0)
			draw_line(c + Vector2(8, -8), c + Vector2(-8, 8), Estilo.ROJO, 2.0)
		elif a.moviendo:
			_flecha(face.position + Vector2(face.size.x - 7, face.size.y - 6))
	# Órdenes: » síganme, → avancen, ‖ alto
	_orden_rects.clear()
	var x0 := r.position.x + 3 * paso
	var ancho_b := floorf((r.end.x - x0) / 3.0)
	for i in 3:
		var b := Rect2(x0 + i * ancho_b, r.position.y, ancho_b - 1, r.size.y)
		_orden_rects.append(b)
		var activa: bool = Aliado.orden == ORDENES[i]
		Estilo.marco(self, b, "hundido" if activa else "chapa")
		if activa:
			draw_rect(b.grow(-3), Estilo.AMBAR, false, 1.0)
		var c := b.get_center().floor() + Vector2(0.5, 0.5)
		var col := Estilo.AMBAR_CLARO if activa else Estilo.OLIVA_5
		var k := clampf((b.size.x - 8.0) / 20.0, 0.6, 1.0)   # dibujo más chico si el botón es angosto
		var g := 2.0 if k > 0.8 else 1.0
		match i:
			0:
				for dx in [-5, 3]:
					draw_polyline([c + Vector2(dx - 3, -6) * k, c + Vector2(dx + 3, 0) * k, c + Vector2(dx - 3, 6) * k], col, g)
			1:
				draw_line(c + Vector2(-8, 0) * k, c + Vector2(7, 0) * k, col, g)
				draw_polyline([c + Vector2(1, -6) * k, c + Vector2(7, 0) * k, c + Vector2(1, 6) * k], col, g)
			2:
				draw_rect(Rect2(c + Vector2(-5, -6) * k, Vector2(3, 13) * k), col)
				draw_rect(Rect2(c + Vector2(2, -6) * k, Vector2(3, 13) * k), col)


## Nombre centrado; si no cabe, junta las letras un píxel (y si aun así no
## cabe, lo corta).
func _nombre_angosto(t: String, cx: float, y: float, col: Color, ancho: float) -> void:
	if Estilo.ancho_texto(t) <= ancho:
		Estilo.texto_c(self, t, cx, y, col)
		return
	var paso := 5.0
	if t.length() * paso - 1.0 > ancho:   # ni así cabe: se corta (DELUCA → DELU)
		t = t.substr(0, int((ancho + 1.0) / paso))
	var x := floorf(cx - (t.length() * paso - 1.0) / 2.0)
	for ch in t:
		Estilo.texto(self, ch, Vector2(x, y), col)
		x += paso


## Flechita ámbar: el compañero va corriendo a otra posición.
func _flecha(c: Vector2) -> void:
	draw_rect(Rect2(c + Vector2(-3, -1), Vector2(5, 2)), Estilo.NEGRO)
	draw_polyline([c + Vector2(-3, 0), c + Vector2(2, 0)], Estilo.AMBAR_CLARO, 1.0)
	draw_polyline([c + Vector2(0, -2), c + Vector2(2, 0), c + Vector2(0, 2)], Estilo.AMBAR_CLARO, 1.0)


func _draw_portrait(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	Estilo.texto_c(self, SOLDIER_NAME, r.position.x + r.size.x / 2, r.position.y + 9, Estilo.CREMA)
	var hp := clampf(_player.health / _player.max_health, 0.0, 1.0)
	# Retrato: se tiñe de rojo con el daño y queda gris al morir
	var face := Rect2(r.position + Vector2(4, 11), Vector2(40, 35))
	Estilo.marco(self, face, "hundido")
	var tex := _retrato
	var herido := hp < 0.5 and _retrato_herido != null
	if herido:
		tex = _retrato_herido
	# Con retrato herido el tinte es leve; sin él, la cara se pone roja
	var tinte := Color.WHITE.lerp(Color(1.0, 0.35, 0.3), (1.0 - hp) * (0.35 if herido else 0.9))
	if _player.dead:
		tinte = Color(0.45, 0.45, 0.45)
	draw_texture(tex, face.position + Vector2(1, 1), tinte)
	if _player.crouching:
		Estilo.icono(self, Estilo.ICONO_AGACHADO, face.position + Vector2(7, face.size.y - 6))
	# Vida: barra vertical de LEDs al lado del retrato
	var bar := Rect2(r.position + Vector2(46, 11), Vector2(9, 35))
	Estilo.marco(self, bar, "hundido")
	var segs := 10
	var col_on := Estilo.VERDE_LED if hp > 0.35 else Estilo.ROJO
	for i in segs:
		var filled := float(i) < hp * segs
		var y := bar.end.y - 3 - (i + 1) * 3
		draw_rect(Rect2(bar.position.x + 2, y + 1, bar.size.x - 4, 2),
			col_on if filled else Color(Estilo.OLIVA_2, 1.0))


func _draw_status(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	# Clima
	Estilo.icono(self, Estilo.ICONO_NIEBLA, r.position + Vector2(14, 8))
	Estilo.texto(self, "NIEBLA", r.position + Vector2(24, 12), Estilo.CREMA)
	# Hora
	var clock := Rect2(r.position + Vector2(5, 15), Vector2(r.size.x - 10, 15))
	Estilo.marco(self, clock, "hundido")
	var t := Game.clock_text()
	var tw := t.length() * 9   # 9 px por dígito mediano
	Estilo.numero(self, t, Vector2(roundf(clock.position.x + (clock.size.x - tw) / 2.0), clock.position.y + 1),
		Estilo.DIG_MEDIANO)
	# Brújula (norte = el mar, como en la playa de Omaha)
	var comp := Rect2(r.position + Vector2(5, 31), Vector2(r.size.x - 10, 13))
	Estilo.marco(self, comp, "hundido")
	var fwd := -_player.global_basis.z
	var bearing := fmod(rad_to_deg(atan2(-fwd.x, fwd.z)) + 360.0, 360.0)
	var names := ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
	var mid := roundf(comp.position.x + comp.size.x / 2)
	for i in 16:
		var deg := i * 22.5
		var diff := wrapf(deg - bearing, -180.0, 180.0)
		if absf(diff) > 60.0:
			continue
		var px := roundf(mid + diff / 60.0 * (comp.size.x / 2 - 7))
		if i % 2 == 0:
			var col := Estilo.CREMA if i != 0 else Estilo.AMBAR_CLARO
			Estilo.texto_c(self, names[i / 2], px, comp.position.y + 11, col)
		else:
			draw_line(Vector2(px, comp.position.y + 7), Vector2(px, comp.position.y + 10), Estilo.OLIVA_4, 1.0)
	draw_rect(Rect2(mid, comp.position.y + 1, 1, 3), Estilo.AMBAR)


func _draw_grenades(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	var n := _player.grenades
	var inner := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10))
	Estilo.marco(self, inner, "hundido")
	var dy := roundf(inner.position.y + (inner.size.y - Estilo.alto_numero()) / 2.0)
	Estilo.numero(self, str(n), Vector2(inner.position.x + 9, dy), Estilo.DIG_GRANDE, 1,
		Color.WHITE if n > 0 else Color(1, 1, 1, 0.0))
	Estilo.icono(self, Estilo.ICONO_GRANADA, inner.position + Vector2(39, inner.size.y / 2.0),
		Color.WHITE if n > 0 else Color(0.4, 0.42, 0.38))
	if n > 0:
		draw_rect(Rect2(inner.position.x + 9, inner.end.y - 4, 13, 2), Estilo.AMBAR)


func _draw_ammo(r: Rect2) -> void:
	Estilo.marco(self, r, "chapa")
	var inner := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10))
	Estilo.marco(self, inner, "hundido")
	var w := _player.weapons
	var mag := w.ammo[w.current]
	var res := w.reserve[w.current]
	# 2 dígitos de cargador | 3 de reserva, centrados
	var ancho := 13 * 5 + 9
	var x := roundf(inner.position.x + (inner.size.x - ancho) / 2.0)
	var y := inner.position.y + 3
	var rojo := Color(1.0, 0.45, 0.4)
	x += Estilo.numero(self, str(mag), Vector2(x, y), Estilo.DIG_GRANDE, 2, Color.WHITE if mag > 0 else rojo)
	draw_rect(Rect2(x + 3, y + 3, 2, Estilo.alto_numero() - 6), Estilo.AMBAR)
	x += 9
	Estilo.numero(self, str(res), Vector2(x, y), Estilo.DIG_GRANDE, 3,
		Color.WHITE if res > 0 else Color(1, 1, 1, 0.25))
	var by := inner.end.y - 11
	if w.is_reloading():
		if int(Time.get_ticks_msec() / 250) % 2 == 0:
			Estilo.texto_c(self, "RECARGANDO", inner.get_center().x, inner.end.y - 3, Estilo.CREMA)
	elif w.def().get("recarga", "") == "clip" and mag > 0:
		# Balas del clip del Garand
		for i in mag:
			draw_texture(Estilo.ICONO_BALA, Vector2(roundf(inner.get_center().x - mag * 2.5) + i * 5, by + 1))


func _draw_slots(r: Rect2) -> void:
	var w := _player.weapons
	_slot_rects.clear()
	var sw := floorf((r.size.x - 2) / 2.0)
	for i in 2:
		var sr := Rect2(r.position + Vector2(i * (sw + 2), 0), Vector2(sw, r.size.y))
		_slot_rects.append(sr)
		Estilo.marco(self, sr, "chapa")
		var inner := Rect2(sr.position + Vector2(5, 5), sr.size - Vector2(10, 10))
		Estilo.marco(self, inner, "hundido")
		var selected := i == w.current
		Estilo.texto(self, str(i + 1), inner.position + Vector2(3, 10),
			Estilo.AMBAR if selected else Estilo.OLIVA_4)
		var tex := Armas.imagen("perfil_" + w.slots[i])
		var tinte := Color.WHITE if selected else Color(0.45, 0.5, 0.42)
		if tex:
			Estilo.icono(self, tex, inner.get_center() + Vector2(1, 1), tinte)
		else:   # sin foto todavía: el nombre del arma
			var nombre: String = Armas.datos(w.slots[i])["name"]
			Estilo.texto_c(self, nombre.split(" ")[0], inner.get_center().x + 3, inner.get_center().y + 4,
				Estilo.CREMA if selected else Estilo.OLIVA_4)
		if selected:
			draw_rect(Rect2(inner.position.x + 3, inner.end.y - 4, inner.size.x - 6, 2), Estilo.AMBAR)
