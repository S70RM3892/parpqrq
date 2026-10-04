extends Node
## 見た目の審査用に、自動走行でコースを走りながら決めた時刻の画面を撮る（試験官 .claude/agents/aaa-examiner.md が使う）。
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" \
##     godot --path . --audio-driver Dummy --fixed-fps 60 res://tools/gallery.tscn -- --course=3-2 --at=4,12,20 --out=/tmp/g/c32 [--shortcuts]
## --at の秒数（走り出してからのゲーム内時間）ごとに <out>_<n>.png を保存し、描画の統計を <out>.txt に書く。
## 撮らない間はビューポートの描画を止めて（_render）自動走行だけを速く進める（1コース数秒〜数十秒）。
## --title=main|courses|controls|settings はタイトルの画面、--results はゴールの結果画面も撮る。--pitch=度 で撮る瞬間だけ上下を向く。

const COURSE_SCENE := preload("res://scenes/levels/course.tscn")
const WARM_FRAMES := 8  ## 撮る前に描画を戻すフレーム数（影・グロー・補間を落ち着かせる）

var _out: String = "/tmp/gallery/shot"
var _at: PackedFloat32Array = [4.0]
var _shortcuts: bool = false
var _course_id: String = "1-1"
var _title_page: String = ""
var _results: bool = false
var _look_pitch: float = NAN
var _stats: PackedStringArray = []
var _frame: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--course="):
			_course_id = a.trim_prefix("--course=")
		elif a.begins_with("--at="):
			_at = PackedFloat32Array(Array(a.trim_prefix("--at=").split(",")).map(func(s: String) -> float: return s.to_float()))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--shortcuts":
			_shortcuts = true
		elif a.begins_with("--title="):
			_title_page = a.trim_prefix("--title=")
		elif a == "--results":
			_results = true
		elif a.begins_with("--pitch="):
			_look_pitch = a.trim_prefix("--pitch=").to_float()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	DebugOverlay.visible = false
	Settings.first_run_done = true
	if _title_page != "":
		await _shoot_title()
	else:
		await _shoot_course()
	var f := FileAccess.open(_out + ".txt", FileAccess.WRITE)
	f.store_string("\n".join(_stats) + "\n")
	f.close()
	print("\n".join(_stats))
	Audio.quit_game()


func _shoot_title() -> void:
	var scene := (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
	add_child(scene)
	if _title_page != "main" and scene.has_method(&"_show"):
		scene.call_deferred(&"_show", StringName(_title_page))
	for i: int in 90:
		await get_tree().process_frame
	await _capture(0, "title " + _title_page)


func _shoot_course() -> void:
	Course.pending_id = _course_id
	var course := COURSE_SCENE.instantiate() as Course
	add_child(course)
	await get_tree().physics_frame
	if course.timer != null:
		course.timer.use_records("gallery_" + _course_id, true)
	var p := course.player
	var bot := Autopilot.new()
	add_child(bot)
	bot.start(p, course.builder.route(_shortcuts))
	var n := 0
	for target: float in _at:
		_render(false)
		if not await _run_until(bot, func() -> bool: return _frame >= roundi(target * 60.0) - WARM_FRAMES):
			break
		_render(true)
		if not await _run_until(bot, func() -> bool: return _frame >= roundi(target * 60.0)):
			break
		if not is_nan(_look_pitch):
			# 自動走行は毎フレーム視線を水平に戻すので、撮る間だけ止める
			bot.set_physics_process(false)
			for i: int in 4:
				p.rig.set_look(p.rig.yaw, deg_to_rad(_look_pitch))
				await get_tree().process_frame
		await _capture(n, "t=%.1fs state %s speed %.1f m/s pos %s" % [_frame / 60.0, Player.State.keys()[p.state],
				p.horizontal_speed(), p.global_position.snapped(Vector3.ONE * 0.1)])
		bot.set_physics_process(true)
		n += 1
	if _results and course.timer != null:
		_render(false)
		if await _run_until(bot, func() -> bool: return not course.timer.last_result.is_empty()):
			bot.stop()
			_render(true)
			for i: int in 80:
				await get_tree().process_frame
			await _capture(n, "results")
	_render(true)


## 描画を止める・戻す（止めている間は自動走行だけが進む）
func _render(on: bool) -> void:
	RenderingServer.viewport_set_update_mode(get_viewport().get_viewport_rid(),
			RenderingServer.VIEWPORT_UPDATE_ALWAYS if on else RenderingServer.VIEWPORT_UPDATE_DISABLED)


## 条件が立つまで物理フレームを進める。自動走行が止まったら false
func _run_until(bot: Autopilot, cond: Callable) -> bool:
	while not cond.call():
		await get_tree().physics_frame
		_frame += 1
		if bot.falls > 0 or bot.stuck or _frame > 60 * 300:
			_stats.append("WARNING autopilot stopped (falls %d stuck %s) at t=%.1f" % [bot.falls, bot.stuck, _frame / 60.0])
			return false
	return true


func _capture(n: int, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%d.png" % [_out, n]
	img.save_png(path)
	var vp := get_viewport()
	var draws := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) \
			+ vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prims := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME) \
			+ vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	var objs := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
	_stats.append("%s  draw_calls %d  primitives %d  objects %d  vram %.0f MB  | %s" % [
			path.get_file(), draws, prims, objs,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, label])
