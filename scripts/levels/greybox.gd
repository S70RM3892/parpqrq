@tool
class_name Greybox
extends Node3D
## 白い箱だけのテストコース（M1の手触り検証用）。_layout() の数値を書き換えれば形が変わる。
## 箱1つ = [中心, 大きさ, ルート色か, Y回転(度), X回転(度), 種類]。ルート色 = 使える足場・縁（仕様書 6章）。
## 種類（省略可）: SOLID = 見た目＋当たり判定、VISUAL = 見た目だけ、COLLIDER = 当たり判定だけ（見えない坂など）

const WHITE := Color(0.92, 0.92, 0.9)
const ROUTE := Color("#FF6A1A")
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
	return b


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
	var white := _material(WHITE)
	var route := _material(ROUTE)
	for b: Array in _layout():
		var size: Vector3 = b[1]
		var kind: Kind = b[5] if b.size() > 5 else Kind.SOLID
		var root: Node3D = StaticBody3D.new() if kind != Kind.VISUAL else Node3D.new()
		root.position = b[0]
		root.rotation_degrees = Vector3(b[4], b[3], 0.0)
		if kind != Kind.VISUAL:
			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = size
			shape.shape = box_shape
			root.add_child(shape)
		if kind != Kind.COLLIDER:
			var mesh := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = size
			mesh.mesh = box_mesh
			mesh.material_override = route if b[2] else white
			root.add_child(mesh)
		add_child(root)


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
