class_name FirstPersonLegs
extends Node3D
## 1人称の脚（仕様書 4章「体」：下を見れば足が見える）。Player の子に top_level で置く。
## モデルは骨格のない機械脚を膝・足首の関節ディスク中心で3分割したもの（tools/build_body.gd）。
## 股関節・膝・足首の角度を足取り位相から手続き的に決め、低い方の足が地面に着く高さに腰を置く。

## 関節の位置（build_body.gd の出力）
const KNEE_OFFSET := Vector3(0.0, -0.3467, -0.0251)
const ANKLE_OFFSET := Vector3(0.0, -0.4507, 0.0553)
const SOLE_BELOW_ANKLE := 0.0825
const HIP_WIDTH := 0.11
const BODY_BACK := 0.0    ## 脚の前後位置（+で後ろ）。胴体が無いので真下に置く

@export var player: Player

var _yaw: float = 0.0
## 脚ごとの [股関節, 膝, 足首]（度）。なめらかに目標へ寄せる
var _cur: Dictionary[StringName, Vector3] = {&"r": Vector3.ZERO, &"l": Vector3.ZERO}

@onready var _legs: Dictionary[StringName, Array] = {
	&"r": [$HipR/Thigh, $HipR/Thigh/Shin, $HipR/Thigh/Shin/Foot],
	&"l": [$HipL/Thigh, $HipL/Thigh/Shin, $HipL/Thigh/Shin/Foot],
}


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	visible = Settings.feel_body
	if player == null or not visible:
		return
	var rig := player.rig
	_yaw = lerp_angle(_yaw, rig.yaw, 1.0 - exp(-12.0 * delta))
	var ph := player.stride_phase_interpolated()
	var w := 1.0 - exp(-20.0 * delta)
	var lowest := 0.0
	for key: StringName in [&"r", &"l"]:
		var leg_phase := ph if key == &"r" else ph + PI
		var target := _pose(key, leg_phase)
		_cur[key] = _cur[key].lerp(target, w)
		var a := _cur[key]
		var parts := _legs[key]
		(parts[0] as Node3D).rotation = Vector3(deg_to_rad(a.x), 0.0, 0.0)
		(parts[1] as Node3D).rotation = Vector3(deg_to_rad(-a.y), 0.0, 0.0)
		(parts[2] as Node3D).rotation = Vector3(deg_to_rad(a.z), 0.0, 0.0)
		lowest = maxf(lowest, _reach(a))
	var grounded := player.state != Player.State.AIR and player.state != Player.State.VAULT
	var hip_y := lowest if grounded else KNEE_OFFSET.length() + ANKLE_OFFSET.length() + SOLE_BELOW_ANKLE
	var origin := player.get_global_transform_interpolated().origin
	var b := Basis(Vector3.UP, _yaw)
	global_transform = Transform3D(b, origin + Vector3.UP * hip_y + b * Vector3(0.0, 0.0, BODY_BACK))


## [股関節, 膝, 足首] の目標角度（度）。股関節は+で脚が前、膝は+で曲がる、足首は+でつま先が上
func _pose(key: StringName, leg_phase: float) -> Vector3:
	var p := player
	var prm := p.params
	var right := key == &"r"
	match p.state:
		Player.State.GROUND:
			var s := clampf(p.horizontal_speed() / prm.run_speed, 0.0, 1.3)
			var hip := lerpf(4.0, 38.0, s) * sin(leg_phase)
			var swing := pow(maxf(cos(leg_phase), 0.0), 1.5)  # 脚が前へ戻る間に膝を畳む
			var knee := lerpf(6.0, 95.0, s) * (0.08 + 0.92 * swing)
			return Vector3(hip, knee, (knee - hip) * 0.85 - 12.0 * swing * s)
		Player.State.AIR:
			if p.velocity.y < -6.0:
				return Vector3(15.0, 25.0, 0.0) if right else Vector3(5.0, 35.0, 10.0)
			return Vector3(30.0, 60.0, 20.0) if right else Vector3(-15.0, 80.0, 40.0)
		Player.State.VAULT:
			return Vector3(70.0, 110.0, 30.0) if right else Vector3(55.0, 120.0, 40.0)
		Player.State.ROLL:
			return Vector3(100.0, 140.0, 30.0)
		Player.State.HARD_LAND:
			var t := p.state_time / prm.hard_land_stun
			var k := 1.0 - smoothstep(0.55, 1.0, t)
			return Vector3(55.0, 100.0, 45.0) * k
	return Vector3.ZERO


## 股関節から足裏までの鉛直距離
func _reach(a: Vector3) -> float:
	var r_hip := Basis(Vector3.RIGHT, deg_to_rad(a.x))
	var r_shin := r_hip * Basis(Vector3.RIGHT, deg_to_rad(-a.y))
	var r_foot := r_shin * Basis(Vector3.RIGHT, deg_to_rad(a.z))
	var sole := r_hip * KNEE_OFFSET + r_shin * ANKLE_OFFSET + r_foot * Vector3(0.0, -SOLE_BELOW_ANKLE, 0.0)
	return -sole.y
