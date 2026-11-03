extends RefCounted
class_name Misiones
## Los datos de cada misión de la campaña (sección 6). El "motor" (Escuadras,
## Defensa, Objetivos, Game) lee de aquí todo lo que antes estaba escrito a
## mano para la Playa Omaha. Una misión nueva = una entrada nueva en DATOS
## (+ su escena con el mapa).
##
## Campos:
##   nombre, lugar, fecha        textos para el menú, el briefing y el diario
##   escena                      escena con el mapa (y quien arma la misión)
##   hora                        minutos desde medianoche al empezar (fija)
##   clima                       "nublado", "lluvia", "noche"... (fijo)
##   entrada                     "playa", "paracaidas", "a_pie", "lanchas"
##   sectores                    carril X (min, max) de cada escuadra 0–3
##   escuadra_jugador            compañeros del jugador: [posición, arma, nombre]
##   lider_z, hombres_z          dónde empiezan las otras escuadras (Z)
##   refuerzos_z                 dónde aparecen los refuerzos americanos (Z min, max)
##   nidos                       nidos de MG42 alemanes
##   refuerzos_alemanes          cuántos llegan en total
##   refuerzo_z                  Z desde donde llegan (desde atrás)
##   morteros                    intervalo en segundos (min, max); vacío = sin morteros
##   objetivos                   uno por escuadra: n, corto, pos, tipo ("carga",
##                               "mg" con i = nido, "tomar"), seg

const DATOS := {
	"omaha": {
		"nombre": "PLAYA OMAHA",
		"lugar": "SECTOR DOG GREEN, PLAYA OMAHA",
		"fecha": "6 DE JUNIO DE 1944",
		"escena": "res://scenes/main.tscn",
		"hora": 6 * 60 + 30,
		"clima": "nublado",
		"entrada": "playa",
		"sectores": [Vector2(-6, 22), Vector2(-45, -20), Vector2(18, 45), Vector2(-22, -4)],
		"escuadra_jugador": [[Vector3(-9, 0, -3), "thompson", "DELUCA"],
			[Vector3(11, 0, -6), "garand", "HAYES"], [Vector3(-6, 0, 3), "bar", "BRENNAN"]],
		"lider_z": 5.0,
		"hombres_z": Vector2(6.5, 9.0),
		"refuerzos_z": Vector2(7.0, 9.5),
		"nidos": [Vector3(-24, 0, -31), Vector3(23, 0, -29)],
		"refuerzos_alemanes": 18,
		"refuerzo_z": -47.0,
		"morteros": Vector2(7.0, 12.0),
		"objetivos": [
			{"n": "VOLAR EL BÚNKER", "corto": "BÚNKER", "pos": Vector3(0, 0, -37.5), "tipo": "carga", "seg": 5.0},
			{"n": "CALLAR LA MG42 IZQUIERDA", "corto": "MG42", "pos": Vector3(-24, 0, -31), "tipo": "mg", "i": 0},
			{"n": "CALLAR LA MG42 DERECHA", "corto": "MG42", "pos": Vector3(23, 0, -29), "tipo": "mg", "i": 1},
			{"n": "TOMAR LA TRINCHERA", "corto": "TRINCHERA", "pos": Vector3(-14, 0, -36), "tipo": "tomar", "seg": 8.0},
		],
	},
}

const PRIMERA := "omaha"


## Los datos de la misión en curso (Game.mision).
static func actual() -> Dictionary:
	return DATOS.get(Game.mision, DATOS[PRIMERA])


static func dato(clave: String):
	return actual()[clave]


static func existe(id: String) -> bool:
	return DATOS.has(id)
