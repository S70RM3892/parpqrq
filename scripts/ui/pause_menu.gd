class_name PauseMenu
extends CanvasLayer
## 一時停止（仕様書 8章：「リトライ／チェックポイント／設定／終了」の4つだけ）。Start / Esc で開閉。

signal retry_requested
signal checkpoint_requested
signal quit_requested

## false の間は開かない（ゴール後の結果・リプレイ中）
var enabled: bool = true

var _root: Control
var _panel: PanelContainer
var _settings: SettingsMenu
var _first: Button


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 32)
	_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	v.custom_minimum_size.x = 520
	m.add_child(v)
	v.add_child(UITheme.label("Paused", 48))
	_first = UITheme.button("Retry", func() -> void:
		close()
		retry_requested.emit())
	v.add_child(_first)
	v.add_child(UITheme.button("Checkpoint", func() -> void:
		close()
		checkpoint_requested.emit()))
	v.add_child(UITheme.button("Settings", _open_settings))
	v.add_child(UITheme.button("Quit to courses", func() -> void:
		close()
		quit_requested.emit()))
	_settings = SettingsMenu.new()
	center.add_child(_settings)
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_panel.visible = true
		_first.grab_focus())
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if not enabled:
		return
	_root.visible = true
	_panel.visible = true
	_settings.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first.grab_focus.call_deferred()


func close() -> void:
	_root.visible = false
	get_tree().paused = false
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	_panel.visible = false
	_settings.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if _root.visible:
			if _settings.visible:
				_settings.close()
			else:
				Audio.ui(&"ui_back")
				close()
		else:
			open()
	elif _root.visible and _panel.visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.ui(&"ui_back")
		close()
