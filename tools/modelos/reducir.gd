extends SceneTree
## Reduce un modelo GLB de Meshy (millones de triángulos) a un modelo de juego
## (unos miles), con la textura de color achicada. Uso:
##   godot --headless --script tools/modelos/reducir.gd -- entrada.glb salida_base [triangulos]
## Escribe salida_base.obj/.mtl/.png (para Mixamo) y salida_base.glb (para mirar).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var entrada: String = args[0]
	var salida: String = args[1]
	var meta := int(args[2]) if args.size() > 2 else 5000
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(entrada, st) != OK:
		push_error("no pude leer " + entrada); quit(1); return
	var gm: GLTFMesh = st.get_meshes()[0]
	var im: ImporterMesh = gm.mesh
	var arr := im.get_surface_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	print("original: ", pos.size(), " vertices, ", idx.size() / 3, " triángulos")
	im.generate_lods(25.0, 60.0, [])
	var mejor := idx
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		print("  lod ", l, ": ", li.size() / 3, " triángulos")
		if li.size() / 3 >= meta * 0.6 and li.size() < mejor.size():
			mejor = li
	if mejor.size() / 3 > meta * 3:   # si los LOD no bajan lo suficiente, toma el menor
		for l in im.get_surface_lod_count(0):
			var li := im.get_surface_lod_indices(0, l)
			if li.size() < mejor.size():
				mejor = li
	# Compactar: solo los vértices usados
	var mapa := {}
	var npos := PackedVector3Array()
	var nuv := PackedVector2Array()
	var nidx := PackedInt32Array()
	for i in mejor:
		if not mapa.has(i):
			mapa[i] = npos.size()
			npos.append(pos[i])
			nuv.append(uv[i])
		nidx.append(mapa[i])
	# Escala: 1,78 m de alto, pies en y = 0
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for p in npos:
		mn = mn.min(p); mx = mx.max(p)
	var esc := 1.78 / (mx.y - mn.y)
	for k in npos.size():
		npos[k] = Vector3((npos[k].x - (mn.x + mx.x) / 2) * esc, (npos[k].y - mn.y) * esc, (npos[k].z - (mn.z + mx.z) / 2) * esc)
	print("reducido: ", npos.size(), " vértices, ", nidx.size() / 3, " triángulos")
	# Textura de color
	var mat: Material = im.get_surface_material(0)
	var tex: Texture2D = (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null
	var img: Image = tex.get_image() if tex else null
	if img:
		if img.is_compressed(): img.decompress()
		img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		img.save_png(salida + ".png")
	# OBJ + MTL (para subir a Mixamo en un zip)
	var nombre := salida.get_file()
	var f := FileAccess.open(salida + ".obj", FileAccess.WRITE)
	f.store_line("mtllib %s.mtl" % nombre)
	f.store_line("o soldado")
	for p in npos: f.store_line("v %.5f %.5f %.5f" % [p.x, p.y, p.z])
	for t in nuv: f.store_line("vt %.5f %.5f" % [t.x, 1.0 - t.y])
	f.store_line("usemtl piel")
	for k in range(0, nidx.size(), 3):
		var a := nidx[k] + 1; var b := nidx[k + 1] + 1; var c := nidx[k + 2] + 1
		f.store_line("f %d/%d %d/%d %d/%d" % [a, a, c, c, b, b])   # Godot gira al revés que OBJ
	f.close()
	var m := FileAccess.open(salida + ".mtl", FileAccess.WRITE)
	m.store_line("newmtl piel\nKd 1 1 1\nmap_Kd %s.png" % nombre)
	m.close()
	# GLB para mirarlo en el juego
	var sto := SurfaceTool.new()
	sto.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in npos.size():
		sto.set_uv(nuv[k]); sto.add_vertex(npos[k])
	for i in nidx: sto.add_index(i)
	sto.generate_normals()
	var malla := sto.commit()
	var smat := StandardMaterial3D.new()
	if img: smat.albedo_texture = ImageTexture.create_from_image(img)
	malla.surface_set_material(0, smat)
	var mi := MeshInstance3D.new()
	mi.mesh = malla
	mi.name = "soldado"
	var raiz := Node3D.new()
	raiz.add_child(mi); mi.owner = raiz
	var d2 := GLTFDocument.new(); var s2 := GLTFState.new()
	d2.append_from_scene(raiz, s2)
	d2.write_to_filesystem(s2, salida + ".glb")
	quit()
