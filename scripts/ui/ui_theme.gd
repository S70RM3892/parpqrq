class_name UITheme
extends RefCounted
## 画面（メニュー）の見た目。白地に1色（ルートカラー）だけを差す（仕様書 6章と同じ考え）。
## 見出しは Oswald（太い縦長）、本文は Zen Kaku Gothic New（日本語の字を含む）。数字は TabularText で升目に置く。
## コントローラーで選んでいる所がはっきり分かるよう、フォーカスは黒地に白文字＋オレンジの帯（FocusButton）。

const INK := Color(0.1, 0.11, 0.13)
const PAPER := Color(0.97, 0.97, 0.96, 0.94)
const MUTED := Color(0.42, 0.44, 0.48)
const ACCENT := Color("#FF6A1A")
const GOOD := Color("#1E9E5A")
const BAD := Color("#D8402A")
## 金属の質感のメダル：[明るい所, 地の色, 暗い所]（MedalIcon が使う）
const MEDAL_COLORS: Dictionary[String, Color] = {
	"DEV": Color("#FF6A1A"), "ACE": Color("#BFEFFF"), "GOLD": Color("#EDB422"), "SILVER": Color("#B5BBC6"),
	"BRONZE": Color("#BA7640"),
}
const MEDAL_TONES: Dictionary[String, Array] = {
	"DEV": [Color("#FFB07A"), Color("#FF6A1A"), Color("#8F2F00")],
	"ACE": [Color("#FFFFFF"), Color("#B6EAFB"), Color("#4C93B2")],
	"GOLD": [Color("#FFF0A8"), Color("#EDB422"), Color("#7E4F00")],
	"SILVER": [Color("#FFFFFF"), Color("#B5BBC6"), Color("#555C68")],
	"BRONZE": [Color("#F3B98A"), Color("#BA7640"), Color("#5E3217")],
}
## メダルの印の1字（小さくても読める。ACE は白金なので A）
const MEDAL_GLYPHS: Dictionary[String, String] = {"DEV": "D", "ACE": "A", "GOLD": "G", "SILVER": "S", "BRONZE": "B"}

const _FONT_HEAD := preload("res://assets/fonts/Oswald.ttf")
const _FONT_BODY := preload("res://assets/fonts/ZenKakuGothicNew-Regular.ttf")
const _FONT_BOLD := preload("res://assets/fonts/ZenKakuGothicNew-Bold.ttf")
const _TAG_WGHT := 0x77676874  # 'wght'

static var _theme: Theme
static var _heading: FontVariation
static var _number: FontVariation


## 見出し：Oswald の太字（日本語はボディの太字に落ちる）
static func heading_font() -> Font:
	if _heading == null:
		_heading = _oswald(700, 1.0)
	return _heading


## 数字：Oswald のやや細い字（大きいタイムでも詰まらない）。TabularText で升目に置く
static func number_font() -> Font:
	if _number == null:
		_number = _oswald(600, 0.0)
	return _number


static func body_font() -> Font:
	return _FONT_BODY


static func bold_font() -> Font:
	return _FONT_BOLD


static func _oswald(weight: int, spacing: float) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = _FONT_HEAD
	f.variation_opentype = {_TAG_WGHT: weight}
	f.spacing_glyph = int(spacing)
	var fb: Array[Font] = [_FONT_BOLD]
	f.fallbacks = fb
	return f


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = _FONT_BODY
	t.default_font_size = 30
	t.set_color(&"font_color", &"Label", INK)
	for cls: StringName in [&"Button", &"OptionButton", &"CheckButton"]:
		t.set_font(&"font", cls, _FONT_BOLD)
		t.set_color(&"font_color", cls, INK)
		t.set_color(&"font_hover_color", cls, INK)
		t.set_color(&"font_focus_color", cls, INK)
		t.set_color(&"font_pressed_color", cls, Color.WHITE)
		t.set_stylebox(&"normal", cls, _box(Color(1, 1, 1, 0.78), Color(0, 0, 0, 0.1), 2))
		t.set_stylebox(&"hover", cls, _box(Color(1, 1, 1, 0.96), Color(0, 0, 0, 0.18), 2))
		t.set_stylebox(&"pressed", cls, _box(ACCENT, ACCENT, 2))
		t.set_stylebox(&"focus", cls, _box(Color(0, 0, 0, 0), ACCENT, 4))
		t.set_stylebox(&"disabled", cls, _box(Color(1, 1, 1, 0.45), Color(0, 0, 0, 0.05), 2))
	# ボタンは選んでいる間、黒地に白文字（遠くからでも分かる）。切り替え・チェックは枠だけ
	t.set_stylebox(&"focus", &"Button", _box(INK, INK, 2))
	t.set_color(&"font_focus_color", &"Button", Color.WHITE)
	t.set_color(&"font_hover_pressed_color", &"Button", Color.WHITE)
	t.set_font_size(&"font_size", &"Button", 32)
	t.set_stylebox(&"panel", &"PanelContainer", _panel_box())
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


## カード（中に絵や文字を置くボタン）の選択中：黒地だと中の文字が読めないので、明るい地にオレンジの太枠
static func card_focus_box() -> StyleBoxFlat:
	return _box(Color(1, 1, 1, 0.98), ACCENT, 4)


## 板：白い紙に細い縁と柔らかい影（背景の3Dから浮かせる）
static func _panel_box() -> StyleBoxFlat:
	var b := _box(PAPER, Color(0, 0, 0, 0.08), 2, 16)
	b.shadow_color = Color(0, 0, 0, 0.28)
	b.shadow_size = 22
	b.shadow_offset = Vector2(0, 8)
	return b


## 本文の文字
static func label(text: String, size: int = 30, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", _FONT_BODY)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


## 見出しの文字（Oswald の太字・大文字）
static func heading(text: String, size: int = 48, color: Color = INK) -> Label:
	var l := label(text.to_upper(), size, color)
	l.add_theme_font_override(&"font", heading_font())
	return l


## 見出しとオレンジの短い帯（板の先頭に置く）
static func title_block(text: String, size: int = 52) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	v.add_child(heading(text, size))
	v.add_child(accent_bar(84, 6))
	return v


static func accent_bar(w: float, h: float = 6.0, color: Color = ACCENT) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(w, h)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, on_press: Callable, size: int = 34) -> Button:
	var b := FocusButton.new()
	b.text = text
	b.add_theme_font_override(&"font", heading_font())
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


## ページ・板の出入り：フェード＋横にすっと滑る（0.15〜0.25 s）。一時停止中・スローの間も同じ速さで動く。
## 画面いっぱいに広げた枠（anchors が左右で違う）は offset で動かす（position を触ると大きさがずれる）
static func slide_in(c: CanvasItem, from_x: float = 40.0, duration: float = 0.2) -> Tween:
	var tw := c.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.modulate.a = 0.0
	if c is Control:
		var ct := c as Control
		if is_equal_approx(ct.anchor_left, ct.anchor_right):
			ct.position.x = from_x
			tw.tween_property(c, "position:x", 0.0, duration)
		else:
			shift_offsets(from_x, ct)
			tw.tween_method(shift_offsets.bind(ct), from_x, 0.0, duration)
	tw.tween_property(c, "modulate:a", 1.0, duration * 0.8)
	return tw


## 左右の offset を同じだけずらす（横に動かす）
static func shift_offsets(x: float, c: Control) -> void:
	c.offset_left = x
	c.offset_right = x


## 板がふわっと出る（真ん中に置かれた板用：位置は容器が決めるので拡大とフェード）
static func pop_in(c: Control, duration: float = 0.18) -> Tween:
	c.pivot_offset = c.get_combined_minimum_size() * 0.5
	c.scale = Vector2(0.96, 0.96)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, duration)
	tw.tween_property(c, "modulate:a", 1.0, duration * 0.8)
	return tw


## 画面の切れ込み（ノッチ・角の丸み・ジェスチャーバー）の内側までの余白。キャンバスの単位で (左, 上, 右, 下)。PC では 0
static func safe_insets() -> Vector4:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4.ZERO
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.x <= 0.0 or safe.size.x <= 0.0 or not (OS.has_feature("mobile") or OS.has_feature("web")):
		return Vector4.ZERO
	var k := minf(win.x / 1920.0, win.y / 1080.0)  # stretch: canvas_items / expand の拡大率
	return Vector4(maxf(safe.position.x, 0.0) / k, maxf(safe.position.y, 0.0) / k,
			maxf(screen.x - safe.end.x, 0.0) / k, maxf(screen.y - safe.end.y, 0.0) / k)
