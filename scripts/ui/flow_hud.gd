class_name FlowHUD
extends CanvasLayer
## 勢い値とPerfectの表示。
## - 勢い値：画面の縁がうっすらルートカラーで光る（数字は出さない）
## - Perfect：縁が一瞬強く光り、「PERFECT」が出て、0.04秒だけ0.2倍速になる（仕様書 4・5章）

const GLOW_MAX := 0.22      ## 勢い100%でも「うっすら」
const FLASH := 0.45
const FLASH_DECAY := 3.0      ## /s
const LABEL_TIME := 0.6       ## s
const BLINK_TIME := 0.15      ## s。戻った瞬間に白から戻す（瞬間移動を目立たせない。読み込み画面ではない）
const HOLD_WHITE := 0.35      ## リトライ長押しの溜め：チェックポイントへ戻る直前の白さ

@export var player: Player

var _flash: float = 0.0
var _label_t: float = 0.0
var _blink: float = 0.0

@onready var _edge: ColorRect = $Edge
@onready var _label: Label = $Perfect
@onready var _white: ColorRect = $Blink


func _ready() -> void:
	layer = 50
	_label.modulate.a = 0.0
	_white.visible = false
	player.perfect.connect(_on_perfect)
	player.respawned.connect(func(_to_start: bool) -> void: _blink = BLINK_TIME)


func _process(delta: float) -> void:
	# スローモーション中も見た目は実時間で進める
	var real := delta / maxf(Engine.time_scale, 0.01)
	_flash = maxf(_flash - FLASH_DECAY * real, 0.0)
	var glow := pow(player.momentum, 1.5) * GLOW_MAX + _flash
	(_edge.material as ShaderMaterial).set_shader_parameter(&"intensity", clampf(glow, 0.0, 1.0))
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
