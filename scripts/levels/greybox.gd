@tool
class_name Greybox
extends Node3D
## 白い箱だけのテストコース（M1の手触り検証用）。_layout() の数値を書き換えれば形が変わる。
## 箱1つ = [中心, 大きさ, ルート色か, Y回転(度), X回転(度), 種類]。ルート色 = 使える足場・縁（仕様書 6章）。
## 箱は LevelGeometry で材質ごとにまとめて描く。
## 種類（省略可）: SOLID = 見た目＋当たり判定、VISUAL = 見た目だけ、COLLIDER = 当たり判定だけ（見えない坂など）

const LANE := 4.0  ## 主ルートの幅
const STEP_RISE := 0.4
const STEP_RUN := 0.8

enum Kind { SOLID, VISUAL, COLLIDER }


func _ready() -> void:
	_build()


func _layout() -> Array[Array]:
	var b: Array[Array] = []
	# 間隔は走り10 m/s用（仕様書の7.5 m/s時の配置を1.33倍に広げ、障害物どうしの時間間隔を保つ）
	# 床：z +20〜-99 と、穴（12 m）を挟んで -111〜-175
	b.append([Vector3(0, -0.5, -39.5), Vector3(44, 1, 119), false, 0.0, 0.0])
	b.append([Vector3(0, -0.5, -143), Vector3(44, 1, 64), false, 0.0, 0.0])
	# --- 主ルート：スタート z=8 から -z へ ---
	b.append(_wall(0.0, 1.0))                  # ヴォルト 1.0 m
	b.append(_wall(-10.6, 0.8))                # ヴォルト 0.8 m（約1秒間隔でリズムを作る）
	b.append([Vector3(0, 0.225, -18.6), Vector3(LANE, 0.45, 2), false, 0.0, 0.0])  # 段差 0.45 m
	b.append_array(_stairs(-24.0, 6))          # 階段で 2.4 m へ
	b.append([Vector3(0, 1.2, -32.4), Vector3(LANE, 2.4, 7.2), true, 0.0, 0.0])  # 2.4 m の台 → 飛び降りてローリング
	b.append([Vector3(0, 0.5, -48), Vector3(LANE, 1.0, 4), true, 0.0, 0.0])      # 深い箱：上に乗るヴォルト
	b.append(_wall(-58.0, 1.2))                # ヴォルト 1.2 m
	b.append_array(_stairs(-63.0, 12))         # 階段で 4.8 m へ
	b.append([Vector3(0, 2.4, -74.8), Vector3(LANE, 4.8, 4.4), true, 0.0, 0.0])  # 4.8 m の塔 → ハードランディング
	b.append([Vector3(0, 1.45, -91.8), Vector3(12, 0.6, 3), true, 0.0, 0.0])     # 下が 1.15 m のバー：スライドでくぐる
	b.append([Vector3(1.0, 2.0, -105), Vector3(0.5, 4, 18.6), true, 0.0, 0.0])   # 穴の右の壁：ウォールランで越える
	b.append([Vector3(0, 1.2, -125), Vector3(LANE, 2.4, 4), true, 0.0, 0.0])     # 2.4 m の壁：クライム
	b.append([Vector3(0, 2.0, -140.6), Vector3(LANE, 4.0, 6), true, 0.0, 0.0])   # 4 m の壁：縦ウォールラン → 縁を掴む
	# --- 試し用（主ルートの外）---
	b.append([Vector3(14, 2.0, -12), Vector3(0.5, 4, 16), true, 0.0, 0.0])        # 壁ジャンプ回廊（左右交互）
	b.append([Vector3(18, 2.0, -16), Vector3(0.5, 4, 16), true, 0.0, 0.0])
	b.append([Vector3(-14, 1.0, -16), Vector3(4, 0.4, 14), false, 0.0, -10.0])    # 下り坂：スライドで加速
	b.append([Vector3(8, 0.3, -4), Vector3(3, 0.6, 0.5), true, 0.0, 0.0])         # ヴォルト下限 0.6 m
	b.append([Vector3(8, 0.65, -12), Vector3(3, 1.3, 0.5), true, 0.0, 0.0])       # ヴォルト上限 1.3 m
	b.append([Vector3(8, 0.5, -20), Vector3(3, 1.0, 0.5), true, 30.0, 0.0])       # 斜め30°（自動補正の外）
	b.append([Vector3(-8, 0.5, -4), Vector3(3, 1.0, 0.5), true, 20.0, 0.0])       # 斜め20°（自動補正の内）
	b.append([Vector3(-8, 1.0, -30), Vector3(3, 2.0, 3), true, 0.0, 0.0])         # 2.0 m：歩いてクライム
	b.append([Vector3(-8, 3.0, -40), Vector3(3, 6.0, 3), true, 0.0, 0.0])         # 6 m：縦ウォールランでも届かない
	# --- 1.1 の技の試し用（主ルートの外）---
	b.append([Vector3(20.75, 3.0, -45), Vector3(0.5, 6, 12), true, 0.0, 0.0])     # ウォールキックの壁（面は x=20.5）
	b.append([Vector3(-16, 1.5, -52), Vector3(4, 3.0, 3), true, 0.0, 0.0])        # 3.0 m：落ちながらでは届かない縁（蹴り上がって掴む）
	b.append(_wall_at(12.0, -62.0, 1.0))                                          # ヴォルトジャンプの壁
	for x: float in [-19.2, -12.8]:                                               # スイングバーの支柱（バーは y=2.4, z=-72）
		b.append([Vector3(x, 1.4, -72), Vector3(0.2, 2.8, 0.2), false, 0.0, 0.0])
	b.append([Vector3(-16, 2.75, -72), Vector3(6.6, 0.1, 0.1), true, 0.0, 0.0, Kind.VISUAL])
	for z: float in [ZIP_HIGH.z, ZIP_LOW.z]:                                      # ジップラインの柱（線の横に立てて腕で吊る）
		var top := ZIP_HIGH.y if z == ZIP_HIGH.z else ZIP_LOW.y
		b.append([Vector3(ZIP_HIGH.x + 0.9, (top + 0.3) * 0.5, z), Vector3(0.25, top + 0.3, 0.25), false, 0.0, 0.0])
		b.append([Vector3(ZIP_HIGH.x + 0.45, top + 0.2, z), Vector3(0.9, 0.12, 0.12), false, 0.0, 0.0, Kind.VISUAL])
	return b


## スイングバー（a, b）とジップライン（高い端, 低い端）
const BAR_A := Vector3(-19.0, 2.4, -72.0)
const BAR_B := Vector3(-13.0, 2.4, -72.0)
const ZIP_HIGH := Vector3(16.0, 6.0, -70.0)
const ZIP_LOW := Vector3(16.0, 2.6, -96.0)


func _lines(geo: LevelGeometry, grabs: GrabLines) -> void:
	geo.add_beam(BAR_A, BAR_B, 0.05, LevelStyle.Mat.ROUTE)
	grabs.add_bar(BAR_A, BAR_B)
	geo.add_beam(ZIP_HIGH, ZIP_LOW, 0.025, LevelStyle.Mat.DARK)
	grabs.add_zip(ZIP_HIGH, ZIP_LOW)


func _wall_at(x: float, z: float, h: float) -> Array:
	return [Vector3(x, h * 0.5, z), Vector3(LANE, h, 0.5), true, 0.0, 0.0]


## 主ルートを横切る薄い壁
func _wall(z: float, h: float) -> Array:
	return [Vector3(0, h * 0.5, z), Vector3(LANE, h, 0.5), true, 0.0, 0.0]


## z0 から -z へ上る階段（1段 0.4 m × 奥行き 0.8 m）。
## 段の角を結ぶ見えない坂を重ねる。坂の上面は角をちょうど通るので、走ると坂だけに乗る。
## 段だけだと1段ごとに体が跳ね上がって詰まる（0.2.0-beta で不快だった）ため。
func _stairs(z0: float, steps: int) -> Array[Array]:
	var out: Array[Array] = []
	for i: int in steps:
		var h := STEP_RISE * (i + 1)
		out.append([Vector3(0, h * 0.5, z0 - STEP_RUN * (i + 0.5)), Vector3(LANE, h, STEP_RUN), false, 0.0, 0.0])
	# 坂：1段目の手前の床 (z0+run, 0) から、最上段の角 (z0-run*(n-1), rise*n) まで
	var a := Vector2(z0 + STEP_RUN, 0.0)
	var b := Vector2(z0 - STEP_RUN * (steps - 1), STEP_RISE * steps)
	var length := a.distance_to(b)
	var angle := atan2(STEP_RISE, STEP_RUN)
	var thick := 0.3
	var mid := (a + b) * 0.5
	# 上面が角を結ぶ線に来るよう、法線 (0, cos, sin) の逆向きに厚みの半分ずらす
	var center := Vector3(0, mid.y - cos(angle) * thick * 0.5, mid.x - sin(angle) * thick * 0.5)
	out.append([center, Vector3(LANE, thick, length), false, 0.0, rad_to_deg(angle), Kind.COLLIDER])
	return out


func _build() -> void:
	for c: Node in get_children():
		c.queue_free()
	var geo := LevelGeometry.new()
	geo.name = "Geometry"
	for b: Array in _layout():
		var kind: Kind = b[5] if b.size() > 5 else Kind.SOLID
		var flags := 0
		if kind == Kind.VISUAL:
			flags = LevelGeometry.NO_COLLIDE
		elif kind == Kind.COLLIDER:
			flags = LevelGeometry.NO_VISUAL
		var mat := LevelStyle.Mat.ROUTE if b[2] else LevelStyle.Mat.WHITE
		geo.add_box(b[0], b[1], mat, Vector3(b[4], b[3], 0.0), flags)
	var grabs := GrabLines.new()
	grabs.name = "GrabLines"
	_lines(geo, grabs)
	geo.build()
	add_child(geo)
	add_child(grabs)
