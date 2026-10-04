extends CanvasLayer
## 手触りの調整パネル（F1 / コントローラーR3）。開いている間はゲームを止める。
## MovementParams の @export_range を自動で読み、スライダーを並べる（数値を足せば勝手に増える）。
## 保存先：エディタから実行 → res://resources/movement_default.tres（そのままコミットできる）
##         実機 → user://movement_tuned.tres（次回起動時に読み込まれる）

const DEFAULT_PATH := "res://resources/movement_default.tres"

const FEEL_TOGGLES: Array[Array] = [
	["feel_camera", "Layer: camera (bob / dip / tilt / speed FOV)"],
	["feel_body", "Layer: body (hands / legs)"],
	["feel_impact", "Layer: impact (screen shake)"],
	["feel_vibration", "Layer: vibration"],
]
const FEEL_SLIDERS: Array[Array] = [
	["fov", 75.0, 110.0, 1.0],
	["speed_fov_strength", 0.0, 1.0, 0.05],
	["head_bob_strength", 0.0, 1.0, 0.05],
	["screen_shake_strength", 0.0, 1.0, 0.05],
	["camera_tilt_strength", 0.0, 1.0, 0.05],
	["sensitivity_x", 0.1, 3.0, 0.05],
	["sensitivity_y", 0.1, 3.0, 0.05],
]

var _params: MovementParams
var _first_focus: Control
var _status: Label

@onready var _root: Control = $Root
@onready var _list: VBoxContainer = $Root/Panel/Margin/VBox/Scroll/List


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	($Root/Panel/Margin/VBox/Buttons/Save as Button).pressed.connect(_save)
	($Root/Panel/Margin/VBox/Buttons/Reset as Button).pressed.connect(_reset)
	($Root/Panel/Margin/VBox/Buttons/Close as Button).pressed.connect(_close)
	_status = $Root/Panel/Margin/VBox/Status


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_tuning"):
		if _root.visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()
	elif _root.visible and event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	var p := get_tree().get_first_node_in_group(&"player") as Player
	if p == null:
		return
	_params = p.params
	_rebuild()
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _first_focus != null:
		_first_focus.grab_focus()


func _close() -> void:
	_root.visible = false
	get_tree().paused = false
	Settings.apply()
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _rebuild() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	_first_focus = null
	_header("Feel layers (spec ch.4)")
	for t: Array in FEEL_TOGGLES:
		var cb := CheckBox.new()
		cb.text = t[1]
		cb.button_pressed = Settings.get(t[0])
		var key: String = t[0]
		cb.toggled.connect(func(on: bool) -> void: Settings.set(key, on))
		_list.add_child(cb)
		_first_focus = _first_focus if _first_focus != null else cb
	for s: Array in FEEL_SLIDERS:
		_slider(Settings, s[0], s[1], s[2], s[3])
	for prop: Dictionary in _params.get_property_list():
		if prop.usage & PROPERTY_USAGE_GROUP:
			_header(prop.name)
		elif prop.usage & PROPERTY_USAGE_EDITOR and prop.hint == PROPERTY_HINT_RANGE and prop.type in [TYPE_FLOAT, TYPE_INT]:
			var r: PackedStringArray = (prop.hint_string as String).split(",")
			var is_int: bool = prop.type == TYPE_INT
			_slider(_params, prop.name, float(r[0]), float(r[1]), float(r[2]) if r.size() > 2 else (1.0 if is_int else 0.01), is_int)


func _header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 22)
	l.add_theme_color_override(&"font_color", Color("#FF6A1A"))
	_list.add_child(l)


func _slider(target: Object, prop: String, lo: float, hi: float, step: float, is_int: bool = false) -> void:
	var row := HBoxContainer.new()
	var name_l := Label.new()
	name_l.text = prop
	name_l.custom_minimum_size.x = 300
	var value_l := Label.new()
	value_l.custom_minimum_size.x = 80
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = target.get(prop)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_ALL
	value_l.text = _fmt(sl.value)
	sl.value_changed.connect(func(v: float) -> void:
		target.set(prop, roundi(v) if is_int else v)
		value_l.text = _fmt(v))
	row.add_child(name_l)
	row.add_child(sl)
	row.add_child(value_l)
	_list.add_child(row)
	_first_focus = _first_focus if _first_focus != null else sl


func _fmt(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".")


func _save() -> void:
	Settings.save_settings()
	var path := DEFAULT_PATH if OS.has_feature("editor") else Player.TUNED_PATH
	var err := ResourceSaver.save(_params, path)
	_status.text = ("saved: %s" % path) if err == OK else ("save failed: %s" % error_string(err))


func _reset() -> void:
	var fresh := MovementParams.new()
	for prop: Dictionary in fresh.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			_params.set(prop.name, fresh.get(prop.name))
	_rebuild()
	_status.text = "reset to spec defaults (not saved yet)"
	if _first_focus != null:
		_first_focus.grab_focus()
