class_name SettingsMenu
extends PanelContainer
## 設定画面（仕様書 8章「酔い対策（設定で全部変えられる）」＋音量・画質・ルートカラー）。
## タイトルと一時停止の両方から開く。変えたらすぐ効く。閉じる時に保存する。
## コントローラー：上下で項目、左右で値、B / Esc で戻る。

signal closed

## [設定の名前, 表示名, 種類, 最小, 最大, 刻み]。種類: "pct" = 0〜100%、"num" = 数値、"bool"、"fps"、"quality"
const ROWS: Array[Array] = [
	["", "COMFORT", "header"],
	["fov", "Field of view", "num", 75.0, 110.0, 1.0],
	["speed_fov_strength", "Speed FOV", "pct"],
	["head_bob_strength", "Head bob", "pct"],
	["screen_shake_strength", "Screen shake", "pct"],
	["camera_tilt_strength", "Camera tilt (wall run etc.)", "pct"],
	["speed_lines_strength", "Speed lines & vignette", "pct"],
	["center_dot", "Fixed center dot", "bool"],
	["hitstop_slowmo", "Perfect slow-motion", "bool"],
	["", "CONTROLS", "header"],
	["sensitivity_x", "Look sensitivity (horizontal)", "num", 0.1, 3.0, 0.05],
	["sensitivity_y", "Look sensitivity (vertical)", "num", 0.1, 3.0, 0.05],
	["invert_y", "Invert vertical look", "bool"],
	["feel_vibration", "Vibration", "bool"],
	["", "VISUALS", "header"],
	["route_color", "Route color (off = expert, marks your medal)", "bool"],
	["graphics_quality", "Graphics", "quality"],
	["render_scale", "Render scale", "num", 0.7, 1.0, 0.05],
	["max_fps", "Frame rate", "fps"],
	["", "AUDIO", "header"],
	["volume_master", "Master volume", "pct"],
	["volume_music", "Music", "pct"],
	["volume_sfx", "Effects", "pct"],
]

var _list: VBoxContainer
var _first: Control
var _scroll: ScrollContainer


func _ready() -> void:
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(1100, 0)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	margin.add_child(v)
	v.add_child(UITheme.title_block("Settings", 48))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override(&"separation", 16)
	presets.add_child(UITheme.button("Motion-sensitive preset", _comfort, 28))
	presets.add_child(UITheme.button("Default preset", _default, 28))
	v.add_child(presets)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.custom_minimum_size = Vector2(0, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_list)
	v.add_child(UITheme.button("Back", close, 32))
	_rebuild()


func open() -> void:
	visible = true
	_rebuild()
	_scroll.set_deferred(&"scroll_vertical", 0)
	if _first != null:
		_first.grab_focus.call_deferred()


func close() -> void:
	Settings.save_settings()
	Settings.apply()
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.ui(&"ui_back")
		close()


func _comfort() -> void:
	Settings.apply_comfort_preset()
	_rebuild()


func _default() -> void:
	Settings.apply_default_preset()
	_rebuild()


func _rebuild() -> void:
	# すぐ外す（queue_free だけだと1フレーム古い行が残り、新しい行が下にずれてスクロールが狂う）
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_first = null
	for r: Array in ROWS:
		var key: String = r[0]
		var kind: String = r[2]
		if kind == "header":
			if _list.get_child_count() > 0:
				var gap := Control.new()
				gap.custom_minimum_size.y = 10
				_list.add_child(gap)
			var h := UITheme.heading(r[1], 26, UITheme.ACCENT)
			_list.add_child(h)
			_list.add_child(UITheme.accent_bar(48, 3))
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 18)
		var name_l := UITheme.label(r[1], 28)
		name_l.custom_minimum_size.x = 600
		row.add_child(name_l)
		var ctrl: Control
		match kind:
			"bool":
				var cb := CheckButton.new()
				cb.button_pressed = Settings.get(key)
				cb.focus_mode = Control.FOCUS_ALL
				cb.toggled.connect(func(on: bool) -> void:
					Settings.set(key, on)
					Settings.apply()
					Audio.ui(&"ui_move"))
				ctrl = cb
			"pct", "num":
				var lo: float = 0.0 if kind == "pct" else r[3]
				var hi: float = 1.0 if kind == "pct" else r[4]
				var step: float = 0.05 if kind == "pct" else r[5]
				var box := HBoxContainer.new()
				box.add_theme_constant_override(&"separation", 16)
				var sl := HSlider.new()
				sl.min_value = lo
				sl.max_value = hi
				sl.step = step
				sl.value = Settings.get(key)
				sl.custom_minimum_size = Vector2(300, 36)
				sl.focus_mode = Control.FOCUS_ALL
				var val := UITheme.label(_fmt(kind, sl.value), 28, UITheme.MUTED)
				val.custom_minimum_size.x = 110
				sl.value_changed.connect(func(x: float) -> void:
					Settings.set(key, x)
					Settings.apply()
					val.text = _fmt(kind, x))
				box.add_child(sl)
				box.add_child(val)
				ctrl = box
				ctrl.set_meta(&"focus", sl)
			"fps", "quality":
				var ob := OptionButton.new()
				ob.focus_mode = Control.FOCUS_ALL
				var values: Array = [60, 90, 120] if kind == "fps" else [0, 1]
				for x: int in values:
					ob.add_item(("%d fps" % x) if kind == "fps" else ("High" if x == 1 else "Low"))
				ob.selected = values.find(Settings.get(key))
				ob.item_selected.connect(func(i: int) -> void:
					Settings.set(key, values[i])
					Settings.apply())
				ctrl = ob
		row.add_child(ctrl)
		_list.add_child(row)
		if _first == null:
			_first = ctrl.get_meta(&"focus") if ctrl.has_meta(&"focus") else ctrl


func _fmt(kind: String, x: float) -> String:
	return ("%d%%" % roundi(x * 100.0)) if kind == "pct" else ("%.2f" % x).rstrip("0").rstrip(".")
