extends Node
## 画面の流れを本物の入力イベントで通しで確かめる（M4）。
##   godot --headless --path . --fixed-fps 60 res://tests/flow_test.tscn
## 初回の酔い対策の選択 → Play（1操作でコース開始）→ 自動走行でゴール → 結果 → リプレイ → リトライ → 一時停止 → コース選択 → フリーラン
## 持ち主の記録・設定を汚さないよう、最後に設定を全部元に戻す（記録は "flow_test" のIDで取る）。

var _failed: int = 0
var _checks: int = 0
## FLOW_SHOTS=<フォルダ> なら要所で画面を撮る（描画できる環境で）
var _shots: String = OS.get_environment("FLOW_SHOTS")
## 持ち主の設定（テストで初回の選択をするので、終わったら全部戻して保存する）
var _saved: Dictionary = {}


func _ready() -> void:
	# シーンが入れ替わってもこのノードは残す（入れ替わって消えるのは身代わりのノード）
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	for k: String in Settings._KEYS:
		_saved[k] = Settings.get(k)
	Settings.hitstop_slowmo = false
	Settings.first_run_done = false
	Game.last_course = ""
	get_tree().change_scene_to_file(Game.TITLE_SCENE)
	await _frames(10)
	await _run()
	for k: String in _saved:
		Settings.set(k, _saved[k])
	Settings.save_settings()
	Settings.apply()
	if _checks < 15:
		_failed += 1
		print("FAIL only %d checks ran" % _checks)
	print("FLOW TEST: %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	Audio.quit_game(1 if _failed > 0 else 0)


func _run() -> void:
	var title := get_tree().current_scene
	_check("title loaded", title != null and title.name == "Title")
	var focused := get_viewport().gui_get_focus_owner() as Button
	_check("first run: comfort prompt focused (%s)" % (focused.text if focused else "-"), focused != null and focused.text == "Standard")
	await _press(&"ui_accept")
	await _frames(3)
	focused = get_viewport().gui_get_focus_owner() as Button
	_check("main menu: Play focused (%s)" % (focused.text if focused else "-"), focused != null and focused.text.begins_with("Play"))
	await _shot("title")
	_check("comfort choice saved", Settings.first_run_done)
	# 1操作でコースが始まる
	await _press(&"ui_accept")
	await _frames(10)
	var course := get_tree().current_scene as Course
	_check("Play starts a course in one press (%s)" % (course.course_id if course else "-"), course != null)
	if course == null:
		return
	course.timer.use_records("flow_test", true)
	var bot := Autopilot.new()
	add_child(bot)
	bot.start(course.player, course.builder.nodes)
	var frames := 0
	while not course.results.is_open() and frames < 60 * 120:
		await get_tree().physics_frame
		frames += 1
	bot.stop()
	bot.queue_free()
	_check("results shown at the goal (%.1f s)" % (frames / 60.0), course.results.is_open())
	_check("player input stopped on results", not course.player.input_enabled)
	await _frames(2)
	var fo := get_viewport().gui_get_focus_owner()
	focused = fo as Button
	_check("results: Retry focused (%s)" % (str(fo.get_path()) if fo else "none"), focused != null and focused.text.begins_with("Retry"))
	await _shot("results")
	await _frames(25)
	# リプレイ
	course.results.replay_requested.emit()
	await _frames(30)
	_check("replay playing", course.replay.visible and not course.results.is_open())
	await _press(&"ui_accept")  # 3人称へ
	await _frames(20)
	_check("replay: third person view", course.replay._third)
	await _shot("replay")
	await _press(&"ui_cancel")
	await _frames(5)
	_check("replay closed back to results", course.results.is_open() and not course.replay.visible)
	await _frames(25)
	# リトライ（Y / R）
	await _press(&"retry")
	await _frames(5)
	_check("retry from results: back at start, input on", course.player.input_enabled and course.player.global_position.distance_to(course.builder.start_xf.origin) < 0.5)
	# 一時停止
	await _press(&"pause")
	await _frames(3)
	_check("pause opens and pauses the game", course.pause_menu.is_open() and get_tree().paused)
	await _shot("pause")
	course.pause_menu._open_settings()
	await _frames(3)
	await _shot("settings")
	course.pause_menu._settings.close()
	await _frames(2)
	await _press(&"ui_cancel")
	await _frames(3)
	_check("pause closes", not course.pause_menu.is_open() and not get_tree().paused)
	await _press(&"pause")
	await _frames(3)
	course.pause_menu.close()
	course.pause_menu.quit_requested.emit()
	await _frames(10)
	title = get_tree().current_scene
	focused = get_viewport().gui_get_focus_owner() as Button
	_check("quit returns to course select (%s)" % (focused.name if focused else "-"), title != null and title.name == "Title" and focused != null and String(focused.name).begins_with("Card_"))
	await _shot("courses")
	# フリーラン
	Game.play(CourseCatalog.FREE_RUN)
	await _frames(10)
	course = get_tree().current_scene as Course
	_check("free run loads without a timer", course != null and course.free_run and course.timer == null and course.player.is_on_floor())
	# フリーランの一時停止 → リトライ（計測が無くても動く）
	course.player.global_position += Vector3(3, 0, 3)
	await _press(&"pause")
	await _frames(3)
	var retry := get_viewport().gui_get_focus_owner() as Button
	_check("free run: pause opens with Retry focused", course.pause_menu.is_open() and retry != null and retry.text == "Retry")
	await _press(&"ui_accept")
	await _frames(3)
	_check("free run: retry returns to the start", not course.pause_menu.is_open() and course.player.global_position.distance_to(course.builder.start_xf.origin) < 0.5)


func _shot(shot_name: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, shot_name])


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(1)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		_failed += 1
