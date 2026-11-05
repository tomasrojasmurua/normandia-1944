class_name Armas
## Catálogo de todas las armas del juego (Segunda Guerra Mundial).
## Para agregar un arma: copia una entrada, cambia sus números y deja sus
## imágenes en assets/armas/ con el mismo "id":
##   arma_<id>_cadera.png   en la mano, desde la cadera   (si falta: modelo 3D)
##   arma_<id>_mira.png     por la mira                    (opcional)
##   perfil_<id>.png        ícono del HUD                  (si falta: el nombre)
##   pieza_cargador_<id>.png  el cargador que entra al recargar (opcional)
##
## Campos de juego:
##   ranura    0 = arma principal (tecla 1), 1 = pistola (tecla 2)
##   mag/reserve  balas en el cargador / de reserva al recogerla nueva
##   damage    100 = derriba de un tiro en el cuerpo (cabeza = doble)
##   interval  segundos entre disparos   auto  true = dispara mientras se mantiene
##   reload    segundos de recarga        spread_hip / spread_ads  dispersión (grados)
##   recoil    grados que sube la vista   ads_fov  zoom al apuntar (menos = más zoom)
##   scope     mira telescópica (círculo negro al apuntar)
##   rocket    dispara un cohete que explota (bazuca)
##   tipo      forma del modelo 3D de respaldo: fusil, subfusil, ametralladora, pistola, bazuca
##
## Campos de imagen (píxeles de la imagen de cadera, 552x368; ver hud.gd):
##   vm_pos (dónde va la imagen), vm_boca (fogonazo), vm_mira (punto que va al
##   centro al apuntar sin imagen de mira), mira_pos / mira_poste (imagen de mira),
##   recarga_punto (dónde entra el cargador), expulsion (de dónde salen las vainas),
##   recarga  "clip" (Garand, entra por arriba) o "cargador" (entra por abajo)
##   vm_cadera  corrimiento de la imagen desde la cadera para que el cañón
##              apunte a la cruz (la boca queda ~16 px abajo a la derecha de
##              ella, sobre la línea del cañón)

const DATOS := {
	# ------------------------------------------------------------- aliadas
	"garand": {
		"name": "M1 GARAND", "ranura": 0, "bando": "aliado", "tipo": "fusil",
		"mag": 8, "reserve": 80, "damage": 100.0, "interval": 0.17, "auto": false,
		"reload": 2.3, "spread_hip": 1.2, "spread_ads": 0.15, "recoil": 2.6,
		"sound": "rifle", "pitch": 1.0, "ads_fov": 42.0,
		"hip": Vector3(0.16, -0.15, -0.26), "ads": Vector3(0, 0, -0.06),
		"vm_cadera": Vector2(-14, 36), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(251, 135), "vm_mira": Vector2(259, 119),
		"mira_pos": Vector2(-3, 34), "mira_poste": Vector2(323, 146),
		"recarga": "clip", "recarga_punto": Vector2(338, 170), "expulsion": Vector2(338, 168),
	},
	"colt": {
		"name": "COLT M1911", "ranura": 1, "bando": "aliado", "tipo": "pistola",
		"mag": 7, "reserve": 28, "damage": 45.0, "interval": 0.14, "auto": false,
		"reload": 1.6, "spread_hip": 1.5, "spread_ads": 0.5, "recoil": 2.0,
		"sound": "pistol", "pitch": 1.0, "ads_fov": 55.0,
		"hip": Vector3(0.1, -0.06, -0.22), "ads": Vector3(0, 0, -0.26),
		"vm_cadera": Vector2(-63, 17), "vm_pos": Vector2(70, 30), "vm_boca": Vector2(326, 142), "vm_mira": Vector2(334, 136),
		"mira_pos": Vector2(-3, 33), "mira_poste": Vector2(323, 147),
		"recarga": "cargador", "recarga_punto": Vector2(409, 350), "expulsion": Vector2(371, 165),
	},
	# Ranura vacía: el arma principal se perdió en el salto (misión 2). No se
	# puede elegir; al recoger cualquier arma principal, la reemplaza.
	"nada": {
		"name": "PERDIDA", "ranura": 0, "bando": "aliado", "tipo": "nada",
		"mag": 0, "reserve": 0, "damage": 0.0, "interval": 0.5, "auto": false,
		"reload": 1.0, "spread_hip": 1.5, "spread_ads": 0.5, "recoil": 0.0,
		"sound": "pistol", "pitch": 1.0, "ads_fov": 55.0,
		"hip": Vector3(0.1, -0.06, -0.22), "ads": Vector3(0, 0, -0.26),
		"vm_cadera": Vector2(-63, 17), "vm_pos": Vector2(70, 30), "vm_boca": Vector2(326, 142), "vm_mira": Vector2(334, 136),
		"mira_pos": Vector2(-3, 33), "mira_poste": Vector2(323, 147),
		"recarga": "cargador", "recarga_punto": Vector2(409, 350), "expulsion": Vector2(371, 165),
	},
	"carbine": {
		"name": "M1 CARBINE", "ranura": 0, "bando": "aliado", "tipo": "fusil",
		"mag": 15, "reserve": 75, "damage": 60.0, "interval": 0.12, "auto": false,
		"reload": 1.8, "spread_hip": 1.0, "spread_ads": 0.25, "recoil": 1.5,
		"sound": "rifle", "pitch": 1.25, "ads_fov": 48.0,
		"hip": Vector3(0.15, -0.14, -0.26), "ads": Vector3(0, 0, -0.1),
		"vm_cadera": Vector2(43, 34), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(195, 136), "vm_mira": Vector2(378, 187),
		"mira_pos": Vector2(-2, 27), "mira_poste": Vector2(322, 153),
		"recarga": "cargador", "recarga_punto": Vector2(311, 241), "expulsion": Vector2(324, 187),
	},
	"thompson": {
		"name": "THOMPSON M1A1", "ranura": 0, "bando": "aliado", "tipo": "subfusil",
		"mag": 30, "reserve": 120, "damage": 34.0, "interval": 0.085, "auto": true,
		"reload": 2.2, "spread_hip": 2.0, "spread_ads": 0.8, "recoil": 0.9,
		"sound": "pistol", "pitch": 0.9, "ads_fov": 55.0,
		"hip": Vector3(0.15, -0.13, -0.25), "ads": Vector3(0, 0, -0.12),
		"vm_cadera": Vector2(51, 34), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(188, 134), "vm_mira": Vector2(410, 160),
		"mira_pos": Vector2(-2, 60), "mira_poste": Vector2(322, 120),
		"recarga": "cargador", "recarga_punto": Vector2(284, 196), "expulsion": Vector2(324, 169),
	},
	"bar": {
		"name": "BAR M1918A2", "ranura": 0, "bando": "aliado", "tipo": "ametralladora",
		"mag": 20, "reserve": 100, "damage": 80.0, "interval": 0.14, "auto": true,
		"reload": 2.6, "spread_hip": 2.4, "spread_ads": 0.5, "recoil": 1.8,
		"sound": "rifle", "pitch": 0.95, "ads_fov": 45.0,
		"hip": Vector3(0.16, -0.15, -0.27), "ads": Vector3(0, 0, -0.1),
		"vm_cadera": Vector2(135, 28), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(105, 137), "vm_mira": Vector2(360, 135),
		"mira_pos": Vector2(-2, 111), "mira_poste": Vector2(322, 69),
		"recarga": "cargador", "recarga_punto": Vector2(282, 216), "expulsion": Vector2(306, 169),
	},
	"springfield": {
		"name": "SPRINGFIELD M1903", "ranura": 0, "bando": "aliado", "tipo": "fusil",
		"mag": 5, "reserve": 40, "damage": 160.0, "interval": 1.1, "auto": false,
		"reload": 2.8, "spread_hip": 1.6, "spread_ads": 0.0, "recoil": 3.5,
		"sound": "rifle", "pitch": 0.9, "ads_fov": 14.0, "scope": true,
		"hip": Vector3(0.16, -0.15, -0.27), "ads": Vector3(0, 0, -0.1),
		"vm_cadera": Vector2(125, 18), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(114, 148), "vm_mira": Vector2(410, 158),
		"recarga": "cargador", "recarga_punto": Vector2(324, 259), "expulsion": Vector2(324, 202),
	},
	"bazooka": {
		"name": "BAZUCA M1", "ranura": 0, "bando": "aliado", "tipo": "bazuca",
		"mag": 1, "reserve": 5, "damage": 220.0, "interval": 1.0, "auto": false,
		"reload": 3.0, "spread_hip": 1.2, "spread_ads": 0.3, "recoil": 4.0,
		"sound": "throw", "pitch": 0.6, "ads_fov": 50.0, "rocket": true,
		"hip": Vector3(0.2, -0.12, -0.3), "ads": Vector3(0.0, -0.02, -0.2),
		"vm_cadera": Vector2(135, 1), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(104, 165), "vm_mira": Vector2(405, 168),
		"recarga": "cohete",
	},
	# ------------------------------------------------------------- alemanas
	"kar98k": {
		"name": "KARABINER 98K", "ranura": 0, "bando": "aleman", "tipo": "fusil",
		"mag": 5, "reserve": 30, "damage": 115.0, "interval": 1.0, "auto": false,
		"reload": 2.6, "spread_hip": 1.3, "spread_ads": 0.1, "recoil": 3.0,
		"sound": "rifle", "pitch": 0.92, "ads_fov": 40.0,
		"hip": Vector3(0.16, -0.15, -0.27), "ads": Vector3(0, 0, -0.1),
		"vm_cadera": Vector2(132, 19), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(107, 147), "vm_mira": Vector2(380, 185),
		"mira_pos": Vector2(-2, 77), "mira_poste": Vector2(322, 103),
		"recarga": "cargador", "recarga_punto": Vector2(317, 274), "expulsion": Vector2(306, 198),
	},
	"mp40": {
		"name": "MP 40", "ranura": 0, "bando": "aleman", "tipo": "subfusil",
		"mag": 32, "reserve": 96, "damage": 30.0, "interval": 0.11, "auto": true,
		"reload": 2.4, "spread_hip": 2.0, "spread_ads": 0.9, "recoil": 0.8,
		"sound": "pistol", "pitch": 0.95, "ads_fov": 55.0,
		"hip": Vector3(0.15, -0.13, -0.25), "ads": Vector3(0, 0, -0.12),
		"vm_cadera": Vector2(41, 23), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(198, 143), "vm_mira": Vector2(325, 145),
		"mira_pos": Vector2(-2, 52), "mira_poste": Vector2(322, 128),
		"recarga": "cargador", "recarga_punto": Vector2(263, 216), "expulsion": Vector2(281, 158),
	},
	"stg44": {
		"name": "STG 44", "ranura": 0, "bando": "aleman", "tipo": "subfusil",
		"mag": 30, "reserve": 90, "damage": 55.0, "interval": 0.1, "auto": true,
		"reload": 2.4, "spread_hip": 1.8, "spread_ads": 0.5, "recoil": 1.2,
		"sound": "rifle", "pitch": 1.15, "ads_fov": 48.0,
		"hip": Vector3(0.15, -0.14, -0.26), "ads": Vector3(0, 0, -0.1),
		"vm_cadera": Vector2(60, 10), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(180, 155), "vm_mira": Vector2(305, 130),
		"mira_pos": Vector2(-3, 58), "mira_poste": Vector2(323, 122),
		"recarga": "cargador", "recarga_punto": Vector2(268, 230), "expulsion": Vector2(342, 173),
	},
	"mg42": {
		"name": "MG 42", "ranura": 0, "bando": "aleman", "tipo": "ametralladora",
		"mag": 50, "reserve": 150, "damage": 55.0, "interval": 0.05, "auto": true,
		"reload": 4.0, "spread_hip": 3.5, "spread_ads": 1.5, "recoil": 1.1,
		"sound": "rifle", "pitch": 1.2, "ads_fov": 50.0,
		"hip": Vector3(0.17, -0.16, -0.28), "ads": Vector3(0, 0, -0.12),
		"vm_cadera": Vector2(136, 29), "vm_pos": Vector2(96, 18), "vm_boca": Vector2(104, 136), "vm_mira": Vector2(230, 120),
		"mira_pos": Vector2(-2, 55), "mira_poste": Vector2(322, 125),
		"recarga": "cargador", "recarga_punto": Vector2(230, 194), "expulsion": Vector2(288, 155),
	},
	"luger": {
		"name": "LUGER P08", "ranura": 1, "bando": "aleman", "tipo": "pistola",
		"mag": 8, "reserve": 24, "damage": 40.0, "interval": 0.13, "auto": false,
		"reload": 1.5, "spread_hip": 1.4, "spread_ads": 0.5, "recoil": 1.8,
		"sound": "pistol", "pitch": 1.1, "ads_fov": 55.0,
		"hip": Vector3(0.1, -0.06, -0.22), "ads": Vector3(0, 0, -0.26),
		"vm_cadera": Vector2(41, 10), "vm_pos": Vector2(70, 30), "vm_boca": Vector2(225, 144), "vm_mira": Vector2(330, 150),
		"mira_pos": Vector2(-4, 50), "mira_poste": Vector2(324, 130),
		"recarga": "cargador", "recarga_punto": Vector2(340, 300), "expulsion": Vector2(353, 169),
	},
}

## Qué llevan los alemanes al morir (peso de cada arma). Kar98k la mayoría.
const BOTIN_ALEMAN := {"kar98k": 60, "mp40": 22, "stg44": 10, "mg42": 4, "luger": 4}

static var _texturas := {}


static func datos(id: String) -> Dictionary:
	return DATOS.get(id, DATOS["garand"])


## Imagen del arma (arma_<id>_cadera, arma_<id>_mira, perfil_<id>...) o null si no existe.
static func imagen(nombre: String) -> Texture2D:
	if not _texturas.has(nombre):
		var path := "res://assets/armas/%s.png" % nombre
		_texturas[nombre] = load(path) if ResourceLoader.exists(path) else null
	return _texturas[nombre]


## Arma 3D con volumen (la que llevan los soldados y la que queda en el
## suelo), hecha de su perfil de ChatGPT con tools/modelos/armas3d.py/.gd.
## El agarre está en el origen; marcas en los meta de la malla.
static var _mat_3d: StandardMaterial3D


static func malla_3d(id: String) -> Mesh:
	var path := "res://assets/armas/3d/%s.res" % id
	return load(path) if ResourceLoader.exists(path) else null


static func modelo_3d(id: String) -> MeshInstance3D:
	if _mat_3d == null:
		_mat_3d = StandardMaterial3D.new()
		_mat_3d.albedo_texture = load("res://assets/armas/3d/atlas.png")
		_mat_3d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_mat_3d.alpha_scissor_threshold = 0.5
		_mat_3d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_mat_3d.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_3d.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mat_3d.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = malla_3d(id)
	mi.material_override = _mat_3d
	return mi


static func botin_aleman(rng: RandomNumberGenerator) -> String:
	var total := 0
	for v in BOTIN_ALEMAN.values():
		total += v
	var r := rng.randi_range(1, total)
	for id in BOTIN_ALEMAN:
		r -= BOTIN_ALEMAN[id]
		if r <= 0:
			return id
	return "kar98k"
