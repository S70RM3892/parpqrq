class_name GhostBody
extends Node3D
## ゴースト・リプレイの体（仕様書 5・8章：半透明の自分。距離が離れると矢印のみ）。
## 箱と円柱の人形を、記録された状態と速さから手続き的に動かす（骨格なし）。
## far_arrow = true なら、カメラから FAR より離れると体を消して頭上の矢印だけにする（壁越しにも見える）。

const FAR := 22.0

var far_arrow: bool = true
var color: Color = Color(1.0, 0.416, 0.102, 0.38)
## true = 影だけを落とす人形（1人称の自分の影。カメラには写らない）
var shadow_only: bool = false

var _phase: float = 0.0
var _state: int = 0
var _state_time: float = 0.0
var _parts: Dictionary[StringName, Node3D] = {}
var _arrow: Node3D
var _body: Node3D


func _ready() -> void:
	# 体はホログラム（縁が光り、走査線が流れる。shaders/ghost.gdshader）。影だけの人形は不透明の普通の材質
	var mat: Material
	if shadow_only:
		mat = StandardMaterial3D.new()
	else:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/ghost.gdshader")
		sm.set_shader_parameter(&"color", color)
		mat = sm
	_body = Node3D.new()
	add_child(_body)
	var hips := _pivot(&"hips", _body, Vector3(0, 0.95, 0))
	var torso := _pivot(&"torso", hips, Vector3.ZERO)
	_part(torso, CapsuleMesh, Vector3(0, 0.32, 0), Vector3(0.36, 0.62, 0.24), mat)
	_part(torso, SphereMesh, Vector3(0, 0.78, 0), Vector3(0.24, 0.26, 0.24), mat)
	for side: float in [-1.0, 1.0]:
		var key := &"r" if side > 0.0 else &"l"
		var shoulder := _pivot(StringName("arm_" + key), torso, Vector3(side * 0.22, 0.58, 0))
		_part(shoulder, CapsuleMesh, Vector3(0, -0.15, 0), Vector3(0.1, 0.32, 0.1), mat)
		var elbow := _pivot(StringName("fore_" + key), shoulder, Vector3(0, -0.3, 0))
		_part(elbow, CapsuleMesh, Vector3(0, -0.14, 0), Vector3(0.09, 0.3, 0.09), mat)
		var hip := _pivot(StringName("thigh_" + key), hips, Vector3(side * 0.1, -0.02, 0))
		_part(hip, CapsuleMesh, Vector3(0, -0.22, 0), Vector3(0.14, 0.46, 0.14), mat)
		var knee := _pivot(StringName("shin_" + key), hip, Vector3(0, -0.44, 0))
		_part(knee, CapsuleMesh, Vector3(0, -0.22, 0), Vector3(0.12, 0.46, 0.12), mat)
	if shadow_only:
		far_arrow = false
		for mi: Node in _body.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		return
	# 遠い時の矢印（壁越しにも見える）
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amat.no_depth_test = true
	amat.albedo_color = Color(color, 0.85)
	amat.render_priority = 10
	_arrow = Node3D.new()
	add_child(_arrow)
	for s: float in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.12, 0.9)
		bar.mesh = bm
		bar.material_override = amat
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.position = Vector3(s * 0.28, 0, 0.3)
		bar.rotation = Vector3(0, s * 0.6, 0)
		_arrow.add_child(bar)
	_arrow.visible = false


## 記録の1コマで動かす（delta は進めた時間）
func show_frame(sample: Dictionary, delta: float) -> void:
	global_position = sample.pos
	rotation = Vector3(0, sample.yaw, 0)
	var st: int = sample.state
	if st != _state:
		_state = st
		_state_time = 0.0
	_state_time += delta
	var spd: float = sample.speed
	_phase += delta * lerpf(2.0, 3.4, clampf(spd / 10.0, 0.0, 1.5)) * PI
	_pose(spd)
	if far_arrow:
		var cam := get_viewport().get_camera_3d()
		var far := cam != null and cam.global_position.distance_to(global_position) > FAR
		_body.visible = not far
		_arrow.visible = far
		if far:
			var d := cam.global_position.distance_to(global_position)
			_arrow.position = Vector3(0, 3.0 + d * 0.02, 0)
			_arrow.scale = Vector3.ONE * clampf(d / 25.0, 1.0, 4.0)


func _pose(spd: float) -> void:
	var s := sin(_phase)
	var run := clampf(spd / 10.0, 0.0, 1.3)
	var hips := _parts[&"hips"]
	var torso := _parts[&"torso"]
	var a := {&"arm_r": 0.0, &"arm_l": 0.0, &"fore_r": 0.5, &"fore_l": 0.5,
			&"thigh_r": 0.0, &"thigh_l": 0.0, &"shin_r": 0.0, &"shin_l": 0.0}
	var lean := 0.0
	var hip_y := 0.95
	var body_pitch := 0.0
	match _state:
		Player.State.GROUND, Player.State.WALL_RUN, Player.State.WALL_CLIMB:
			a[&"thigh_r"] = 0.7 * run * s
			a[&"thigh_l"] = -0.7 * run * s
			a[&"shin_r"] = 0.9 * run * maxf(-cos(_phase), 0.0) + 0.1
			a[&"shin_l"] = 0.9 * run * maxf(cos(_phase), 0.0) + 0.1
			a[&"arm_r"] = -0.8 * run * s
			a[&"arm_l"] = 0.8 * run * s
			lean = 0.25 * run
		Player.State.AIR, Player.State.VAULT, Player.State.CLIMB:
			a[&"thigh_r"] = 0.9
			a[&"thigh_l"] = 0.4
			a[&"shin_r"] = 1.2
			a[&"shin_l"] = 1.0
			a[&"arm_r"] = 1.2
			a[&"arm_l"] = 1.2
			lean = 0.3
		Player.State.SLIDE:
			hip_y = 0.45
			a[&"thigh_r"] = 1.4
			a[&"thigh_l"] = 0.9
			a[&"shin_l"] = 1.5
			a[&"arm_r"] = 0.4
			a[&"arm_l"] = -0.6
			lean = -0.8
		Player.State.ROLL:
			hip_y = 0.6
			body_pitch = -TAU * clampf(_state_time / 0.55, 0.0, 1.0)
			a[&"thigh_r"] = 1.8
			a[&"thigh_l"] = 1.8
			a[&"shin_r"] = 2.0
			a[&"shin_l"] = 2.0
			a[&"arm_r"] = 1.0
			a[&"arm_l"] = 1.0
		Player.State.LEDGE_HANG, Player.State.SWING, Player.State.ZIPLINE:
			if _state != Player.State.LEDGE_HANG:
				a[&"thigh_r"] = 0.8
				a[&"thigh_l"] = 0.5
				a[&"shin_r"] = 1.0
				a[&"shin_l"] = 1.2
			a[&"arm_r"] = 2.9
			a[&"arm_l"] = 2.9
			a[&"fore_r"] = 0.0
			a[&"fore_l"] = 0.0
			hip_y = 0.95
	hips.position = Vector3(0, hip_y, 0)
	hips.rotation = Vector3(body_pitch, 0, 0)
	torso.rotation = Vector3(-lean, 0, 0)
	for k: StringName in a:
		var n := _parts[k]
		var v: float = a[k]
		if String(k).begins_with("shin") or String(k).begins_with("fore"):
			n.rotation = Vector3(-v if String(k).begins_with("shin") else v, 0, 0)
		else:
			n.rotation = Vector3(v, 0, 0)


func _pivot(key: StringName, parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	parent.add_child(n)
	_parts[key] = n
	return n


func _part(parent: Node3D, mesh_type: Variant, at: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m: PrimitiveMesh
	if mesh_type == CapsuleMesh:
		var c := CapsuleMesh.new()
		c.radius = size.x * 0.5
		c.height = size.y
		c.radial_segments = 14
		c.rings = 4
		m = c
	else:
		var sp := SphereMesh.new()
		sp.radius = size.x * 0.5
		sp.height = size.y
		sp.radial_segments = 16
		sp.rings = 8
		m = sp
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	parent.add_child(mi)
