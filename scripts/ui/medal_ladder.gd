class_name MedalLadder
extends HBoxContainer
## 5つのメダル（DEV・ACE・GOLD・SILVER・BRONZE）とそれぞれのタイム。取った分は明るく、次の目標はオレンジの枠。
## 結果画面とコース選択の詳細で使う。

var _cells: Array[PanelContainer] = []
var _icons: Array[MedalIcon] = []
var _times: Array[TabularText] = []
var _frame: StyleBoxFlat
var _clear: StyleBoxFlat


func _init(icon_size: int = 44, time_size: int = 22) -> void:
	name = "MedalLadder"
	add_theme_constant_override(&"separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = StyleBoxFlat.new()
	_frame.bg_color = Color(UITheme.ACCENT, 0.1)
	_frame.border_color = UITheme.ACCENT
	_frame.set_border_width_all(3)
	_frame.set_corner_radius_all(10)
	_frame.set_content_margin_all(5)
	_clear = StyleBoxFlat.new()
	_clear.bg_color = Color(0, 0, 0, 0)
	_clear.set_content_margin_all(5)
	for m: String in CourseTimer.MEDALS:
		var cell := PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := VBoxContainer.new()
		v.add_theme_constant_override(&"separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := MedalIcon.new()
		ic.medal = m
		ic.custom_minimum_size = Vector2(icon_size, icon_size)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var tt := TabularText.new("--:--.--", time_size, UITheme.INK)
		tt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(tt)
		cell.add_child(v)
		add_child(cell)
		_cells.append(cell)
		_icons.append(ic)
		_times.append(tt)


## times：[DEV, ACE, GOLD, SILVER, BRONZE] の秒。best_medal：今取れているメダル（無ければ ""）。
func set_times(times: Array, best_medal: String) -> void:
	var earned := CourseTimer.MEDALS.find(best_medal) if best_medal != "" else CourseTimer.MEDALS.size()
	var next := earned - 1 if earned > 0 else -1
	for i: int in _cells.size():
		var got := i >= earned
		_times[i].text = UITheme.format_time(float(times[i])) if i < times.size() else "--:--.--"
		_times[i].color = UITheme.INK if got else UITheme.MUTED
		_icons[i].modulate.a = 1.0 if got else 0.38
		_cells[i].add_theme_stylebox_override(&"panel", _frame if i == next else _clear)
