extends Node
## 全コースを自動走行で走りきれるか確かめる（M4）。1.1 から近道も確かめる。
##   godot --headless --path . --fixed-fps 60 res://tests/course_test.tscn [-- --only=2-3]
## 各コースを2回走る：主ルートだけ（色付き）と、隠れた近道を全部通る走り。
## 合格：どちらも落ちずにゴール、近道はどれも主ルートより速い（MIN_SAVE 秒以上）、
## メダルが走りに合っている（開発者 = 近道の走りでぎりぎり、ゴールド = 主ルートの走りで取れる）。
## 終了コード 0 = 全コース合格。各コースのタイムとメダルの目安を出す。
## 記録は "test_<id>" のIDで取る（持ち主の自己ベストを上書きしない）。

const COURSE_SCENE := preload("res://scenes/levels/course.tscn")
## 近道1本で縮まる時間の最低（秒）
const MIN_SAVE := 0.25

var _failed: int = 0


func _ready() -> void:
	Settings.hitstop_slowmo = false
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var results: Array[String] = []
	for c: Dictionary in CourseCatalog.COURSES:
		if only != "" and c.id != only:
			continue
		results.append(await _run_course(c))
	print("\n".join(results))
	print("COURSE TEST: %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	Audio.quit_game(1 if _failed > 0 else 0)


func _run_course(c: Dictionary) -> String:
	var main := await _run_once(c, false)
	var short := await _run_once(c, true)
	var ok: bool = main.ok and short.ok
	var t: float = main.time
	var ts: float = short.time
	# 近道ごとに縮んだ時間：分かれる道しるべ → 戻る道しるべ までの時間を2つの走りで比べる
	var saves: PackedStringArray = []
	for sc: Dictionary in main.shortcuts:
		var a: float = sc.from_dist
		var b: float = sc.to_dist
		var tm := _span(main.passed, a, b)
		var tsc := _span(short.passed, a, b)
		var save := tm - tsc
		saves.append("%s %+.2f" % [sc.name, -save])
		if ok and not (save >= MIN_SAVE):
			_failed += 1
			ok = false
			print("FAIL %s: shortcut %s is not faster (main %.2f s, shortcut %.2f s)" % [c.id, sc.name, tm, tsc])
	# メダル：開発者 = 近道の走り（0.5秒単位で切り上げ）、ゴールド = 主ルートの走りの105%
	var medals: Array = c.medals
	if ok and not (ts <= float(medals[0]) and float(medals[0]) < t and t <= float(medals[1])):
		_failed += 1
		ok = false
		print("FAIL %s: medal times %s do not fit the runs (main %.2f, shortcuts %.2f) (update CourseCatalog)" % [c.id, str(medals), t, ts])
	return "%s %-4s %-16s main %6.2f s  shortcuts %6.2f s  route %4.0f m  crashes %d/%d  perfects %d/%d  medals %s  build %d ms\n       %s" % [
			"ok  " if ok else "FAIL", c.id, c.name, t, ts, main.route_len, main.crash, short.crash, main.perfect, short.perfect,
			_suggest(t, ts), main.build_ms, ", ".join(saves) if not saves.is_empty() else "(no shortcuts)"]


## 道しるべ a → b（dist）の間の時間（秒）
func _span(passed: Dictionary, a: float, b: float) -> float:
	if not passed.has(a) or not passed.has(b):
		return INF
	return (int(passed[b]) - int(passed[a])) / 60.0


func _run_once(c: Dictionary, take_shortcuts: bool) -> Dictionary:
	Course.pending_id = c.id
	var course := COURSE_SCENE.instantiate() as Course
	add_child(course)
	await get_tree().physics_frame
	course.timer.use_records("test_" + c.id, true)
	var p := course.player
	var bot := Autopilot.new()
	add_child(bot)
	var counts := {"crash": 0, "perfect": 0}
	var trace := OS.get_environment("COURSE_TRACE") != ""
	p.crashed.connect(func(spd: float) -> void:
		counts.crash += 1
		if trace and counts.crash <= 3:
			var col := p.get_last_slide_collision()
			print("  crash %.1f m/s at %s state %d node %d collider %s normal %s" % [spd, p.global_position, p.state, bot.idx,
					col.get_collider().name if col else "-", col.get_normal() if col else Vector3.ZERO]))
	p.perfect.connect(func(_k: StringName) -> void: counts.perfect += 1)
	var route := course.builder.route(take_shortcuts)
	bot.start(p, route)
	var limit := 60 * 240
	var frames := 0
	var tn := OS.get_environment("TRACE_NODES").split("-")
	var trace_mode := OS.get_environment("TRACE_MODE")  # main / short（空なら両方）
	var tracing := tn.size() == 2 and (trace_mode == "" or (trace_mode == "short") == take_shortcuts)
	while frames < limit:
		await get_tree().physics_frame
		frames += 1
		if tracing and bot.idx >= tn[0].to_int() and bot.idx <= tn[1].to_int():
			print("  f%d pos (%.2f, %.2f, %.2f) st %d t %.2f v (%.2f, %.2f, %.2f) node %d" % [frames, p.global_position.x, p.global_position.y, p.global_position.z, p.state, p.state_time, p.velocity.x, p.velocity.y, p.velocity.z, bot.idx])
		if not course.timer.last_result.is_empty() or bot.stuck or bot.falls > 0:
			break
	bot.stop()
	var res := course.timer.last_result
	var ok := not res.is_empty() and bot.falls == 0 and not bot.stuck
	var label := "%s%s" % [c.id, " (shortcuts)" if take_shortcuts else ""]
	if not ok:
		_failed += 1
		var pos := p.global_position
		print("FAIL %s: stopped at node %d/%d after %.1f s, pos (%.1f, %.1f, %.1f), state %d, falls %d, stuck %s" % [
				label, bot.idx, bot.nodes.size(), frames / 60.0, pos.x, pos.y, pos.z, p.state, bot.falls, bot.stuck])
		if bot.fall_info != "":
			print("     " + bot.fall_info)
	var shortcuts: Array[Dictionary] = []
	for sc: Dictionary in course.builder.shortcuts:
		shortcuts.append({"name": sc.name, "from_dist": float(course.builder.nodes[int(sc.from)].dist),
				"to_dist": float(course.builder.nodes[int(sc.to)].dist)})
	var out := {"ok": ok, "time": float(res.get("time", -1.0)), "passed": bot.passed, "crash": counts.crash,
			"perfect": counts.perfect, "route_len": course.builder.route_len, "build_ms": course.build_ms,
			"shortcuts": shortcuts}
	bot.queue_free()
	course.queue_free()
	await get_tree().physics_frame
	return out


## 走りからメダルの目安：開発者 = 近道の走りを0.5秒単位で切り上げ、ゴールド = 主ルートの105%、シルバー125%、ブロンズ155%
func _suggest(t: float, ts: float) -> String:
	if t <= 0.0 or ts <= 0.0:
		return "-"
	return "[%.1f, %.1f, %.1f, %.1f]" % [ceilf(ts * 2.0) / 2.0, ceilf(t * 1.05 * 2.0) / 2.0, ceilf(t * 1.25), ceilf(t * 1.55)]
