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
	_cache[mat] = m
	return m


## エリアの差し色（屋内は1エリア1色：仕様書 6章）
static func set_accent(c: Color) -> void:
	material(Mat.ACCENT).set_shader_parameter(&"albedo", c)


## ルートカラーのON/OFF（上級者向け設定）と夜の度合いは全材質で共通（グローバルなシェーダー変数）
static func set_route_visible(on: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"route_strength", 1.0 if on else 0.0)


static func set_night(amount: float) -> void:
	night_amount = clampf(amount, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set(&"night", night_amount)


static func _configure(m: ShaderMaterial, pattern: int, albedo: Color, roughness: float, metallic: float) -> void:
	m.set_shader_parameter(&"pattern", pattern)
	m.set_shader_parameter(&"albedo", albedo)
	m.set_shader_parameter(&"roughness_value", roughness)
	m.set_shader_parameter(&"metallic_value", metallic)
