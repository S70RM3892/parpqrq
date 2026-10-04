class_name MedalIcon
extends Control
## メダルの印（円）。ルートカラーOFFでクリアしていれば右上に小さな菱形（仕様書 6章）。
## 文字（字形）に頼らず描くので、どのフォントでも同じに見える。

var medal: String = "":
	set(v):
		medal = v
		queue_redraw()
var route_off: bool = false:
	set(v):
		route_off = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.38
	if medal == "":
		draw_arc(c, r, 0.0, TAU, 32, Color(0, 0, 0, 0.18), 3.0, true)
	else:
		var col: Color = UITheme.MEDAL_COLORS.get(medal, Color.WHITE)
		draw_circle(c, r, col)
		draw_arc(c, r, 0.0, TAU, 32, col.darkened(0.25), 3.0, true)
		if medal == "DEV":
			draw_circle(c, r * 0.35, Color.WHITE)
		elif medal == "ACE":
			draw_arc(c, r * 0.55, 0.0, TAU, 24, col.darkened(0.45), 3.0, true)  # 白金：二重の輪（ゴールド・シルバーの丸と見分ける）
	if route_off:
		var p := c + Vector2(r * 0.9, -r * 0.9)
		var d := r * 0.42
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), UITheme.INK)
