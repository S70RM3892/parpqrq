class_name FlowHUD
extends CanvasLayer
## 走行中の画面演出（数字は出さない：仕様書 8章）。重ねる演出は screen_fx.gdshader の1枚にまとめる。
## - 勢い値：画面の縁がうっすらルートカラーで光る
## - Perfect：縁が一瞬強く光り、「PERFECT」が出て、0.04秒だけ0.2倍速になる（仕様書 4・5章）
## - スピードライン・速度ビネット：走り速度の1.07倍（仕様書の8 m/s相当）から出て、技の上限で最大（仕様書 6章）
## - 照準点（crosshair.gd）

const GLOW_MAX := 0.22      ## 勢い100%でも「うっすら」
const FLASH := 0.45
const FLASH_DECAY := 3.0      ## /s
const LABEL_TIME := 0.6       ## s
const BLINK_TIME := 0.15      ## s。戻った瞬間に白から戻す（瞬間移動を目立たせない。読み込み画面ではない）
const HOLD_WHITE := 0.35      ## リトライ長押しの溜め：チェックポイントへ戻る直前の白さ
const LINES_FROM := 1.07      ## 走り速度に対する倍率。仕様書の 8 m/s（走り7.5 m/s）に当たる
const VIGNETTE_MAX := 0.55

@export var player: Player

var _flash: float = 0.0
var _label_t: float = 0.0
var _blink: float = 0.0
var _line_time: float = 0.0
var _speed_k: float = 0.0

@onready var _edge: ColorRect = $Edge
@onready var _label: Label = $Perfect
@onready var _white: ColorRect = $Blink


func _ready() -> void:
	layer = 50
	_label.modulate.a = 0.0
	_white.visible = false
	player.perfect.connect(_on_perfect)
	var cross := Crosshair.new()
	cross.name = "Crosshair"
	cross.player = player
	add_child(cross)
	player.respawned.connect(func(_to_start: bool) -> void: _blink = BLINK_TIME)


func _process(delta: float) -> void:
	# スローモーション中も見た目は実時間で進める
	var real := delta / maxf(Engine.time_scale, 0.01)
	_flash = maxf(_flash - FLASH_DECAY * real, 0.0)
	var glow := pow(player.momentum, 1.5) * GLOW_MAX + _flash
	var prm := player.params
	var over := clampf((player.horizontal_speed() - prm.run_speed * LINES_FROM) / maxf(prm.max_flow_speed - prm.run_speed * LINES_FROM, 0.01), 0.0, 1.0)
	_speed_k = lerpf(_speed_k, over, 1.0 - exp(-5.0 * real))
	var lines := _speed_k * Settings.speed_lines_strength
	var vig := _speed_k * VIGNETTE_MAX * Settings.speed_lines_strength
	_line_time += real
	var mat := _edge.material as ShaderMaterial
	mat.set_shader_parameter(&"intensity", clampf(glow, 0.0, 1.0))
	mat.set_shader_parameter(&"lines", lines)
	mat.set_shader_parameter(&"vignette", vig)
	mat.set_shader_parameter(&"line_time", _line_time)
	mat.set_shader_parameter(&"line_color", Color(0.42, 0.47, 0.58, 0.6).lerp(Color(0.85, 0.9, 1.0, 0.45), LevelStyle.night_amount))
	var vp := get_viewport().get_visible_rect().size
	mat.set_shader_parameter(&"aspect", vp.x / maxf(vp.y, 1.0))
	# 何も出していない時は描かない（画面全体の読み書きを省く）
	_edge.visible = glow > 0.003 or lines > 0.003 or vig > 0.003
	if _label_t > 0.0:
		_label_t -= real
		_label.modulate.a = clampf(_label_t / LABEL_TIME * 2.0, 0.0, 1.0)
	# リトライ：長押しの間だけ白くなっていき、戻った瞬間は白から素早く戻る
	_blink = maxf(_blink - real, 0.0)
	var hold := clampf(player.retry_hold / Player.RETRY_HOLD, 0.0, 1.0) * HOLD_WHITE
	var white := maxf(_blink / BLINK_TIME, hold)
	_white.visible = white > 0.0
	_white.color.a = white


func _on_perfect(_kind: StringName) -> void:
	_flash = FLASH
	_label_t = LABEL_TIME
	Haptics.pulse(0.0, 0.7, 40.0)
	if Settings.hitstop_slowmo and player.params.perfect_slowmo_time > 0.0:
		Engine.time_scale = player.params.perfect_slowmo_scale
		# 実時間で戻す（time_scale の影響を受けないタイマー）
		var t := get_tree().create_timer(player.params.perfect_slowmo_time, true, false, true)
		t.timeout.connect(func() -> void: Engine.time_scale = 1.0)
