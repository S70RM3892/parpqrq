extends CanvasLayer
## 性能計測オーバーレイ。M0ゲート「中価格帯Android実機で空シーン60fps」の判定に使う。
## エディタのプロファイラはPCの性能を映すので、判定は必ず実機でこの表示を見る。
## F3 / コントローラーのBack(Select)で表示切替。

const WINDOW_SEC := 5.0
const BUDGET_MS := 1000.0 / 60.0
const SLACK_MS := 1.0  ## vsyncの揺れを許す幅

var _frame_ms: PackedFloat32Array = []
var _window_sum := 0.0

@onready var _label: Label = $Label


func _ready() -> void:
	layer = 100
	visible = OS.is_debug_build()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		visible = not visible


func _process(delta: float) -> void:
	_record(delta)
	if not visible:
		return
	var over := 0
	var worst := 0.0
	var total := 0.0
	for ms: float in _frame_ms:
		total += ms
		worst = maxf(worst, ms)
		if ms > BUDGET_MS + SLACK_MS:
			over += 1
	var avg := total / maxf(1.0, _frame_ms.size())
	var lines: PackedStringArray = [
		"FPS %d  (cap %d)" % [Engine.get_frames_per_second(), Engine.max_fps],
		"frame avg %.2f ms  worst %.2f ms  (last %.0fs)" % [avg, worst, WINDOW_SEC],
		"frames over %.1f ms: %d" % [BUDGET_MS + SLACK_MS, over],
		"cpu process %.2f ms  physics %.2f ms" % [
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		"draw calls %d  scale %.2f" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			get_viewport().scaling_3d_scale],
		"%s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()],
	]
	var p := get_tree().get_first_node_in_group(&"player") as Player
	if p != null:
		lines.append("speed %.2f m/s  floor %s" % [p.horizontal_speed(), p.is_on_floor()])
	lines.append("GATE 60fps: %s" % ("PASS" if over == 0 and _frame_ms.size() > 60 else "FAIL"))
	_label.text = "\n".join(lines)


func _record(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	_window_sum += delta
	while _window_sum > WINDOW_SEC and _frame_ms.size() > 1:
		_window_sum -= _frame_ms[0] / 1000.0
		_frame_ms.remove_at(0)
