extends Node
## プレイヤー設定（仕様書 8章「酔い対策」）。user://settings.cfg に保存する。
## 手触りの数値（MovementParams）とは分ける。ここは「好み」で変える値だけ。

signal changed

const PATH := "user://settings.cfg"

# 視点
var fov: float = 90.0                 ## 75〜110°
var sensitivity_x: float = 1.0        ## 0.1〜3.0
var sensitivity_y: float = 1.0        ## 0.1〜3.0
var invert_y: bool = false

# 演出の強さ 0.0〜1.0（M1以降の各カメラ層が参照する）
var speed_fov_strength: float = 1.0
var head_bob_strength: float = 0.7
var screen_shake_strength: float = 1.0
var camera_tilt_strength: float = 1.0
var speed_lines_strength: float = 1.0
var center_dot: bool = false
var hitstop_slowmo: bool = true

# 性能
var max_fps: int = 60                 ## 60 / 90 / 120
var render_scale: float = 1.0         ## 0.7〜1.0

const _KEYS: PackedStringArray = [
	"fov", "sensitivity_x", "sensitivity_y", "invert_y",
	"speed_fov_strength", "head_bob_strength", "screen_shake_strength",
	"camera_tilt_strength", "speed_lines_strength", "center_dot", "hitstop_slowmo",
	"max_fps", "render_scale",
]


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	Engine.max_fps = max_fps
	get_viewport().scaling_3d_scale = clampf(render_scale, 0.7, 1.0)
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in _KEYS:
		set(k, cfg.get_value("settings", k, get(k)))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k: String in _KEYS:
		cfg.set_value("settings", k, get(k))
	cfg.save(PATH)
