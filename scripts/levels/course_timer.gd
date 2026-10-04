class_name CourseTimer
extends Node3D
## スタートからゴールまでの計測（M1ゲート「同じ白箱コースを10回走っても気持ちいい」用）。
## スタート範囲を出た瞬間に計測開始、ゴール範囲に入ったら停止。リトライで計り直し。
## 走行中は何も出さず、ゴールした時だけタイムと自己ベストを出す（仕様書 8章）。

const BEST_PATH := "user://best_times.cfg"
const SHOW_SEC := 3.0

@export var course_id: String = "test_course"

var _running: bool = false
var _elapsed: float = 0.0
var _best: float = INF
var _shown: float = 0.0

@onready var _label: Label = $HUD/Time


func _ready() -> void:
	($StartArea as Area3D).body_exited.connect(_on_start_exited)
	($GoalArea as Area3D).body_entered.connect(_on_goal_entered)
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) == OK:
		_best = cfg.get_value("best", course_id, INF)
	_label.text = ""


func _process(delta: float) -> void:
	if _shown > 0.0:
		_shown -= delta
		if _shown <= 0.0:
			_label.text = ""


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"retry"):
		_running = false
	elif _running:
		_elapsed += delta


func _on_start_exited(body: Node3D) -> void:
	if body is Player:
		_running = true
		_elapsed = 0.0


func _on_goal_entered(body: Node3D) -> void:
	if not body is Player or not _running:
		return
	var t := _elapsed
	_running = false
	var diff := "" if _best == INF else "  (%+.2f)" % (t - _best)
	if t < _best:
		_best = t
		var cfg := ConfigFile.new()
		cfg.load(BEST_PATH)
		cfg.set_value("best", course_id, _best)
		cfg.save(BEST_PATH)
	_label.text = "%.2f%s\nBEST %.2f" % [t, diff, _best]
	_label.modulate = Color(0.4, 1.0, 0.5) if diff == "" or t <= _best else Color(1.0, 0.45, 0.4)
	_shown = SHOW_SEC
