class_name Player
extends CharacterBody3D
## 1人称パルクールの動き（仕様書 3章）。
## 走り・ジャンプ・ヴォルト・クライム・レッジグラブ・ウォールラン（横/縦）・壁ジャンプ・スライド・ローリング・ハードランディング。
## 速度計算は全部自前で行い、move_and_slide() は衝突処理だけに使う。
## 演出（カメラ・体・振動）はここでは行わず、シグナルと公開している状態を各層が読む。
##
## 上手いほど速くなる仕組み（仕様書 5章）:
## - Perfect判定：理想タイミング±perfect_window で技を出すと速度+3%、勢い値が溜まる
## - 勢い値（momentum 0〜1）：技を繋ぐと溜まり、溜まるほど速度の上限（flow_cap）が上がる。止まる・激突で減る
## 慣性の制御：進行方向と逆に倒すとブレーキ。空中で何も倒さなければ勢いを保つ。クイックターンで180°振り向く

signal jumped
signal footstep
## impact = 着地時の落下速度 m/s、drop = 最高点からの落差 m
signal landed(impact: float, drop: float)
signal rolled(drop: float)
signal hard_landed(drop: float)
signal vault_started
signal climb_started
signal ledge_grabbed
signal wallrun_started
signal wall_jumped
signal slide_started
## 壁に正面からぶつかった。speed = 壁に向かっていた速度 m/s
signal crashed(speed: float)
## Perfect判定。kind = &"landing_jump" / &"roll" / &"vault" / &"wall_jump" / &"slide_jump"
signal perfect(kind: StringName)
signal quick_turned
## リトライ・チェックポイント復帰・落下で戻った。to_start = スタート地点へ戻った（計測をやり直す）
signal respawned(to_start: bool)

enum State { GROUND, AIR, VAULT, ROLL, HARD_LAND, CLIMB, LEDGE_HANG, WALL_RUN, WALL_CLIMB, SLIDE }

const TUNED_PATH := "user://movement_tuned.tres"
const CRASH_SPEED := 5.0      ## m/s。これより速く壁に当たると激突
const STAND_HEIGHT := 1.8     ## m。立っている時の当たり判定
const HANG_DROP := 1.9        ## m。ぶら下がり中、縁から足元まで
const WALL_DETECT := 0.45     ## m。体の表面から壁までの検出距離
const WALL_COOLDOWN := 0.35   ## s。離れた直後の同じ壁には張り付かない
const RETRY_HOLD := 0.3       ## s。リトライをこれだけ押し続けるとチェックポイントへ（仕様書 5章）

@export var params: MovementParams

var state: State = State.AIR
var state_time: float = 0.0
## 足取りの位相。π進むごとに1歩
var stride_phase: float = 0.0
var prev_stride_phase: float = 0.0
## ヴォルト・クライム・ぶら下がり中の地形（体の層が手を着く位置に使う）
var move: VaultProbe.Result
var move_progress: float = 0.0
## ウォールラン中の壁（法線は壁から外向き）と側（+1=右, -1=左）
var wall_normal: Vector3 = Vector3.ZERO
var wall_side: float = 0.0
var spawn: Transform3D
var checkpoint: Transform3D
## 勢い値 0〜1
var momentum: float = 0.0
var perfect_count: int = 0
## 進行方向と逆に倒して減速中（カメラ・脚・振動が読む）
var braking: bool = false
## これより下に落ちたらチェックポイントへ戻す（コースごとに道の高さより下に置く）
var kill_y: float = -30.0
## リトライを押している時間（チェックポイント復帰の溜め。画面の演出が読む）。押していなければ -1
var retry_hold: float = -1.0
## false の間は入力を読まない（ゴール後・リプレイ中）
var input_enabled: bool = true
## 今立っている床の素材（足音が読む）。&"concrete" / &"metal" / &"glass" / &"gravel"
var floor_surface: StringName = &"concrete"

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
var _move_duration: float = 0.0
var _move_speed_in: float = 0.0
var _last_wall_normal: Vector3 = Vector3.ZERO
var _wall_cooldown: float = 0.0
var _climb_rise_d: float = 0.0
## 縦ウォールランに入る直前の水平速度（駆け上がって縁を登った後の速さに使う）
var _wall_climb_speed_in: float = 0.0
## Perfect判定用の時刻（秒）
var _clock: float = 0.0
var _land_clock: float = -INF
var _jump_press_clock: float = -INF
var _vault_perfect: bool = false

@onready var rig: CameraRig = $CameraRig
@onready var _shape_node: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = _shape_node.shape


func _ready() -> void:
	add_to_group(&"player")
	# 実機で調整パネルから保存した値（エディタ実行では res:// の既定値を直接書き換えるので読まない）
	if not OS.has_feature("editor") and ResourceLoader.exists(TUNED_PATH):
		var tuned := load(TUNED_PATH) as MovementParams
		if tuned != null:
			params = tuned
	spawn = global_transform
	checkpoint = spawn
	rig.player = self
	footstep.connect(Haptics.step)
	landed.connect(func(impact: float, _drop: float) -> void:
		if impact > 3.0:
			Haptics.land())
	hard_landed.connect(func(_drop: float) -> void: Haptics.hard_land())
	ledge_grabbed.connect(Haptics.grab)
	climb_started.connect(Haptics.grab)
	rig.snap(rotation.y)


func _physics_process(delta: float) -> void:
	if _update_retry(delta):
		return
	if global_position.y < kill_y:
		respawn(checkpoint)
		return
	_clock += delta
	if _just(&"jump"):
		_jump_press_clock = _clock
	_since_jump_press = 0.0 if _just(&"jump") else _since_jump_press + delta
	_since_crouch_press = 0.0 if _just(&"crouch") else _since_crouch_press + delta
	_wall_cooldown = maxf(_wall_cooldown - delta, 0.0)
	state_time += delta
	braking = false
	if _just(&"quick_turn"):
		_quick_turn()

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
		State.CLIMB:
			_climb(delta)
		State.LEDGE_HANG:
			_ledge_hang(delta)
		State.WALL_RUN:
			_wall_run(delta)
		State.WALL_CLIMB:
			_wall_climb(delta)
		State.SLIDE:
			_slide(delta)
	_update_stride(delta)
	_update_momentum(delta)
	_continuous_haptics()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 今の速度の上限。勢い0で 走り速度×flow_cap_base、勢い100%で max_flow_speed
func flow_cap() -> float:
	return lerpf(params.run_speed * params.flow_cap_base, params.max_flow_speed, momentum)


## 物理tick間を補間した足取り位相（描画側が使う）
func stride_phase_interpolated() -> float:
	return lerpf(prev_stride_phase, stride_phase, Engine.get_physics_interpolation_fraction())


## 引数なし = スタート地点へ（リトライ）。落下時はチェックポイントへ
func respawn(at: Transform3D = spawn) -> void:
	var to_start := at == spawn
	global_transform = at
	velocity = Vector3.ZERO
	_pending_time = -1.0
	move = null
	momentum = 0.0
	perfect_count = 0
	braking = false
	_land_clock = -INF
	_set_height(STAND_HEIGHT)
	_set_state(State.AIR)
	reset_physics_interpolation()
	rig.snap(at.basis.get_euler().y)
	respawned.emit(to_start)


## リトライ（仕様書 5章「即リトライ」）：
## 押して離せばスタートへ（離した瞬間。0.5秒以内）、RETRY_HOLD 押し続ければチェックポイントへ。
## 押した瞬間に戻さないのは、長押しでチェックポイントを選んだ時に計測を消さないため。
func _update_retry(delta: float) -> bool:
	if not input_enabled:
		retry_hold = -1.0
		return false
	if Input.is_action_just_pressed(&"retry"):
		retry_hold = 0.0
	elif retry_hold >= 0.0:
		if not Input.is_action_pressed(&"retry"):
			retry_hold = -1.0
			respawn()
			return true
		retry_hold += delta
		if retry_hold >= RETRY_HOLD - 0.001:
			retry_hold = -2.0  # 離すまで次を受け付けない
			respawn(checkpoint)
			return true
	elif retry_hold < -1.5 and not Input.is_action_pressed(&"retry"):
		retry_hold = -1.0
	return false


# --- 状態 ---------------------------------------------------------------

func _ground(delta: float) -> void:
	var h := _steer(Vector3(velocity.x, 0.0, velocity.z), _desired_velocity(), 1.0, delta)
	velocity = Vector3(h.x, minf(velocity.y, 0.0), h.z)

	if _pending_time >= 0.0:
		_pending_time += delta
		if _since_crouch_press <= _pending_time:
			_start_roll(_pending_drop, _pending_time - _since_crouch_press)  # 着地からどれだけ遅れて押したか
			return
		if _pending_time > params.roll_window_after:
			_pending_time = -1.0
			if _pending_drop >= params.hard_land_drop:
				_start_hard_land(_pending_drop)
				return
	elif _since_jump_press <= params.jump_buffer:
		if not _try_ground_move():
			# 着地の瞬間（±perfect_window）に押したジャンプはPerfect：速度を落とさず上乗せして跳ぶ
			var hop := _clock - _land_clock <= params.perfect_window + 0.001 \
					and absf(_jump_press_clock - _land_clock) <= params.perfect_window \
					and horizontal_speed() > params.walk_speed
			_jump()
			if hop:
				_apply_perfect(&"landing_jump", true)
			_move(delta, false)  # 押したフレームで上昇を始める
		return
	elif _since_crouch_press <= params.move_buffer and _try_slide():
		return

	_move(delta, true)
	if not is_on_floor():
		# 坂の頂上を越えた瞬間は上向きに動いているので、Godotの床吸着が効かない。自分で吸着させる
		apply_floor_snap()
		if is_on_floor():
			velocity.y = 0.0
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
		if not _try_ground_move():
			_jump()
			_move(delta, false)
		return
	if _jumped and not _jump_cut_done and velocity.y > 0.0 and not _held(&"jump"):
		velocity.y *= 1.0 - params.jump_cut_max
		_jump_cut_done = true
	if _try_ledge_from_air() or _try_wall_run() or _try_wall_climb_from_air():
		return
	_move(delta, false)
	_air_peak_y = maxf(_air_peak_y, global_position.y)
	if is_on_floor():
		_land()


func _vault(delta: float) -> void:
	var v := move
	move_progress = clampf(state_time / _move_duration, 0.0, 1.0)
	var d := v.back_dist * move_progress
	var pos := v.start + v.dir * d
	pos.y = _vault_height(v, d)
	_teleport(pos, delta)
	if move_progress >= 1.0:
		var keep := 1.0 + params.perfect_speed_bonus if _vault_perfect else params.vault_speed_keep
		var out := v.dir * maxf(_move_speed_in, params.walk_speed) * keep
		_finish_move(v, out.limit_length(maxf(flow_cap(), _move_speed_in)))


## よじ登り：まず壁際で縁の上まで体を上げ（前半55%）、それから上面へ進む
func _climb(delta: float) -> void:
	var v := move
	move_progress = clampf(state_time / _move_duration, 0.0, 1.0)
	var over := v.top_y + params.vault_clearance
	var pos: Vector3
	if move_progress < 0.55:
		var u := move_progress / 0.55
		pos = v.start + v.dir * (_climb_rise_d * u)
		pos.y = lerpf(v.start.y, over, _ease_out(u))
	else:
		var u := (move_progress - 0.55) / 0.45
		pos = v.start + v.dir * lerpf(_climb_rise_d, v.back_dist, _ease_out(u))
		pos.y = lerpf(over, v.land.y, u)
	_teleport(pos, delta)
	if move_progress >= 1.0:
		var out := v.dir * clampf(_move_speed_in, params.walk_speed, params.run_speed) * 0.6
		_finish_move(v, out)


func _ledge_hang(_delta: float) -> void:
	velocity = Vector3.ZERO
	var input := _move_input()
	if _since_jump_press <= params.move_buffer or input.y < -0.6:
		_start_climb(move)
		return
	if _just(&"crouch") or input.y > 0.6:
		_drop_from_wall(move.dir * -1.0)
		return
	# 横移動：縁が続く所までだけ動く
	if absf(input.x) > 0.3:
		var lateral := move.dir.cross(Vector3.UP).normalized() * signf(input.x)
		var step := lateral * params.ledge_shimmy_speed * get_physics_process_delta_time()
		var probe_from := global_position + step
		var saved := global_position
		global_position = probe_from
		var r := VaultProbe.ledge(self, move.dir, 0.6, HANG_DROP - 0.4, HANG_DROP + 0.4, 10.0, _capsule.radius, STAND_HEIGHT)
		if r == null or test_move(Transform3D(basis, saved), step):
			global_position = saved
		else:
			move = r


func _wall_run(delta: float) -> void:
	var h_now := Vector3(velocity.x, 0.0, velocity.z)
	var along := _along_wall(h_now)
	# 壁に沿った成分だけを速さとする（押し付け成分を数えると毎フレーム速くなる）
	var spd := maxf(h_now.dot(along), params.wallrun_min_speed)
	if _since_jump_press <= params.move_buffer:
		_wall_jump(along, spd)
		return
	var wall := VaultProbe.side_wall(self, along, _capsule.radius + WALL_DETECT)
	var input := _desired_velocity()
	var leaving := input != Vector3.ZERO and input.normalized().dot(wall_normal) > 0.5
	if wall.is_empty() or state_time > params.wallrun_max_time or leaving or spd < params.wallrun_min_speed * 0.6:
		_drop_from_wall(Vector3.ZERO)
		return
	wall_normal = Vector3(wall.normal.x, 0.0, wall.normal.z).normalized()
	wall_side = wall.side
	var h := along * minf(spd, params.max_flow_speed) - wall_normal * 1.0  # 壁へ軽く押し付ける
	var vy := velocity.y - params.gravity() * params.wallrun_gravity * delta
	velocity = Vector3(h.x, vy, h.z)
	move_and_slide()
	if is_on_floor():
		_land()


## 縦のウォールラン：壁に正対して駆け上がる。届けば縁を掴む
func _wall_climb(delta: float) -> void:
	if _since_jump_press <= params.move_buffer and state_time > 0.1:
		# 壁を蹴って後ろへ
		velocity = wall_normal * params.run_speed * 0.6 + Vector3.UP * params.jump_velocity() * 0.8
		_since_jump_press = INF
		_wall_cooldown = WALL_COOLDOWN
		_last_wall_normal = wall_normal
		_leave_ground()
		_jumped = true
		wall_jumped.emit()
		return
	var r := VaultProbe.ledge(self, -wall_normal, WALL_DETECT, 0.4, params.ledge_reach, 20.0, _capsule.radius, STAND_HEIGHT)
	if r != null:
		_start_climb(r)
		return
	# 壁に着くまでは寄っていき、着いたら軽く押し付ける
	var toward := maxf(Vector3(velocity.x, 0.0, velocity.z).dot(-wall_normal), 1.0)
	if is_on_wall():
		toward = 1.0
	velocity = Vector3(-wall_normal.x * toward, velocity.y, -wall_normal.z * toward)
	_move(delta, false, false)
	# 寄っていく間（最初の0.3秒）は遠くまで壁を見る
	var look := _capsule.radius + (WALL_DETECT if state_time > 0.3 else 2.5)
	if velocity.y <= 0.0 or VaultProbe.front_wall(self, -wall_normal, look, 1.6).is_empty():
		_drop_from_wall(wall_normal * 0.5)


func _slide(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var spd := h.length()
	var dir := h.normalized() if spd > 0.01 else Vector3.ZERO
	# 坂：重力の斜面方向成分で加速。平地では摩擦で少しずつ減速
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	var downhill := Vector3.DOWN - n * n.dot(Vector3.DOWN)
	var slope_acc := Vector3(downhill.x, 0.0, downhill.z) * params.gravity()
	var accelerating := slope_acc.length() > 0.5 and slope_acc.dot(dir) > 0.0
	h += slope_acc * delta
	if not accelerating:
		h = h.move_toward(Vector3.ZERO, params.slide_friction * delta)
	# 向きは少しだけ変えられる。逆に倒すとブレーキ
	var want := _desired_velocity()
	braking = want != Vector3.ZERO and h.length() > 0.5 and want.dot(h) < 0.0
	if braking:
		h = h.move_toward(Vector3.ZERO, params.brake_decel * 0.6 * delta)
	elif want != Vector3.ZERO and h.length() > 0.1:
		h = h.slerp(want.normalized() * h.length(), minf(1.0, 1.5 * delta))
	h = h.limit_length(params.max_flow_speed)
	velocity = Vector3(h.x, minf(velocity.y, 0.0), h.z)

	if _since_jump_press <= params.jump_buffer and VaultProbe.can_stand(self, _capsule.radius, STAND_HEIGHT):
		# 滑り出してすぐ跳ぶとPerfect
		var quick := state_time <= params.perfect_chain_window
		var bonus := params.slide_jump_bonus + (params.perfect_speed_bonus if quick else 0.0)
		var boosted := _boost(h, bonus)
		velocity = Vector3(boosted.x, 0.0, boosted.z)
		_set_height(STAND_HEIGHT)
		_jump()
		if quick:
			_apply_perfect(&"slide_jump", false)
		_move(delta, false)
		return
	_move(delta, true)
	if not is_on_floor():
		if VaultProbe.can_stand(self, _capsule.radius, STAND_HEIGHT):
			_set_height(STAND_HEIGHT)
		_leave_ground()
		return
	var done := (state_time >= params.slide_time and not accelerating) or h.length() < 2.0
	if done and VaultProbe.can_stand(self, _capsule.radius, STAND_HEIGHT):
		_set_height(STAND_HEIGHT)
		_set_state(State.GROUND)


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
		_ground_move_or_jump()
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


## 地上でジャンプを押した時の優先順：ヴォルト → クライム → 縦ウォールラン（どれも無理ならfalse）
func _try_ground_move() -> bool:
	return _try_vault() or _try_climb() or _try_wall_climb()


func _ground_move_or_jump() -> void:
	if not _try_ground_move():
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
	_land_clock = _clock
	if drop >= params.roll_min_drop:
		if _since_crouch_press <= params.roll_window_before:
			_start_roll(drop, _since_crouch_press)  # 着地のどれだけ前に押したか
		else:
			_pending_drop = drop
			_pending_time = 0.0
	elif _since_crouch_press <= params.roll_window_before or _held(&"crouch"):
		_try_slide()  # 着地にしゃがみを合わせると、そのままスライドへ


## timing_error = 着地としゃがみ入力のずれ（秒）。成功で速度を上乗せ、ずれが perfect_window 以内ならさらに上乗せ
func _start_roll(drop: float, timing_error: float) -> void:
	_pending_time = -1.0
	_since_crouch_press = INF
	_add_momentum(params.momentum_gain_move)
	var h := _boost(Vector3(velocity.x, 0.0, velocity.z), params.roll_speed_bonus)
	velocity = Vector3(h.x, velocity.y, h.z)
	_set_state(State.ROLL)
	rolled.emit(drop)
	if timing_error <= params.perfect_window:
		_apply_perfect(&"roll", true)


func _start_hard_land(drop: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z) * (1.0 - params.hard_land_speed_loss)
	velocity = Vector3(h.x, 0.0, h.z)
	momentum = maxf(momentum - params.momentum_hard_land_loss, 0.0)
	hard_landed.emit(drop)  # 揺れ・振動は常に出す
	if params.hard_land_stun > 0.0:
		_set_state(State.HARD_LAND)


func _try_vault() -> bool:
	var spd := horizontal_speed()
	if spd < params.vault_min_speed:
		return false
	var dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	var r := VaultProbe.probe(self, dir, spd, params, _capsule.radius, STAND_HEIGHT)
	if r == null:
		return false
	# 体が障害物に着く vault_ideal_time 前に押していればPerfect（先行入力で遅れて発動した分も押した時刻で測る）
	var time_to_face := (r.front_dist - _capsule.radius) / spd + _since_jump_press
	_vault_perfect = absf(time_to_face - params.vault_ideal_time) <= params.perfect_window
	move = r
	move_progress = 0.0
	_move_speed_in = spd
	_move_duration = clampf(r.back_dist / (spd * params.vault_speed_keep),
			params.vault_min_duration, params.vault_max_duration)
	_since_jump_press = INF
	_pending_time = -1.0
	_add_momentum(params.momentum_gain_move)
	_set_state(State.VAULT)
	vault_started.emit()
	if _vault_perfect:
		_apply_perfect(&"vault", false)  # 速度は越えた時に上乗せする
	return true


## 地上から：向いている方向に手の届く縁があれば登る
func _try_climb() -> bool:
	var reach := maxf(0.7, horizontal_speed() * params.vault_reach_time)
	var r := VaultProbe.ledge(self, _facing(), reach, params.vault_min_height, params.climb_max_height,
			params.vault_auto_align_deg, _capsule.radius, STAND_HEIGHT)
	if r == null:
		return false
	_start_climb(r)
	return true


func _start_climb(r: VaultProbe.Result) -> void:
	move = r
	move_progress = 0.0
	move.start = global_position
	# 縦ウォールランから登る時は、壁に押し付けている速さ（約1 m/s）ではなく駆け込んだ速さで登りきる
	_move_speed_in = _wall_climb_speed_in if state == State.WALL_CLIMB else horizontal_speed()
	var k := clampf(_move_speed_in / params.run_speed, 0.0, 1.0)
	_move_duration = params.climb_time * lerpf(1.0, params.climb_fast_mult, k)
	# 前面との距離を測り直す（ぶら下がりや縦ウォールランから来た時は start が変わっている）
	var front_dist := (r.hand - global_position).dot(r.dir) - 0.12
	_climb_rise_d = maxf(front_dist - _capsule.radius - 0.02, 0.0)
	move.back_dist = front_dist + _capsule.radius + 0.3
	_since_jump_press = INF
	_pending_time = -1.0
	_add_momentum(params.momentum_gain_small)
	_set_state(State.CLIMB)
	climb_started.emit()


## 縦のウォールラン：壁に正対してジャンプ
func _try_wall_climb() -> bool:
	if horizontal_speed() < params.wallrun_up_min_speed:
		return false
	var dir := _facing()
	# 速いほど遠くから届く（ヴォルトと同じ考え方）
	var reach := _capsule.radius + maxf(0.7, horizontal_speed() * params.vault_reach_time)
	var hit := VaultProbe.front_wall(self, dir, reach)
	if hit.is_empty():
		return false
	return _start_wall_climb(hit, dir)


func _start_wall_climb(hit: Dictionary, dir: Vector3) -> bool:
	var n: Vector3 = hit.normal
	n = Vector3(n.x, 0.0, n.z).normalized()
	if rad_to_deg((-n).angle_to(dir)) > params.vault_auto_align_deg:
		return false
	if _wall_cooldown > 0.0 and n.dot(_last_wall_normal) > 0.9:
		return false
	wall_normal = n
	_wall_climb_speed_in = horizontal_speed()
	# 壁まで少し距離があれば、その分は今の速度で寄っていく（_wall_climb が壁へ押し付ける）
	var up := sqrt(2.0 * params.gravity() * params.wallrun_up_height)
	velocity = Vector3(0.0, maxf(up, velocity.y), 0.0) - n * minf(horizontal_speed(), params.run_speed)
	_since_jump_press = INF
	_set_state(State.WALL_CLIMB)
	_jumped = true
	wallrun_started.emit()
	return true


## ジャンプして0.5秒以内に正面の壁に着いたら、空中からでも縦ウォールランに入る
func _try_wall_climb_from_air() -> bool:
	if not _jumped or state_time > 0.5 or horizontal_speed() < params.wallrun_up_min_speed:
		return false
	var dir := _facing()
	var hit := VaultProbe.front_wall(self, dir, _capsule.radius + WALL_DETECT)
	if hit.is_empty():
		return false
	# 縁に手が届く高さなら、縦ウォールランではなくレッジグラブ側に任せる
	return _start_wall_climb(hit, dir)


## 空中で縁に手が届いたら掴む。前を押していればそのまま登る、押していなければぶら下がる
func _try_ledge_from_air() -> bool:
	if velocity.y > 2.0:
		return false
	var dir := _facing()
	var want := _desired_velocity()
	var toward := Vector3(velocity.x, 0.0, velocity.z)
	if want.dot(dir) <= 0.0 and toward.dot(dir) < 1.0:
		return false
	var r := VaultProbe.ledge(self, dir, WALL_DETECT, 1.0, params.ledge_reach, params.vault_auto_align_deg,
			_capsule.radius, STAND_HEIGHT)
	if r == null:
		return false
	if _wall_cooldown > 0.0 and (-r.dir).dot(_last_wall_normal) > 0.9:
		return false
	if want.dot(r.dir) > 0.5 * params.run_speed or _held(&"jump"):
		_start_climb(r)
		return true
	# ぶら下がる：手を縁に、体を壁際へ
	move = r
	var hang := r.hand - r.dir * (0.12 + _capsule.radius + 0.02)
	hang.y = r.top_y - HANG_DROP
	global_position = hang
	velocity = Vector3.ZERO
	_set_state(State.LEDGE_HANG)
	ledge_grabbed.emit()
	return true


## 空中で横に壁があり、速度と角度の条件を満たせばウォールラン
func _try_wall_run() -> bool:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length() < params.wallrun_min_speed or velocity.y < -6.0:
		return false
	var dir := h.normalized()
	var wall := VaultProbe.side_wall(self, dir, _capsule.radius + WALL_DETECT)
	if wall.is_empty():
		return false
	var n: Vector3 = wall.normal
	n = Vector3(n.x, 0.0, n.z).normalized()
	if _wall_cooldown > 0.0 and n.dot(_last_wall_normal) > 0.9:
		return false
	var into := -dir.dot(n)
	if into < -0.05:
		return false  # 壁から離れていく
	var angle := rad_to_deg(asin(clampf(into, 0.0, 1.0)))
	if angle < params.wallrun_min_angle or angle > params.wallrun_max_angle:
		return false
	wall_normal = n
	wall_side = wall.side
	var along := _along_wall(h)
	var keep := along * h.length()
	# 跳んだ勢いを残しつつ、上向きを lift〜max_lift に収める（落ちながら張り付いても少し持ち上げる）
	velocity = Vector3(keep.x, clampf(velocity.y, params.wallrun_entry_lift, params.wallrun_entry_max_lift), keep.z)
	_add_momentum(params.momentum_gain_move)
	_set_state(State.WALL_RUN)
	wallrun_started.emit()
	return true


func _wall_jump(along: Vector3, spd: float) -> void:
	# 張り付いてすぐ蹴るとPerfect
	var quick := state_time <= params.perfect_chain_window
	var bonus := params.wall_jump_speed_bonus + (params.perfect_speed_bonus if quick else 0.0)
	_add_momentum(params.momentum_gain_move)
	var dir := (along + wall_normal * params.wall_jump_push).normalized()
	var out := _boost(dir * spd, bonus)
	velocity = Vector3(out.x, params.jump_velocity(), out.z)
	if quick:
		_apply_perfect(&"wall_jump", false)
	_since_jump_press = INF
	_wall_cooldown = WALL_COOLDOWN
	_last_wall_normal = wall_normal
	_leave_ground()
	_jumped = true
	_jump_cut_done = true
	wall_jumped.emit()


func _drop_from_wall(push: Vector3) -> void:
	velocity += push
	_wall_cooldown = WALL_COOLDOWN
	_last_wall_normal = wall_normal if state != State.LEDGE_HANG else -move.dir
	move = null
	_leave_ground()
	_jumped = true


func _try_slide() -> bool:
	if horizontal_speed() < params.slide_min_speed:
		return false
	_since_crouch_press = INF
	_add_momentum(params.momentum_gain_small)
	_set_height(params.slide_height)
	_set_state(State.SLIDE)
	slide_started.emit()
	return true


func _finish_move(v: VaultProbe.Result, out: Vector3) -> void:
	velocity = Vector3(out.x, 0.0, out.z)
	move = null
	if v.land_on_ground:
		apply_floor_snap()
		_set_state(State.GROUND)
		_since_floor = 0.0
		if _since_jump_press <= params.move_buffer:
			_ground_move_or_jump()  # 技の最中の先行入力
	else:
		_leave_ground()


func _teleport(pos: Vector3, delta: float) -> void:
	var prev := global_position
	global_position = pos
	velocity = (pos - prev) / delta


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

## 重力をかけて動かす。地上では段差を自動で乗り越える。check_crash=false は壁に触れるのが意図どおりの時
func _move(delta: float, grounded: bool, check_crash: bool = true) -> void:
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
	if check_crash:
		_check_crash(h_before)
	if is_on_floor():
		_read_floor_surface()
	if is_equal_approx(velocity.y, vy_avg):
		velocity.y = vy_next


## 壁への激突：壁に向かって CRASH_SPEED 以上で当たった（乗り越えられる段差は _try_step_up が先に処理する）
func _check_crash(h_before: Vector3) -> void:
	if not is_on_wall():
		return
	for i: int in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.3:
			continue  # 段の角など、斜めの接触は激突にしない
		var into := -h_before.dot(n)
		if into > CRASH_SPEED:
			momentum *= 1.0 - params.momentum_crash_loss
			crashed.emit(into)
			return


## 床の素材をコライダーのメタデータ "surface" から読む（無ければコンクリート）
func _read_floor_surface() -> void:
	for i: int in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y > 0.7:
			var body := c.get_collider() as Node
			floor_surface = body.get_meta(&"surface", &"concrete") if body != null else &"concrete"
			return


## 段差の自動乗り越え：上げる→進む→下ろす を試す
func _try_step_up(motion: Vector3) -> bool:
	if motion.length_squared() < 1e-6 or params.step_height <= 0.0:
		return false
	var start := global_transform
	var col := KinematicCollision3D.new()
	# 少し先まで見る（1フレームの移動量だけだと段の角に乗り上げてから気づく）
	var look := motion.normalized() * maxf(motion.length(), _capsule.radius * 0.5)
	if not test_move(start, look, col, 0.001, false, 4):
		return false
	# 当たった位置の高さで判定する。カプセルの丸い底が角に当たると法線が斜め上を向くので、法線では判定しない。
	# 今立っている床との接触も一緒に返ってくるので、全部の接触から段の縁を探す
	var is_step := false
	for i: int in col.get_collision_count():
		var hit_h := col.get_position(i).y - start.origin.y
		if hit_h > params.step_height + 0.02 and absf(col.get_normal(i).y) < 0.3:
			return false  # 段差より高い壁
		if hit_h >= 0.02 and col.get_normal(i).y < 0.95:
			is_step = true
	if not is_step:
		return false
	var up := Vector3.UP * params.step_height
	if test_move(start, up):
		return false
	var raised := start.translated(up)
	# 下ろした先が段の角だと法線が急になるので、その時はもう少し前に進めて下ろし直す
	for extra: float in [0.0, _capsule.radius]:
		var fwd := look + look.normalized() * extra
		if test_move(raised, fwd):
			return false
		var moved := raised.translated(fwd)
		var down := KinematicCollision3D.new()
		if not test_move(moved, -up, down):
			return false
		if down.get_normal().angle_to(Vector3.UP) > floor_max_angle:
			continue
		var before := global_position.y
		global_position = moved.origin + down.get_travel()
		# 補間を切ってから目線の跳ねを吸収する（補間が残ると旧位置との間を描いて、目線が一度沈んでから跳ねる）
		reset_physics_interpolation()
		rig.absorb_step(global_position.y - before)
		apply_floor_snap()
		return true
	return false


## 速度を目標へ寄せる。control = 1 が地上、air_control が空中
## - 進行方向と逆に倒すとブレーキ（地上 brake_decel、空中はその air_brake 倍）。慣性を消す手段
## - 空中で何も倒していなければ勢いをそのまま保つ
## - 通常最高を超えた分は、地上で毎秒 overspeed_decay ずつ戻る（勢い値が高いほどゆっくり）
func _steer(h: Vector3, target: Vector3, control: float, delta: float) -> Vector3:
	var spd := h.length()
	var grounded := control >= 1.0
	braking = false
	if target == Vector3.ZERO:
		if not grounded:
			return _soft_cap(h, delta)
		return h.move_toward(Vector3.ZERO, params.run_speed / params.decel_time * delta)
	if spd > 0.5 and h.dot(target) < 0.0:
		braking = spd > params.walk_speed
		var brake := params.brake_decel * (1.0 if grounded else params.air_brake)
		return h.move_toward(target, brake * delta)
	if spd > params.run_speed:
		var new_spd := spd
		if grounded:
			new_spd = maxf(spd - params.overspeed_decay * (1.0 - 0.5 * momentum) * delta, params.run_speed)
		var turned := h.normalized().slerp(target.normalized(), minf(1.0, 6.0 * control * delta))
		return _soft_cap(turned * new_spd, delta)
	return h.move_toward(target, params.run_speed / params.accel_time * control * delta)


## 上限を超えていたら少しずつ上限まで戻す（勢いを失った瞬間に速度が飛ばないように）
func _soft_cap(h: Vector3, delta: float) -> Vector3:
	var cap := flow_cap()
	var spd := h.length()
	if spd <= cap:
		return h
	return h * (maxf(cap, spd - params.overspeed_decay * 4.0 * delta) / spd)


## 速度の上乗せ。上限（flow_cap）までは伸び、上限を超えていても今より遅くはしない
func _boost(h: Vector3, bonus: float) -> Vector3:
	var spd := h.length()
	return (h * (1.0 + bonus)).limit_length(maxf(flow_cap(), spd))


func _add_momentum(amount: float) -> void:
	momentum = clampf(momentum + amount, 0.0, 1.0)


## Perfect：勢い値を足し、boost=true なら速度も上乗せする（ヴォルト・壁ジャンプ・スライドジャンプは呼び出し側で上乗せ済み）
func _apply_perfect(kind: StringName, boost: bool) -> void:
	perfect_count += 1
	_add_momentum(params.momentum_gain_perfect)
	if boost:
		var h := _boost(Vector3(velocity.x, 0.0, velocity.z), params.perfect_speed_bonus)
		velocity = Vector3(h.x, velocity.y, h.z)
	perfect.emit(kind)


## 止まっている間だけ勢い値が減る（普通に走っている間は減らない：仕様書 5章）
func _update_momentum(delta: float) -> void:
	if horizontal_speed() < params.walk_speed and state in [State.GROUND, State.LEDGE_HANG, State.HARD_LAND]:
		momentum = maxf(momentum - params.momentum_stop_decay * delta, 0.0)


## クイックターン：180°振り向く。地上では速度の一部を逆向きに残し、そのまま反対へ走り出せる
func _quick_turn() -> void:
	match state:
		State.GROUND, State.SLIDE, State.ROLL:
			var h := Vector3(velocity.x, 0.0, velocity.z) * -params.quick_turn_keep
			velocity = Vector3(h.x, velocity.y, h.z)
			if state != State.GROUND and VaultProbe.can_stand(self, _capsule.radius, STAND_HEIGHT):
				_set_height(STAND_HEIGHT)
				_set_state(State.GROUND)
		State.WALL_CLIMB:
			# 駆け上がりの途中で振り向いて、壁を蹴って後ろへ
			velocity = wall_normal * params.run_speed * 0.6 + Vector3.UP * params.jump_velocity() * 0.8
			_wall_cooldown = WALL_COOLDOWN
			_last_wall_normal = wall_normal
			_leave_ground()
			_jumped = true
			wall_jumped.emit()
		State.AIR:
			pass  # 空中は向きだけ変える
		_:
			return
	rig.start_turn(PI, params.quick_turn_time)
	quick_turned.emit()


## スティックの倒し量で速度を決める：半倒しで歩き、全倒しで走り
func _desired_velocity() -> Vector3:
	var input := _move_input()
	if _held(&"walk"):
		input = input.limit_length(0.5)
	var m := input.length()
	if m == 0.0:
		return Vector3.ZERO
	var speed: float
	if m <= 0.5:
		speed = params.walk_speed * m / 0.5
	else:
		speed = lerpf(params.walk_speed, params.run_speed, (m - 0.5) / 0.5)
	var dir := Basis(Vector3.UP, rig.move_yaw()) * Vector3(input.x, 0.0, input.y)
	return dir.normalized() * speed


## 体の向き：動いていれば進行方向、止まっていれば視線の向き
func _facing() -> Vector3:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length() > 1.0:
		return h.normalized()
	return Basis(Vector3.UP, rig.move_yaw()) * Vector3.FORWARD


func _along_wall(h: Vector3) -> Vector3:
	var a := h - wall_normal * h.dot(wall_normal)
	if a.length() < 0.01:
		a = wall_normal.cross(Vector3.UP) * signf(wall_side)
	return a.normalized()


## 当たり判定の高さを変える（足元の位置は保つ）
func _set_height(h: float) -> void:
	if is_equal_approx(_capsule.height, h):
		return
	_capsule.height = h
	_shape_node.position.y = h * 0.5


func _update_stride(delta: float) -> void:
	prev_stride_phase = stride_phase
	var running_on_wall := state == State.WALL_RUN or state == State.WALL_CLIMB
	if not running_on_wall and (state != State.GROUND or not is_on_floor()):
		return
	var spd := maxf(horizontal_speed(), absf(velocity.y)) if state == State.WALL_CLIMB else horizontal_speed()
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


## 継続する振動（仕様書 4章の表）：ウォールラン中、スライド中（速度に比例）
func _continuous_haptics() -> void:
	match state:
		State.WALL_RUN:
			Haptics.hold(0.05, 0.15)
		State.SLIDE:
			var k := clampf(horizontal_speed() / params.run_speed, 0.0, 1.5)
			Haptics.hold(0.1 * k, 0.25 * k)
		State.GROUND:
			if braking:
				Haptics.hold(0.15, 0.1)  # 足を滑らせて止まる


# --- 入力 ---------------------------------------------------------------
# 入力はここを通して読む。input_enabled=false（ゴール後・リプレイ中）なら何も押していない扱い

func _just(action: StringName) -> bool:
	return input_enabled and Input.is_action_just_pressed(action)


func _held(action: StringName) -> bool:
	return input_enabled and Input.is_action_pressed(action)


func _move_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
