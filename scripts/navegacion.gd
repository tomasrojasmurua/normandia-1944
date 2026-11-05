extends RefCounted
class_name Navegacion
## Mapa de caminos de la playa (navmesh): por dónde se puede caminar sin
## chocar con erizos, sacos, búnker ni cajas. Se arma una vez al cargar la
## playa a partir de las formas de choque del escenario (capa 1), y después
## cada soldado pide rutas con `ruta()` (es barato: una consulta por destino).

static var _region := RID()
static var _mapa := RID()
static var listo := false


## Arma el mapa con los obstáculos que cuelgan de `raiz`, dentro de `zona`.
static func hornear(raiz: Node3D, zona: AABB) -> void:
	var nav := NavigationMesh.new()
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	nav.agent_radius = 0.45
	nav.agent_height = 1.6
	nav.agent_max_climb = 0.4
	nav.agent_max_slope = 40.0
	nav.region_min_size = 4.0
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_collision_mask = 1 | 256   # escenario + cajas de los modelos
	nav.filter_baking_aabb = zona
	var fuente := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, fuente, raiz)
	NavigationServer3D.bake_from_source_geometry_data(nav, fuente)

	_mapa = raiz.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(_mapa, nav.cell_size)
	NavigationServer3D.map_set_cell_height(_mapa, nav.cell_height)
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _mapa)
	NavigationServer3D.region_set_navigation_mesh(_region, nav)
	NavigationServer3D.map_force_update(_mapa)
	listo = true


## Ruta de `desde` a `hasta` (lista de puntos); vacía si no hay mapa.
static func ruta(desde: Vector3, hasta: Vector3) -> PackedVector3Array:
	if not listo:
		return PackedVector3Array([hasta])
	return NavigationServer3D.map_get_path(_mapa, desde, hasta, true)


## El punto caminable más cercano a `pos`.
static func cerca_de(pos: Vector3) -> Vector3:
	if not listo:
		return pos
	return NavigationServer3D.map_get_closest_point(_mapa, pos)


static func olvidar() -> void:
	listo = false
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
	_region = RID()
