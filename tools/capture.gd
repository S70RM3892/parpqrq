extends Node
## 画面を撮る（見た目の確認用）。オートロードが読まれるよう、普通に起動する:
##   godot --path . res://tools/capture.tscn -- --scene=res://scenes/levels/test_course.tscn --out=/tmp/shot --at=1.0,3.0 [--forward]
## --at の秒数ごとに <out>_<n>.png を保存して終了する。--forward で前進を押し続ける。--speed=14 で前へ押し出す。--pos=x,y,z で置き直す。
## ディスプレイが無い環境では xvfb-run で包む。

var _out: String = "user://capture"
var _at: PackedFloat32Array = [1.0]
var _t: float = 0.0
var _n: int = 0
var _speed: float = 0.0  ## >0 なら前へこの速さで押し出す（スピード表現の確認用）
var _pos: Vector3 = Vector3.INF  ## 置き直す位置（--pos=x,y,z）


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
		elif a.begins_with("--pos="):
			var v := a.trim_prefix("--pos=").split(",")
			_pos = Vector3(v[0].to_float(), v[1].to_float(), v[2].to_float())
		elif a.begins_with("--speed="):
			_speed = a.trim_prefix("--speed=").to_float()
	DebugOverlay.visible = false
	add_child((load(scene_path) as PackedScene).instantiate())


func _physics_process(_delta: float) -> void:
	if _pos != Vector3.INF:
		var pl := get_tree().get_first_node_in_group(&"player") as Player
		if pl != null:
			pl.respawn(Transform3D(Basis.IDENTITY, _pos))
			_pos = Vector3.INF
	if _speed > 0.0:
		var p := get_tree().get_first_node_in_group(&"player") as Player
		if p != null:
			p.momentum = 1.0
			var dir := Basis(Vector3.UP, p.rig.yaw) * Vector3.FORWARD
			p.velocity.x = dir.x * _speed
			p.velocity.z = dir.z * _speed


func _process(delta: float) -> void:
	_t += delta
	if _n < _at.size() and _t >= _at[_n]:
		var img := get_viewport().get_texture().get_image()
		var path := "%s_%d.png" % [_out, _n]
		img.save_png(path)
		var pl := get_tree().get_first_node_in_group(&"player") as Player
		print("capture: ", path, "  player ", pl.global_position if pl else Vector3.ZERO, " state ", pl.state if pl else -1, " speed ", pl.horizontal_speed() if pl else 0.0, " fps ", Engine.get_frames_per_second())
		_n += 1
		if _n >= _at.size():
			get_tree().quit()
