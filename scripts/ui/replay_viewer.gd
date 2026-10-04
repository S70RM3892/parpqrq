class_name ReplayViewer
extends Node3D
## リプレイ（仕様書 7章「ゲームモード」：自分の走りを1人称／追従3人称で見返せる。3人称はリプレイ専用）。
## 1人称はカメラの位置と向きを記録どおりに再生する。3人称は体の斜め後ろから滑らかに追う。
## A：視点の切り替え　左右：速さ（0.25〜2倍）　B：終わる

signal closed

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0]

var _run: RunRecording
var _frame: float = 0.0
var _speed_i: int = 2
var _third: bool = false
var _cam: Camera3D
var _body: GhostBody
var _hud: CanvasLayer
var _label: Label
var _cam_pos: Vector3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cam = Camera3D.new()
	_cam.near = 0.03
	_cam.far = 400.0
	add_child(_cam)
	_body = GhostBody.new()
	_body.far_arrow = false
	_body.color = Color(1.0, 0.45, 0.15, 0.85)
	_body.top_level = true
	add_child(_body)
	_hud = CanvasLayer.new()
	_hud.layer = 60
	add_child(_hud)
	_label = UITheme.label("", 28, Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 8)
	_label.position = Vector2(60, 40)
	_hud.add_child(_label)
	visible = false
	_hud.visible = false
	set_process(false)


func play(run: RunRecording) -> void:
	_run = run
	_frame = 0.0
	visible = true
	_hud.visible = true
	_body.visible = _third
	_cam.current = true
	set_process(true)
	var s := _run.sample(0.0)
	_cam_pos = (s.pos as Vector3) + Vector3(0, 3, 4)


func stop() -> void:
	visible = false
	_hud.visible = false
	set_process(false)
	_cam.current = false
	closed.emit()


func _process(delta: float) -> void:
	if _run == null or _run.size() == 0:
		return
	_frame = minf(_frame + delta * 60.0 * SPEEDS[_speed_i], _run.size() - 1.0)
	var s := _run.sample(_frame)
	_body.show_frame(s, delta * SPEEDS[_speed_i])
	_body.visible = _third
	if _third or not s.has("eye"):
		var target: Vector3 = (s.pos as Vector3) + Vector3.UP * 1.2
		var back := Basis(Vector3.UP, s.yaw) * Vector3.BACK
		var want := target + back * 4.2 + Vector3.UP * 1.4
		_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-5.0 * delta))
		_cam.global_position = _cam_pos
		_cam.look_at(target, Vector3.UP)
		_cam.fov = 75.0
	else:
		_cam.global_transform = Transform3D(Basis(s.rot as Quaternion), s.eye)
		_cam.fov = s.fov
		_cam_pos = _cam.global_position
	var t := _frame / 60.0
	var end := _frame >= _run.size() - 1.0
	_label.text = "REPLAY  %s / %s   x%s   %s\nA: %s view   left / right: speed   B: back%s" % [
			UITheme.format_time(t), UITheme.format_time(_run.size() / 60.0), str(SPEEDS[_speed_i]),
			"3rd person" if _third else "1st person", "1st" if _third else "3rd", "   (end, A: again)" if end else ""]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"jump"):
		get_viewport().set_input_as_handled()
		if _frame >= _run.size() - 1.0:
			_frame = 0.0
		else:
			_third = not _third
	elif event.is_action_pressed(&"ui_right"):
		_speed_i = mini(_speed_i + 1, SPEEDS.size() - 1)
	elif event.is_action_pressed(&"ui_left"):
		_speed_i = maxi(_speed_i - 1, 0)
	elif event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		Audio.ui(&"ui_back")
		stop()
