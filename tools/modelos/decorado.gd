extends SceneTree
## Prepara un modelo de decorado de Meshy (GLB) para el juego: lo simplifica
## a pocas caras con el simplificador de Godot (meshoptimizer), pasa el color
## de la textura a los vértices (aspecto retro, sin textura) y lo centra con
## la base en el suelo.
##
## Uso:
##   godot --headless --path . --script tools/modelos/decorado.gd -- entrada.glb res://assets/decorado/higgins 2500
##   → res://assets/decorado/higgins.res (malla con el color en cada vértice, sin textura)
## El modelo queda mirando como venía de Meshy; el tamaño real se ajusta en el juego.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var entrada: String = a[0]
	var salida: String = a[1]
	var caras := int(a[2]) if a.size() > 2 else 2500

	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(entrada, st) != OK:
		push_error("no pude leer " + entrada); quit(1); return
	# Todas las mallas del archivo, con la transformación de su nodo
	var pos_t := PackedVector3Array()
	var nor_t := PackedVector3Array()
	var uv_t := PackedVector2Array()
	var idx_t := PackedInt32Array()
	var textura: Image = null
	for n: GLTFNode in st.get_nodes():
		if n.mesh < 0:
			continue
		var gm: GLTFMesh = st.get_meshes()[n.mesh]
		var im: ImporterMesh = gm.mesh
		var xf := _global(st, n)
		for s in im.get_surface_count():
			var arr := im.get_surface_arrays(s)
			var base := pos_t.size()
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				pos_t.append(xf * v)
			if arr[Mesh.ARRAY_NORMAL]:
				for v: Vector3 in arr[Mesh.ARRAY_NORMAL]:
					nor_t.append((xf.basis * v).normalized())
			if arr[Mesh.ARRAY_TEX_UV]:
				uv_t.append_array(arr[Mesh.ARRAY_TEX_UV])
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				for i in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
					idx.append(i)
			for i in idx:
				idx_t.append(base + i)
			var mat := im.get_surface_material(s)
			if textura == null and mat is BaseMaterial3D and mat.albedo_texture:
				textura = mat.albedo_texture.get_image()
	print("original: %d vértices, %d caras" % [pos_t.size(), idx_t.size() / 3])

	# Soldar vértices por posición (sin mirar la UV: las costuras de la UV de
	# Meshy no dejan simplificar) y pasar el color de la textura a cada vértice.
	# Con pocas caras, el color por vértice da un aspecto retro "pintado".
	if textura and textura.is_compressed():
		textura.decompress()
	var chica: Image = null
	if textura:
		chica = textura.duplicate()
		chica.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var mapa := {}
	var p2 := PackedVector3Array(); var n2 := PackedVector3Array(); var u2 := PackedVector2Array()
	var col_suma: Array[Color] = []
	var col_n := PackedInt32Array()
	var remap := PackedInt32Array(); remap.resize(pos_t.size())
	for i in pos_t.size():
		var k := Vector3i(roundi(pos_t[i].x * 1000), roundi(pos_t[i].y * 1000), roundi(pos_t[i].z * 1000))
		var j: int
		if mapa.has(k):
			j = mapa[k]
		else:
			j = p2.size(); mapa[k] = j
			p2.append(pos_t[i]); n2.append(Vector3.ZERO); u2.append(uv_t[i] if uv_t.size() > i else Vector2.ZERO)
			col_suma.append(Color(0, 0, 0, 0)); col_n.append(0)
		remap[i] = j
		if nor_t.size() > i:
			n2[j] += nor_t[i]
		if chica and uv_t.size() > i:
			var uv := uv_t[i]
			var c := chica.get_pixel(clampi(int(fposmod(uv.x, 1.0) * 511), 0, 511), clampi(int(fposmod(uv.y, 1.0) * 511), 0, 511))
			col_suma[j] += c; col_n[j] += 1
	var c2 := PackedColorArray()
	for j in p2.size():
		n2[j] = n2[j].normalized() if n2[j].length() > 0.0 else Vector3.UP
		var c: Color = col_suma[j] / maxf(col_n[j], 1)
		c.a = 1.0
		c2.append(c)
	var i2 := PackedInt32Array()
	for i in idx_t:
		i2.append(remap[i])
	print("soldado: %d vértices" % p2.size())

	# Simplificar con LODs de Godot; se repite sobre el LOD más bajo hasta
	# llegar cerca de `caras` (cada pasada se detiene en un límite de error)
	var mejor := i2
	for pasada in 6:
		if mejor.size() / 3 <= caras * 1.3:
			break
		var imp := ImporterMesh.new()
		var arrs := []
		arrs.resize(Mesh.ARRAY_MAX)
		arrs[Mesh.ARRAY_VERTEX] = p2; arrs[Mesh.ARRAY_NORMAL] = n2; arrs[Mesh.ARRAY_INDEX] = mejor
		imp.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrs)
		imp.generate_lods(60.0 + pasada * 20.0, 25.0 + pasada * 15.0, [])
		var antes := mejor.size()
		for l in imp.get_surface_lod_count(0):
			var li := imp.get_surface_lod_indices(0, l)
			if li.size() / 3 >= caras * 0.6:
				mejor = li
		print("  pasada %d: %d caras" % [pasada, mejor.size() / 3])
		if mejor.size() == antes:
			break
	print("simplificado: %d caras" % (mejor.size() / 3))

	# Compactar vértices usados, centrar en X/Z y apoyar en el suelo
	var usado := {}
	var p3 := PackedVector3Array(); var n3 := PackedVector3Array(); var c3 := PackedColorArray(); var i3 := PackedInt32Array()
	for i in mejor:
		if not usado.has(i):
			usado[i] = p3.size(); p3.append(p2[i]); n3.append(n2[i]); c3.append(c2[i])
		i3.append(usado[i])
	var caja := AABB(p3[0], Vector3.ZERO)
	for v in p3:
		caja = caja.expand(v)
	var mover := Vector3(-caja.get_center().x, -caja.position.y, -caja.get_center().z)
	for i in p3.size():
		p3[i] += mover
	print("tamaño: ", caja.size)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = p3; out[Mesh.ARRAY_NORMAL] = n3; out[Mesh.ARRAY_COLOR] = c3; out[Mesh.ARRAY_INDEX] = i3
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(salida.get_base_dir()))
	ResourceSaver.save(am, salida + ".res")
	print("listo: ", salida)
	quit()


func _global(st: GLTFState, n: GLTFNode) -> Transform3D:
	var xf := n.xform
	var padre := n.parent
	while padre >= 0:
		var p: GLTFNode = st.get_nodes()[padre]
		xf = p.xform * xf
		padre = p.parent
	return xf
