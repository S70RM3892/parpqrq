class_name MedalTotals
extends HBoxContainer
## メダルの合計（ティアごとの数）と見つけた近道の合計。タイトルとコース選択の上に出す。
## 数は Game.totals() から。icon_size で大きさを変える。

var _counts: Dictionary[String, Label] = {}
var _shortcuts: Label
var _icon_size: int


func _init(icon_size: int = 40) -> void:
	_icon_size = icon_size
	name = "MedalTotals"
	add_theme_constant_override(&"separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for m: String in CourseTimer.MEDALS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override(&"separation", 2)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := MedalIcon.new()
		ic.medal = m
		ic.custom_minimum_size = Vector2(icon_size, icon_size)
		cell.add_child(ic)
		var n := UITheme.heading("0", int(icon_size * 0.8))
		n.custom_minimum_size.x = int(icon_size * 0.55)
		cell.add_child(n)
		add_child(cell)
		_counts[m] = n
	var sep := ColorRect.new()
	sep.color = Color(0, 0, 0, 0.18)
	sep.custom_minimum_size = Vector2(2, icon_size * 0.8)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(sep)
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override(&"separation", -4)
	sc.add_child(UITheme.heading("Shortcuts", int(icon_size * 0.38), UITheme.MUTED))
	_shortcuts = UITheme.heading("0 / 0", int(icon_size * 0.72))
	sc.add_child(_shortcuts)
	add_child(sc)


func refresh(t: Dictionary) -> void:
	for m: String in _counts:
		_counts[m].text = str(int((t.counts as Dictionary).get(m, 0)))
		# 0 個のティアは薄く（取った数が増えるのが見える）
		(_counts[m].get_parent() as Control).modulate.a = 1.0 if int((t.counts as Dictionary).get(m, 0)) > 0 else 0.4
	_shortcuts.text = "%d / %d" % [int(t.shortcuts), int(t.shortcuts_total)]
