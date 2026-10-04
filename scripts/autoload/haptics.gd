extends Node
## コントローラー振動（仕様書 4章「振動」）。最後に触ったコントローラーを鳴らす。
## 表の「低周波モーター」= Godotの strong、「高周波モーター」= weak。

var _device: int = -1


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_device = event.device


## low, high = 0〜1、ms = 長さ
func pulse(low: float, high: float, ms: float) -> void:
	if not Settings.feel_vibration:
		return
	var dev := _device
	if dev < 0:
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			return
		dev = pads[0]
	Input.start_joy_vibration(dev, high, low, ms / 1000.0)


func step() -> void:
	pulse(0.0, 0.08, 30.0)


func land() -> void:
	pulse(0.3, 0.2, 80.0)


func hard_land() -> void:
	pulse(0.9, 0.5, 200.0)


func grab() -> void:
	pulse(0.2, 0.6, 60.0)
