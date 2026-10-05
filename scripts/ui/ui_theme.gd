class_name UITheme
extends RefCounted
## 画面（メニュー）の見た目。白地に1色（ルートカラー）だけを差す（仕様書 6章と同じ考え）。
## コントローラーで選んでいる所がはっきり分かるよう、フォーカスはオレンジの太枠。

const INK := Color(0.1, 0.11, 0.13)
const PAPER := Color(0.97, 0.97, 0.96, 0.94)
const MUTED := Color(0.42, 0.44, 0.48)
const ACCENT := Color("#FF6A1A")
const MEDAL_COLORS: Dictionary[String, Color] = {
	"DEV": Color("#FF6A1A"), "ACE": Color(0.62, 0.94, 1.0), "GOLD": Color(0.95, 0.75, 0.2), "SILVER": Color(0.72, 0.75, 0.8),
	"BRONZE": Color(0.75, 0.5, 0.3),
}

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 30
	t.set_color(&"font_color", &"Label", INK)
	t.set_color(&"font_color", &"Button", INK)
	t.set_color(&"font_hover_color", &"Button", INK)
	t.set_color(&"font_focus_color", &"Button", INK)
	t.set_color(&"font_pressed_color", &"Button", Color.WHITE)
	t.set_color(&"font_color", &"CheckButton", INK)
	t.set_color(&"font_focus_color", &"CheckButton", INK)
	t.set_color(&"font_hover_color", &"CheckButton", INK)
	t.set_color(&"font_color", &"OptionButton", INK)
	t.set_color(&"font_focus_color", &"OptionButton", INK)
	t.set_color(&"font_hover_color", &"OptionButton", INK)
	for cls: StringName in [&"Button", &"OptionButton", &"CheckButton"]:
		t.set_stylebox(&"normal", cls, _box(Color(1, 1, 1, 0.75), Color(0, 0, 0, 0.08), 2))
		t.set_stylebox(&"hover", cls, _box(Color(1, 1, 1, 0.95), Color(0, 0, 0, 0.15), 2))
		t.set_stylebox(&"pressed", cls, _box(ACCENT, ACCENT, 2))
		t.set_stylebox(&"focus", cls, _box(Color(0, 0, 0, 0), ACCENT, 5))
		t.set_stylebox(&"disabled", cls, _box(Color(1, 1, 1, 0.4), Color(0, 0, 0, 0.05), 2))
	t.set_stylebox(&"panel", &"PanelContainer", _box(PAPER, Color(0, 0, 0, 0.06), 2, 18))
	# スライダー
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.15)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.set_corner_radius_all(4)
	t.set_stylebox(&"slider", &"HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	var focus := _box(Color(0, 0, 0, 0), ACCENT, 4)
	t.set_stylebox(&"focus", &"HSlider", focus)
	_theme = t
	return t


static func _box(bg: Color, border: Color, border_w: int, radius: int = 10) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(border_w)
	b.set_corner_radius_all(radius)
	b.content_margin_left = 22
	b.content_margin_right = 22
	b.content_margin_top = 12
	b.content_margin_bottom = 12
	return b


static func label(text: String, size: int = 30, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


static func button(text: String, on_press: Callable, size: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override(&"font_size", size)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		Audio.ui(&"ui_ok")
		on_press.call())
	b.focus_entered.connect(func() -> void: Audio.ui(&"ui_move"))
	return b


static func format_time(t: float) -> String:
	if t >= INF or t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	return "%d:%05.2f" % [m, t - m * 60.0]
