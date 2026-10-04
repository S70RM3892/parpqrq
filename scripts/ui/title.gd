extends Node3D
## タイトル（仕様書 8章「メニュー」）：
## - タイトルから2操作以内でコースが始まる（「Play」にフォーカスがあり、押せばすぐ始まる）
## - コース選択に自己ベスト・メダル・ゴーストの有無を並べる（ルートカラーOFFでのクリアは印）
## - 初回起動時に「酔いやすい方向け」プリセットを選べる画面を出す
## 背景は朝の屋上をゆっくり回るカメラ（コースと同じ部品で組む）。

const BG_RECIPE: PackedStringArray = ["walk 20", "vault 0.9 ac", "walk 14", "gap 3.5 -1", "walk 18", "turn L", "walk 20", "gap 4 0", "walk 20"]

var _ui: Control
var _pages: Dictionary[StringName, Control] = {}
var _settings: SettingsMenu
var _info: Label
var _cam: Camera3D
var _t: float = 0.0
var _orbit_center: Vector3


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	_build_ui()
	Audio.set_mode(Audio.Mode.MENU)
	if not Settings.first_run_done:
		_show(&"comfort")
	elif Game.open_course_select:
		_show(&"courses")
	else:
		_show(&"main")
	Game.open_course_select = false


func _process(delta: float) -> void:
	_t += delta
	var a := _t * 0.05
	_cam.global_position = _orbit_center + Vector3(sin(a) * 26.0, 7.0 + sin(_t * 0.2) * 0.8, cos(a) * 26.0)
	_cam.look_at(_orbit_center + Vector3(0, 2.0, 0), Vector3.UP)


# --- 背景 ---------------------------------------------------------------------

func _build_background() -> void:
	var area: Dictionary = CourseCatalog.AREAS[0]
	var geo := LevelGeometry.new()
	var b := CourseBuilder.new(geo, area, 7)
	b.build(BG_RECIPE)
	geo.build()
	add_child(geo)
	LevelLighting.apply(geo, "title")
	var atmo := Atmosphere.new()
	atmo.preset = &"morning"
	atmo.fog_floor = -6.0
	add_child(atmo)
	var bd := Backdrop.new()
	add_child(bd)
	bd.build(b.route_points, CourseBuilder.STREET_Y, 0.0, 7)
	_orbit_center = b.route_points[b.route_points.size() / 2]
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.current = true


# --- 画面 ---------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.get_theme()
	layer.add_child(_ui)
	_pages[&"main"] = _main_page()
	_pages[&"courses"] = _courses_page()
	_pages[&"comfort"] = _comfort_page()
	_pages[&"controls"] = _controls_page()
	_settings = SettingsMenu.new()
	_settings.set_anchors_preset(Control.PRESET_CENTER)
	_settings.closed.connect(func() -> void: _show(&"main"))
	_center(_settings)
	_pages[&"settings"] = _settings
	for p: Control in _pages.values():
		p.visible = false


func _show(page: StringName) -> void:
	for k: StringName in _pages:
		_pages[k].visible = k == page
	match page:
		&"main":
			_focus_first(_pages[page])
		&"courses":
			_refresh_courses()
		&"settings":
			_settings.open()
		&"comfort", &"controls":
			_focus_first(_pages[page])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and (_pages[&"courses"].visible or _pages[&"controls"].visible):
		get_viewport().set_input_as_handled()
		Audio.ui(&"ui_back")
		_show(&"main")


func _main_page() -> Control:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override(&"margin_left", 120)
	root.add_theme_constant_override(&"margin_top", 110)
	_ui.add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	root.add_child(v)
	var title := UITheme.label("PARKOUR", 128, UITheme.INK)
	title.add_theme_color_override(&"font_outline_color", Color(1, 1, 1, 0.8))
	title.add_theme_constant_override(&"outline_size", 18)
	v.add_child(title)
	var sub := UITheme.label("Run the white city. Keep your speed.", 30, UITheme.MUTED)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 40
	v.add_child(gap)
	var rec := Game.recommended()
	var c := CourseCatalog.get_course(rec)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	buttons.custom_minimum_size.x = 620
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(buttons)
	buttons.add_child(UITheme.button("Play   %s  %s" % [rec, c.get("name", "")], func() -> void: Game.play(rec), 40))
	buttons.add_child(UITheme.button("Courses", func() -> void: _show(&"courses")))
	buttons.add_child(UITheme.button("Free Run", func() -> void: Game.play(CourseCatalog.FREE_RUN)))
	buttons.add_child(UITheme.button("Controls", func() -> void: _show(&"controls")))
	buttons.add_child(UITheme.button("Settings", func() -> void: _show(&"settings")))
	if not OS.has_feature("web"):
		buttons.add_child(UITheme.button("Quit", func() -> void: Audio.quit_game()))
	var hint := UITheme.label("A / Enter: select     B / Esc: back", 24, UITheme.MUTED)
	v.add_child(hint)
	return root


func _courses_page() -> Control:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 70)
	root.add_theme_constant_override(&"margin_top", 60)
	root.add_theme_constant_override(&"margin_bottom", 50)
	_ui.add_child(root)
	var panel := PanelContainer.new()
	root.add_child(panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	m.add_child(v)
	v.add_child(UITheme.label("Courses", 52))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	for a: int in CourseCatalog.AREAS.size():
		var area: Dictionary = CourseCatalog.AREAS[a]
		var col := VBoxContainer.new()
		col.add_theme_constant_override(&"separation", 10)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		col.add_child(UITheme.label("%d  %s" % [a + 1, area.name], 26, UITheme.ACCENT))
		col.add_child(UITheme.label(area.teach, 20, UITheme.MUTED))
		var ids: PackedStringArray = []
		for c: Dictionary in CourseCatalog.COURSES:
			if int(c.area) == a:
				ids.append(c.id)
		if a == CourseCatalog.AREAS.size() - 1:
			ids.append(CourseCatalog.FREE_RUN)
		for id: String in ids:
			col.add_child(_course_card(id))
	_info = UITheme.label("", 26, UITheme.INK)
	_info.custom_minimum_size.y = 80
	v.add_child(_info)
	v.add_child(UITheme.label("A: play     B: back     a small dark diamond on a medal = cleared with route color off", 22, UITheme.MUTED))
	return root


func _course_card(id: String) -> Button:
	var c := CourseCatalog.get_course(id)
	var b := Button.new()
	b.name = "Card_" + id
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 96)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override(&"font_size", 26)
	b.pressed.connect(func() -> void:
		Audio.ui(&"ui_ok")
		Game.play(id))
	b.focus_entered.connect(func() -> void:
		Audio.ui(&"ui_move")
		_describe(id))
	b.mouse_entered.connect(func() -> void: _describe(id))
	var icon := MedalIcon.new()
	icon.name = "Medal"
	icon.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	icon.position = Vector2(-56, -20)
	icon.size = Vector2(40, 40)
	b.add_child(icon)
	b.set_meta(&"id", id)
	b.text = c.get("name", id)
	return b


## 記録を読み直して並べ直す（戻ってきた時に新しいベストを出す）
func _refresh_courses() -> void:
	var first: Button = null
	var last: Button = null
	for b: Node in _pages[&"courses"].find_children("Card_*", "Button", true, false):
		var btn := b as Button
		var id: String = btn.get_meta(&"id")
		var c := CourseCatalog.get_course(id)
		if id == CourseCatalog.FREE_RUN:
			btn.text = "Free Run\nno timer"
		else:
			var r := Game.record(id)
			btn.text = "%s  %s\n%s%s   shortcuts %d/%d" % [id, c.name, UITheme.format_time(r.best), "   ghost" if r.ghost else "",
					r.shortcuts, r.shortcuts_total]
			var icon := btn.get_node("Medal") as MedalIcon
			icon.medal = r.medal
			icon.route_off = r.route_off
		if first == null:
			first = btn
		if id == Game.last_course:
			last = btn
	var f := last if last != null else first
	if f != null:
		f.grab_focus.call_deferred()


func _describe(id: String) -> void:
	if id == CourseCatalog.FREE_RUN:
		_info.text = "Free Run — a big block of rooftops with no timer. Fall and you return to the last roof you stood on."
		return
	var c := CourseCatalog.get_course(id)
	var m: Array = c.medals
	var r := Game.record(id)
	_info.text = "%s  %s      best %s      hidden shortcuts found %d / %d\nDEV %s   ACE %s   GOLD %s   SILVER %s   BRONZE %s     (DEV and ACE need shortcuts)" % [
			id, c.name, UITheme.format_time(r.best), r.shortcuts, r.shortcuts_total,
			UITheme.format_time(m[0]), UITheme.format_time(m[1]), UITheme.format_time(m[2]), UITheme.format_time(m[3]), UITheme.format_time(m[4])]


## 操作と技（走っている間は文字を出さないので、ここで覚える：仕様書 8章）
const CONTROLS: Array[Array] = [
	["Move (tilt = walk to run)", "Left stick", "WASD (Shift: walk)"],
	["Look", "Right stick", "Mouse"],
	["Jump / vault / climb / wall run", "A / Cross, R2", "Space"],
	["Crouch: slide / roll on landing", "B / Circle, L2", "Ctrl / C"],
	["Quick turn", "X / Square", "Q"],
	["Retry (hold 0.3 s: checkpoint)", "Y / Triangle", "R"],
	["Pause", "Start", "Esc"],
]
const MOVES: PackedStringArray = [
	"Vault: jump while running at a waist-high obstacle (0.6-1.3 m). Jump 0.15 s before you reach it for a Perfect.",
	"Climb: jump at a ledge up to 2.4 m. Taller walls up to about 4 m: run straight at them and jump (vertical wall run).",
	"Wall run: jump along a wall at speed. Jump again to kick off; Perfect if you kick within 0.15 s.",
	"Slide: crouch while running; slopes keep you accelerating. Jump out of a slide for +8%.",
	"Roll: crouch just before landing a drop of 2 m or more. Exactly on landing = Perfect.",
	"Pull back on the stick to brake. Chain moves without stopping to build momentum (the orange glow at the screen edge).",
	"Wall kick: jump the moment you touch a wall in the air. Hold toward the wall to kick upward (reach a higher ledge), or away to bounce off.",
	"Vertical wall run + kick: hold toward the wall and jump at the top of the run to reach about 0.8 m higher.",
	"Vault jump: press jump again while you are on top of the obstacle to launch from it. Pushing off its far edge = Perfect.",
	"Swing bar: jump at a horizontal bar to grab it. Release with jump: early = long and low, around 35 degrees = Perfect, late = high.",
	"Zipline: jump at a cable to grab it and slide down. Jump off just before the end for a Perfect.",
	"Hanging from a ledge: look back and jump (or quick turn) to kick off the wall behind you.",
	"Hidden shortcuts: the orange route is the safe way. Faster lines hide in scaffolds, AC units, stair houses and cables. Look for scuff marks.",
]


func _controls_page() -> Control:
	var panel := PanelContainer.new()
	_center(panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	v.custom_minimum_size.x = 1400
	m.add_child(v)
	v.add_child(UITheme.label("Controls", 40))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 40)
	grid.add_theme_constant_override(&"v_separation", 0)
	for h: String in ["", "Controller", "Keyboard + mouse"]:
		grid.add_child(UITheme.label(h, 20, UITheme.ACCENT))
	for row: Array in CONTROLS:
		for i: int in 3:
			grid.add_child(UITheme.label(row[i], 22, UITheme.INK if i == 0 else UITheme.MUTED))
	v.add_child(grid)
	v.add_child(UITheme.label("Moves", 22, UITheme.ACCENT))
	# 技は2列（1.1で増えたので1列だと画面に収まらない）
	var moves := GridContainer.new()
	moves.columns = 2
	moves.add_theme_constant_override(&"h_separation", 36)
	moves.add_theme_constant_override(&"v_separation", 4)
	for line: String in MOVES:
		var l := UITheme.label(line, 19, UITheme.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 680
		moves.add_child(l)
	v.add_child(moves)
	v.add_child(UITheme.button("Back", func() -> void: _show(&"main"), 30))
	return panel


func _comfort_page() -> Control:
	var panel := PanelContainer.new()
	_center(panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 36)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	m.add_child(v)
	v.add_child(UITheme.label("Before you run", 48))
	var t := UITheme.label("Do you get motion sick in first-person games?\nThe motion-sensitive preset lowers head bob, shake, tilt,\nspeed FOV and speed lines to 30% and shows a fixed center dot.\nYou can change every setting later.", 28, UITheme.MUTED)
	v.add_child(t)
	v.add_child(UITheme.button("Standard", func() -> void: _choose_comfort(false), 34))
	v.add_child(UITheme.button("Motion-sensitive", func() -> void: _choose_comfort(true), 34))
	return panel


func _choose_comfort(sensitive: bool) -> void:
	if sensitive:
		Settings.apply_comfort_preset()
	else:
		Settings.apply_default_preset()
	Settings.first_run_done = true
	Settings.save_settings()
	_show(&"main")


func _center(c: Control) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(holder)
	holder.add_child(c)
	c.visibility_changed.connect(func() -> void: holder.visible = c.visible)


func _focus_first(root: Control) -> void:
	for n: Node in root.find_children("*", "Button", true, false):
		if (n as Button).is_visible_in_tree():
			(n as Button).grab_focus.call_deferred()
			return
