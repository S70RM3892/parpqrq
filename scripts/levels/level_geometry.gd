@tool
class_name LevelGeometry
extends Node3D
## 箱・円柱・棒を材質ごとに1つのメッシュへまとめて置く（モバイル60fps：描画の呼び出しを減らす）。
## 区画（CHUNK m 四方）ごとに MeshInstance3D を1つ作り、材質ごとに1サーフェスにする。視界の外の区画は丸ごと省かれる。
## 当たり判定は区画×足音の素材ごとに StaticBody3D を1つ作り、形をまとめて入れる（メタデータ "surface" に素材）。
## 使い方: add_box / add_cylinder / add_beam で積んで、最後に build()。
##
## 焼いた光（ライトマップ）：build() の時に、面ごとにアトラスの中の場所を決めて頂点（CUSTOM1）に書く。
## 中身は tools/bake_lighting.tscn が焼き（tools/lightbaker/）、LevelLighting が読み込む。
## 場所の決め方は積んだ順と形だけで決まるので、同じレシピなら焼いた時と同じになる（lightmap_hash で確かめる）。

const CHUNK := 40.0
const NO_COLLIDE := 1   ## 見た目だけ
const NO_VISUAL := 2    ## 当たり判定だけ（階段に重ねる見えない坂など）
const NO_SHADOW := 4    ## 影を落とさない（遠景・細い電線）。光も焼かない

## ライトマップの細かさ（画素/m）。屋上・小物、ビルの壁の上の帯、それより下の壁（霧で消える所）
const LM_DENSITY := 4.0
const LM_DENSITY_SIDE := 3.0
const LM_DENSITY_LOW := 0.35
## ビルの壁は屋上からこの高さまでを細かく焼く
const LM_BAND := 9.0
const LM_ATLAS_W := 2048
const LM_MAX_TEXELS := 1024
## これより細い円柱（電線・手すり・柱）は焼かない（遮るだけ）
const LM_MIN_RADIUS := 0.25

const Mat := LevelStyle.Mat

class _Surf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var custom := PackedFloat32Array()
	var lm := PackedFloat32Array()  ## CUSTOM1：ライトマップの uv（焼かない面は -1）
	var tangents := PackedFloat32Array()  ## 面の u の向き（xyz）と、v の向きの符号（w）。法線マップ用
	var indices := PackedInt32Array()

	func add(v: Vector3, n: Vector3, uv: Vector2, size: Vector2, c: Color, h: float, face: float, rnd: float,
			t: Vector3 = Vector3.RIGHT, tw: float = 1.0) -> void:
		verts.append(v)
		normals.append(n)
		tangents.append_array([t.x, t.y, t.z, tw])
		uvs.append(uv)
		uv2s.append(size)
		colors.append(c)
		custom.append_array([h, face, rnd, 0.0])
		lm.append_array([-1.0, -1.0])


## 焼く・遮る面。corners は世界座標（uv (0,0) (1,0) (1,1) (0,1) の順）
class _LmFace:
	var surf: _Surf
	var v0: int                 ## surf の中の最初の頂点（4つ並ぶ）
	var corners: PackedVector3Array
	var uv_v: Vector2           ## 面の中の v の範囲（ビルの壁を上下に分けた時）
	var normal: Vector3
	var texels: Vector2i        ## 焼く画素数（0 = 焼かない）
	var rect: Rect2i            ## アトラスの中の場所（内側）
	var mat: int
	var tint: Color


## key = Vector3i(chunk_x, chunk_z, mat * 2 + shadow)
var _surfs: Dictionary[Vector3i, _Surf] = {}
## key = "cx,cz,surface"
var _bodies: Dictionary[String, StaticBody3D] = {}
var _rng := RandomNumberGenerator.new()
var primitive_count: int = 0

var _lm_faces: Array[_LmFace] = []
## 遮るだけの三角形（円柱のふた）。[a, b, c, mat, tint] の並び
var _lm_tris: Array = []
## ライトマップのアトラスの大きさと、面の並びの指紋（焼いた時と同じ形か）
var lightmap_size: Vector2i = Vector2i.ZERO
var lightmap_hash: String = ""
## 焼く道具だけが true にする（build() の後も面の一覧を残して write_bake_input に使う）
var keep_bake_data: bool = false


func _init() -> void:
	_rng.seed = 7


## center = 箱の中心、size = 大きさ、rot_deg = 回転（度、YXZ順：Node3D.rotation_degrees と同じ）
func add_box(center: Vector3, size: Vector3, mat: int, rot_deg: Vector3 = Vector3.ZERO, flags: int = 0,
		tint: Color = Color.WHITE, surface: StringName = &"") -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	var xf := Transform3D(b, center)
	if flags & NO_VISUAL == 0:
		_box_mesh(xf, size, mat, flags, tint)
	if flags & NO_COLLIDE == 0:
		var shape := BoxShape3D.new()
		shape.size = size
		_collider(xf, shape, surface if surface != &"" else LevelStyle.SURFACE[mat])
	primitive_count += 1


## 縦の円柱（rot_deg で倒せる）。center = 中心
func add_cylinder(center: Vector3, radius: float, height: float, mat: int, rot_deg: Vector3 = Vector3.ZERO,
		flags: int = 0, tint: Color = Color.WHITE, sides: int = 12) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	var xf := Transform3D(b, center)
	if flags & NO_VISUAL == 0:
		_cylinder_mesh(xf, radius, height, mat, flags, tint, sides)
	if flags & NO_COLLIDE == 0:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_collider(xf, shape, LevelStyle.SURFACE[mat])
	primitive_count += 1


## a から b への棒（電線・パイプ・手すり）。既定では当たり判定なし
func add_beam(a: Vector3, b: Vector3, radius: float, mat: int, flags: int = NO_COLLIDE, sides: int = 6,
		tint: Color = Color.WHITE) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var xf := Transform3D(Basis(x, y, z), (a + b) * 0.5)
	if flags & NO_VISUAL == 0:
		_cylinder_mesh(xf, radius, length, mat, flags, tint, sides)
	if flags & NO_COLLIDE == 0:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = length
		_collider(xf, shape, LevelStyle.SURFACE[mat])
	primitive_count += 1


## 積んだものをメッシュにして置く
func build() -> void:
	_pack_lightmap()
	var meshes: Dictionary[Vector2i, ArrayMesh] = {}
	var shadowless: Dictionary[Vector2i, ArrayMesh] = {}
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	for key: Vector3i in _surfs:
		var s := _surfs[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TANGENT] = s.tangents
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_TEX_UV2] = s.uv2s
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_CUSTOM0] = s.custom
		arrays[Mesh.ARRAY_CUSTOM1] = s.lm
		arrays[Mesh.ARRAY_INDEX] = s.indices
		var c := Vector2i(key.x, key.y)
		var casts := key.z % 2 == 1
		var table := meshes if casts else shadowless
		if not table.has(c):
			table[c] = ArrayMesh.new()
		var mesh := table[c]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		mesh.surface_set_material(mesh.get_surface_count() - 1, LevelStyle.material(key.z / 2))
	for table: Dictionary in [meshes, shadowless]:
		for c: Vector2i in table:
			var mi := MeshInstance3D.new()
			mi.mesh = table[c]
			mi.name = "Chunk_%d_%d%s" % [c.x, c.y, "" if table == meshes else "_ns"]
			if table != meshes:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	_surfs.clear()
	if not keep_bake_data:
		_lm_faces.clear()
		_lm_tris.clear()


func clear() -> void:
	for c: Node in get_children():
		c.queue_free()
	_surfs.clear()
	_bodies.clear()
	_lm_faces.clear()
	_lm_tris.clear()
	primitive_count = 0


# --- ライトマップ -------------------------------------------------------------

## 面にアトラスの場所を割り当てて頂点に書く（棚詰め。高い順に並べ、同じ高さは積んだ順）
func _pack_lightmap() -> void:
	var order: Array[int] = []
	for i: int in _lm_faces.size():
		if _lm_faces[i].texels.x > 0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ta := _lm_faces[a].texels
		var tb := _lm_faces[b].texels
		if ta.y != tb.y:
			return ta.y > tb.y
		if ta.x != tb.x:
			return ta.x > tb.x
		return a < b)
	var x := 0
	var y := 0
	var shelf := 0
	for i: int in order:
		var f := _lm_faces[i]
		var w := f.texels.x + 2  # 周りに1画素の縁取り
		var h := f.texels.y + 2
		if x + w > LM_ATLAS_W:
			x = 0
			y += shelf
			shelf = 0
		f.rect = Rect2i(x + 1, y + 1, f.texels.x, f.texels.y)
		x += w
		shelf = maxi(shelf, h)
	var height := y + shelf
	height = maxi(4, (height + 3) / 4 * 4)
	lightmap_size = Vector2i(LM_ATLAS_W, height) if not order.is_empty() else Vector2i.ZERO
	var fingerprint := PackedFloat32Array()
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i: int in order:
		var f := _lm_faces[i]
		var r := f.rect
		for k: int in 4:
			var u := r.position.x + 0.5 + uvs[k].x * (r.size.x - 1)
			var v := r.position.y + 0.5 + uvs[k].y * (r.size.y - 1)
			f.surf.lm[(f.v0 + k) * 2] = u / lightmap_size.x
			f.surf.lm[(f.v0 + k) * 2 + 1] = v / lightmap_size.y
			var p := f.corners[k]
			fingerprint.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		fingerprint.append_array([r.position.x, r.position.y, r.size.x, r.size.y, f.mat])
	if order.is_empty():
		lightmap_hash = ""
		return
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update(fingerprint.to_byte_array())
	lightmap_hash = hc.finish().hex_encode()


## 焼く道具（tools/bake_lighting.gd）に渡す中身を書く。build() の後に呼ぶ。形式は tools/lightbaker/lightbaker.cpp の read_input
func write_bake_input(path: String, sun_dir: Vector3, sun_color: Color, sky_top: Color, sky_horizon: Color,
		sky_ground: Color, samples: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("LMB1".to_ascii_buffer())
	f.store_32(lightmap_size.x)
	f.store_32(lightmap_size.y)
	var v3 := func(v: Vector3) -> void:
		f.store_float(v.x)
		f.store_float(v.y)
		f.store_float(v.z)
	var col := func(c: Color) -> void:
		f.store_float(c.r)
		f.store_float(c.g)
		f.store_float(c.b)
	v3.call(sun_dir.normalized())
	col.call(sun_color)
	col.call(sky_top)
	col.call(sky_horizon)
	col.call(sky_ground)
	f.store_32(samples)
	f.store_32(_lm_faces.size())
	for lf: _LmFace in _lm_faces:
		for k: int in 4:
			v3.call(lf.corners[k])
		v3.call(lf.normal)
		if lf.texels.x > 0:
			f.store_32(lf.rect.position.x)
			f.store_32(lf.rect.position.y)
			f.store_32(lf.rect.size.x)
			f.store_32(lf.rect.size.y)
		else:
			for k: int in 4:
				f.store_32(-1)
		col.call(LevelStyle.bake_albedo(lf.mat, lf.tint))
		col.call(LevelStyle.bake_emission(lf.mat, lf.tint))
	f.store_32(_lm_tris.size())
	for t: Array in _lm_tris:
		v3.call(t[0])
		v3.call(t[1])
		v3.call(t[2])
		col.call(LevelStyle.bake_albedo(t[3], t[4]))
		col.call(LevelStyle.bake_emission(t[3], t[4]))
	f.close()


func _texels(size: Vector2, density: float) -> Vector2i:
	if density <= 0.0:
		return Vector2i.ZERO
	return Vector2i(clampi(ceili(size.x * density), 2, LM_MAX_TEXELS), clampi(ceili(size.y * density), 2, LM_MAX_TEXELS))


# --- 中身 -----------------------------------------------------------------

func _surf(center: Vector3, mat: int, flags: int) -> _Surf:
	var key := Vector3i(floori(center.x / CHUNK), floori(center.z / CHUNK), mat * 2 + (0 if flags & NO_SHADOW else 1))
	if not _surfs.has(key):
		_surfs[key] = _Surf.new()
	return _surfs[key]


func _collider(xf: Transform3D, shape: Shape3D, surface: StringName) -> void:
	var key := "%d,%d,%s" % [floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK), surface]
	var body: StaticBody3D = _bodies.get(key)
	if body == null:
		body = StaticBody3D.new()
		body.name = "Body_" + key.replace(",", "_")
		body.set_meta(&"surface", surface)
		_bodies[key] = body
		add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


## 焼くかどうかと細かさ（発光する物・影を落とさない物は焼かない）
func _bakes(mat: int, flags: int) -> bool:
	return flags & NO_SHADOW == 0 and mat != Mat.LIGHT


func _box_mesh(xf: Transform3D, size: Vector3, mat: int, flags: int, tint: Color) -> void:
	var s := _surf(xf.origin, mat, flags)
	var e := size * 0.5
	var b := xf.basis
	var rnd := _rng.randf()
	var bake := _bakes(mat, flags)
	var d_top := LM_DENSITY if bake else 0.0
	# 上面（u = x, v = z）
	_face(s, xf, b * Vector3.UP, [Vector3(-e.x, e.y, e.z), Vector3(e.x, e.y, e.z), Vector3(e.x, e.y, -e.z), Vector3(-e.x, e.y, -e.z)],
			Vector2(size.x, size.z), tint, [size.y, size.y, size.y, size.y], 1.0, rnd, mat, flags, d_top)
	# 下面
	_face(s, xf, b * Vector3.DOWN, [Vector3(-e.x, -e.y, -e.z), Vector3(e.x, -e.y, -e.z), Vector3(e.x, -e.y, e.z), Vector3(-e.x, -e.y, e.z)],
			Vector2(size.x, size.z), tint, [0.0, 0.0, 0.0, 0.0], 2.0, rnd, mat, flags, d_top)
	# 側面（u = 横、v = 下0→上1）。高いビルの壁は、屋上から LM_BAND までを細かく、それより下を粗く焼くため上下に分ける
	var sides: Array = [
		[Vector3.BACK, [Vector3(-e.x, -e.y, e.z), Vector3(e.x, -e.y, e.z), Vector3(e.x, e.y, e.z), Vector3(-e.x, e.y, e.z)], size.x],
		[Vector3.FORWARD, [Vector3(e.x, -e.y, -e.z), Vector3(-e.x, -e.y, -e.z), Vector3(-e.x, e.y, -e.z), Vector3(e.x, e.y, -e.z)], size.x],
		[Vector3.RIGHT, [Vector3(e.x, -e.y, e.z), Vector3(e.x, -e.y, -e.z), Vector3(e.x, e.y, -e.z), Vector3(e.x, e.y, e.z)], size.z],
		[Vector3.LEFT, [Vector3(-e.x, -e.y, -e.z), Vector3(-e.x, -e.y, e.z), Vector3(-e.x, e.y, e.z), Vector3(-e.x, e.y, -e.z)], size.z],
	]
	var split := bake and size.y > LM_BAND + 3.0
	var k := (size.y - LM_BAND) / size.y if split else 0.0
	for sd: Array in sides:
		var n: Vector3 = sd[0]
		var c: Array = sd[1]
		var face_size := Vector2(sd[2] as float, size.y)
		if not split:
			_face(s, xf, b * n, c, face_size, tint, [0.0, 0.0, size.y, size.y], 0.0, rnd, mat, flags,
					(LM_DENSITY_SIDE if size.y > 3.0 else LM_DENSITY) if bake else 0.0)
			continue
		var m0: Vector3 = (c[0] as Vector3).lerp(c[3], k)
		var m1: Vector3 = (c[1] as Vector3).lerp(c[2], k)
		var hk := size.y * k
		_face(s, xf, b * n, [c[0], c[1], m1, m0], face_size, tint, [0.0, 0.0, hk, hk], 0.0, rnd, mat, flags,
				LM_DENSITY_LOW, Vector2(0.0, k))
		_face(s, xf, b * n, [m0, m1, c[2], c[3]], face_size, tint, [hk, hk, size.y, size.y], 0.0, rnd, mat, flags,
				LM_DENSITY_SIDE, Vector2(k, 1.0))


## 4頂点（反時計回り：外から見て）の面。UV は 0,v0 → 1,v0 → 1,v1 → 0,v1（uv_v = (v0, v1)、面を分けた時の範囲）。
## density > 0 なら光を焼く（画素/m）
func _face(s: _Surf, xf: Transform3D, n: Vector3, corners: Array, size: Vector2, tint: Color,
		hs: Array, face: float, rnd: float, mat: int, flags: int, density: float,
		uv_v: Vector2 = Vector2(0.0, 1.0)) -> void:
	var a := s.verts.size()
	var uvs: Array[Vector2] = [Vector2(0, uv_v.x), Vector2(1, uv_v.x), Vector2(1, uv_v.y), Vector2(0, uv_v.y)]
	var world := PackedVector3Array()
	for i: int in 4:
		world.append(xf * (corners[i] as Vector3))
	# 接線 = 面の u の向き。Godot は binormal = cross(normal, tangent) * w
	var tu := (world[1] - world[0]).normalized()
	var tv := (world[3] - world[0]).normalized()
	var tw := 1.0 if n.cross(tu).dot(tv) >= 0.0 else -1.0
	for i: int in 4:
		s.add(world[i], n, uvs[i], size, tint, hs[i] as float, face, rnd, tu, tw)
	# Godot は時計回りが表（外から見て頂点が時計回り）なので逆順に張る
	s.indices.append_array([a, a + 2, a + 1, a, a + 3, a + 2])
	if flags & NO_SHADOW:
		return
	var lf := _LmFace.new()
	lf.surf = s
	lf.v0 = a
	lf.corners = world
	lf.uv_v = uv_v
	lf.normal = n.normalized()
	lf.texels = _texels(Vector2(size.x, size.y * (uv_v.y - uv_v.x)), density)
	lf.mat = mat
	lf.tint = tint
	_lm_faces.append(lf)


func _cylinder_mesh(xf: Transform3D, r: float, height: float, mat: int, flags: int, tint: Color, sides: int) -> void:
	var s := _surf(xf.origin, mat, flags)
	var rnd := _rng.randf()
	var hh := height * 0.5
	var circ := TAU * r
	var b := xf.basis
	var density := LM_DENSITY if _bakes(mat, flags) and r >= LM_MIN_RADIUS else 0.0
	# 側面：隣どうしで頂点を分ける（UV の継ぎ目を持たせる）。1面ずつ光を焼く
	for i: int in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var n0 := (b * Vector3(cos(a0), 0.0, sin(a0))).normalized()
		var n1 := (b * Vector3(cos(a1), 0.0, sin(a1))).normalized()
		var u0 := float(i) / sides
		var u1 := float(i + 1) / sides
		var base := s.verts.size()
		var size := Vector2(circ, height)
		var world := PackedVector3Array([xf * (p0 + Vector3.DOWN * hh), xf * (p1 + Vector3.DOWN * hh),
				xf * (p1 + Vector3.UP * hh), xf * (p0 + Vector3.UP * hh)])
		var tu := (world[1] - world[0]).normalized()
		var tv := (world[3] - world[0]).normalized()
		var tw := 1.0 if n0.cross(tu).dot(tv) >= 0.0 else -1.0
		s.add(world[0], n0, Vector2(u0, 0.0), size, tint, 0.0, 0.0, rnd, tu, tw)
		s.add(world[1], n1, Vector2(u1, 0.0), size, tint, 0.0, 0.0, rnd, tu, tw)
		s.add(world[2], n1, Vector2(u1, 1.0), size, tint, height, 0.0, rnd, tu, tw)
		s.add(world[3], n0, Vector2(u0, 1.0), size, tint, height, 0.0, rnd, tu, tw)
		s.indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		if flags & NO_SHADOW == 0:
			var lf := _LmFace.new()
			lf.surf = s
			lf.v0 = base
			lf.corners = world
			lf.uv_v = Vector2(0.0, 1.0)
			lf.normal = (n0 + n1).normalized()
			lf.texels = _texels(Vector2(circ / sides, height), density)
			lf.mat = mat
			lf.tint = tint
			_lm_faces.append(lf)
	# 上下のふた（扇形）。光は焼かず、遮るだけ
	for top: bool in [true, false]:
		var y := hh if top else -hh
		var n := b * (Vector3.UP if top else Vector3.DOWN)
		var center := s.verts.size()
		var cp := xf * Vector3(0.0, y, 0.0)
		var ct := b.x.normalized()
		var cz := b.z.normalized()
		var ctw := 1.0 if n.cross(ct).dot(cz) >= 0.0 else -1.0
		s.add(cp, n, Vector2(0.5, 0.5), Vector2(r * 2.0, r * 2.0), tint, height if top else 0.0, 1.0 if top else 2.0, rnd, ct, ctw)
		var rim := PackedVector3Array()
		for i: int in sides:
			var a := TAU * i / sides
			var p := xf * Vector3(cos(a) * r, y, sin(a) * r)
			rim.append(p)
			s.add(p, n, Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5),
					Vector2(r * 2.0, r * 2.0), tint, height if top else 0.0, 1.0 if top else 2.0, rnd, ct, ctw)
		for i: int in sides:
			var i0 := center + 1 + i
			var i1 := center + 1 + (i + 1) % sides
			if top:
				s.indices.append_array([center, i0, i1])
			else:
				s.indices.append_array([center, i1, i0])
			if flags & NO_SHADOW == 0:
				var q0 := rim[i]
				var q1 := rim[(i + 1) % sides]
				# 外から見て反時計回り（法線が外向きになる順）
				if top:
					_lm_tris.append([cp, q1, q0, mat, tint])
				else:
					_lm_tris.append([cp, q0, q1, mat, tint])
