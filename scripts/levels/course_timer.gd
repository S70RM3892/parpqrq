class_name CourseTimer
extends Node3D
## スタートからゴールまでの計測と、上達が見える仕組み（仕様書 5章「自己ベストとの競争」）。
## - スタート範囲を出た瞬間に計測開始、ゴール範囲に入ったら停止。スタートへ戻ったら計り直し
## - 区間（Split1, Split2…）を通るたびに、自己ベストの区間タイムとの差を1.5秒だけ出す（緑＝速い、赤＝遅い）
## - ゴールでタイム・差・メダル・次のメダルまで・最高速度・Perfect数（finished シグナル。白箱コースは上の表示にも出す）
## - 自己ベストの走りをゴースト（半透明の自分）として次のプレイに出す。走りは全部記録してリプレイに使う
## - ルートカラーOFFでクリアしたら印を残す（仕様書 6章）
## - 隠れた近道を通ったら「発見」として残す（Neon White の近道探しにならう）。初めて通った時だけ上に1.5秒出す
## 走行中はそれ以外何も出さない（仕様書 8章）。

signal started
signal split_passed(index: int, time: float, diff: float)
signal finished(result: Dictionary)
## 隠れた近道を初めて通った。found = これまでに見つけた数
signal shortcut_found(shortcut_name: String, found: int, total: int)

const SAVE_PATH := "user://best_times.cfg"
const SPLIT_SHOW := 1.5
const RESULT_SHOW := 6.0
## メダルは速い順（Neon White の開発者・エース・ゴールド・シルバー・ブロンズにならう）。基準タイムも同じ並び
const MEDALS: PackedStringArray = ["DEV", "ACE", "GOLD", "SILVER", "BRONZE"]
## 近道の目印が出る条件：自己ベストがシルバー以内（MEDALS の番号）、または同じコースを HINT_FINISHES 回ゴールした
const SILVER_INDEX := 3
const HINT_FINISHES := 5
const GREEN := Color(0.4, 1.0, 0.5)
const GOLD := Color(1.0, 0.85, 0.35)
const RED := Color(1.0, 0.45, 0.4)

@export var course_id: String = "test_course"
## メダルの基準タイム（秒）。開発者・エース・ゴールド・シルバー・ブロンズの順
@export var medal_times: PackedFloat32Array = [15.5, 16.5, 17.0, 20.0, 25.0]  # 自動走行（Perfect 8回）で16.2秒
## true = ゴールの結果を上の表示に出す（白箱コース。生成コースは結果画面が出す）
@export var show_result_label: bool = true

var running: bool = false
var elapsed: float = 0.0
## ゴールした時の結果（テストからも読む）
var last_result: Dictionary = {}
## 今の走り（ゴールしたらリプレイに使える）と、自己ベストの走り（ゴースト）
var recording := RunRecording.new()
var last_run: RunRecording
var best_run := RunRecording.new()

var _best: float = INF
## このコースをゴールした回数（保存する。近道の目印の条件）
var _finishes: int = 0
var _best_splits: PackedFloat32Array = []
var _splits: PackedFloat32Array = []
var _shown: float = 0.0
var _max_speed: float = 0.0
var _perfects_at_start: int = 0
var _player: Player
var _ghost_body: GhostBody
## 隠れた近道（Course が渡す：CourseBuilder.shortcuts）。{name, found_xf, found_size, found_states（状態の名前）, ...}
var shortcuts: Array[Dictionary] = []
## これまでに見つけた近道の名前（保存する）／この走りで通った近道／この走りで初めて見つけた近道
var _found: Dictionary = {}
var _found_run: Dictionary = {}
var _new_run: int = 0
## 1つ目の箱を通った近道（2つ目の箱がある近道で、この走りの間だけ。戻されたら消す）
var _stage: Dictionary = {}

@onready var _label: Label = $HUD/Time
@onready var _ghost: Node3D = $Ghost


## 実行時に組むコース用：スタート・ゴール・区間の範囲とゴースト・表示を子に作った計測を返す（シーンで作る時と同じ形）
static func create(id: String, medals: PackedFloat32Array, start: Transform3D, goal: Transform3D,
		splits: Array[Transform3D]) -> CourseTimer:
	var t := CourseTimer.new()
	t.name = "CourseTimer"
	t.course_id = id
	t.medal_times = medals
	t.show_result_label = false
	t.add_child(_area("StartArea", start, Vector3(8, 6, 10)))
	t.add_child(_area("GoalArea", goal, Vector3(12, 12, 3)))
	for i: int in splits.size():
		t.add_child(_area("Split%d" % (i + 1), splits[i], Vector3(18, 40, 1.5)))
	var ghost := Node3D.new()
	ghost.name = "Ghost"
	t.add_child(ghost)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	var label := Label.new()
	label.name = "Time"
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -400.0
	label.offset_right = 400.0
	label.offset_top = 40.0
	label.offset_bottom = 200.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 8)
	label.add_theme_font_size_override(&"font_size", 48)
	hud.add_child(label)
	t.add_child(hud)
	return t


static func _area(area_name: String, xf: Transform3D, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = area_name
	a.transform = xf.translated_local(Vector3(0, size.y * 0.5 - 1.0, 0))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	a.add_child(cs)
	return a


static func medal_for(t: float, times: PackedFloat32Array) -> String:
	for i: int in times.size():
		if times[i] > 0.0 and t <= times[i]:
			return MEDALS[i]
	return ""


## 近道の目印を出すか：自己ベストがシルバー以内、または同じコースを HINT_FINISHES 回ゴールした
static func hint_for(best: float, times: PackedFloat32Array, finishes: int) -> bool:
	if finishes >= HINT_FINISHES:
		return true
	return times.size() > SILVER_INDEX and times[SILVER_INDEX] > 0.0 and best <= times[SILVER_INDEX]


## 保存してあるゴールした回数（持ち主の記録は id ごと。テストは "test_<id>" などの別のIDで取る）
static func finish_count(id: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("finishes", id, 0))


func _ready() -> void:
	($StartArea as Area3D).body_exited.connect(_on_start_exited)
	($GoalArea as Area3D).body_entered.connect(_on_goal_entered)
	var splits := _split_areas()
	for i: int in splits.size():
		var idx := i
		splits[i].body_entered.connect(func(body: Node3D) -> void: _on_split(body, idx))
	_load()
	_label.text = ""
	_ghost.top_level = true
	_ghost_body = GhostBody.new()
	_ghost.add_child(_ghost_body)
	_ghost.visible = false
	_bind_player.call_deferred()


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player != null:
		_player.respawned.connect(_on_respawned)


func _process(delta: float) -> void:
	if _shown > 0.0:
		_shown -= delta
		if _shown <= 0.0:
			_label.text = ""


func _physics_process(delta: float) -> void:
	if not running:
		return
	if _player != null and not shortcuts.is_empty() and Engine.get_physics_frames() % 2 == 0:
		_check_shortcuts()
	elapsed += delta
	if _player != null:
		_max_speed = maxf(_max_speed, _player.horizontal_speed())
		recording.add(_player)
	_update_ghost(delta)


## スタートへ戻ったら計り直し（スタート範囲を出た瞬間にまた始まる）。チェックポイントへ戻った時は計測を続ける
func _on_respawned(to_start: bool) -> void:
	_stage.clear()
	if to_start:
		running = false
		_ghost.visible = false
		_found_run.clear()
		_new_run = 0


func _on_start_exited(body: Node3D) -> void:
	if not body is Player:
		return
	_player = body
	running = true
	elapsed = 0.0
	_max_speed = 0.0
	_perfects_at_start = _player.perfect_count
	_splits = []
	_found_run.clear()
	_stage.clear()
	_new_run = 0
	recording.clear()
	_ghost.visible = best_run.size() > 0
	started.emit()


func _on_split(body: Node3D, idx: int) -> void:
	if not body is Player or not running or idx != _splits.size():
		return
	_splits.append(elapsed)
	var diff := NAN
	if idx < _best_splits.size():
		diff = elapsed - _best_splits[idx]
		_show("%.2f  (%+.2f)" % [elapsed, diff], GREEN if diff <= 0.0 else RED, SPLIT_SHOW)
	split_passed.emit(idx, elapsed, diff)
	Audio.ui(&"split", 1.0 if is_nan(diff) or diff <= 0.0 else 0.8)


func _on_goal_entered(body: Node3D) -> void:
	if not body is Player or not running:
		return
	running = false
	_ghost.visible = false
	var t := elapsed
	var prev := _best
	var had_best := _best < INF
	var diff := t - _best
	var medal := _medal_for(t)
	var perfects := _player.perfect_count - _perfects_at_start
	count_finish()
	last_run = recording.duplicate_run()
	var new_best := t < _best
	if new_best:
		_best = t
		_best_splits = _splits.duplicate()
		best_run = last_run
	var route_off := not Settings.route_color
	_save(new_best, route_off)
	var next := _next_medal(t)
	last_result = {
		"time": t, "medal": medal, "max_speed": _max_speed, "perfects": perfects, "best": _best,
		"prev_best": prev, "new_best": new_best, "route_off": route_off,
		"next_medal": next.get("medal", ""), "next_time": next.get("time", 0.0),
		"shortcuts_total": shortcuts.size(), "shortcuts_found": _found.size(),
		"shortcuts_used": _found_run.size(), "new_shortcuts": _new_run,
		"hint_on": medal_times.size() > 1 and _best <= medal_times[1] and _found.size() < shortcuts.size(),
	}
	if show_result_label:
		var lines: PackedStringArray = []
		lines.append("%.2f%s   %s" % [t, ("  (%+.2f)" % diff) if had_best else "", medal if medal != "" else "-"])
		lines.append("BEST %.2f   TOP %.1f m/s   PERFECT x%d" % [_best, _max_speed, perfects])
		if next.has("medal"):
			lines.append("NEXT %s %.2f  (-%.2f)" % [next.medal, next.time, t - (next.time as float)])
		_show("\n".join(lines), GREEN if not had_best or diff <= 0.0 else RED, RESULT_SHOW)
	Audio.ui(&"goal")
	finished.emit(last_result)


## 記録を別のIDで取り直す（スモークテストが持ち主の自己ベストを上書きしない）
func use_records(id: String, clear: bool) -> void:
	course_id = id
	_best = INF
	_best_splits = []
	best_run = RunRecording.new()
	if clear:
		var cfg := ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			for section: String in ["best", "splits", "route_off", "shortcuts", "finishes"]:
				if cfg.has_section_key(section, id):
					cfg.erase_section_key(section, id)
			cfg.save(SAVE_PATH)
		if FileAccess.file_exists(_ghost_path()):
			DirAccess.remove_absolute(_ghost_path())
	_load()


## ゴールした回数を1つ増やして保存する（ゴールのたびに呼ぶ）
func count_finish() -> void:
	_finishes += 1
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("finishes", course_id, _finishes)
	cfg.save(SAVE_PATH)


## 今の自己ベストとゴールした回数で、近道の目印を出すか
func hint_unlocked() -> bool:
	return hint_for(_best, medal_times, _finishes)


## 隠れた近道を渡す（発見の判定に使う）
func set_shortcuts(list: Array[Dictionary]) -> void:
	shortcuts = list


## これまでに見つけた近道の数
func shortcuts_found() -> int:
	return _found.size()


func is_shortcut_found(shortcut_name: String) -> bool:
	return _found.has(shortcut_name)


## 見つけた近道の名前（保存してある分）
static func found_shortcuts(id: String) -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return PackedStringArray()
	return cfg.get_value("shortcuts", id, PackedStringArray())


## 近道の判定の箱に体の中心が入っていて、状態も合っていれば「通った」
func _check_shortcuts() -> void:
	var center := _player.global_position + Vector3.UP * 0.9
	for sc: Dictionary in shortcuts:
		var sc_name: String = sc.name
		if _found_run.has(sc_name):
			continue
		var then_size: Vector3 = sc.get("then_size", Vector3.ZERO)
		if _stage.has(sc_name):
			if not _inside(center, sc.then_xf, then_size):
				continue
		else:
			var states: Array = sc.get("found_states", [])
			if not states.is_empty() and not states.has(Player.State.find_key(_player.state)):
				continue
			if not _inside(center, sc.found_xf, sc.found_size):
				continue
			if then_size != Vector3.ZERO:
				_stage[sc_name] = true  # 2つ目の箱を待つ
				continue
		_found_run[sc_name] = true
		if _found.has(sc_name):
			continue
		_found[sc_name] = true
		_new_run += 1
		_save_found()
		_show("SHORTCUT FOUND  %d / %d" % [_found.size(), shortcuts.size()], GOLD, SPLIT_SHOW)
		Audio.ui(&"split", 1.25)
		shortcut_found.emit(sc_name, _found.size(), shortcuts.size())


static func _inside(p: Vector3, xf: Transform3D, size: Vector3) -> bool:
	var local := xf.affine_inverse() * p
	var half := size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


func _save_found() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("shortcuts", course_id, PackedStringArray(_found.keys()))
	cfg.save(SAVE_PATH)


func ghost_samples() -> int:
	return best_run.size()


func best_time() -> float:
	return _best


func _medal_for(t: float) -> String:
	return medal_for(t, medal_times)


## 次に取れるメダルとその基準タイム（全部取っていれば空）
func _next_medal(t: float) -> Dictionary:
	for i: int in range(medal_times.size() - 1, -1, -1):
		if medal_times[i] > 0.0 and t > medal_times[i]:
			return {"medal": MEDALS[i], "time": medal_times[i]}
	return {}


func _show(text: String, color: Color, time: float) -> void:
	_label.text = text
	_label.modulate = color
	_shown = time


func _update_ghost(delta: float) -> void:
	if best_run.size() == 0:
		return
	var i := mini(recording.size() - 1, best_run.size() - 1)
	if i < 0:
		return
	_ghost_body.show_frame(best_run.sample(i), delta)


func _split_areas() -> Array[Area3D]:
	var out: Array[Area3D] = []
	for c: Node in get_children():
		if c is Area3D and c.name.begins_with("Split"):
			out.append(c)
	out.sort_custom(func(a: Area3D, b: Area3D) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


func _ghost_path() -> String:
	return "user://ghost_%s.dat" % course_id


func _load() -> void:
	var cfg := ConfigFile.new()
	_found.clear()
	_finishes = 0
	if cfg.load(SAVE_PATH) == OK:
		_best = cfg.get_value("best", course_id, INF)
		_finishes = int(cfg.get_value("finishes", course_id, 0))
		_best_splits = cfg.get_value("splits", course_id, PackedFloat32Array())
		for n: String in cfg.get_value("shortcuts", course_id, PackedStringArray()):
			_found[n] = true
	if FileAccess.file_exists(_ghost_path()):
		var f := FileAccess.open(_ghost_path(), FileAccess.READ)
		var data: Variant = f.get_var()
		if data is Dictionary:
			best_run = RunRecording.from_dict(data)


func _save(new_best: bool, route_off: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	if new_best:
		cfg.set_value("best", course_id, _best)
		cfg.set_value("splits", course_id, _best_splits)
	if route_off:
		cfg.set_value("route_off", course_id, true)
	cfg.save(SAVE_PATH)
	if new_best:
		var f := FileAccess.open(_ghost_path(), FileAccess.WRITE)
		f.store_var(best_run.to_dict())
