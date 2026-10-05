class_name LevelStyle
extends RefCounted
## 街の材質（仕様書 6章「アートディレクション」）。白とライトグレーが基調、ルートカラー（オレンジ）だけを差す。
## 材質はコース全体で共有する（描画の呼び出しを材質の数に抑える）。

enum Mat { WHITE, ROUTE, METAL, GLASS, GRAVEL, DARK, ACCENT, LIGHT, BUILDING, HAZARD }

const ROUTE_COLOR := Color("#FF6A1A")

## 材質ごとの足音の素材（コライダーのメタデータ "surface" になる）
const SURFACE: Dictionary[int, StringName] = {
	Mat.WHITE: &"concrete", Mat.ROUTE: &"concrete", Mat.METAL: &"metal", Mat.GLASS: &"glass",
	Mat.GRAVEL: &"gravel", Mat.DARK: &"concrete", Mat.ACCENT: &"concrete", Mat.LIGHT: &"metal",
	Mat.BUILDING: &"concrete", Mat.HAZARD: &"metal",
}

## 今の夜の度合い（シェーダー側のグローバル変数は実行中に読めないので、ここに持つ）
static var night_amount: float = 0.0

static var _cache: Dictionary[int, ShaderMaterial] = {}
static var _shader: Shader


static func material(mat: int) -> ShaderMaterial:
	if _cache.has(mat):
		return _cache[mat]
	if _shader == null:
		_shader = load("res://shaders/level.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	match mat:
		Mat.WHITE:
			_configure(m, 1, Color(0.93, 0.93, 0.91), 0.85, 0.0)
		Mat.ROUTE:
			_configure(m, 6, ROUTE_COLOR, 0.6, 0.0)
		Mat.METAL:
			_configure(m, 2, Color(0.70, 0.72, 0.75), 0.42, 0.5)
		Mat.GLASS:
			_configure(m, 3, Color(0.42, 0.52, 0.6), 0.05, 0.25)
		Mat.GRAVEL:
			_configure(m, 4, Color(0.74, 0.73, 0.70), 0.95, 0.0)
		Mat.DARK:
			_configure(m, 0, Color(0.17, 0.18, 0.2), 0.7, 0.1)
		Mat.ACCENT:
			_configure(m, 0, Color(0.3, 0.62, 0.8), 0.6, 0.0)
		Mat.LIGHT:
			_configure(m, 7, Color.WHITE, 0.5, 0.0)
			m.set_shader_parameter(&"emission_energy", 3.0)
		Mat.BUILDING:
			_configure(m, 5, Color(0.86, 0.86, 0.84), 0.85, 0.0)
		Mat.HAZARD:
			_configure(m, 8, Color(0.98, 0.78, 0.12), 0.6, 0.0)
	# 写真のテクスチャ（CC0、assets/textures/CREDITS.md）：明るさのムラ・粗さ・凹み・法線だけを足す。色は上の albedo のまま
	match mat:
		Mat.WHITE:
			_textures(m, "concrete", 2.0, 0.45, 0.55, "plaster", 1.6, 0.35)
			m.set_shader_parameter(&"grime", 0.6)
		Mat.BUILDING:
			_textures(m, "concrete", 2.0, 0.45, 0.55, "plaster", 1.6, 0.4)
			m.set_shader_parameter(&"grime", 1.0)
			m.set_shader_parameter(&"bevel_m", 0.05)
		Mat.ROUTE:
			_textures(m, "concrete_dirty", 2.0, 0.45, 0.4, "concrete_dirty", 2.0, 0.45)
			m.set_shader_parameter(&"grime", 0.7)
		Mat.METAL:
			_textures(m, "metal", 1.0, 0.5, 0.8, "corrugated", 2.0, 0.45)
		Mat.GRAVEL:
			_textures(m, "gravel", 2.1, 0.85, 1.0)
			m.set_shader_parameter(&"bevel_m", 0.0)
		Mat.DARK:
			_textures(m, "concrete_dirty", 2.0, 0.5, 0.5, "shutter", 1.2, 0.4)
		Mat.ACCENT:
			_textures(m, "shutter", 1.2, 0.35, 0.4, "shutter", 1.2, 0.35)
		Mat.HAZARD:
			_textures(m, "shutter", 1.2, 0.3, 0.4, "shutter", 1.2, 0.3)
		Mat.GLASS:
			m.set_shader_parameter(&"bevel_m", 0.015)
	_cache[mat] = m
	return m


## 写真のテクスチャを材質に付ける（上面用と、あれば側面用）。tile = 1枚の実寸 m、strength = 明るさのムラ、nrm = 法線の強さ
static func _textures(m: ShaderMaterial, top: String, tile: float, strength: float, nrm: float,
		side: String = "", side_tile: float = 2.0, side_strength: float = 0.0) -> void:
	m.set_shader_parameter(&"detail_tex", load("res://assets/textures/%s_detail.png" % top))
	m.set_shader_parameter(&"normal_tex", load("res://assets/textures/%s_normal.png" % top))
	m.set_shader_parameter(&"tile_m", tile)
	m.set_shader_parameter(&"detail_strength", strength)
	m.set_shader_parameter(&"normal_strength", nrm)
	m.set_shader_parameter(&"tex_rough", 1.0)
	if side != "":
		m.set_shader_parameter(&"side_detail_tex", load("res://assets/textures/%s_detail.png" % side))
		m.set_shader_parameter(&"side_normal_tex", load("res://assets/textures/%s_normal.png" % side))
		m.set_shader_parameter(&"side_tile_m", side_tile)
		m.set_shader_parameter(&"side_detail_strength", side_strength)


## エリアの差し色（屋内は1エリア1色：仕様書 6章）
static func set_accent(c: Color) -> void:
	material(Mat.ACCENT).set_shader_parameter(&"albedo", c)


## ルートカラーのON/OFF（上級者向け設定）と夜の度合いは全材質で共通（グローバルなシェーダー変数）
static func set_route_visible(on: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"route_strength", 1.0 if on else 0.0)


static func set_night(amount: float) -> void:
	night_amount = clampf(amount, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set(&"night", night_amount)


## 雨上がりの度合い（広い屋上に水たまり。level.gdshader）
static func set_wet(amount: float) -> void:
	RenderingServer.global_shader_parameter_set(&"wet", clampf(amount, 0.0, 1.0))


## 光を焼く時の面の色（線形）。シェーダーの模様（窓・縞・枠）をならした平均の色
static func bake_albedo(mat: int, tint: Color) -> Color:
	var m := material(mat)
	var a := (m.get_shader_parameter(&"albedo") as Color).srgb_to_linear()
	var t := Color(tint.r, tint.g, tint.b)
	match mat:
		Mat.ROUTE:
			a = ROUTE_COLOR.srgb_to_linear()
		Mat.BUILDING:
			a = a.lerp(Color(0.30, 0.36, 0.44).srgb_to_linear(), 0.3)  # 窓が3割
		Mat.HAZARD:
			a = a.lerp(Color(0.12, 0.12, 0.13).srgb_to_linear(), 0.5)  # 黒の縞が半分
		Mat.GLASS:
			a = a * 0.6
		Mat.LIGHT:
			a = Color(0.2, 0.2, 0.2)
	return Color(a.r * t.r, a.g * t.g, a.b * t.b)


## 光を焼く時に面が出す光（線形）。照明・ネオンは夜ほど強い（level.gdshader の pattern 7 と同じ）、ルートカラーは近くの淡い光
static func bake_emission(mat: int, tint: Color) -> Color:
	match mat:
		Mat.LIGHT:
			var e := 3.0 * lerpf(0.35, 1.0, night_amount)
			return Color(tint.r * e, tint.g * e, tint.b * e)
		Mat.ROUTE:
			var r := ROUTE_COLOR.srgb_to_linear() * (0.25 * (1.0 + night_amount * 1.2))  # 壁際の床がオレンジに染まる
			return Color(r.r, r.g, r.b)
	return Color(0, 0, 0)


static func _configure(m: ShaderMaterial, pattern: int, albedo: Color, roughness: float, metallic: float) -> void:
	m.set_shader_parameter(&"pattern", pattern)
	m.set_shader_parameter(&"albedo", albedo)
	m.set_shader_parameter(&"roughness_value", roughness)
	m.set_shader_parameter(&"metallic_value", metallic)
