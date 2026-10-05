class_name Autopilot
extends Node
## 自動走行：CourseBuilder の道しるべ（nodes）を順にたどって、決めた所でジャンプ・しゃがみ・壁蹴りを入力する。
## 入力は InputMap のアクションを押す（人と同じ経路）。コースが走りきれるかの確認と、メダルの基準タイムに使う。
## - 向き：次の道しるべへ視線を向けて前を押し続ける。横ウォールラン中は壁に沿って前を押す（離れる向きに倒すと落ちる）
## - ジャンプ：残りの距離が lead_c + 速さ×lead_t 以下になったら押す（ヴォルトは体が着く0.15秒前 = Perfect）
## - ローリング：2 m以上の落下で、着地直前にしゃがむ
## - 1.1 の技：ヴォルトジャンプ（障害物の上でもう一度押す）・スイング（理想の角度で離す）・
##   ジップライン（終点の少し手前で離す）・縦ウォールランの頂点で蹴り上がる。どれもPerfectを狙う
## 主ルートの道しるべ（dist >= 0）を通り過ぎた時刻を passed に残す（近道でどれだけ速くなったかをテストが比べる）
## 人の模型（human = true）：腕のいい人が少しずれて押す。変えるのは「押す瞬間」だけ（物理・手触りの数値には触らない）
## - 技の入力（ジャンプ・しゃがみ・壁蹴り・スイング/ジップの離し・縦ウォールランの蹴り・ヴォルトジャンプの2度目）は、
##   完璧な走りが押す瞬間の HUMAN_DELAY_MIN〜MAX フレーム後に押す（Perfect の ±0.05 s は普通は外れる）
## - 着地のローリングだけは遅らせず、同じ 4〜8 フレーム早く押す（遅らせると着地後の0.08 sを過ぎるか、着地の±0.05 sに収まって Perfect になる）
## - 縁・壁のジャンプ（ギャップ・段差・よじ登り・縦ウォールランの駆け上がり。ヴォルト以外の Act.JUMP）は、人は先読みして手前で早めに跳ぶので
##   0〜HUMAN_EARLY_MAX フレーム早い（壁へ駆け込んで遅れると、跳ぶ前にぶつかって止まる）
## - 乱数は seed_value で固定（同じコース・同じ種なら毎回同じ走り）

## 人の模型の押す遅れ（フレーム）。完璧な走りが押す瞬間から 0.067〜0.133 s 後
const HUMAN_DELAY_MIN := 4
const HUMAN_DELAY_MAX := 8
## 縁・壁のジャンプを早める最大（フレーム）。ヴォルトの道しるべは lead_t が 0.15（体が着く0.15秒前 = Perfect）、
## 縁は 0.03、よじ登りと縦ウォールランは 0.1〜0.12。時刻の Perfect があるのはヴォルトだけなので、それ以外は人が先読みして早めに跳ぶ
const HUMAN_EARLY_MAX := 4
const VAULT_LEAD_T := 0.15
## 人の模型のローリングを着地の何秒前までに押すか（roll_window_before = 0.2 s の内側）
const HUMAN_ROLL_MAX_TIME := 0.18

var player: Player
var nodes: Array[Dictionary] = []
var idx: int = 0
## 結果
var falls: int = 0
## 落ちる直前の様子（テストの報告用）
var fall_info: String = ""
var _last_pos: Vector3
var _last_state: int = 0
var stuck: bool = false

var _release_jump_at: int = -1
var _release_crouch_at: int = -1
var _crouched_this_fall: bool = false
var _peak_y: float = 0.0
var _slow_time: float = 0.0
var _frame: int = 0
var _start: Vector3
## 入力した直後は次を入れない（スクリプトの入力は1フレーム遅れて効く）
var _wait_until: int = 0
## 壁を蹴ったら、次の壁に張り付くまで次の壁蹴りをしない
var _wall_armed: bool = true
## 押しっぱなしのジャンプを押し直す時は、一度離して次のフレームで押す
var _press_at: int = -1
var _press_hold: int = 0
## ヴォルトに入ったら、障害物の上でもう一度押す
var _vault_jump_pending: bool = false
var _prev_swing: float = 0.0
## 主ルートの道しるべの dist → 通り過ぎたフレーム
var passed: Dictionary = {}
## 人の模型（start() の前に決める）
var human: bool = false
var seed_value: int = 1
var rng := RandomNumberGenerator.new()
## 人の模型：遅らせて押す入力 {at: 押すフレーム, kind: &"jump" / &"crouch", hold: 押している長さ}
var _queue: Array[Dictionary] = []
## 縁のジャンプを何フレーム早めるか（道しるべの番号 → フレーム。最初に見た時に1回だけ振る）
var _early: Dictionary = {}
## 人の模型：今回の落下でローリングを早める量（フレーム。-1 = まだ振っていない）
var _roll_early: float = -1.0


func start(p: Player, route: Array[Dictionary]) -> void:
	player = p
	nodes = route
	idx = 0
	_start = p.global_position
	rng.seed = seed_value
	# 自動走行はリトライを押さないので、戻されたら必ず落下（チェックポイント前ならスタートへ戻る）
	player.respawned.connect(func(_to_start: bool) -> void:
		falls += 1
		if fall_info == "":
			fall_info = "fell near (%.1f, %.1f, %.1f) state %d, node %d %s" % [_last_pos.x, _last_pos.y, _last_pos.z, _last_state, idx,
					str(nodes[idx]) if idx < nodes.size() else ""])
	Input.action_press(&"move_forward")


func stop() -> void:
	for a: StringName in [&"move_forward", &"jump", &"crouch"]:
		Input.action_release(a)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_frame += 1
	if _frame == _release_jump_at:
		Input.action_release(&"jump")
	if _frame == _press_at:
		Input.action_press(&"jump")
		_release_jump_at = _frame + _press_hold
	if _frame == _release_crouch_at:
		Input.action_release(&"crouch")
	_fire_queue()
	var p := player
	var pos := p.global_position
	var spd := p.horizontal_speed()
	if pos.y > p.kill_y + 3.0:
		_last_pos = pos
		_last_state = p.state

	# 動けなくなったら終わり（テストで失敗にする）
	_slow_time = _slow_time + delta if spd < 1.0 and p.state != Player.State.LEDGE_HANG else 0.0
	if _slow_time > 2.0:
		stuck = true

	_roll_if_needed(pos)
	_vault_jump_if_pending()
	# 通り過ぎた・すぐそこの道しるべ（技なし）を進める
	while idx < nodes.size() and int(nodes[idx].act) == CourseBuilder.Act.NONE and _remaining(idx, pos) <= 0.3:
		_advance(idx + 1)
	if p.state != Player.State.WALL_RUN:
		_wall_armed = true
	# 先にある技の道しるべ（間に技なしの道しるべがあっても見る）
	var k := idx
	while _frame >= _wait_until and k < mini(idx + 4, nodes.size()):
		var n := nodes[k]
		var act := int(n.act)
		if act == CourseBuilder.Act.NONE:
			k += 1
			continue
		var remaining := _remaining(k, pos)
		var lead := float(n.lead_c) + spd * float(n.lead_t)
		# 人の模型：縁のジャンプは早め（遅らせない）
		var early := human and act == CourseBuilder.Act.JUMP and float(n.lead_t) < VAULT_LEAD_T - 0.01
		if early:
			lead += spd * _early_frames(k) / 60.0
		var roll_ready := p.state == Player.State.ROLL and p.state_time >= p.params.roll_duration * 0.5 - 0.1
		match act:
			CourseBuilder.Act.JUMP, CourseBuilder.Act.VAULT_JUMP:
				# ローリング中のジャンプは後半（先行入力0.15秒込み）からしか効かない
				if remaining <= lead and (p.state in [Player.State.GROUND, Player.State.SLIDE] or roll_ready):
					_press_jump(12, not early)
					_vault_jump_pending = act == CourseBuilder.Act.VAULT_JUMP
					_advance(k + 1)
			CourseBuilder.Act.CROUCH:
				var rolling_out := p.state == Player.State.ROLL and p.state_time >= p.params.roll_duration * 0.5
				if remaining <= lead and (p.state == Player.State.GROUND or rolling_out):
					_tap_crouch()
					_advance(k + 1)
			CourseBuilder.Act.WALLJUMP:
				if p.state == Player.State.WALL_RUN and p.state_time >= 0.08 and _wall_armed:
					_press_jump(8)
					_wall_armed = false
					_advance(k + 1)
				elif remaining <= -1.0:
					_advance(k + 1)  # 壁に着かずに通り過ぎた
			CourseBuilder.Act.SWING:
				# 振り上がって理想の角度を越える1フレーム前に押す（スクリプトの入力は1フレーム遅れて効く）
				if p.state == Player.State.SWING:
					var step := p.swing_angle - _prev_swing
					if step > 0.0 and p.swing_angle + step * 1.5 >= deg_to_rad(p.params.swing_ideal_angle):
						_press_jump(10)
						_advance(k + 1)
				elif remaining <= -3.0:
					_advance(k + 1)  # バーを掴めずに通り過ぎた
			CourseBuilder.Act.ZIP:
				if p.state == Player.State.ZIPLINE:
					if p.zip_remaining_time() <= p.params.zip_ideal_time + 1.5 / 60.0:
						_press_jump(10)
						_advance(k + 1)
				elif p.state in [Player.State.GROUND, Player.State.ROLL] and remaining <= 0.0:
					_advance(k + 1)
			CourseBuilder.Act.CLIMB_KICK:
				# 縦ウォールランの頂点の2フレーム前に押す
				if p.state == Player.State.WALL_CLIMB:
					if p.velocity.y <= p.params.gravity() * 2.0 / 60.0:
						_press_jump(12)
						_advance(k + 1)
				elif p.state in [Player.State.CLIMB, Player.State.LEDGE_HANG] or (p.state == Player.State.GROUND and pos.y > float((n.p as Vector3).y) + 1.0):
					_advance(k + 1)
		break
	if p.state == Player.State.SWING:
		_prev_swing = p.swing_angle

	# 向き：横ウォールラン中は壁に沿って。それ以外は次の道しるべへ
	if p.state == Player.State.WALL_RUN:
		var v := Vector3(p.velocity.x, 0.0, p.velocity.z)
		if v.length() > 0.5:
			_steer_to(pos + v, pos)
	elif idx < nodes.size():
		var aim: Vector3 = nodes[idx].p
		# 目の前の道しるべが近すぎる時は、その次も見て急に向きを変えない
		if Vector2(aim.x - pos.x, aim.z - pos.z).length() < 1.0 and idx + 1 < nodes.size():
			aim = nodes[idx + 1].p
		_steer_to(aim, pos)


## idx を進める。主ルートの道しるべを通り過ぎた時刻を残す
func _advance(to_idx: int) -> void:
	while idx < to_idx and idx < nodes.size():
		var d := float(nodes[idx].get("dist", -1.0))
		if d >= 0.0 and not passed.has(d):
			passed[d] = _frame
		idx += 1


## ヴォルトに入ったら、手で押し切る所（障害物の奥の面）に体が来る少し前にもう一度押す
func _vault_jump_if_pending() -> void:
	if not _vault_jump_pending:
		return
	var p := player
	if p.state == Player.State.VAULT and p.move != null:
		var d := p.move.back_dist * p.move_progress
		if d >= p.move.back_face - p.horizontal_speed() * 2.0 / 60.0:
			_vault_jump_pending = false
			_press_jump(14)
	elif p.state not in [Player.State.GROUND, Player.State.SLIDE, Player.State.ROLL]:
		_vault_jump_pending = false  # ヴォルトにならなかった


## 道しるべ i までの残り（ひとつ前の道しるべからの向きで測る）
func _remaining(i: int, pos: Vector3) -> float:
	var target: Vector3 = nodes[i].p
	var prev: Vector3 = nodes[i - 1].p if i > 0 else _start
	var seg := Vector3(target.x - prev.x, 0.0, target.z - prev.z)
	if seg.length() < 0.05:
		# 同じ所に重なった道しるべは、さらに前の道しるべからの向きで
		var j := i - 1
		while j > 0 and Vector3(target.x - (nodes[j].p as Vector3).x, 0.0, target.z - (nodes[j].p as Vector3).z).length() < 0.05:
			j -= 1
		prev = nodes[j].p if j >= 0 else _start
		seg = Vector3(target.x - prev.x, 0.0, target.z - prev.z)
	if seg.length() < 0.05:
		seg = _heading()
	return Vector3(target.x - pos.x, 0.0, target.z - pos.z).dot(seg.normalized())


func _steer_to(target: Vector3, pos: Vector3) -> void:
	var d := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if d.length() < 0.05:
		return
	player.rig.set_look(atan2(-d.x, -d.z), 0.0)


func _heading() -> Vector3:
	return Basis(Vector3.UP, player.rig.yaw) * Vector3.FORWARD


## ジャンプを押す（人の模型なら遅らせる。late = false は遅らせない：縁のジャンプは lead を広げて早めている）
func _press_jump(hold_frames: int, late: bool = true) -> void:
	_act(&"jump", hold_frames, late)


func _tap_crouch() -> void:
	_act(&"crouch", 1, true)


## 入力する。人の模型は HUMAN_DELAY_MIN〜MAX フレーム後に押す（その間は次の判断もしない）
func _act(kind: StringName, hold_frames: int, late: bool) -> void:
	var delay := rng.randi_range(HUMAN_DELAY_MIN, HUMAN_DELAY_MAX) if human and late else 0
	_wait_until = _frame + 3 + delay
	if delay == 0:
		_fire(kind, hold_frames)
	else:
		_queue.append({"at": _frame + delay, "kind": kind, "hold": hold_frames})


func _fire_queue() -> void:
	var i := 0
	while i < _queue.size():
		if int(_queue[i].at) <= _frame:
			var q: Dictionary = _queue[i]
			_queue.remove_at(i)
			_fire(q.kind, int(q.hold))
		else:
			i += 1


func _fire(kind: StringName, hold_frames: int) -> void:
	if kind == &"crouch":
		Input.action_press(&"crouch")
		_release_crouch_at = _frame + 1
		return
	if Input.is_action_pressed(&"jump"):
		Input.action_release(&"jump")
		_press_at = _frame + 1
		_press_hold = hold_frames
		_release_jump_at = -1
		return
	Input.action_press(&"jump")
	_release_jump_at = _frame + hold_frames


## 縁のジャンプを早めるフレーム数（道しるべごとに最初に見た時に1回だけ振る）
func _early_frames(i: int) -> float:
	if not _early.has(i):
		_early[i] = rng.randi_range(0, HUMAN_EARLY_MAX)
	return float(_early[i])


## 2 m以上落ちる時は、着地の直前にしゃがんでローリング。
## 人の模型は早めに押す：完璧な走りは着地の約0.05 s前に押すので、そこから4〜8フレーム遅らせても着地の±0.05 s に収まって Perfect になってしまう。
## 人は着地を見越して早めに押す（先行入力は着地の0.2 s前から効く）ので、4〜8フレーム早く押す（遅れると着地後の0.08 sを過ぎて転がれない）
func _roll_if_needed(pos: Vector3) -> void:
	var p := player
	if p.state != Player.State.AIR:
		_crouched_this_fall = false
		_roll_early = -1.0
		_peak_y = pos.y
		return
	_peak_y = maxf(_peak_y, pos.y)
	if p.velocity.y >= 0.0 or _crouched_this_fall:
		return
	var reach := 0.6
	if human:
		reach = maxf(reach, minf(reach + absf(p.velocity.y) * _roll_early_frames() / 60.0, absf(p.velocity.y) * HUMAN_ROLL_MAX_TIME))
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.1, pos + Vector3.DOWN * reach)
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	if _peak_y - (hit.position as Vector3).y >= p.params.roll_min_drop:
		_act(&"crouch", 1, false)
	_crouched_this_fall = true


## 今回の落下で、ローリングを何フレーム早く押すか（落下ごとに1回だけ振る。着地したら振り直す）
func _roll_early_frames() -> float:
	if _roll_early < 0.0:
		_roll_early = float(rng.randi_range(HUMAN_DELAY_MIN, HUMAN_DELAY_MAX))
	return _roll_early
