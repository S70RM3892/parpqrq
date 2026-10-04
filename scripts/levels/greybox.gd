@tool
class_name Greybox
extends Node3D
## 白い箱だけのテストコースを配列から組み立てる（M1の手触り検証用）。
## 箱1つ = [位置, 大きさ, ルート色か, Y回転(度), X回転(度)]。数値を書き換えれば形が変わる。

const WHITE := Color(0.92, 0.92, 0.9)
const ROUTE := Color("#FF6A1A")

## 各寸法は仕様書3章の判定値に合わせてある（段差0.45 / ヴォルト0.6〜1.3 / クライム〜2.4）
var boxes: Array[Array] = [
	# 床
	[Vector3(0, -0.5, 0), Vector3(80, 1, 80), false, 0.0, 0.0],
	# 段差 0.45 m
	[Vector3(-6, 0.225, 0), Vector3(3, 0.45, 3), false, 0.0, 0.0],
	# ヴォルト 0.6 / 1.0 / 1.3 m
	[Vector3(0, 0.3, -6), Vector3(3, 0.6, 0.5), true, 0.0, 0.0],
	[Vector3(0, 0.5, -12), Vector3(3, 1.0, 0.5), true, 0.0, 0.0],
	[Vector3(0, 0.65, -18), Vector3(3, 1.3, 0.5), true, 0.0, 0.0],
	# クライム 2.4 m の壁と上の足場
	[Vector3(0, 1.2, -26), Vector3(6, 2.4, 4), true, 0.0, 0.0],
	# ウォールラン用の長い壁
	[Vector3(8, 2.0, -14), Vector3(0.5, 4, 16), true, 0.0, 0.0],
	# 下り坂（スライド用）
	[Vector3(-10, 1.0, -16), Vector3(4, 0.4, 14), false, 0.0, -10.0],
	# 高所の足場
	[Vector3(-10, 2.2, -26), Vector3(4, 0.4, 6), true, 0.0, 0.0],
]


func _ready() -> void:
	_build()


func _build() -> void:
	for c: Node in get_children():
		c.queue_free()
	var white := _material(WHITE)
	var route := _material(ROUTE)
	for b: Array in boxes:
		var size: Vector3 = b[1]
		var body := StaticBody3D.new()
		body.position = b[0]
		body.rotation_degrees = Vector3(b[4], b[3], 0.0)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh.mesh = box_mesh
		mesh.material_override = route if b[2] else white
		body.add_child(shape)
		body.add_child(mesh)
		add_child(body)


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
