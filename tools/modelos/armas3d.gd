extends SceneTree
## Construye las armas 3D con volumen a partir del atlas de perfiles
## (tools/modelos/armas3d.py). Cada píxel opaco del perfil se "extruye" con el
## grosor del arma: dos caras planas con la imagen y bordes del color del
## píxel de la orilla (los bordes seguidos se juntan para ahorrar triángulos).
##
## Uso: godot --headless --path . --script tools/modelos/armas3d.gd
## Escribe assets/armas/3d/<id>.res. Espacio del arma: el agarre (mano
## derecha) en el origen, el cañón hacia -Z, arriba +Y. Marcas en los meta
## "guardamanos", "boca" y "culata" (Vector3).

const DIR := "res://assets/armas/3d/"


func _init() -> void:
	var datos: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "armas.json"))
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(DIR + "atlas.png"))
	for id in datos:
		var d: Dictionary = datos[id]
		var malla := _construir(atlas, d)
		ResourceSaver.save(malla, DIR + id + ".res")
		print(id, ": ", malla.get_meta("triangulos"), " triángulos")
	quit()


func _construir(atlas: Image, d: Dictionary) -> ArrayMesh:
	var rx: int = d["rect"][0]
	var ry: int = d["rect"][1]
	var w: int = d["rect"][2]
	var h: int = d["rect"][3]
	var m: float = d["largo"] / float(w)          # metros por píxel
	var t: float = d["grosor"] / 2.0
	var g := Vector2(d["agarre"][0], d["agarre"][1])
	var aw := float(atlas.get_width())
	var ah := float(atlas.get_height())
	var lleno := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and atlas.get_pixel(rx + x, ry + y).a > 0.5
	# píxel (x, y) del recorte -> punto del arma (con lado X = ±t)
	var p := func(x: float, y: float, lado: float) -> Vector3:
		return Vector3(lado, -(y - g.y) * m, -(x - g.x) * m)
	var uv := func(x: float, y: float) -> Vector2:
		return Vector2((rx + x) / aw, (ry + y) / ah)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := 0
	# Caras planas (la transparencia la recorta el material)
	for lado in [t, -t]:
		var n := Vector3(signf(lado), 0, 0)
		tris += _quad(st, [p.call(0, 0, lado), p.call(w, 0, lado), p.call(w, h, lado), p.call(0, h, lado)],
			[uv.call(0, 0), uv.call(w, 0), uv.call(w, h), uv.call(0, h)], n)
	# Bordes horizontales (arriba / abajo de cada fila), juntando tramos seguidos
	for y in h:
		for arriba in [true, false]:
			var dy := -1 if arriba else 1
			var x := 0
			while x < w:
				if lleno.call(x, y) and not lleno.call(x, y + dy):
					var x0 := x
					while x < w and lleno.call(x, y) and not lleno.call(x, y + dy):
						x += 1
					var ye := float(y) if arriba else float(y + 1)
					var vc := float(y) + 0.5
					tris += _quad(st, [p.call(x0, ye, t), p.call(x, ye, t), p.call(x, ye, -t), p.call(x0, ye, -t)],
						[uv.call(x0 + 0.01, vc), uv.call(x - 0.01, vc), uv.call(x - 0.01, vc), uv.call(x0 + 0.01, vc)],
						Vector3(0, 1 if arriba else -1, 0))
				else:
					x += 1
	# Bordes verticales (hacia la culata / hacia la boca de cada columna)
	for x in w:
		for atras in [true, false]:
			var dx := -1 if atras else 1
			var y := 0
			while y < h:
				if lleno.call(x, y) and not lleno.call(x + dx, y):
					var y0 := y
					while y < h and lleno.call(x, y) and not lleno.call(x + dx, y):
						y += 1
					var xe := float(x) if atras else float(x + 1)
					var uc := float(x) + 0.5
					tris += _quad(st, [p.call(xe, y0, t), p.call(xe, y, t), p.call(xe, y, -t), p.call(xe, y0, -t)],
						[uv.call(uc, y0 + 0.01), uv.call(uc, y - 0.01), uv.call(uc, y - 0.01), uv.call(uc, y0 + 0.01)],
						Vector3(0, 0, 1 if atras else -1))
				else:
					y += 1
	st.index()
	var malla := st.commit()
	malla.set_meta("triangulos", tris)
	for marca in ["guardamanos", "boca", "culata"]:
		malla.set_meta(marca, p.call(d[marca][0], d[marca][1], 0.0))
	return malla


## Agrega un cuadrilátero con la normal "n" (ordena los vértices para que
## la cara visible sea la de afuera).
func _quad(st: SurfaceTool, v: Array, u: Array, n: Vector3) -> int:
	var orden := [0, 1, 2, 0, 2, 3]
	if (v[1] - v[0]).cross(v[2] - v[0]).dot(n) > 0.0:
		orden = [0, 2, 1, 0, 3, 2]
	for i in orden:
		st.set_normal(n)
		st.set_uv(u[i])
		st.add_vertex(v[i])
	return 2
