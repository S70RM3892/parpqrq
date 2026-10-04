class_name Backdrop
extends Node3D
## 遠景の街（仕様書 6章：速度と高さが目で分かる絵）。コースから離れた所にビルを並べ、霧で白く飛ばす。
## ビルは MultiMesh 1つ（描画1回）。谷底の通りは大きな板1枚（高さフォグで白く消える）。

const CELL := 24.0
const CLEAR := 26.0      ## ルートからこれより近い所には置かない
const MARGIN := 170.0

var building_count: int = 0


## points = ルートの点、street_y = 通りの高さ、roof_y = だいたいの屋上の高さ
func build(points: PackedVector3Array, street_y: float, roof_y: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
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
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var x := lo.x
	while x < hi.x:
		var z := lo.y
		while z < hi.y:
			var c := Vector2(x + rng.randf_range(-4, 4), z + rng.randf_range(-4, 4))
			var near := INF
			for p: Vector2 in pts:
				near = minf(near, c.distance_squared_to(p))
			near = sqrt(near)
			if near > CLEAR and rng.randf() < 0.82:
				var w := rng.randf_range(12.0, 20.0)
				var d := rng.randf_range(12.0, 20.0)
				# 近くはコースの屋上より低く（下に街が広がって高さが分かる）、遠いほど高いビルが混ざる
				var far := clampf((near - CLEAR) / 140.0, 0.0, 1.0)
				var top := roof_y - lerpf(rng.randf_range(6.0, 22.0), rng.randf_range(-8.0, 12.0), far)
				if far > 0.4 and rng.randf() < 0.25:
					top += rng.randf_range(20.0, 75.0)
				var h := top - (street_y - 5.0)
				var b := Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)).scaled(Vector3(w, h, d))
				xforms.append(Transform3D(b, Vector3(c.x, street_y - 5.0 + h * 0.5, c.y)))
				customs.append(Color(rng.randf(), 0, 0))
			z += CELL
		x += CELL
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Buildings"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/backdrop.gdshader")
	mmi.material_override = mat
	add_child(mmi)
	# 谷底の通り
	var street := MeshInstance3D.new()
	street.name = "Street"
	var plane := PlaneMesh.new()
	plane.size = (hi - lo) + Vector2(400, 400)
	street.mesh = plane
	street.position = Vector3((lo.x + hi.x) * 0.5, street_y, (lo.y + hi.y) * 0.5)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.45, 0.46, 0.48)
	sm.roughness = 1.0
	street.material_override = sm
	street.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(street)
	building_count = xforms.size()
