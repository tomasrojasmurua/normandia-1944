extends Node3D
class_name Soldado
## Cuerpo 3D de un soldado con su arma. No piensa: enemy.gd / aliado.gd (y en
## el cooperativo, la red) le dicen qué pose tomar.
## Desde v0.12 el juego usa soldado_sprite.gd (sprites sacados de este modelo
## con tools/sprites/hornear.gd, mucho más livianos); este queda para hornear
## los sprites y como opción "SOLDADOS: 3D" en la pausa, para comparar.
##
## Modelo esculpido con IA (Meshy) con esqueleto y animaciones de Mixamo:
##   assets/soldados/aleman/     (bando "aleman")
##   assets/soldados/americano/  (cualquier otro bando)
## Cada carpeta tiene los FBX de Mixamo (rifle_idle.fbx trae el esqueleto),
## cuerpo.res (malla liviana, ver tools/modelos/piel.gd) y textura.png.
## El arma 3D (Armas.modelo_3d) se coloca sola entre las dos manos.
##
## Poses: "reposo" (arma baja), "pie" (de pie apuntando), "rodilla" (rodilla en
## tierra apuntando), "agachado" (escondido tras una cobertura).
## "andar" (opcional) pone una animación de movimiento encima de la pose:
## "camina", "corre", "atras", "izquierda", "derecha", "agachado".

@export var bando := "aleman"      # "aleman" o "aliado"
@export var arma := "kar98k"

var pose := "reposo"
var andar := ""
var apuntar_a := Vector3.ZERO      # punto al que mira (global); ZERO = al frente
var muerto := false

var nodo_arma: Node3D
var boca: Node3D                   # punta del cañón (fogonazo y trazadoras)
var _fogonazo: Node3D

# Marcas del arma (en el espacio del arma): mano derecha, culata, mano izquierda
var _agarre := Vector3.ZERO
var _guardamanos := Vector3(0, 0, -0.4)
var _es_pistola := false

const ESCALA := 100.0              # Mixamo exporta en centímetros
## nombre interno: [archivo FBX, se repite]. Las que falten se saltan.
const ANIMS := {
	"reposo": ["rifle_idle", true],
	"apunta": ["rifle_aiming_idle", true],
	"dispara": ["firing_rifle", false],
	"rodilla": ["rifle_kneel_idle", true],
	"camina": ["rifle_walk", true],
	"corre": ["rifle_run", true],
	"atras": ["rifle_walk_back", true],
	"izquierda": ["rifle_walk_left", true],
	"derecha": ["rifle_walk_right", true],
	"agachado": ["rifle_crouch_walk", true],
	"muere_atras": ["rifle_death_1", false],
	"muere_golpe": ["rifle_hit_to_back", false],
	"muere_rodilla": ["rifle_kneel_hit_to_back", false],
	"muere_corriendo": ["rifle_run_to_dying", false],
}

## Por carpeta: {"lib": AnimationLibrary, "mat": material, "malla": Mesh}
static var _recursos := {}

var _dir := ""
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _b_cabeza := -1
var _b_spine := [-1, -1, -1]
var _b_mano := [-1, -1]
var _b_indice := [-1, -1]
var _anim := ""
var _t := randf() * 10.0
var _retroceso := 0.0
var _sacudon := Vector3.ZERO
var _encorvado := 0.0
var _pitch := 0.0
var _acumulado := randf() * 0.06


## Las animaciones de Mixamo para caminar y correr avanzan solas (la cadera se
## va 2,5 m hacia adelante en cada zancada de correr y vuelve de golpe al
## repetirse). El que mueve al soldado es el juego, así que se quita ese
## avance: si no, el cuerpo se adelanta y salta para atrás en cada vuelta.
static func _quitar_avance(an: Animation) -> void:
	for i in an.get_track_count():
		if an.track_get_type(i) != Animation.TYPE_POSITION_3D or not str(an.track_get_path(i)).ends_with("Hips"):
			continue
		var n := an.track_get_key_count(i)
		if n < 2:
			continue
		var ini: Vector3 = an.track_get_key_value(i, 0)
		var deriva: Vector3 = an.track_get_key_value(i, n - 1) - ini
		deriva.y = 0.0
		var t_fin := an.track_get_key_time(i, n - 1)
		for k in n:
			var v: Vector3 = an.track_get_key_value(i, k)
			an.track_set_key_value(i, k, v - deriva * (an.track_get_key_time(i, k) / t_fin))


static func _cargar(dir: String) -> Dictionary:
	if not _recursos.has(dir):
		var lib := AnimationLibrary.new()
		for nombre in ANIMS:
			var path: String = dir + ANIMS[nombre][0] + ".fbx"
			if not ResourceLoader.exists(path):
				continue
			var fuente: Node = load(path).instantiate()
			var ap: AnimationPlayer = fuente.find_children("*", "AnimationPlayer", true, false)[0]
			var an: Animation = ap.get_animation("mixamo_com").duplicate()
			an.loop_mode = Animation.LOOP_LINEAR if ANIMS[nombre][1] else Animation.LOOP_NONE
			if ANIMS[nombre][1]:
				_quitar_avance(an)
			lib.add_animation(nombre, an)
			fuente.free()
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(dir + "textura.png")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.roughness = 1.0
		_recursos[dir] = {"lib": lib, "mat": mat,
			"malla": load(dir + "cuerpo.res") if ResourceLoader.exists(dir + "cuerpo.res") else null}
	return _recursos[dir]


func _ready() -> void:
	_dir = "res://assets/soldados/%s/" % ("aleman" if bando == "aleman" else "americano")
	var r := _cargar(_dir)
	var modelo: Node3D = load(_dir + "rifle_idle.fbx").instantiate()
	modelo.scale = Vector3.ONE * ESCALA
	modelo.rotation.y = PI            # Mixamo mira a +Z; el juego, a -Z
	add_child(modelo)
	_sk = modelo.find_children("*", "Skeleton3D", true, false)[0]
	for mi: MeshInstance3D in modelo.find_children("*", "MeshInstance3D", true, false):
		if r["malla"]:
			mi.mesh = r["malla"]       # malla propia, más liviana y con mejor cara
		mi.material_override = r["mat"]
		mi.extra_cull_margin = 0.02
	_ap = modelo.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.add_animation_library("s", r["lib"])
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_b_cabeza = _sk.find_bone("mixamorig_Head")
	_b_spine = [_sk.find_bone("mixamorig_Spine"), _sk.find_bone("mixamorig_Spine1"), _sk.find_bone("mixamorig_Spine2")]
	_b_mano = [_sk.find_bone("mixamorig_RightHand"), _sk.find_bone("mixamorig_LeftHand")]
	_b_indice = [_sk.find_bone("mixamorig_RightHandIndex1"), _sk.find_bone("mixamorig_LeftHandIndex1")]
	nodo_arma = Node3D.new()
	add_child(nodo_arma)
	_modelo_arma()
	_poner_anim("reposo", 0.0)
	_ap.seek(randf() * _ap.current_animation_length, true)


func _modelo_arma() -> void:
	_es_pistola = Armas.datos(arma)["tipo"] == "pistola"
	var mi := Armas.modelo_3d(arma)
	nodo_arma.add_child(mi)
	_guardamanos = mi.mesh.get_meta("guardamanos")
	boca = Node3D.new()
	boca.position = mi.mesh.get_meta("boca")
	nodo_arma.add_child(boca)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.4)
	_fogonazo = Game.box(boca, Vector3(0.14, 0.14, 0.22), Vector3(0, 0, -0.1), fmat, Vector3(0, 0, 45))
	_fogonazo.visible = false


# ================================================================ lo que piden los demás

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


## Muere con una animación según la pose y de dónde vino la bala; suelta el arma.
func morir(dir: Vector3, _cabeza_tiro: bool) -> void:
	muerto = true
	nodo_arma.visible = false
	_fogonazo.visible = false
	var local := global_basis.inverse() * dir
	var nombre: String
	if pose == "rodilla" or pose == "agachado":
		nombre = "muere_rodilla"
	elif local.z < 0.0:     # la bala venía de frente
		nombre = ["muere_atras", "muere_golpe"][randi() % 2]
	else:
		nombre = "muere_corriendo"
	_poner_anim(nombre, 0.1)


## Posición de la cabeza (para el disparo a la cabeza y la línea de vista).
func pos_cabeza() -> Vector3:
	return _hueso_global(_b_cabeza) + Vector3(0, 0.08, 0)


# ================================================================ animación

func _process(delta: float) -> void:
	_t += delta
	# Deformar el modelo es lo caro, así que la pose de los soldados quietos
	# se actualiza pocas veces por segundo (15 de cerca, 8 de lejos, 3 fuera
	# de la vista), estilo animación retro. Cada soldado empieza desfasado
	# para repartir la carga.
	# Los que CORREN se actualizan en cada cuadro mientras se ven: en Godot el
	# cuerpo deformado solo cambia de lugar cuando se actualiza el esqueleto,
	# así que con menos cuadros avanzaba a saltos aunque el soldado se moviera
	# parejo (v0.11.2; medido cuadro a cuadro).
	_acumulado += delta
	var corre := andar != "" and not muerto
	var intervalo := 0.0 if corre else 1.0 / 15.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var centro := global_position + Vector3(0, 1.0, 0)
		if not cam.is_position_in_frustum(centro):
			intervalo = 1.0 / 3.0
		elif not corre and cam.global_position.distance_squared_to(centro) > 20.0 * 20.0:
			intervalo = 1.0 / 8.0
	if _acumulado < intervalo:
		return
	delta = _acumulado
	_acumulado = 0.0
	if muerto:
		_ap.advance(delta)
		if not _ap.is_playing():
			set_process(false)      # ya cayó: queda quieto para siempre
		return
	_retroceso = move_toward(_retroceso, 0.0, delta * 6.0)
	_sacudon = _sacudon.move_toward(Vector3.ZERO, delta * 3.0)
	if andar != "" and _ap.has_animation("s/" + andar):
		_poner_anim(andar)
	else:
		match pose:
			"pie":
				_poner_anim("apunta")
			"rodilla", "agachado":
				_poner_anim("rodilla")
			_:
				_poner_anim("reposo")
	_ap.advance(delta)

	# Inclinación: hacia el blanco al apuntar; encorvado tras la cobertura
	var pitch := 0.0
	if apuntar_a != Vector3.ZERO and (pose == "pie" or pose == "rodilla"):
		var d := apuntar_a - _hueso_global(_b_spine[2])
		pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.5)
	_pitch = lerpf(_pitch, pitch, minf(delta * 6.0, 1.0))
	_encorvado = move_toward(_encorvado, 0.5 if pose == "agachado" and andar == "" else 0.0, delta * 1.8)
	# Eje X del esqueleto: ángulo positivo = hacia adelante (el modelo mira a +Z).
	# Se leen las rotaciones de los padres antes de tocar huesos: así el
	# esqueleto se recalcula una sola vez por cuadro.
	var adelante := _encorvado - _pitch / 3.0 + _retroceso * -0.04 + _sacudon.x * 0.5
	var padres := []
	for b in _b_spine + [_b_cabeza]:
		padres.append(_sk.get_bone_global_pose(_sk.get_bone_parent(b)).basis.get_rotation_quaternion())
	for i in 3:
		var q := Quaternion(Vector3.RIGHT, adelante) * Quaternion(Vector3.FORWARD, _sacudon.z * 0.4)
		_girar_hueso(_b_spine[i], padres[i], q.get_axis(), q.get_angle())
	_girar_hueso(_b_cabeza, padres[3], Vector3.RIGHT, _encorvado * 0.6)

	_colocar_arma()


func _poner_anim(nombre: String, mezcla := 0.25) -> void:
	if _anim == nombre:
		return
	_anim = nombre
	_ap.play("s/" + nombre, mezcla)


func _hueso_global(b: int) -> Vector3:
	return _sk.global_transform * _sk.get_bone_global_pose(b).origin


## Gira un hueso alrededor de un eje dado en el espacio del esqueleto
## (q_padre: rotación global del padre, leída antes de tocar huesos).
func _girar_hueso(b: int, q_padre: Quaternion, eje: Vector3, angulo: float) -> void:
	if absf(angulo) < 0.0001:
		return
	var eje_local := (q_padre.inverse() * eje).normalized()
	_sk.set_bone_pose_rotation(b, Quaternion(eje_local, angulo) * _sk.get_bone_pose_rotation(b))


## Pone el arma entre las manos de la animación.
func _colocar_arma() -> void:
	var mano_d := (_hueso_global(_b_mano[0]) + _hueso_global(_b_indice[0])) * 0.5
	var mano_i := (_hueso_global(_b_mano[1]) + _hueso_global(_b_indice[1])) * 0.5
	var arriba := (_sk.global_transform.basis * _sk.get_bone_global_pose(_b_spine[2]).basis).y.normalized()
	var dir := (mano_i - mano_d)
	if _es_pistola or dir.length() < 0.15:
		dir = -global_basis.z
	var b := Basis.looking_at(dir.normalized(), arriba)
	if not _es_pistola:
		# corrige la pequeña diferencia entre la línea agarre→guardamanos y el cañón
		b = b * Basis(Quaternion((_guardamanos - _agarre).normalized(), Vector3.FORWARD))
	b = b.rotated(b.x, _retroceso * 0.15)
	nodo_arma.global_transform = Transform3D(b, mano_d - b * _agarre)
