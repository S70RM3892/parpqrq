class_name MovementParams
extends Resource
## 動きの数値（仕様書 3章）。全部ここに出して .tres で調整する。
## プレイ中は調整パネル（F1 / R3）のスライダーで変えられる。
## 速度は 0.2.0-beta の試走で「全体的に遅い」となり、仕様書の値（走り7.5 / 上限12）から+33%にした。
## 技が出る速度の条件（vault_min_speed など）も同じ比率で上げてある。
## ジャンプは重力を直接決めず、最高点の高さと到達時間から逆算する。

@export_group("基本移動")
@export_range(0.5, 5.0, 0.1) var walk_speed: float = 3.3        ## m/s。スティック半倒し
@export_range(3.0, 16.0, 0.1) var run_speed: float = 10.0       ## m/s。通常最高
@export_range(0.05, 1.0, 0.01) var accel_time: float = 0.35     ## s。0→最高
@export_range(0.05, 1.0, 0.01) var decel_time: float = 0.15     ## s。入力なしで停止まで
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.35     ## 地上比
@export_range(0.0, 0.8, 0.01) var step_height: float = 0.45     ## m。自動で乗り越える段差

@export_group("ジャンプ")
@export_range(0.3, 3.0, 0.05) var jump_apex_height: float = 1.2 ## m
@export_range(0.15, 0.8, 0.01) var jump_apex_time: float = 0.36 ## s
@export_range(1.0, 3.0, 0.05) var fall_gravity_mult: float = 1.6
@export_range(0.0, 1.0, 0.05) var jump_cut_max: float = 0.5     ## 早離しで削る上昇速度の割合
@export_range(0.0, 0.3, 0.01) var coyote_time: float = 0.1      ## s
@export_range(0.0, 0.3, 0.01) var jump_buffer: float = 0.12     ## s
@export_range(0.0, 0.3, 0.01) var move_buffer: float = 0.15     ## s。技の最中の先行入力

@export_group("ヴォルト")
@export_range(0.3, 1.0, 0.05) var vault_min_height: float = 0.6
@export_range(0.8, 1.8, 0.05) var vault_max_height: float = 1.3
@export_range(0.2, 2.0, 0.05) var vault_max_depth: float = 1.2  ## これより奥行きがあれば上に乗る
@export_range(0.0, 8.0, 0.1) var vault_min_speed: float = 5.3   ## m/s。走っている時だけ
@export_range(0.5, 1.2, 0.01) var vault_speed_keep: float = 0.95
@export_range(0.05, 0.4, 0.01) var vault_reach_time: float = 0.2 ## s。この時間で届く距離まで障害物を探す
@export_range(0.0, 45.0, 1.0) var vault_auto_align_deg: float = 25.0
@export_range(0.0, 0.5, 0.01) var vault_clearance: float = 0.12 ## m。上面からの足の高さ
@export_range(0.15, 0.6, 0.01) var vault_min_duration: float = 0.25
@export_range(0.3, 1.2, 0.01) var vault_max_duration: float = 0.6

@export_group("クライム・レッジグラブ")
@export_range(1.0, 3.5, 0.05) var climb_max_height: float = 2.4  ## m。手の届く縁（地上から）
@export_range(0.2, 1.2, 0.01) var climb_time: float = 0.5        ## s。止まった状態から登りきる時間
@export_range(0.3, 1.0, 0.05) var climb_fast_mult: float = 0.75  ## 走り速度で来た時の時間倍率（速いほど短い）
@export_range(1.5, 2.6, 0.05) var ledge_reach: float = 2.2       ## m。空中で足元から手が届く高さ
@export_range(0.3, 3.0, 0.1) var ledge_shimmy_speed: float = 1.2 ## m/s。ぶら下がり中の横移動

@export_group("ウォールラン")
@export_range(0.0, 10.0, 0.1) var wallrun_min_speed: float = 6.7
@export_range(0.3, 3.0, 0.05) var wallrun_max_time: float = 1.6
@export_range(0.0, 1.0, 0.05) var wallrun_gravity: float = 0.3   ## 通常の重力に対する倍率
@export_range(0.0, 45.0, 1.0) var wallrun_min_angle: float = 0.0 ## 度。仕様書は15°。平行に近い進入も拾うため0
@export_range(30.0, 89.0, 1.0) var wallrun_max_angle: float = 60.0
@export_range(0.0, 5.0, 0.1) var wallrun_entry_lift: float = 2.0 ## m/s。張り付いた瞬間の上向き速度（最低）
@export_range(0.0, 10.0, 0.1) var wallrun_entry_max_lift: float = 5.0 ## m/s。跳んだ勢いをここまで残す
@export_range(0.0, 0.5, 0.01) var wall_jump_speed_bonus: float = 0.10
@export_range(0.0, 2.0, 0.05) var wall_jump_push: float = 0.8    ## 壁から離れる成分の強さ
@export_range(0.0, 10.0, 0.1) var wallrun_up_min_speed: float = 5.3
@export_range(0.5, 4.0, 0.1) var wallrun_up_height: float = 2.0  ## m。縦ウォールランで駆け上がる高さ

@export_group("スライド")
@export_range(0.0, 10.0, 0.1) var slide_min_speed: float = 6.7
@export_range(0.2, 2.0, 0.05) var slide_time: float = 0.8
@export_range(0.0, 10.0, 0.1) var slide_friction: float = 2.0    ## m/s 毎秒。平地での減速
@export_range(0.0, 0.3, 0.01) var slide_jump_bonus: float = 0.08
@export_range(0.6, 1.4, 0.05) var slide_height: float = 1.0      ## m。スライド中の当たり判定の高さ

@export_group("着地")
@export_range(0.5, 4.0, 0.1) var roll_min_drop: float = 2.0     ## m。これ以上の落下でローリング可
@export_range(0.0, 0.4, 0.01) var roll_window_before: float = 0.2
@export_range(0.0, 0.2, 0.01) var roll_window_after: float = 0.08
@export_range(0.2, 1.2, 0.01) var roll_duration: float = 0.55
@export_range(2.0, 10.0, 0.1) var hard_land_drop: float = 4.0   ## m
@export_range(0.0, 1.5, 0.05) var hard_land_stun: float = 0.0   ## s。0.3.0-beta の試走で「止まるのが不快」となり0（仕様書は0.6）
@export_range(0.0, 1.0, 0.05) var hard_land_speed_loss: float = 0.0 ## 同上で0（仕様書は0.7）。揺れと振動だけ残す

@export_group("足取り")
@export_range(0.5, 4.0, 0.1) var cadence_walk: float = 2.0      ## 歩/s
@export_range(1.5, 5.0, 0.1) var cadence_run: float = 3.3       ## 歩/s

@export_group("速度上限")
@export_range(8.0, 25.0, 0.5) var max_flow_speed: float = 15.0  ## m/s。技でつないだ時の上限
@export_range(0.0, 5.0, 0.1) var overspeed_decay: float = 1.5   ## m/s 毎秒。地上で通常最高まで戻る速さ


## g = 2h / t²
func gravity() -> float:
	return 2.0 * jump_apex_height / (jump_apex_time * jump_apex_time)


## v0 = 2h / t
func jump_velocity() -> float:
	return 2.0 * jump_apex_height / jump_apex_time


## 高さ h から落ちた時の着地速度
func fall_speed_from(h: float) -> float:
	return sqrt(2.0 * gravity() * fall_gravity_mult * maxf(h, 0.0))
