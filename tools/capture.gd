extends Node
## 画面を撮る（見た目の確認用）。オートロードが読まれるよう、普通に起動する:
##   godot --path . res://tools/capture.tscn -- --scene=res://scenes/levels/test_course.tscn --out=/tmp/shot --at=1.0,3.0 [--forward]
## --at の秒数ごとに <out>_<n>.png を保存して終了する。--forward で前進を押し続ける。
## ディスプレイが無い環境では xvfb-run で包む。

var _out: String = "user://capture"
var _at: PackedFloat32Array = [1.0]
var _t: float = 0.0
var _n: int = 0


func _ready() -> void:
	var scene_path := "res://scenes/levels/test_course.tscn"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.trim_prefix("--scene=")
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--at="):
			_at = PackedFloat32Array(Array(a.trim_prefix("--at=").split(",")).map(func(s: String) -> float: return s.to_float()))
		elif a == "--forward":
			Input.action_press(&"move_forward")
	DebugOverlay.visible = false
	add_child((load(scene_path) as PackedScene).instantiate())


func _process(delta: float) -> void:
	_t += delta
	if _n < _at.size() and _t >= _at[_n]:
		var img := get_viewport().get_texture().get_image()
		var path := "%s_%d.png" % [_out, _n]
		img.save_png(path)
		print("capture: ", path)
		_n += 1
		if _n >= _at.size():
			get_tree().quit()
