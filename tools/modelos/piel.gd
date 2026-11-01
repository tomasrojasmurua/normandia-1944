extends SceneTree
## Arma la malla final de un soldado: toma un modelo simplificado (GLB hecho
## con gltfpack desde el original de Meshy) y le copia el esqueleto de la
## malla que devolvió Mixamo (cada vértice toma los huesos del vértice de
## Mixamo más cercano). Así se puede cambiar el detalle del modelo sin volver
## a subirlo a Mixamo.
##
## Uso:
##   godot --headless --path . --script tools/modelos/piel.gd -- simplificado.glb res://assets/soldados/aleman/rifle_idle.fbx res://assets/soldados/aleman/cuerpo.res
##
## Para simplificar el original (gltfpack se compila desde github.com/zeux/meshoptimizer):
##   gltfpack -i soldado_aleman_meshy.glb -o simplificado.glb -si 0.005 -se 0.05 -noq

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# --- Malla simplificada (espacio original de Meshy)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(args[0], st) != OK:
		push_error("no pude leer " + args[0]); quit(1); return
	var im: ImporterMesh = st.get_meshes()[0].mesh
	var arr := im.get_surface_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	# El nodo del GLB puede traer una transformación: aplicarla
	var xf := Transform3D.IDENTITY
	for n: GLTFNode in st.get_nodes():
		if n.mesh == 0:
			xf = n.xform
	for k in pos.size():
		pos[k] = xf * pos[k]
		nor[k] = (xf.basis * nor[k]).normalized()

	# --- Malla con esqueleto de Mixamo
	var escena: Node = load(args[1]).instantiate()
	var mi: MeshInstance3D = escena.find_children("*", "MeshInstance3D", true, false)[0]
	var marr := mi.mesh.surface_get_arrays(0)
	var mpos: PackedVector3Array = marr[Mesh.ARRAY_VERTEX]
	var mhue: PackedInt32Array = marr[Mesh.ARRAY_BONES]
	var mpes: PackedFloat32Array = marr[Mesh.ARRAY_WEIGHTS]
	var por_vertice := mhue.size() / mpos.size()

	# --- Alinear las dos mallas por su caja (misma orientación, otra escala)
	var a := _caja(pos)
	var b := _caja(mpos)
	var esc := b.size.y / a.size.y
	print("cajas: simplificada ", a.size, " mixamo ", b.size, " escala ", esc)
	var centro_a := a.get_center()
	var centro_b := b.get_center()
	for k in pos.size():
		pos[k] = (pos[k] - centro_a) * esc + centro_b

	# --- Copiar huesos del vértice más cercano (rejilla para buscar rápido)
	var celda := b.size.y / 40.0
	var rejilla := {}
	for k in mpos.size():
		var c := Vector3i((mpos[k] / celda).floor())
		if not rejilla.has(c):
			rejilla[c] = PackedInt32Array()
		rejilla[c].append(k)
	var hue := PackedInt32Array()
	var pes := PackedFloat32Array()
	hue.resize(pos.size() * por_vertice)
	pes.resize(pos.size() * por_vertice)
	var lejos := 0
	for k in pos.size():
		var c := Vector3i((pos[k] / celda).floor())
		var mejor := -1
		var dmin := INF
		var radio := 1
		while mejor < 0 or radio <= 2:
			for dx in range(-radio, radio + 1):
				for dy in range(-radio, radio + 1):
					for dz in range(-radio, radio + 1):
						var lista = rejilla.get(c + Vector3i(dx, dy, dz))
						if lista == null:
							continue
						for j in lista:
							var d := pos[k].distance_squared_to(mpos[j])
							if d < dmin:
								dmin = d; mejor = j
			radio += 1
			if radio > 8:
				break
		if sqrt(dmin) > celda:
			lejos += 1
		for w in por_vertice:
			hue[k * por_vertice + w] = mhue[mejor * por_vertice + w]
			pes[k * por_vertice + w] = mpes[mejor * por_vertice + w]
	print("vértices: ", pos.size(), " triángulos: ", idx.size() / 3, " lejos de Mixamo: ", lejos)

	var nuevo := []
	nuevo.resize(Mesh.ARRAY_MAX)
	nuevo[Mesh.ARRAY_VERTEX] = pos
	nuevo[Mesh.ARRAY_NORMAL] = nor
	nuevo[Mesh.ARRAY_TEX_UV] = uv
	nuevo[Mesh.ARRAY_INDEX] = idx
	nuevo[Mesh.ARRAY_BONES] = hue
	nuevo[Mesh.ARRAY_WEIGHTS] = pes
	var malla := ArrayMesh.new()
	var formato := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if por_vertice == 8 else 0
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, nuevo, [], {}, formato)
	var err := ResourceSaver.save(malla, args[2])
	print("guardado ", args[2], " -> ", err)
	escena.free()
	quit()


func _caja(p: PackedVector3Array) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for v in p:
		mn = mn.min(v); mx = mx.max(v)
	return AABB(mn, mx - mn)
