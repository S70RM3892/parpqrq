class_name MovementParams
extends Resource
## 動きの数値（仕様書 3章）。全部ここに出して .tres で調整する。
## ジャンプは重力を直接決めず、最高点の高さと到達時間から逆算する。

@export_group("基本移動")
@export var walk_speed: float = 2.5          ## m/s。スティック半倒し
@export var run_speed: float = 7.5           ## m/s。通常最高
@export var accel_time: float = 0.35         ## s。0→最高
@export var decel_time: float = 0.15         ## s。入力なしで停止まで
@export_range(0.0, 1.0) var air_control: float = 0.35  ## 地上比
@export var step_height: float = 0.45        ## m。M1で実装

@export_group("ジャンプ")
@export var jump_apex_height: float = 1.2    ## m
@export var jump_apex_time: float = 0.36     ## s
@export var fall_gravity_mult: float = 1.6
@export_range(0.0, 1.0) var jump_cut_max: float = 0.5
@export var coyote_time: float = 0.1         ## s。M1で実装
@export var jump_buffer: float = 0.12        ## s。M1で実装

@export_group("速度上限")
@export var max_flow_speed: float = 12.0     ## m/s。技でつないだ時の上限
@export var overspeed_decay: float = 1.5     ## m/s 毎秒。地上で通常最高まで戻る速さ


## g = 2h / t²
func gravity() -> float:
	return 2.0 * jump_apex_height / (jump_apex_time * jump_apex_time)


## v0 = 2h / t
func jump_velocity() -> float:
	return 2.0 * jump_apex_height / jump_apex_time
