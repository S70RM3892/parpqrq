class_name CourseProps
extends RefCounted
## 屋上の小物（仕様書 6章：日本風の架空都市の屋上群。給水塔・室外機・看板・電線など）。
## 全部 LevelGeometry に箱と円柱で積む（まとめて描くのでモバイルでも数を置ける）。
## xf = 置く場所の足元。basis の -Z が「前」、+X が「右」。

const Mat := LevelStyle.Mat
const NC := LevelGeometry.NO_COLLIDE
const NS := LevelGeometry.NO_SHADOW


static func box(geo: LevelGeometry, xf: Transform3D, center: Vector3, size: Vector3, mat: int, flags: int = 0,
		tint: Color = Color.WHITE, pitch_deg: float = 0.0) -> void:
	geo.add_box(xf * center, size, mat, Vector3(pitch_deg, rad_to_deg(xf.basis.get_euler().y), 0.0), flags, tint)


static func cyl(geo: LevelGeometry, xf: Transform3D, center: Vector3, r: float, h: float, mat: int,
		flags: int = 0, tint: Color = Color.WHITE, lying: bool = false, sides: int = 12) -> void:
	var rot := Vector3(90.0 if lying else 0.0, rad_to_deg(xf.basis.get_euler().y), 0.0)
	geo.add_cylinder(xf * center, r, h, mat, rot, flags, tint, sides)


## 室外機（幅0.9 × 高さ0.75 × 奥行き0.65）。route=true ならルートカラー（越える障害物）
static func ac_unit(geo: LevelGeometry, xf: Transform3D, route: bool = false) -> void:
	box(geo, xf, Vector3(0, 0.4, 0), Vector3(0.9, 0.7, 0.62), Mat.ROUTE if route else Mat.METAL)
	box(geo, xf, Vector3(0, 0.025, 0), Vector3(0.8, 0.05, 0.5), Mat.DARK, NC)
	cyl(geo, xf, Vector3(0.1, 0.4, -0.315), 0.24, 0.02, Mat.DARK, NC, Color.WHITE, true, 14)
	box(geo, xf, Vector3(-0.33, 0.4, -0.315), Vector3(0.12, 0.5, 0.02), Mat.DARK, NC)


## 受水槽（FRPのパネル張りの箱）を鉄骨の台に載せたもの。幅2.4 × 奥行き1.8
static func water_tank(geo: LevelGeometry, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var tint := Color(0.8, 0.88, 0.95) if rng.randf() < 0.6 else Color(0.95, 0.93, 0.85)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(geo, xf, Vector3(sx * 1.05, 0.4, sz * 0.75), Vector3(0.12, 0.8, 0.12), Mat.DARK)
	box(geo, xf, Vector3(0, 0.82, 0), Vector3(2.5, 0.08, 1.9), Mat.DARK)
	box(geo, xf, Vector3(0, 1.75, 0), Vector3(2.4, 1.8, 1.8), Mat.WHITE, 0, tint)
	# パネルの継ぎ目
	for i: int in 3:
		box(geo, xf, Vector3(-0.6 + i * 0.6, 1.75, -0.905), Vector3(0.04, 1.8, 0.02), Mat.DARK, NC)
	# はしご
	geo.add_beam(xf * Vector3(1.25, 0.0, 0.3), xf * Vector3(1.25, 2.7, 0.3), 0.025, Mat.METAL)
	geo.add_beam(xf * Vector3(1.25, 0.0, -0.1), xf * Vector3(1.25, 2.7, -0.1), 0.025, Mat.METAL)


## 円筒形の高架水槽（遠くから目印になる）
static func water_tower(geo: LevelGeometry, xf: Transform3D) -> void:
	for a: int in 4:
		var ang := TAU * a / 4.0 + PI / 4.0
		var foot := Vector3(cos(ang) * 1.4, 0.0, sin(ang) * 1.4)
		geo.add_beam(xf * foot, xf * (foot * 0.75 + Vector3(0, 4.0, 0)), 0.08, Mat.DARK, 0, 6)
	cyl(geo, xf, Vector3(0, 4.05, 0), 1.25, 0.12, Mat.DARK)
	cyl(geo, xf, Vector3(0, 5.2, 0), 1.2, 2.2, Mat.METAL, 0, Color(0.85, 0.9, 0.95), false, 16)
	geo.add_cylinder(xf * Vector3(0, 6.55, 0), 0.6, 0.5, Mat.METAL, Vector3.ZERO, NC, Color.WHITE, 12)


## アンテナ
static func antenna(geo: LevelGeometry, xf: Transform3D, h: float = 4.5) -> void:
	geo.add_beam(xf * Vector3.ZERO, xf * Vector3(0, h, 0), 0.05, Mat.METAL, NC | NS)
	for i: int in 3:
		var y := h - 0.4 - i * 0.6
		var w := 0.9 - i * 0.2
		geo.add_beam(xf * Vector3(-w, y, 0), xf * Vector3(w, y, 0), 0.02, Mat.METAL, NC | NS, 4)
	box(geo, xf, Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.5), Mat.DARK)


## 塔屋（屋上への階段室）。w × d、高さ h
static func stair_house(geo: LevelGeometry, xf: Transform3D, w: float, d: float, h: float) -> void:
	box(geo, xf, Vector3(0, h * 0.5, 0), Vector3(w, h, d), Mat.WHITE, 0, Color(0.9, 0.9, 0.88))
	box(geo, xf, Vector3(0, h + 0.05, 0), Vector3(w + 0.3, 0.1, d + 0.3), Mat.WHITE)
	box(geo, xf, Vector3(0, 1.0, -d * 0.5 - 0.01), Vector3(0.9, 2.0, 0.04), Mat.DARK, NC)


## 手すり（a→b）。支柱1.5 mおき、高さ1.1 m。当たり判定は薄い板
static func railing(geo: LevelGeometry, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var n := maxi(1, ceili(length / 1.5))
	for i: int in n + 1:
		var p := a.lerp(b, float(i) / n)
		geo.add_beam(p, p + Vector3.UP * 1.1, 0.03, Mat.METAL, NC, 5)
	geo.add_beam(a + Vector3.UP * 1.1, b + Vector3.UP * 1.1, 0.035, Mat.METAL, NC, 6)
	geo.add_beam(a + Vector3.UP * 0.55, b + Vector3.UP * 0.55, 0.02, Mat.METAL, NC, 4)
	var mid := (a + b) * 0.5 + Vector3.UP * 0.55
	var yaw := atan2(-(b - a).x, -(b - a).z)
	geo.add_box(mid, Vector3(0.06, 1.1, length), Mat.METAL, Vector3(0, rad_to_deg(yaw), 0), LevelGeometry.NO_VISUAL)


## 看板：脚の上の板。lit = 発光（夕方・夜）
static func billboard(geo: LevelGeometry, xf: Transform3D, w: float, h: float, color: Color, lit: bool) -> void:
	for sx: float in [-0.35, 0.35]:
		box(geo, xf, Vector3(sx * w, 1.2, 0.2), Vector3(0.12, 2.4, 0.12), Mat.DARK)
	box(geo, xf, Vector3(0, 2.4 + h * 0.5, 0.05), Vector3(w + 0.2, h + 0.2, 0.25), Mat.DARK)
	if lit:
		box(geo, xf, Vector3(0, 2.4 + h * 0.5, -0.09), Vector3(w, h, 0.04), Mat.LIGHT, NC, color)
		geo.add_light(xf * Vector3(0, 2.4 + h * 0.5, -1.2), color, 1.6, 7.0 + w)
	else:
		box(geo, xf, Vector3(0, 2.4 + h * 0.5, -0.09), Vector3(w, h, 0.04), Mat.ACCENT, NC, color)


## 縦長のネオンサイン（繁華街）
static func neon(geo: LevelGeometry, xf: Transform3D, h: float, color: Color) -> void:
	box(geo, xf, Vector3(0, h * 0.5, 0), Vector3(0.9, h, 0.3), Mat.DARK)
	var n := int(h / 1.1)
	for i: int in n:
		box(geo, xf, Vector3(0, 0.6 + i * 1.1, -0.16), Vector3(0.6, 0.8, 0.04), Mat.LIGHT, NC, color)
	geo.add_light(xf * Vector3(0, minf(h * 0.5, 2.2), -0.9), color, 1.4, 6.5)


## 照明（夜の駅前）
static func lamp(geo: LevelGeometry, xf: Transform3D) -> void:
	geo.add_beam(xf * Vector3.ZERO, xf * Vector3(0, 3.2, 0), 0.06, Mat.DARK, NC, 6)
	geo.add_beam(xf * Vector3(0, 3.2, 0), xf * Vector3(0, 3.2, -0.7), 0.04, Mat.DARK, NC, 6)
	box(geo, xf, Vector3(0, 3.12, -0.75), Vector3(0.5, 0.1, 0.25), Mat.LIGHT, NC | NS, Color(1.0, 0.85, 0.6))
	geo.add_light(xf * Vector3(0, 3.0, -0.75), Color(1.0, 0.82, 0.58), 6.0, 11.0, true)


## 足場（工事中）。w 横、h 高さ、d 奥行き
static func scaffold(geo: LevelGeometry, xf: Transform3D, w: float, h: float, d: float) -> void:
	var nx := maxi(1, int(w / 1.8))
	var ny := maxi(1, int(h / 1.9))
	for i: int in nx + 1:
		var x := -w * 0.5 + w * i / nx
		for z: float in [0.0, -d]:
			geo.add_beam(xf * Vector3(x, 0, z), xf * Vector3(x, h, z), 0.035, Mat.METAL, NC, 5)
	for j: int in ny + 1:
		var y := h * j / ny
		for z: float in [0.0, -d]:
			geo.add_beam(xf * Vector3(-w * 0.5, y, z), xf * Vector3(w * 0.5, y, z), 0.03, Mat.METAL, NC, 5)
		if j > 0:
			box(geo, xf, Vector3(0, y, -d * 0.5), Vector3(w, 0.05, d), Mat.HAZARD, NC)
	geo.add_beam(xf * Vector3(-w * 0.5, 0, 0), xf * Vector3(w * 0.5, h, 0), 0.025, Mat.METAL, NC, 4)


## クレーン（遠景の目印）
static func crane(geo: LevelGeometry, xf: Transform3D, h: float) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			geo.add_beam(xf * Vector3(sx, 0, sz), xf * Vector3(sx, h, sz), 0.12, Mat.HAZARD, NC, 6)
	var n := int(h / 3.0)
	for i: int in n:
		var y := i * 3.0
		geo.add_beam(xf * Vector3(-1, y, -1), xf * Vector3(1, y + 3, -1), 0.06, Mat.HAZARD, NC | NS, 4)
		geo.add_beam(xf * Vector3(-1, y, 1), xf * Vector3(1, y + 3, 1), 0.06, Mat.HAZARD, NC | NS, 4)
	box(geo, xf, Vector3(0, h + 1.0, 0), Vector3(2.6, 2.0, 2.6), Mat.HAZARD, NC)
	box(geo, xf, Vector3(0, h + 2.4, -9.0), Vector3(1.2, 0.9, 26.0), Mat.HAZARD, NC)
	box(geo, xf, Vector3(0, h + 2.4, 6.0), Vector3(2.4, 1.4, 4.0), Mat.DARK, NC)
	geo.add_beam(xf * Vector3(0, h + 2.0, -18.0), xf * Vector3(0, h - 10.0, -18.0), 0.03, Mat.DARK, NC | NS, 4)


## 屋上の配管（低い台の上を這う）
static func pipes(geo: LevelGeometry, xf: Transform3D, length: float) -> void:
	for k: int in 2:
		var y := 0.35 + k * 0.28
		var x := -0.2 + k * 0.4
		geo.add_beam(xf * Vector3(x, y, 0), xf * Vector3(x, y, -length), 0.11 - k * 0.03, Mat.METAL, 0, 8)
	var n := maxi(1, int(length / 2.5))
	for i: int in n + 1:
		box(geo, xf, Vector3(0, 0.2, -length * i / n), Vector3(0.9, 0.4, 0.15), Mat.DARK)


## 天窓（ガラス）。上を走れる
static func skylight(geo: LevelGeometry, xf: Transform3D, w: float, d: float, route: bool = false) -> void:
	box(geo, xf, Vector3(0, 0.3, 0), Vector3(w, 0.6, d), Mat.GLASS)
	if route:
		box(geo, xf, Vector3(0, 0.605, d * 0.5 - 0.08), Vector3(w, 0.03, 0.16), Mat.ROUTE, NC)


## 電柱と電線（隙間の上に張る：速さと高さの目安）
static func power_line(geo: LevelGeometry, a: Vector3, b: Vector3, h: float) -> void:
	for p: Vector3 in [a, b]:
		geo.add_beam(p, p + Vector3.UP * h, 0.12, Mat.DARK, NC, 6)
		var side := (b - a).cross(Vector3.UP).normalized()
		geo.add_beam(p + Vector3.UP * (h - 0.4) - side * 0.9, p + Vector3.UP * (h - 0.4) + side * 0.9, 0.05, Mat.DARK, NC | NS, 4)
	var side2 := (b - a).cross(Vector3.UP).normalized()
	for k: float in [-0.7, 0.0, 0.7]:
		var prev := a + Vector3.UP * (h - 0.35) + side2 * k
		for i: int in 6:
			var t := float(i + 1) / 6.0
			var p := a.lerp(b, t) + Vector3.UP * (h - 0.35 - sin(t * PI) * 0.9) + side2 * k
			geo.add_beam(prev, p, 0.015, Mat.DARK, NC | NS, 3)
			prev = p


## ゴールの門（遠くから見える柱と光る梁）
static func goal_gate(geo: LevelGeometry, xf: Transform3D, w: float) -> void:
	for sx: float in [-1.0, 1.0]:
		box(geo, xf, Vector3(sx * (w * 0.5 + 0.3), 2.5, 0), Vector3(0.6, 5.0, 0.6), Mat.ROUTE)
	box(geo, xf, Vector3(0, 5.2, 0), Vector3(w + 1.2, 0.5, 0.6), Mat.LIGHT, NC, LevelStyle.ROUTE_COLOR)
	# 遠くから見える光の柱
	box(geo, xf, Vector3(0, 30.0, 0), Vector3(0.5, 50.0, 0.5), Mat.LIGHT, NC | NS, LevelStyle.ROUTE_COLOR)
