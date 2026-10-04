extends SceneTree
## 元モデル（assets/source/*.glb、Meshy製・骨格なし）から、ゲームで使う軽いメッシュを作る。
##   godot --headless --path . -s tools/build_body.gd
## - ポリゴンを目標数まで削減（モバイル60fps用）
## - テクスチャを1024pxに縮小
## - 脚は膝・足首の関節ディスク中心で3分割し、各パーツの原点を関節に置く
##   （ディスク中心を軸に回すので、曲げても円が重なったまま継ぎ目が出にくい）
## - 向きをGodotの前方(-Z)にそろえ、実寸に拡大縮小する
## 出力: assets/body/*.res（メッシュ）、assets/body/textures/*.png

const SRC := "res://assets/source/"
const OUT := "res://assets/body/"
const TEX_SIZE := 1024

# 脚：元モデル座標での関節（側面図から計測）。つま先は+Z向き
const LEG_HIP := Vector3(0.0, 0.80, -0.07)
const LEG_KNEE := Vector3(0.0, 0.11, -0.02)
const LEG_ANKLE := Vector3(0.0, -0.787, -0.13)
const LEG_LENGTH_M := 0.88       ## 股関節〜足裏
const LEG_TARGET_TRIS := 12000

# 手：前腕の袖口〜指先
const HAND_LENGTH_M := 0.40
const HAND_TARGET_TRIS := 14000
const HAND_ROLL_DEG := 0.0       ## 主軸まわりの回転。手の甲が上(+Y)になる値


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "textures"))
	_build_leg()
	_build_hand()
	print("build_body: done")
	quit()


func _build_leg() -> void:
	var src := _load(SRC + "leg.glb", "leg")
	var arrays: Array = src.arrays
	var idx := _decimate(arrays, LEG_TARGET_TRIS)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ymin := INF
	for p: Vector3 in v:
		ymin = minf(ymin, p.y)
	var s := LEG_LENGTH_M / (LEG_HIP.y - ymin)
	var flip := Basis(Vector3.UP, PI)  # つま先を-Zへ
	var parts := {"thigh": PackedInt32Array(), "shin": PackedInt32Array(), "foot": PackedInt32Array()}
	for t: int in range(0, idx.size(), 3):
		var cy := (v[idx[t]].y + v[idx[t + 1]].y + v[idx[t + 2]].y) / 3.0
		var key := "thigh" if cy > LEG_KNEE.y else ("shin" if cy > LEG_ANKLE.y else "foot")
		parts[key].append_array([idx[t], idx[t + 1], idx[t + 2]])
	var pivots := {"thigh": LEG_HIP, "shin": LEG_KNEE, "foot": LEG_ANKLE}
	for key: String in parts:
		var xf := Transform3D(flip.scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivots[key])
		var mesh := _make_mesh(arrays, parts[key], xf)
		ResourceSaver.save(mesh, OUT + "leg_%s.res" % key)
		print("leg_%s: %d tris" % [key, parts[key].size() / 3])
	# 関節間の距離（ゲーム側で親子を組む時に使う）
	var to_game := func(p: Vector3) -> Vector3: return flip * (p * s)
	print("leg knee offset from hip: ", to_game.call(LEG_KNEE - LEG_HIP))
	print("leg ankle offset from knee: ", to_game.call(LEG_ANKLE - LEG_KNEE))
	print("leg sole below ankle: ", (LEG_ANKLE.y - ymin) * s)


func _build_hand() -> void:
	var src := _load(SRC + "hand_r.glb", "hand")
	var arrays: Array = src.arrays
	var idx := _decimate(arrays, HAND_TARGET_TRIS)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 主軸（PCA）を求め、袖口→指先の向きにそろえる
	var c := Vector3.ZERO
	for p: Vector3 in v:
		c += p
	c /= v.size()
	var axis := _principal_axis(v, c)
	if axis.dot(Vector3(1, 1, -1)) < 0.0:  # 指先は元モデルの(+x,+y,-z)側
		axis = -axis
	var lo := INF
	var hi := -INF
	for p: Vector3 in v:
		var d := (p - c).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	# 袖口の中心を原点に
	var cuff := Vector3.ZERO
	var n := 0
	for p: Vector3 in v:
		if (p - c).dot(axis) < lo + (hi - lo) * 0.05:
			cuff += p
			n += 1
	cuff /= n
	var s := HAND_LENGTH_M / (hi - lo)
	# axis → -Z に回す
	var rot := Basis(Quaternion(axis, Vector3.FORWARD))
	rot = Basis(Vector3.FORWARD, deg_to_rad(HAND_ROLL_DEG)) * rot
	var xf := Transform3D(rot.scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -cuff)
	var mesh := _make_mesh(arrays, idx, xf)
	# 手のひらの中心（指の付け根付近、袖口から75%）
	var palm := Vector3.ZERO
	n = 0
	for p: Vector3 in v:
		var d := ((p - c).dot(axis) - lo) / (hi - lo)
		if d > 0.70 and d < 0.80:
			palm += p
			n += 1
	palm = xf * (palm / n)
	mesh.set_meta(&"palm", palm)
	ResourceSaver.save(mesh, OUT + "hand_r.res")
	print("hand_r: %d tris, palm at %s" % [idx.size() / 3, palm])


## 頂点を変換し、使われている頂点だけ詰めてタンジェント付きのメッシュにする
func _make_mesh(arrays: Array, idx: PackedInt32Array, xf: Transform3D) -> ArrayMesh:
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	var nb := xf.basis.orthonormalized()
	for i: int in idx:
		if not remap.has(i):
			remap[i] = nv.size()
			nv.append(xf * src_v[i])
			nn.append((nb * src_n[i]).normalized())
			nuv.append(src_uv[i])
		ni.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_TEX_UV] = nuv
	out[Mesh.ARRAY_INDEX] = ni
	var st := SurfaceTool.new()
	st.create_from_arrays(out)
	st.generate_tangents()
	st.optimize_indices_for_cache()
	return st.commit()


func _decimate(arrays: Array, target_tris: int) -> PackedInt32Array:
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lod := st.generate_lod(25.0, target_tris * 3)
	print("  decimate %d -> %d tris" % [full.size() / 3, lod.size() / 3])
	return lod


func _principal_axis(v: PackedVector3Array, c: Vector3) -> Vector3:
	var xx := 0.0; var xy := 0.0; var xz := 0.0; var yy := 0.0; var yz := 0.0; var zz := 0.0
	for p: Vector3 in v:
		var d := p - c
		xx += d.x * d.x; xy += d.x * d.y; xz += d.x * d.z
		yy += d.y * d.y; yz += d.y * d.z; zz += d.z * d.z
	var m := Basis(Vector3(xx, xy, xz), Vector3(xy, yy, yz), Vector3(xz, yz, zz))
	var a := Vector3(1, 1, -1).normalized()
	for i: int in 50:
		a = (m * a).normalized()
	return a


## glbを読み、配列とテクスチャ（縮小してPNG保存）を返す
func _load(path: String, tex_prefix: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	assert(err == OK, "cannot load %s" % path)
	var im: ImporterMesh = state.get_meshes()[0].mesh
	var mat := im.get_surface_material(0) as BaseMaterial3D
	var maps := {
		"albedo": mat.albedo_texture,
		"orm": mat.roughness_texture,  # glTFのmetallicRoughness（G=粗さ, B=金属）
		"normal": mat.normal_texture,
	}
	for k: String in maps:
		var tex := maps[k] as Texture2D
		var img := tex.get_image()
		img.decompress()
		img.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT + "textures/%s_%s.png" % [tex_prefix, k]))
	return {"arrays": im.get_surface_arrays(0)}
