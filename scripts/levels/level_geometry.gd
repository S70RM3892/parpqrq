@tool
class_name LevelGeometry
extends Node3D
## 箱・円柱・棒を材質ごとに1つのメッシュへまとめて置く（モバイル60fps：描画の呼び出しを減らす）。
## 区画（CHUNK m 四方）ごとに MeshInstance3D を1つ作り、材質ごとに1サーフェスにする。視界の外の区画は丸ごと省かれる。
## 当たり判定は区画×足音の素材ごとに StaticBody3D を1つ作り、形をまとめて入れる（メタデータ "surface" に素材）。
## 使い方: add_box / add_cylinder / add_beam で積んで、最後に build()。

const CHUNK := 40.0
const NO_COLLIDE := 1   ## 見た目だけ
const NO_VISUAL := 2    ## 当たり判定だけ（階段に重ねる見えない坂など）
const NO_SHADOW := 4    ## 影を落とさない（遠景・細い電線）

const Mat := LevelStyle.Mat

class _Surf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()

	func add(v: Vector3, n: Vector3, uv: Vector2, size: Vector2, c: Color, h: float, face: float, rnd: float) -> void:
		verts.append(v)
		normals.append(n)
		uvs.append(uv)
		uv2s.append(size)
		colors.append(c)
		custom.append_array([h, face, rnd, 0.0])



## key = Vector3i(chunk_x, chunk_z, mat * 2 + shadow)
var _surfs: Dictionary[Vector3i, _Surf] = {}
## key = "cx,cz,surface"
var _bodies: Dictionary[String, StaticBody3D] = {}
var _rng := RandomNumberGenerator.new()
var primitive_count: int = 0


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
	var meshes: Dictionary[Vector2i, ArrayMesh] = {}
	var shadowless: Dictionary[Vector2i, ArrayMesh] = {}
	for key: Vector3i in _surfs:
		var s := _surfs[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_TEX_UV2] = s.uv2s
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_CUSTOM0] = s.custom
		arrays[Mesh.ARRAY_INDEX] = s.indices
		var c := Vector2i(key.x, key.y)
		var casts := key.z % 2 == 1
		var table := meshes if casts else shadowless
		if not table.has(c):
			table[c] = ArrayMesh.new()
		var mesh := table[c]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
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


func clear() -> void:
	for c: Node in get_children():
		c.queue_free()
	_surfs.clear()
	_bodies.clear()
	primitive_count = 0


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


func _box_mesh(xf: Transform3D, size: Vector3, mat: int, flags: int, tint: Color) -> void:
	var s := _surf(xf.origin, mat, flags)
	var e := size * 0.5
	var b := xf.basis
	var rnd := _rng.randf()
	# 上面（u = x, v = z）
	_face(s, xf, b * Vector3.UP, [Vector3(-e.x, e.y, e.z), Vector3(e.x, e.y, e.z), Vector3(e.x, e.y, -e.z), Vector3(-e.x, e.y, -e.z)],
			Vector2(size.x, size.z), tint, [size.y, size.y, size.y, size.y], 1.0, rnd)
	# 下面
	_face(s, xf, b * Vector3.DOWN, [Vector3(-e.x, -e.y, -e.z), Vector3(e.x, -e.y, -e.z), Vector3(e.x, -e.y, e.z), Vector3(-e.x, -e.y, e.z)],
			Vector2(size.x, size.z), tint, [0.0, 0.0, 0.0, 0.0], 2.0, rnd)
	# 側面（u = 横、v = 下0→上1）
	var hs: Array[float] = [0.0, 0.0, size.y, size.y]
	_face(s, xf, b * Vector3.BACK, [Vector3(-e.x, -e.y, e.z), Vector3(e.x, -e.y, e.z), Vector3(e.x, e.y, e.z), Vector3(-e.x, e.y, e.z)],
			Vector2(size.x, size.y), tint, hs, 0.0, rnd)
	_face(s, xf, b * Vector3.FORWARD, [Vector3(e.x, -e.y, -e.z), Vector3(-e.x, -e.y, -e.z), Vector3(-e.x, e.y, -e.z), Vector3(e.x, e.y, -e.z)],
			Vector2(size.x, size.y), tint, hs, 0.0, rnd)
	_face(s, xf, b * Vector3.RIGHT, [Vector3(e.x, -e.y, e.z), Vector3(e.x, -e.y, -e.z), Vector3(e.x, e.y, -e.z), Vector3(e.x, e.y, e.z)],
			Vector2(size.z, size.y), tint, hs, 0.0, rnd)
	_face(s, xf, b * Vector3.LEFT, [Vector3(-e.x, -e.y, -e.z), Vector3(-e.x, -e.y, e.z), Vector3(-e.x, e.y, e.z), Vector3(-e.x, e.y, -e.z)],
			Vector2(size.z, size.y), tint, hs, 0.0, rnd)


## 4頂点（反時計回り：外から見て）の面。UV は 0,0 → 1,0 → 1,1 → 0,1
func _face(s: _Surf, xf: Transform3D, n: Vector3, corners: Array[Vector3], size: Vector2, tint: Color,
		hs: Array[float], face: float, rnd: float) -> void:
	var a := s.verts.size()
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i: int in 4:
		s.add(xf * corners[i], n, uvs[i], size, tint, hs[i], face, rnd)
	# Godot は時計回りが表（外から見て頂点が時計回り）なので逆順に張る
	s.indices.append_array([a, a + 2, a + 1, a, a + 3, a + 2])


func _cylinder_mesh(xf: Transform3D, r: float, height: float, mat: int, flags: int, tint: Color, sides: int) -> void:
	var s := _surf(xf.origin, mat, flags)
	var rnd := _rng.randf()
	var hh := height * 0.5
	var circ := TAU * r
	var b := xf.basis
	# 側面：隣どうしで頂点を分ける（UV の継ぎ目を持たせる）
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
		s.add(xf * (p0 + Vector3.DOWN * hh), n0, Vector2(u0, 0.0), size, tint, 0.0, 0.0, rnd)
		s.add(xf * (p1 + Vector3.DOWN * hh), n1, Vector2(u1, 0.0), size, tint, 0.0, 0.0, rnd)
		s.add(xf * (p1 + Vector3.UP * hh), n1, Vector2(u1, 1.0), size, tint, height, 0.0, rnd)
		s.add(xf * (p0 + Vector3.UP * hh), n0, Vector2(u0, 1.0), size, tint, height, 0.0, rnd)
		s.indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	# 上下のふた（扇形）
	for top: bool in [true, false]:
		var y := hh if top else -hh
		var n := b * (Vector3.UP if top else Vector3.DOWN)
		var center := s.verts.size()
		s.add(xf * Vector3(0.0, y, 0.0), n, Vector2(0.5, 0.5), Vector2(r * 2.0, r * 2.0), tint, height if top else 0.0, 1.0 if top else 2.0, rnd)
		for i: int in sides:
			var a := TAU * i / sides
			s.add(xf * Vector3(cos(a) * r, y, sin(a) * r), n, Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5),
					Vector2(r * 2.0, r * 2.0), tint, height if top else 0.0, 1.0 if top else 2.0, rnd)
		for i: int in sides:
			var i0 := center + 1 + i
			var i1 := center + 1 + (i + 1) % sides
			if top:
				s.indices.append_array([center, i0, i1])
			else:
				s.indices.append_array([center, i1, i0])
