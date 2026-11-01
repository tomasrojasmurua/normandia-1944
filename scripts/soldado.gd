extends Node3D
class_name Soldado
## Cuerpo de un soldado (alemán o americano): modelo articulado hecho de
## piezas simples con texturas pixeladas (assets/soldados), con su equipo y su
## arma. No piensa: enemy.gd / aliado.gd le dicen qué pose tomar.
##
## Poses: "reposo" (arma baja), "pie" (de pie apuntando), "rodilla" (rodilla en
## tierra apuntando), "agachado" (escondido tras una cobertura).
## Las manos se ponen solas sobre el arma (cinemática inversa de dos huesos).

@export var bando := "aleman"      # "aleman" o "aliado"
@export var arma := "kar98k"
@export var cara := 1              # 1..3

var pose := "reposo"
var apuntar_a := Vector3.ZERO      # punto al que mira (global); ZERO = al frente
var muerto := false

# Partes (nodos que se mueven)
var cadera: Node3D
var torso: Node3D
var cabeza: Node3D
var casco: Node3D
var nodo_arma: Node3D
var boca: Node3D                   # punta del cañón (fogonazo y trazadoras)
var _hombro := [null, null]        # derecho, izquierdo
var _codo := [null, null]
var _mano := [null, null]
var _muslo := [null, null]
var _rodilla := [null, null]
var _fogonazo: Node3D

# Marcas del arma (en el espacio del arma): culata, mano izquierda
var _culata := Vector3(0, 0, 0.32)
var _guardamanos := Vector3(0, -0.02, -0.38)
var _es_pistola := false

var _t := randf() * 10.0
var _retroceso := 0.0
var _sacudon := Vector3.ZERO
var _altura := 0.95                # altura actual de la cadera (se suaviza)

const MUSLO := 0.45
const PIERNA := 0.45
const BRAZO := 0.29
const ANTEBRAZO := 0.28

static var _mats := {}


static func _mat(nombre: String, metros: float, tinte := Color.WHITE) -> StandardMaterial3D:
	var clave := "%s_%s_%s" % [nombre, metros, tinte]
	if _mats.has(clave):
		return _mats[clave]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/soldados/%s.png" % nombre)
	m.albedo_color = tinte
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / metros
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mats[clave] = m
	return m


func _ready() -> void:
	_construir()


# ================================================================ animación

func _process(delta: float) -> void:
	if muerto:
		return
	_t += delta
	_retroceso = move_toward(_retroceso, 0.0, delta * 6.0)
	_sacudon = _sacudon.move_toward(Vector3.ZERO, delta * 3.0)

	# Altura de la cadera y piernas según la pose
	var alto: float = {"reposo": 0.95, "pie": 0.95, "rodilla": 0.5, "agachado": 0.33}[pose]
	_altura = move_toward(_altura, alto, delta * 2.2)
	cadera.position.y = _altura + sin(_t * 1.6) * 0.004
	_piernas()

	# Torso: inclinación hacia el blanco + respiración + retroceso + sacudón por impacto
	var pitch := 0.0
	if apuntar_a != Vector3.ZERO and pose != "agachado" and pose != "reposo":
		var d := apuntar_a - torso.global_position
		var horiz := Vector2(d.x, d.z).length()
		pitch = clampf(atan2(d.y, horiz), -0.5, 0.5)
	var encorvado := 0.75 if pose == "agachado" else (0.08 if pose == "rodilla" else 0.0)
	torso.rotation = Vector3(-encorvado + pitch * 0.6 + sin(_t * 1.6) * 0.01 - _retroceso * 0.12,
		sin(_t * 0.7) * 0.02, 0) + _sacudon
	cabeza.rotation = Vector3(pitch * 0.4 + (-0.25 if pose == "agachado" else 0.0)
		- (0.12 if pose in ["pie", "rodilla"] else 0.0), 0, 0.12 if pose in ["pie", "rodilla"] else 0.0)

	# Arma: al hombro apuntando, o baja en reposo/agachado
	var hombro_d := Vector3(0.11, 0.42, -0.06)
	var objetivo_pos: Vector3
	var objetivo_rot: Vector3
	if _es_pistola:
		objetivo_pos = Vector3(0.02, 0.38, -0.5)
		objetivo_rot = Vector3(0, 0, 0)
	else:
		objetivo_pos = hombro_d - _culata
		objetivo_rot = Vector3.ZERO
	if pose == "reposo" or pose == "agachado":
		objetivo_pos = Vector3(0.06, 0.22, -0.22) - Vector3(0, 0, _culata.z * 0.3)
		objetivo_rot = Vector3(deg_to_rad(-35), deg_to_rad(25), deg_to_rad(-20))
		if pose == "agachado":
			objetivo_rot = Vector3(deg_to_rad(55), deg_to_rad(20), deg_to_rad(-10))  # cañón hacia arriba
	nodo_arma.position = nodo_arma.position.lerp(objetivo_pos + Vector3(0, 0, _retroceso * 0.06), minf(delta * 8.0, 1.0))
	nodo_arma.rotation = nodo_arma.rotation.lerp(objetivo_rot + Vector3(_retroceso * 0.25, 0, 0), minf(delta * 8.0, 1.0))

	# Manos al arma
	var grip := nodo_arma.global_transform * Vector3(0, -0.06, 0.04)
	var guard := nodo_arma.global_transform * _guardamanos
	_brazo(0, grip, 1.0)
	_brazo(1, guard, -1.0)


func _piernas() -> void:
	var a: Array   # [muslo der, rodilla der, muslo izq, rodilla izq] en grados
	match pose:
		"rodilla":
			a = [-10.0, -80.0, 80.0, -80.0]     # derecha en el suelo, izquierda adelante
		"agachado":
			a = [100.0, -150.0, 95.0, -145.0]   # en cuclillas
		_:
			a = [0.0, 0.0, 0.0, 0.0]
			if pose == "pie":
				a = [8.0, -6.0, -6.0, -2.0]    # piernas un poco abiertas, firme
	for i in 2:
		_muslo[i].rotation.x = lerp_angle(_muslo[i].rotation.x, deg_to_rad(a[i * 2]), 0.2)
		_rodilla[i].rotation.x = lerp_angle(_rodilla[i].rotation.x, deg_to_rad(a[i * 2 + 1]), 0.2)


## Cinemática inversa de dos huesos: lleva la mano "i" a "destino" (global).
func _brazo(i: int, destino: Vector3, lado: float) -> void:
	var h: Node3D = _hombro[i]
	var c: Node3D = _codo[i]
	var s := h.global_position
	var to := destino - s
	var d := clampf(to.length(), 0.05, BRAZO + ANTEBRAZO - 0.005)
	var dir := to.normalized()
	var polo := torso.global_basis * Vector3(lado * 0.8, -1.0, 0.25)
	var n := (polo - dir * polo.dot(dir)).normalized()
	var cos_a := clampf((BRAZO * BRAZO + d * d - ANTEBRAZO * ANTEBRAZO) / (2.0 * BRAZO * d), -1.0, 1.0)
	var codo := s + dir * cos_a * BRAZO + n * sqrt(1.0 - cos_a * cos_a) * BRAZO
	_orientar(h, s, codo, polo)
	_orientar(c, codo, s + dir * d, polo)


## Gira "nodo" para que su eje -Y apunte de "desde" a "hacia".
static func _orientar(nodo: Node3D, desde: Vector3, hacia: Vector3, polo: Vector3) -> void:
	var y := -(hacia - desde).normalized()
	var x := y.cross(polo).normalized()
	if x.length() < 0.01:
		x = y.cross(Vector3.FORWARD).normalized()
	var z := x.cross(y)
	nodo.global_basis = Basis(x, y, z)


## Retroceso y fogonazo al disparar.
func disparo() -> void:
	_retroceso = 1.0
	_fogonazo.visible = true
	_fogonazo.rotation.z = randf() * TAU
	get_tree().create_timer(0.05).timeout.connect(func() -> void:
		if is_instance_valid(_fogonazo): _fogonazo.visible = false)


## Sacudón al recibir un balazo (dir = dirección de la bala, global).
func impacto(dir: Vector3) -> void:
	var local := global_basis.inverse() * dir
	_sacudon = Vector3(clampf(-local.z, -1, 1) * 0.25, randf_range(-0.2, 0.2), clampf(local.x, -1, 1) * 0.3)


## Muere: suelta el arma y cae. Si fue en la cabeza, el casco sale volando.
func morir(dir: Vector3, cabeza_tiro: bool) -> void:
	muerto = true
	nodo_arma.visible = false
	_fogonazo.visible = false
	var local := global_basis.inverse() * dir
	var hacia_atras := local.z < 0.0   # la bala venía de frente: cae de espaldas
	var estilo := randi() % 3
	var tw := create_tween().set_parallel(true)
	# Brazos sueltos
	for i in 2:
		tw.tween_property(_hombro[i], "rotation", Vector3(randf_range(-0.6, 0.6), 0, (1 - i * 2) * randf_range(0.3, 1.2)), 0.5)
		tw.tween_property(_codo[i], "rotation", Vector3(randf_range(0.1, 0.8), 0, 0), 0.5)
	var raiz := get_child(0) as Node3D
	match estilo:
		0:  # cae recto hacia atrás (o adelante)
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(raiz, "rotation:x", (-PI / 2 if hacia_atras else PI / 2) * 0.97, 0.55)
			tw.tween_property(raiz, "position:y", 0.12, 0.55)
		1:  # se dobla de rodillas y se va de bruces
			tw.tween_property(cadera, "position:y", 0.45, 0.35)
			for i in 2:
				tw.tween_property(_muslo[i], "rotation:x", deg_to_rad(-15), 0.35)
				tw.tween_property(_rodilla[i], "rotation:x", deg_to_rad(-100), 0.35)
			tw.chain().tween_property(raiz, "rotation:x", PI / 2 * 0.95, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(raiz, "position:y", 0.1, 0.45)
		_:  # gira y cae de lado
			tw.tween_property(raiz, "rotation", Vector3(0, randf_range(-1.2, 1.2), (1 if local.x > 0 else -1) * PI / 2 * 0.95), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(raiz, "position:y", 0.14, 0.6)
	if cabeza_tiro:
		_soltar_casco(dir)


func _soltar_casco(dir: Vector3) -> void:
	var g := casco.global_transform
	casco.get_parent().remove_child(casco)
	get_tree().current_scene.add_child(casco)
	casco.global_transform = g
	var suelo := Vector3(g.origin.x, 0.07, g.origin.z) + Vector3(dir.x, 0, dir.z).normalized() * randf_range(0.8, 1.6)
	var tw := casco.create_tween().set_parallel(true)
	tw.tween_property(casco, "global_position", suelo, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(casco, "rotation", Vector3(PI * randf_range(0.6, 1.0), randf() * TAU, randf_range(-0.5, 0.5)), 0.6)


## Posición de la cabeza (para el disparo a la cabeza y la línea de vista).
func pos_cabeza() -> Vector3:
	return cabeza.global_position + cabeza.global_basis.y * 0.1


# ================================================================ modelo

func _construir() -> void:
	var aleman := bando == "aleman"
	var chaqueta := _mat("tela_feldgrau", 0.5) if aleman else _mat("tela_m41", 0.5)
	var pantalon := _mat("tela_gris", 0.5) if aleman else _mat("tela_hbt", 0.5)
	var cuero := _mat("cuero", 0.3)
	var correaje := cuero if aleman else _mat("lona", 0.3)
	var piel := Game.material(Color(0.76, 0.56, 0.44))
	var raiz := Node3D.new()
	add_child(raiz)

	cadera = _nodo(raiz, Vector3(0, 0.95, 0))
	_caja(cadera, Vector3(0.34, 0.2, 0.22), Vector3(0, -0.04, 0), pantalon)
	if aleman:   # faldón de la guerrera bajo el cinturón
		_caja(cadera, Vector3(0.38, 0.16, 0.25), Vector3(0, 0.0, 0), chaqueta)

	# Piernas
	for i in 2:
		var lado := 1.0 if i == 0 else -1.0
		_muslo[i] = _nodo(cadera, Vector3(lado * 0.1, -0.08, 0))
		_capsula(_muslo[i], MUSLO + 0.06, 0.085, pantalon)
		_rodilla[i] = _nodo(_muslo[i], Vector3(0, -MUSLO, 0))
		if aleman:   # botas altas de cuero hasta la rodilla
			_capsula(_rodilla[i], PIERNA + 0.04, 0.072, cuero)
		else:        # polainas de lona y botas cafés
			_capsula(_rodilla[i], PIERNA * 0.55, 0.068, pantalon)
			var polaina := _nodo(_rodilla[i], Vector3(0, -PIERNA * 0.45, 0))
			_capsula(polaina, PIERNA * 0.5, 0.072, _mat("lona", 0.3))
		_caja(_rodilla[i], Vector3(0.1, 0.08, 0.24), Vector3(0, -PIERNA + 0.02, -0.05),
			cuero if aleman else _mat("cuero", 0.3, Color(1.6, 1.15, 0.8)))

	# Torso
	torso = _nodo(cadera, Vector3(0, 0.04, 0))
	_caja(torso, Vector3(0.36, 0.22, 0.22), Vector3(0, 0.1, 0), chaqueta)        # cintura
	_caja(torso, Vector3(0.42, 0.3, 0.25), Vector3(0, 0.33, 0), chaqueta)        # pecho
	_caja(torso, Vector3(0.36, 0.06, 0.2), Vector3(0, 0.49, 0), chaqueta)        # hombros
	_caja(torso, Vector3(0.4, 0.05, 0.25), Vector3(0, 0.0, 0), correaje)         # cinturón
	if aleman:
		for lado in [-1.0, 1.0]:
			for k in 3:   # cartucheras de cuero (3 por lado)
				_caja(torso, Vector3(0.055, 0.07, 0.045), Vector3(lado * (0.05 + k * 0.055), 0.04, -0.14), cuero)
			# tirantes en Y
			_caja(torso, Vector3(0.035, 0.42, 0.02), Vector3(lado * 0.1, 0.25, -0.13), cuero, Vector3(0, 0, lado * 8))
		_caja(torso, Vector3(0.035, 0.42, 0.02), Vector3(0, 0.25, 0.13), cuero)            # tirante de atrás
		_caja(torso, Vector3(0.12, 0.13, 0.08), Vector3(0.21, -0.03, 0.05), _mat("tela_gris", 0.3, Color(0.85, 0.9, 0.75)))  # morral de pan
		_cilindro(torso, 0.045, 0.14, Vector3(0.2, -0.02, 0.15), _mat("tela_feldgrau", 0.2, Color(0.6, 0.55, 0.45)))  # cantimplora
		var bote := _cilindro(torso, 0.055, 0.26, Vector3(-0.05, 0.12, 0.17), _mat("tela_gris", 0.15, Color(0.9, 1.0, 0.85)))   # caja de la máscara antigás
		bote.rotation_degrees = Vector3(0, 0, 70)
		_caja(torso, Vector3(0.06, 0.18, 0.03), Vector3(-0.2, -0.04, 0.08), cuero)    # pala
	else:
		for lado in [-1.0, 1.0]:
			for k in 4:   # cartucheras de lona del cinturón M1923
				_caja(torso, Vector3(0.06, 0.08, 0.045), Vector3(lado * (0.04 + k * 0.05), 0.02, -0.14), correaje)
			_caja(torso, Vector3(0.04, 0.44, 0.02), Vector3(lado * 0.1, 0.26, -0.13), correaje, Vector3(0, 0, lado * 6))  # tirantes
		_caja(torso, Vector3(0.28, 0.22, 0.1), Vector3(0, 0.3, 0.17), correaje)     # mochila
		_caja(torso, Vector3(0.07, 0.24, 0.03), Vector3(0.0, 0.2, 0.235), _mat("cuero", 0.2, Color(1.3, 1.3, 1.1)))  # pala en la mochila
		_cilindro(torso, 0.045, 0.14, Vector3(-0.2, -0.04, 0.08), correaje)          # cantimplora

	# Cabeza y casco
	_cilindro(torso, 0.055, 0.1, Vector3(0, 0.55, 0), piel)                         # cuello
	cabeza = _nodo(torso, Vector3(0, 0.58, 0))
	_caja(cabeza, Vector3(0.17, 0.21, 0.19), Vector3(0, 0.11, 0), piel)
	var frente := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.17, 0.17)
	frente.mesh = quad
	var mcara := StandardMaterial3D.new()
	mcara.albedo_texture = load("res://assets/soldados/cara_%d.png" % clampi(cara, 1, 3))
	mcara.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mcara.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	frente.material_override = mcara
	frente.position = Vector3(0, 0.1, -0.096)
	frente.rotation.y = PI
	cabeza.add_child(frente)
	casco = _nodo(cabeza, Vector3(0, 0.16, 0.01))
	if aleman:   # Stahlhelm M35: cúpula y faldón acampanado
		var mc := _mat("casco_aleman", 0.25)
		_esfera(casco, 0.135, 0.13, Vector3(0, 0.0, 0), mc)
		var faldon := _cono(casco, 0.135, 0.165, 0.07, Vector3(0, -0.04, 0.015), mc)
		faldon.scale = Vector3(1.0, 1.0, 1.08)
	else:        # M1 con red
		var mc := _mat("casco_us", 0.12)
		_esfera(casco, 0.15, 0.15, Vector3(0, -0.01, 0), mc)
		_cono(casco, 0.15, 0.165, 0.02, Vector3(0, -0.02, 0), mc)
		_caja(casco, Vector3(0.012, 0.12, 0.012), Vector3(0.12, -0.08, 0), correaje)   # barboquejo suelto
		_caja(casco, Vector3(0.012, 0.12, 0.012), Vector3(-0.12, -0.08, 0), correaje)

	# Brazos
	for i in 2:
		var lado := 1.0 if i == 0 else -1.0
		_hombro[i] = _nodo(torso, Vector3(lado * 0.21, 0.45, 0))
		_capsula(_hombro[i], BRAZO + 0.06, 0.06, chaqueta)
		_codo[i] = _nodo(_hombro[i], Vector3(0, -BRAZO, 0))
		_capsula(_codo[i], ANTEBRAZO + 0.04, 0.05, chaqueta)
		_mano[i] = _caja(_codo[i], Vector3(0.07, 0.09, 0.05), Vector3(0, -ANTEBRAZO - 0.03, 0), piel)

	# Arma
	nodo_arma = _nodo(torso, Vector3(0.1, 0.3, -0.3))
	_modelo_arma()


func _modelo_arma() -> void:
	var d := Armas.datos(arma)
	var tipo: String = d["tipo"]
	var madera := Game.material(Color(0.42, 0.25, 0.13))
	var metal := Game.material(Color(0.17, 0.17, 0.18))
	var oliva := Game.material(Color(0.32, 0.34, 0.22))
	var con_madera: bool = arma in ["garand", "carbine", "thompson", "bar", "springfield", "kar98k", "stg44"]
	var n := nodo_arma
	var punta := -0.9
	_es_pistola = tipo == "pistola"
	match tipo:
		"pistola":
			_caja(n, Vector3(0.03, 0.035, 0.2), Vector3(0, 0, -0.06), metal)
			_caja(n, Vector3(0.03, 0.1, 0.04), Vector3(0, -0.06, 0.02), madera, Vector3(20, 0, 0))
			_culata = Vector3(0, 0, 0.05)
			_guardamanos = Vector3(-0.02, -0.06, 0.03)
			punta = -0.17
		"bazuca":
			_cilindro(n, 0.045, 1.4, Vector3(0, 0.05, -0.35), oliva).rotation_degrees = Vector3(90, 0, 0)
			_caja(n, Vector3(0.04, 0.1, 0.05), Vector3(0, -0.04, -0.15), madera)
			_culata = Vector3(0, 0.05, 0.1)
			_guardamanos = Vector3(0, -0.02, -0.45)
			punta = -1.05
		_:
			var largo := 1.0 if tipo == "fusil" else (0.7 if tipo == "subfusil" else 1.15)
			if arma == "carbine":
				largo = 0.85
			var cuerpo := madera if con_madera else metal
			_caja(n, Vector3(0.045, 0.11, 0.3), Vector3(0, -0.03, 0.18), cuerpo if arma != "mp40" else metal, Vector3(-6, 0, 0))   # culata
			_caja(n, Vector3(0.05, 0.06, largo * 0.4), Vector3(0, 0.0, -largo * 0.18), metal)                                      # cajón
			_caja(n, Vector3(0.045, 0.05, largo * 0.35), Vector3(0, -0.01, -largo * 0.5), cuerpo)                                  # guardamanos
			_caja(n, Vector3(0.022, 0.022, largo * 0.3), Vector3(0, 0.01, -largo * 0.75), metal)                                  # cañón
			if tipo != "fusil" or arma == "carbine":
				var alto := 0.22 if arma in ["thompson", "mp40", "stg44"] else 0.15
				_caja(n, Vector3(0.03, alto, 0.05), Vector3(0, -alto / 2.0 - 0.02, -largo * 0.22), metal, Vector3(-15 if arma == "stg44" else 0, 0, 0))
			if arma == "springfield":
				_cilindro(n, 0.02, 0.3, Vector3(0, 0.06, -0.15), metal).rotation_degrees = Vector3(90, 0, 0)
			if arma == "mg42":
				_caja(n, Vector3(0.06, 0.06, 0.4), Vector3(0, 0.0, -0.75), metal)
			_culata = Vector3(0, -0.02, 0.32)
			_guardamanos = Vector3(0, -0.04, -largo * 0.45)
			punta = -largo * 0.92
	boca = _nodo(n, Vector3(0, 0.01, punta))
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.4)
	_fogonazo = Game.box(boca, Vector3(0.14, 0.14, 0.22), Vector3(0, 0, -0.1), fmat, Vector3(0, 0, 45))
	_fogonazo.visible = false


# --- piezas
func _nodo(padre: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	padre.add_child(n)
	return n


func _caja(padre: Node3D, tam: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return Game.box(padre, tam, pos, mat, rot)


## Cápsula que cuelga hacia abajo desde el nodo (para brazos y piernas).
func _capsula(padre: Node3D, largo: float, radio: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radio
	c.height = maxf(largo, radio * 2.0)
	c.radial_segments = 8
	c.rings = 2
	m.mesh = c
	m.material_override = mat
	m.position = Vector3(0, -largo / 2.0 + radio * 0.5, 0)
	padre.add_child(m)
	return m


func _cilindro(padre: Node3D, radio: float, alto: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	return _cono(padre, radio, radio, alto, pos, mat)


func _cono(padre: Node3D, arriba: float, abajo: float, alto: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = arriba
	c.bottom_radius = abajo
	c.height = alto
	c.radial_segments = 10
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	m.position = pos
	padre.add_child(m)
	return m


func _esfera(padre: Node3D, radio: float, alto: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var e := SphereMesh.new()
	e.radius = radio
	e.height = alto
	e.is_hemisphere = true
	e.radial_segments = 10
	e.rings = 4
	m.mesh = e
	m.material_override = mat
	m.position = pos
	padre.add_child(m)
	return m
