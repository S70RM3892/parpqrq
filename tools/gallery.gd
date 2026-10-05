extends Node
## 見た目の審査用に、自動走行でコースを走りながら決めた時刻の画面を撮る（試験官 .claude/agents/aaa-examiner.md が使う）。
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" \
##     godot --path . --audio-driver Dummy --fixed-fps 60 res://tools/gallery.tscn -- --course=3-2 --at=4,12,20 --out=/tmp/g/c32 [--shortcuts]
## --at の秒数（走り出してからのゲーム内時間）ごとに <out>_<n>.png を保存し、描画の統計を <out>.txt に書く。
## 撮らない間はビューポートの描画を止めて（_render）自動走行だけを速く進める（1コース数秒〜数十秒）。
## --title=main|courses|controls|settings|comfort はタイトルの画面、--results はゴールの結果画面も撮る（--rframes=N で結果が出てから撮るまでのフレーム数。
## 既定 80 で演出の後、10 なら数え上げの途中）。--pause=menu|settings は最初の --at で一時停止（か、その中の設定）を撮る。--pitch=度 で撮る瞬間だけ上下を向く。
## --fake-records は見本の記録（各ティアのメダル・近道・ゴースト）を書いてから撮る（終わったら元の記録に戻す。メダルの表示の確認用）。
## 20:9（Android のフラッグシップ機：2400×1080）は xvfb の画面と --resolution を変える（tools/gallery.sh の wide）。
## --when=SWING,ZIPLINE は --at の代わりに、その状態（Player.State の名前）に順に入ってから --delay=N フレーム（既定 12）後を撮る（手の形の確認用）。
## 反射プローブのあるコースは、走り出す前にプローブが撮り終わるまで描画する（ゲーム中は走り出して数秒で揃う）。
## --thumb=<出力.jpg> はコース選択のカードの絵：最初の --at の画面から UI を消し、480×270 に縮めて JPG で書く（tools/thumbs.sh が全コースを撮り直す）。

const COURSE_SCENE := preload("res://scenes/levels/course.tscn")
const WARM_FRAMES := 8  ## 撮る前に描画を戻すフレーム数（影・グロー・補間を落ち着かせる）

var _out: String = "/tmp/gallery/shot"
var _at: PackedFloat32Array = [4.0]
var _shortcuts: bool = false
var _course_id: String = "1-1"
var _title_page: String = ""
var _results: bool = false
var _look_pitch: float = NAN
var _thumb: String = ""
var _pause: String = ""
var _rframes: int = 80
var _fake_records: bool = false
var _fake_ghosts: PackedStringArray = []
var _stats: PackedStringArray = []
var _frame: int = 0
var _when: PackedStringArray = []
var _delay: int = 12


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
		elif a.begins_with("--thumb="):
			_thumb = a.trim_prefix("--thumb=")
		elif a.begins_with("--pause="):
			_pause = a.trim_prefix("--pause=")
		elif a == "--fake-records":
			_fake_records = true
		elif a.begins_with("--when="):
			_when = a.trim_prefix("--when=").split(",")
		elif a.begins_with("--delay="):
			_delay = a.trim_prefix("--delay=").to_int()
		elif a.begins_with("--rframes="):
			_rframes = a.trim_prefix("--rframes=").to_int()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	if _thumb != "":
		DirAccess.make_dir_recursive_absolute(_thumb.get_base_dir())
	DebugOverlay.visible = false
	Settings.first_run_done = true
	if _fake_records:
		_write_fake_records()
	if _title_page != "":
		await _shoot_title()
	else:
		await _shoot_course()
	var f := FileAccess.open(_out + ".txt", FileAccess.WRITE)
	f.store_string("\n".join(_stats) + "\n")
	f.close()
	print("\n".join(_stats))
	if _fake_records:
		_restore_records()
	Audio.quit_game()


const _BAK := "user://best_times.cfg.gallery_bak"
## 見本：コースごとに違うティア。ルートカラーOFFの印・ゴースト・近道の全発見も混ぜる
const _FAKE: Dictionary[String, Array] = {
	"1-1": ["DEV", false, 2, true], "1-2": ["ACE", false, 3, false], "1-3": ["GOLD", false, 1, true], "1-4": ["SILVER", true, 0, false],
	"2-1": ["BRONZE", false, 2, false], "2-2": ["", false, 0, false], "2-3": ["GOLD", true, 4, true], "3-2": ["ACE", false, 4, true],
	"4-2": ["DEV", true, 4, true], "4-4": ["SILVER", false, 2, false],
}


func _write_fake_records() -> void:
	if not FileAccess.file_exists(_BAK):  # 前回途中で落ちた時の退避は上書きしない
		if FileAccess.file_exists(CourseTimer.SAVE_PATH):
			DirAccess.copy_absolute(CourseTimer.SAVE_PATH, _BAK)
	var cfg := ConfigFile.new()
	for id: String in _FAKE:
		var spec: Array = _FAKE[id]
		var medals: Array = CourseCatalog.get_course(id).medals
		var tier := CourseTimer.MEDALS.find(spec[0] as String)
		cfg.set_value("best", id, (medals[tier] as float) - 0.01 if tier >= 0 else 999.0)
		cfg.set_value("route_off", id, spec[1])
		var found := PackedStringArray()
		for i: int in int(spec[2]):
			found.append("s%d" % i)
		cfg.set_value("shortcuts", id, found)
		var gp := "user://ghost_%s.dat" % id
		if spec[3] and not FileAccess.file_exists(gp):  # 持ち主のゴーストがあれば触らない
			FileAccess.open(gp, FileAccess.WRITE).store_8(0)
			_fake_ghosts.append(gp)
	cfg.save(CourseTimer.SAVE_PATH)


func _restore_records() -> void:
	for gp: String in _fake_ghosts:
		DirAccess.remove_absolute(gp)
	if FileAccess.file_exists(_BAK):
		DirAccess.copy_absolute(_BAK, CourseTimer.SAVE_PATH)
		DirAccess.remove_absolute(_BAK)
	else:
		DirAccess.remove_absolute(CourseTimer.SAVE_PATH)


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
	# 反射プローブは1フレームに1つずつ、1つ数フレームかけて撮られる
	var probes := course.find_children("*", "ReflectionProbe", true, false).size()
	if probes > 0:
		_render(true)
		for i: int in probes * 9 + 4:
			await get_tree().process_frame
	var bot := Autopilot.new()
	add_child(bot)
	bot.start(p, course.builder.route(_shortcuts))
	var n := 0
	for st: String in _when:
		_render(false)
		var want := Player.State.keys().find(st)
		if want < 0 or not await _run_until(bot, func() -> bool: return p.state == want):
			print("gallery: state %s not reached" % st)
			break
		_render(true)
		var stop := _frame + _delay
		if not await _run_until(bot, func() -> bool: return _frame >= stop):
			break
		await _capture(n, "when %s +%d frames: t=%.1fs state %s speed %.1f m/s" % [st, _delay, _frame / 60.0,
				Player.State.keys()[p.state], p.horizontal_speed()])
		n += 1
	var times := _at if _when.is_empty() else PackedFloat32Array()
	for target: float in times:
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
		if _thumb != "":
			await _capture_thumb(course)
			_render(true)
			return
		if _pause != "":
			await _capture_pause(course, n)
			return
		await _capture(n, "t=%.1fs state %s speed %.1f m/s pos %s" % [_frame / 60.0, Player.State.keys()[p.state],
				p.horizontal_speed(), p.global_position.snapped(Vector3.ONE * 0.1)])
		bot.set_physics_process(true)
		n += 1
	if _results and course.timer != null:
		_render(false)
		if await _run_until(bot, func() -> bool: return not course.timer.last_result.is_empty()):
			bot.stop()
			_render(true)
			for i: int in _rframes:
				await get_tree().process_frame
			await _capture(n, "results (%d frames after the goal)" % _rframes)
	_render(true)


## 一時停止の画面（設定まで開く）。0.3 s ぶんの動きが終わってから撮る
func _capture_pause(course: Course, n: int) -> void:
	_render(true)
	course.pause_menu.open()
	if _pause == "settings":
		course.pause_menu._open_settings()
	for i: int in 40:
		await get_tree().process_frame
	await _capture(n, "pause " + _pause)
	course.pause_menu.close()


## コース選択の絵：画面の UI を消して 480×270 の JPG にする
func _capture_thumb(course: Course) -> void:
	_render(true)
	for layer: Node in course.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for layer: Node in course.player.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for i: int in WARM_FRAMES + 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(480, 270, Image.INTERPOLATE_LANCZOS)
	img.save_jpg(_thumb, 0.9)
	print("thumb ", _thumb)


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
