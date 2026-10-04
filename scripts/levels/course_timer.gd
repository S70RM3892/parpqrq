class_name CourseTimer
extends Node3D
## スタートからゴールまでの計測と、上達が見える仕組み（仕様書 5章「自己ベストとの競争」）。
## - スタート範囲を出た瞬間に計測開始、ゴール範囲に入ったら停止。リトライで計り直し
## - 区間（Split1, Split2…）を通るたびに、自己ベストの区間タイムとの差を1.5秒だけ出す（緑＝速い、赤＝遅い）
## - ゴールでタイム・差・メダル・次のメダルまで・最高速度・Perfect数を出す
## - 自己ベストの走りをゴースト（半透明の自分）として次のプレイに出す
## 走行中はそれ以外何も出さない（仕様書 8章）。

const SAVE_PATH := "user://best_times.cfg"
const SPLIT_SHOW := 1.5
const RESULT_SHOW := 6.0
const MEDALS: PackedStringArray = ["DEV", "GOLD", "SILVER", "BRONZE"]
const GREEN := Color(0.4, 1.0, 0.5)
const RED := Color(1.0, 0.45, 0.4)

@export var course_id: String = "test_course"
## メダルの基準タイム（秒）。開発者・ゴールド・シルバー・ブロンズの順
@export var medal_times: PackedFloat32Array = [15.5, 17.0, 20.0, 25.0]  # 自動走行（Perfect 8回）で16.2秒

var running: bool = false
var elapsed: float = 0.0
## ゴールした時の結果（テストからも読む）
var last_result: Dictionary = {}

var _best: float = INF
var _best_splits: PackedFloat32Array = []
var _splits: PackedFloat32Array = []
var _shown: float = 0.0
var _max_speed: float = 0.0
var _perfects_at_start: int = 0
var _rec_pos: PackedVector3Array = []
var _rec_yaw: PackedFloat32Array = []
var _ghost_pos: PackedVector3Array = []
var _ghost_yaw: PackedFloat32Array = []
var _player: Player

@onready var _label: Label = $HUD/Time
@onready var _ghost: Node3D = $Ghost


func _ready() -> void:
	($StartArea as Area3D).body_exited.connect(_on_start_exited)
	($GoalArea as Area3D).body_entered.connect(_on_goal_entered)
	var splits := _split_areas()
	for i: int in splits.size():
		var idx := i
		splits[i].body_entered.connect(func(body: Node3D) -> void: _on_split(body, idx))
	_load()
	_label.text = ""
	_ghost.visible = false
	_ghost.top_level = true
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
	elapsed += delta
	if _player != null:
		_max_speed = maxf(_max_speed, _player.horizontal_speed())
		_rec_pos.append(_player.global_position)
		_rec_yaw.append(_player.rig.yaw)
	_update_ghost()


## スタートへ戻ったら計り直し（スタート範囲を出た瞬間にまた始まる）。チェックポイントへ戻った時は計測を続ける
func _on_respawned(to_start: bool) -> void:
	if to_start:
		running = false
		_ghost.visible = false


func _on_start_exited(body: Node3D) -> void:
	if not body is Player:
		return
	_player = body
	running = true
	elapsed = 0.0
	_max_speed = 0.0
	_perfects_at_start = _player.perfect_count
	_splits = []
	_rec_pos = []
	_rec_yaw = []
	_ghost.visible = not _ghost_pos.is_empty()


func _on_split(body: Node3D, idx: int) -> void:
	if not body is Player or not running or idx != _splits.size():
		return
	_splits.append(elapsed)
	if idx < _best_splits.size():
		var diff := elapsed - _best_splits[idx]
		_show("%.2f  (%+.2f)" % [elapsed, diff], GREEN if diff <= 0.0 else RED, SPLIT_SHOW)


func _on_goal_entered(body: Node3D) -> void:
	if not body is Player or not running:
		return
	running = false
	_ghost.visible = false
	var t := elapsed
	var had_best := _best < INF
	var diff := t - _best
	var medal := _medal_for(t)
	var perfects := _player.perfect_count - _perfects_at_start
	if t < _best:
		_best = t
		_best_splits = _splits.duplicate()
		_ghost_pos = _rec_pos.duplicate()
		_ghost_yaw = _rec_yaw.duplicate()
		_save()
	var lines: PackedStringArray = []
	lines.append("%.2f%s   %s" % [t, ("  (%+.2f)" % diff) if had_best else "", medal if medal != "" else "-"])
	lines.append("BEST %.2f   TOP %.1f m/s   PERFECT x%d" % [_best, _max_speed, perfects])
	var next := _next_medal(t)
	if next != "":
		lines.append(next)
	_show("\n".join(lines), GREEN if not had_best or diff <= 0.0 else RED, RESULT_SHOW)
	last_result = {"time": t, "medal": medal, "max_speed": _max_speed, "perfects": perfects, "best": _best}


## 記録を別のIDで取り直す（スモークテストが持ち主の自己ベストを上書きしないように）
func use_records(id: String, clear: bool) -> void:
	course_id = id
	_best = INF
	_best_splits = []
	_ghost_pos = []
	_ghost_yaw = []
	if clear:
		var cfg := ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			for section: String in ["best", "splits"]:
				if cfg.has_section_key(section, id):
					cfg.erase_section_key(section, id)
			cfg.save(SAVE_PATH)
		if FileAccess.file_exists(_ghost_path()):
			DirAccess.remove_absolute(_ghost_path())
	_load()


func ghost_samples() -> int:
	return _ghost_pos.size()


func _medal_for(t: float) -> String:
	for i: int in medal_times.size():
		if t <= medal_times[i]:
			return MEDALS[i]
	return ""


## 次に取れるメダルまであと何秒か
func _next_medal(t: float) -> String:
	for i: int in range(medal_times.size() - 1, -1, -1):
		if t > medal_times[i]:
			return "NEXT %s %.2f  (-%.2f)" % [MEDALS[i], medal_times[i], t - medal_times[i]]
	return ""


func _show(text: String, color: Color, time: float) -> void:
	_label.text = text
	_label.modulate = color
	_shown = time


func _update_ghost() -> void:
	if _ghost_pos.is_empty():
		return
	var i := mini(_rec_pos.size() - 1, _ghost_pos.size() - 1)
	if i < 0:
		return
	_ghost.global_position = _ghost_pos[i]
	_ghost.rotation = Vector3(0.0, _ghost_yaw[i], 0.0)


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
	if cfg.load(SAVE_PATH) == OK:
		_best = cfg.get_value("best", course_id, INF)
		_best_splits = cfg.get_value("splits", course_id, PackedFloat32Array())
	if FileAccess.file_exists(_ghost_path()):
		var f := FileAccess.open(_ghost_path(), FileAccess.READ)
		var data: Variant = f.get_var()
		if data is Dictionary:
			_ghost_pos = data.get("pos", PackedVector3Array())
			_ghost_yaw = data.get("yaw", PackedFloat32Array())


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("best", course_id, _best)
	cfg.set_value("splits", course_id, _best_splits)
	cfg.save(SAVE_PATH)
	var f := FileAccess.open(_ghost_path(), FileAccess.WRITE)
	f.store_var({"pos": _ghost_pos, "yaw": _ghost_yaw})
