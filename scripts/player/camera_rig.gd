class_name CameraRig
extends Node3D
## 1人称カメラリグ（仕様書 4章）。
## 体に直付けせず top_level で目の位置に追従させる。視点回転は入力を受けたフレームで即反映し、
## 物理補間の1tick遅れを視点に乗せない（入力→画面 3フレーム以内）。
## 演出は層ごとのノードに分け、層単位でON/OFFできる:
##   CameraRig(yaw) > Pitch > Bob > Dip > Tilt > Shake > Camera3D
## Bob/Dip/Tilt と速度FOV は「カメラ」層（Settings.feel_camera）、Shake は「衝撃」層（feel_impact）。

const MOUSE_DEG_PER_PX := 0.08
const STICK_DEG_PER_SEC := 220.0
const PITCH_LIMIT_DEG := 89.0
const LAYER_NAMES: Array[StringName] = [&"bob", &"dip", &"tilt", &"shake"]

# 演出の初期値（仕様書 4章の表）
const BOB_AMP := 0.025              ## m。縦揺れ
const BOB_SWAY := 0.1               ## 横揺れ = 縦の10%（極小）
const DIP_MAX := 0.12               ## m。着地ディップ
const DIP_DOWN_TIME := 0.05         ## s。沈むまで
const DIP_RETURN_TIME := 0.18       ## s。戻るまで
const SPEED_FOV_MAX := 12.0         ## 度
const VAULT_PITCH_DEG := 8.0        ## ヴォルト前半の前傾
const ROLL_PITCH_DEG := 30.0
const ROLL_EYE_DROP := 0.55         ## m
const HARD_LAND_EYE_DROP := 0.35    ## m
const SLIDE_EYE_DROP := 0.9         ## m
const SLIDE_PITCH_DEG := 5.0        ## 後傾
const WALLRUN_ROLL_DEG := 10.0      ## 壁と反対側へ
const SHAKE_DECAY := 1.5            ## トラウマ/秒
const SHAKE_ROT_DEG := Vector3(2.0, 2.0, 3.0)
const SHAKE_POS := 0.03
const SHAKE_FREQ := 22.0

## 目の位置。Player の EyeAnchor を指す
@export var eye: Node3D

var yaw: float = 0.0
var pitch: float = 0.0
## Player が _ready で入れる
var player: Player:
	set(p):
		player = p
		p.landed.connect(_on_landed)
		p.rolled.connect(_on_rolled)
		p.hard_landed.connect(func(_d: float) -> void: add_trauma(0.5))
		p.crashed.connect(func(_s: float) -> void: add_trauma(0.6))

var _layers: Dictionary[StringName, Node3D] = {}
var _layer_enabled: Dictionary[StringName, bool] = {}
var _bob_amp: float = 0.0
var _dip_amount: float = 0.0
var _dip_t: float = INF
var _pose_drop: float = 0.0
var _pose_pitch: float = 0.0
var _pose_roll: float = 0.0
var _step_offset: float = 0.0
var _trauma: float = 0.0
var _time: float = 0.0
var _speed_fov: float = 0.0
var _noise := FastNoiseLite.new()

@onready var _pitch: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Bob/Dip/Tilt/Shake/Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_layers = {
		&"bob": $Pitch/Bob,
		&"dip": $Pitch/Bob/Dip,
		&"tilt": $Pitch/Bob/Dip/Tilt,
		&"shake": $Pitch/Bob/Dip/Tilt/Shake,
	}
	for n: StringName in LAYER_NAMES:
		_layer_enabled[n] = true
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var d: Vector2 = mm.screen_relative * MOUSE_DEG_PER_PX
		_add_look(-d.x * Settings.sensitivity_x, -d.y * Settings.sensitivity_y * _invert())
	elif event is InputEventMouseButton and event.is_pressed() and not get_tree().paused:
		_capture_mouse(true)
	elif event.is_action_pressed(&"pause"):
		_capture_mouse(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_capture_mouse(false)


func _process(delta: float) -> void:
	_time += delta
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO and not get_tree().paused:
		# 2乗カーブ：小さく倒した時の微調整をしやすくする
		stick *= stick.length()
		var step := STICK_DEG_PER_SEC * delta
		_add_look(-stick.x * step * Settings.sensitivity_x, -stick.y * step * Settings.sensitivity_y * _invert())
	_step_offset *= exp(-delta / 0.05)
	if eye != null:
		global_position = eye.get_global_transform_interpolated().origin + Vector3.UP * _step_offset
	if player != null:
		_update_camera_layer(delta)
		_update_shake(delta)


## 向きを即座に合わせる（リスポーン等）
func snap(new_yaw: float, new_pitch: float = 0.0) -> void:
	yaw = new_yaw
	pitch = new_pitch
	_apply_rotation()
	_step_offset = 0.0
	_dip_t = INF
	_trauma = 0.0
	if eye != null:
		global_position = eye.global_position


## 段差を乗り越えた時の目線の跳ねを吸収する（dy だけ下げてから素早く戻す）
func absorb_step(dy: float) -> void:
	_step_offset -= dy


## 0〜1。揺れの大きさはその2乗
func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func set_layer_enabled(layer_name: StringName, on: bool) -> void:
	_layer_enabled[layer_name] = on
	if not on:
		_layers[layer_name].transform = Transform3D.IDENTITY


func is_layer_enabled(layer_name: StringName) -> bool:
	return _layer_enabled.get(layer_name, false)


func layer(layer_name: StringName) -> Node3D:
	return _layers[layer_name]


# --- 演出 ---------------------------------------------------------------

func _on_landed(impact: float, _drop: float) -> void:
	var hard_speed := player.params.fall_speed_from(player.params.hard_land_drop)
	_dip_amount = DIP_MAX * clampf(impact / hard_speed, 0.0, 1.0)
	_dip_t = 0.0


func _on_rolled(drop: float) -> void:
	if drop >= player.params.hard_land_drop:
		add_trauma(0.25)


func _update_camera_layer(delta: float) -> void:
	var p := player
	var on := Settings.feel_camera
	var spd := p.horizontal_speed()

	# 速度FOV：通常最高を超えた分に比例
	var over := clampf((spd - p.params.run_speed) / maxf(p.params.max_flow_speed - p.params.run_speed, 0.01), 0.0, 1.0)
	var fov_target := SPEED_FOV_MAX * over * Settings.speed_fov_strength if on else 0.0
	_speed_fov = lerpf(_speed_fov, fov_target, 1.0 - exp(-6.0 * delta))
	camera.fov = clampf(Settings.fov, 75.0, 110.0) + _speed_fov

	# ヘッドボブ：足の接地で一番下がる
	var grounded := p.state == Player.State.GROUND and p.is_on_floor()
	var amp_target := BOB_AMP * clampf(spd / p.params.run_speed, 0.0, 1.3) if grounded else 0.0
	_bob_amp = lerpf(_bob_amp, amp_target, 1.0 - exp(-10.0 * delta))
	var ph := p.stride_phase_interpolated()
	var bob_k := Settings.head_bob_strength if on else 0.0
	_set_layer(&"bob", Vector3(_bob_amp * BOB_SWAY * sin(ph), -_bob_amp * (1.0 - absf(sin(ph))), 0.0) * bob_k, Vector3.ZERO)

	# 着地ディップ＋状態ごとの姿勢（ローリングで目線が下がる、ハードランディングでしゃがむ）
	_dip_t += delta
	var dip := 0.0
	if _dip_t < DIP_DOWN_TIME:
		dip = _dip_amount * _ease_out(_dip_t / DIP_DOWN_TIME)
	elif _dip_t < DIP_DOWN_TIME + DIP_RETURN_TIME:
		dip = _dip_amount * (1.0 - smoothstep(0.0, 1.0, (_dip_t - DIP_DOWN_TIME) / DIP_RETURN_TIME))
	var drop_target := 0.0
	var pitch_target := 0.0
	match p.state:
		Player.State.ROLL:
			var t := clampf(p.state_time / p.params.roll_duration, 0.0, 1.0)
			drop_target = ROLL_EYE_DROP * sin(PI * t)
			pitch_target = -ROLL_PITCH_DEG * sin(PI * t)
		Player.State.HARD_LAND:
			var t := clampf(p.state_time / p.params.hard_land_stun, 0.0, 1.0)
			drop_target = HARD_LAND_EYE_DROP * (1.0 - smoothstep(0.55, 1.0, t))
			pitch_target = -6.0 * (1.0 - smoothstep(0.55, 1.0, t))
		Player.State.VAULT, Player.State.CLIMB:
			# 技の前半に手を見下ろす
			pitch_target = -VAULT_PITCH_DEG * sin(PI * clampf(p.move_progress / 0.5, 0.0, 1.0))
		Player.State.SLIDE:
			drop_target = SLIDE_EYE_DROP
			pitch_target = SLIDE_PITCH_DEG
	var roll_target := 0.0
	if p.state == Player.State.WALL_RUN:
		# 右の壁なら左へ傾ける（rotation.z が + で視界は左に傾く）
		roll_target = WALLRUN_ROLL_DEG * p.wall_side
	_pose_drop = lerpf(_pose_drop, drop_target, 1.0 - exp(-25.0 * delta))
	_pose_pitch = lerpf(_pose_pitch, pitch_target, 1.0 - exp(-25.0 * delta))
	_pose_roll = lerpf(_pose_roll, roll_target, 1.0 - exp(-12.0 * delta))
	var dip_k := 1.0 if on else 0.0
	_set_layer(&"dip", Vector3(0.0, -(dip + _pose_drop) * dip_k, 0.0), Vector3.ZERO)
	var nod := -3.0 * dip / DIP_MAX
	var tilt_k := Settings.camera_tilt_strength * dip_k
	_set_layer(&"tilt", Vector3.ZERO, Vector3(deg_to_rad((_pose_pitch + nod) * tilt_k), 0.0, deg_to_rad(_pose_roll * tilt_k)))


func _update_shake(delta: float) -> void:
	_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)
	var s := _trauma * _trauma * Settings.screen_shake_strength
	if not Settings.feel_impact:
		s = 0.0
	var t := _time * SHAKE_FREQ
	var rot := Vector3(
		deg_to_rad(SHAKE_ROT_DEG.x) * _noise.get_noise_2d(t, 0.0),
		deg_to_rad(SHAKE_ROT_DEG.y) * _noise.get_noise_2d(t, 100.0),
		deg_to_rad(SHAKE_ROT_DEG.z) * _noise.get_noise_2d(t, 200.0)) * s
	var pos := Vector3(_noise.get_noise_2d(t, 300.0), _noise.get_noise_2d(t, 400.0), 0.0) * SHAKE_POS * s
	_set_layer(&"shake", pos, rot)


func _set_layer(layer_name: StringName, pos: Vector3, rot: Vector3) -> void:
	if not _layer_enabled[layer_name]:
		return
	var n := _layers[layer_name]
	n.position = pos
	n.rotation = rot


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


# --- 視点 ---------------------------------------------------------------

func _add_look(yaw_deg: float, pitch_deg: float) -> void:
	yaw = wrapf(yaw + deg_to_rad(yaw_deg), -PI, PI)
	pitch = clampf(pitch + deg_to_rad(pitch_deg), deg_to_rad(-PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch.rotation = Vector3(pitch, 0.0, 0.0)


func _invert() -> float:
	return -1.0 if Settings.invert_y else 1.0


func _capture_mouse(on: bool) -> void:
	if OS.has_feature("mobile"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
