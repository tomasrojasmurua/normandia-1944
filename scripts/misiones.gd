extends RefCounted
class_name Misiones
## Los datos de cada misión de la campaña (sección 6). El "motor" (Escuadras,
## Defensa, Objetivos, Game) lee de aquí todo lo que antes estaba escrito a
## mano para la Playa Omaha. Una misión nueva = una entrada nueva en DATOS
## (+ su escena con el mapa).
##
## Campos de la misión:
##   nombre, lugar, fecha        textos para el menú, el briefing y el diario
##   escena                      escena con el mapa (y quien arma la misión)
##   hora                        minutos desde medianoche al empezar (fija)
##   clima, entrada              "nublado", "noche" (ver noche.gd)... / "playa", "planeador", "a_pie"
##   perdidos                    (misión 2) puestos de la escuadra del jugador que empiezan dispersos
##   sectores                    carril X (min, max) de cada escuadra 0–3 al empezar
##   escuadra_jugador            compañeros del jugador: [posición, arma, nombre]
##   lider_z, hombres_z          dónde empiezan las otras escuadras (Z)
##   fases                       la misión se juega por fases, en orden (ver abajo)
##
## Campos de cada fase:
##   nombre, hora, radio         título, hora del reloj al empezar, mensaje de radio
##   ancla                       hacia dónde se repliegan los alemanes
##   morteros                    intervalo (min, max) en s; sin la clave = sin morteros
##   bengalas                    (de noche) intervalo (min, max) en s entre bengalas alemanas
##   refuerzos_us                refuerzos americanos que se suman a CADA escuadra
##   llegada                     dónde aparecen los refuerzos americanos: [centro, ancho X]
##                               (sin la clave: en la orilla de su sector)
##   alemanes                    alemanes que aparecen al empezar la fase: [[zona, n], ...]
##                               zona = [x_min, x_max, z_min, z_max] (en coberturas libres)
##   refuerzos                   alemanes que llegan durante la fase: {n, zona, cada}
##   retirar_z                   al empezar la fase se rinden los alemanes que quedaron atrás
##                               (Z mayor que esta y lejos de los jugadores)
##   objetivos                   lista de objetivos de la fase (todos para pasar a la siguiente)
##
## Campos de cada objetivo:
##   id, n, corto, pos           nombre largo, etiqueta del marcador y lugar
##   tipo                        "carga" (un jugador pone una carga: seg + mecha),
##                               "mg" (matar al tirador de la MG42 en `nido` y tomar el nido),
##                               "tomar" (americanos dentro de `radio`, sin alemanes cerca),
##                               "defender" (aguantar `seg` en `radio` mientras llegan `olas`),
##                               "reunir" (encontrar a los compañeros dispersos, ver objetivos.gd)
##   esc                         escuadras a las que les toca (0 = la del jugador)
##   carril                      carril X por donde avanzan las escuadras hacia él
##   tras                        id del objetivo que tiene que estar cumplido antes
##   efecto                      algo que cambia en el mapa al cumplirlo ("brecha", "casamata")
##   boom                        dónde explota la carga

const DATOS := {
	"omaha": {
		"nombre": "PLAYA OMAHA",
		"lugar": "SECTOR DOG GREEN, PLAYA OMAHA",
		"fecha": "6 DE JUNIO DE 1944",
		"escena": "res://scenes/main.tscn",
		"hora": 6 * 60 + 30,
		"clima": "nublado",
		"entrada": "playa",
		"briefing": [
			"SARGENTO, SU COMPAÑÍA DESEMBARCA",
			"EN DOG GREEN CON LA PRIMERA OLA.",
			"VUELE EL BÚNKER Y SUBA EL",
			"ACANTILADO. DESTRUYA EL CAÑÓN",
			"Y TOME VIERVILLE. ELIJA A TRES",
			"HOMBRES: LOS QUIERO DE VUELTA.",
		],
		"sectores": [Vector2(-6, 22), Vector2(-38, -20), Vector2(18, 38), Vector2(-22, -4)],
		"escuadra_jugador": [[Vector3(-9, 0, -3), "thompson", "DELUCA"],
			[Vector3(11, 0, -6), "garand", "HAYES"], [Vector3(-6, 0, 3), "bar", "BRENNAN"]],
		"lider_z": 5.0,
		"hombres_z": Vector2(6.5, 9.0),
		"refuerzos_z": Vector2(7.0, 9.5),
		"refuerzo_z": -47.0,
		"fases": [
			{
				"nombre": "LA PLAYA",
				"hora": 6 * 60 + 30,
				"radio": "",
				"ancla": Vector3(0, 0, -42),
				"morteros": Vector2(7.0, 12.0),
				"refuerzos_us": 4,
				"refuerzos": {"n": 12, "zona": [-40.0, 40.0, -50.0, -24.0], "cada": Vector2(25.0, 35.0)},
				"objetivos": [
					{"id": "bunker", "n": "VOLAR EL BÚNKER", "corto": "BÚNKER", "pos": Vector3(0, 0, -37.5),
						"tipo": "carga", "seg": 5.0, "mecha": 6.0, "boom": Vector3(0, 0.6, -39.0),
						"esc": [0], "carril": Vector2(-6, 22)},
					{"id": "mg_izq", "n": "CALLAR LA MG42 IZQUIERDA", "corto": "MG42", "pos": Vector3(-24, 0, -31),
						"tipo": "mg", "nido": Vector3(-24, 0, -31), "esc": [1], "carril": Vector2(-38, -20)},
					{"id": "mg_der", "n": "CALLAR LA MG42 DERECHA", "corto": "MG42", "pos": Vector3(23, 0, -29),
						"tipo": "mg", "nido": Vector3(23, 0, -29), "esc": [2], "carril": Vector2(18, 38)},
					{"id": "trinchera", "n": "TOMAR LA TRINCHERA", "corto": "TRINCHERA", "pos": Vector3(-14, 0, -36),
						"tipo": "tomar", "seg": 12.0, "radio": 6.0, "esc": [3], "carril": Vector2(-22, -4)},
				],
			},
			{
				"nombre": "LA LADERA",
				"retirar_z": -20.0,
				"hora": 8 * 60 + 10,
				"radio": "[RADIO: ¡SAQUEN A SUS HOMBRES DE LA PLAYA! VUELEN EL ALAMBRE Y SUBAN POR LA QUEBRADA]",
				"ancla": Vector3(12, 14, -88),
				"morteros": Vector2(10.0, 16.0),
				"refuerzos_us": 2,
				"alemanes": [[[-14.0, 40.0, -76.0, -60.0], 6], [[-20.0, 44.0, -88.0, -80.0], 6]],
				"refuerzos": {"n": 6, "zona": [-20.0, 44.0, -95.0, -82.0], "cada": Vector2(30.0, 40.0)},
				"objetivos": [
					{"id": "bangalore", "n": "VOLAR EL ALAMBRE CON EL BANGALORE", "corto": "BANGALORE",
						"pos": Vector3(12, 0, -50.6), "tipo": "carga", "seg": 4.0, "mecha": 4.0, "radio": 4.0,
						"boom": Vector3(12, 0.4, -52.6), "efecto": "brecha", "esc": [0, 1, 2, 3], "carril": Vector2(4, 20)},
					{"id": "trinchera_ladera", "n": "LIMPIAR LA TRINCHERA DE LA LADERA", "corto": "TRINCHERA",
						"pos": Vector3(2, 5.3, -65.5), "tipo": "tomar", "seg": 12.0, "radio": 6.0,
						"tras": "bangalore", "esc": [1, 3], "carril": Vector2(-8, 12)},
					{"id": "mg_ladera", "n": "CALLAR LA MG42 DE LA LADERA", "corto": "MG42",
						"pos": Vector3(23, 8.8, -71.5), "nido": Vector3(23, 8.8, -71.5), "tipo": "mg",
						"tras": "bangalore", "esc": [0, 2], "carril": Vector2(12, 32)},
				],
			},
			{
				"nombre": "LA MESETA",
				"retirar_z": -60.0,
				"hora": 9 * 60 + 40,
				"radio": "[RADIO: UN CAÑÓN EN CASAMATA SIGUE BATIENDO LA PLAYA. ¡DESTRÚYANLO!]",
				"ancla": Vector3(0, 14, -118),
				"morteros": Vector2(12.0, 18.0),
				"refuerzos_us": 4,
				"llegada": [Vector3(12, 14, -86), 10.0],
				"alemanes": [[[-38.0, 38.0, -102.0, -84.0], 6], [[-38.0, 38.0, -132.0, -104.0], 6]],
				"refuerzos": {"n": 6, "zona": [-38.0, 38.0, -134.0, -110.0], "cada": Vector2(25.0, 35.0)},
				"objetivos": [
					{"id": "casamata", "n": "VOLAR LA CASAMATA DEL CAÑÓN", "corto": "CASAMATA",
						"pos": Vector3(-26, 14, -88.6), "tipo": "carga", "seg": 5.0, "mecha": 6.0,
						"boom": Vector3(-26, 15.2, -84.0), "efecto": "casamata", "esc": [0], "carril": Vector2(-36, -12)},
					{"id": "trinchera_seto", "n": "TOMAR LA TRINCHERA DEL SETO", "corto": "TRINCHERA",
						"pos": Vector3(12, 14, -99.6), "tipo": "tomar", "seg": 12.0, "radio": 7.0,
						"esc": [1, 3], "carril": Vector2(0, 26)},
					{"id": "mg_seto", "n": "CALLAR LA MG42 DE LOS SETOS", "corto": "MG42",
						"pos": Vector3(-14, 14, -113.6), "nido": Vector3(-14, 14, -113.6), "tipo": "mg",
						"esc": [2], "carril": Vector2(-26, -2)},
				],
			},
			{
				"nombre": "VIERVILLE",
				"retirar_z": -100.0,
				"hora": 11 * 60 + 30,
				"radio": "[RADIO: TOMEN EL CRUCE DE VIERVILLE Y AGUANTEN HASTA QUE LLEGUEN LOS TANQUES]",
				"ancla": Vector3(0, 14, -168),
				"refuerzos_us": 4,
				"llegada": [Vector3(4, 14, -106), 14.0],
				# Defensores del cruce: un grupo pegado al cruce y el resto en el pueblo
				"alemanes": [[[-14.0, 14.0, -162.0, -143.0], 6], [[-38.0, 38.0, -182.0, -136.0], 9]],
				"objetivos": [
					{"id": "cruce", "n": "TOMAR EL CRUCE DE VIERVILLE", "corto": "CRUCE",
						"pos": Vector3(0, 14, -152), "tipo": "tomar", "seg": 12.0, "radio": 9.0,
						"esc": [0, 1, 2, 3], "carril": Vector2(-16, 16)},
					{"id": "resistir", "n": "RESISTIR EL CONTRAATAQUE", "corto": "RESISTIR",
						"pos": Vector3(0, 14, -152), "tipo": "defender", "seg": 240.0, "radio": 18.0,
						"tras": "cruce", "esc": [0, 1, 2, 3], "carril": Vector2(-22, 22),
						# v0.32: contraataque de verdad (antes 4 por ola cada ~32 s, máx. 16
						# vivos contando a los del pueblo que no se movían: casi no salían)
						"olas": {"cada": Vector2(22.0, 28.0), "n": 5, "crece": 3, "max_vivos": 20,
							"morteros": Vector2(9.0, 15.0), "pueblo": true, "mg": true, "gran": 0.7,
							"desde": [Vector3(-30, 14, -198), Vector3(0, 14, -200), Vector3(30, 14, -198),
								Vector3(-35, 14, -172), Vector3(35, 14, -172)]}},
				],
			},
		],
	},
	"planeador": {
		"nombre": "EL PLANEADOR",
		"lugar": "SAINTE-MÈRE-ÉGLISE",
		"fecha": "NOCHE DEL 6 AL 7 DE JUNIO DE 1944",
		"escena": "res://scenes/planeador.tscn",
		"hora": 23 * 60 + 10,
		"clima": "noche",
		"entrada": "planeador",
		"suelo": 0.0,               # altura del terreno (Omaha: la meseta a 14 m)
		"briefing": [
			"SARGENTO, SU COMPAÑÍA LLEGA EN",
			"PLANEADOR AL SUR DE SAINTE-MÈRE-",
			"ÉGLISE. REÚNA A SUS HOMBRES,",
			"CRUCE LOS SETOS Y ENTRE AL PUEBLO.",
			"LA 82.A LO TIENE: HAY QUE",
			"AGUANTARLO HASTA QUE AMANEZCA.",
		],
		# El jugador y la escuadra 0 en el potrero del medio (su planeador, de
		# nariz en el seto); Kowalski y Cole en el de la izquierda (la granja);
		# Reyes en el de la derecha.
		"sectores": [Vector2(-16, 14), Vector2(-44, -30), Vector2(22, 42), Vector2(-32, -22)],
		"escuadra_jugador": [[Vector3(-3, 0, -16), "thompson", "DELUCA"],
			[Vector3(16.4, 0, -6), "garand", "HAYES"], [Vector3(-18.4, 0, 7), "bar", "BRENNAN"]],
		"perdidos": [1, 2],         # dispersos tras el choque (objetivo "reunir")
		"lider_z": 8.0,
		"hombres_z": Vector2(8.0, 11.0),
		"refuerzos_z": Vector2(8.0, 11.5),
		"fases": [
			{
				"nombre": "EL CHOQUE",
				"hora": 23 * 60 + 10,
				"radio": "",
				"ancla": Vector3(0, 0, -60),
				"bengalas": Vector2(16.0, 26.0),
				"refuerzos_us": 3,
				"alemanes": [[[-44.0, 44.0, -62.0, -34.0], 7], [[-44.0, -24.0, -30.0, -12.0], 3]],
				"refuerzos": {"n": 5, "zona": [-40.0, 40.0, -62.0, -40.0], "cada": Vector2(30.0, 40.0)},
				"objetivos": [
					{"id": "reunir", "n": "REUNIR A TU ESCUADRA", "corto": "ESCUADRA", "pos": Vector3(-5, 0, -18),
						"tipo": "reunir", "esc": [0], "carril": Vector2(-16, 14)},
					{"id": "mg_lz", "n": "CALLAR LA MG42 DEL SETO", "corto": "MG42", "pos": Vector3(14, 0, -34.5),
						"tipo": "mg", "nido": Vector3(14, 0, -34.5), "esc": [0, 2], "carril": Vector2(2, 26)},
					{"id": "granja", "n": "TOMAR LA GRANJA", "corto": "GRANJA", "pos": Vector3(-30, 0, -20),
						"tipo": "tomar", "seg": 12.0, "radio": 7.0, "esc": [1, 3], "carril": Vector2(-44, -22)},
				],
			},
			{
				"nombre": "LOS SETOS",
				"retirar_z": -28.0,
				"hora": 40,
				"radio": "[RADIO: AQUÍ 82.A. LOS CONTENEDORES CAYERON ENTRE LOS SETOS. RECUPÉRENLOS Y TOMEN EL CRUCE]",
				"ancla": Vector3(4, 0, -104),
				"morteros": Vector2(16.0, 26.0),
				"bengalas": Vector2(12.0, 20.0),
				"refuerzos_us": 2,
				"llegada": [Vector3(-2, 0, -36), 14.0],
				"alemanes": [[[-40.0, -14.0, -62.0, -50.0], 2], [[-44.0, 44.0, -90.0, -66.0], 6], [[-44.0, 44.0, -100.0, -92.0], 5]],
				"refuerzos": {"n": 6, "zona": [-40.0, 40.0, -104.0, -94.0], "cada": Vector2(28.0, 38.0)},
				"objetivos": [
					{"id": "cont_izq", "n": "RECUPERAR EL CONTENEDOR IZQUIERDO", "corto": "CONTENEDOR",
						"pos": Vector3(-28, 0, -48), "tipo": "tomar", "seg": 8.0, "radio": 5.0,
						"esc": [0, 1], "carril": Vector2(-40, -14)},
					{"id": "cont_der", "n": "RECUPERAR EL CONTENEDOR DERECHO", "corto": "CONTENEDOR",
						"pos": Vector3(30, 0, -80), "tipo": "tomar", "seg": 8.0, "radio": 5.0,
						"esc": [2, 3], "carril": Vector2(14, 44)},
					{"id": "mg_cruce", "n": "CALLAR LA MG42 DEL CRUCE", "corto": "MG42", "pos": Vector3(9.5, 0, -98.3),
						"tipo": "mg", "nido": Vector3(9.5, 0, -98.3), "esc": [0, 2], "carril": Vector2(0, 20)},
					{"id": "cruce", "n": "TOMAR EL CRUCE DEL CAMINO HUNDIDO", "corto": "CRUCE", "pos": Vector3(4, 0, -96),
						"tipo": "tomar", "seg": 12.0, "radio": 8.0, "esc": [0, 1, 2, 3], "carril": Vector2(-10, 18)},
				],
			},
			{
				"nombre": "EL PUEBLO",
				"retirar_z": -90.0,
				"hora": 2 * 60 + 30,
				"radio": "[RADIO: LA 82.A RESISTE EN LA PLAZA. LIMPIEN EL PUEBLO Y VUELEN ESE CAÑÓN]",
				"ancla": Vector3(-12, 0, -172),
				"morteros": Vector2(18.0, 28.0),
				"bengalas": Vector2(20.0, 30.0),
				"refuerzos_us": 3,
				"llegada": [Vector3(4, 0, -100), 12.0],
				"alemanes": [[[-42.0, 42.0, -160.0, -120.0], 9], [[-42.0, 42.0, -182.0, -160.0], 4]],
				"refuerzos": {"n": 6, "zona": [-40.0, 40.0, -184.0, -166.0], "cada": Vector2(25.0, 35.0)},
				"objetivos": [
					{"id": "canon", "n": "VOLAR EL CAÑÓN DE LA CALLE", "corto": "CAÑÓN", "pos": Vector3(22.5, 0, -137.2),
						"tipo": "carga", "seg": 5.0, "mecha": 6.0, "radio": 3.5, "boom": Vector3(26, 0.6, -140),
						"efecto": "canon", "esc": [0], "carril": Vector2(12, 34)},
					{"id": "mg_plaza", "n": "CALLAR LA MG42 DE LA PLAZA", "corto": "MG42", "pos": Vector3(-26, 0, -156),
						"tipo": "mg", "nido": Vector3(-26, 0, -156), "esc": [0, 2], "carril": Vector2(-36, -14)},
					{"id": "plaza", "n": "TOMAR LA PLAZA DE LA IGLESIA", "corto": "PLAZA", "pos": Vector3(-2, 0, -140),
						"tipo": "tomar", "seg": 12.0, "radio": 9.0, "esc": [0, 1, 2, 3], "carril": Vector2(-16, 8)},
				],
			},
			{
				"nombre": "EL AMANECER",
				"retirar_z": -120.0,
				"hora": 4 * 60 + 30,
				"radio": "[RADIO: ¡CONTRAATAQUE ALEMÁN DESDE NEUVILLE! ¡AGUANTEN LA SALIDA NORTE HASTA EL ALBA!]",
				"ancla": Vector3(4, 0, -210),
				"bengalas": Vector2(22.0, 32.0),
				"refuerzos_us": 4,
				"llegada": [Vector3(4, 0, -150), 12.0],
				"alemanes": [[[-40.0, 40.0, -216.0, -188.0], 6]],
				"objetivos": [
					{"id": "barricada", "n": "TOMAR LA BARRICADA NORTE", "corto": "BARRICADA", "pos": Vector3(4, 0, -174),
						"tipo": "tomar", "seg": 10.0, "radio": 9.0, "esc": [0, 1, 2, 3], "carril": Vector2(-16, 20)},
					{"id": "resistir_alba", "n": "AGUANTAR HASTA EL ALBA", "corto": "RESISTIR",
						"pos": Vector3(4, 0, -174), "tipo": "defender", "seg": 240.0, "radio": 18.0,
						"tras": "barricada", "esc": [0, 1, 2, 3], "carril": Vector2(-22, 26),
						"txt_toman": "[¡LOS ALEMANES TOMAN LA BARRICADA! ¡RECUPÉRENLA!]",
						"txt_perdido": "[PERDIMOS SAINTE-MÈRE-ÉGLISE]",
						"txt_llegan": "[RADIO: LOS TANQUES DE UTAH LLEGAN EN %d S. ¡AGUANTEN!]",
						"txt_fin": "[¡AMANECE Y LLEGAN LOS SHERMAN! ¡SAINTE-MÈRE-ÉGLISE ES NUESTRA!]",
						"txt_recupera": "¡RECUPERA LA BARRICADA!",
						"olas": {"cada": Vector2(28.0, 36.0), "n": 4, "max_vivos": 16, "morteros": Vector2(16.0, 24.0),
							"desde": [Vector3(-30, 0, -214), Vector3(4, 0, -218), Vector3(34, 0, -212),
								Vector3(-42, 0, -196), Vector3(42, 0, -196)]}},
				],
			},
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


static func fases() -> Array:
	return actual()["fases"]


static func fase(i: int) -> Dictionary:
	var f := fases()
	return f[clampi(i, 0, f.size() - 1)]
