class_name FocusButton
extends Button
## 選んでいるボタンの強調：左にオレンジの帯が伸びて、ひと跳ねする（0.2 s）。
## 見た目の地（黒地に白文字）は UITheme の focus スタイル。ここは動きだけ。

const BAR_WIDTH := 7.0
const BAR_INSET := 14.0

var _bar: ColorRect
var _tween: Tween
var _pop: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	_bar = ColorRect.new()
	_bar.color = UITheme.ACCENT
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size = Vector2(BAR_WIDTH, 0.0)
	add_child(_bar)
	resized.connect(_on_resized)
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	_on_resized()
	if has_focus():
		_bar_height(1.0)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	_bar_height(_bar.size.y / maxf(size.y - BAR_INSET * 2.0, 1.0))


func _on_focus(on: bool) -> void:
	if _tween != null:
		_tween.kill()
	if _pop != null:
		_pop.kill()
	_tween = create_tween().set_ignore_time_scale(true)
	if on:
		_tween.tween_method(_bar_height, _bar_t(), 1.0, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		scale = Vector2.ONE
		_pop = create_tween().set_ignore_time_scale(true)
		_pop.tween_property(self, "scale", Vector2(1.035, 1.035), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_pop.tween_property(self, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_method(_bar_height, _bar_t(), 0.0, 0.1)
		scale = Vector2.ONE


func _bar_t() -> float:
	return _bar.size.y / maxf(size.y - BAR_INSET * 2.0, 1.0)


## t = 0（無し）〜 1（ボタンの高さいっぱい）。中央から上下に伸びる
func _bar_height(t: float) -> void:
	var full := maxf(size.y - BAR_INSET * 2.0, 0.0)
	var h := full * clampf(t, 0.0, 1.0)
	_bar.size = Vector2(BAR_WIDTH, h)
	_bar.position = Vector2(8.0, (size.y - h) * 0.5)
