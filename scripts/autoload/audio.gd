extends Node
## BGM と画面（メニュー）の効果音、効果音の残響（エリアごと）。
## BGM は曲ごとに3つの層（ドラム→ベース→リード）を同期して鳴らし、勢い値で重ねる（仕様書 5章「サウンド」）:
##   走行中：ドラムは常に、勢い35%からベース、70%からリード。100%でさらに一段（全体を少し上げる）
##   メニュー：3つとも（静かな曲なので）
## 曲はエリアごとに1曲（朝・昼・夕・夜）とメニューの1曲。2分を超えるので、同じエリアのコースを続けて走っても飽きにくい。
## 曲が変わる時（タイトル ↔ コース、別のエリアのコース）は2秒でクロスフェード。同じ曲ならそのまま続ける
## （次のコースへ進んでも曲が頭に戻らない）。
## 層の音量は AudioStreamSynchronized が鳴らしながら読み直すので、途中で変えても拍がずれない。
## 曲の中身と作り方は docs/AUDIO.md、素材は tools/build_audio.gd が合成する。

enum Mode { OFF, MENU, RUN }

const LAYERS: PackedStringArray = ["drums", "bass", "lead"]
const AREA_TRACKS: PackedStringArray = ["morning", "noon", "evening", "night"]
const FADE := 1.5        ## /s。層が入る・抜ける速さ
const XFADE := 2.0       ## 秒。曲が変わる時のクロスフェード
## 曲の最大ピークは -1 dBFS（3層を全部重ねた時）。効果音が乗る余地を取る
const MUSIC_DB := -3.0
const UI_SOUNDS: PackedStringArray = ["ui_move", "ui_ok", "ui_back", "goal", "split", "checkpoint"]

## エリアごとの効果音の残響（SFXRoom バスの Delay → Reverb）。足音・着地・掴みなど、プレイヤーの音だけがここを通る
##   開けた屋上（朝）= 短くまばら、昼の鉄骨 = 金属の小さな反射、夕方の路地 = スラップバック（壁に当たって返る）、夜の駅 = 長く暗い
##   room = 部屋の大きさ、damp = 高域の吸収（大きいほど暗い）、wet = 残響の量、pre = プリディレイ（ms）
##   tap1 / tap2 = [遅れ ms, 音量 dB, 左右]（遅れが 0 ならその反射なし）
const ROOMS: Dictionary[StringName, Dictionary] = {
	&"morning": {"room": 0.14, "damp": 0.6, "wet": 0.05, "pre": 6.0, "tap1": [0.0, -80.0, 0.0], "tap2": [0.0, -80.0, 0.0]},
	&"noon": {"room": 0.3, "damp": 0.3, "wet": 0.09, "pre": 12.0, "tap1": [38.0, -17.0, 0.3], "tap2": [0.0, -80.0, 0.0]},
	&"evening": {"room": 0.24, "damp": 0.5, "wet": 0.08, "pre": 10.0, "tap1": [110.0, -9.0, -0.25], "tap2": [190.0, -17.0, 0.25]},
	&"night": {"room": 0.85, "damp": 0.78, "wet": 0.22, "pre": 28.0, "tap1": [0.0, -80.0, 0.0], "tap2": [0.0, -80.0, 0.0]},
	&"menu": {"room": 0.2, "damp": 0.55, "wet": 0.04, "pre": 8.0, "tap1": [0.0, -80.0, 0.0], "tap2": [0.0, -80.0, 0.0]},
}

## 0〜1。走行中は Player の勢い値が入る
var intensity: float = 0.0
## 音を鳴らすか。ヘッドレス（テスト）では音の合成が回らず、鳴らした音が解放されないので鳴らさない
var enabled: bool = DisplayServer.get_name() != "headless"
## 今鳴らしている（または鳴らすはずの）曲。テストが見る
var track: StringName = &""
var room: StringName = &""

var _mode: Mode = Mode.OFF
var _slots: Array[Slot] = []
var _active: int = -1
var _ui: Dictionary[StringName, AudioStreamPlayer] = {}


## 曲を鳴らす1組（3つの層）。クロスフェードのために2組持つ
class Slot extends RefCounted:
	var player: AudioStreamPlayer
	var sync: AudioStreamSynchronized
	var track: StringName = &""
	var vol: PackedFloat32Array = [0.0, 0.0, 0.0]
	var fade: float = 0.0   ## 0〜1。この曲全体の音量（クロスフェード）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in 2:
		var s := Slot.new()
		s.sync = AudioStreamSynchronized.new()
		s.sync.stream_count = LAYERS.size()
		s.player = AudioStreamPlayer.new()
		s.player.stream = s.sync
		s.player.bus = &"Music"
		s.player.volume_db = MUSIC_DB
		add_child(s.player)
		_slots.append(s)
	for n: String in UI_SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/%s.wav" % n)
		p.bus = &"SFX"
		p.max_polyphony = 2
		add_child(p)
		_ui[StringName(n)] = p
	set_room(&"menu")


## area = 走行中のエリアの時間帯（&"morning" / &"noon" / &"evening" / &"night"）。メニューでは要らない
func set_mode(m: Mode, area: StringName = &"") -> void:
	_mode = m
	if m == Mode.OFF:
		for s: Slot in _slots:
			s.player.stop()
			s.track = &""
		_active = -1
		track = &""
		return
	var want: StringName = &"menu"
	if m == Mode.RUN:
		want = area if AREA_TRACKS.has(area) else &"morning"
	set_room(want)
	track = want
	if not enabled:
		return
	if _active >= 0 and _slots[_active].track == want:
		return
	_switch_to(want)


## 効果音の残響をエリアに合わせる（SFXRoom バスの Delay → Reverb。default_bus_layout.tres）
func set_room(area: StringName) -> void:
	room = area if ROOMS.has(area) else &"morning"
	var idx := AudioServer.get_bus_index(&"SFXRoom")
	if idx < 0:
		return
	var r: Dictionary = ROOMS[room]
	var delay := AudioServer.get_bus_effect(idx, 0) as AudioEffectDelay
	if delay != null:
		var t1: Array = r["tap1"]
		var t2: Array = r["tap2"]
		delay.tap1_active = float(t1[0]) > 0.0
		delay.tap1_delay_ms = maxf(float(t1[0]), 1.0)
		delay.tap1_level_db = float(t1[1])
		delay.tap1_pan = float(t1[2])
		delay.tap2_active = float(t2[0]) > 0.0
		delay.tap2_delay_ms = maxf(float(t2[0]), 1.0)
		delay.tap2_level_db = float(t2[1])
		delay.tap2_pan = float(t2[2])
	var verb := AudioServer.get_bus_effect(idx, 1) as AudioEffectReverb
	if verb != null:
		verb.room_size = float(r["room"])
		verb.damping = float(r["damp"])
		verb.wet = float(r["wet"])
		verb.predelay_msec = float(r["pre"])


## 終了する前に全部の音を止める（鳴ったまま終了すると、オーディオサーバーが音を握ったままになり「使用中のリソース」が残る）
func quit_game(exit_code: int = 0) -> void:
	set_mode(Mode.OFF)
	for n: Node in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		(n as AudioStreamPlayer).stop()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)


## 画面の効果音（メニュー操作・ゴール・区間）
func ui(sound: StringName, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _ui.get(sound)
	if p != null and enabled:
		p.pitch_scale = pitch
		p.play()


## 新しい曲を空いている組に入れて頭から鳴らし、今の曲を抜けさせる（クロスフェードは _process）
func _switch_to(want: StringName) -> void:
	var idx := 0 if _active != 0 else 1
	var s := _slots[idx]
	s.player.stop()
	for i: int in LAYERS.size():
		s.sync.set_sync_stream(i, _load_layer(want, i))
		s.sync.set_sync_stream_volume(i, -80.0)
	s.track = want
	s.vol = [0.0, 0.0, 0.0]
	s.fade = 0.0
	s.player.play()
	_active = idx


## 曲の層を読む。Ogg（ループは .import の loop / loop_offset）か、ffmpeg が無い環境で作った WAV
func _load_layer(t: StringName, i: int) -> AudioStream:
	var base := "res://assets/audio/music_%s_%s" % [t, LAYERS[i]]
	for ext: String in [".ogg", ".wav"]:
		if ResourceLoader.exists(base + ext):
			var stream := load(base + ext) as AudioStream
			var ogg := stream as AudioStreamOggVorbis
			if ogg != null and not ogg.loop:
				ogg.loop = true
			return stream
	push_error("Audio: 曲の層が無い: " + base)
	return null


func _targets() -> PackedFloat32Array:
	if _mode == Mode.RUN:
		var top := 1.0 if intensity >= 0.99 else 0.85  # 勢い100%で一段盛り上がる
		return [top, smoothstep(0.25, 0.4, intensity) * top, smoothstep(0.6, 0.75, intensity) * top]
	return [0.8, 0.9, 0.9]


func _process(delta: float) -> void:
	if _mode == Mode.OFF or not enabled:
		return
	var target := _targets()
	var real := delta / maxf(Engine.time_scale, 0.01)
	for i: int in _slots.size():
		var s := _slots[i]
		if s.track == &"":
			continue
		var is_active := i == _active
		s.fade = move_toward(s.fade, 1.0 if is_active else 0.0, real / XFADE)
		if not is_active and s.fade <= 0.0:
			s.player.stop()
			s.track = &""
			continue
		var gain := sin(s.fade * PI * 0.5)   # 等パワーのクロスフェード
		for k: int in LAYERS.size():
			s.vol[k] = move_toward(s.vol[k], target[k], FADE * real)
			s.sync.set_sync_stream_volume(k, linear_to_db(maxf(s.vol[k] * gain, 0.0001)))
