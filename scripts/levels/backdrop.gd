class_name Backdrop
extends Node3D
## 遠景の街（仕様書 6章：速度と高さが目で分かる絵）。コースから離れた所にビルを並べ、霧で白く飛ばす。
## ビルは種類ごとに形と外壁が違う（板状の高層・ガラスの事務所・ベランダのある集合住宅・細長い雑居ビル・古いビル・黒いガラスの塔）。
## 高いビルはセットバック（上ほど細く）と頭の飾り、屋上には塔屋・水槽・室外機・アンテナを載せてシルエットを作る。
## 箱は全部 MultiMesh 1つ（描画1回）。外壁は backdrop.gdshader が種類ごとに描く（窓の奥の部屋・ベランダ・カーテンウォール）。
## エリアごとの目印（電波塔・旋回するタワークレーン・大きな画面のビル・高架を走る電車）と、谷底の通りを流れる車の光も置く。

const CELL := 24.0
const CLEAR := 26.0      ## ルートからこれより近い所には置かない
const MARGIN := 170.0

## 外壁の種類（backdrop.gdshader の kind と同じ番号）
enum Kind { SLAB, OFFICE, RESIDENTIAL, PENCIL, OLD, DARK_GLASS, PLAIN, ROOF_BOX, BEACON, SCREEN, STEEL, RAIL, TRAIN }

var building_count: int = 0

var _xforms: Array[Transform3D] = []
var _customs: Array[Color] = []
var _rng := RandomNumberGenerator.new()
## 旋回するクレーンの腕（MultiMesh の番号、回転の中心、速さ）と電車
var _movers: Array[Dictionary] = []
var _mm: MultiMesh
var _time: float = 0.0
## 屋上の旗（揺れる布）と湯気の出る所
var _flags: Array[Transform3D] = []
var _flag_colors: Array[Color] = []
var _steam: PackedVector3Array = []
const WIND := Vector3(0.8, 0.0, 0.6)
## エリアごとの湯気の色（空気の色に合わせる）
const STEAM_TINT: Array[Color] = [Color(0.95, 0.93, 0.9, 0.5), Color(0.95, 0.96, 0.98, 0.45), Color(0.98, 0.78, 0.68, 0.45),
		Color(0.32, 0.34, 0.42, 0.5), Color(0.95, 0.93, 0.9, 0.5)]


## points = ルートの点、street_y = 通りの高さ、roof_y = だいたいの屋上の高さ、area = エリア（0〜3、4 = フリーラン）
func build(points: PackedVector3Array, street_y: float, roof_y: float, seed_value: int, area: int = 0) -> void:
	_rng.seed = seed_value
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pts: Array[Vector2] = []
	for i: int in range(0, points.size(), 2):
		var p := Vector2(points[i].x, points[i].z)
		pts.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector2(MARGIN, MARGIN)
	hi += Vector2(MARGIN, MARGIN)
	var base_y := street_y - 5.0
	var x := lo.x
	while x < hi.x:
		var z := lo.y
		while z < hi.y:
			var c := Vector2(x + _rng.randf_range(-4, 4), z + _rng.randf_range(-4, 4))
			var near := _nearest(pts, c)
			if near > CLEAR and _rng.randf() < 0.82:
				var w := _rng.randf_range(12.0, 20.0)
				var d := _rng.randf_range(12.0, 20.0)
				# 近くはコースの屋上より低く（下に街が広がって高さが分かる）、遠いほど高いビルが混ざる
				var far := clampf((near - CLEAR) / 140.0, 0.0, 1.0)
				var top := roof_y - lerpf(_rng.randf_range(6.0, 22.0), _rng.randf_range(-8.0, 12.0), far)
				if far > 0.4 and _rng.randf() < 0.25:
					top += _rng.randf_range(20.0, 75.0)
				_building(Vector3(c.x, base_y, c.y), w, d, top, far)
				building_count += 1
			z += CELL
		x += CELL
	_landmark(area, pts, lo, hi, base_y, roof_y)
	_make_multimesh()
	_street(lo, hi, street_y)
	if area == 0:
		_birds(pts, roof_y)
	_make_flags()
	_make_steam(STEAM_TINT[clampi(area, 0, STEAM_TINT.size() - 1)])


func _nearest(pts: Array[Vector2], c: Vector2) -> float:
	var near := INF
	for p: Vector2 in pts:
		near = minf(near, c.distance_squared_to(p))
	return sqrt(near)


## 1棟。高さで種類を選び、セットバック・頭・屋上の物を足す
func _building(foot: Vector3, w: float, d: float, top: float, far: float) -> void:
	var h := top - foot.y
	var yaw := _rng.randf_range(-0.05, 0.05)
	var seed_k := _rng.randf()
	var kind: int
	var tall := h > 70.0
	var r := _rng.randf()
	if tall:
		kind = [Kind.OFFICE, Kind.SLAB, Kind.DARK_GLASS, Kind.OFFICE, Kind.SLAB][int(r * 5.0)]
	else:
		kind = [Kind.SLAB, Kind.RESIDENTIAL, Kind.RESIDENTIAL, Kind.OLD, Kind.PENCIL, Kind.SLAB, Kind.OLD][int(r * 7.0)]
	if kind == Kind.PENCIL:
		w = minf(w, _rng.randf_range(7.0, 10.0))
	var body_h := h
	var tiers := 0
	if tall and _rng.randf() < 0.65:
		tiers = _rng.randi_range(1, 2)
		body_h = h * _rng.randf_range(0.62, 0.78)
	_box(foot + Vector3(0, body_h * 0.5, 0), Vector3(w, body_h, d), yaw, kind, seed_k)
	var y := foot.y + body_h
	var tw := w
	var td := d
	for t: int in tiers:
		tw *= _rng.randf_range(0.68, 0.85)
		td *= _rng.randf_range(0.68, 0.85)
		var th := (h - body_h) / tiers
		_box(Vector3(foot.x, y + th * 0.5, foot.z), Vector3(tw, th, td), yaw, kind, seed_k)
		y += th
	# 頭：細い帯（笠木）
	_box(Vector3(foot.x, y + 0.35, foot.z), Vector3(tw + 0.4, 0.7, td + 0.4), yaw, Kind.PLAIN, seed_k)
	y += 0.7
	var b := Basis(Vector3.UP, yaw)
	# 屋上の物（塔屋・水槽・室外機・アンテナ）。遠すぎるビルは省く
	if far < 0.9:
		var n := _rng.randi_range(1, 4)
		for i: int in n:
			var pick := _rng.randf()
			var off := b * Vector3(_rng.randf_range(-tw * 0.3, tw * 0.3), 0, _rng.randf_range(-td * 0.3, td * 0.3))
			if pick < 0.35:
				_box(Vector3(foot.x, y + 1.5, foot.z) + off, Vector3(3.2, 3.0, 3.6), yaw, Kind.ROOF_BOX, seed_k)
			elif pick < 0.6:
				_box(Vector3(foot.x, y + 1.3, foot.z) + off, Vector3(2.4, 2.6, 2.4), yaw + PI * 0.25, Kind.ROOF_BOX, seed_k * 0.5)
			elif pick < 0.85:
				_box(Vector3(foot.x, y + 0.6, foot.z) + off, Vector3(2.2, 1.2, 1.0), yaw, Kind.ROOF_BOX, seed_k * 0.3)
			else:
				_box(Vector3(foot.x, y + 3.0, foot.z) + off, Vector3(0.15, 6.0, 0.15), 0.0, Kind.STEEL, seed_k)
	# 屋上の旗（ポールの先で風になびく）と、室外機の湯気
	if far < 0.7 and not tall:
		var r2 := _rng.randf()
		var corner := Vector3(foot.x, y, foot.z) + b * Vector3(tw * 0.42, 0, -td * 0.42)
		if r2 < 0.14:
			_box(corner + Vector3.UP * 3.5, Vector3(0.12, 7.0, 0.12), 0.0, Kind.STEEL, 0.5)
			var fb := Basis.looking_at(Vector3(WIND.z, 0, -WIND.x), Vector3.UP)  # 旗の +X が風下
			_flags.append(Transform3D(fb, corner + Vector3.UP * 6.3))
			_flag_colors.append(Color(_rng.randf(), _rng.randf(), 0.0, 0.0))
		elif r2 < 0.24 and _steam.size() < 10:
			_steam.append(Vector3(foot.x, y + 1.4, foot.z) + b * Vector3(-tw * 0.25, 0, td * 0.2))
	# 高い塔には夜に点滅する赤い航空障害灯
	if tall:
		for s: Vector2 in [Vector2(-0.45, -0.45), Vector2(0.45, 0.45)]:
			_box(Vector3(foot.x, y + 0.3, foot.z) + b * Vector3(s.x * tw, 0, s.y * td), Vector3(0.5, 0.5, 0.5), 0.0, Kind.BEACON, seed_k)


func _box(center: Vector3, size: Vector3, yaw: float, kind: int, seed_k: float) -> void:
	var bas := Basis(Vector3.UP, yaw).scaled(size)
	_xforms.append(Transform3D(bas, center))
	_customs.append(Color(seed_k, float(kind), 0.0, 0.0))


## エリアの目印。ルートの先（ゴール側）の遠くに置き、走っている間に何度も見える
func _landmark(area: int, pts: Array[Vector2], lo: Vector2, hi: Vector2, base_y: float, roof_y: float) -> void:
	if pts.size() < 2:
		return
	var start := pts[0]
	var goal := pts[pts.size() - 1]
	var dir := (goal - start).normalized() if goal.distance_to(start) > 1.0 else Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var spot := goal + dir * 180.0 + side * 90.0
	var g := Vector3(spot.x, base_y, spot.y)
	match area:
		0:
			# 電波塔：4本脚の格子の塔、展望台、赤白の帯（kind STEEL の上下の縞はシェーダー）
			var h := roof_y - base_y + 170.0
			for i: int in 4:
				var a := TAU * i / 4.0 + PI * 0.25
				var foot := g + Vector3(cos(a), 0, sin(a)) * 14.0
				var head := g + Vector3(cos(a), 0, sin(a)) * 2.2 + Vector3.UP * h * 0.8
				_beam(foot, head, 1.1, Kind.STEEL)
			for k: int in 6:
				var t := (k + 1) / 7.0
				var rr := lerpf(14.0, 2.2, t) * 1.45
				_box(g + Vector3.UP * h * 0.8 * t, Vector3(rr, 0.6, rr), PI * 0.25, Kind.STEEL, 0.5)
			_box(g + Vector3.UP * h * 0.55, Vector3(9.0, 6.0, 9.0), PI * 0.25, Kind.OFFICE, 0.3)
			_box(g + Vector3.UP * (h * 0.8 + h * 0.1), Vector3(1.6, h * 0.2, 1.6), 0.0, Kind.STEEL, 0.7)
			_box(g + Vector3.UP * (h + 1.0), Vector3(0.8, 0.8, 0.8), 0.0, Kind.BEACON, 0.2)
		1:
			# タワークレーン3基（腕はゆっくり旋回する）
			for i: int in 3:
				var c := g + Vector3(side.x, 0, side.y) * (i * 70.0 - 70.0) + Vector3(dir.x, 0, dir.y) * (i % 2) * 40.0
				var h := roof_y - base_y + _rng.randf_range(40.0, 80.0)
				_box(c + Vector3.UP * h * 0.5, Vector3(2.2, h, 2.2), 0.0, Kind.STEEL, 0.9)
				var top := c + Vector3.UP * (h + 1.5)
				_box(top, Vector3(3.0, 3.0, 3.0), 0.0, Kind.ROOF_BOX, 0.9)
				var idx := _xforms.size()
				_box(top + Vector3(14.0, 2.0, 0.0), Vector3(48.0, 1.6, 1.8), 0.0, Kind.STEEL, 0.9)
				_box(top + Vector3(-12.0, 1.0, 0.0), Vector3(5.0, 3.5, 3.0), 0.0, Kind.ROOF_BOX, 0.95)
				# 吊り荷（ワイヤーと鉄骨の束。腕の先で振り子のように揺れる）
				var hook := _xforms.size()
				var drop := _rng.randf_range(14.0, 26.0)
				_box(top + Vector3(30.0, 1.2 - drop * 0.5, 0.0), Vector3(0.12, drop, 0.12), 0.0, Kind.STEEL, 0.5)
				_box(top + Vector3(30.0, 1.2 - drop - 0.8, 0.0), Vector3(6.0, 1.2, 1.6), 0.0, Kind.ROOF_BOX, 0.2)
				_movers.append({"first": idx, "count": 2, "pivot": top, "speed": _rng.randf_range(0.03, 0.06) * (1.0 if i % 2 == 0 else -1.0),
						"phase": _rng.randf() * TAU, "hook": hook, "hook_at": Vector3(30.0, 1.2, 0.0), "drop": drop})
		2:
			# 大きな画面のビル（夕方から光る。画面の絵はシェーダーが動かす）
			var h := roof_y - base_y + 90.0
			_box(g + Vector3.UP * h * 0.5, Vector3(36.0, h, 30.0), atan2(-dir.x, -dir.y), Kind.DARK_GLASS, 0.4)
			var face := g + Vector3(-dir.x, 0, -dir.y) * 15.4 + Vector3.UP * (h * 0.62)
			_box(face, Vector3(30.0, 22.0, 0.6), atan2(-dir.x, -dir.y), Kind.SCREEN, 0.5)
		3:
			# 高架の線路と電車（街の中をルートと並んで横切る）
			var mid := (Vector3(start.x, 0, start.y) + Vector3(goal.x, 0, goal.y)) * 0.5 + Vector3(side.x, 0, side.y) * 75.0
			var rail_y := roof_y - 18.0
			var along := Vector3(dir.x, 0, dir.y)
			var length := (hi - lo).length() + 200.0
			var yaw := atan2(-along.x, -along.z)
			_box(Vector3(mid.x, rail_y, mid.z), Vector3(9.0, 2.2, length), yaw, Kind.RAIL, 0.6)
			var n := int(length / 40.0)
			for i: int in n:
				var pp := mid + along * (i * 40.0 - length * 0.5)
				_box(Vector3(pp.x, (base_y + rail_y) * 0.5, pp.z), Vector3(2.4, rail_y - base_y, 2.4), yaw, Kind.PLAIN, 0.6)
			var first := _xforms.size()
			for k: int in 6:
				_box(Vector3(mid.x, rail_y + 2.6, mid.z) + along * (k * 21.0), Vector3(3.0, 3.4, 20.0), yaw, Kind.TRAIN, 0.6)
			_movers.append({"first": first, "count": 6, "train": true, "mid": mid, "along": along, "length": length,
					"y": rail_y + 2.6, "yaw": yaw, "speed": 22.0})


## a から b への細長い箱（電波塔の脚）
func _beam(a: Vector3, b: Vector3, thick: float, kind: int) -> void:
	var d := b - a
	var y := d.normalized()
	var xax := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var zax := xax.cross(y)
	var bas := Basis(xax * thick, y * d.length(), zax * thick)
	_xforms.append(Transform3D(bas, (a + b) * 0.5))
	_customs.append(Color(0.5, float(kind), 0.0, 0.0))


func _make_multimesh() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mm.mesh = box
	_mm.instance_count = _xforms.size()
	for i: int in _xforms.size():
		_mm.set_instance_transform(i, _xforms[i])
		_mm.set_instance_custom_data(i, _customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Buildings"
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/backdrop.gdshader")
	mmi.material_override = mat
	add_child(mmi)


## 屋上の旗（MultiMesh 1つ。布のなびきは flag.gdshader）
func _make_flags() -> void:
	if _flags.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 1.5)
	plane.subdivide_width = 10
	plane.subdivide_depth = 3
	plane.orientation = PlaneMesh.FACE_Z
	plane.center_offset = Vector3(1.2, 0, 0)
	mm.mesh = plane
	mm.instance_count = _flags.size()
	for i: int in _flags.size():
		mm.set_instance_transform(i, _flags[i])
		mm.set_instance_custom_data(i, _flag_colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "Flags"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag.gdshader")
	mi.material_override = mat
	add_child(mi)


## 室外機の湯気（煙の玉が昇って風に流され、薄れて消える。MultiMesh 1つ、steam.gdshader）
func _make_steam(tint: Color) -> void:
	if _steam.is_empty():
		return
	const PUFFS := 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = _steam.size() * PUFFS
	var i := 0
	for p: Vector3 in _steam:
		var seed_k := _rng.randf()
		for k: int in PUFFS:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
			mm.set_instance_custom_data(i, Color(float(k) / PUFFS, seed_k, 0.0, 0.0))
			i += 1
	var mi := MultiMeshInstance3D.new()
	mi.name = "Steam"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/steam.gdshader")
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"wind", WIND)
	mi.material_override = mat
	add_child(mi)


## 谷底の通り（高さフォグで白く消える）。夕方・夜は車のライトが流れる（street.gdshader）
func _street(lo: Vector2, hi: Vector2, street_y: float) -> void:
	var street := MeshInstance3D.new()
	street.name = "Street"
	var plane := PlaneMesh.new()
	plane.size = (hi - lo) + Vector2(400, 400)
	street.mesh = plane
	street.position = Vector3((lo.x + hi.x) * 0.5, street_y, (lo.y + hi.y) * 0.5)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/street.gdshader")
	sm.set_shader_parameter(&"cell", CELL)
	sm.set_shader_parameter(&"origin", lo)
	street.material_override = sm
	street.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(street)


## 朝の鳥の群れ（屋上より少し上を大きく回る。1羽 = 板2枚の羽ばたき、頂点シェーダーで動かす）
func _birds(pts: Array[Vector2], roof_y: float) -> void:
	if pts.is_empty():
		return
	var flock := MultiMesh.new()
	flock.transform_format = MultiMesh.TRANSFORM_3D
	flock.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.3)
	flock.mesh = quad
	var count := 18
	flock.instance_count = count
	for i: int in count:
		var off := Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-2, 2), _rng.randf_range(-8, 8))
		flock.set_instance_transform(i, Transform3D(Basis.IDENTITY, off))
		flock.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Birds"
	mmi.multimesh = flock
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := pts[pts.size() / 3]
	mmi.position = Vector3(c.x + 40.0, roof_y + 22.0, c.y - 30.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/birds.gdshader")
	mmi.material_override = mat
	mmi.extra_cull_margin = 80.0
	add_child(mmi)


func _process(delta: float) -> void:
	if _movers.is_empty() or _mm == null:
		return
	_time += delta
	for m: Dictionary in _movers:
		if m.get("train", false):
			var along: Vector3 = m.along
			var length: float = m.length
			var travel := fposmod(_time * float(m.speed), length + 200.0) - length * 0.5 - 100.0
			for k: int in int(m.count):
				var p: Vector3 = (m.mid as Vector3) + along * (travel - k * 21.0)
				p.y = m.y
				_mm.set_instance_transform(int(m.first) + k, Transform3D(Basis(Vector3.UP, m.yaw).scaled(Vector3(3.0, 3.4, 20.0)), p))
		else:
			var ang: float = float(m.phase) + _time * float(m.speed)
			var rot := Basis(Vector3.UP, ang)
			var pivot: Vector3 = m.pivot
			for k: int in int(m.count):
				var i := int(m.first) + k
				var base_xf := _xforms[i]
				var rel := base_xf.origin - pivot
				_mm.set_instance_transform(i, Transform3D(rot * base_xf.basis, pivot + rot * rel))
			if m.has("hook"):
				# 腕の先の吊り荷：旋回に遅れて振れる振り子
				var at: Vector3 = pivot + rot * (m.hook_at as Vector3)
				var drop: float = m.drop
				var sway := Basis(rot * Vector3.FORWARD, sin(_time * 0.9 + float(m.phase)) * 0.1) \
						* Basis(rot * Vector3.RIGHT, sin(_time * 0.7 + float(m.phase) * 2.0) * 0.06)
				var down := sway * Vector3.DOWN
				var h := int(m.hook)
				_mm.set_instance_transform(h, Transform3D(sway * rot * Basis.IDENTITY.scaled(Vector3(0.12, drop, 0.12)), at + down * drop * 0.5))
				_mm.set_instance_transform(h + 1, Transform3D(sway * rot * Basis.IDENTITY.scaled(Vector3(6.0, 1.2, 1.6)), at + down * (drop + 0.8)))
