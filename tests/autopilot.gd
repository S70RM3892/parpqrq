class_name Autopilot
extends Node
## 自動走行：CourseBuilder の道しるべ（nodes）を順にたどって、決めた所でジャンプ・しゃがみ・壁蹴りを入力する。
## 入力は InputMap のアクションを押す（人と同じ経路）。コースが走りきれるかの確認と、メダルの基準タイムに使う。
## - 向き：次の道しるべへ視線を向けて前を押し続ける。横ウォールラン中は壁に沿って前を押す（離れる向きに倒すと落ちる）
## - ジャンプ：残りの距離が lead_c + 速さ×lead_t 以下になったら押す（ヴォルトは体が着く0.15秒前 = Perfect）
## - ローリング：2 m以上の落下で、着地直前にしゃがむ

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


func start(p: Player, route: Array[Dictionary]) -> void:
	player = p
	nodes = route
	idx = 0
	_start = p.global_position
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
	# 通り過ぎた・すぐそこの道しるべ（技なし）を進める
	while idx < nodes.size() and int(nodes[idx].act) == CourseBuilder.Act.NONE and _remaining(idx, pos) <= 0.3:
		idx += 1
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
		match act:
			CourseBuilder.Act.JUMP:
				# ローリング中のジャンプは後半（先行入力0.15秒込み）からしか効かない
				var roll_ready := p.state == Player.State.ROLL and p.state_time >= p.params.roll_duration * 0.5 - 0.1
				if remaining <= lead and (p.state in [Player.State.GROUND, Player.State.SLIDE] or roll_ready):
					_press_jump(12)
					idx = k + 1
			CourseBuilder.Act.CROUCH:
				var rolling_out := p.state == Player.State.ROLL and p.state_time >= p.params.roll_duration * 0.5
				if remaining <= lead and (p.state == Player.State.GROUND or rolling_out):
					_tap_crouch()
					idx = k + 1
			CourseBuilder.Act.WALLJUMP:
				if p.state == Player.State.WALL_RUN and p.state_time >= 0.08 and _wall_armed:
					_press_jump(8)
					_wall_armed = false
					idx = k + 1
				elif remaining <= -1.0:
					idx = k + 1  # 壁に着かずに通り過ぎた
		break

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


func _press_jump(hold_frames: int) -> void:
	_wait_until = _frame + 3
	if Input.is_action_pressed(&"jump"):
		Input.action_release(&"jump")
		_press_at = _frame + 1
		_press_hold = hold_frames
		_release_jump_at = -1
		return
	Input.action_press(&"jump")
	_release_jump_at = _frame + hold_frames


func _tap_crouch() -> void:
	Input.action_press(&"crouch")
	_release_crouch_at = _frame + 1
	_wait_until = _frame + 3


## 2 m以上落ちる時は、着地の直前にしゃがんでローリング
func _roll_if_needed(pos: Vector3) -> void:
	var p := player
	if p.state != Player.State.AIR:
		_crouched_this_fall = false
		_peak_y = pos.y
		return
	_peak_y = maxf(_peak_y, pos.y)
	if p.velocity.y >= 0.0 or _crouched_this_fall:
		return
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.1, pos + Vector3.DOWN * 0.6)
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	if _peak_y - (hit.position as Vector3).y >= p.params.roll_min_drop:
		_tap_crouch()
	_crouched_this_fall = true
