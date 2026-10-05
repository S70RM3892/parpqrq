class_name FirstPersonArms
extends Node3D
## 1人称の腕（仕様書 4章「体」）。Camera3D の子に置く。
## - 走行中は速度に応じて腕を大きく振る（速度メーターの代わり）
## - ヴォルト・クライム・ぶら下がりでは手が先に縁に着く（「掴んだ」確信）
## 手は FirstPersonHand（手続き的に作る機械の手。指が3節ずつ曲がる）。袖口を原点に位置と向きで動かし、
## 状態ごとに指の形（握る・開く・手のひらを着く）を選ぶ。横ウォールラン中は壁側の手のひらを壁に添える。

const SHOULDER := Vector3(0.2, -0.36, 0.22)  ## 右肩（カメラ基準）。左はxを反転
const ARM_REACH := 0.25                       ## 肩から袖口まで
const INWARD_DEG := 10.0
const REST_DEG := -40.0                       ## 振っていない時：画面外
const SWING_DEG := 45.0                       ## 全力疾走で前に振った時に画面下に入る
const HAND_PITCH_DEG := 15.0
const PLANT_SPREAD := 0.14                    ## 手を着く位置の左右の間隔
const PALM_ABOVE := 0.005                     ## 手のひら中心と面の距離（手のひらのゴムの厚み）
const WALL_GAP := 0.35                        ## 体の中心から壁まで（カプセルの半径）

@export var rig: CameraRig

var _palm: Vector3 = FirstPersonHand.PALM

@onready var _right: Node3D = $Right
@onready var _left: Node3D = $Left
@onready var _hand_r: FirstPersonHand = $Right/Hand
@onready var _hand_l: FirstPersonHand = $Left/Hand


func _ready() -> void:
	_right.transform = _rest(1.0)
	_left.transform = _rest(-1.0)


func _process(delta: float) -> void:
	var p := rig.player
	visible = Settings.feel_body
	if p == null or not visible:
		return
	var planting := p.state in [Player.State.VAULT, Player.State.CLIMB, Player.State.LEDGE_HANG, Player.State.SWING, Player.State.ZIPLINE]
	var rate := 40.0 if planting else 18.0
	var w := 1.0 - exp(-rate * delta)
	_right.transform = _right.transform.interpolate_with(_pose(1.0, p), w)
	_left.transform = _left.transform.interpolate_with(_pose(-1.0, p), w)
	var wf := 1.0 - exp(-(30.0 if planting else 14.0) * delta)
	var fr := _fingers(1.0, p)
	var fl := _fingers(-1.0, p)
	_hand_r.blend_pose(fr.x, fr.y, fr.z, wf)
	_hand_l.blend_pose(fl.x, fl.y, fl.z, wf)


## 指の形（握り, 開き, 親指）。握る = 棒・縁、開く = 空中で前へ伸ばす、手のひらを着く = 面に押し当てる
func _fingers(side: float, p: Player) -> Vector3:
	const FIST := Vector3(0.62, 0.0, 0.65)
	const OPEN := Vector3(0.22, 0.45, 0.2)
	const FLAT := Vector3(-0.05, 0.6, 0.05)
	const GRIP := Vector3(0.95, 0.0, 0.92)
	const HOOK := Vector3(0.62, 0.15, 0.35)
	var u := p.move_progress
	match p.state:
		Player.State.GROUND:
			return FIST.lerp(OPEN, clampf(1.0 - p.horizontal_speed() / p.params.run_speed, 0.0, 1.0) * 0.6)
		Player.State.AIR:
			return OPEN
		Player.State.VAULT:
			return FLAT if (side < 0.0 or (p.move != null and p.move.onto)) and u < 0.75 else OPEN
		Player.State.CLIMB:
			return HOOK if u < 0.35 else FLAT
		Player.State.LEDGE_HANG:
			return HOOK
		Player.State.SWING, Player.State.ZIPLINE:
			return GRIP
		Player.State.WALL_RUN:
			return FLAT if side == p.wall_side else FIST
		Player.State.WALL_CLIMB:
			return OPEN
		Player.State.SLIDE:
			return FLAT if side < 0.0 else FIST
		Player.State.ROLL:
			return Vector3(0.8, 0.0, 0.8)
		Player.State.HARD_LAND:
			return FLAT
	return FIST


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
			# 壁側の手は壁に添える（_wall_touch）、反対の手は振る
			if side == p.wall_side and p.wall_normal != Vector3.ZERO:
				return _wall_touch(p)
			theta = REST_DEG + SWING_DEG * (0.5 - 0.5 * side * sin(p.stride_phase_interpolated()))
		Player.State.WALL_CLIMB:
			theta = 30.0 + 20.0 * side * sin(p.stride_phase_interpolated())
		Player.State.SLIDE:
			theta = -15.0 if side > 0.0 else -65.0
		Player.State.HARD_LAND:
			var t := p.state_time / prm.hard_land_stun
			theta = 0.0 if t < 0.5 else REST_DEG  # 両手を前に出して着地を受ける
		Player.State.SWING, Player.State.ZIPLINE:
			theta = 60.0
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
			xf = _plant(side, p.move)  # 両手で縁を掴む
		Player.State.SWING, Player.State.ZIPLINE:
			xf = _hang(side, p.move)  # 両手でバー・線を下から握る
	return xf


## 横ウォールラン：壁側の手のひらを、肩の少し前の壁に添える（指先は進む向きの斜め上）
func _wall_touch(p: Player) -> Transform3D:
	var cam := get_parent() as Node3D
	var n := p.wall_normal
	var eye := cam.global_position
	var vel := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var fwd := vel.normalized() if vel.length() > 0.5 else -cam.global_basis.z
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var base := eye + fwd * 0.3 + Vector3.DOWN * 0.18
	# 体（カプセルの中心）から壁までは半径ぶん。手のひらをその面へ
	var center := p.get_global_transform_interpolated().origin
	var off := (base - center).dot(n) + WALL_GAP - PALM_ABOVE
	var target := base - n * off
	var dir := (fwd + Vector3.UP * 0.55).normalized()
	var world_basis := Basis.looking_at(dir, n)
	var inv := cam.global_transform.affine_inverse()
	var b := (inv.basis * world_basis).orthonormalized()
	return Transform3D(b, inv * target - b * _palm)


func _rest(side: float) -> Transform3D:
	return _arm(side, REST_DEG)


func _arm(side: float, theta_deg: float) -> Transform3D:
	var shoulder := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
	var r := Basis(Vector3.UP, deg_to_rad(-side * INWARD_DEG)) * Basis(Vector3.RIGHT, deg_to_rad(theta_deg))
	var cuff := shoulder + r * Vector3(0.0, 0.0, -ARM_REACH)
	return Transform3D(r * Basis(Vector3.RIGHT, deg_to_rad(HAND_PITCH_DEG)), cuff)


## 手のひらを上面の point に、指先を越える向きに合わせた姿勢（カメラ基準）
## スイング・ジップライン：バー・線を下から握る。前腕は肩から握る所へ伸び、手のひらは前を向く。
## 右手はカメラの右（線が前へ延びるジップラインでは前）に来る
func _hang(side: float, v: VaultProbe.Result) -> Transform3D:
	var cam := get_parent() as Node3D
	var along := v.dir.cross(Vector3.UP).normalized()
	var fwd := -cam.global_basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var s := 1.0 if along.dot(cam.global_basis.x * side + fwd * side * 0.3) >= 0.0 else -1.0
	var grip := v.hand + along * s * PLANT_SPREAD
	var shoulder := cam.global_position + cam.global_basis.x * side * 0.2 + Vector3.DOWN * 0.3
	var reach := (grip - shoulder).normalized()
	var inv := cam.global_transform.affine_inverse()
	var b := (inv.basis * Basis.looking_at(reach, -fwd)).orthonormalized()
	var local_target := inv * (grip - fwd * 0.03 + Vector3.DOWN * 0.035)
	return Transform3D(b, local_target - b * _palm)


func _plant(side: float, v: VaultProbe.Result) -> Transform3D:
	var cam := get_parent() as Node3D
	var lateral := v.dir.cross(Vector3.UP).normalized()
	var target := v.hand + lateral * side * PLANT_SPREAD + Vector3.UP * PALM_ABOVE
	var world_basis := Basis.looking_at(v.dir, Vector3.UP) * Basis(Vector3.UP, deg_to_rad(side * 12.0))
	var inv := cam.global_transform.affine_inverse()
	var b := (inv.basis * world_basis).orthonormalized()
	var local_target := inv * target
	return Transform3D(b, local_target - b * _palm)
