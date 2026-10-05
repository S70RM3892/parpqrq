class_name FirstPersonHand
extends Node3D
## 1人称の手（仕様書 4章「手が先に触れる」）。白い装甲と黒い関節の、指の曲がる機械の手（脚の機械脚とそろえる）。
## メッシュは実行時に手続き的に作る（角を丸めた箱と、太さの変わるカプセル）。指は3節ずつ関節で曲がる。
## 原点 = 袖口、-Z = 指先、+Y = 手の甲。右手の形（左手は親が x を反転して使う）。
## 姿勢は set_pose(握り, 開き, 親指) の3つの値で決める（arms.gd が状態ごとに選んで、なめらかに寄せる）。
## 描画の呼び出しを減らすため、関節ごとに部品を1つのメッシュにまとめ、材質は頂点色で描き分ける（shaders/hand.gdshader）。

const WRIST_Z := -0.21                          ## 手首（袖口から前へ）
const PALM := Vector3(0.0, -0.017, -0.262)      ## 手のひらの中心（面に着く点）
const PALM_SIZE := Vector3(0.084, 0.03, 0.1)

## 指：[付け根の位置, [基節, 中節, 末節] の長さ, 太さ, 曲がりやすさ]（右手。親指は -X 側）
const FINGERS: Array = [
	[Vector3(-0.029, 0.002, -0.308), [0.042, 0.025, 0.020], 0.0098, 1.0],   # 人差し指
	[Vector3(-0.0095, 0.003, -0.313), [0.046, 0.029, 0.021], 0.0102, 1.0],  # 中指
	[Vector3(0.0105, 0.002, -0.309), [0.043, 0.027, 0.020], 0.0098, 1.04],  # 薬指
	[Vector3(0.029, 0.0, -0.300), [0.034, 0.020, 0.018], 0.0088, 1.1],      # 小指
]
const THUMB_ROOT := Vector3(-0.034, -0.008, -0.232)
const THUMB_LENGTHS := [0.036, 0.030, 0.025]

## 材質の番号（頂点色の a）。hand.gdshader と同じ
const ARMOR := 0.0
const JOINT := 1.0
const ACCENT := 2.0
const PAD := 3.0
const SLEEVE := 4.0
const COLORS: Dictionary[float, Color] = {
	ARMOR: Color(0.9, 0.9, 0.88), JOINT: Color(0.07, 0.075, 0.085), ACCENT: Color(1.0, 0.42, 0.1),
	PAD: Color(0.04, 0.04, 0.045), SLEEVE: Color(0.14, 0.145, 0.16),
}

static var _material: ShaderMaterial
static var _mesh_cache: Dictionary[String, ArrayMesh] = {}

## 指の関節（[基節, 中節, 末節] の Node3D）。最後が親指
var _joints: Array[Array] = []
var _curl: float = 0.5
var _spread: float = 0.0
var _thumb: float = 0.5


func _ready() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/hand.gdshader")
	_build()
	set_pose(0.5, 0.0, 0.5)


## 握り（0 = 伸ばす、1 = 握る。少しマイナスで反らせる）、開き（指の間）、親指（0 = 開く、1 = 握る）
func set_pose(curl: float, spread: float, thumb: float) -> void:
	_curl = curl
	_spread = spread
	_thumb = thumb
	var yaws: Array[float] = [8.0, 2.0, -4.0, -10.0]
	for i: int in 4:
		var j: Array = _joints[i]
		var k: float = FINGERS[i][3]
		var c := curl * k
		(j[0] as Node3D).rotation = Vector3(deg_to_rad(-82.0 * c), deg_to_rad(yaws[i] * spread), 0.0)
		(j[1] as Node3D).rotation = Vector3(deg_to_rad(-98.0 * maxf(c, -0.1)), 0.0, 0.0)
		(j[2] as Node3D).rotation = Vector3(deg_to_rad(-62.0 * maxf(c, -0.1)), 0.0, 0.0)
	var t: Array = _joints[4]
	(t[0] as Node3D).rotation = Vector3(deg_to_rad(-20.0 * thumb), deg_to_rad(55.0 - 35.0 * thumb), deg_to_rad(-70.0 - 20.0 * thumb))
	(t[1] as Node3D).rotation = Vector3(deg_to_rad(-55.0 * thumb), 0.0, 0.0)
	(t[2] as Node3D).rotation = Vector3(deg_to_rad(-50.0 * thumb), 0.0, 0.0)


## 今の姿勢から目標へ w だけ寄せる
func blend_pose(curl: float, spread: float, thumb: float, w: float) -> void:
	set_pose(lerpf(_curl, curl, w), lerpf(_spread, spread, w), lerpf(_thumb, thumb, w))


# --- 形 -----------------------------------------------------------------------

func _build() -> void:
	_add_mesh(self, _cached("base", _base_mesh))
	for i: int in FINGERS.size():
		var f: Array = FINGERS[i]
		_joints.append(_finger("f%d" % i, f[0], f[1], f[2]))
	_joints.append(_finger("thumb", THUMB_ROOT, THUMB_LENGTHS, 0.0108))


## 二の腕・肘・前腕・手のひら（指以外）を1つのメッシュに
func _base_mesh() -> ArrayMesh:
	var st := _begin()
	# 袖口から肘・二の腕へ：黒い下地に白い装甲の板（ぶら下がると腕が画面に大きく入るので、布の筒にしない）
	_capsule(st, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.13)), 0.043, 0.036, 0.15, 0.8, JOINT)
	_box(st, _xf(Vector3(0, 0.031, 0.05), Vector3(2.0, 0, 0)), Vector3(0.066, 0.016, 0.13), 0.007, ARMOR)
	for sx: float in [-1.0, 1.0]:
		_box(st, _xf(Vector3(sx * 0.037, 0.004, 0.055), Vector3.ZERO), Vector3(0.014, 0.042, 0.12), 0.005, ARMOR)
	# 肘：黒い関節にオレンジの細い輪、肘の当て
	_capsule(st, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.19)), 0.048, 0.048, 0.055, 1.0, JOINT)
	_capsule(st, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.166)), 0.0495, 0.0495, 0.006, 1.0, ACCENT)
	_box(st, _xf(Vector3(0, 0.04, 0.165), Vector3(-8.0, 0, 0)), Vector3(0.052, 0.014, 0.045), 0.006, ARMOR)
	# 二の腕
	_capsule(st, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.52)), 0.057, 0.049, 0.33, 0.85, JOINT)
	_box(st, _xf(Vector3(0, 0.044, 0.35), Vector3(-1.5, 0, 0)), Vector3(0.076, 0.02, 0.27), 0.009, ARMOR)
	_box(st, _xf(Vector3(0.022, 0.0555, 0.33), Vector3(-1.5, 0, 0)), Vector3(0.01, 0.004, 0.13), 0.002, ACCENT)
	for sx: float in [-1.0, 1.0]:
		_box(st, _xf(Vector3(sx * 0.049, 0.006, 0.35), Vector3.ZERO), Vector3(0.016, 0.06, 0.25), 0.006, ARMOR)
	# 前腕：黒い下地と白い装甲、手首の手前にオレンジの細い帯
	_capsule(st, Transform3D.IDENTITY, 0.036, 0.029, -WRIST_Z + 0.02, 0.78, JOINT)
	_box(st, _xf(Vector3(0, 0.022, -0.1), Vector3(-2.5, 0, 0)), Vector3(0.056, 0.016, 0.16), 0.007, ARMOR)
	_box(st, _xf(Vector3(0, -0.019, -0.11), Vector3(3.0, 0, 0)), Vector3(0.046, 0.012, 0.13), 0.006, ARMOR)
	_capsule(st, Transform3D(Basis.IDENTITY, Vector3(0, 0, WRIST_Z + 0.022)), 0.0315, 0.0315, 0.007, 0.8, ACCENT)
	# 手のひら：黒い芯、甲の装甲、手のひらのゴム
	_box(st, _xf(Vector3(0, 0, -0.262), Vector3.ZERO), PALM_SIZE, 0.013, JOINT)
	_box(st, _xf(Vector3(0, 0.0165, -0.262), Vector3(-3.0, 0, 0)), Vector3(0.074, 0.009, 0.082), 0.004, ARMOR)
	_box(st, _xf(Vector3(0.022, 0.0215, -0.245), Vector3.ZERO), Vector3(0.012, 0.004, 0.03), 0.002, ACCENT)
	_box(st, _xf(Vector3(0, -0.0155, -0.264), Vector3.ZERO), Vector3(0.072, 0.007, 0.08), 0.0035, PAD)
	return st.commit()


## 3節の指。各節は黒い芯のカプセルと、上に白い装甲板（末節は指先のゴム）
func _finger(key: String, root: Vector3, lengths: Array, r: float) -> Array:
	var chain: Array = []
	var parent: Node3D = self
	var pos := root
	for i: int in 3:
		var j := Node3D.new()
		j.position = pos
		parent.add_child(j)
		chain.append(j)
		var length: float = lengths[i]
		var rr := r * (1.0 - 0.07 * i)
		var last := i == 2
		_add_mesh(j, _cached("%s_%d" % [key, i], func() -> ArrayMesh: return _segment_mesh(rr, length, last)))
		parent = j
		pos = Vector3(0, 0, -length)
	return chain


func _segment_mesh(rr: float, length: float, tip: bool) -> ArrayMesh:
	var st := _begin()
	_capsule(st, Transform3D.IDENTITY, rr, rr * 0.93, length, 0.86, JOINT)
	_box(st, _xf(Vector3(0, rr * 0.62, -length * 0.5), Vector3.ZERO), Vector3(rr * 1.7, rr * 0.7, length * 0.72), rr * 0.32, ARMOR)
	if tip:
		_box(st, _xf(Vector3(0, -rr * 0.62, -length * 0.55), Vector3.ZERO), Vector3(rr * 1.5, rr * 0.5, length * 0.45), rr * 0.24, PAD)
	return st.commit()


func _add_mesh(parent: Node3D, mesh: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _cached(key: String, make: Callable) -> ArrayMesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = make.call()
	return _mesh_cache[key]


static func _xf(pos: Vector3, rot_deg: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## 太さが r0 → r1 に変わるカプセル（xf の原点から -Z へ length）。flat = 縦（y）の潰し
static func _capsule(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, length: float, flat: float, mat: float) -> void:
	const SEG := 18
	const CAP := 6
	var col := COLORS[mat]
	col.a = mat / 4.0
	var prof: Array[Vector4] = []
	for i: int in CAP + 1:
		var a := PI * 0.5 * i / CAP
		prof.append(Vector4(r0 * cos(a), r0 * sin(a), cos(a), sin(a)))
	for i: int in CAP + 1:
		var a := PI * 0.5 + PI * 0.5 * i / CAP
		prof.append(Vector4(-length + r1 * cos(a), r1 * sin(a), cos(a), sin(a)))
	var rows: Array[Array] = []
	for pr: Vector4 in prof:
		var row: Array = []
		for s: int in SEG:
			var ang := TAU * s / SEG
			var p := Vector3(cos(ang) * pr.y, sin(ang) * pr.y * flat, pr.x)
			var n := Vector3(cos(ang) * pr.w, sin(ang) * pr.w / flat, pr.z).normalized()
			row.append([xf * p, (xf.basis * n).normalized()])
		rows.append(row)
	for r: int in rows.size() - 1:
		for s: int in SEG:
			var a: Array = rows[r][s]
			var b: Array = rows[r][(s + 1) % SEG]
			var c: Array = rows[r + 1][s]
			var d: Array = rows[r + 1][(s + 1) % SEG]
			# Godot は時計回り（外から見て）が表
			for v: Array in [a, b, c, b, d, c]:
				st.set_color(col)
				st.set_normal(v[1])
				st.add_vertex(v[0])


## 角を丸めた箱（xf の原点が中心）
static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, radius: float, mat: float) -> void:
	const N := 6
	var col := COLORS[mat]
	col.a = mat / 4.0
	var half := size * 0.5
	var inner := (half - Vector3.ONE * radius).max(Vector3.ZERO)
	var faces: Array = [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f: Array in faces:
		var n0: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var grid: Array = []
		for j: int in N + 1:
			for i: int in N + 1:
				var q := (n0 + u * (i * 2.0 / N - 1.0) + v * (j * 2.0 / N - 1.0)) * half
				var core := q.clamp(-inner, inner)
				var dn := q - core
				var n := dn.normalized() if dn.length() > 1e-6 else n0
				grid.append([xf * (core + n * radius), (xf.basis * n).normalized()])
		for j: int in N:
			for i: int in N:
				var a: Array = grid[j * (N + 1) + i]
				var b: Array = grid[j * (N + 1) + i + 1]
				var c: Array = grid[(j + 1) * (N + 1) + i]
				var d: Array = grid[(j + 1) * (N + 1) + i + 1]
				for vv: Array in [a, b, c, b, d, c]:
					st.set_color(col)
					st.set_normal(vv[1])
					st.add_vertex(vv[0])
