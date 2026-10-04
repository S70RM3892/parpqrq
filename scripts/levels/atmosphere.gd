class_name Atmosphere
extends Node3D
## 空・太陽・霧・トーン（仕様書 6章「ライティング」「ポストプロセス」）。時間帯はコースごとに固定。
## - 主光源は太陽1灯。リアルタイムの影は近距離だけ、カスケード2段
## - 間接光は空から（LightmapGI の代わり。コースは実行時に組むので焼けない。接地の陰は level.gdshader で描く）
## - 高さフォグで足元の谷を白く飛ばし、高所の怖さを出す（fog_floor より下ほど濃い）
## - グローは画質「高」のときだけ、強度を抑えて
## 子ノード（WorldEnvironment・太陽・雲）は _ready で作る。

const PRESETS: Dictionary[StringName, Dictionary] = {
	&"morning": {
		"top": Color(0.34, 0.56, 0.86), "horizon": Color(0.98, 0.88, 0.78), "ground": Color(0.86, 0.84, 0.8),
		"sun": Color(1.0, 0.87, 0.7), "sun_energy": 1.5, "elevation": 22.0, "azimuth": 55.0,
		"ambient": 0.9, "fog": Color(0.96, 0.9, 0.84), "fog_end": 260.0, "fog_max": 0.9,
		"exposure": 1.0, "contrast": 1.05, "saturation": 1.05, "night": 0.0, "stars": 0.0, "wet": 0.3,
		"cloud": Color(1.0, 0.97, 0.94, 0.85), "cloud_shade": Color(0.86, 0.8, 0.8), "coverage": 0.52,
	},
	&"noon": {
		"top": Color(0.28, 0.5, 0.86), "horizon": Color(0.86, 0.9, 0.95), "ground": Color(0.8, 0.82, 0.84),
		"sun": Color(1.0, 0.97, 0.92), "sun_energy": 1.7, "elevation": 58.0, "azimuth": 25.0,
		"ambient": 0.85, "fog": Color(0.88, 0.91, 0.95), "fog_end": 280.0, "fog_max": 0.85,
		"exposure": 0.95, "contrast": 1.08, "saturation": 1.0, "night": 0.0, "stars": 0.0, "wet": 0.0,
		"cloud": Color(1.0, 1.0, 1.0, 0.9), "cloud_shade": Color(0.8, 0.83, 0.88), "coverage": 0.48,
	},
	&"evening": {
		"top": Color(0.22, 0.24, 0.5), "horizon": Color(1.0, 0.6, 0.38), "ground": Color(0.45, 0.36, 0.4),
		"sun": Color(1.0, 0.58, 0.32), "sun_energy": 1.3, "elevation": 9.0, "azimuth": -35.0,
		"ambient": 0.75, "fog": Color(0.95, 0.66, 0.55), "fog_end": 240.0, "fog_max": 0.9,
		"exposure": 1.05, "contrast": 1.08, "saturation": 1.12, "night": 0.35, "stars": 0.0, "wet": 0.12,
		"cloud": Color(1.0, 0.72, 0.55, 0.85), "cloud_shade": Color(0.55, 0.42, 0.55), "coverage": 0.5,
	},
	&"night": {
		"top": Color(0.015, 0.02, 0.06), "horizon": Color(0.13, 0.12, 0.24), "ground": Color(0.04, 0.04, 0.07),
		"sun": Color(0.6, 0.7, 1.0), "sun_energy": 0.35, "elevation": 38.0, "azimuth": 140.0,
		"ambient": 0.62, "fog": Color(0.1, 0.1, 0.19), "fog_end": 220.0, "fog_max": 0.95,
		"exposure": 1.2, "contrast": 1.05, "saturation": 1.1, "night": 1.0, "stars": 1.0, "wet": 0.72,
		"cloud": Color(0.2, 0.2, 0.32, 0.6), "cloud_shade": Color(0.1, 0.1, 0.16), "coverage": 0.56,
	},
}

## エリアの中の進み（0 = エリアの1本目 〜 1 = 4本目）。同じ時間帯の中で時刻が進む：
## 朝は夜明け→朝、昼は昼前→昼過ぎ、夕方は黄金の時間→日没、夜は宵→深夜（コースごとに見た目が変わる）
const LATE: Dictionary[StringName, Dictionary] = {
	&"morning": {"elevation": 34.0, "sun_energy": 1.65, "sun": Color(1.0, 0.93, 0.82), "horizon": Color(0.95, 0.9, 0.84),
			"fog": Color(0.94, 0.92, 0.88), "top": Color(0.3, 0.54, 0.88), "exposure": 0.88, "contrast": 1.12, "fog_max": 0.8, "wet": 0.12},
	&"noon": {"elevation": 66.0, "azimuth": -15.0, "coverage": 0.44},
	&"evening": {"elevation": 2.5, "sun_energy": 0.95, "sun": Color(1.0, 0.45, 0.25), "top": Color(0.14, 0.13, 0.36),
			"horizon": Color(0.95, 0.45, 0.32), "fog": Color(0.75, 0.45, 0.45), "night": 0.6, "ambient": 0.62,
			"cloud": Color(0.95, 0.55, 0.45, 0.85), "cloud_shade": Color(0.38, 0.28, 0.42), "wet": 0.3},
	&"night": {"horizon": Color(0.08, 0.08, 0.17), "ambient": 0.55, "exposure": 1.15, "wet": 0.9},
}
const EARLY: Dictionary[StringName, Dictionary] = {
	&"morning": {"elevation": 9.0, "sun_energy": 1.3, "sun": Color(1.0, 0.72, 0.5), "horizon": Color(1.0, 0.78, 0.62),
			"fog": Color(0.98, 0.84, 0.74), "top": Color(0.38, 0.52, 0.8), "cloud": Color(1.0, 0.85, 0.75, 0.85), "wet": 0.5},
	&"noon": {"elevation": 50.0, "azimuth": 45.0},
	&"evening": {"elevation": 16.0, "sun_energy": 1.45, "sun": Color(1.0, 0.7, 0.4), "night": 0.2, "top": Color(0.28, 0.32, 0.58),
			"horizon": Color(1.0, 0.72, 0.45), "wet": 0.0},
	&"night": {"horizon": Color(0.2, 0.16, 0.3), "ambient": 0.68, "wet": 0.55},
}

@export var preset: StringName = &"morning"
@export_range(0.0, 1.0) var step: float = 0.5
## これより下ほど霧が濃い（谷底の街を白く飛ばす）。-1000 で無効
@export var fog_floor: float = -1000.0
@export var fog_floor_density: float = 0.05

var environment: Environment
var sun: DirectionalLight3D

var _clouds: MeshInstance3D
var _sky_mat: ShaderMaterial


## 時間帯と進み（0〜1）の空の設定。EARLY（0）→ PRESETS（0.5）→ LATE（1）を補間する（光を焼く道具も使う）
static func preset_for(time: StringName, at: float) -> Dictionary:
	var base: Dictionary = PRESETS.get(time, PRESETS[&"morning"])
	var other: Dictionary = (LATE if at >= 0.5 else EARLY).get(time, {})
	var k := absf(at - 0.5) * 2.0
	var out := base.duplicate()
	for key: String in other:
		var a: Variant = base[key]
		var b: Variant = other[key]
		if a is Color:
			out[key] = (a as Color).lerp(b as Color, k)
		else:
			out[key] = lerpf(float(a), float(b), k)
	return out


## コースの id（"3-4" など）からエリアの中の進み（0〜1）。それ以外は 0.5
static func step_for(id: String) -> float:
	var parts := id.split("-")
	if parts.size() == 2 and parts[1].is_valid_int():
		return clampf((parts[1].to_int() - 1) / 3.0, 0.0, 1.0)
	return 0.5


func _ready() -> void:
	var p: Dictionary = preset_for(preset, step)
	environment = Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	# 空の放射輝度マップは一度だけ作る（毎フレーム作り直さない）
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 影が空の青に染まりすぎないよう、空の寄与を少し落として中間色を混ぜる
	environment.ambient_light_sky_contribution = 0.7
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	# AgX：明るい白が飛ばずに色味を保つ（白い街の日向が真っ白に潰れない）
	environment.tonemap_agx_white = 10.0
	environment.tonemap_agx_contrast = 1.35
	environment.adjustment_enabled = true
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 30.0
	environment.fog_depth_curve = 1.4
	environment.fog_sky_affect = 0.35
	environment.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = false
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.8  # 低い朝日で広い床に斜めの縞（シャドウアクネ）が出ないように
	add_child(sun)

	_clouds = MeshInstance3D.new()
	_clouds.name = "Clouds"
	var dome := SphereMesh.new()
	dome.radius = 330.0
	dome.height = 330.0
	dome.is_hemisphere = true
	dome.radial_segments = 64
	dome.rings = 32  # 粗いと地平線の少し上に輪の継ぎ目が見える
	_clouds.mesh = dome
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.top_level = true
	var cm := ShaderMaterial.new()
	cm.shader = load("res://shaders/clouds.gdshader")
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 4
	tex.noise = fn
	cm.set_shader_parameter(&"noise", tex)
	_clouds.material_override = cm
	add_child(_clouds)

	apply_preset(p)
	Settings.changed.connect(_apply_quality)
	_apply_quality()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_clouds.global_position = cam.global_position


func apply_preset(p: Dictionary) -> void:
	var e := environment
	_sky_mat.set_shader_parameter(&"top_color", p.top)
	_sky_mat.set_shader_parameter(&"horizon_color", p.horizon)
	_sky_mat.set_shader_parameter(&"ground_color", p.ground)
	_sky_mat.set_shader_parameter(&"sun_color", p.sun)
	_sky_mat.set_shader_parameter(&"stars", p.stars)
	# 方位は進行方向（-Z）から右回りの角度
	var elev := deg_to_rad(p.elevation as float)
	var az := deg_to_rad(p.azimuth as float)
	var to_sun := Vector3(sin(az) * cos(elev), sin(elev), -cos(az) * cos(elev))
	_sky_mat.set_shader_parameter(&"sun_dir", to_sun)
	sun.light_color = p.sun
	sun.light_energy = p.sun_energy
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	e.ambient_light_energy = p.ambient
	e.ambient_light_color = (p.horizon as Color).lerp(Color(0.8, 0.8, 0.8), 0.5)
	e.fog_light_color = p.fog
	e.fog_depth_end = p.fog_end
	e.fog_density = p.fog_max
	if fog_floor > -999.0:
		e.fog_height = fog_floor
		e.fog_height_density = fog_floor_density
	e.tonemap_exposure = p.exposure
	e.adjustment_contrast = p.contrast
	e.adjustment_saturation = p.saturation
	# 光るもの（太陽・看板・ネオン・窓）だけが柔らかく滲む。広い段まで使って太陽のまわりに大きな光の輪
	e.glow_intensity = 0.7
	e.glow_strength = 1.0
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.1
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for lv: int in 7:
		e.set_glow_level(lv, [0.0, 1.0, 0.8, 0.6, 0.5, 0.35, 0.0][lv])
	var cm := _clouds.material_override as ShaderMaterial
	cm.set_shader_parameter(&"cloud_color", p.cloud)
	cm.set_shader_parameter(&"shade_color", p.cloud_shade)
	cm.set_shader_parameter(&"coverage", p.coverage)
	cm.set_shader_parameter(&"sun_color", p.sun)
	cm.set_shader_parameter(&"sun_dir", to_sun)
	LevelStyle.set_night(p.night)
	LevelStyle.set_wet(p.wet)


## 画質：影の距離・グロー（仕様書 6章）
func _apply_quality() -> void:
	var high := Settings.graphics_quality >= 1
	environment.glow_enabled = high
	sun.directional_shadow_max_distance = 60.0 if high else 32.0
	sun.directional_shadow_split_1 = 0.25 if high else 0.35
