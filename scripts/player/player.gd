class_name Player
extends CharacterBody3D
## 1人称パルクールの動き（仕様書 3章）。M1：走り・ジャンプ・ヴォルト・ローリング・ハードランディング。
## 速度計算は全部自前で行い、move_and_slide() は衝突処理だけに使う。
## 演出（カメラ・体・振動）はここでは行わず、シグナルと公開している状態を各層が読む。

signal jumped
signal footstep
## impact = 着地時の落下速度 m/s、drop = 最高点からの落差 m
signal landed(impact: float, drop: float)
signal rolled(drop: float)
signal hard_landed(drop: float)
signal vault_started
## 壁に正面からぶつかった。speed = 壁に向かっていた速度 m/s
signal crashed(speed: float)

enum State { GROUND, AIR, VAULT, ROLL, HARD_LAND }

const TUNED_PATH := "user://movement_tuned.tres"
const CRASH_SPEED := 5.0  ## m/s。これより速く壁に当たると激突

@export var params: MovementParams

var state: State = State.AIR
var state_time: float = 0.0
## 足取りの位相。π進むごとに1歩
var stride_phase: float = 0.0
var prev_stride_phase: float = 0.0
## ヴォルト中の情報（体の層が手を着く位置に使う）
var vault: VaultProbe.Result
var vault_progress: float = 0.0
var spawn: Transform3D

var _since_floor: float = 0.0
var _since_jump_press: float = INF
var _since_crouch_press: float = INF
var _jumped: bool = false
var _jump_cut_done: bool = false
var _air_peak_y: float = 0.0
var _vy_before_move: float = 0.0
## 大きな落下の着地直後、ローリング入力を待つ時間（仕様：着地の0.2 s前〜直後）
var _pending_drop: float = 0.0
var _pending_time: float = -1.0
var _vault_duration: float = 0.0
var _vault_speed_in: float = 0.0

@onready var rig: CameraRig = $CameraRig
@onready var _capsule: CapsuleShape3D = ($CollisionShape3D as CollisionShape3D).shape


func _ready() -> void:
	add_to_group(&"player")
	# 実機で調整パネルから保存した値（エディタ実行では res:// の既定値を直接書き換えるので読まない）
	if not OS.has_feature("editor") and ResourceLoader.exists(TUNED_PATH):
		var tuned := load(TUNED_PATH) as MovementParams
		if tuned != null:
			params = tuned
	spawn = global_transform
	rig.player = self
	footstep.connect(Haptics.step)
	landed.connect(func(impact: float, _drop: float) -> void:
		if impact > 3.0:
			Haptics.land())
	hard_landed.connect(func(_drop: float) -> void: Haptics.hard_land())
	rig.snap(rotation.y)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"retry") or global_position.y < -30.0:
		respawn()
		return
	_since_jump_press = 0.0 if Input.is_action_just_pressed(&"jump") else _since_jump_press + delta
	_since_crouch_press = 0.0 if Input.is_action_just_pressed(&"crouch") else _since_crouch_press + delta
	state_time += delta

	match state:
		State.GROUND:
			_ground(delta)
		State.AIR:
			_air(delta)
		State.VAULT:
			_vault(delta)
		State.ROLL:
			_roll(delta)
		State.HARD_LAND:
			_hard_land(delta)
	_update_stride(delta)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 物理tick間を補間した足取り位相（描画側が使う）
func stride_phase_interpolated() -> float:
	return lerpf(prev_stride_phase, stride_phase, Engine.get_physics_interpolation_fraction())


func respawn() -> void:
	global_transform = spawn
	velocity = Vector3.ZERO
	_pending_time = -1.0
	_set_state(State.AIR)
	reset_physics_interpolation()
	rig.snap(spawn.basis.get_euler().y)


# --- 状態 ---------------------------------------------------------------

func _ground(delta: float) -> void:
	var h := _steer(Vector3(velocity.x, 0.0, velocity.z), _desired_velocity(), 1.0, delta)
	velocity = Vector3(h.x, minf(velocity.y, 0.0), h.z)

	if _pending_time >= 0.0:
		_pending_time += delta
		if _since_crouch_press <= _pending_time:
			_start_roll(_pending_drop)
			return
		if _pending_time > params.roll_window_after:
			_pending_time = -1.0
			if _pending_drop >= params.hard_land_drop:
				_start_hard_land(_pending_drop)
				return
	elif _since_jump_press <= params.jump_buffer:
		if not _try_vault():
			_jump()
			_move(delta, false)  # 押したフレームで上昇を始める
		return

	_move(delta, true)
	if is_on_floor():
		_since_floor = 0.0
	else:
		_leave_ground()


func _air(delta: float) -> void:
	_since_floor += delta
	var h := _steer(Vector3(velocity.x, 0.0, velocity.z), _desired_velocity(), params.air_control, delta)
	velocity.x = h.x
	velocity.z = h.z
	if not _jumped and _since_floor <= params.coyote_time and _since_jump_press <= params.jump_buffer:
		if not _try_vault():
			_jump()
			_move(delta, false)
		return
	if _jumped and not _jump_cut_done and velocity.y > 0.0 and not Input.is_action_pressed(&"jump"):
		velocity.y *= 1.0 - params.jump_cut_max
		_jump_cut_done = true
	_move(delta, false)
	_air_peak_y = maxf(_air_peak_y, global_position.y)
	if is_on_floor():
		_land()


func _vault(delta: float) -> void:
	var v := vault
	vault_progress = clampf(state_time / _vault_duration, 0.0, 1.0)
	var d := v.back_dist * vault_progress
	var pos := v.start + v.dir * d
	pos.y = _vault_height(v, d)
	var prev := global_position
	global_position = pos
	velocity = (pos - prev) / delta
	if vault_progress >= 1.0:
		var out := v.dir * maxf(_vault_speed_in, params.walk_speed) * params.vault_speed_keep
		velocity = Vector3(out.x, 0.0, out.z)
		vault = null
		if v.land_on_ground:
			apply_floor_snap()
			_set_state(State.GROUND)
			_since_floor = 0.0
			if _since_jump_press <= params.move_buffer:
				_vault_or_jump()  # 技の最中の先行入力
		else:
			_leave_ground()


func _roll(delta: float) -> void:
	# 速度を落とさず転がる。向きは少しだけ変えられる
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var spd := h.length()
	var want := _desired_velocity()
	if want != Vector3.ZERO and spd > 0.1:
		h = h.slerp(want.normalized() * spd, minf(1.0, 2.0 * delta))
	velocity = Vector3(h.x, minf(velocity.y, 0.0), h.z)
	_move(delta, true)
	var t := state_time / params.roll_duration
	if not is_on_floor():
		_leave_ground()
	elif t >= 0.5 and _since_jump_press <= params.move_buffer:
		_set_state(State.GROUND)
		_vault_or_jump()
	elif t >= 1.0:
		_set_state(State.GROUND)


func _hard_land(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	h = h.move_toward(Vector3.ZERO, params.run_speed / params.decel_time * 0.25 * delta)
	velocity = Vector3(h.x, minf(velocity.y, 0.0), h.z)
	_move(delta, true)
	if state_time >= params.hard_land_stun:
		_set_state(State.GROUND if is_on_floor() else State.AIR)


# --- 遷移 ---------------------------------------------------------------

func _set_state(s: State) -> void:
	state = s
	state_time = 0.0


func _vault_or_jump() -> void:
	if not _try_vault():
		_jump()


func _jump() -> void:
	velocity.y = params.jump_velocity()
	_since_jump_press = INF
	_leave_ground()
	_jumped = true
	jumped.emit()


func _leave_ground() -> void:
	_set_state(State.AIR)
	_jumped = false
	_jump_cut_done = false
	_air_peak_y = global_position.y
	_pending_time = -1.0


func _land() -> void:
	var drop := _air_peak_y - global_position.y
	var impact := maxf(-_vy_before_move, 0.0)
	_set_state(State.GROUND)
	_since_floor = 0.0
	velocity.y = 0.0
	landed.emit(impact, drop)
	if drop >= params.roll_min_drop:
		if _since_crouch_press <= params.roll_window_before:
			_start_roll(drop)
		else:
			_pending_drop = drop
			_pending_time = 0.0


func _start_roll(drop: float) -> void:
	_pending_time = -1.0
	_since_crouch_press = INF
	_set_state(State.ROLL)
	rolled.emit(drop)


func _start_hard_land(drop: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z) * (1.0 - params.hard_land_speed_loss)
	velocity = Vector3(h.x, 0.0, h.z)
	_set_state(State.HARD_LAND)
	hard_landed.emit(drop)


func _try_vault() -> bool:
	var spd := horizontal_speed()
	if spd < params.vault_min_speed:
		return false
	var dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	var r := VaultProbe.probe(self, dir, spd, params, _capsule.radius, _capsule.height)
	if r == null:
		return false
	vault = r
	vault_progress = 0.0
	_vault_speed_in = spd
	_vault_duration = clampf(r.back_dist / (spd * params.vault_speed_keep),
			params.vault_min_duration, params.vault_max_duration)
	_since_jump_press = INF
	_pending_time = -1.0
	_set_state(State.VAULT)
	vault_started.emit()
	return true


## ヴォルトの足の高さ：前面までに上面＋余裕まで上がり、上を通り、背面の先で着地点へ下りる
func _vault_height(v: VaultProbe.Result, d: float) -> float:
	var over := v.top_y + params.vault_clearance
	var rise_end := maxf(v.front_dist, 0.05)
	if d < rise_end:
		return lerpf(v.start.y, over, _ease_out(d / rise_end))
	if v.onto:
		return lerpf(over, v.land.y, clampf((d - rise_end) / maxf(v.back_dist - rise_end, 0.01), 0.0, 1.0))
	var fall_start := v.back_dist - (v.back_dist - v.front_dist) * 0.45
	if d < fall_start:
		return over
	return lerpf(over, v.land.y, _ease_in((d - fall_start) / maxf(v.back_dist - fall_start, 0.01)))


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


static func _ease_in(t: float) -> float:
	return t * t


# --- 移動の下回り -------------------------------------------------------------

## 重力をかけて動かす。地上では段差を自動で乗り越える
func _move(delta: float, grounded: bool) -> void:
	var vy := velocity.y
	var g := params.gravity()
	if vy < 0.0:
		g *= params.fall_gravity_mult
	var vy_next := vy - g * delta
	_vy_before_move = vy_next
	if grounded and _try_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta):
		velocity.y = 0.0
		return
	# このフレームの平均速度で動かす。終速で動かすと最高点が v0·dt/2（約5cm）低く出る
	var vy_avg := (vy + vy_next) * 0.5
	var h_before := Vector3(velocity.x, 0.0, velocity.z)
	velocity.y = vy_avg
	move_and_slide()
	if is_on_wall():
		var into := -h_before.dot(get_wall_normal())
		if into > CRASH_SPEED:
			crashed.emit(into)
	if is_equal_approx(velocity.y, vy_avg):
		velocity.y = vy_next


## 段差の自動乗り越え：上げる→進む→下ろす を試す
func _try_step_up(motion: Vector3) -> bool:
	if motion.length_squared() < 1e-6 or params.step_height <= 0.0:
		return false
	var start := global_transform
	var col := KinematicCollision3D.new()
	if not test_move(start, motion, col):
		return false
	if absf(col.get_normal().y) > 0.7:
		return false  # 床や天井で止まっただけ
	var up := Vector3.UP * params.step_height
	if test_move(start, up):
		return false
	var raised := start.translated(up)
	# 段の上に乗るのに最低限必要な前進（半径ぶん）を保証する
	var fwd := motion.normalized() * maxf(motion.length(), _capsule.radius * 0.5)
	if test_move(raised, fwd):
		return false
	var moved := raised.translated(fwd)
	var down := KinematicCollision3D.new()
	if not test_move(moved, -up, down):
		return false
	if down.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false
	var before := global_position.y
	global_position = moved.origin + down.get_travel()
	rig.absorb_step(global_position.y - before)
	apply_floor_snap()
	return true


## 速度を目標へ寄せる。通常最高を超えた分は地上で毎秒 overspeed_decay ずつ戻す
func _steer(h: Vector3, target: Vector3, control: float, delta: float) -> Vector3:
	var spd := h.length()
	if target != Vector3.ZERO and spd > params.run_speed and h.dot(target) > 0.0:
		var new_spd := spd
		if control >= 1.0:
			new_spd = maxf(spd - params.overspeed_decay * delta, params.run_speed)
		var turned := h.normalized().slerp(target.normalized(), minf(1.0, 6.0 * control * delta))
		return turned * minf(new_spd, params.max_flow_speed)
	var rate := params.run_speed / (params.accel_time if target != Vector3.ZERO else params.decel_time)
	return h.move_toward(target, rate * control * delta).limit_length(params.max_flow_speed)


## スティックの倒し量で速度を決める：半倒しで歩き、全倒しで走り
func _desired_velocity() -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if Input.is_action_pressed(&"walk"):
		input = input.limit_length(0.5)
	var m := input.length()
	if m == 0.0:
		return Vector3.ZERO
	var speed: float
	if m <= 0.5:
		speed = params.walk_speed * m / 0.5
	else:
		speed = lerpf(params.walk_speed, params.run_speed, (m - 0.5) / 0.5)
	var dir := Basis(Vector3.UP, rig.yaw) * Vector3(input.x, 0.0, input.y)
	return dir.normalized() * speed


func _update_stride(delta: float) -> void:
	prev_stride_phase = stride_phase
	if state != State.GROUND or not is_on_floor():
		return
	var spd := horizontal_speed()
	if spd < 0.3:
		return
	var k := clampf(spd / params.run_speed, 0.0, 1.6)
	var cadence := lerpf(params.cadence_walk, params.cadence_run, k)
	var before := floori(stride_phase / PI)
	stride_phase += cadence * PI * delta
	if floori(stride_phase / PI) != before:
		footstep.emit()
	if stride_phase > TAU * 64.0:
		stride_phase -= TAU * 64.0
		prev_stride_phase -= TAU * 64.0
