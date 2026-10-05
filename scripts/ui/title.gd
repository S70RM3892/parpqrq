extends Node3D
## タイトル（仕様書 8章「メニュー」）：
## - タイトルから2操作以内でコースが始まる（「Play」にフォーカスがあり、押せばすぐ始まる）
## - コース選択に絵・自己ベスト・メダル・近道の数を並べ、上にメダルと近道の合計を出す（ルートカラーOFFでのクリアは印）
## - 初回起動時に「酔いやすい方向け」プリセットを選べる画面を出す
## 背景は朝の屋上をゆっくり回るカメラ（コースと同じ部品で組む）。
## ページの切り替えはフェード＋横に滑る（0.2 s）。画面は anchors と container だけで組む（16:9 も 20:9 も同じ）。

const BG_RECIPE: PackedStringArray = ["walk 20", "vault 0.9 ac", "walk 14", "gap 3.5 -1", "walk 18", "turn L", "walk 20", "gap 4 0", "walk 20"]
const CARD_H := 116.0
const THUMB_SIZE := Vector2(172, 97)
const FREE_THUMB_SIZE := Vector2(150, 84)

var _ui: Control
var _pages: Dictionary[StringName, Control] = {}
var _settings: SettingsMenu
var _cam: Camera3D
var _t: float = 0.0
var _orbit_center: Vector3
var _logo: TitleLogo
var _sub: Label
var _menu_buttons: Array[Control] = []
var _main_totals: MedalTotals
var _totals: MedalTotals
var _d_title: Label
var _d_line: Label
var _ladder: MedalLadder
var _page_tween: Tween
## 最初に開いた時だけロゴとボタンが現れる。ページの動きは2回目から
var _shown_once: bool = false
var _intro_done: bool = false


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
	_settings.closed.connect(func() -> void: _show(&"main"))
	_settings.visible = false
	_pages[&"settings"] = _slot(_settings, true)
	for p: Control in _pages.values():
		p.visible = false


## ページの枠：画面いっぱいの Control に中身を入れる（出入りの動きは枠ごと）。centered なら中身を真ん中に置く
func _slot(content: Control, centered: bool = false) -> Control:
	var slot := Control.new()
	slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(slot)
	if content == null:
		return slot
	if centered:
		var holder := CenterContainer.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(holder)
		holder.add_child(content)
	else:
		slot.add_child(content)
	return slot


func _show(page: StringName) -> void:
	_settings.visible = page == &"settings"
	for k: StringName in _pages:
		_pages[k].visible = k == page
	var slot := _pages[page]
	if _page_tween != null:
		_page_tween.kill()
	UITheme.shift_offsets(0.0, slot)
	slot.modulate.a = 1.0
	if _shown_once:
		_page_tween = UITheme.slide_in(slot, 44.0, 0.2)
	match page:
		&"main":
			_focus_first(slot)
			_refresh_main()
			if not _intro_done:
				_intro_done = true
				_play_intro()
		&"courses":
			_refresh_courses()
		&"settings":
			_settings.open()
		&"comfort", &"controls":
			_focus_first(slot)
	_shown_once = true


## タイトルを開いた時：ロゴが滑り込み、ボタンが順に出てくる（0.6 s 以内。操作はすぐできる）
func _play_intro() -> void:
	_logo.play(0.55)
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	var i := 0
	for b: Control in _menu_buttons:
		b.modulate.a = 0.0
		tw.tween_property(b, "modulate:a", 1.0, 0.25).set_delay(0.12 + i * 0.04)
		i += 1
	_sub.modulate.a = 0.0
	tw.tween_property(_sub, "modulate:a", 1.0, 0.3).set_delay(0.25)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and (_pages[&"courses"].visible or _pages[&"controls"].visible):
		get_viewport().set_input_as_handled()
		Audio.ui(&"ui_back")
		_show(&"main")


func _main_page() -> Control:
	var inset := UITheme.safe_insets()
	var slot := _slot(null)
	# 左に薄い白の幕（ロゴとボタンを3Dの背景から浮かせる）
	var scrim := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	scrim.texture = gt
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.anchor_right = 0.45
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(scrim)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override(&"margin_left", int(maxf(110.0, inset.x + 40.0)))
	root.add_theme_constant_override(&"margin_top", int(maxf(60.0, inset.y + 30.0)))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	root.add_child(v)
	_logo = TitleLogo.new()
	v.add_child(_logo)
	_sub = UITheme.label("Run the white city. Keep your speed.", 30, UITheme.MUTED)
	_sub.add_theme_font_override(&"font", UITheme.bold_font())
	_sub.add_theme_constant_override(&"outline_size", 10)
	_sub.add_theme_color_override(&"font_outline_color", Color(1, 1, 1, 0.8))
	v.add_child(_sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	v.add_child(gap)
	var rec := Game.recommended()
	var c := CourseCatalog.get_course(rec)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	buttons.custom_minimum_size.x = 620
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(buttons)
	_menu_button(buttons, UITheme.button("Play   %s  %s" % [rec, c.get("name", "")], func() -> void: Game.play(rec), 40))
	_menu_button(buttons, UITheme.button("Courses", func() -> void: _show(&"courses")))
	_menu_button(buttons, UITheme.button("Free Run", func() -> void: Game.play(CourseCatalog.FREE_RUN)))
	_menu_button(buttons, UITheme.button("Controls", func() -> void: _show(&"controls")))
	_menu_button(buttons, UITheme.button("Settings", func() -> void: _show(&"settings")))
	if not OS.has_feature("web"):
		_menu_button(buttons, UITheme.button("Quit", func() -> void: Audio.quit_game()))
	var hint := UITheme.label("A / Enter: select     B / Esc: back", 24, UITheme.MUTED)
	hint.add_theme_font_override(&"font", UITheme.bold_font())
	hint.add_theme_constant_override(&"outline_size", 8)
	hint.add_theme_color_override(&"font_outline_color", Color(1, 1, 1, 0.8))
	v.add_child(hint)
	# 右上：メダルと近道の合計
	var corner := MarginContainer.new()
	corner.set_anchors_preset(Control.PRESET_FULL_RECT)
	corner.add_theme_constant_override(&"margin_top", int(maxf(40.0, inset.y + 24.0)))
	corner.add_theme_constant_override(&"margin_right", int(maxf(60.0, inset.z + 30.0)))
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(corner)
	var tp := PanelContainer.new()
	tp.size_flags_horizontal = Control.SIZE_SHRINK_END
	tp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tm := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		tm.add_theme_constant_override("margin_" + side, 14)
	tp.add_child(tm)
	_main_totals = MedalTotals.new(44)
	tm.add_child(_main_totals)
	corner.add_child(tp)
	return slot


func _menu_button(parent: Control, b: Button) -> void:
	parent.add_child(b)
	_menu_buttons.append(b)


func _refresh_main() -> void:
	_main_totals.refresh(Game.totals())


func _courses_page() -> Control:
	var inset := UITheme.safe_insets()
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override(&"margin_left", int(maxf(70.0, inset.x + 30.0)))
	root.add_theme_constant_override(&"margin_right", int(maxf(70.0, inset.z + 30.0)))
	root.add_theme_constant_override(&"margin_top", int(maxf(36.0, inset.y + 20.0)))
	root.add_theme_constant_override(&"margin_bottom", int(maxf(32.0, inset.w + 20.0)))
	var panel := PanelContainer.new()
	root.add_child(panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	m.add_child(v)
	# 見出しと合計
	var head := HBoxContainer.new()
	head.add_child(UITheme.title_block("Courses", 52))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_totals = MedalTotals.new(46)
	_totals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_totals)
	v.add_child(head)
	# 4つのエリア
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	for a: int in CourseCatalog.AREAS.size() - 1:
		var area: Dictionary = CourseCatalog.AREAS[a]
		var col := VBoxContainer.new()
		col.add_theme_constant_override(&"separation", 8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		var ah := HBoxContainer.new()
		ah.add_theme_constant_override(&"separation", 10)
		ah.add_child(UITheme.heading(str(a + 1), 30, UITheme.ACCENT))
		var an := UITheme.heading(area.name, 28)
		an.clip_text = true
		an.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		an.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(an)
		col.add_child(ah)
		var teach := UITheme.label(area.teach, 20, UITheme.MUTED)
		teach.clip_text = true
		teach.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(teach)
		for c: Dictionary in CourseCatalog.COURSES:
			if int(c.area) == a:
				col.add_child(_course_card(c.id))
	v.add_child(_course_card(CourseCatalog.FREE_RUN))
	# 選んでいるコースの詳細（5つのメダルのタイム）
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override(&"separation", 24)
	var dl := VBoxContainer.new()
	dl.add_theme_constant_override(&"separation", 0)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_d_title = UITheme.heading("", 36)
	dl.add_child(_d_title)
	_d_line = UITheme.label("", 24, UITheme.MUTED)
	_d_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.add_child(_d_line)
	detail.add_child(dl)
	_ladder = MedalLadder.new(44, 22)
	_ladder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail.add_child(_ladder)
	detail.custom_minimum_size.y = 96
	v.add_child(detail)
	var foot := UITheme.label("A: play     B: back     DEV and ACE need shortcuts     a small dark diamond on a medal = cleared with route color off", 20, UITheme.MUTED)
	v.add_child(foot)
	return _slot(root)


func _course_card(id: String) -> Button:
	var c := CourseCatalog.get_course(id)
	var free := id == CourseCatalog.FREE_RUN
	var b := FocusButton.new()
	b.name = "Card_" + id
	var thumb_size := FREE_THUMB_SIZE if free else THUMB_SIZE
	b.custom_minimum_size = Vector2(0, thumb_size.y + 12.0 if free else CARD_H)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_stylebox_override(&"focus", UITheme.card_focus_box())
	b.pressed.connect(func() -> void:
		Audio.ui(&"ui_ok")
		Game.play(id))
	b.focus_entered.connect(func() -> void:
		Audio.ui(&"ui_move")
		_describe(id))
	b.mouse_entered.connect(func() -> void: _describe(id))
	b.set_meta(&"id", id)
	# 中身（絵・文字）は全部マウスを素通りさせる（カードのボタンが押される）
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override(&"margin_left", 18)
	inner.add_theme_constant_override(&"margin_right", 10)
	inner.add_theme_constant_override(&"margin_top", 5)
	inner.add_theme_constant_override(&"margin_bottom", 5)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(row)
	# 絵（右下にメダル。絵の中に収めるので文字には重ならない）
	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.custom_minimum_size = thumb_size
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.texture = _thumb_texture(id)
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumb)
	var icon := MedalIcon.new()
	icon.name = "Medal"
	icon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	icon.offset_left = -50.0
	icon.offset_top = -50.0
	icon.offset_right = -1.0
	icon.offset_bottom = -1.0
	icon.visible = false
	thumb.add_child(icon)
	# 文字
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override(&"separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tv)
	var nm := UITheme.heading(String(c.get("name", id)), 24)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(nm)
	if free:
		var fl := UITheme.label("No timer. A big block of rooftops: fall and you return to the last roof you stood on.", 20, UITheme.MUTED)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(fl)
	else:
		# 2行目：コース番号とベスト、3行目：近道
		var l2 := HBoxContainer.new()
		l2.add_theme_constant_override(&"separation", 10)
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var idl := UITheme.heading(id, 24, UITheme.ACCENT)
		idl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l2.add_child(idl)
		var best := TabularText.new("--:--.--", 26, UITheme.INK)
		best.name = "Best"
		l2.add_child(best)
		var ghost := UITheme.heading("ghost", 18, UITheme.MUTED)
		ghost.name = "Ghost"
		ghost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l2.add_child(ghost)
		tv.add_child(l2)
		var sc := UITheme.label("", 19, UITheme.MUTED)
		sc.name = "Shortcuts"
		tv.add_child(sc)
	return b


## コースの絵（assets/ui/thumbs/<id>.jpg。tools/thumbs.sh で撮り直す）。無ければ単色
func _thumb_texture(id: String) -> Texture2D:
	var path := "res://assets/ui/thumbs/%s.jpg" % id
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.82, 0.84, 0.88), Color(0.62, 0.66, 0.72)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 36
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	return gt


## 記録を読み直して並べ直す（戻ってきた時に新しいベストを出す）
func _refresh_courses() -> void:
	var first: Button = null
	var last: Button = null
	var totals := Game.totals()
	_totals.refresh(totals)
	for b: Node in _pages[&"courses"].find_children("Card_*", "Button", true, false):
		var btn := b as Button
		var id: String = btn.get_meta(&"id")
		if id != CourseCatalog.FREE_RUN:
			var r: Dictionary = (totals.records as Dictionary)[id]
			(btn.find_child("Best", true, false) as TabularText).text = UITheme.format_time(r.best)
			(btn.find_child("Ghost", true, false) as Control).visible = r.ghost
			var sc := btn.find_child("Shortcuts", true, false) as Label
			sc.text = "Shortcuts %d / %d" % [r.shortcuts, r.shortcuts_total]
			var all_found: bool = int(r.shortcuts) >= int(r.shortcuts_total) and int(r.shortcuts_total) > 0
			sc.add_theme_color_override(&"font_color", UITheme.GOOD if all_found else UITheme.MUTED)
			var icon := btn.find_child("Medal", true, false) as MedalIcon
			icon.medal = r.medal
			icon.route_off = r.route_off
			icon.visible = r.medal != ""
		if first == null:
			first = btn
		if id == Game.last_course:
			last = btn
	var f := last if last != null else first
	if f != null:
		f.grab_focus.call_deferred()
		_describe(String(f.get_meta(&"id")))


func _describe(id: String) -> void:
	if id == CourseCatalog.FREE_RUN:
		_d_title.text = "FREE RUN"
		_d_line.text = "A big block of rooftops with no timer. Fall and you return to the last roof you stood on."
		_ladder.visible = false
		return
	var c := CourseCatalog.get_course(id)
	var r := Game.record(id)
	_d_title.text = "%s  %s" % [id, String(c.name).to_upper()]
	_d_line.text = "Best %s     Hidden shortcuts found %d / %d%s" % [UITheme.format_time(r.best), r.shortcuts, r.shortcuts_total,
			"     Ghost saved" if r.ghost else ""]
	_ladder.visible = true
	_ladder.set_times(c.medals, r.medal)


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
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	v.custom_minimum_size.x = 1400
	m.add_child(v)
	v.add_child(UITheme.title_block("Controls", 44))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 40)
	grid.add_theme_constant_override(&"v_separation", 0)
	for h: String in ["", "Controller", "Keyboard + mouse"]:
		grid.add_child(UITheme.heading(h, 22, UITheme.ACCENT))
	for row: Array in CONTROLS:
		for i: int in 3:
			grid.add_child(UITheme.label(row[i], 22, UITheme.INK if i == 0 else UITheme.MUTED))
	v.add_child(grid)
	v.add_child(UITheme.heading("Moves", 24, UITheme.ACCENT))
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
	return _slot(panel, true)


func _comfort_page() -> Control:
	var panel := PanelContainer.new()
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 36)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	m.add_child(v)
	v.add_child(UITheme.title_block("Before you run", 48))
	var t := UITheme.label("Do you get motion sick in first-person games?\nThe motion-sensitive preset lowers head bob, shake, tilt,\nspeed FOV and speed lines to 30% and shows a fixed center dot.\nYou can change every setting later.", 28, UITheme.MUTED)
	v.add_child(t)
	v.add_child(UITheme.button("Standard", func() -> void: _choose_comfort(false), 34))
	v.add_child(UITheme.button("Motion-sensitive", func() -> void: _choose_comfort(true), 34))
	return _slot(panel, true)


func _choose_comfort(sensitive: bool) -> void:
	if sensitive:
		Settings.apply_comfort_preset()
	else:
		Settings.apply_default_preset()
	Settings.first_run_done = true
	Settings.save_settings()
	_show(&"main")


func _focus_first(root: Control) -> void:
	for n: Node in root.find_children("*", "Button", true, false):
		if (n as Button).is_visible_in_tree():
			(n as Button).grab_focus.call_deferred()
			return
