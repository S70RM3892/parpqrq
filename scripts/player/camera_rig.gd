class_name CameraRig
extends Node3D
## 1人称カメラリグ（仕様書 4章）。
## 体に直付けせず top_level で目の位置に追従させる。視点回転は入力を受けたフレームで即反映し、
## 物理補間の1tick遅れを視点に乗せない（入力→画面 3フレーム以内）。
## 演出は層ごとのノードに分け、層単位でON/OFFできる:
##   CameraRig(yaw) > Pitch > Bob > Dip > Tilt > Shake > Camera3D

const MOUSE_DEG_PER_PX := 0.08
const STICK_DEG_PER_SEC := 220.0
const PITCH_LIMIT_DEG := 89.0
const LAYER_NAMES: Array[StringName] = [&"bob", &"dip", &"tilt", &"shake"]

## 目の位置。Player の EyeAnchor を指す
@export var eye: Node3D

var yaw: float = 0.0
var pitch: float = 0.0

var _layers: Dictionary[StringName, Node3D] = {}
var _layer_enabled: Dictionary[StringName, bool] = {}

@onready var _pitch: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Bob/Dip/Tilt/Shake/Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_layers = {
		&"bob": $Pitch/Bob,
		&"dip": $Pitch/Bob/Dip,
		&"tilt": $Pitch/Bob/Dip/Tilt,
		&"shake": $Pitch/Bob/Dip/Tilt/Shake,
	}
	for n: StringName in LAYER_NAMES:
		_layer_enabled[n] = true
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var d: Vector2 = mm.screen_relative * MOUSE_DEG_PER_PX
		_add_look(-d.x * Settings.sensitivity_x, -d.y * Settings.sensitivity_y * _invert())
	elif event is InputEventMouseButton and event.is_pressed():
		_capture_mouse(true)
	elif event.is_action_pressed(&"pause"):
		_capture_mouse(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_capture_mouse(false)


func _process(delta: float) -> void:
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO:
		# 2乗カーブ：小さく倒した時の微調整をしやすくする
		stick *= stick.length()
		var step := STICK_DEG_PER_SEC * delta
		_add_look(-stick.x * step * Settings.sensitivity_x, -stick.y * step * Settings.sensitivity_y * _invert())
	if eye != null:
		global_position = eye.get_global_transform_interpolated().origin


## 向きを即座に合わせる（リスポーン等）
func snap(new_yaw: float, new_pitch: float = 0.0) -> void:
	yaw = new_yaw
	pitch = new_pitch
	_apply_rotation()
	if eye != null:
		global_position = eye.global_position


func set_layer_enabled(layer: StringName, on: bool) -> void:
	_layer_enabled[layer] = on
	if not on:
		_layers[layer].transform = Transform3D.IDENTITY


func is_layer_enabled(layer: StringName) -> bool:
	return _layer_enabled.get(layer, false)


## 各演出層のノード。M1でボブ・着地ディップ・傾き・揺れがここに値を書く
func layer(layer_name: StringName) -> Node3D:
	return _layers[layer_name]


func _add_look(yaw_deg: float, pitch_deg: float) -> void:
	yaw = wrapf(yaw + deg_to_rad(yaw_deg), -PI, PI)
	pitch = clampf(pitch + deg_to_rad(pitch_deg), deg_to_rad(-PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch.rotation = Vector3(pitch, 0.0, 0.0)


func _invert() -> float:
	return -1.0 if Settings.invert_y else 1.0


func _apply_settings() -> void:
	camera.fov = clampf(Settings.fov, 75.0, 110.0)


func _capture_mouse(on: bool) -> void:
	if OS.has_feature("mobile"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
