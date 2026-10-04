class_name Player
extends CharacterBody3D
## M0の仮移動：走りとジャンプだけ。状態機械とパルクール技はM1で作る。
## 速度計算は全部自前で行い、move_and_slide() は衝突処理だけに使う。

@export var params: MovementParams

var _spawn: Transform3D

@onready var rig: CameraRig = $CameraRig


func _ready() -> void:
	add_to_group(&"player")
	_spawn = global_transform
	rig.snap(rotation.y)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"retry") or global_position.y < -30.0:
		respawn()
		return

	var on_floor := is_on_floor()
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var target := _desired_velocity()

	var rate := params.run_speed / (params.accel_time if target != Vector3.ZERO else params.decel_time)
	if not on_floor:
		rate *= params.air_control
	h = h.move_toward(target, rate * delta)

	var vy := velocity.y
	if on_floor and Input.is_action_just_pressed(&"jump"):
		vy = params.jump_velocity()
	elif not on_floor and vy > 0.0 and Input.is_action_just_released(&"jump"):
		vy *= 1.0 - params.jump_cut_max
	var g := params.gravity()
	if vy < 0.0:
		g *= params.fall_gravity_mult
	var vy_next := vy - g * delta

	# このフレームの平均速度で動かす。終速で動かすと最高点が v0·dt/2（約5cm）低く出る
	var vy_avg := (vy + vy_next) * 0.5
	velocity = Vector3(h.x, vy_avg, h.z)
	move_and_slide()
	if is_equal_approx(velocity.y, vy_avg):
		velocity.y = vy_next


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	rig.snap(_spawn.basis.get_euler().y)


## スティックの倒し量で速度を決める：半倒しで歩き、全倒しで走り
func _desired_velocity() -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if Input.is_action_pressed(&"walk"):
		input = input.limit_length(0.5)
	var m := input.length()
	if m == 0.0:
		return Vector3.ZERO
	var speed: float
	if m <= 0.5:
		speed = params.walk_speed * m / 0.5
	else:
		speed = lerpf(params.walk_speed, params.run_speed, (m - 0.5) / 0.5)
	var dir := Basis(Vector3.UP, rig.yaw) * Vector3(input.x, 0.0, input.y)
	return dir.normalized() * speed
