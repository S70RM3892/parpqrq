class_name PlayerAudio
extends Node
## プレイヤーの音（仕様書 5章「サウンド」）。Player のシグナルを受けて、その物理フレームのうちに鳴らす
## （効果音は画面の動きと同じフレームで鳴らす。ずれると手触りが壊れる）。
## - 風切り音：速度の2乗に比例して大きく、速いほど高音を足す。技の上限（max_flow_speed）で最大
## - 足音：床の素材別（コンクリ・金属・ガラス・砂利）に8種ずつ。毎回ピッチを ±4% ばらつかせ、同じ音が続けて鳴らない。間隔は足取り（速いほど詰まる）
## - 息づかい：勢い値が高いほど荒く・速く
## - 手が触れる音：強さ3段階（軽 = ヴォルト・壁に張り付く、中 = クライム・縁掴み、重 = スイングバー・ジップライン・ウォールキック）× 3種
## - 着地：落下速度で3段階（軽・中・重）× 3種。ハードランディングは低音を強調
## - 残響：足音・着地・掴みは SFXRoom バス（エリアごとの残響。Audio.set_room）を通す。風・息・スライドの擦れは通さない
## 1人称なので位置を持たない AudioStreamPlayer で鳴らす。

const SURFACES: PackedStringArray = ["concrete", "metal", "glass", "gravel"]
const STEP_VARIANTS := 8
const VARIANTS := 3          ## 着地と掴みの種類（強さごと）
const PITCH_SPREAD := 1.04   ## AudioStreamRandomizer の random_pitch。1/1.04〜1.04 倍（約 ±4%）

@export var player: Player

var _steps: Dictionary[StringName, AudioStreamPlayer] = {}
var _wind_low: AudioStreamPlayer
var _wind_high: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _slide: AudioStreamPlayer
var _one_shots: Dictionary[StringName, AudioStreamPlayer] = {}
var _wind_k: float = 0.0


func _ready() -> void:
	for s: String in SURFACES:
		_steps[StringName(s)] = _make(_variants("step_%s" % s, STEP_VARIANTS, 1.5), 3, &"SFXRoom")
	for strength: String in ["light", "mid", "heavy"]:
		_one_shots[StringName("hand_" + strength)] = _make(_variants("hand_" + strength, VARIANTS, 1.5), 3, &"SFXRoom")
		_one_shots[StringName("land_" + strength)] = _make(_variants("land_" + strength, VARIANTS, 1.5), 2, &"SFXRoom")
	for n: String in ["roll", "jump", "crash", "perfect", "respawn"]:
		_one_shots[StringName(n)] = _make(load("res://assets/audio/%s.wav" % n), 2, &"SFXRoom")
	_wind_low = _make(load("res://assets/audio/wind_low.wav"), 1, &"SFX")
	_wind_high = _make(load("res://assets/audio/wind_high.wav"), 1, &"SFX")
	_breath = _make(load("res://assets/audio/breath.wav"), 1, &"SFX")
	_slide = _make(load("res://assets/audio/slide_loop.wav"), 1, &"SFX")
	for loop: AudioStreamPlayer in [_wind_low, _wind_high, _breath]:
		loop.volume_db = -80.0
		if Audio.enabled:
			loop.play()

	player.footstep.connect(_on_footstep)
	player.landed.connect(_on_landed)
	player.rolled.connect(func(_d: float) -> void: _play(&"roll", 0.0))
	player.jumped.connect(func() -> void: _play(&"jump", -10.0, randf_range(0.95, 1.08)))
	player.vault_started.connect(func() -> void: _play(&"hand_light", 0.0))
	player.climb_started.connect(func() -> void: _play(&"hand_mid", 0.0))
	player.ledge_grabbed.connect(func() -> void: _play(&"hand_mid", 1.0))
	player.swing_started.connect(func() -> void: _play(&"hand_heavy", 0.0))
	player.zip_started.connect(func() -> void: _play(&"hand_heavy", 0.0, 0.9))
	player.wall_kicked.connect(func() -> void:
		_play(&"hand_heavy", -3.0, 0.8)  # 靴底が壁を叩く
		_play(&"jump", -8.0, 1.1))
	player.vault_jumped.connect(func() -> void: _play(&"hand_light", -2.0, 1.1))  # 手で押し切る音（跳ぶ音は jumped が鳴らす）
	player.wallrun_started.connect(func() -> void: _play(&"hand_light", -5.0, 0.9))
	player.wall_jumped.connect(func() -> void:
		_play(&"hand_mid", -2.0)
		_play(&"jump", -6.0))
	player.crashed.connect(func(_s: float) -> void: _play(&"crash", 0.0))
	player.perfect.connect(func(_k: StringName) -> void: _play(&"perfect", -2.0))
	player.respawned.connect(func(_to_start: bool) -> void: _play(&"respawn", -8.0))
	# 走っているエリアの曲と残響（コース以外、白箱のテストコースなどは朝）
	Audio.set_mode(Audio.Mode.RUN, _area_time())


func _process(delta: float) -> void:
	var prm := player.params
	var spd := player.velocity.length()
	# 風切り音：速度の2乗。技の上限で最大
	var k := clampf(spd / prm.max_flow_speed, 0.0, 1.2)
	_wind_k = lerpf(_wind_k, k * k, 1.0 - exp(-6.0 * delta))
	_wind_low.volume_db = linear_to_db(maxf(_wind_k * 0.9, 0.0001))
	_wind_low.pitch_scale = lerpf(0.8, 1.25, clampf(_wind_k, 0.0, 1.0))
	var high := smoothstep(0.35, 1.0, _wind_k)
	_wind_high.volume_db = linear_to_db(maxf(high * 0.6, 0.0001))
	# 息づかい：勢い値で荒く・速く
	var m := player.momentum
	_breath.volume_db = linear_to_db(lerpf(0.08, 0.45, m))
	_breath.pitch_scale = lerpf(0.9, 1.45, m)
	# スライドの擦れ。ジップラインは同じ擦れを高く鳴らして線の唸りにする
	var zipping := player.state == Player.State.ZIPLINE
	if (player.state == Player.State.SLIDE or zipping) and Audio.enabled:
		if not _slide.playing:
			_slide.play()
		_slide.volume_db = linear_to_db(clampf(player.velocity.length() / prm.run_speed, 0.1, 1.2) * (0.5 if zipping else 0.7))
		_slide.pitch_scale = lerpf(1.6, 2.2, clampf(player.velocity.length() / prm.zip_max_speed, 0.0, 1.0)) if zipping else 1.0
	elif _slide.playing:
		_slide.stop()
	Audio.intensity = m


## このコースのエリアの時間帯（朝・昼・夕・夜）。親が Course でなければ朝
func _area_time() -> StringName:
	var course := player.get_parent()
	if course != null:
		var area: Variant = course.get(&"area")
		if area is Dictionary:
			return StringName(str((area as Dictionary).get("time", "morning")))
	return &"morning"


func _on_footstep() -> void:
	var surface := player.floor_surface
	if player.state == Player.State.WALL_RUN or player.state == Player.State.WALL_CLIMB:
		surface = &"concrete"
	var p: AudioStreamPlayer = _steps.get(surface, _steps[&"concrete"])
	# 速いほど少し大きく
	p.volume_db = linear_to_db(clampf(player.horizontal_speed() / player.params.run_speed, 0.35, 1.1) * 0.8)
	if Audio.enabled:
		p.play()


## 着地：落下速度で3段階（普通のジャンプの着地＝軽、2〜3 m＝中、ハードランディングの速さ＝重）
func _on_landed(impact: float, _drop: float) -> void:
	if impact < 3.0:
		return
	var hard := player.params.fall_speed_from(player.params.hard_land_drop)
	var flat := player.params.fall_speed_from(player.params.jump_apex_height)
	if impact >= hard * 0.92:
		_play(&"land_heavy", 0.0)
	elif impact > flat * 1.2:
		_play(&"land_mid", -2.0)
	else:
		_play(&"land_light", -5.0)


func _play(sound: StringName, db: float, pitch: float = 1.0) -> void:
	if not Audio.enabled:
		return
	var p := _one_shots[sound]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## base_0.wav … base_(count-1).wav を、同じ音が続けて鳴らないランダム再生にする（ピッチは ±4%、音量は ±1.5 dB）
func _variants(base: String, count: int, volume_range_db: float) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = PITCH_SPREAD
	r.random_volume_offset_db = volume_range_db
	for i: int in count:
		r.add_stream(-1, load("res://assets/audio/%s_%d.wav" % [base, i]))
	return r


func _make(stream: AudioStream, polyphony: int, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.max_polyphony = polyphony
	add_child(p)
	return p
