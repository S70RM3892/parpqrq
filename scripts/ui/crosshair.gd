class_name Crosshair
extends Control
## 照準点（仕様書 8章）：小さな点1つ。技が使える時だけ少し広がる。
## 「画面中央の固定ドット」設定（酔い対策）がONなら常に出す。OFFなら技が使える時だけ浮かび上がる。

const DOT := 3.0        ## px（1080p基準）
const OPEN := 7.0       ## 技が使える時のリングの半径
const RATE := 18.0

var player: Player

var _open: float = 0.0
var _alpha: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if player == null:
		return
	var avail := 1.0 if player.move_hint != &"" else 0.0
	var w := 1.0 - exp(-RATE * delta)
	_open = lerpf(_open, avail, w)
	var target := 0.85 if Settings.center_dot else avail * 0.7
	_alpha = lerpf(_alpha, target, w)
	queue_redraw()


func _draw() -> void:
	if _alpha < 0.01:
		return
	var k := size.y / 1080.0
	var c := size * 0.5
	var col := Color(1, 1, 1, _alpha)
	var shadow := Color(0, 0, 0, _alpha * 0.45)
	draw_circle(c, (DOT + 1.2) * k, shadow)
	draw_circle(c, DOT * k, col)
	if _open > 0.02:
		var r := lerpf(DOT, OPEN, _open) * k
		draw_arc(c, r + 1.5 * k, 0.0, TAU, 32, Color(LevelStyle.ROUTE_COLOR, _alpha * _open), 2.0 * k, true)
