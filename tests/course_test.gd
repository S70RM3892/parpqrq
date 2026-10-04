extends Node
## 全コースを自動走行で走りきれるか確かめる（M4）。
##   godot --headless --path . --fixed-fps 60 res://tests/course_test.tscn [-- --only=2-3]
## 終了コード 0 = 全コース合格。各コースのタイムとメダルの目安を出す。
## 記録は "test_<id>" のIDで取る（持ち主の自己ベストを上書きしない）。

const COURSE_SCENE := preload("res://scenes/levels/course.tscn")

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
	Course.pending_id = c.id
	var course := COURSE_SCENE.instantiate() as Course
	add_child(course)
	await get_tree().physics_frame
	course.timer.use_records("test_" + c.id, true)
	var p := course.player
	var bot := Autopilot.new()
	add_child(bot)
	var seen := {}
	var counts := {"crash": 0, "perfect": 0}
	var trace := OS.get_environment("COURSE_TRACE") != ""
	p.crashed.connect(func(spd: float) -> void:
		counts.crash += 1
		if trace and counts.crash <= 3:
			var col := p.get_last_slide_collision()
			print("  crash %.1f m/s at %s state %d node %d collider %s normal %s" % [spd, p.global_position, p.state, bot.idx,
					col.get_collider().name if col else "-", col.get_normal() if col else Vector3.ZERO]))
	p.perfect.connect(func(_k: StringName) -> void: counts.perfect += 1)
	bot.start(p, course.builder.nodes)
	var limit := 60 * 240
	var frames := 0
	while frames < limit:
		await get_tree().physics_frame
		frames += 1
		seen[p.state] = true
		var tn := OS.get_environment("TRACE_NODES").split("-")
		if tn.size() == 2 and bot.idx >= tn[0].to_int() and bot.idx <= tn[1].to_int():
			print("  f%d pos (%.2f, %.2f, %.2f) st %d t %.2f v (%.2f, %.2f, %.2f) node %d" % [frames, p.global_position.x, p.global_position.y, p.global_position.z, p.state, p.state_time, p.velocity.x, p.velocity.y, p.velocity.z, bot.idx])
		if trace and frames < 200 and OS.get_environment("COURSE_TRACE") == "2":
			print("  f%d pos (%.2f, %.2f, %.2f) st %d v (%.2f, %.2f, %.2f) node %d" % [frames, p.global_position.x, p.global_position.y, p.global_position.z, p.state, p.velocity.x, p.velocity.y, p.velocity.z, bot.idx])
		if not course.timer.last_result.is_empty() or bot.stuck or bot.falls > 0:
			break
	bot.stop()
	var res := course.timer.last_result
	var ok := not res.is_empty() and bot.falls == 0 and not bot.stuck
	if not ok:
		_failed += 1
		var pos := p.global_position
		print("FAIL %s: stopped at node %d/%d after %.1f s, pos (%.1f, %.1f, %.1f), state %d, falls %d, stuck %s" % [
				c.id, bot.idx, bot.nodes.size(), frames / 60.0, pos.x, pos.y, pos.z, p.state, bot.falls, bot.stuck])
		if bot.fall_info != "":
			print("     " + bot.fall_info)
	var t: float = res.get("time", -1.0)
	# メダルは自動走行のタイムに合わせてある：開発者 < 自動走行 <= ゴールド。コースを変えたら目安の値に書き換える
	var medals: Array = c.medals
	if ok and not (float(medals[0]) < t and t <= float(medals[1])):
		_failed += 1
		ok = false
		print("FAIL %s: medal times %s do not fit the autopilot time %.2f (update CourseCatalog)" % [c.id, str(medals), t])
	var line := "%s %-4s %-16s %6.2f s  route %4.0f m  crashes %d  perfects %d  medals %s  build %d ms" % [
			"ok  " if ok else "FAIL", c.id, c.name, t, course.builder.route_len, counts.crash, counts.perfect,
			_suggest(t), course.build_ms]
	bot.queue_free()
	course.queue_free()
	await get_tree().physics_frame
	return line


## 自動走行のタイムからメダルの目安（開発者 = 自動走行の97%、ゴールド105%、シルバー125%、ブロンズ155%）
func _suggest(t: float) -> String:
	if t <= 0.0:
		return "-"
	return "[%.1f, %.1f, %.1f, %.1f]" % [floorf(t * 0.97 * 2.0) / 2.0, ceilf(t * 1.05 * 2.0) / 2.0, ceilf(t * 1.25), ceilf(t * 1.55)]
