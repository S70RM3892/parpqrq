extends Node
## BGM と画面（メニュー）の効果音。
## BGM は3つの層（ドラム→ベース→リード）を同期して鳴らし、勢い値で重ねる（仕様書 5章「サウンド」）:
##   走行中：ドラムは常に、勢い35%からベース、70%からリード。100%でさらに一段（全体を少し上げる）
##   メニュー：ベースとリードだけ静かに
## 層の音量は AudioStreamSynchronized が鳴らしながら読み直すので、途中で変えても拍がずれない。

enum Mode { OFF, MENU, RUN }

const LAYERS: PackedStringArray = ["music_drums", "music_bass", "music_lead"]
const FADE := 1.5        ## /s。層が入る・抜ける速さ
const UI_SOUNDS: PackedStringArray = ["ui_move", "ui_ok", "ui_back", "goal", "split", "checkpoint"]

## 0〜1。走行中は Player の勢い値が入る
var intensity: float = 0.0
## 音を鳴らすか。ヘッドレス（テスト）では音の合成が回らず、鳴らした音が解放されないので鳴らさない
var enabled: bool = DisplayServer.get_name() != "headless"

var _mode: Mode = Mode.OFF
var _music: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _vol: PackedFloat32Array = [0.0, 0.0, 0.0]
var _ui: Dictionary[StringName, AudioStreamPlayer] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = LAYERS.size()
	for i: int in LAYERS.size():
		_sync.set_sync_stream(i, load("res://assets/audio/%s.wav" % LAYERS[i]))
		_sync.set_sync_stream_volume(i, -80.0)
	_music = AudioStreamPlayer.new()
	_music.stream = _sync
	_music.bus = &"Music"
	add_child(_music)
	for n: String in UI_SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/%s.wav" % n)
		p.bus = &"SFX"
		p.max_polyphony = 2
		add_child(p)
		_ui[StringName(n)] = p


func set_mode(m: Mode) -> void:
	_mode = m
	if m == Mode.OFF:
		_music.stop()
	elif not _music.playing and enabled:
		_music.play()


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


func _process(delta: float) -> void:
	if _mode == Mode.OFF:
		return
	var target: PackedFloat32Array = [0.0, 0.0, 0.0]
	if _mode == Mode.RUN:
		var top := 1.0 if intensity >= 0.99 else 0.85  # 勢い100%で一段盛り上がる
		target = [top, smoothstep(0.25, 0.4, intensity) * top, smoothstep(0.6, 0.75, intensity) * top]
	else:
		target = [0.0, 0.55, 0.6]
	var real := delta / maxf(Engine.time_scale, 0.01)
	for i: int in _vol.size():
		_vol[i] = move_toward(_vol[i], target[i], FADE * real)
		_sync.set_sync_stream_volume(i, linear_to_db(maxf(_vol[i], 0.0001)))
