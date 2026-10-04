class_name FirstPersonArms
extends Node3D
## 1人称の腕（仕様書 4章「体」）。Camera3D の子に置く。
## - 走行中は速度に応じて腕を大きく振る（速度メーターの代わり）
## - ヴォルト・クライム・ぶら下がりでは手が先に縁に着く（「掴んだ」確信）
## モデルは骨格のない前腕＋手の剛体なので、袖口を原点に位置と向きだけで動かす。

const SHOULDER := Vector3(0.2, -0.36, 0.22)  ## 右肩（カメラ基準）。左はxを反転
const ARM_REACH := 0.25                       ## 肩から袖口まで
const INWARD_DEG := 10.0
const REST_DEG := -40.0                       ## 振っていない時：画面外
const SWING_DEG := 45.0                       ## 全力疾走で前に振った時に画面下に入る
const HAND_PITCH_DEG := 15.0
const PLANT_SPREAD := 0.14                    ## 手を着く位置の左右の間隔
const PALM_ABOVE := 0.03                      ## 手のひら中心と上面の距離

@export var rig: CameraRig

var _palm: Vector3 = Vector3(0.0, 0.0, -0.29)

@onready var _right: Node3D = $Right
@onready var _left: Node3D = $Left


func _ready() -> void:
	var mesh := ($Right/Hand as MeshInstance3D).mesh
	if mesh.has_meta(&"palm"):
		_palm = mesh.get_meta(&"palm")
	_right.transform = _rest(1.0)
	_left.transform = _rest(-1.0)


func _process(delta: float) -> void:
	var p := rig.player
	visible = Settings.feel_body
	if p == null or not visible:
		return
	var planting := p.state == Player.State.VAULT or p.state == Player.State.CLIMB or p.state == Player.State.LEDGE_HANG
	var rate := 40.0 if planting else 18.0
	var w := 1.0 - exp(-rate * delta)
	_right.transform = _right.transform.interpolate_with(_pose(1.0, p), w)
	_left.transform = _left.transform.interpolate_with(_pose(-1.0, p), w)


func _pose(side: float, p: Player) -> Transform3D:
	var prm := p.params
	var theta := REST_DEG
	match p.state:
		Player.State.GROUND:
			var k := clampf((p.horizontal_speed() - prm.walk_speed) / (prm.run_speed - prm.walk_speed), 0.0, 1.3)
			# 腕は反対側の脚と同じ向きに振る（右脚が前 = sin>0 の時、右腕は後ろ）
			var swing := -side * sin(p.stride_phase_interpolated())
			theta = REST_DEG + k * SWING_DEG * (0.5 + 0.5 * swing)
		Player.State.AIR:
			theta = -5.0 if p.velocity.y > 0.0 else -15.0
		Player.State.VAULT:
			theta = -10.0
		Player.State.ROLL:
			theta = -75.0
		Player.State.WALL_RUN:
			# 壁側の手を上げて壁に添える、反対の手は振る
			var wall_hand := side == p.wall_side
			theta = 5.0 if wall_hand else REST_DEG + SWING_DEG * (0.5 - 0.5 * side * sin(p.stride_phase_interpolated()))
		Player.State.WALL_CLIMB:
			theta = 30.0 + 20.0 * side * sin(p.stride_phase_interpolated())
		Player.State.SLIDE:
			theta = -15.0 if side > 0.0 else -65.0
		Player.State.HARD_LAND:
			var t := p.state_time / prm.hard_land_stun
			theta = 0.0 if t < 0.5 else REST_DEG  # 両手を前に出して着地を受ける
	var xf := _arm(side, theta)
	if p.move == null:
		return xf
	var u := p.move_progress
	match p.state:
		Player.State.VAULT:
			# 片手（深い箱に乗る時は両手）を先に着く
			if side < 0.0 or p.move.onto:
				xf = xf.interpolate_with(_plant(side, p.move), smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.55, 0.8, u)))
		Player.State.CLIMB:
			# 両手で縁を掴み、体が上がりきるまで離さない
			xf = xf.interpolate_with(_plant(side, p.move), smoothstep(0.0, 0.1, u) * (1.0 - smoothstep(0.7, 0.95, u)))
		Player.State.LEDGE_HANG:
			xf = _plant(side, p.move)
	return xf


func _rest(side: float) -> Transform3D:
	return _arm(side, REST_DEG)


func _arm(side: float, theta_deg: float) -> Transform3D:
	var shoulder := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
	var r := Basis(Vector3.UP, deg_to_rad(-side * INWARD_DEG)) * Basis(Vector3.RIGHT, deg_to_rad(theta_deg))
	var cuff := shoulder + r * Vector3(0.0, 0.0, -ARM_REACH)
	return Transform3D(r * Basis(Vector3.RIGHT, deg_to_rad(HAND_PITCH_DEG)), cuff)


## 手のひらを上面の point に、指先を越える向きに合わせた姿勢（カメラ基準）
func _plant(side: float, v: VaultProbe.Result) -> Transform3D:
	var cam := get_parent() as Node3D
	var lateral := v.dir.cross(Vector3.UP).normalized()
	var target := v.hand + lateral * side * PLANT_SPREAD + Vector3.UP * PALM_ABOVE
	var world_basis := Basis.looking_at(v.dir, Vector3.UP) * Basis(Vector3.UP, deg_to_rad(side * 12.0))
	var inv := cam.global_transform.affine_inverse()
	var b := (inv.basis * world_basis).orthonormalized()
	var local_target := inv * target
	return Transform3D(b, local_target - b * _palm)
