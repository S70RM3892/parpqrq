class_name TitleLogo
extends Control
## タイトルのロゴ：Oswald の太字を斜めに倒し（スキュー）、下にオレンジの帯を引いた文字だけのロゴ。
## 画像は使わず UI の描画だけで作る。play() で左から滑り込んで現れる（0.55 s）。

const WORD := "PARKOUR"
const SIZE_PX := 184
const SKEW := -0.2  ## 負で右に倒れる（上が右へずれる）
const BASELINE := 0.96  ## 文字の下端（フォントの大きさに対する比）

## 0→1：現れ方（1 = 出きった）
var reveal: float = 1.0:
	set(v):
		reveal = v
		queue_redraw()
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	var f := UITheme.heading_font()
	var w := f.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_PX).x
	return Vector2(ceilf(w) + 120.0, SIZE_PX * BASELINE + 48.0)


func play(duration: float = 0.55) -> void:
	if _tween != null:
		_tween.kill()
	reveal = 0.0
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_property(self, "reveal", 1.0, duration)


func _draw() -> void:
	var f := UITheme.heading_font()
	var tw := f.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_PX).x
	var e_text := _ease_out(clampf(reveal / 0.65, 0.0, 1.0))
	var e_bar := _ease_out(clampf((reveal - 0.25) / 0.75, 0.0, 1.0))
	var alpha := clampf(reveal * 3.0, 0.0, 1.0)
	var origin := Vector2(52.0 + lerpf(-110.0, 0.0, e_text), SIZE_PX * BASELINE)
	# 原点を文字の左下に置き、y を倒す（上のものほど右へずれる）
	draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(SKEW, 1), origin))
	# 影（右下に薄く）→ 白い縁（背景の3Dの上でも読める）→ 本体
	draw_string(f, Vector2(7, 8), WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_PX, Color(0, 0, 0, 0.2 * alpha))
	draw_string_outline(f, Vector2.ZERO, WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_PX, 14, Color(1, 1, 1, 0.9 * alpha))
	draw_string(f, Vector2.ZERO, WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE_PX, Color(UITheme.INK, alpha))
	# オレンジの帯：文字より左に突き出し、端は斜めに切る。細い帯がもう1本続く（走る線）
	var y0 := 22.0
	var h := 22.0
	var x0 := -44.0
	var x1 := x0 + (tw * 0.8 + 44.0) * e_bar
	_bar(x0, x1, y0, h, alpha)
	var d0 := tw * 0.8 + 22.0
	var d1 := d0 + (tw * 0.2 - 22.0) * clampf((e_bar - 0.35) / 0.65, 0.0, 1.0)
	if d1 > d0 + 2.0:
		_bar(d0, d1, y0, h, alpha)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _bar(xa: float, xb: float, y: float, h: float, alpha: float) -> void:
	if xb - xa < h:
		return
	var pts := PackedVector2Array([Vector2(xa + h, y), Vector2(xb + h, y), Vector2(xb, y + h), Vector2(xa, y + h)])
	var sh := pts.duplicate()
	for i: int in sh.size():
		sh[i] += Vector2(5, 6)
	draw_colored_polygon(sh, Color(0, 0, 0, 0.18 * alpha))
	draw_colored_polygon(pts, Color(UITheme.ACCENT, alpha))


static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)
