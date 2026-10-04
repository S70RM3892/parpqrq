class_name WindStreaks
extends MultiMeshInstance3D
## 風に舞う塵（仕様書 6章「スピード表現」）。空中に止まっている塵の間を走り抜けるので、後ろへ流れて見える。
## 速いほど長い線になり、濃くなる。粒はカメラの周りの箱に置き、後ろへ抜けたら前に置き直す。
## パーティクルではなく MultiMesh 1つ（描画1回）。

const COUNT_HIGH := 56
const COUNT_LOW := 24
const RADIUS := 12.0       ## m。カメラの周りのこの範囲に置く
const STREAK_TIME := 0.045 ## s。線の長さ = 速度 × これ
const WIDTH := 0.012       ## m

@export var player: Player

var _pos: PackedVector3Array = []
var _rng := RandomNumberGenerator.new()
var _alpha: float = 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.5, 0.0, 0.0)  # 原点が線の後ろ端
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wind_streak.gdshader")
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	Settings.changed.connect(_resize)
	_resize()


func _resize() -> void:
	var n := COUNT_HIGH if Settings.graphics_quality >= 1 else COUNT_LOW
	if multimesh.instance_count == n:
		return
	multimesh.instance_count = n
	_pos.resize(n)
	for i: int in n:
		_pos[i] = _random_around(Vector3.ZERO, Vector3.FORWARD, false)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or player == null:
		return
	var eye := cam.global_position
	global_transform = Transform3D.IDENTITY
	var v := player.velocity
	var spd := v.length()
	var prm := player.params
	var target := clampf((spd - prm.run_speed * 0.6) / (prm.max_flow_speed - prm.run_speed * 0.6), 0.0, 1.0)
	if not Settings.feel_camera:
		target = 0.0
	_alpha = lerpf(_alpha, target * Settings.speed_lines_strength, 1.0 - exp(-4.0 * delta))
	visible = _alpha > 0.01
	if not visible:
		return
	var dir := v / spd if spd > 0.1 else -cam.global_basis.z
	var length := maxf(spd * STREAK_TIME, 0.05)
	for i: int in _pos.size():
		var p := _pos[i]
		var rel := p - eye
		# 後ろへ抜けた・遠すぎる粒は前へ置き直す
		if rel.dot(dir) < -2.0 or rel.length() > RADIUS:
			p = _random_around(eye, dir, true)
			_pos[i] = p
			rel = p - eye
		# 線は進行方向の逆へ伸びる（塵から見て自分が動いた跡）。幅はカメラに向ける
		var axis := -dir * length
		var side := axis.cross(rel).normalized() * WIDTH
		var normal := axis.cross(side).normalized()
		multimesh.set_instance_transform(i, Transform3D(Basis(axis, side, normal), p))
		var fade := 1.0 - smoothstep(RADIUS * 0.6, RADIUS, rel.length())
		multimesh.set_instance_color(i, Color(1, 1, 1, _alpha * fade * smoothstep(0.6, 2.0, rel.length())))


func _random_around(center: Vector3, dir: Vector3, ahead: bool) -> Vector3:
	var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.8), _rng.randf_range(-1, 1)).normalized()
	off *= _rng.randf_range(1.5, RADIUS)
	if ahead and off.dot(dir) < 0.0:
		off -= dir * off.dot(dir) * 2.0  # 前の半分へ折り返す
	return center + off
