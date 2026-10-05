class_name TabularText
extends Control
## 数字を同じ幅の升目に置く文字列。Oswald の数字は幅がまちまちなので、タイムを数え上げると揺れる。
## 数字だけ升目（一番広い数字の幅）の中央に置き、「:」「.」などは元の幅のまま。

var text: String = "":
	set(v):
		if v == text:
			return
		text = v
		update_minimum_size()
		queue_redraw()
var font_size: int = 72:
	set(v):
		font_size = v
		update_minimum_size()
		queue_redraw()
var color: Color = UITheme.INK:
	set(v):
		color = v
		queue_redraw()
var font: Font = UITheme.number_font()
## 影（右下に薄く）
var shadow: bool = false
## 左寄せ / 右寄せ
var align_right: bool = false


func _init(t: String = "", size_px: int = 72, col: Color = UITheme.INK) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = t
	font_size = size_px
	color = col


func _cell() -> float:
	var w := 0.0
	for d: int in range(48, 58):
		w = maxf(w, font.get_char_size(d, font_size).x)
	return w


func _advance(c: int, cell: float) -> float:
	return cell if (c >= 48 and c <= 57) else font.get_char_size(c, font_size).x


func _get_minimum_size() -> Vector2:
	var cell := _cell()
	var w := 0.0
	for i: int in text.length():
		w += _advance(text.unicode_at(i), cell)
	return Vector2(ceilf(w), ceilf(font.get_height(font_size)))


func _draw() -> void:
	var cell := _cell()
	var total := _get_minimum_size().x
	var x := (size.x - total) if align_right else 0.0
	var y := font.get_ascent(font_size)
	for i: int in text.length():
		var c := text.unicode_at(i)
		var adv := _advance(c, cell)
		var gw := font.get_char_size(c, font_size).x
		var px := x + (adv - gw) * 0.5
		if shadow:
			draw_char(font, Vector2(px + 3.0, y + 4.0), String.chr(c), font_size, Color(0, 0, 0, 0.18))
		draw_char(font, Vector2(px, y), String.chr(c), font_size, color)
		x += adv
