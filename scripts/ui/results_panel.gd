class_name ResultsPanel
extends CanvasLayer
## ゴールの結果（仕様書 5・8章：数字は止まった時だけ出す）。
## タイムが数え上がり（0.55 s）→ メダルがスタンプのように押される（0.35 s）。確定・戻る・クリックで演出を飛ばせる。
## リトライ（Y / R）は演出の途中でも1回で効く（飛ばした上でそのまま走り直す）。
## タイム・自己ベストとの差・メダル・次のメダルまで・最高速度・Perfect数・見つけた近道の数。
## Y / R（リトライ）か「Retry」ですぐ走り直せる（A でも Retry にフォーカスがある）。

signal retry_requested
signal next_requested
signal replay_requested
signal courses_requested

const COUNT_TIME := 0.55
const STAMP_TIME := 0.32
const FLASH_TIME := 0.38
const PANEL_WIDTH := 780.0

var _root: Control
var _panel: PanelContainer
var _slide: Control  ## 板の出入りで動かす枠（板自身は容器が置くので動かせない）
var _course_id: Label
var _course_name: Label
var _time: TabularText
var _medal: MedalIcon
var _chips: HBoxContainer
var _medal_name: Label
var _new_pill: PanelContainer
var _diff: Label
var _ladder: MedalLadder
var _next_row: HBoxContainer
var _next_icon: MedalIcon
var _next_label: Label
var _next_gap: Label
var _speed: Label
var _perfect: Label
var _shortcuts: Label
var _hint: Label
var _records: Label
var _retry: Button
var _next: Button
var _buttons: Array[Button] = []
## 出てからの時間（ゴールの瞬間に押していたボタンで誤って選ばないよう、0.3秒は受け付けない）
var _guard: float = 0.0
var _anim: Tween
var _slide_tween: Tween
var _animating: bool = false
var _final_time: float = 0.0
## 最後に出した結果（リプレイから戻った時は演出をやり直さない）
var _last: Dictionary = {}


func _ready() -> void:
	layer = 70
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var inset := UITheme.safe_insets()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", int(maxf(110.0, inset.x + 40.0)))
	margin.add_theme_constant_override(&"margin_top", 40)
	margin.add_theme_constant_override(&"margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	_slide = margin
	_panel = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(_panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 30)
	_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	v.custom_minimum_size.x = PANEL_WIDTH
	m.add_child(v)
	# コース名
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	_course_id = UITheme.heading("", 34, UITheme.ACCENT)
	_course_name = UITheme.heading("", 34)
	head.add_child(_course_id)
	head.add_child(_course_name)
	v.add_child(head)
	v.add_child(UITheme.accent_bar(84, 6))
	# メダル（左）・タイム（右）
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 26)
	_medal = MedalIcon.new()
	_medal.custom_minimum_size = Vector2(150, 150)
	_medal.pivot_offset = Vector2(75, 75)
	top.add_child(_medal)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override(&"separation", 6)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time = TabularText.new("0:00.00", 116, UITheme.INK)
	_time.shadow = true
	tv.add_child(_time)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override(&"separation", 14)
	_medal_name = UITheme.heading("", 32)
	_chips.add_child(_medal_name)
	_new_pill = _pill("NEW BEST")
	_chips.add_child(_new_pill)
	_diff = UITheme.heading("", 30, UITheme.GOOD)
	_chips.add_child(_diff)
	tv.add_child(_chips)
	top.add_child(tv)
	v.add_child(top)
	# 次のメダルまで（目立たせる）とメダルの一覧
	_next_row = HBoxContainer.new()
	_next_row.add_theme_constant_override(&"separation", 12)
	_next_icon = MedalIcon.new()
	_next_icon.custom_minimum_size = Vector2(46, 46)
	_next_row.add_child(_next_icon)
	_next_label = UITheme.heading("", 34)
	_next_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next_row.add_child(_next_label)
	_next_gap = UITheme.heading("", 34, UITheme.ACCENT)
	_next_gap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next_row.add_child(_next_gap)
	v.add_child(_next_row)
	_ladder = MedalLadder.new(46, 22)
	v.add_child(_ladder)
	# 数字
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 54)
	_speed = _stat(stats, "Top speed")
	_perfect = _stat(stats, "Perfect")
	v.add_child(stats)
	_shortcuts = UITheme.heading("", 28)
	v.add_child(_shortcuts)
	_hint = UITheme.label("", 22, UITheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint)
	_records = UITheme.label("", 22, UITheme.INK)
	_records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_records)
	# ボタン：リトライを大きく、続きを選ぶ3つを横に並べる
	_retry = UITheme.button("Retry  (Y / R)", func() -> void: retry_requested.emit(), 36)
	v.add_child(_retry)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_next = UITheme.button("Next course", func() -> void: next_requested.emit(), 28)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_next)
	var replay := UITheme.button("Replay", func() -> void: replay_requested.emit(), 28)
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(replay)
	var courses := UITheme.button("Courses", func() -> void: courses_requested.emit(), 28)
	courses.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(courses)
	v.add_child(row)
	_buttons = [_retry, _next, replay, courses]
	_root.visible = false


## 小さな見出しと大きな数字（最高速度など）。数字の Label を返す
func _stat(parent: Control, caption: String) -> Label:
	var s := VBoxContainer.new()
	s.add_theme_constant_override(&"separation", -6)
	s.add_child(UITheme.heading(caption, 20, UITheme.MUTED))
	var n := UITheme.heading("", 40)
	s.add_child(n)
	parent.add_child(s)
	return n


## オレンジの札（NEW BEST など）
func _pill(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.ACCENT
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override(&"panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(UITheme.heading(text, 28, Color.WHITE))
	return p


func is_open() -> bool:
	return _root.visible


## 数え上げ・スタンプの演出の最中か
func is_animating() -> bool:
	return _animating


func show_result(r: Dictionary, has_next: bool) -> void:
	var t: float = r.time
	var parent := get_parent()
	var cid: String = (parent as Course).course_id if parent is Course else Game.last_course
	var c := CourseCatalog.get_course(cid)
	_course_id.text = cid
	_course_name.text = String(c.get("name", "")).to_upper()
	var medal: String = r.medal
	_medal.medal = medal
	_medal.route_off = r.route_off
	_final_time = t
	# メダルの名前・NEW BEST・差
	_medal_name.text = medal if medal != "" else "NO MEDAL"
	_medal_name.add_theme_color_override(&"font_color", UITheme.INK if medal != "" else UITheme.MUTED)
	var prev_best: float = r.prev_best
	_new_pill.visible = r.new_best
	if r.new_best:
		_diff.visible = prev_best < INF
		_diff.text = "%+.2f s" % (t - prev_best)
		_diff.add_theme_color_override(&"font_color", UITheme.GOOD)
	else:
		_diff.visible = true
		_diff.text = "BEST %s   %+.2f s" % [UITheme.format_time(r.best), t - (r.best as float)]
		_diff.add_theme_color_override(&"font_color", UITheme.MUTED)
	# 次のメダルまで
	if r.next_medal != "":
		_next_row.visible = true
		_next_icon.medal = r.next_medal
		var gap := t - (r.next_time as float)
		_next_label.text = "NEXT  %s" % r.next_medal
		_next_gap.text = "-%.2f s" % gap
	else:
		_next_row.visible = true
		_next_icon.medal = medal
		_next_label.text = "ALL MEDALS CLEARED"
		_next_gap.text = ""
	_ladder.set_times(c.get("medals", []), medal)
	_speed.text = "%.1f m/s" % r.max_speed
	_perfect.text = "x%d" % int(r.perfects)
	# 近道
	var total := int(r.get("shortcuts_total", 0))
	var hint: PackedStringArray = []
	_shortcuts.visible = total > 0
	if total > 0:
		var found := int(r.get("shortcuts_found", 0))
		var sc := "Shortcuts found %d / %d" % [found, total]
		if int(r.get("new_shortcuts", 0)) > 0:
			sc += "   +%d new" % int(r.new_shortcuts)
		elif found < total:
			if bool(r.get("hint_on", false)):
				hint.append("A marker shows the next one.")
			else:
				var left := maxi(CourseTimer.HINT_FINISHES - _finishes(), 0)
				hint.append("Take SILVER, or finish %d more time%s, for a marker." % [left, "" if left == 1 else "s"])
		_shortcuts.text = sc.to_upper()
	if r.route_off:
		hint.append("Cleared with route color off.")
	_hint.text = " ".join(hint)
	_hint.visible = not hint.is_empty()
	# 手元の記録表（エースで開く）
	if bool(r.get("records_open", false)):
		var tops: PackedStringArray = []
		var top: PackedFloat32Array = r.get("top", PackedFloat32Array())
		for i: int in top.size():
			tops.append("%d. %s" % [i + 1, UITheme.format_time(top[i])])
		var sob: float = r.get("sum_best", INF)
		_records.text = "TOP  " + "   ".join(tops) + (("\nSUM OF BEST SPLITS  " + UITheme.format_time(sob)) if sob < INF else "")
		_records.add_theme_color_override(&"font_color", UITheme.INK)
	else:
		_records.text = "Take ACE to open your records table."
		_records.add_theme_color_override(&"font_color", UITheme.MUTED)
	_next.visible = has_next
	var again := is_same(r, _last) or r.hash() == _last.hash()
	_last = r
	_root.visible = true
	if _slide_tween != null:
		_slide_tween.kill()
	_slide_tween = UITheme.slide_in(_slide, -48.0, 0.22)
	_guard = 0.3
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_retry.grab_focus.call_deferred()
	if again:
		_skip()
	else:
		_play(t, medal != "")


## 今までにゴールした回数（近道の目印が出るまでの数え方に使う）
func _finishes() -> int:
	var parent := get_parent()
	if parent is Course and (parent as Course).timer != null:
		return CourseTimer.finish_count((parent as Course).timer.course_id)
	return 0


## 数え上げ → スタンプ
func _play(t: float, has_medal: bool) -> void:
	_kill_anim()
	_animating = true
	_time.text = UITheme.format_time(0.0)
	_medal.flash = 0.0
	_medal.modulate.a = 0.0
	_medal.scale = Vector2(1.6, 1.6)
	_chips.modulate.a = 0.0
	_anim = create_tween().set_ignore_time_scale(true)
	_anim.tween_method(_set_time, 0.0, t, COUNT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim.tween_callback(_stamp.bind(has_medal))


func _set_time(v: float) -> void:
	_time.text = UITheme.format_time(v)


func _stamp(has_medal: bool) -> void:
	_time.text = UITheme.format_time(_final_time)
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	_anim = tw
	if has_medal:
		Audio.ui(&"ui_ok")
		tw.tween_property(_medal, "modulate:a", 1.0, 0.07)
		tw.tween_property(_medal, "scale", Vector2.ONE, STAMP_TIME).from(Vector2(1.6, 1.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_medal, "flash", 1.0, FLASH_TIME).from(0.0)
	else:
		_medal.scale = Vector2.ONE
		tw.tween_property(_medal, "modulate:a", 1.0, 0.2)
	tw.tween_property(_chips, "modulate:a", 1.0, 0.2).set_delay(0.1)
	tw.tween_callback(func() -> void: _animating = false).set_delay(FLASH_TIME)


## 演出を飛ばして最後の姿にする
func _skip() -> void:
	_kill_anim()
	_animating = false
	_time.text = UITheme.format_time(_final_time)
	_medal.flash = 0.0
	_medal.modulate.a = 1.0
	_medal.scale = Vector2.ONE
	_chips.modulate.a = 1.0


func _kill_anim() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()


func _process(delta: float) -> void:
	if _guard <= 0.0:
		return
	_guard = maxf(_guard - delta, 0.0)
	# 出たばかりの間はボタンも押せないようにする
	for b: Button in _buttons:
		b.disabled = _guard > 0.0


func hide_result() -> void:
	_kill_anim()
	_animating = false
	_root.visible = false


## 演出の途中の入力：確定・戻る・クリックは飛ばすだけ（確定・戻るは他に何も起こさない）。
## リトライ（Y / R）とボタンへのクリックは飛ばした上で、そのまま通す（1回で効く）
func _input(event: InputEvent) -> void:
	if not _root.visible or not _animating or _guard > 0.0:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
		_skip()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"retry") or (event is InputEventMouseButton and event.is_pressed()):
		_skip()


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
