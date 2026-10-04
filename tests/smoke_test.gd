extends Node
## 起動して入力を流し、動きの数値が MovementParams どおりに出るかを確かめる。
## 実行: godot --headless --path . res://tests/smoke_test.tscn
## 終了コード 0 = 全部合格。

const TOL := 0.03  ## 許容誤差 3%

var _failed := 0


func _ready() -> void:
	await _run()
	print("SMOKE TEST: %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
	var p := get_tree().get_first_node_in_group(&"player") as Player
	_check_true("player exists", p != null)
	if p == null:
		return
	var mp := p.params
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

	# リトライでスタート地点へ戻る
	p.global_position += Vector3(5, 0, 0)
	Input.action_press(&"retry")
	await _frames(2)
	Input.action_release(&"retry")
	_check_near("retry returns to spawn", p.global_position.distance_to(Vector3(0, 0, 8)), 0.0, 0.05)

	await _course_run(p)
	await _crash_test(p)
	await _wall_jump_test(p)
	await _ledge_test(p)
	await _slide_slope_test(p)


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
	await _place(p, Vector3(14.45, 0.0, -2.0), Vector3.ZERO)
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


## コースを自動で走る。前進は押しっぱなし、決まった位置でジャンプ・しゃがみを押す
func _course_run(p: Player) -> void:
	var mp := p.params
	p.respawn()
	await _frames(10)
	# z がこの値を下回ったらジャンプ（障害物の前面 + 届く距離の手前）
	var jump_at: Array[float] = [1.9, -6.1, -34.3, -44.1, -81.3, -99.2, -111.2]
	var labels: Array[String] = ["vault 1.0 m", "vault 0.8 m", "vault onto 1.0 m box", "vault 1.2 m"]
	var vaulted: Array[bool] = [false, false, false, false, false, false, false]
	var speed_after: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var seen: Dictionary[Player.State, bool] = {}
	var slide_pressed := false
	var slide_cleared := false
	var wallrun_cleared := false
	var roll2_pressed := false
	var top_y := 0.0
	var next_jump := 0
	var was_vault := false
	var max_y_stairs1 := 0.0
	var max_y_stairs2 := 0.0
	var rolled := false
	var roll_pressed := false
	var roll_end_speed := 0.0
	var was_roll := false
	var hard := false
	var y_on_box := 0.0
	var counts := {"crash": 0}  # ラムダはローカルを値でコピーするので参照型で数える
	var on_crash := func(spd: float) -> void:
		counts.crash += 1
		print("  crash at z=%.2f y=%.2f state=%d speed=%.2f" % [p.global_position.z, p.global_position.y, p.state, spd])
	p.crashed.connect(on_crash)
	var label := get_tree().root.find_child("Time", true, false) as Label
	Input.action_press(&"move_forward")
	for i: int in 60 * 25:
		await get_tree().physics_frame
		var z := p.global_position.z
		var y := p.global_position.y
		if OS.get_environment("SMOKE_TRACE") != "" and z < -70.0:
			print("  z=%.2f y=%.2f st=%d spd=%.2f vy=%.2f" % [z, y, p.state, p.horizontal_speed(), p.velocity.y])
		if next_jump < jump_at.size() and z < jump_at[next_jump]:
			Input.action_press(&"jump")
			await get_tree().physics_frame
			Input.action_release(&"jump")
			next_jump += 1
		seen[p.state] = true
		# スライドでバーをくぐる
		if not slide_pressed and z < -72.6:
			Input.action_press(&"crouch")
			await get_tree().physics_frame
			Input.action_release(&"crouch")
			slide_pressed = true
		if z < -77.5 and z > -80.0 and y < 0.5:
			slide_cleared = true
		if z < -92.0 and z > -95.0 and y > -0.5:
			wallrun_cleared = true
		# 2.4 m の壁の上から降りる時もローリング
		if z < -104.0 and z > -108.0 and not roll2_pressed and p.state == Player.State.AIR and p.velocity.y < 0.0 and y < 0.5:
			Input.action_press(&"crouch")
			await get_tree().physics_frame
			Input.action_release(&"crouch")
			roll2_pressed = true
		if z < -112.5 and z > -118.0:
			top_y = maxf(top_y, y)
		if p.state == Player.State.VAULT:
			vaulted[next_jump - 1] = true
		elif was_vault:
			speed_after[next_jump - 1] = p.horizontal_speed()
			if next_jump == 3:
				y_on_box = y
		was_vault = p.state == Player.State.VAULT
		if z > -30.0 and z < -18.0:
			max_y_stairs1 = maxf(max_y_stairs1, y)
		if z < -50.0 and z > -64.0:
			max_y_stairs2 = maxf(max_y_stairs2, y)
		# 2.4 m の台から落ちて着地直前にしゃがむ → ローリング
		if z < -30.0 and z > -35.0 and not roll_pressed and p.state == Player.State.AIR and p.velocity.y < 0.0 and y < 0.5:
			Input.action_press(&"crouch")
			await get_tree().physics_frame
			Input.action_release(&"crouch")
			roll_pressed = true
		if p.state == Player.State.ROLL:
			rolled = true
		elif was_roll and z > -40.0:
			roll_end_speed = p.horizontal_speed()
		was_roll = p.state == Player.State.ROLL
		if p.state == Player.State.HARD_LAND:
			hard = true
		if label != null and label.text != "":
			break
	Input.action_release(&"move_forward")
	var keep := mp.run_speed * mp.vault_speed_keep
	for k: int in labels.size():  # 先頭4つがヴォルト
		_check_true("%s: vaulted" % labels[k], vaulted[k])
		if k != 2:
			_check_near("%s: speed kept" % labels[k], speed_after[k], keep, keep * 0.06)
	_check_near("vault onto: standing on box top", y_on_box, 1.0, 0.05)
	_check_true("step 0.45 m and stairs climbed to 2.4 m (got %.2f)" % max_y_stairs1, max_y_stairs1 > 2.35)
	_check_true("rolled after 2.4 m drop", rolled)
	_check_near("roll keeps speed", roll_end_speed, mp.run_speed, mp.run_speed * 0.08)
	_check_true("stairs climbed to 4.8 m (got %.2f)" % max_y_stairs2, max_y_stairs2 > 4.75)
	_check_true("hard landing after 4.8 m drop without roll", hard)
	_check_true("slide: entered SLIDE", seen.has(Player.State.SLIDE))
	_check_true("slide: passed under the 1.15 m bar", slide_cleared)
	_check_true("wall run: entered WALL_RUN", seen.has(Player.State.WALL_RUN))
	_check_true("wall run: crossed the 9 m pit", wallrun_cleared)
	_check_true("climb: entered CLIMB", seen.has(Player.State.CLIMB))
	_check_true("vertical wall run: entered WALL_CLIMB", seen.has(Player.State.WALL_CLIMB))
	_check_near("vertical wall run + ledge: on top of 4 m wall", top_y, 4.0, 0.1)
	p.crashed.disconnect(on_crash)
	_check_true("no wall crash on the clean line (got %d)" % counts.crash, counts.crash == 0)
	_check_true("reached goal, timer shown: %s" % (label.text.replace("\n", " ") if label != null else "-"), label != null and label.text != "")


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
