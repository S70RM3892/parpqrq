extends Node
## 起動して入力を流し、動きの数値が MovementParams どおりに出るかを確かめる。
## 実行: godot --headless --path . res://tests/smoke_test.tscn
## 終了コード 0 = 全部合格。

const TOL := 0.03  ## 許容誤差 3%

var _failed := 0


func _ready() -> void:
	await _run()
	print("SMOKE TEST: %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	Audio.quit_game(1 if _failed > 0 else 0)


func _run() -> void:
	var p := get_tree().get_first_node_in_group(&"player") as Player
	_check_true("player exists", p != null)
	if p == null:
		return
	var mp := p.params
	Settings.hitstop_slowmo = false  # スローが入るとフレーム数で測る時間がずれる
	var timer := get_tree().root.find_child("CourseTimer", true, false) as CourseTimer
	timer.use_records("smoke_test", true)
	await _frames(30)
	_check_true("on floor at spawn", p.is_on_floor())

	# 走り：0.35 s で最高速、その後は 7.5 m/s を保つ
	Input.action_press(&"move_forward")
	await _seconds(mp.accel_time + 0.05)
	_check_near("run speed after accel_time", p.horizontal_speed(), mp.run_speed)
	Input.action_release(&"move_forward")
	await _seconds(mp.decel_time + 0.05)
	_check_near("stopped after decel_time", p.horizontal_speed(), 0.0)

	# ジャンプ：最高点 1.2 m、到達 0.36 s
	var y0 := p.global_position.y
	var top := y0
	var t := 0.0
	var t_top := 0.0
	var t_takeoff := -1.0
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	Input.action_press(&"jump")  # 押しっぱなし扱いで早離しカットを避ける
	for i: int in 120:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if t_takeoff < 0.0 and p.global_position.y > y0:
			t_takeoff = t - 1.0 / Engine.physics_ticks_per_second
		if p.global_position.y > top:
			top = p.global_position.y
			t_top = t
		if p.is_on_floor() and t > 0.1:
			break
	Input.action_release(&"jump")
	_check_near("jump apex height", top - y0, mp.jump_apex_height)
	_check_near("jump apex time", t_top - t_takeoff, mp.jump_apex_time, 1.0 / 60.0 + 0.001)
	_check_true("landed", p.is_on_floor())

	await _retry_tests(p)

	await _course_run(p)
	_check_true("ghost saved from the best run (%d samples)" % timer.ghost_samples(), timer.ghost_samples() > 300)
	_check_true("result has a medal: %s" % str(timer.last_result), timer.last_result.get("medal", "") != "")
	await _perfect_tests(p)
	await _inertia_tests(p)
	await _momentum_test(p)
	await _stairs_test(p)
	await _crash_test(p)
	await _wall_jump_test(p)
	await _ledge_test(p)
	await _slide_slope_test(p)


## 即リトライ（仕様書 5章）：押して離せば0.5秒以内にスタートへ、0.3秒押し続ければチェックポイントへ。落下でもチェックポイントへ
func _retry_tests(p: Player) -> void:
	var spawn := p.spawn.origin
	var c := {"start": 0, "cp": 0}
	var on_respawn := func(to_start: bool) -> void:
		if to_start:
			c.start += 1
		else:
			c.cp += 1
	p.respawned.connect(on_respawn)
	# 素早く押して離す（6フレーム = 0.1秒）
	p.global_position += Vector3(5, 0, 0)
	var frames := 0
	Input.action_press(&"retry")
	while c.start == 0 and frames < 60:
		await get_tree().physics_frame
		frames += 1
		if frames == 6:
			Input.action_release(&"retry")
	Input.action_release(&"retry")
	await get_tree().physics_frame
	_check_near("retry returns to spawn", p.global_position.distance_to(spawn), 0.0, 0.05)
	_check_true("retry: back at start within 0.5 s of the press (%.2f s)" % (frames / 60.0), c.start == 1 and frames / 60.0 <= 0.5)

	# 長押し：チェックポイントへ（スタートには戻らない）
	var cp := Transform3D(Basis.IDENTITY, Vector3(-19.0, 0.0, 0.0))
	p.checkpoint = cp
	p.global_position += Vector3(3, 0, -3)
	c.start = 0
	frames = 0
	Input.action_press(&"retry")
	while c.cp == 0 and frames < 60:
		await get_tree().physics_frame
		if p.retry_hold >= 0.0 or frames > 0:  # 押したのが見えたフレームから数える（スクリプトの入力は1フレーム遅れる）
			frames += 1
	await _frames(10)  # 押したまま：もう一度は戻らない
	Input.action_release(&"retry")
	await _frames(3)
	_check_true("hold retry: back at checkpoint (%.2f s)" % (frames / 60.0), c.cp == 1 and c.start == 0 and p.global_position.distance_to(cp.origin) < 0.3)
	_check_near("hold retry: takes 0.3 s", frames / 60.0, Player.RETRY_HOLD, 1.5 / 60.0)

	# 道より下に落ちたらチェックポイントへ
	c.cp = 0
	p.kill_y = -5.0
	p.global_position = Vector3(-19.0, -6.0, 8.0)
	await _frames(2)
	p.kill_y = -30.0
	_check_true("fell below the course: back at checkpoint", c.cp == 1 and p.global_position.distance_to(cp.origin) < 0.3)
	p.respawned.disconnect(on_respawn)
	p.checkpoint = p.spawn
	p.respawn()
	await _frames(10)


## 階段は滑らかに上がる：1フレームの上昇が一定以下（段ごとに跳ねない）、水平速度を保つ
func _stairs_test(p: Player) -> void:
	await _place(p, Vector3(0.0, 0.0, -20.0), Vector3.ZERO)
	await _frames(5)
	Input.action_press(&"move_forward")
	await _seconds(0.5)  # 走り速度まで上げる
	var max_dy := 0.0
	var min_spd := INF
	var prev_y := p.global_position.y
	var airborne := 0
	while p.global_position.z > -30.0:
		await get_tree().physics_frame
		var y := p.global_position.y
		if p.global_position.z < -23.0:
			max_dy = maxf(max_dy, absf(y - prev_y))
			min_spd = minf(min_spd, p.horizontal_speed())
			if p.state != Player.State.GROUND:
				airborne += 1
		prev_y = y
	Input.action_release(&"move_forward")
	_check_true("stairs: no per-frame jump in height (max %.3f m/frame)" % max_dy, max_dy < 0.12)
	_check_true("stairs: keeps speed (min %.2f m/s)" % min_spd, min_spd > p.params.run_speed * 0.95)
	_check_true("stairs: never leaves the ground (%d frames)" % airborne, airborne == 0)


## ジャンプせずに 1.0 m の壁へ走り込むと激突になる（段差の判定と取り違えない）
func _crash_test(p: Player) -> void:
	await _place(p, Vector3(0.0, 0.0, 6.0), Vector3.ZERO)
	var c := {"crash": 0}
	var on_crash := func(_s: float) -> void: c.crash += 1
	p.crashed.connect(on_crash)
	Input.action_press(&"move_forward")
	await _seconds(1.2)
	Input.action_release(&"move_forward")
	p.crashed.disconnect(on_crash)
	_check_true("crash: running into a 1.0 m wall counts as a crash (%d)" % c.crash, c.crash >= 1)


func _place(p: Player, pos: Vector3, vel: Vector3) -> void:
	p.respawn(Transform3D(Basis.IDENTITY, pos))
	p.velocity = vel
	await get_tree().physics_frame


## 壁ジャンプ回廊：左の壁を走る → 壁ジャンプ（速度+10%）→ 右の壁に張り付く
func _wall_jump_test(p: Player) -> void:
	await _place(p, Vector3(14.75, 0.0, -2.0), Vector3.ZERO)  # 左の壁の内面は x=14.25
	await _frames(5)
	var c := {"runs": 0, "jumps": 0, "speed_after": 0.0}  # ラムダはローカルを値でコピーするので参照型で数える
	var speed_before := 0.0
	var on_run := func() -> void: c.runs += 1
	var on_jump := func() -> void:
		c.jumps += 1
		c.speed_after = p.horizontal_speed()
	p.wallrun_started.connect(on_run)
	p.wall_jumped.connect(on_jump)
	Input.action_press(&"move_forward")
	await _seconds(0.8)
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	for i: int in 30:
		await get_tree().physics_frame
		if OS.get_environment("SMOKE_TRACE") != "":
			print("  wj x=%.2f y=%.2f z=%.2f st=%d spd=%.2f" % [p.global_position.x, p.global_position.y, p.global_position.z, p.state, p.horizontal_speed()])
		if p.state == Player.State.WALL_RUN:
			break
	speed_before = p.horizontal_speed()
	await _seconds(0.3)
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	Input.action_press(&"move_right")  # 反対の壁の方へ倒す
	await _seconds(0.8)
	Input.action_release(&"move_right")
	Input.action_release(&"move_forward")
	p.wallrun_started.disconnect(on_run)
	p.wall_jumped.disconnect(on_jump)
	_check_true("wall jump: ran on a wall (runs %d)" % c.runs, c.runs >= 1)
	_check_true("wall jump: jumped off (jumps %d)" % c.jumps, c.jumps >= 1)
	_check_near("wall jump: speed +10%", c.speed_after, speed_before * (1.0 + p.params.wall_jump_speed_bonus), 0.3)
	_check_true("wall jump: caught the opposite wall (runs %d)" % c.runs, c.runs >= 2)


## 2.0 m の箱：空中で縁を掴んでぶら下がる → 横移動 → 登る
func _ledge_test(p: Player) -> void:
	await _place(p, Vector3(-8.0, 0.8, -27.7), Vector3(0, 0, -2.0))
	for i: int in 30:
		await get_tree().physics_frame
		if p.state == Player.State.LEDGE_HANG:
			break
	_check_true("ledge: grabbed and hanging", p.state == Player.State.LEDGE_HANG)
	var x0 := p.global_position.x
	Input.action_press(&"move_right")
	await _seconds(0.5)
	Input.action_release(&"move_right")
	_check_near("ledge: shimmied right", p.global_position.x - x0, p.params.ledge_shimmy_speed * 0.5, 0.15)
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	await _seconds(0.8)
	_check_near("ledge: climbed onto the 2.0 m box", p.global_position.y, 2.0, 0.05)


## 下り坂のスライドは 0.8 s を過ぎても加速し続ける
func _slide_slope_test(p: Player) -> void:
	await _place(p, Vector3(-14.0, 2.6, -10.0), Vector3(0, 0, -6.0))
	Input.action_press(&"move_forward")
	for i: int in 30:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	var v0 := p.horizontal_speed()
	Input.action_press(&"crouch")
	await get_tree().physics_frame
	Input.action_release(&"crouch")
	await _seconds(1.0)
	_check_true("slide slope: still sliding after 1.0 s (state %d)" % p.state, p.state == Player.State.SLIDE)
	_check_true("slide slope: accelerating (%.2f -> %.2f m/s)" % [v0, p.horizontal_speed()], p.horizontal_speed() > v0 + 0.5)
	Input.action_release(&"move_forward")


## コースを自動で走る。前進は押しっぱなしで、前方をレイで見てジャンプ・スライド・ローリングを判断する
## （z座標の決め打ちにしないので、コースの配置を変えてもこのテストは直さなくていい）
func _course_run(p: Player) -> void:
	var mp := p.params
	p.respawn()
	await _frames(10)
	var r := {
		"vaults": 0, "onto_y": -1.0, "vault_speeds": [], "rolled": false, "roll_end_speed": -1.0,
		"crash": 0, "min_y": 0.0, "max_y": 0.0, "top_after_wall_climb": 0.0, "hard": 0, "hard_speed": -1.0, "hard_frame": -1,
		"vault_in": 0.0, "roll_gain": 0.0, "perfects": 0,
		"wallrun_in": 0.0, "wallrun_out": -1.0, "stall": 0, "running": false,
	}
	var on_perfect := func(_k: StringName) -> void: r.perfects += 1
	p.perfect.connect(on_perfect)
	var last_air_speed := 0.0
	var on_hard := func(_d: float) -> void:
		r.hard += 1
		r.hard_frame = Engine.get_physics_frames()
	p.hard_landed.connect(on_hard)
	var seen: Dictionary[Player.State, bool] = {}
	var on_crash := func(spd: float) -> void:
		r.crash += 1
		print("  crash at z=%.2f y=%.2f state=%d speed=%.2f" % [p.global_position.z, p.global_position.y, p.state, spd])
	p.crashed.connect(on_crash)
	var label := get_tree().root.find_child("Time", true, false) as Label
	var prev_state := p.state
	var was_onto := false
	var peak_y := 0.0
	var crouched_this_fall := false
	var cooldown := 0.0
	var jump_release_at := -1  # ジャンプは0.2秒押す（1フレームで離すと早離しカットで半分の高さになる）
	Input.action_press(&"move_forward")
	for i: int in 60 * 40:
		await get_tree().physics_frame
		if i == jump_release_at:
			Input.action_release(&"jump")
		var pos := p.global_position
		var spd := p.horizontal_speed()
		if OS.get_environment("SMOKE_TRACE") != "" and pos.z < -96.0 and pos.z > -116.0:
			print("  T z=%.2f x=%.2f y=%.2f st=%d vy=%.2f spd=%.2f" % [pos.z, pos.x, pos.y, p.state, p.velocity.y, spd])
		var dir := Vector3(p.velocity.x, 0.0, p.velocity.z).normalized() if spd > 1.0 else Vector3.FORWARD
		cooldown -= 1.0 / 60.0
		if r.hard_frame >= 0 and r.hard_speed < 0.0 and Engine.get_physics_frames() >= r.hard_frame + 20:
			r.hard_speed = spd  # ハードランディングの約0.3秒後の速度
		seen[p.state] = true
		# M2ゲート「全技が速度を落とさずにつながる」：走り出した後、地上で走り速度の90%を下回っていた時間
		if spd >= mp.run_speed * 0.95:
			r.running = true
		if r.running and p.state == Player.State.GROUND and spd < mp.run_speed * 0.9:
			r.stall += 1
			if OS.get_environment("SMOKE_TRACE") != "":
				print("  stall z=%.2f y=%.2f spd=%.2f" % [pos.z, pos.y, spd])
		r.min_y = minf(r.min_y, pos.y)
		r.max_y = maxf(r.max_y, pos.y)
		if seen.has(Player.State.WALL_CLIMB):
			r.top_after_wall_climb = maxf(r.top_after_wall_climb, pos.y)

		# 状態が変わった瞬間の記録
		if p.state != prev_state:
			if p.state == Player.State.VAULT:
				r.vault_in = p._move_speed_in
			if prev_state == Player.State.VAULT:
				r.vaults += 1
				if was_onto:
					r.onto_y = pos.y
				else:
					(r.vault_speeds as Array).append(spd / r.vault_in)
			if p.state == Player.State.ROLL and r.roll_gain == 0.0 and last_air_speed > 0.0:
				r.roll_gain = spd / last_air_speed
			if prev_state == Player.State.ROLL and r.roll_end_speed < 0.0:
				r.roll_end_speed = spd
			if p.state == Player.State.AIR:
				peak_y = pos.y
				crouched_this_fall = false
			if p.state == Player.State.WALL_RUN:
				r.wallrun_in = spd
			if prev_state == Player.State.WALL_RUN and r.wallrun_out < 0.0:
				r.wallrun_out = spd
			prev_state = p.state
		if p.state == Player.State.VAULT and p.move != null:
			was_onto = p.move.onto
		if p.state == Player.State.ROLL:
			r.rolled = true
		if p.state == Player.State.AIR:
			peak_y = maxf(peak_y, pos.y)
			last_air_speed = spd

		var on_feet := p.state == Player.State.GROUND or p.state == Player.State.ROLL
		if on_feet and cooldown <= 0.0:
			var reach := 0.35 + maxf(0.6, spd * 0.15)
			if not _ray(p, pos + Vector3.UP * 0.4, dir * reach).is_empty():
				Input.action_press(&"jump")  # 前に障害物
				jump_release_at = i + 12
				cooldown = 0.3
			elif not _ray(p, pos + Vector3.UP * 1.5, dir * (0.35 + spd * 0.12)).is_empty() \
					and _ray(p, pos + Vector3.UP * 0.4, dir * reach).is_empty():
				await _tap(&"crouch")  # 頭の高さだけに障害物 → スライドでくぐる
				cooldown = 0.3
			elif _ray(p, pos + dir * spd * 0.12 + Vector3.UP * 0.5, Vector3.DOWN * 8.0).is_empty():
				Input.action_press(&"jump")  # 床が無い（穴）
				jump_release_at = i + 12
				cooldown = 0.3
		# 大きな落下（2〜4.5 m）は着地直前にしゃがんでローリング。4.5 m以上はわざとハードランディングを見る
		if p.state == Player.State.AIR and p.velocity.y < 0.0 and not crouched_this_fall:
			var ground := _ray(p, pos + Vector3.UP * 0.1, Vector3.DOWN * 0.6)
			if not ground.is_empty():
				var drop := peak_y - (ground.position as Vector3).y
				if drop >= mp.roll_min_drop and drop < 4.5:
					await _tap(&"crouch")
				crouched_this_fall = true
		if label != null and label.text != "":
			break
	Input.action_release(&"move_forward")
	Input.action_release(&"jump")
	p.crashed.disconnect(on_crash)
	p.hard_landed.disconnect(on_hard)
	p.perfect.disconnect(on_perfect)
	print("  course run: perfects %d, momentum at goal %.2f, result %s" % [r.perfects, p.momentum, str(timer_result())])

	_check_true("vaults done: %d (want 4: 1.0 m, 0.8 m, onto box, 1.2 m)" % r.vaults, r.vaults >= 4)
	for ratio: float in r.vault_speeds:
		_check_true("vault keeps >= 95%% speed (x%.3f)" % ratio, ratio > mp.vault_speed_keep - 0.01)
	_check_near("vault onto: standing on box top", r.onto_y, 1.0, 0.05)
	_check_true("stairs climbed to the 4.8 m tower (max y %.2f)" % r.max_y, r.max_y > 4.75)
	_check_true("rolled after a big drop", r.rolled)
	_check_true("roll adds speed (x%.3f)" % r.roll_gain, r.roll_gain > 1.0 + mp.roll_speed_bonus - 0.02)
	_check_true("hard landing feedback after 4.8 m drop without roll (%d)" % r.hard, r.hard >= 1)
	_check_near("hard landing does not stop the run (speed after)", r.hard_speed, mp.run_speed * (1.0 - mp.hard_land_speed_loss), 0.5)
	_check_true("slide under the bar", seen.has(Player.State.SLIDE))
	_check_true("wall run over the pit", seen.has(Player.State.WALL_RUN))
	_check_true("never fell into the pit (min y %.2f)" % r.min_y, r.min_y > -1.0)
	_check_true("climb", seen.has(Player.State.CLIMB))
	_check_true("vertical wall run", seen.has(Player.State.WALL_CLIMB))
	_check_true("on top of the 4 m wall after vertical wall run (max y %.2f)" % r.top_after_wall_climb, r.top_after_wall_climb > 3.95)
	_check_true("no wall crash on the clean line (got %d)" % r.crash, r.crash == 0)
	_check_true("wall run keeps speed (%.2f -> %.2f m/s)" % [r.wallrun_in, r.wallrun_out], r.wallrun_out >= r.wallrun_in * 0.95)
	_check_true("M2 gate: moves chain without slowing down (%.2f s below 90%% run speed)" % (r.stall / 60.0), r.stall / 60.0 <= 0.3)
	_check_true("reached goal, timer shown: %s" % (label.text.replace("\n", " ") if label != null else "-"), label != null and label.text != "")


func timer_result() -> Dictionary:
	var t := get_tree().root.find_child("CourseTimer", true, false) as CourseTimer
	return t.last_result if t != null else {}


## 平らな場所（x=-19）で走り出し、走り速度に乗せる
func _run_up(p: Player, z: float = 8.0) -> void:
	await _place(p, Vector3(-19.0, 0.0, z), Vector3.ZERO)
	await _frames(3)
	Input.action_press(&"move_forward")
	await _seconds(0.5)


## 着地Perfectジャンプ・Perfectローリング・ずれたローリング・Perfectヴォルト
func _perfect_tests(p: Player) -> void:
	var mp := p.params
	var got := {"kinds": []}
	var on_perfect := func(k: StringName) -> void: (got.kinds as Array).append(k)
	p.perfect.connect(on_perfect)

	# 着地の瞬間にジャンプ → 速度+3%
	await _run_up(p)
	Input.action_press(&"jump")
	await _frames(12)
	Input.action_release(&"jump")
	while p.state != Player.State.GROUND:
		await get_tree().physics_frame
	var v_land := p.horizontal_speed()
	Input.action_press(&"jump")
	await _frames(2)
	_check_true("perfect landing jump fired", (got.kinds as Array).has(&"landing_jump"))
	_check_near("perfect landing jump: speed +3%", p.horizontal_speed(), v_land * (1.0 + mp.perfect_speed_bonus), 0.08)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")

	# 3 m から落ちて、着地のフレームでしゃがむ → Perfectローリング（+10% と +3%）
	got.kinds = []
	await _place(p, Vector3(-19.0, 3.0, 8.0), Vector3(0, 0, -8.0))
	Input.action_press(&"move_forward")  # 実際のプレイと同じく前を押したまま（離すと地上で減速が入る）
	while p.state != Player.State.GROUND:
		await get_tree().physics_frame
	var v0 := p.horizontal_speed()
	Input.action_press(&"crouch")
	await _frames(2)
	Input.action_release(&"crouch")
	Input.action_release(&"move_forward")
	_check_true("perfect roll: rolled", p.state == Player.State.ROLL)
	_check_true("perfect roll fired", (got.kinds as Array).has(&"roll"))
	_check_near("perfect roll: speed x1.10 x1.03", p.horizontal_speed(), v0 * (1.0 + mp.roll_speed_bonus) * (1.0 + mp.perfect_speed_bonus), 0.15)

	# 着地の0.15秒前にしゃがむ → ローリングは成功（+10%）、Perfectではない
	got.kinds = []
	await _place(p, Vector3(-19.0, 3.0, 8.0), Vector3(0, 0, -8.0))
	while p.velocity.y > -0.1 or p.global_position.y > absf(p.velocity.y) * 0.15 + 0.02:
		await get_tree().physics_frame
	Input.action_press(&"crouch")
	await get_tree().physics_frame
	Input.action_release(&"crouch")
	while p.state == Player.State.AIR:
		await get_tree().physics_frame
	_check_true("early roll: rolled", p.state == Player.State.ROLL)
	_check_true("early roll: not perfect", not (got.kinds as Array).has(&"roll"))
	_check_near("early roll: speed x1.10", p.horizontal_speed(), 8.0 * (1.0 + mp.roll_speed_bonus), 0.1)

	# ヴォルト：体が壁に着く0.15秒前に押す → Perfect、越えた後の速度は100%+3%
	got.kinds = []
	await _place(p, Vector3(0.0, 0.0, 9.0), Vector3.ZERO)
	await _frames(3)
	Input.action_press(&"move_forward")
	await _seconds(0.5)
	while p.global_position.z - 0.25 - 0.35 > p.horizontal_speed() * mp.vault_ideal_time:
		await get_tree().physics_frame
	var v_in := p.horizontal_speed()
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	while p.state != Player.State.VAULT:
		await get_tree().physics_frame
	while p.state == Player.State.VAULT:
		await get_tree().physics_frame
	_check_true("perfect vault fired", (got.kinds as Array).has(&"vault"))
	_check_near("perfect vault: exit speed +3%", p.horizontal_speed(), v_in * (1.0 + mp.perfect_speed_bonus), 0.15)
	Input.action_release(&"move_forward")
	p.perfect.disconnect(on_perfect)


## 慣性の制御：地上ブレーキ、空中は入力なしで勢いを保つ、空中ブレーキ、クイックターン
func _inertia_tests(p: Player) -> void:
	var mp := p.params
	# 地上：逆に倒すと急停止
	await _run_up(p)
	var v0 := p.horizontal_speed()
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	var braked := false
	var t := 0.0
	while p.horizontal_speed() > 0.5 and t < 1.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		braked = braked or p.braking
	Input.action_release(&"move_back")
	_check_true("brake: braking flag on", braked)
	_check_true("brake: %.1f m/s stopped in %.2f s" % [v0, t], t <= v0 / mp.brake_decel + 0.05)

	# 空中：何も倒さなければ勢いを保つ
	await _run_up(p)
	Input.action_press(&"jump")
	await _frames(2)  # スクリプトからの入力は1フレーム遅れて反映される
	Input.action_release(&"move_forward")
	var v_air := p.horizontal_speed()
	await _seconds(0.4)
	Input.action_release(&"jump")
	_check_near("air: no input keeps momentum", p.horizontal_speed(), v_air, 0.05)

	# 空中：逆に倒すとブレーキ
	await _run_up(p)
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"move_forward")
	v_air = p.horizontal_speed()
	Input.action_press(&"move_back")
	await _seconds(0.3)
	Input.action_release(&"move_back")
	Input.action_release(&"jump")
	var want := v_air - mp.brake_decel * mp.air_brake * 0.3
	_check_true("air brake: %.2f -> %.2f m/s (want <= %.2f)" % [v_air, p.horizontal_speed(), want + 0.3], p.horizontal_speed() <= want + 0.3)

	# クイックターン：振り向いて、速度の半分で反対へ
	await _run_up(p)
	var yaw0 := p.rig.yaw
	v0 = p.horizontal_speed()
	Input.action_press(&"quick_turn")
	await _frames(2)
	Input.action_release(&"quick_turn")
	_check_true("quick turn: moving backwards now (vz %.2f)" % p.velocity.z, p.velocity.z > v0 * mp.quick_turn_keep * 0.9)
	await _seconds(mp.quick_turn_time + 0.05)
	_check_near("quick turn: view turned 180 deg", absf(wrapf(p.rig.yaw - yaw0, -PI, PI)), PI, 0.05)
	Input.action_release(&"move_forward")


## 勢い値：止まっていると減る、走っている間は減らない
func _momentum_test(p: Player) -> void:
	await _place(p, Vector3(-19.0, 0.0, 8.0), Vector3.ZERO)
	await _frames(3)
	Input.action_press(&"move_forward")
	await _seconds(0.5)  # 歩き速度より遅い加速中は減るので、走り速度に乗ってから測る
	p.momentum = 0.5
	await _seconds(1.0)
	_check_near("momentum: does not drop while running", p.momentum, 0.5, 0.01)
	Input.action_release(&"move_forward")
	await _seconds(1.5)
	_check_true("momentum: drops while stopped (%.2f)" % p.momentum, p.momentum <= maxf(0.5 - p.params.momentum_stop_decay * 1.2, 0.0) + 0.01)


func _ray(p: Player, from: Vector3, motion: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + motion)
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _check_near(label: String, got: float, want: float, abs_tol: float = -1.0) -> void:
	var tol := abs_tol if abs_tol >= 0.0 else maxf(absf(want) * TOL, 0.05)
	var ok := absf(got - want) <= tol
	print("%s %s: got %.3f want %.3f" % ["ok  " if ok else "FAIL", label, got, want])
	if not ok:
		_failed += 1


func _check_true(label: String, cond: bool) -> void:
	print("%s %s" % ["ok  " if cond else "FAIL", label])
	if not cond:
		_failed += 1


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(ceili(s * Engine.physics_ticks_per_second))
