class_name Course
extends Node3D
## 1本のコース（仕様書 7章）。CourseCatalog のレシピから実行時に組み立てる（読み込み画面なしで数百ms）。
## 子: Atmosphere（空・霧・太陽）、Geometry（屋上と小物）、GrabLines（スイングバー・ジップライン）、Backdrop（遠景）、
## CourseTimer、Checkpoint、Player、ShortcutHint（金メダルの後、まだ見つけていない近道の入口に出す目印）

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHECKPOINT_SIZE := Vector3(16, 8, 2)

## 次に開くコース（メニューが入れる。空ならシーンの course_id）
static var pending_id: String = ""

@export var course_id: String = "1-1"

var def: Dictionary
var area: Dictionary
var builder: CourseBuilder
var player: Player
var timer: CourseTimer
var free_run: bool = false
var build_ms: int = 0
## 焼いた光がこのコースの形に合っているか（false = 焼き直していない。コーステストが落とす）
var lightmap_ok: bool = false
var pause_menu: PauseMenu
var results: ResultsPanel
var replay: ReplayViewer
## 近道の目印（金メダルを取ったら、まだ見つけていない近道を1つだけ示す）
var _hint: LevelGeometry
var hint_shortcut: String = ""


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	if pending_id != "":
		course_id = pending_id
	def = CourseCatalog.get_course(course_id)
	area = CourseCatalog.area_of(course_id)
	free_run = course_id == CourseCatalog.FREE_RUN
	if area.has("accent"):
		LevelStyle.set_accent(area.accent)

	var geo := LevelGeometry.new()
	geo.name = "Geometry"
	builder = CourseBuilder.new(geo, area, int(def.get("seed", 1)))
	if free_run:
		builder.build_district()
	else:
		builder.build(CourseCatalog.recipe(course_id))
	geo.build()
	add_child(geo)
	lightmap_ok = LevelLighting.apply(geo, course_id)
	if bool(area.get("lit", false)):
		_spawn_lights(geo.lights, LevelStyle.night_amount_for(area.time))
	var grabs := GrabLines.new()
	grabs.name = "GrabLines"
	grabs.lines = builder.grab_lines
	add_child(grabs)

	var atmo := Atmosphere.new()
	atmo.name = "Atmosphere"
	atmo.preset = area.time
	atmo.fog_floor = builder.min_floor_y - 6.0
	add_child(atmo)

	var backdrop := Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	backdrop.build(builder.route_points, CourseBuilder.STREET_Y, builder.start_xf.origin.y, int(def.get("seed", 1)))

	for i: int in builder.checkpoints.size():
		var cp := Checkpoint.new()
		cp.name = "Checkpoint%d" % (i + 1)
		cp.transform = builder.checkpoints[i]
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = CHECKPOINT_SIZE
		cs.shape = box
		cs.position = Vector3(0, CHECKPOINT_SIZE.y * 0.5 - 1.0, 0)
		cp.add_child(cs)
		add_child(cp)

	if not free_run:
		timer = CourseTimer.create(course_id, PackedFloat32Array(def.get("medals", [])), builder.start_xf, builder.goal_xf, builder.splits)
		add_child(timer)
		timer.set_shortcuts(builder.shortcuts)
		timer.shortcut_found.connect(func(sc_name: String, _found: int, _total: int) -> void:
			if sc_name == hint_shortcut:
				update_shortcut_hint())
		update_shortcut_hint()

	player = PLAYER_SCENE.instantiate() as Player
	player.transform = builder.start_xf
	add_child(player)
	player.kill_y = builder.min_floor_y - 10.0
	if free_run:
		# フリーランは最後に立っていた屋上へ戻す
		var keep := Timer.new()
		keep.wait_time = 0.5
		keep.autostart = true
		keep.timeout.connect(_remember_footing)
		add_child(keep)
	_build_menus()
	build_ms = Time.get_ticks_msec() - t0
	print("course %s: %d primitives, %d backdrop buildings, route %.0f m, built in %d ms" % [
			course_id, geo.primitive_count, backdrop.building_count, builder.route_len, build_ms])


## 街灯・ネオン・看板の灯り（夕方・夜）。Mobile レンダラーは1つのメッシュに灯り8つまでなので、
## LevelGeometry の区画（40 m）ごとに MAX_LIGHTS_PER_CHUNK までに抑える。影は落とさない（重い）
const MAX_LIGHTS_PER_CHUNK := 5


func _spawn_lights(list: Array[Dictionary], night_k: float) -> void:
	var per_chunk: Dictionary[Vector2i, int] = {}
	var k := lerpf(0.45, 1.0, clampf((night_k - 0.3) / 0.7, 0.0, 1.0))
	for l: Dictionary in list:
		var pos: Vector3 = l.pos
		var c := Vector2i(floori(pos.x / LevelGeometry.CHUNK), floori(pos.z / LevelGeometry.CHUNK))
		if per_chunk.get(c, 0) >= MAX_LIGHTS_PER_CHUNK:
			continue
		per_chunk[c] = per_chunk.get(c, 0) + 1
		var light: Light3D
		if l.down:
			var sp := SpotLight3D.new()
			sp.spot_range = l.range
			sp.spot_angle = 58.0
			sp.spot_attenuation = 0.8
			sp.rotation_degrees = Vector3(-90, 0, 0)
			light = sp
		else:
			var om := OmniLight3D.new()
			om.omni_range = l.range
			om.omni_attenuation = 1.4
			light = om
		light.position = pos
		light.light_color = l.color
		light.light_energy = float(l.energy) * k
		light.light_specular = 0.6
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 70.0
		light.distance_fade_length = 20.0
		add_child(light)


## フリーラン：屋上に立っている間、落ちた時の戻り先をそこにする
func _remember_footing() -> void:
	if player.state == Player.State.GROUND and player.is_on_floor() and player.horizontal_speed() < player.params.run_speed * 1.5:
		player.checkpoint = Transform3D(Basis(Vector3.UP, player.rig.yaw), player.global_position)


## 近道の目印：自己ベストがゴールド以上で、まだ見つけていない近道があれば、その入口に光る菱形と細い光の柱を出す。
## 1つ見つけたら次へ移る（全部の答えは見せない）。Neon White は金メダルの後に近道の場所を示す
func update_shortcut_hint() -> void:
	if _hint != null:
		_hint.queue_free()
		_hint = null
	hint_shortcut = ""
	if timer == null or builder.shortcuts.is_empty():
		return
	var medals: Array = def.get("medals", [])
	if medals.size() < 2 or timer.best_time() > float(medals[1]):
		return
	for sc: Dictionary in builder.shortcuts:
		if timer.is_shortcut_found(sc.name):
			continue
		hint_shortcut = sc.name
		var p: Vector3 = sc.hint
		var gold := Color(1.0, 0.82, 0.35)
		var flags := LevelGeometry.NO_COLLIDE | LevelGeometry.NO_SHADOW
		_hint = LevelGeometry.new()
		_hint.name = "ShortcutHint"
		_hint.add_box(p + Vector3.UP * 0.4, Vector3(0.3, 0.3, 0.3), LevelStyle.Mat.LIGHT, Vector3(45.0, 0.0, 45.0), flags, gold)
		_hint.add_box(p + Vector3.UP * 3.4, Vector3(0.05, 5.0, 0.05), LevelStyle.Mat.LIGHT, Vector3.ZERO, flags, gold * 0.6)
		_hint.build()
		add_child(_hint)
		return


# --- 一時停止・結果・リプレイ ---------------------------------------------------------

func _build_menus() -> void:
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.retry_requested.connect(restart)
	pause_menu.checkpoint_requested.connect(func() -> void: player.respawn(player.checkpoint))
	pause_menu.quit_requested.connect(func() -> void: Game.to_title(true))
	replay = ReplayViewer.new()
	add_child(replay)
	replay.closed.connect(_on_replay_closed)
	if timer != null:
		results = ResultsPanel.new()
		add_child(results)
		results.retry_requested.connect(restart)
		results.next_requested.connect(func() -> void: Game.play(CourseCatalog.next_id(course_id)))
		results.replay_requested.connect(_start_replay)
		results.courses_requested.connect(func() -> void: Game.to_title(true))
		timer.finished.connect(_on_finished)


## ゴール：入力を止めて結果を出す（体は惰性で少し進んで止まる）
func _on_finished(r: Dictionary) -> void:
	update_shortcut_hint()  # 初めて金メダルを取ったら、リトライからもう目印が出る
	player.input_enabled = false
	player.rig.mouse_capture_enabled = false
	pause_menu.enabled = false
	results.show_result(r, CourseCatalog.next_id(course_id) != "")


## スタートからやり直す（読み込みなし。仕様書 5章「即リトライ」）
func restart() -> void:
	if results != null:
		results.hide_result()
	_set_player_active(true)
	player.input_enabled = true
	player.rig.mouse_capture_enabled = true
	pause_menu.enabled = true
	player.respawn()
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _start_replay() -> void:
	if timer.last_run == null or timer.last_run.size() == 0:
		return
	results.hide_result()
	_set_player_active(false)
	replay.play(timer.last_run)


func _on_replay_closed() -> void:
	_set_player_active(true)
	player.rig.camera.current = true
	results.show_result(timer.last_result, CourseCatalog.next_id(course_id) != "")


## リプレイ中は自分を止めて隠す（カメラ・手足・画面の演出・音）
func _set_player_active(on: bool) -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	player.visible = on
	(player.get_node("FlowHUD") as CanvasLayer).visible = on
	(player.get_node("Body") as Node3D).visible = on and Settings.feel_body
	if timer != null:
		timer.set_physics_process(on)
