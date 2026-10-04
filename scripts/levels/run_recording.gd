class_name RunRecording
extends RefCounted
## 1回の走りの記録（物理フレームごと）。ゴースト（自己ベストの走り）とリプレイ（1人称／追従3人称）に使う。
## 1人称のリプレイはカメラの位置と向きをそのまま再生する（揺れ・傾きも含めて自分が見た通り）。

var pos := PackedVector3Array()   ## 足元
var yaw := PackedFloat32Array()
var eye := PackedVector3Array()   ## カメラの位置
var rot := PackedFloat32Array()   ## カメラの向き（四元数 x, y, z, w）
var fov := PackedFloat32Array()
var state := PackedByteArray()
var speed := PackedFloat32Array()


func size() -> int:
	return pos.size()


func clear() -> void:
	pos.clear()
	yaw.clear()
	eye.clear()
	rot.clear()
	fov.clear()
	state.clear()
	speed.clear()


func add(p: Player) -> void:
	pos.append(p.global_position)
	yaw.append(p.rig.yaw)
	var cam := p.rig.camera
	eye.append(cam.global_position)
	var q := cam.global_basis.get_rotation_quaternion()
	rot.append_array([q.x, q.y, q.z, q.w])
	fov.append(cam.fov)
	state.append(p.state)
	speed.append(p.horizontal_speed())


func duplicate_run() -> RunRecording:
	var r := RunRecording.new()
	r.pos = pos.duplicate()
	r.yaw = yaw.duplicate()
	r.eye = eye.duplicate()
	r.rot = rot.duplicate()
	r.fov = fov.duplicate()
	r.state = state.duplicate()
	r.speed = speed.duplicate()
	return r


## f = フレーム（小数でよい）。間を補間した {pos, yaw, eye, rot: Quaternion, fov, state, speed}
func sample(f: float) -> Dictionary:
	var n := size()
	if n == 0:
		return {}
	f = clampf(f, 0.0, n - 1.0)
	var i := mini(int(f), n - 1)
	var j := mini(i + 1, n - 1)
	var k := f - i
	var out := {
		"pos": pos[i].lerp(pos[j], k),
		"yaw": lerp_angle(yaw[i], yaw[j], k),
		"state": state[i],
		"speed": lerpf(speed[i], speed[j], k),
	}
	if eye.size() == n:
		out.eye = eye[i].lerp(eye[j], k)
		out.rot = _q(i).slerp(_q(j), k)
		out.fov = lerpf(fov[i], fov[j], k)
	return out


func _q(i: int) -> Quaternion:
	return Quaternion(rot[i * 4], rot[i * 4 + 1], rot[i * 4 + 2], rot[i * 4 + 3])


func to_dict() -> Dictionary:
	return {"pos": pos, "yaw": yaw, "eye": eye, "rot": rot, "fov": fov, "state": state, "speed": speed}


static func from_dict(d: Dictionary) -> RunRecording:
	var r := RunRecording.new()
	r.pos = d.get("pos", PackedVector3Array())
	r.yaw = d.get("yaw", PackedFloat32Array())
	r.eye = d.get("eye", PackedVector3Array())
	r.rot = d.get("rot", PackedFloat32Array())
	r.fov = d.get("fov", PackedFloat32Array())
	r.state = d.get("state", PackedByteArray())
	r.speed = d.get("speed", PackedFloat32Array())
	if r.state.size() != r.pos.size():
		# 古い形式（位置と向きだけ）のゴースト
		r.state.resize(r.pos.size())
		r.speed.resize(r.pos.size())
		r.eye.clear()
		r.rot.clear()
		r.fov.clear()
	return r
