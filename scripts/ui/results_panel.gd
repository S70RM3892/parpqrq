class_name ResultsPanel
extends CanvasLayer
## ゴールの結果（仕様書 5・8章：数字は止まった時だけ出す）。
## タイム・自己ベストとの差・メダル・次のメダルまで・最高速度・Perfect数。
## Y / R（リトライ）か「Retry」ですぐ走り直せる（A でも Retry にフォーカスがある）。

signal retry_requested
signal next_requested
signal replay_requested
signal courses_requested

var _root: Control
var _time: Label
var _detail: Label
var _medal: MedalIcon
var _medal_name: Label
var _retry: Button
var _next: Button
## 出てからの時間（ゴールの瞬間に押していたボタンで誤って選ばないよう、0.3秒は受け付けない）
var _guard: float = 0.0


func _ready() -> void:
	layer = 70
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 110)
	margin.add_theme_constant_override(&"margin_top", 120)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 34)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	v.custom_minimum_size.x = 640
	m.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 18)
	_medal = MedalIcon.new()
	_medal.custom_minimum_size = Vector2(84, 84)
	top.add_child(_medal)
	var tv := VBoxContainer.new()
	_time = UITheme.label("", 72)
	_medal_name = UITheme.label("", 28, UITheme.MUTED)
	tv.add_child(_time)
	tv.add_child(_medal_name)
	top.add_child(tv)
	v.add_child(top)
	_detail = UITheme.label("", 28, UITheme.INK)
	v.add_child(_detail)
	_retry = UITheme.button("Retry  (Y / R)", func() -> void: retry_requested.emit())
	v.add_child(_retry)
	_next = UITheme.button("Next course", func() -> void: next_requested.emit())
	v.add_child(_next)
	v.add_child(UITheme.button("Replay", func() -> void: replay_requested.emit()))
	v.add_child(UITheme.button("Courses", func() -> void: courses_requested.emit()))
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func show_result(r: Dictionary, has_next: bool) -> void:
	var t: float = r.time
	_time.text = UITheme.format_time(t)
	var medal: String = r.medal
	_medal.medal = medal
	_medal.route_off = r.route_off
	var head := medal if medal != "" else "no medal"
	if r.new_best:
		head += "   NEW BEST" + ("" if (r.prev_best as float) >= INF else "  (%+.2f)" % (t - (r.prev_best as float)))
	else:
		head += "   best %s  (%+.2f)" % [UITheme.format_time(r.best), t - (r.best as float)]
	_medal_name.text = head
	var lines: PackedStringArray = []
	lines.append("Top speed %.1f m/s     Perfect x%d" % [r.max_speed, r.perfects])
	if r.next_medal != "":
		lines.append("Next: %s %s  (-%.2f s)" % [r.next_medal, UITheme.format_time(r.next_time), t - (r.next_time as float)])
	if r.route_off:
		lines.append("Cleared with route color off")
	_detail.text = "\n".join(lines)
	_next.visible = has_next
	_root.visible = true
	_guard = 0.3
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_retry.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if _guard <= 0.0:
		return
	_guard = maxf(_guard - delta, 0.0)
	# 出たばかりの間はボタンも押せないようにする
	for b: Node in _retry.get_parent().get_children():
		if b is Button:
			(b as Button).disabled = _guard > 0.0


func hide_result() -> void:
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if _guard > 0.0:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"retry"):
		get_viewport().set_input_as_handled()
		retry_requested.emit()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		courses_requested.emit()
