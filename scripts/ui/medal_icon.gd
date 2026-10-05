class_name MedalIcon
extends Control
## メダルの印：金属の円盤（縁・放射状のグラデーション・つや・刻印の1字）。ティアごとに色と形が違う
## （BRONZE / SILVER / GOLD は丸、ACE は白金で外に輪、DEV はルートカラーのオレンジで歯車の縁）。
## ルートカラーOFFでクリアしていれば右上に小さな菱形（仕様書 6章）。
## flash（0→1）は結果のスタンプで広がる輪と閃光。

var medal: String = "":
	set(v):
		medal = v
		queue_redraw()
var route_off: bool = false:
	set(v):
		route_off = v
		queue_redraw()
var flash: float = 0.0:
	set(v):
		flash = v
		queue_redraw()

static var _tex: Dictionary[String, GradientTexture2D] = {}


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 円盤の模様のグラデーション（色ごとに1回だけ作る）
static func _gradient(key: String, cols: Array[Color], offs: PackedFloat32Array, radial: bool, from: Vector2, to: Vector2) -> GradientTexture2D:
	if _tex.has(key):
		return _tex[key]
	var g := Gradient.new()
	g.offsets = offs
	g.colors = PackedColorArray(cols)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	t.fill_from = from
	t.fill_to = to
	_tex[key] = t
	return t


## 半径 rad の円（歯車なら縁が波打つ）をテクスチャ付きで塗る
func _disc(c: Vector2, rad: float, tex: Texture2D, teeth: int = 0) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var n := 96
	for i: int in n:
		var a := TAU * i / n
		var rr := rad * (1.0 + (0.05 * clampf(cos(a * teeth) * 3.0, -1.0, 1.0) if teeth > 0 else 0.0))
		var p := c + Vector2(cos(a), sin(a)) * rr
		pts.append(p)
		uvs.append((p - c) / (rad * 2.0) + Vector2(0.5, 0.5))
	draw_colored_polygon(pts, Color.WHITE, uvs, tex)


func _draw() -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y)
	var r := s * 0.42
	if medal == "":
		draw_arc(c, r * 0.9, 0.0, TAU, 40, Color(0, 0, 0, 0.18), maxf(s * 0.05, 2.0), true)
		draw_circle(c, r * 0.12, Color(0, 0, 0, 0.18))
		_draw_route_off(c, r, s)
		return
	var tones: Array = UITheme.MEDAL_TONES.get(medal, UITheme.MEDAL_TONES["SILVER"])
	var light: Color = tones[0]
	var base: Color = tones[1]
	var dark: Color = tones[2]
	var teeth := 12 if medal == "DEV" else 0
	var px := maxf(s / 84.0, 0.5)  # 84 px を基準にした太さ
	# 影
	draw_circle(c + Vector2(0, r * 0.09), r * 1.04, Color(0, 0, 0, 0.14))
	draw_circle(c + Vector2(0, r * 0.06), r * 1.0, Color(0, 0, 0, 0.16))
	# ACE：外に細い輪（白金の光）
	if medal == "ACE":
		draw_arc(c, r * 1.13, 0.0, TAU, 64, Color(light.r, light.g, light.b, 0.55), 2.5 * px, true)
	# 縁（左上が明るく右下が暗い）
	var rim := _gradient(medal + "_rim", [light, base, dark], PackedFloat32Array([0.0, 0.5, 1.0]), false, Vector2(0.15, 0.05), Vector2(0.85, 0.95))
	_disc(c, r, rim, teeth)
	if teeth == 0:
		draw_arc(c, r, 0.0, TAU, 72, dark.darkened(0.2), 1.6 * px, true)
	# 縁の内側の溝（暗い線の下に明るい線）
	draw_arc(c, r * 0.86, 0.0, TAU, 56, Color(dark.r, dark.g, dark.b, 0.7), 2.0 * px, true)
	draw_arc(c + Vector2(0.9, 0.9) * px, r * 0.86, 0.0, TAU, 56, Color(1, 1, 1, 0.35), 1.4 * px, true)
	# 面（中心の左上に光が当たる放射状）
	var face := _gradient(medal + "_face", [light.lerp(Color.WHITE, 0.25), base, dark.lerp(base, 0.35)], PackedFloat32Array([0.0, 0.5, 0.95]),
			true, Vector2(0.36, 0.3), Vector2(0.96, 0.9))
	_disc(c, r * 0.8, face)
	# 刻印の1字（明るい縁取りを右下にずらして彫ったように）
	var font := UITheme.heading_font()
	var glyph: String = UITheme.MEDAL_GLYPHS.get(medal, "")
	var fs := int(r * 1.05)
	var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var gp := Vector2(c.x - gw * 0.5, c.y + font.get_ascent(fs) * 0.5 - r * 0.07)
	var ink := dark.darkened(0.25)
	ink.a = 0.9
	draw_string(font, gp + Vector2(1.2, 1.4) * px, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.45))
	draw_string(font, gp, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# つや（上半分に白のグラデーション）と光の点
	var gloss := PackedVector2Array()
	var gcols := PackedColorArray()
	var gc := c + Vector2(-r * 0.04, -r * 0.34)
	for i: int in 40:
		var a := TAU * i / 40.0
		gloss.append(gc + Vector2(cos(a) * r * 0.58, sin(a) * r * 0.36))
		gcols.append(Color(1, 1, 1, 0.5 * (0.5 - 0.5 * sin(a))))
	draw_polygon(gloss, gcols)
	draw_circle(c + Vector2(-r * 0.46, -r * 0.5), r * 0.055, Color(1, 1, 1, 0.85))
	_draw_route_off(c, r, s)
	# スタンプの輪と閃光
	if flash > 0.0 and flash < 1.0:
		var k := 1.0 - flash
		draw_arc(c, r * (1.05 + 0.9 * flash), 0.0, TAU, 72, Color(light.r, light.g, light.b, k * 0.9), lerpf(9.0, 1.5, flash) * px, true)
		draw_arc(c, r * (1.0 + 0.5 * flash), 0.0, TAU, 72, Color(1, 1, 1, k * k * 0.7), lerpf(5.0, 1.0, flash) * px, true)
		draw_circle(c, r * 0.98, Color(1, 1, 1, k * k * k * 0.45))


func _draw_route_off(c: Vector2, r: float, s: float) -> void:
	if not route_off:
		return
	var p := c + Vector2(r * 0.88, -r * 0.88)
	var d := s * 0.12
	var pts := PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)])
	draw_colored_polygon(pts, UITheme.INK)
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.9), 1.5, true)
