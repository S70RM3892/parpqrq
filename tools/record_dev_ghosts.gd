extends Node
## 開発者のゴースト（近道を全部通る自動走行の走り）を全コース記録して assets/ghosts/<id>.res に書く。
##   godot --headless --path . --fixed-fps 60 res://tools/record_dev_ghosts.tscn [-- --only=1-1,2-3]
## コースの形を変えたら記録し直す（形の指紋が違うゴーストは使われず、コーステストが「dev ghost stale」で落ちる）。

const COURSE_SCENE := preload("res://scenes/levels/course.tscn")


func _ready() -> void:
	Settings.hitstop_slowmo = false
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ghosts"))
	var failed := 0
	for c: Dictionary in CourseCatalog.COURSES:
		if not only.is_empty() and c.id not in only:
			continue
		if not await _record(c.id):
			failed += 1
	print("DEV GHOSTS: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	Settings.hitstop_slowmo = true
	Audio.quit_game(1 if failed > 0 else 0)


func _record(id: String) -> bool:
	Course.pending_id = id
	var course := COURSE_SCENE.instantiate() as Course
	add_child(course)
	await get_tree().physics_frame
	course.timer.use_records("devghost_" + id, true)
	var bot := Autopilot.new()
	add_child(bot)
	bot.start(course.player, course.builder.route(true))
	var frames := 0
	while frames < 60 * 240 and course.timer.last_result.is_empty() and not bot.stuck and bot.falls == 0:
		await get_tree().physics_frame
		frames += 1
	bot.stop()
	var ok := not course.timer.last_result.is_empty()
	if ok:
		var g := GhostData.new()
		g.run = course.timer.last_run.to_dict()
		g.time = float(course.timer.last_result.time)
		g.fingerprint = course.geometry_hash
		ok = ResourceSaver.save(g, GhostData.path_for(id), ResourceSaver.FLAG_COMPRESS) == OK
		print("dev ghost %s: %.2f s, %d frames" % [id, g.time, course.timer.last_run.size()])
	else:
		print("FAIL dev ghost %s: autopilot did not finish" % id)
	bot.queue_free()
	course.queue_free()
	await get_tree().physics_frame
	return ok
