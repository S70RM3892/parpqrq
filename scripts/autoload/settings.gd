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

# 手触りの4層（仕様書 4章）。どれが気持ちよさに効き、どれが酔いの原因かを切り分ける
var feel_camera: bool = true          ## ボブ・着地ディップ・傾き・速度FOV
var feel_body: bool = true            ## 手と脚の表示
var feel_impact: bool = true          ## 画面揺れ
var feel_vibration: bool = true       ## コントローラー振動

# 性能
var max_fps: int = 60                 ## 60 / 90 / 120
var render_scale: float = 1.0         ## 0.7〜1.0
## 0 = 低（影は近くだけ・グローなし・風の粒を減らす）、1 = 高（グローあり：仕様書 6章「強度を抑えて高設定のみ」）
var graphics_quality: int = 1

# 見た目
## ルートカラー（使える足場・壁・縁のオレンジ）。上級者向けにOFFにできる。OFFでクリアするとメダルに印が付く
var route_color: bool = true
## 走っている間ずっとタイムを右上に出す（既定はOFF：走行中は文字を出さない方針。タイムアタックしたい人向け）
var run_timer: bool = false

# 音量 0.0〜1.0
var volume_master: float = 1.0
var volume_music: float = 0.8
var volume_sfx: float = 1.0

## 初回起動の「酔いやすい方向け」プリセットを選んだか
var first_run_done: bool = false

const _KEYS: PackedStringArray = [
	"fov", "sensitivity_x", "sensitivity_y", "invert_y",
	"speed_fov_strength", "head_bob_strength", "screen_shake_strength",
	"camera_tilt_strength", "speed_lines_strength", "center_dot", "hitstop_slowmo",
	"feel_camera", "feel_body", "feel_impact", "feel_vibration",
	"max_fps", "render_scale", "graphics_quality", "route_color", "run_timer",
	"volume_master", "volume_music", "volume_sfx", "first_run_done",
]


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	Engine.max_fps = max_fps
	get_viewport().scaling_3d_scale = clampf(render_scale, 0.7, 1.0)
	# 画質「高」は MSAA 4x（電線・手すり・縁のギザギザを消す。タイル型のモバイルGPUでは安い）
	get_viewport().msaa_3d = Viewport.MSAA_4X if graphics_quality >= 1 else Viewport.MSAA_DISABLED
	LevelStyle.set_route_visible(route_color)
	_set_bus_volume(&"Master", volume_master)
	_set_bus_volume(&"Music", volume_music)
	_set_bus_volume(&"SFX", volume_sfx)
	changed.emit()


## 酔いやすい方向け（仕様書 8章）：揺れ系を全部30%、画面中央の固定ドットON
func apply_comfort_preset() -> void:
	speed_fov_strength = 0.3
	head_bob_strength = 0.3
	screen_shake_strength = 0.3
	camera_tilt_strength = 0.3
	speed_lines_strength = 0.3
	center_dot = true
	apply()


## 仕様書 8章の初期値に戻す（視点の感度・音量・画質はそのまま）
func apply_default_preset() -> void:
	fov = 90.0
	speed_fov_strength = 1.0
	head_bob_strength = 0.7
	screen_shake_strength = 1.0
	camera_tilt_strength = 1.0
	speed_lines_strength = 1.0
	center_dot = false
	hitstop_slowmo = true
	apply()


func _set_bus_volume(bus: StringName, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


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
