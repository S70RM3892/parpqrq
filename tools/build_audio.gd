extends SceneTree
## 効果音とBGMを合成して assets/audio/ に書き出す（仕様書 4・5章「サウンド」。音素材が無いので手続き的に作る）。
##   godot --headless --path . -s tools/build_audio.gd [-- --only=sfx,loops,morning,noon,evening,night,menu] [--wav]
##   書き出したら godot --headless --path . --import で取り込み直す（ループ点は .ogg.import に書く）
## - 効果音（足音は素材ごとに8種、着地・掴みは強さ3段階×3種）と環境音は 44.1 kHz の WAV（QOA で取り込まれる）
## - BGM は5曲（朝・昼・夕・夜・メニュー）。1曲 = ドラム・ベース・リードの3つの層（同じ長さ。audio.gd が勢い値で重ねる）。
##   44.1 kHz ステレオ。曲の頭へ戻ってループする（終わりのアウトロがイントロにつながる。ループ点は頭で、loop_from は 0 のまま。イントロの後ろにすると、イントロの残響が継ぎ目に重なって段差が出る）。ffmpeg があれば Ogg Vorbis にして書き出す
##   （WAV のままだと 1 曲 70 MB を超えるので git に入れられない）。ffmpeg が無い時、または --wav なら WAV のまま
## - BGM の合成は5曲を別スレッドで並べて走らせる（1曲は数十秒〜数分）。終わりに曲ごとの測定値（ピーク・区間のRMS・ステレオ相関・層ごとの重心）を出す
## - 乱数の種は固定。同じコードなら同じ音になる

const OUT := "res://assets/audio/"
const TMP := "res://.godot/audio_build/"
const SR := 44100
const PEAK_DB := -1.5     ## BGM の最大ピーク（3層を全部重ねた時）。Ogg にすると +1 dB 前後はみ出すので、少し余裕を取る
## 昔の名前の素材（今は作らない）。全部作り直す時に消す
const STALE: PackedStringArray = ["hand_0", "hand_1", "land_light", "land_mid", "land_heavy", "music_drums", "music_bass", "music_lead"]

var _rng := RandomNumberGenerator.new()
var _only: PackedStringArray = []
var _keep_wav: bool = false


func _init() -> void:
	_rng.seed = 20261004
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).split(",")
		elif a == "--wav":
			_keep_wav = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var t0 := Time.get_ticks_msec()
	if _only.is_empty():
		for stale: String in STALE:
			for ext: String in [".wav", ".wav.import"]:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + stale + ext))
	if _wants("sfx"):
		_build_sfx()
	if _wants("loops"):
		_build_loops()
	_build_music()
	print("build_audio: done in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func _wants(what: String) -> bool:
	return _only.is_empty() or what in _only


# --- 効果音 -----------------------------------------------------------------

func _build_sfx() -> void:
	# 足音：素材ごとに8種（ピッチは再生側で ±4% ばらつかせる）
	for i: int in 8:
		_save("step_concrete_%d" % i, _step_concrete())
		_save("step_metal_%d" % i, _step_metal())
		_save("step_glass_%d" % i, _step_glass())
		_save("step_gravel_%d" % i, _step_gravel())
	# 手が触れる音・掴む音：強さ3段階（軽 = 手のひらで触れる、中 = 握る、重 = 全体重で掴む・棒や線）× 3種
	for i: int in 3:
		_save("hand_light_%d" % i, _hand(0))
		_save("hand_mid_%d" % i, _hand(1))
		_save("hand_heavy_%d" % i, _hand(2))
		_save("land_light_%d" % i, _land(0))
		_save("land_mid_%d" % i, _land(1))
		_save("land_heavy_%d" % i, _land(2))
	_save("roll", _roll())
	_save("jump", _whoosh(0.16, 900.0, 2600.0, 0.35, 0.6))
	_save("crash", _crash())
	_save("perfect", _chime([1567.98, 2349.32], 0.55, 0.5))
	_save("checkpoint", _chime([880.0, 1318.51], 0.5, 0.35))
	_save("split", _chime([1760.0], 0.18, 0.3))
	_save("goal", _goal())
	_save("respawn", _whoosh(0.22, 500.0, 3000.0, 0.4, 0.6))
	_save("ui_move", _click(2400.0, 0.025, 0.25))
	_save("ui_ok", _chime([1318.51, 1975.53], 0.18, 0.35))
	_save("ui_back", _chime([987.77, 659.26], 0.16, 0.3))


func _noise(n: int) -> PackedFloat32Array:
	return Dsp.noise(n, _rng.randi())


func _rf(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


## 足音：コンクリ = かかとの「コツ」＋低い「トン」＋靴底の「ザッ」＋つま先の小さな2発目
func _step_concrete() -> PackedFloat32Array:
	var n := int(SR * 0.26)
	var out := Dsp.thump(n, _rf(70.0, 100.0), _rf(0.035, 0.065), _rf(0.55, 0.8))
	var heel := Dsp.bp2(_noise(n), _rf(500.0, 900.0), _rf(2200.0, 3400.0))
	Dsp.env_ad(heel, 0.0005, _rf(0.010, 0.020))
	Dsp.add(out, heel, 0, 0.9)
	var scuff := Dsp.bp2(_noise(n), 1000.0, _rf(3500.0, 5200.0))
	Dsp.env_ad(scuff, 0.006, _rf(0.03, 0.06))
	Dsp.add(out, scuff, int(SR * 0.004), 0.35)
	Dsp.add(out, Dsp.thump(n, _rf(110.0, 150.0), 0.03, 0.4), int(SR * _rf(0.055, 0.085)), 0.55)
	return Dsp.normalized(out, _rf(0.72, 0.8))


## 金属：トンの上に響く倍音（調和しない比で鳴らすと金属らしい）。板の鳴りは毎回違う比にする
func _step_metal() -> PackedFloat32Array:
	var n := int(SR * 0.5)
	var out := Dsp.thump(n, _rf(100.0, 125.0), 0.04, 0.5)
	var base := _rf(340.0, 480.0)
	var ratios: Array[float] = [1.0, _rf(2.3, 2.9), _rf(4.6, 5.6), _rf(7.6, 9.2), _rf(11.0, 13.0)]
	for k: int in ratios.size():
		var tone := Dsp.sine(n, base * ratios[k], _rf(0.0, TAU))
		Dsp.env_ad(tone, 0.001, _rf(0.16, 0.26) / (1.0 + k * 0.6))
		Dsp.add(out, tone, 0, 0.32 / (1.0 + k * 0.5))
	var clank := Dsp.bp1(_noise(n), 1500.0, _rf(5000.0, 7000.0))
	Dsp.env_ad(clank, 0.0008, _rf(0.012, 0.03))
	Dsp.add(out, clank, 0, 0.6)
	return Dsp.normalized(out, _rf(0.72, 0.78))


## ガラス：高いカチッと短い響き
func _step_glass() -> PackedFloat32Array:
	var n := int(SR * 0.32)
	var out := Dsp.thump(n, _rf(90.0, 105.0), 0.035, 0.5)
	var base := _rf(2200.0, 2800.0)
	for k: float in [1.0, _rf(1.55, 1.7), _rf(2.4, 2.65), _rf(3.7, 4.1)]:
		var tone := Dsp.sine(n, base * k, _rf(0.0, TAU))
		Dsp.env_ad(tone, 0.0005, _rf(0.08, 0.14) / k)
		Dsp.add(out, tone, 0, 0.3 / k)
	var tick := Dsp.hp1(_noise(n), 4000.0)
	Dsp.env_ad(tick, 0.0003, _rf(0.004, 0.009))
	Dsp.add(out, tick, 0, 0.7)
	return Dsp.normalized(out, _rf(0.66, 0.72))


## 砂利：細かい粒がザクッと（粒の数と散らばりを毎回変える）
func _step_gravel() -> PackedFloat32Array:
	var n := int(SR * 0.24)
	var out := Dsp.thump(n, _rf(75.0, 90.0), 0.04, 0.45)
	var grains := PackedFloat32Array()
	grains.resize(n)
	var spread := _rf(0.08, 0.14)
	for g: int in _rng.randi_range(32, 60):
		var at := int(_rf(0.0, spread) * SR)
		var glen := int(SR * _rf(0.003, 0.012))
		var amp := _rf(0.3, 1.0) * (1.0 - float(at) / n)
		for i: int in glen:
			if at + i < n:
				grains[at + i] += _rf(-1.0, 1.0) * amp * (1.0 - float(i) / glen)
	Dsp.add(out, Dsp.bp2(grains, _rf(900.0, 1400.0), _rf(4200.0, 5600.0)), 0, 1.4)
	return Dsp.normalized(out, _rf(0.72, 0.78))


## 手が触れる音（強さ 0 = 軽・1 = 中・2 = 重）
## 軽：手袋の手のひらで触れる「ペタッ」。中：握る「ギュッ」。重：全体重で掴む（棒・線は金属の鳴りを足す）
func _hand(strength: int) -> PackedFloat32Array:
	var n := int(SR * (0.14 + 0.1 * strength))
	var out := Dsp.thump(n, _rf(150.0, 190.0) * (1.0 - 0.25 * strength), 0.02 + 0.03 * strength, 0.3 + 0.35 * strength)
	var slap := Dsp.bp2(_noise(n), _rf(700.0, 1300.0), _rf(3200.0, 4500.0))
	Dsp.env_ad(slap, 0.0004, 0.02 + 0.012 * strength)
	Dsp.add(out, slap, 0, 1.0)
	if strength >= 1:
		var creak := Dsp.bp1(_noise(n), 300.0, _rf(1000.0, 1500.0))
		Dsp.env_ad(creak, 0.012, 0.07)
		Dsp.add(out, creak, int(SR * 0.012), 0.35 + 0.1 * strength)
	if strength == 2:
		var base := _rf(260.0, 420.0)
		for k: float in [1.0, 2.76, 5.4]:
			var tone := Dsp.sine(n, base * k, 0.0)
			Dsp.env_ad(tone, 0.001, 0.16 / k)
			Dsp.add(out, tone, 0, 0.28 / k)
	return Dsp.normalized(out, [0.6, 0.78, 0.95][strength])


## 着地（強さ 0 = 軽・1 = 中・2 = 重）。重いほど低音が長く、粉塵と擦れが付く。ハードランディングは低いドンを足す
func _land(strength: int) -> PackedFloat32Array:
	var weight: float = [0.35, 0.65, 1.0][strength]
	var length: float = [0.10, 0.16, 0.30][strength] * _rf(0.9, 1.1)
	var n := int(SR * (length + 0.3))
	var out := Dsp.thump(n, lerpf(88.0, 58.0, weight) * _rf(0.94, 1.06), length * 0.5, 1.0)
	var dust := Dsp.bp1(_noise(n), 200.0, lerpf(2200.0, 1200.0, weight))
	Dsp.env_ad(dust, 0.002, length * 0.6)
	Dsp.add(out, dust, 0, 0.6 + weight * 0.4)
	var heel := Dsp.bp2(_noise(n), 600.0, _rf(2400.0, 3400.0))
	Dsp.env_ad(heel, 0.0005, 0.012 + 0.006 * strength)
	Dsp.add(out, heel, 0, 0.5 + 0.2 * weight)
	if strength >= 1:
		# 靴底と服の擦れ
		var rustle := Dsp.bp2(_noise(n), 800.0, _rf(3500.0, 5000.0))
		Dsp.env_ad(rustle, 0.02, 0.05 + 0.04 * strength)
		Dsp.add(out, rustle, int(SR * 0.015), 0.25 + 0.1 * strength)
	if strength == 2:
		var sub := Dsp.sweep(n, _rf(66.0, 74.0), _rf(36.0, 40.0), 0.25)
		Dsp.env_ad(sub, 0.004, 0.35)
		Dsp.add(out, sub, 0, 1.1)
		# 砂利が跳ねる
		var rattle := Dsp.bp2(_noise(n), 1200.0, 4800.0)
		for k: int in 6:
			var at := int(SR * _rf(0.02, 0.16))
			var piece := rattle.slice(0, int(SR * _rf(0.004, 0.01)))
			Dsp.env_ad(piece, 0.0003, 0.004)
			Dsp.add(out, piece, at, _rf(0.1, 0.25))
	return Dsp.normalized(out, lerpf(0.55, 0.95, weight))


func _roll() -> PackedFloat32Array:
	var n := int(SR * 0.55)
	var out := _whoosh(0.5, 300.0, 1400.0, 0.7, 0.7)
	Dsp.add(out, Dsp.thump(n, 70.0, 0.08, 0.7), int(SR * 0.05), 0.8)
	Dsp.add(out, Dsp.thump(n, 90.0, 0.05, 0.4), int(SR * 0.3), 0.6)
	return Dsp.normalized(out, 0.7)


func _crash() -> PackedFloat32Array:
	var n := int(SR * 0.5)
	var out := Dsp.thump(n, 55.0, 0.18, 1.0)
	var hit := Dsp.bp1(_noise(n), 150.0, 2500.0)
	Dsp.env_ad(hit, 0.001, 0.09)
	Dsp.add(out, hit, 0, 1.0)
	return Dsp.normalized(out, 0.95)


## 風を切る「シュッ」：帯域を動かしたノイズ
func _whoosh(length: float, lo: float, hi: float, peak_at: float, peak: float) -> PackedFloat32Array:
	var n := int(SR * length)
	var src := _noise(n)
	var out := PackedFloat32Array()
	out.resize(n)
	var y1 := 0.0
	var y2 := 0.0
	for i: int in n:
		var t := float(i) / n
		var fc := lerpf(lo, hi, sin(t * PI))
		var a := 1.0 - exp(-TAU * fc / SR)
		y1 += a * (src[i] - y1)
		y2 += (1.0 - exp(-TAU * lo * 0.5 / SR)) * (y1 - y2)
		var env := smoothstep(0.0, peak_at, t) * (1.0 - smoothstep(peak_at, 1.0, t))
		out[i] = (y1 - y2) * env
	return Dsp.normalized(out, peak)


## 鐘のような音（Perfect・チェックポイント・UI）
func _chime(freqs: Array, length: float, peak: float) -> PackedFloat32Array:
	var n := int(SR * length)
	var out := PackedFloat32Array()
	out.resize(n)
	for j: int in freqs.size():
		var f: float = freqs[j]
		var at := int(SR * 0.045 * j)
		for k: float in [1.0, 2.0, 3.01]:
			var tone := Dsp.sine(n - at, f * k, 0.0)
			Dsp.env_ad(tone, 0.002, length * 0.35 / k)
			Dsp.add(out, tone, at, 0.5 / (k * k))
	return Dsp.normalized(out, peak)


func _goal() -> PackedFloat32Array:
	var notes := [880.0, 1108.73, 1318.51, 1760.0]
	var n := int(SR * 1.2)
	var out := PackedFloat32Array()
	out.resize(n)
	for j: int in notes.size():
		Dsp.add(out, _chime([notes[j]], 0.9 - j * 0.1, 1.0), int(SR * 0.09 * j), 0.6)
	return Dsp.normalized(out, 0.7)


func _click(freq: float, length: float, peak: float) -> PackedFloat32Array:
	var out := Dsp.sine(int(SR * length), freq, 0.0)
	Dsp.env_ad(out, 0.0005, length * 0.3)
	return Dsp.normalized(out, peak)


# --- 環境音のループ（44.1 kHz。風はステレオ）---------------------------------

func _build_loops() -> void:
	# 風切り音（低）：茶色ノイズにゆっくりした息継ぎ。左右は別のノイズ（広がる）
	var n := SR * 4
	var wl: Array[PackedFloat32Array] = []
	for c: int in 2:
		var low := Dsp.lp1(Dsp.lp1(_noise(n), 500.0), 700.0)
		for i: int in n:
			var t := float(i) / SR
			low[i] *= 0.75 + 0.25 * sin(TAU * t * 0.5 + c * 1.3) * sin(TAU * t * 0.25 + 1.0 + c * 0.7)
		wl.append(Dsp.looped(low, SR / 4))
	var k := 0.8 / maxf(Dsp.peak(wl[0]), Dsp.peak(wl[1]))
	_write_wav(OUT + "wind_low.wav", [Dsp.scaled(wl[0], k), Dsp.scaled(wl[1], k)], SR, 0)
	# 風切り音（高）：速くなると足す高音
	n = SR * 3
	var wh: Array[PackedFloat32Array] = []
	for c: int in 2:
		var high := Dsp.bp1(_noise(n), 2500.0, 7000.0)
		for i: int in n:
			var t := float(i) / SR
			high[i] *= 0.7 + 0.3 * sin(TAU * t * (1.0 / 3.0) * 2.0 + c * 1.1)
		wh.append(Dsp.looped(high, SR / 4))
	k = 0.6 / maxf(Dsp.peak(wh[0]), Dsp.peak(wh[1]))
	_write_wav(OUT + "wind_high.wav", [Dsp.scaled(wh[0], k), Dsp.scaled(wh[1], k)], SR, 0)
	# スライドの擦れ
	n = SR * 2
	var scrape := Dsp.bp1(_noise(n), 500.0, 2400.0)
	for i: int in n:
		scrape[i] *= 0.6 + 0.4 * absf(sin(float(i) / SR * TAU * 13.0)) * _rf(0.7, 1.0)
	_save("slide_loop", Dsp.normalized(Dsp.looped(scrape, SR / 8), 0.7), true)
	# 息づかい：吸う→吐く（勢い値で速く・荒くする：再生速度と音量を変える）
	n = int(SR * 2.4)
	var breath := PackedFloat32Array()
	breath.resize(n)
	var inhale := Dsp.bp1(_noise(n), 900.0, 2600.0)
	var exhale := Dsp.bp1(_noise(n), 450.0, 1600.0)
	for i: int in n:
		var t := float(i) / SR
		var e_in := smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(0.6, 0.9, t))
		var e_out := smoothstep(1.0, 1.15, t) * (1.0 - smoothstep(1.2, 2.1, t))
		breath[i] = inhale[i] * e_in * 0.6 + exhale[i] * e_out
	_save("breath", Dsp.normalized(breath, 0.6), true)


# --- 書き出し -----------------------------------------------------------------

func _save(file_name: String, x: PackedFloat32Array, loop: bool = false) -> void:
	_write_wav(OUT + file_name + ".wav", [x], SR, 0 if loop else -1)


## 16bit の WAV を書く（チャンネル数は ch の数）。loop_begin >= 0 なら smpl チャンクに「そこから最後まで」のループを入れる
func _write_wav(path: String, ch: Array[PackedFloat32Array], sr: int, loop_begin: int) -> void:
	var nch: int = ch.size()
	var frames: int = ch[0].size()
	var pcm := PackedByteArray()
	pcm.resize(frames * nch * 2)
	for c: int in nch:
		var x: PackedFloat32Array = ch[c]
		for i: int in frames:
			pcm.encode_s16((i * nch + c) * 2, int(clampf(x[i], -1.0, 1.0) * 32767.0))
	var loop := loop_begin >= 0
	var f := FileAccess.open(path, FileAccess.WRITE)
	var smpl_size := 36 + 24
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(4 + (8 + 16) + (8 + pcm.size()) + ((8 + smpl_size) if loop else 0))
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)        # PCM
	f.store_16(nch)
	f.store_32(sr)
	f.store_32(sr * nch * 2)
	f.store_16(nch * 2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	if loop:
		f.store_buffer("smpl".to_ascii_buffer())
		f.store_32(smpl_size)
		for v: int in [0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0]:
			f.store_32(v)
		# ループ1つ：前向き、loop_begin から最後のサンプルまで
		for v: int in [0, 0, loop_begin, frames - 1, 0, 0]:
			f.store_32(v)
	f.close()


# --- 部品（スレッドから呼ぶので全部 static。状態を持たない）---------------------------

class Stereo extends RefCounted:
	var l: PackedFloat32Array
	var r: PackedFloat32Array

	func _init(n: int = 0) -> void:
		l.resize(n)
		r.resize(n)


class Dsp extends RefCounted:
	## 白色雑音。種から作る xorshift32（RandomNumberGenerator より速く、スレッドごとに独立）
	static func noise(n: int, seed_v: int) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(n)
		var s: int = (seed_v & 0x7FFFFFFF) | 1
		for i: int in n:
			s ^= (s << 13) & 0xFFFFFFFF
			s ^= s >> 17
			s ^= (s << 5) & 0xFFFFFFFF
			out[i] = float(s) * 4.656612873077393e-10 - 1.0
		return out

	static func sine(n: int, freq: float, phase: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(maxi(n, 0))
		var w := TAU * freq / SR
		for i: int in n:
			out[i] = sin(phase + w * i)
		return out

	## 下へ滑る正弦波の「ドン」
	static func thump(n: int, freq: float, decay: float, amp: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(n)
		var ph := 0.0
		for i: int in n:
			var t := float(i) / SR
			ph += TAU * freq * (1.0 + 0.8 * exp(-t / 0.012)) / SR
			out[i] = sin(ph) * exp(-t / decay) * amp * minf(t / 0.001, 1.0)
		return out

	static func sweep(n: int, f0: float, f1: float, length: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(n)
		var ph := 0.0
		for i: int in n:
			var t := float(i) / SR
			ph += TAU * lerpf(f0, f1, minf(t / length, 1.0)) / SR
			out[i] = sin(ph)
		return out

	static func lp1(x: PackedFloat32Array, fc: float) -> PackedFloat32Array:
		var out := x.duplicate()
		var a := 1.0 - exp(-TAU * fc / SR)
		var y := 0.0
		for i: int in out.size():
			y += a * (x[i] - y)
			out[i] = y
		return out

	static func hp1(x: PackedFloat32Array, fc: float) -> PackedFloat32Array:
		var out := x.duplicate()
		var a := 1.0 - exp(-TAU * fc / SR)
		var y := 0.0
		for i: int in out.size():
			y += a * (x[i] - y)
			out[i] = x[i] - y
		return out

	static func bp1(x: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
		return hp1(lp1(x, hi), lo)

	## 傾きを倍にした帯域フィルタ（一極を2段）。ノイズの高域の荒れを抑えたい所に使う
	static func bp2(x: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
		return hp1(hp1(lp1(lp1(x, hi), hi), lo), lo)

	## 2次のフィルタ（RBJ）。kind 0 = LP, 1 = HP, 2 = BP
	static func biquad(x: PackedFloat32Array, kind: int, fc: float, q: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(x.size())
		var w0 := TAU * minf(fc, SR * 0.45) / SR
		var cw := cos(w0)
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		var b0: float
		var b1: float
		var b2: float
		if kind == 0:
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = b0
		elif kind == 1:
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = b0
		else:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
		var a1 := -2.0 * cw / a0
		var a2 := (1.0 - alpha) / a0
		b0 /= a0
		b1 /= a0
		b2 /= a0
		var z1 := 0.0
		var z2 := 0.0
		for i: int in x.size():
			var v := x[i]
			var y := b0 * v + z1
			z1 = b1 * v - a1 * y + z2
			z2 = b2 * v - a2 * y
			out[i] = y
		return out

	## カットオフを block サンプルごとに変えられる2次ローパス（状態変数フィルタ）。cuts は Hz（5 kHz で頭打ち）
	static func svf_lp(x: PackedFloat32Array, cuts: PackedFloat32Array, block: int, q: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var n := x.size()
		out.resize(n)
		var low := 0.0
		var band := 0.0
		var k := 1.0 / q
		var i := 0
		for b: int in cuts.size():
			var f := 2.0 * sin(PI * minf(cuts[b], 5000.0) / SR)
			var end := mini(i + block, n)
			while i < end:
				low += f * band
				var high := x[i] - low - k * band
				band += f * high
				out[i] = low
				i += 1
		return out

	## PolyBLEP（帯域制限のノコギリ波・矩形波）。t = 位相 0〜1、dt = 1サンプルあたりの位相の進み
	static func blep(t: float, dt: float) -> float:
		if t < dt:
			var x := t / dt
			return x + x - x * x - 1.0
		if t > 1.0 - dt:
			var x := (t - 1.0) / dt
			return x * x + x + x + 1.0
		return 0.0

	static func saw(t: float, dt: float) -> float:
		return 2.0 * t - 1.0 - blep(t, dt)

	static func pulse(t: float, dt: float, pw: float) -> float:
		return (1.0 if t < pw else -1.0) + blep(t, dt) - blep(fposmod(t + 1.0 - pw, 1.0), dt)

	## 小さい音はそのまま、大きい音は 1/drive に丸める（tanh）
	static func softclip(x: PackedFloat32Array, drive: float) -> void:
		var inv := 1.0 / drive
		for i: int in x.size():
			x[i] = tanh(x[i] * drive) * inv

	## 立ち上がり attack 秒、そのあと指数で減衰する包絡を掛ける（その場で）
	static func env_ad(x: PackedFloat32Array, attack: float, decay: float) -> void:
		var inv_a := 1.0 / maxf(attack * SR, 1.0)
		var k := exp(-1.0 / maxf(decay * SR, 1.0))
		var a := 0.0
		var d := 1.0
		for i: int in x.size():
			if a < 1.0:
				a = minf(a + inv_a, 1.0)
			else:
				d *= k
			x[i] *= a * d

	static func peak(x: PackedFloat32Array) -> float:
		var m := 0.0
		for v: float in x:
			m = maxf(m, absf(v))
		return m

	static func scaled(x: PackedFloat32Array, k: float) -> PackedFloat32Array:
		var out := x.duplicate()
		for i: int in out.size():
			out[i] *= k
		return out

	static func normalized(x: PackedFloat32Array, peak_to: float) -> PackedFloat32Array:
		var m := peak(x)
		if m < 1e-6:
			return x
		return scaled(x, peak_to / m)

	## dst に src を at から足す（はみ出しは捨てる）
	static func add(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> void:
		var n := mini(src.size(), dst.size() - at)
		for i: int in n:
			dst[at + i] += src[i] * gain

	## モノラルの音を定位（-1 = 左、1 = 右。等パワー）をつけてステレオに足す
	static func add_pan(dst: Stereo, src: PackedFloat32Array, at: int, gain: float, pan: float) -> void:
		var n := mini(src.size(), dst.l.size() - at)
		var ang := (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
		var gl := cos(ang) * gain
		var gr := sin(ang) * gain
		for i: int in n:
			var v := src[i]
			dst.l[at + i] += v * gl
			dst.r[at + i] += v * gr

	static func add_st(dst: Stereo, src: Stereo, at: int, gain: float) -> void:
		var n := mini(src.l.size(), dst.l.size() - at)
		for i: int in n:
			dst.l[at + i] += src.l[i] * gain
			dst.r[at + i] += src.r[i] * gain

	## ループの終わりからはみ出す分（fade サンプル）を頭に重ねて継ぎ目をなくす（長さは fade だけ短くなる）
	static func looped(x: PackedFloat32Array, fade: int) -> PackedFloat32Array:
		var n := x.size() - fade
		var out := x.slice(0, n)
		for i: int in fade:
			var k := float(i) / fade
			out[i] = x[i] * k + x[n + i] * (1.0 - k)
		return out

	# --- 空間系 -------------------------------------------------------------------

	## 6本のフィードバック遅延網（FDN）の残響。入力は左右を足して1つに。返すのは残響だけ（原音は含まない）
	## rt60 = 残響時間（秒）、size = 部屋の大きさ（遅延長の倍率）、damp = 高域の吸収（0〜0.9）、pre_ms = プリディレイ
	static func reverb(l: PackedFloat32Array, r: PackedFloat32Array, rt60: float, size: float, damp: float, pre_ms: float) -> Stereo:
		var n := l.size()
		var out := Stereo.new(n)
		var base: Array[int] = [1103, 1327, 1559, 1787, 2053, 2339]
		var d: Array[int] = []
		var g: Array[float] = []
		var off: Array[int] = []
		var total := 0
		for k: int in 6:
			var len := int(base[k] * size) | 1
			d.append(len)
			g.append(pow(10.0, -3.0 * len / (rt60 * SR)))
			off.append(total)
			total += len
		var buf := PackedFloat32Array()
		buf.resize(total)
		var da := 1.0 - clampf(damp, 0.0, 0.95)
		var p0 := 0
		var p1 := 0
		var p2 := 0
		var p3 := 0
		var p4 := 0
		var p5 := 0
		var o0: int = off[0]
		var o1: int = off[1]
		var o2: int = off[2]
		var o3: int = off[3]
		var o4: int = off[4]
		var o5: int = off[5]
		var d0: int = d[0]
		var d1: int = d[1]
		var d2: int = d[2]
		var d3: int = d[3]
		var d4: int = d[4]
		var d5: int = d[5]
		var g0: float = g[0]
		var g1: float = g[1]
		var g2: float = g[2]
		var g3: float = g[3]
		var g4: float = g[4]
		var g5: float = g[5]
		var s0 := 0.0
		var s1 := 0.0
		var s2 := 0.0
		var s3 := 0.0
		var s4 := 0.0
		var s5 := 0.0
		# 入力の拡散（直列の全域通過 2段）
		var ap1 := PackedFloat32Array()
		ap1.resize(149)
		var ap2 := PackedFloat32Array()
		ap2.resize(211)
		var q1 := 0
		var q2 := 0
		var pre := int(pre_ms * 0.001 * SR)
		for i: int in n:
			var inp := 0.0
			if i >= pre:
				inp = (l[i - pre] + r[i - pre]) * 0.5
			var v1 := inp + 0.6 * ap1[q1]
			var x1 := ap1[q1] - 0.6 * v1
			ap1[q1] = v1
			q1 += 1
			if q1 == 149:
				q1 = 0
			var v2 := x1 + 0.6 * ap2[q2]
			inp = ap2[q2] - 0.6 * v2
			ap2[q2] = v2
			q2 += 1
			if q2 == 211:
				q2 = 0
			var a0 := buf[o0 + p0]
			var a1 := buf[o1 + p1]
			var a2 := buf[o2 + p2]
			var a3 := buf[o3 + p3]
			var a4 := buf[o4 + p4]
			var a5 := buf[o5 + p5]
			var hh := (a0 + a1 + a2 + a3 + a4 + a5) * 0.33333334
			s0 += da * ((a0 - hh) - s0)
			s1 += da * ((a1 - hh) - s1)
			s2 += da * ((a2 - hh) - s2)
			s3 += da * ((a3 - hh) - s3)
			s4 += da * ((a4 - hh) - s4)
			s5 += da * ((a5 - hh) - s5)
			buf[o0 + p0] = s0 * g0 + inp * 0.5
			buf[o1 + p1] = s1 * g1 - inp * 0.5
			buf[o2 + p2] = s2 * g2 + inp * 0.5
			buf[o3 + p3] = s3 * g3 - inp * 0.5
			buf[o4 + p4] = s4 * g4 + inp * 0.5
			buf[o5 + p5] = s5 * g5 - inp * 0.5
			out.l[i] = (a0 - a2 + a4) * 0.6
			out.r[i] = (a1 - a3 + a5) * 0.6
			p0 += 1
			if p0 == d0:
				p0 = 0
			p1 += 1
			if p1 == d1:
				p1 = 0
			p2 += 1
			if p2 == d2:
				p2 = 0
			p3 += 1
			if p3 == d3:
				p3 = 0
			p4 += 1
			if p4 == d4:
				p4 = 0
			p5 += 1
			if p5 == d5:
				p5 = 0
		return out

	## テンポに合わせたピンポンディレイ（左→右→左…）。s にその場で足す。lp_a = 反復ごとの高域の丸め（0〜1、小さいほど暗い）
	static func pingpong(s: Stereo, delay: int, fb: float, mix: float, lp_a: float) -> void:
		var bl := PackedFloat32Array()
		bl.resize(delay)
		var br := PackedFloat32Array()
		br.resize(delay)
		var p := 0
		var sl := 0.0
		var sr_ := 0.0
		for i: int in s.l.size():
			var xl := bl[p]
			var xr := br[p]
			var inp := (s.l[i] + s.r[i]) * 0.5
			sl += lp_a * ((inp + xr * fb) - sl)
			sr_ += lp_a * (xl * fb - sr_)
			bl[p] = sl
			br[p] = sr_
			s.l[i] += xl * mix
			s.r[i] += xr * mix
			p += 1
			if p == delay:
				p = 0

	## ステレオコーラス（左右で逆位相に揺らす）。dry と wet を半々で混ぜる
	static func chorus(s: Stereo, rate: float, base_ms: float, depth_ms: float, mix: float) -> void:
		var size := int((base_ms + depth_ms + 2.0) * 0.001 * SR) + 8
		var bl := PackedFloat32Array()
		bl.resize(size)
		var br := PackedFloat32Array()
		br.resize(size)
		var w := 0
		var ph := 0.0
		var dph := TAU * rate / SR
		var base := base_ms * 0.001 * SR
		var depth := depth_ms * 0.001 * SR
		for i: int in s.l.size():
			bl[w] = s.l[i]
			br[w] = s.r[i]
			var m := sin(ph)
			ph += dph
			var pl := float(w) - (base + depth * m)
			var pr := float(w) - (base - depth * m)
			if pl < 0.0:
				pl += size
			if pr < 0.0:
				pr += size
			var il := int(pl)
			var ir := int(pr)
			var fl := pl - il
			var fr := pr - ir
			var il2 := il + 1
			if il2 == size:
				il2 = 0
			var ir2 := ir + 1
			if ir2 == size:
				ir2 = 0
			var dl := bl[il] * (1.0 - fl) + bl[il2] * fl
			var dr := br[ir] * (1.0 - fr) + br[ir2] * fr
			s.l[i] = s.l[i] * (1.0 - mix * 0.5) + dl * mix
			s.r[i] = s.r[i] * (1.0 - mix * 0.5) + dr * mix
			w += 1
			if w == size:
				w = 0

	## 中央と両脇に分けて両脇を w 倍する（1.0 = そのまま）
	static func width(s: Stereo, w: float) -> void:
		for i: int in s.l.size():
			var m := (s.l[i] + s.r[i]) * 0.5
			var d := (s.l[i] - s.r[i]) * 0.5 * w
			s.l[i] = m + d
			s.r[i] = m - d

	# --- マスター ------------------------------------------------------------------

	## 全部の層の合計から作る共通のゲイン（リミッタ）。各層に同じゲインを掛けて、足した音が thresh を超えないようにする。
	## 32サンプルごとの山を先読み（前後1区画）して、ゲインは直線で結ぶ。戻りは release 秒の指数
	static func limiter_gains(l: PackedFloat32Array, r: PackedFloat32Array, thresh: float, release: float) -> PackedFloat32Array:
		var n := l.size()
		var nb := (n + 31) / 32
		var pk := PackedFloat32Array()
		pk.resize(nb)
		for b: int in nb:
			var m := 0.0
			var end := mini(b * 32 + 32, n)
			for i: int in range(b * 32, end):
				m = maxf(m, maxf(absf(l[i]), absf(r[i])))
			pk[b] = m
		var req := PackedFloat32Array()
		req.resize(nb)
		for b: int in nb:
			var m := pk[b]
			if b > 0:
				m = maxf(m, pk[b - 1])
			if b + 1 < nb:
				m = maxf(m, pk[b + 1])
			req[b] = minf(1.0, thresh / maxf(m, 1e-6))
		var rc := 1.0 - exp(-32.0 / (release * SR))
		var g := PackedFloat32Array()
		g.resize(nb)
		# 曲の終わりの1秒で先に状態を作ってから頭へ（ループの継ぎ目でゲインが跳ばないように）
		var cur := 1.0
		for b: int in range(maxi(nb - 1400, 0), nb):
			cur = minf(req[b], cur + (1.0 - cur) * rc)
		for b: int in nb:
			cur = minf(req[b], cur + (1.0 - cur) * rc)
			g[b] = cur
		return g

	## limiter_gains の結果を掛ける（ブロックの中心どうしを直線で結ぶ）
	static func apply_gains(x: PackedFloat32Array, g: PackedFloat32Array) -> void:
		var n := x.size()
		var nb := g.size()
		for i: int in n:
			var u := (i - 15.5) / 32.0
			var b := int(floor(u))
			var f := u - b
			var g0 := g[clampi(b, 0, nb - 1)]
			var g1 := g[clampi(b + 1, 0, nb - 1)]
			x[i] *= g0 + (g1 - g0) * f

	## 区間 [from, to) の実効値（0 dBFS = 1.0）。ステレオは両チャンネルの平均
	static func rms(l: PackedFloat32Array, r: PackedFloat32Array, from: int, to: int) -> float:
		var s := 0.0
		for i: int in range(from, to):
			s += l[i] * l[i] + r[i] * r[i]
		return sqrt(s / maxf(2.0 * (to - from), 1.0))

	## 音のある所だけの実効値（2048サンプルごとに測って、ほぼ無音の区画は数えない）
	static func active_rms(l: PackedFloat32Array, r: PackedFloat32Array) -> float:
		var s := 0.0
		var cnt := 0
		var n := l.size()
		var i := 0
		while i + 2048 <= n:
			var e := 0.0
			for j: int in range(i, i + 2048):
				e += l[j] * l[j] + r[j] * r[j]
			if e / 4096.0 > 1e-6:
				s += e
				cnt += 4096
			i += 2048
		return sqrt(s / maxf(cnt, 1.0))

	static func to_db(v: float) -> float:
		return 20.0 * log(maxf(v, 1e-9)) / log(10.0)

	## ピアソンの相関（左右）
	static func correlation(l: PackedFloat32Array, r: PackedFloat32Array) -> float:
		var sl := 0.0
		var sr_ := 0.0
		var sll := 0.0
		var srr := 0.0
		var slr := 0.0
		var n := l.size()
		for i: int in n:
			sl += l[i]
			sr_ += r[i]
			sll += l[i] * l[i]
			srr += r[i] * r[i]
			slr += l[i] * r[i]
		var cov := slr / n - (sl / n) * (sr_ / n)
		var vl := sll / n - (sl / n) * (sl / n)
		var vr := srr / n - (sr_ / n) * (sr_ / n)
		return cov / sqrt(maxf(vl * vr, 1e-20))

	## スペクトル重心（Hz）。長さ 4096 の窓を曲の全体から 24 か所取って、音のある窓の平均を返す
	static func centroid(l: PackedFloat32Array, r: PackedFloat32Array) -> float:
		var size := 4096
		var n := l.size()
		var sum := 0.0
		var cnt := 0
		var win := PackedFloat32Array()
		win.resize(size)
		for i: int in size:
			win[i] = 0.5 - 0.5 * cos(TAU * i / size)
		for k: int in 24:
			var at := int((n - size) * (k + 0.5) / 24.0)
			var re := PackedFloat32Array()
			re.resize(size)
			var im := PackedFloat32Array()
			im.resize(size)
			var e := 0.0
			for i: int in size:
				re[i] = (l[at + i] + r[at + i]) * 0.5 * win[i]
				e += re[i] * re[i]
			if e < 1e-4:
				continue
			fft(re, im)
			var num := 0.0
			var den := 0.0
			for i: int in range(1, size / 2):
				var mag := sqrt(re[i] * re[i] + im[i] * im[i])
				num += mag * i
				den += mag
			sum += num / maxf(den, 1e-9) * SR / size
			cnt += 1
		return sum / maxf(cnt, 1)

	## 高さ f 以上の成分のエネルギー比（折り返しノイズや高域の荒れの目安）
	static func high_ratio(l: PackedFloat32Array, r: PackedFloat32Array, f_hz: float) -> float:
		var size := 4096
		var n := l.size()
		var hi := 0.0
		var all := 0.0
		for k: int in 12:
			var at := int((n - size) * (k + 0.5) / 12.0)
			var re := PackedFloat32Array()
			re.resize(size)
			var im := PackedFloat32Array()
			im.resize(size)
			for i: int in size:
				re[i] = (l[at + i] + r[at + i]) * 0.5 * (0.5 - 0.5 * cos(TAU * i / size))
			fft(re, im)
			for i: int in range(1, size / 2):
				var e := re[i] * re[i] + im[i] * im[i]
				all += e
				if i * SR / size >= f_hz:
					hi += e
		return hi / maxf(all, 1e-12)

	## 基数2のFFT（その場で）
	static func fft(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
		var n := re.size()
		var j := 0
		for i: int in range(1, n):
			var bit := n >> 1
			while j & bit:
				j ^= bit
				bit >>= 1
			j ^= bit
			if i < j:
				var tr := re[i]
				re[i] = re[j]
				re[j] = tr
				var ti := im[i]
				im[i] = im[j]
				im[j] = ti
		var len := 2
		while len <= n:
			var ang := -TAU / len
			var wr := cos(ang)
			var wi := sin(ang)
			var i := 0
			while i < n:
				var cr := 1.0
				var ci := 0.0
				for k: int in len / 2:
					var ur := re[i + k]
					var ui := im[i + k]
					var vr := re[i + k + len / 2] * cr - im[i + k + len / 2] * ci
					var vi := re[i + k + len / 2] * ci + im[i + k + len / 2] * cr
					re[i + k] = ur + vr
					im[i + k] = ui + vi
					re[i + k + len / 2] = ur - vr
					im[i + k + len / 2] = ui - vi
					var ncr := cr * wr - ci * wi
					ci = cr * wi + ci * wr
					cr = ncr
				i += len
			len <<= 1

# --- BGM（5曲を別スレッドで）----------------------------------------------------

const TRACKS: PackedStringArray = ["morning", "noon", "evening", "night", "menu"]
const STEMS: PackedStringArray = ["drums", "bass", "lead"]
## Ogg Vorbis の品質（層ごと。ドラムは高域が多いので高め）
const OGG_QUALITY: Array[float] = [4.0, 3.0, 3.5]


func _build_music() -> void:
	var todo: PackedStringArray = []
	for t: String in TRACKS:
		if _wants(t):
			todo.append(t)
	if todo.is_empty():
		return
	var use_ffmpeg := not _keep_wav and OS.execute("ffmpeg", ["-version"], []) == 0
	if not use_ffmpeg:
		print("build_audio: ffmpeg が無い（または --wav）ので BGM は WAV のまま書き出す（容量が大きい）")
	var threads: Array[Thread] = []
	for t: String in todo:
		var th := Thread.new()
		th.start(_make_track.bind(t, use_ffmpeg))
		threads.append(th)
	for th: Thread in threads:
		_print_report(th.wait_to_finish() as Dictionary)


## 1曲を作って3つの層を書き出す（スレッドで走る）
func _make_track(id: String, use_ffmpeg: bool) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var song := Song.new()
	var rep: Dictionary = song.build(id, DEFS[id])
	var stems: Array = rep["audio"]
	rep.erase("audio")
	var loop_s: float = float(rep["loop_start"]) / SR
	var bytes := PackedInt32Array()
	for k: int in 3:
		var st: Stereo = stems[k]
		var base := "music_%s_%s" % [id, STEMS[k]]
		var ch: Array[PackedFloat32Array] = [st.l, st.r]
		if use_ffmpeg:
			var tmp_wav := ProjectSettings.globalize_path(TMP + base + ".wav")
			_write_wav(TMP + base + ".wav", ch, SR, -1)
			var ogg := ProjectSettings.globalize_path(OUT + base + ".ogg")
			var args := PackedStringArray(["-y", "-v", "error", "-i", tmp_wav, "-map_metadata", "-1",
					"-c:a", "libvorbis", "-q:a", str(OGG_QUALITY[k]), ogg])
			var output: Array = []
			var code := OS.execute("ffmpeg", args, output, true)
			DirAccess.remove_absolute(tmp_wav)
			if code != 0:
				push_error("ffmpeg が失敗した（%s）: %s" % [base, output])
			_write_ogg_import(base, loop_s)
			bytes.append(FileAccess.get_file_as_bytes(OUT + base + ".ogg").size())
		else:
			_write_wav(OUT + base + ".wav", ch, SR, int(rep["loop_start"]))
			bytes.append(FileAccess.get_file_as_bytes(OUT + base + ".wav").size())
	rep["bytes"] = bytes
	rep["secs"] = (Time.get_ticks_msec() - t0) / 1000.0
	rep["ogg"] = use_ffmpeg
	return rep


## .ogg.import を書く（ループは loop_offset = イントロの長さ）。あれば uid などはそのまま、ループの2行だけ直す
func _write_ogg_import(base: String, loop_s: float) -> void:
	var path := OUT + base + ".ogg.import"
	var off := "loop_offset=%s" % String.num(loop_s, 6)
	var text := ""
	if FileAccess.file_exists(path):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			if lines[i].begins_with("loop="):
				lines[i] = "loop=true"
			elif lines[i].begins_with("loop_offset="):
				lines[i] = off
		text = "\n".join(lines)
	else:
		text = "[remap]\n\nimporter=\"oggvorbisstr\"\ntype=\"AudioStreamOggVorbis\"\n\n[deps]\n\nsource_file=\"%s%s.ogg\"\n\n[params]\n\nloop=true\n%s\nbpm=0\nbeat_count=0\nbar_beats=4\n" % [OUT, base, off]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _print_report(r: Dictionary) -> void:
	var lines: PackedStringArray = []
	var mb := 0.0
	for b: int in r["bytes"]:
		mb += b / 1048576.0
	lines.append("== %s  %.0f BPM  %s  loop from %.1f s, loop body %s  (%s %.1f MB, built in %.0f s)" % [
			r["id"], r["bpm"], _mmss(r["dur"]), r["loop_start"] / float(SR), _mmss(r["dur"] - r["loop_start"] / float(SR)),
			"ogg" if r["ogg"] else "wav", mb, r["secs"]])
	lines.append("   peak dBFS: all 3 layers %.2f | drums+bass %.2f | drums %.2f | bass+lead %.2f   (limiter max reduction %.1f dB)" % [
			r["peak_all"], r["peak_db"], r["peak_d"], r["peak_bl"], r["gr"]])
	lines.append("   stereo correlation L/R %.3f | energy above 16 kHz %.2f%% | all-layer RMS %.1f dBFS" % [r["corr"], r["hf"] * 100.0, r["rms_all"]])
	var st := ""
	for s: Array in r["stems"]:
		st += "%s: rms %.1f dB, centroid %.0f Hz, peak %.1f dB   " % [s[0], s[1], s[2], s[3]]
	lines.append("   layers  " + st)
	var sec := ""
	for s: Array in r["sections"]:
		sec += "%s %.1f | " % [s[0], s[1]]
	lines.append("   RMS dBFS per section (all layers): " + sec)
	print("\n".join(lines))


func _mmss(sec: float) -> String:
	return "%d:%04.1f" % [int(sec) / 60, fmod(sec, 60.0)]


## 1曲の組み立て。TRACK の定義（下の DEFS）を読んで、ドラム・ベース・パッド・コード刻み・リード・アルペジオを鳴らす位置に置き、
## 層ごとに整えて（飽和・幅・残響）、3層をまとめてリミッタに通す。
## 時間は「小節 × 16分音符」で数える（1小節 = 16 ステップ、小節は曲の頭から数えた通し番号）
class Song extends RefCounted:
	const ROOTS: Dictionary = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
			"G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
	const QUALS: Dictionary = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10],
			"m9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14], "6": [0, 4, 7, 9], "sus4": [0, 5, 7], "7sus4": [0, 5, 7, 10],
			"5": [0, 7, 12], "add9": [0, 4, 7, 14], "m6": [0, 3, 7, 9], "9": [0, 4, 7, 10, 14], "dim": [0, 3, 6]}
	const MAJOR: Array[int] = [0, 2, 4, 5, 7, 9, 11]
	const MINOR: Array[int] = [0, 2, 3, 5, 7, 8, 10]
	const TAIL_SEC := 4.0

	var id: String
	var def: Dictionary
	var rng := RandomNumberGenerator.new()
	var noise_n: int = 0
	var bpm: float
	var step_len: float      ## 16分音符のサンプル数
	var bar_len: float
	var swing: float
	var key_pc: int
	var n: int               ## 曲の長さ（サンプル）
	var buf_n: int           ## 作業用の長さ（曲 + 残響のしっぽ）
	var tail: int
	var loop_start: int
	var secs: Array[Dictionary] = []
	var kit: Dictionary = {}
	var cache: Dictionary = {}
	var chord_cache: Dictionary = {}
	var scale_notes: Array[int] = []
	var voicing_prev: Dictionary = {}
	var hit_count: Dictionary = {}
	var timing: bool = false
	var t_last: int = 0
	var kick_at: Array[int] = []
	var kick_vel: Array[float] = []
	var drum: Stereo
	var bass: Stereo
	var pad: Stereo
	var comp_b: Stereo
	var comp_l: Stereo
	var lead: Stereo
	var arp: Stereo

	func build(p_id: String, p_def: Dictionary) -> Dictionary:
		id = p_id
		def = p_def
		rng.seed = hash(id) + 7
		timing = OS.get_cmdline_user_args().has("--timing")
		t_last = Time.get_ticks_msec()
		_setup()
		kit = _make_kit(str(def["kit"]))
		_log("kit")
		_compose()
		_log("compose")
		return _master()

	## --timing を付けると、各段階にかかった時間を出す（遅い所を探す用）
	func _log(label: String) -> void:
		if timing:
			var now := Time.get_ticks_msec()
			print("  [%s] %s %.1f s" % [id, label, (now - t_last) / 1000.0])
			t_last = now

	func _setup() -> void:
		bpm = float(def["bpm"])
		step_len = 60.0 / bpm / 4.0 * SR
		bar_len = step_len * 16.0
		swing = float(def.get("swing", 0.0))
		key_pc = int(def["key"])
		var scale: Array[int] = MINOR if bool(def["minor"]) else MAJOR
		for midi: int in range(24, 110):
			if scale.has(posmod(midi - key_pc, 12)):
				scale_notes.append(midi)
		var bar0 := 0
		for sec: Dictionary in def["sections"]:
			var s := sec.duplicate()
			var pbars := 0
			for e: Array in def["progs"][sec["prog"]]:
				pbars += int(e[1])
			s["bars"] = int(sec.get("bars", pbars))
			s["bar0"] = bar0
			secs.append(s)
			bar0 += int(s["bars"])
		var loop_bars := 0
		for i: int in int(def["loop_from"]):
			loop_bars += int(secs[i]["bars"])
		n = int(round(bar0 * bar_len))
		loop_start = int(round(loop_bars * bar_len))
		tail = int(TAIL_SEC * SR)
		buf_n = n + tail
		drum = Stereo.new(buf_n)
		bass = Stereo.new(buf_n)
		pad = Stereo.new(buf_n)
		comp_b = Stereo.new(buf_n)
		comp_l = Stereo.new(buf_n)
		lead = Stereo.new(buf_n)
		arp = Stereo.new(buf_n)

	# --- 楽理 ------------------------------------------------------------------------

	func _hz(m: float) -> float:
		return 440.0 * pow(2.0, (m - 69.0) / 12.0)

	func _noise(len: int) -> PackedFloat32Array:
		noise_n += 1
		return Dsp.noise(len, rng.randi() + noise_n * 7919)

	func _at(bar: int, step: int) -> int:
		var s := float(step)
		if swing > 0.0 and step % 2 == 1:
			s += swing * 2.0   # 奇数番（裏）の16分を後ろへ。swing = 8分音符の何割（0.17 で3連ノリ）
		return int(round((bar * 16.0 + s) * step_len))

	## コード名 → {root: 0〜11, core: [根音からの音程 0〜11 の昇順（7thまで）], pcs: [9thなども含む]}
	func _chord(nm: String) -> Dictionary:
		if chord_cache.has(nm):
			return chord_cache[nm]
		var rl := 2 if nm.length() > 1 and (nm[1] == "#" or nm[1] == "b") else 1
		var root: int = ROOTS[nm.substr(0, rl)]
		var iv: Array = QUALS[nm.substr(rl)]
		var core: Array[int] = []
		var pcs: Array[int] = []
		for v: int in iv:
			if v < 12 and not core.has(v):
				core.append(v)
			if not pcs.has(v % 12):
				pcs.append(v % 12)
		core.sort()
		pcs.sort()
		var ch := {"root": root, "core": core, "pcs": pcs}
		chord_cache[nm] = ch
		return ch

	## 小節 b にあるコード
	func _chord_at(chords: Array[Dictionary], b: int) -> Dictionary:
		for c: Dictionary in chords:
			if b >= int(c["bar"]) and b < int(c["bar"]) + int(c["bars"]):
				return _chord(str(c["name"]))
		return _chord(str(chords[chords.size() - 1]["name"]))

	## コードの構成音（MIDI）を center の近くで昇順に並べたもの
	func _tones(ch: Dictionary, center: float, ext: bool) -> Array[int]:
		var pcs: Array = ch["pcs"] if ext else ch["core"]
		var out: Array[int] = []
		for midi: int in range(int(center) - 30, int(center) + 31):
			if pcs.has(posmod(midi - int(ch["root"]), 12)):
				out.append(midi)
		return out

	## count 個の構成音を重ねた響き。center に近く、前の響きからなるべく動かない転回を選ぶ（声部の動きを滑らかに）
	func _voice(ch: Dictionary, count: int, center: float, prev: Array[int], ext: bool) -> Array[int]:
		var tones := _tones(ch, center, ext)
		var best: Array[int] = []
		var best_cost := 1e9
		for start: int in range(0, tones.size() - count + 1):
			var cand := tones.slice(start, start + count)
			var avg := 0.0
			for v: int in cand:
				avg += v
			var cost := absf(avg / count - center) * 1.2
			if prev.size() == count:
				for i: int in count:
					cost += absf(cand[i] - prev[i]) * 0.8
			if cost < best_cost:
				best_cost = cost
				best = cand
		return best

	## center に一番近い構成音を 0 として、k 番目上（負なら下）の構成音
	func _ct(ch: Dictionary, center: float, k: int, ext: bool) -> int:
		var tones := _tones(ch, center, ext)
		var near := 0
		for i: int in tones.size():
			if absf(tones[i] - center) < absf(tones[near] - center):
				near = i
		return tones[clampi(near + k, 0, tones.size() - 1)]

	## 調の音階で from から steps 段（負なら下）動かした音
	func _scale_step(from: int, steps: int) -> int:
		var near := 0
		for i: int in scale_notes.size():
			if absf(scale_notes[i] - from) < absf(scale_notes[near] - from):
				near = i
		return scale_notes[clampi(near + steps, 0, scale_notes.size() - 1)]

	# --- ドラムの音色 ----------------------------------------------------------------------

	func _fade_out(x: PackedFloat32Array, secs: float) -> void:
		var m := mini(int(secs * SR), x.size())
		var sz := x.size()
		for i: int in m:
			x[sz - 1 - i] *= float(i) / m

	## キック：周波数が指数で下がる正弦波 + 頭の「カツッ」（雑音と短い高音）+ 軽い飽和
	func _kick(f0: float, f1: float, pd: float, ad: float, dur: float, click: float, drive: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var out := PackedFloat32Array()
		out.resize(len)
		var ph := 0.0
		for i: int in len:
			var t := float(i) / SR
			ph += TAU * (f1 + (f0 - f1) * exp(-t / pd)) / SR
			out[i] = sin(ph) * exp(-t / ad) * minf(t / 0.0008, 1.0)
		var c := Dsp.hp1(_noise(int(SR * 0.012)), 2500.0)
		Dsp.env_ad(c, 0.0002, 0.0025)
		Dsp.add(out, c, 0, click)
		var blip := Dsp.sine(int(SR * 0.006), 1700.0, 0.0)
		Dsp.env_ad(blip, 0.0001, 0.0018)
		Dsp.add(out, blip, 0, click * 0.6)
		Dsp.softclip(out, drive)
		_fade_out(out, 0.012)
		return Dsp.normalized(out, 0.95)

	## スネア：胴鳴り（2つの音、頭で少し高い）+ 雑音の帯域。gate > 0 ならゲートリバーブ（長い雑音を急に切る）
	func _snare(tone: float, tone_dec: float, noise_dec: float, hp: float, lp: float, tone_mix: float,
			dur: float, drive: float, gate: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var nz := Dsp.bp2(_noise(len), hp, lp)
		Dsp.env_ad(nz, 0.0006, noise_dec)
		var out := PackedFloat32Array()
		out.resize(len)
		var ph := 0.0
		var ph2 := 0.0
		for i: int in len:
			var t := float(i) / SR
			var fm := tone * (1.0 + 0.28 * exp(-t / 0.012))
			ph += TAU * fm / SR
			ph2 += TAU * fm * 1.51 / SR
			out[i] = (sin(ph) + 0.45 * sin(ph2)) * exp(-t / tone_dec) * tone_mix + nz[i]
		if gate > 0.0:
			var gl := mini(int(gate * SR), len)
			var wash := Dsp.bp2(_noise(len), 450.0, 6500.0)
			var fade := int(0.005 * SR)
			for i: int in gl:
				var e := pow(1.0 - float(i) / gl, 0.6) * minf(float(i) / (0.002 * SR), 1.0)
				if gl - i < fade:
					e *= float(gl - i) / fade
				out[i] += wash[i] * e * 0.55
		Dsp.softclip(out, drive)
		_fade_out(out, 0.006)
		return Dsp.normalized(out, 0.9)

	## クラップ：短い雑音を数回ずらして重ね、最後に少し長く残す
	func _clap(bursts: int, spacing_ms: float, tail_dec: float, lo: float, hi: float, dur: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var out := PackedFloat32Array()
		out.resize(len)
		for b: int in bursts:
			var at := int(b * spacing_ms * 0.001 * SR)
			var piece := Dsp.bp2(_noise(len - at), lo, hi)
			Dsp.env_ad(piece, 0.0004, tail_dec if b == bursts - 1 else 0.007)
			Dsp.add(out, piece, at, 1.0 if b == bursts - 1 else 0.7)
		_fade_out(out, 0.006)
		return Dsp.normalized(out, 0.9)

	## ハイハット：高域の雑音 + 非整数倍の金属的な正弦波（metal = 金属音の割合）
	func _hat(decay: float, hp: float, metal: float, dur: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var nz := Dsp.hp1(Dsp.hp1(_noise(len), hp), hp)
		var m := PackedFloat32Array()
		m.resize(len)
		for f: float in [3150.0, 4390.0, 5330.0, 6370.0, 7210.0, 8870.0]:
			var w := TAU * f * rng.randf_range(0.97, 1.03) / SR
			var p0 := rng.randf() * TAU
			for i: int in len:
				m[i] += sin(p0 + w * i)
		m = Dsp.hp1(m, hp * 0.8)
		for i: int in len:
			nz[i] = nz[i] * (1.0 - metal) + m[i] * metal * 0.16
		Dsp.env_ad(nz, 0.0003, decay)
		_fade_out(nz, 0.004)
		return Dsp.normalized(nz, 0.9)

	func _shaker(lo: float, hi: float, att: float, dec: float, dur: float) -> PackedFloat32Array:
		var out := Dsp.bp2(_noise(int(SR * dur)), lo, hi)
		Dsp.env_ad(out, att, dec)
		_fade_out(out, 0.004)
		return Dsp.normalized(out, 0.9)

	func _tom(f: float, dec: float, dur: float, sweep: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var out := PackedFloat32Array()
		out.resize(len)
		var ph := 0.0
		for i: int in len:
			var t := float(i) / SR
			ph += TAU * f * (1.0 + sweep * exp(-t / 0.03)) / SR
			out[i] = sin(ph) * exp(-t / dec) * minf(t / 0.001, 1.0)
		var c := Dsp.bp2(_noise(int(SR * 0.02)), 800.0, 4000.0)
		Dsp.env_ad(c, 0.0002, 0.004)
		Dsp.add(out, c, 0, 0.3)
		Dsp.softclip(out, 1.4)
		_fade_out(out, 0.01)
		return Dsp.normalized(out, 0.9)

	## シンバル（クラッシュ・ライド）：雑音と、バラバラの高さの正弦波の長い響き
	func _cymbal(dur: float, dec: float, hp: float, bell: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var out := Dsp.hp1(Dsp.hp1(_noise(len), hp), hp)
		Dsp.env_ad(out, 0.002, dec)
		for f: float in [2180.0, 3320.0, 4470.0, 5630.0, 7110.0, 8440.0]:
			var tone := Dsp.sine(len, f * rng.randf_range(0.98, 1.02), rng.randf() * TAU)
			Dsp.env_ad(tone, 0.001, dec * 0.8)
			Dsp.add(out, tone, 0, 0.05 * bell)
		_fade_out(out, 0.05)
		return Dsp.normalized(out, 0.9)

	## 金属を叩く音（昼の工事現場）：調和しない比の倍音が次々に消える
	func _clang(base: float, dec: float, dur: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var out := PackedFloat32Array()
		out.resize(len)
		var ratios: Array[float] = [1.0, 2.76, 5.40, 8.93, 13.34]
		var amps: Array[float] = [1.0, 0.7, 0.5, 0.35, 0.25]
		for k: int in ratios.size():
			var tone := Dsp.sine(len, base * ratios[k] * rng.randf_range(0.99, 1.01), rng.randf() * TAU)
			Dsp.env_ad(tone, 0.0005, dec / (1.0 + k * 0.7))
			Dsp.add(out, tone, 0, amps[k])
		var c := Dsp.bp2(_noise(int(SR * 0.02)), 2000.0, 7000.0)
		Dsp.env_ad(c, 0.0002, 0.004)
		Dsp.add(out, c, 0, 0.8)
		_fade_out(out, 0.02)
		return Dsp.normalized(out, 0.85)

	## 盛り上げ（雑音の通過帯域が f0 → f1 へ上がり、音量も上がる）
	func _riser(dur: float, f0: float, f1: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var nz := _noise(len)
		var out := PackedFloat32Array()
		out.resize(len)
		var low := 0.0
		var band := 0.0
		var ff := 0.1
		for i: int in len:
			var u := float(i) / len
			if i & 15 == 0:
				ff = 2.0 * sin(PI * minf(f0 * pow(f1 / f0, u), 6500.0) / SR)
			low += ff * band
			var high := nz[i] - low - 0.45 * band
			band += ff * high
			out[i] = (band * 0.8 + high * 0.4) * u * u
		_fade_out(out, 0.006)   # 区切りの拍で切れる。ループの継ぎ目で雑音がぶつっと切れないように
		return Dsp.normalized(out, 0.9)

	## 区切りの重い一撃（低い正弦波の長い減衰 + 雑音の尾）
	func _impact(dur: float) -> PackedFloat32Array:
		var len := int(SR * dur)
		var out := Dsp.thump(len, 42.0, 0.9, 1.0)
		var nz := Dsp.bp2(_noise(len), 120.0, 2200.0)
		Dsp.env_ad(nz, 0.002, 0.45)
		Dsp.add(out, nz, 0, 0.5)
		_fade_out(out, 0.05)
		return Dsp.normalized(out, 0.95)

	func _inst(variants: Array, gain: float, pan: float, alt: bool = false) -> Dictionary:
		return {"v": variants, "gain": gain, "pan": pan, "alt": alt}

	## 曲ごとのドラムセット。キー: k キック / s スネア / g ゴースト / c クラップ / h ハット / o オープンハット / r シェイカー・ライド /
	## n リム・刻み / m 金属 / t u v タム（高・中・低）/ x クラッシュ
	func _make_kit(kind: String) -> Dictionary:
		var k: Dictionary = {}
		if kind == "house":
			k["k"] = _inst([_kick(175.0, 46.0, 0.028, 0.19, 0.38, 0.5, 1.8)], 1.0, 0.0)
			var clap := _clap(4, 9.0, 0.14, 1000.0, 3800.0, 0.34)
			Dsp.add(clap, _snare(185.0, 0.06, 0.05, 1500.0, 8000.0, 0.7, 0.2, 1.2, 0.0), 0, 0.35)
			k["c"] = _inst([clap], 0.8, 0.0)
			k["s"] = _inst([_snare(190.0, 0.08, 0.11, 1400.0, 8500.0, 0.6, 0.3, 1.5, 0.0)], 0.8, 0.0)
			k["h"] = _inst([_hat(0.028, 8000.0, 0.4, 0.12), _hat(0.036, 7500.0, 0.4, 0.15), _hat(0.046, 7000.0, 0.4, 0.15)], 0.5, 0.3, true)
			k["o"] = _inst([_hat(0.16, 6500.0, 0.5, 0.5)], 0.42, 0.2, true)
			k["r"] = _inst([_shaker(5500.0, 10000.0, 0.008, 0.04, 0.12)], 0.4, 0.45, true)
			var rim := Dsp.sine(int(SR * 0.05), 820.0, 0.0)
			Dsp.env_ad(rim, 0.0003, 0.012)
			Dsp.add(rim, Dsp.bp2(_noise(int(SR * 0.05)), 2000.0, 6000.0), 0, 0.15)
			k["n"] = _inst([Dsp.normalized(rim, 0.8)], 0.5, -0.4, true)
			k["x"] = _inst([_cymbal(2.4, 0.9, 3000.0, 1.0)], 0.5, 0.0)
		elif kind == "break":
			k["k"] = _inst([_kick(160.0, 52.0, 0.022, 0.14, 0.3, 0.65, 2.6)], 1.0, 0.0)
			k["s"] = _inst([_snare(200.0, 0.09, 0.15, 1300.0, 9000.0, 0.55, 0.4, 2.0, 0.0),
					_snare(205.0, 0.1, 0.18, 1200.0, 9500.0, 0.6, 0.42, 2.2, 0.0)], 0.95, 0.0)
			k["g"] = _inst([_snare(210.0, 0.05, 0.07, 1500.0, 8000.0, 0.4, 0.2, 1.5, 0.0)], 0.6, 0.0)
			k["h"] = _inst([_hat(0.024, 8200.0, 0.6, 0.12), _hat(0.03, 7600.0, 0.6, 0.14), _hat(0.038, 7000.0, 0.6, 0.15)], 0.5, 0.3, true)
			k["o"] = _inst([_hat(0.13, 6800.0, 0.6, 0.4)], 0.45, -0.25)
			k["m"] = _inst([_clang(330.0, 0.5, 0.9), _clang(520.0, 0.4, 0.8), _clang(790.0, 0.3, 0.7)], 0.55, 0.35, true)
			var rv := Dsp.bp2(_noise(int(SR * 0.04)), 3000.0, 6500.0)
			Dsp.env_ad(rv, 0.0002, 0.005)
			k["n"] = _inst([Dsp.normalized(rv, 0.8)], 0.5, -0.5, true)
			k["t"] = _inst([_tom(190.0, 0.18, 0.4, 0.5)], 0.8, -0.3)
			k["u"] = _inst([_tom(140.0, 0.22, 0.45, 0.5)], 0.8, 0.0)
			k["v"] = _inst([_tom(98.0, 0.28, 0.5, 0.5)], 0.85, 0.3)
			k["x"] = _inst([_cymbal(2.0, 0.7, 3500.0, 1.2)], 0.5, 0.0)
		elif kind == "synth":
			k["k"] = _inst([_kick(130.0, 50.0, 0.040, 0.26, 0.45, 0.35, 1.5)], 1.0, 0.0)
			var gs := _snare(200.0, 0.1, 0.12, 1500.0, 9000.0, 0.65, 0.5, 1.5, 0.3)
			Dsp.add(gs, _clap(3, 10.0, 0.1, 1100.0, 4200.0, 0.4), 0, 0.45)
			k["s"] = _inst([gs], 0.95, 0.0)
			k["c"] = _inst([_clap(4, 11.0, 0.1, 1100.0, 4200.0, 0.34)], 0.6, 0.0)
			k["h"] = _inst([_hat(0.03, 7800.0, 0.35, 0.12), _hat(0.04, 7200.0, 0.35, 0.14)], 0.42, 0.3, true)
			k["o"] = _inst([_hat(0.2, 6500.0, 0.45, 0.55)], 0.4, 0.25)
			k["r"] = _inst([_shaker(4500.0, 9500.0, 0.012, 0.05, 0.14)], 0.38, 0.4, true)
			k["t"] = _inst([_tom(230.0, 0.25, 0.5, 0.9)], 0.8, -0.5)
			k["u"] = _inst([_tom(170.0, 0.28, 0.55, 0.9)], 0.8, -0.1)
			k["v"] = _inst([_tom(122.0, 0.32, 0.6, 0.9)], 0.85, 0.4)
			k["x"] = _inst([_cymbal(2.6, 1.0, 3200.0, 0.9)], 0.5, 0.0)
		elif kind == "dnb":
			k["k"] = _inst([_kick(150.0, 48.0, 0.020, 0.13, 0.27, 0.6, 1.9)], 1.0, 0.0)
			k["s"] = _inst([_snare(215.0, 0.07, 0.10, 1600.0, 9500.0, 0.5, 0.3, 1.7, 0.0),
					_snare(222.0, 0.075, 0.12, 1500.0, 9500.0, 0.55, 0.32, 1.9, 0.0)], 0.95, 0.0)
			k["g"] = _inst([_snare(225.0, 0.04, 0.05, 1800.0, 9000.0, 0.35, 0.18, 1.3, 0.0)], 0.5, 0.0)
			k["h"] = _inst([_hat(0.016, 8800.0, 0.35, 0.1), _hat(0.022, 8200.0, 0.35, 0.12), _hat(0.03, 7600.0, 0.35, 0.14)], 0.45, 0.3, true)
			k["o"] = _inst([_hat(0.1, 7000.0, 0.45, 0.35)], 0.4, -0.2)
			k["r"] = _inst([_cymbal(1.1, 0.35, 5500.0, 1.4)], 0.32, 0.35, true)
			k["q"] = _inst([_shaker(6000.0, 11000.0, 0.006, 0.03, 0.1)], 0.3, 0.5, true)
			k["x"] = _inst([_cymbal(2.4, 0.9, 3500.0, 1.0)], 0.5, 0.0)
		else:  # soft（メニュー）
			k["k"] = _inst([_kick(105.0, 52.0, 0.04, 0.3, 0.5, 0.15, 1.2)], 0.9, 0.0)
			var brush := Dsp.bp2(_noise(int(SR * 0.3)), 1800.0, 7500.0)
			Dsp.env_ad(brush, 0.012, 0.11)
			Dsp.add(brush, Dsp.sine(int(SR * 0.3), 190.0, 0.0), 0, 0.0)
			var body := Dsp.sine(int(SR * 0.3), 185.0, 0.0)
			Dsp.env_ad(body, 0.001, 0.05)
			Dsp.add(brush, body, 0, 0.5)
			_fade_out(brush, 0.02)
			k["s"] = _inst([Dsp.normalized(brush, 0.8)], 0.6, 0.0)
			k["h"] = _inst([_hat(0.04, 7000.0, 0.3, 0.14), _hat(0.05, 6500.0, 0.3, 0.16)], 0.34, 0.3, true)
			k["o"] = _inst([_hat(0.22, 6000.0, 0.35, 0.6)], 0.3, 0.2)
			k["r"] = _inst([_shaker(4000.0, 9000.0, 0.015, 0.06, 0.16)], 0.3, 0.4, true)
			var wood := Dsp.sine(int(SR * 0.08), 1180.0, 0.0)
			Dsp.env_ad(wood, 0.0004, 0.014)
			Dsp.add(wood, Dsp.sine(int(SR * 0.08), 1930.0, 0.0), 0, 0.3)
			k["n"] = _inst([Dsp.normalized(wood, 0.7)], 0.4, -0.4, true)
			k["x"] = _inst([_cymbal(3.0, 1.4, 3500.0, 0.7)], 0.3, 0.0)
		return k

	# --- 音色（メロディ・ベース・パッド）------------------------------------------------------

	## ノコギリ波ベース（またはパルス波）。フィルタの口が音の頭で開いて閉じる + 下のサイン + 飽和
	func _bass_saw(midi: int, len: int, p: Dictionary) -> PackedFloat32Array:
		var f := _hz(midi)
		var rel := int(0.02 * SR)
		var sz := len + rel
		var out := PackedFloat32Array()
		out.resize(sz)
		var dt := f / SR
		var ph := 0.0
		var sph := 0.0
		var low := 0.0
		var band := 0.0
		var ff := 0.1
		var k := 1.0 / float(p.get("q", 1.5))
		var cut_hi: float = float(p.get("cut_hi", 1800.0))
		var cut_lo: float = float(p.get("cut_lo", 300.0))
		var env: float = float(p.get("env", 0.08))
		var sub: float = float(p.get("sub", 0.5))
		var drive: float = float(p.get("drive", 1.3))
		var pulse_mix: float = float(p.get("pulse", 0.0))
		var inv_drive := 1.0 / drive
		for i: int in sz:
			var t := float(i) / SR
			var s := Dsp.saw(ph, dt)
			if pulse_mix > 0.0:
				s = s * (1.0 - pulse_mix) + Dsp.pulse(ph, dt, 0.5) * pulse_mix
			ph += dt
			if ph >= 1.0:
				ph -= 1.0
			if i & 15 == 0:
				ff = 2.0 * sin(PI * minf(cut_lo + (cut_hi - cut_lo) * exp(-t / env), 4500.0) / SR)
			low += ff * band
			var high := s - low - k * band
			band += ff * high
			var y := low + sub * sin(sph)
			sph += TAU * f / SR
			var a := minf(float(i) / (0.003 * SR), 1.0)
			if i >= len:
				a *= 1.0 - float(i - len) / rel
			out[i] = tanh(y * drive) * inv_drive * a
		return out

	## サブベース：サイン波を軽く歪ませて（小さいスピーカーでも聞こえるように）倍音を足す
	func _bass_sub(midi: int, len: int, p: Dictionary) -> PackedFloat32Array:
		var f := _hz(midi)
		var rel := int(float(p.get("rel", 0.06)) * SR)
		var sz := len + rel
		var out := PackedFloat32Array()
		out.resize(sz)
		var drive: float = float(p.get("drive", 1.8))
		var inv_drive := 1.0 / drive
		var an := float(p.get("att", 0.012)) * SR
		var ph := 0.0
		var w := TAU * f / SR
		for i: int in sz:
			var a := minf(float(i) / an, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			if i >= len:
				a *= 1.0 - float(i - len) / rel
			out[i] = tanh(sin(ph) * drive) * inv_drive * a
			ph += w
		return out

	## リース（ドラムンベースの太いベース）：少しずれた3本のノコギリ波をゆっくり揺れるローパスに通す
	func _bass_reese(midi: int, len: int, p: Dictionary) -> PackedFloat32Array:
		var f := _hz(midi)
		var rel := int(0.05 * SR)
		var sz := len + rel
		var out := PackedFloat32Array()
		out.resize(sz)
		var d1 := f / SR * 0.9945
		var d2 := f / SR
		var d3 := f / SR * 1.0055
		var p1 := 0.0
		var p2 := 0.37
		var p3 := 0.71
		var low := 0.0
		var band := 0.0
		var ff := 0.1
		var cut: float = float(p.get("cut", 700.0))
		var depth: float = float(p.get("depth", 0.6))
		var lfo: float = float(p.get("lfo", 0.6))
		var drive: float = float(p.get("drive", 1.5))
		var inv_drive := 1.0 / drive
		var sph := 0.0
		for i: int in sz:
			var t := float(i) / SR
			var s := (Dsp.saw(p1, d1) + Dsp.saw(p2, d2) + Dsp.saw(p3, d3)) * 0.33
			p1 += d1
			if p1 >= 1.0:
				p1 -= 1.0
			p2 += d2
			if p2 >= 1.0:
				p2 -= 1.0
			p3 += d3
			if p3 >= 1.0:
				p3 -= 1.0
			if i & 15 == 0:
				ff = 2.0 * sin(PI * minf(cut * pow(2.0, depth * sin(TAU * lfo * t)), 3800.0) / SR)
			low += ff * band
			var high := s - low - 0.9 * band
			band += ff * high
			var y := low + 0.5 * sin(sph)
			sph += TAU * f * 0.5 / SR
			var a := minf(float(i) / (0.01 * SR), 1.0)
			if i >= len:
				a *= 1.0 - float(i - len) / rel
			out[i] = tanh(y * drive) * inv_drive * a
		return out

	## 厚いパッド：少しずつ音程をずらしたノコギリ波を重ねる（ステレオに散らす）
	func _render_pad(notes: Array[int], len: int, pd: Dictionary) -> Stereo:
		var st := Stereo.new(len)
		var voices := int(pd["voices"])
		var spread: float = float(pd["spread"])
		var width: float = float(pd.get("width", 0.9))
		var nt := notes.size()
		var norm := 1.0 / sqrt(float(voices * nt))
		for ni: int in nt:
			for v: int in voices:
				var u := float(v) / maxf(voices - 1, 1) * 2.0 - 1.0
				var f := _hz(notes[ni]) * pow(2.0, (spread * u + rng.randf_range(-1.5, 1.5)) / 1200.0)
				var dt := f / SR
				var ph := rng.randf()
				var pan := clampf(width * (u * 0.9 + rng.randf_range(-0.15, 0.15)), -1.0, 1.0)
				var ang := (pan + 1.0) * PI * 0.25
				var gl := cos(ang) * norm
				var gr := sin(ang) * norm
				for i: int in len:
					var s := Dsp.saw(ph, dt)
					ph += dt
					if ph >= 1.0:
						ph -= 1.0
					st.l[i] += s * gl
					st.r[i] += s * gr
		var an := maxi(int(float(pd["att"]) * SR), 1)
		var rn := maxi(int(float(pd["rel"]) * SR), 1)
		for i: int in len:
			var e := minf(float(i) / an, 1.0) * minf(float(len - i) / rn, 1.0)
			e = e * e * (3.0 - 2.0 * e)
			st.l[i] *= e
			st.r[i] *= e
		return st

	## 和音の刻み（ハウスのオルガン風スタブ）：短く鳴って閉じる。口の開き（cut_hi → cut_lo）と減衰（dec）で形が変わる
	func _render_stab(notes: Array[int], len: int, p: Dictionary) -> Stereo:
		var rel := int(0.05 * SR)
		var sz := len + rel
		var st := Stereo.new(sz)
		var nt := notes.size()
		for ni: int in nt:
			var pan := (float(ni) / maxf(nt - 1, 1) - 0.5) * 0.9
			var ang := (pan + 1.0) * PI * 0.25
			var gl := cos(ang) * 0.35
			var gr := sin(ang) * 0.35
			for v: int in 2:
				var dt := _hz(notes[ni]) * (1.0 + (v * 2 - 1) * 0.0045) / SR
				var ph := rng.randf()
				for i: int in sz:
					var s := Dsp.saw(ph, dt)
					ph += dt
					if ph >= 1.0:
						ph -= 1.0
					st.l[i] += s * gl
					st.r[i] += s * gr
		var hi: float = float(p.get("cut_hi", 5000.0))
		var lo: float = float(p.get("cut_lo", 900.0))
		var cd: float = float(p.get("cut_dec", 0.08))
		var cuts := PackedFloat32Array()
		cuts.resize(sz / 32 + 1)
		for b: int in cuts.size():
			cuts[b] = lo + (hi - lo) * exp(-float(b * 32) / SR / cd)
		st.l = Dsp.svf_lp(st.l, cuts, 32, 1.1)
		st.r = Dsp.svf_lp(st.r, cuts, 32, 1.1)
		var dec: float = float(p.get("dec", 0.12))
		for i: int in sz:
			var t := float(i) / SR
			var a := minf(t / 0.002, 1.0) * exp(-t / dec)
			if i >= len:
				a *= 1.0 - float(i - len) / rel
			st.l[i] *= a
			st.r[i] *= a
		return st

	## FM のエレクトリックピアノ・ベル（2つの音の位相変調）。idx0 = 頭の音の荒さ、idx1 = 残る荒さ、ratio = 変調の周波数比
	func _render_ep(midi: int, len: int, p: Dictionary) -> PackedFloat32Array:
		var f := _hz(midi)
		var rel := int(0.3 * SR)
		var sz := len + rel
		var out := PackedFloat32Array()
		out.resize(sz)
		var wc := TAU * f / SR
		var wm := wc * float(p.get("ratio", 1.0))
		var wb := wc * 14.0
		var idx0: float = float(p.get("idx0", 2.0))
		var idx1: float = float(p.get("idx1", 0.4))
		var md: float = float(p.get("mod_decay", 0.35))
		var dec: float = float(p.get("decay", 1.0))
		var tine: float = float(p.get("tine", 0.18)) if f * 14.0 < 9000.0 else 0.0
		var pc := 0.0
		var pm := 0.0
		var pb := 0.0
		for i: int in sz:
			var t := float(i) / SR
			var m := sin(pm) * (idx0 * exp(-t / md) + idx1)
			var a := minf(t / 0.002, 1.0) * exp(-t / dec)
			if i >= len:
				var r := 1.0 - float(i - len) / rel
				a *= r * r
			out[i] = (sin(pc + m) + sin(pb) * tine * exp(-t / 0.025)) * a
			pc += wc
			pm += wm
			pb += wb
		return out

	## つま弾く音（アルペジオ・ベル風）：ノコギリ波（またはパルス）を、頭で開くローパスに通して素早く減衰
	func _render_pluck(midi: int, len: int, p: Dictionary) -> PackedFloat32Array:
		var f := _hz(midi)
		var rel := int(0.03 * SR)
		var sz := len + rel
		var out := PackedFloat32Array()
		out.resize(sz)
		var dt := f / SR
		var ph := 0.0
		var low := 0.0
		var band := 0.0
		var ff := 0.1
		var lo: float = float(p.get("lo", 800.0))
		var hi: float = float(p.get("hi", 5000.0))
		var cd: float = float(p.get("cut_dec", 0.07))
		var dec: float = float(p.get("dec", 0.16))
		var pw: float = float(p.get("pulse", 0.0))
		var k := 1.0 / float(p.get("q", 1.2))
		for i: int in sz:
			var t := float(i) / SR
			var s := Dsp.saw(ph, dt)
			if pw > 0.0:
				s = s * (1.0 - pw) + Dsp.pulse(ph, dt, 0.5) * pw
			ph += dt
			if ph >= 1.0:
				ph -= 1.0
			if i & 15 == 0:
				ff = 2.0 * sin(PI * minf(lo + (hi - lo) * exp(-t / cd), 5500.0) / SR)
			low += ff * band
			var high := s - low - k * band
			band += ff * high
			var a := minf(t / 0.001, 1.0) * exp(-t / dec)
			if i >= len:
				a *= 1.0 - float(i - len) / rel
			out[i] = low * a
		return out

	## リード：少しずらした2本のノコギリ波（左右に振る）+ 1オクターブ下のパルス。ビブラートは遅れてかかる。頭で少し下から入る
	func _render_lead(midi: int, len: int, p: Dictionary) -> Stereo:
		var f := _hz(midi)
		var rel := int(float(p.get("rel", 0.12)) * SR)
		var sz := len + rel
		var st := Stereo.new(sz)
		var det: float = float(p.get("detune", 0.0035))
		var vib: float = float(p.get("vib", 0.0045))
		var sub: float = float(p.get("sub", 0.2))
		var att: float = float(p.get("att", 0.012))
		var dec: float = float(p.get("dec", 3.0))
		var lo: float = float(p.get("lo", 1500.0))
		var hi: float = float(p.get("hi", 4200.0))
		var cd: float = float(p.get("cut_dec", 0.15))
		var pa := rng.randf()
		var pb := rng.randf()
		var ps := 0.0
		var low_l := 0.0
		var band_l := 0.0
		var low_r := 0.0
		var band_r := 0.0
		var ff := 0.1
		for i: int in sz:
			var t := float(i) / SR
			var m := (1.0 + vib * sin(TAU * 5.4 * t) * smoothstep(0.08, 0.3, t)) * (1.0 - 0.015 * exp(-t / 0.025))
			var da := f * (1.0 + det) * m / SR
			var db := f * (1.0 - det) * m / SR
			var ds := f * 0.5 * m / SR
			var a_ := Dsp.saw(pa, da)
			var b_ := Dsp.saw(pb, db)
			var q_ := Dsp.pulse(ps, ds, 0.5) * sub
			pa += da
			if pa >= 1.0:
				pa -= 1.0
			pb += db
			if pb >= 1.0:
				pb -= 1.0
			ps += ds
			if ps >= 1.0:
				ps -= 1.0
			if i & 15 == 0:
				ff = 2.0 * sin(PI * minf(lo + (hi - lo) * exp(-t / cd), 5500.0) / SR)
			var xl := a_ * 0.75 + b_ * 0.35 + q_
			var xr := b_ * 0.75 + a_ * 0.35 + q_
			low_l += ff * band_l
			var high_l := xl - low_l - 0.9 * band_l
			band_l += ff * high_l
			low_r += ff * band_r
			var high_r := xr - low_r - 0.9 * band_r
			band_r += ff * high_r
			var e := minf(t / att, 1.0) * exp(-t / dec)
			if i >= len:
				e *= 1.0 - float(i - len) / rel
			st.l[i] = low_l * e
			st.r[i] = low_r * e
		return st

	# --- 置く ----------------------------------------------------------------------------

	func _hit(inst: String, vel: float, bar: int, step: int) -> void:
		if not kit.has(inst):
			push_error("%s: ドラムセットに '%s' が無い" % [id, inst])
			return
		var k: Dictionary = kit[inst]
		var variants: Array = k["v"]
		var v := clampf(vel, 0.0, 1.0)
		var smp: PackedFloat32Array = variants[clampi(int(v * variants.size() * 0.999), 0, variants.size() - 1)]
		var at := _at(bar, step)
		if inst != "k" and inst != "s" and inst != "c":
			at += rng.randi_range(-50, 50)   # 人の手のわずかなずれ（±1 ms）
		var gain: float = float(k["gain"]) * lerpf(0.4, 1.0, v) * rng.randf_range(0.93, 1.0)
		var pan: float = float(k["pan"])
		if bool(k["alt"]):
			var c: int = hit_count.get(inst, 0)
			hit_count[inst] = c + 1
			if c % 2 == 1:
				pan = -pan
		Dsp.add_pan(drum, smp, maxi(at, 0), gain, pan)
		if inst == "k":
			kick_at.append(maxi(at, 0))
			kick_vel.append(clampf(vel, 0.3, 1.0))

	func _expand(prog_name: String, bars: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		var prog: Array = def["progs"][prog_name]
		var b := 0
		while b < bars:
			for e: Array in prog:
				if b >= bars:
					break
				out.append({"name": str(e[0]), "bar": b, "bars": int(e[1])})
				b += int(e[1])
		return out

	func _compose() -> void:
		for sec: Dictionary in secs:
			var chords := _expand(str(sec["prog"]), int(sec["bars"]))
			_drums(sec)
			_fx(sec)
			_bass_line(sec, "bass", chords)
			_bass_line(sec, "bass2", chords)
			_pads(sec, chords)
			_comps(sec, chords)
			_leads(sec, chords)
			_arps(sec, chords)

	## パターンは 1小節 = 16文字（'.' = 休み、'1'〜'9' = 強さ）。複数小節ぶん続けて書くとその周期で回る。
	## fill_every 小節ごとの最後の小節は fill のパターンに置き換わる
	func _drums(sec: Dictionary) -> void:
		var nm: String = sec.get("drums", "")
		if nm == "":
			return
		var ds: Dictionary = def["drums"][nm]
		var fill_every := int(ds.get("fill_every", 0))
		var fill: Dictionary = ds.get("fill", {})
		var ramp: Array = sec.get("ramp", [1.0, 1.0])
		var bars := int(sec["bars"])
		var bar0 := int(sec["bar0"])
		for b: int in bars:
			var is_fill := fill_every > 0 and b % fill_every == fill_every - 1
			var vg := lerpf(float(ramp[0]), float(ramp[1]), float(b) / maxf(bars - 1, 1))
			var keys: Array = ds.keys()
			if is_fill:
				for fk: String in fill.keys():
					if not keys.has(fk):
						keys.append(fk)
			for inst: String in keys:
				if inst == "fill" or inst == "fill_every":
					continue
				var pat: String = str(fill[inst]) if is_fill and fill.has(inst) else str(ds.get(inst, ""))
				if pat.length() % 16 != 0 or pat.is_empty():
					push_error("%s/%s: パターン '%s' の長さが16の倍数でない（%d）" % [id, nm, inst, pat.length()])
					continue
				var base := (b % (pat.length() / 16)) * 16
				for s: int in 16:
					var c := pat.unicode_at(base + s)
					if c != 46:
						_hit(inst, float(c - 48) / 9.0 * vg, bar0 + b, s)

	func _fx(sec: Dictionary) -> void:
		var fx: Dictionary = sec.get("fx", {})
		if fx.is_empty():
			return
		var bar0 := int(sec["bar0"])
		var bars := int(sec["bars"])
		if fx.has("crash"):
			var x: Dictionary = kit["x"]
			var xv: Array = x["v"]
			Dsp.add_pan(drum, xv[0], _at(bar0, 0), float(x["gain"]) * float(fx["crash"]), 0.0)
		if fx.has("impact"):
			var key := "impact"
			if not cache.has(key):
				cache[key] = _impact(1.6)
			Dsp.add_pan(drum, cache[key], _at(bar0, 0), 0.9 * float(fx["impact"]), 0.0)
		if fx.has("riser"):
			var rb := int(fx["riser"])
			var rsec := rb * bar_len / SR
			var at := _at(bar0 + bars - rb, 0)
			Dsp.add_pan(drum, _riser(rsec, 300.0, 9000.0), at, 0.55 * float(fx.get("riser_gain", 1.0)), -0.55)
			Dsp.add_pan(drum, _riser(rsec, 300.0, 9000.0), at, 0.55 * float(fx.get("riser_gain", 1.0)), 0.55)

	func _bass_line(sec: Dictionary, field: String, chords: Array[Dictionary]) -> void:
		var nm: String = sec.get(field, "")
		if nm == "":
			return
		var bd: Dictionary = def["bass"][nm]
		var pats: Array = bd["pat"]
		var lo := int(bd.get("lo", 28))
		var bar0 := int(sec["bar0"])
		for b: int in int(sec["bars"]):
			var root := lo + posmod(int(_chord_at(chords, b)["root"]) - lo, 12)
			for tok: String in str(pats[b % pats.size()]).split(" ", false):
				var f := tok.split(":")
				var len := int(float(f[1]) * step_len)
				var vel := float(int(f[3])) / 9.0 if f.size() > 3 else 1.0
				var midi := root + int(f[2])
				var key := "b:%s:%d:%d" % [nm, midi, len]
				var buf: PackedFloat32Array
				if cache.has(key):
					buf = cache[key]
				else:
					var kind := str(bd["kind"])
					if kind == "sub":
						buf = _bass_sub(midi, len, bd)
					elif kind == "reese":
						buf = _bass_reese(midi, len, bd)
					else:
						buf = _bass_saw(midi, len, bd)
					cache[key] = buf
				Dsp.add_pan(bass, buf, _at(bar0 + b, int(f[0])), float(bd["level"]) * vel, 0.0)

	func _pads(sec: Dictionary, chords: Array[Dictionary]) -> void:
		var nm: String = sec.get("pad", "")
		if nm == "":
			return
		var pd: Dictionary = def["pads"][nm]
		var gain_k: float = float(sec.get("pad_gain", 1.0))
		for c: Dictionary in chords:
			var prev: Array[int] = []
			if voicing_prev.has("pad:" + nm):
				prev = voicing_prev["pad:" + nm]
			var notes := _voice(_chord(str(c["name"])), int(pd["count"]), float(pd["center"]), prev, bool(pd.get("ext", false)))
			voicing_prev["pad:" + nm] = notes
			var len := int(float(c["bars"]) * bar_len) + int(float(pd["rel"]) * SR)
			var key := "pad:%s:%s:%d" % [nm, str(notes), len]
			var st: Stereo
			if cache.has(key):
				st = cache[key]
			else:
				st = _render_pad(notes, len, pd)
				cache[key] = st
			Dsp.add_st(pad, st, _at(int(sec["bar0"]) + int(c["bar"]), 0), float(pd["level"]) * gain_k)

	## コードの刻み（stem = "bass" ならベース層、"lead" ならリード層に入る）
	func _comps(sec: Dictionary, chords: Array[Dictionary]) -> void:
		var nm: String = sec.get("comp", "")
		if nm == "":
			return
		var cd: Dictionary = def["comps"][nm]
		var target: Stereo = comp_b if str(cd["stem"]) == "bass" else comp_l
		var pats: Array = cd["pat"]
		var bar0 := int(sec["bar0"])
		var gain_k: float = float(sec.get("comp_gain", 1.0))
		for c: Dictionary in chords:
			var prev: Array[int] = []
			if voicing_prev.has("comp:" + nm):
				prev = voicing_prev["comp:" + nm]
			var notes := _voice(_chord(str(c["name"])), int(cd["count"]), float(cd["center"]), prev, bool(cd.get("ext", false)))
			voicing_prev["comp:" + nm] = notes
			for bb: int in range(int(c["bar"]), int(c["bar"]) + int(c["bars"])):
				for tok: String in str(pats[bb % pats.size()]).split(" ", false):
					var f := tok.split(":")
					var len := int(float(f[1]) * step_len)
					var vel := float(int(f[2])) / 9.0 if f.size() > 2 else 1.0
					var at := _at(bar0 + bb, int(f[0]))
					var level := float(cd["level"]) * vel * gain_k
					if str(cd["kind"]) == "stab":
						var key := "stab:%s:%s:%d" % [nm, str(notes), len]
						var st: Stereo
						if cache.has(key):
							st = cache[key]
						else:
							st = _render_stab(notes, len, cd)
							cache[key] = st
						Dsp.add_st(target, st, at, level)
					else:
						for ni: int in notes.size():
							var pan := (float(ni) / maxf(notes.size() - 1, 1) - 0.5) * 0.8
							_put_note(target, "ep:" + nm, cd, notes[ni], len, at + ni * int(0.004 * SR), level / sqrt(float(notes.size())), pan)

	func _put_note(layer: Stereo, nm: String, d: Dictionary, midi: int, len: int, at: int, gain: float, pan: float) -> void:
		var kind := str(d["kind"])
		var key := "%s:%d:%d" % [nm, midi, len]
		if kind == "saw":
			var st: Stereo
			if cache.has(key):
				st = cache[key]
			else:
				st = _render_lead(midi, len, d)
				cache[key] = st
			Dsp.add_st(layer, st, at, gain)
			return
		var buf: PackedFloat32Array
		if cache.has(key):
			buf = cache[key]
		else:
			buf = _render_ep(midi, len, d) if kind == "ep" or kind == "bell" else _render_pluck(midi, len, d)
			cache[key] = buf
		Dsp.add_pan(layer, buf, at, gain, pan)

	## メロディ：音は「コードの構成音の何番目か」（0 = center に一番近い構成音、1 = その上、-1 = 下）で書く。
	## コードが変わると同じ書き方で和音に合った音になる。"p2" は直前の音から調の音階で2段上（passing tone）
	func _leads(sec: Dictionary, chords: Array[Dictionary]) -> void:
		var nm: String = sec.get("lead", "")
		if nm == "":
			return
		var ld: Dictionary = def["leads"][nm]
		var pb := int(ld["phrase_bars"])
		var seq: Array = ld["seq"]
		var phrases: Array = ld["phrases"]
		var bars := int(sec["bars"])
		var bar0 := int(sec["bar0"])
		var center: float = float(ld["center"])
		var ext: bool = bool(ld.get("ext", false))
		var slot := 0
		for k: int in range(0, bars, pb):
			var pi := int(seq[slot % seq.size()])
			slot += 1
			if pi < 0:
				continue
			var prev := -1
			for tok: String in str(phrases[pi]).split(" ", false):
				var f := tok.split(":")
				var rb := k + int(f[0]) / 16
				if rb >= bars:
					continue
				var len := int(float(f[1]) * step_len)
				var ps := str(f[2])
				var midi: int
				if ps.begins_with("p") and prev >= 0:
					midi = _scale_step(prev, int(ps.substr(1)))
				else:
					midi = _ct(_chord_at(chords, rb), center, int(ps), ext)
				prev = midi
				var vel := float(int(f[3])) / 9.0 if f.size() > 3 else 1.0
				_put_note(lead, "lead:" + nm, ld, midi, len, _at(bar0 + rb, int(f[0]) % 16), float(ld["level"]) * vel, float(ld.get("pan", 0.0)))

	## アルペジオ：1小節16個の「構成音の番号」（'.' は休み）を、小節ごとのコードに当てて鳴らす。左右に交互に振る
	func _arps(sec: Dictionary, chords: Array[Dictionary]) -> void:
		var nm: String = sec.get("arp", "")
		if nm == "":
			return
		var ad: Dictionary = def["arps"][nm]
		var idx := str(ad["idx"]).split(" ", false)
		var vels := str(ad["vel"]).split(" ", false)
		var bar0 := int(sec["bar0"])
		var len := int(float(ad["len"]) * step_len)
		var center: float = float(ad["center"])
		var ext: bool = bool(ad.get("ext", false))
		var pw: float = float(ad.get("pan", 0.35))
		var gain_k: float = float(sec.get("arp_gain", 1.0))
		for b: int in int(sec["bars"]):
			var ch := _chord_at(chords, b)
			var base := (b % (idx.size() / 16)) * 16
			for s: int in 16:
				var tok := idx[base + s]
				if tok == ".":
					continue
				var midi := _ct(ch, center, int(tok), ext)
				var vel := float(int(vels[s % vels.size()])) / 9.0
				_put_note(arp, "arp:" + nm, ad, midi, len, _at(bar0 + b, s), float(ad["level"]) * vel * gain_k, pw if s % 2 == 0 else -pw)

	# --- 仕上げ ----------------------------------------------------------------------------

	## キックの鳴った後、0 → 1 → 0 で戻る形（サイドチェイン用。各層は 1 - depth × この形 のゲインを掛ける）
	func _kick_shape(rel_s: float) -> PackedFloat32Array:
		var sh := PackedFloat32Array()
		sh.resize(buf_n)
		var k := exp(-1.0 / (rel_s * SR))
		var win := int(rel_s * SR * 3.5)
		for e: int in kick_at.size():
			var at := kick_at[e]
			var d := kick_vel[e]
			var env := 1.0
			for i: int in mini(win, buf_n - at):
				var v := d * env * minf(float(i + 1) / 44.0, 1.0)
				if v > sh[at + i]:
					sh[at + i] = v
				env *= k
		return sh

	## パッドのローパスを区間ごとの [始め, 終わり] Hz（cut）で動かし、LFO でゆっくり揺らす（左右で位相をずらす）
	func _pad_filter() -> void:
		var lfo: Array = def["pad_lfo"]   # [Hz, 振れ幅（オクターブ）, 既定のカットオフ Hz, Q]
		var block := 64
		var nb := buf_n / block + 1
		var cl := PackedFloat32Array()
		cl.resize(nb)
		var cr := PackedFloat32Array()
		cr.resize(nb)
		var si := 0
		for b: int in nb:
			var smp := b * block
			while si + 1 < secs.size() and smp >= int(round(float(secs[si + 1]["bar0"]) * bar_len)):
				si += 1
			var sec := secs[si]
			var cut: Array = sec.get("cut", [lfo[2], lfo[2]])
			var s0 := float(sec["bar0"]) * bar_len
			var s1 := float(int(sec["bar0"]) + int(sec["bars"])) * bar_len
			var u := clampf((smp - s0) / (s1 - s0), 0.0, 1.0)
			var base := float(cut[0]) * pow(float(cut[1]) / float(cut[0]), u)
			var t := float(smp) / SR
			cl[b] = base * pow(2.0, float(lfo[1]) * sin(TAU * float(lfo[0]) * t))
			cr[b] = base * pow(2.0, float(lfo[1]) * sin(TAU * float(lfo[0]) * t + 1.6))
		pad.l = Dsp.svf_lp(pad.l, cl, block, float(lfo[3]))
		pad.r = Dsp.svf_lp(pad.r, cr, block, float(lfo[3]))

	## 残響のしっぽ（曲の終わりからはみ出した分）をループの頭へ回して、長さを n に切る
	func _fold(st: Stereo) -> void:
		for i: int in tail:
			st.l[loop_start + i] += st.l[n + i]
			st.r[loop_start + i] += st.r[n + i]
		st.l.resize(n)
		st.r.resize(n)

	func _master() -> Dictionary:
		_pad_filter()
		_log("pad filter")
		for layer: Stereo in [pad, comp_b, comp_l]:
			layer.l = Dsp.hp1(layer.l, 140.0)
			layer.r = Dsp.hp1(layer.r, 140.0)
		if def.has("lead_chorus"):
			var c: Array = def["lead_chorus"]
			Dsp.chorus(lead, float(c[0]), float(c[1]), float(c[2]), float(c[3]))
		if def.has("lead_delay"):
			var d: Array = def["lead_delay"]
			Dsp.pingpong(lead, int(float(d[0]) * step_len), float(d[1]), float(d[2]), 0.45)
		if def.has("arp_delay"):
			var d: Array = def["arp_delay"]
			Dsp.pingpong(arp, int(float(d[0]) * step_len), float(d[1]), float(d[2]), 0.5)
		_log("hp / chorus / delays")
		# サイドチェイン：キックのたびにパッド・ベース・リードの音量が下がる
		var dk: Array = def["duck"]   # [パッド, ベース, リードの深さ, 戻る秒]
		var shape := _kick_shape(float(dk[3]))
		_log("kick shape")
		var dp := float(dk[0])
		var db := float(dk[1])
		var dl := float(dk[2])
		var bs := Stereo.new(buf_n)
		var ls := Stereo.new(buf_n)
		for i: int in buf_n:
			var sh := shape[i]
			var gp := 1.0 - dp * sh
			var gb := 1.0 - db * sh
			var gl := 1.0 - dl * sh
			bs.l[i] = bass.l[i] * gb + (pad.l[i] + comp_b.l[i]) * gp
			bs.r[i] = bass.r[i] * gb + (pad.r[i] + comp_b.r[i]) * gp
			ls.l[i] = (lead.l[i] + arp.l[i] + comp_l.l[i]) * gl
			ls.r[i] = (lead.r[i] + arp.r[i] + comp_l.r[i]) * gl
		bass = null
		pad = null
		comp_b = null
		comp_l = null
		lead = null
		arp = null
		var stems: Array[Stereo] = [drum, bs, ls]
		# 層ごとの仕上げ：音量をそろえる → 軽い飽和 → 幅 → 残響 → 低域の整理 → しっぽを頭へ
		var targets: Array = def["stem_db"]
		var sat: Array = def["sat"]
		var wid: Array = def["width"]
		var rev: Array = def["rev"]   # 層ごとに [残響時間, 部屋の大きさ, 高域の吸収, 混ぜる量, 送りの低域カット Hz, プリディレイ ms]
		for k: int in 3:
			var st: Stereo = stems[k]
			var g := pow(10.0, float(targets[k]) / 20.0) / maxf(Dsp.active_rms(st.l, st.r), 1e-9)
			st.l = Dsp.scaled(st.l, g)
			st.r = Dsp.scaled(st.r, g)
			Dsp.softclip(st.l, float(sat[k]))
			Dsp.softclip(st.r, float(sat[k]))
			Dsp.width(st, float(wid[k]))
			var rv: Array = rev[k]
			if float(rv[3]) > 0.0:
				var wet := Dsp.reverb(Dsp.hp1(st.l, float(rv[4])), Dsp.hp1(st.r, float(rv[4])), float(rv[0]), float(rv[1]), float(rv[2]), float(rv[5]))
				Dsp.add(st.l, wet.l, 0, float(rv[3]))
				Dsp.add(st.r, wet.r, 0, float(rv[3]))
			st.l = Dsp.hp1(st.l, 28.0)
			st.r = Dsp.hp1(st.r, 28.0)
			_fold(st)
			_log("stem %d finish (rms, sat, width, reverb)" % k)
		# 3層を全部重ねた音からリミッタのゲインを作り、全層に同じゲインを掛ける
		var sum_l := PackedFloat32Array()
		var sum_r := PackedFloat32Array()
		sum_l.resize(n)
		sum_r.resize(n)
		for st: Stereo in stems:
			for i: int in n:
				sum_l[i] += st.l[i]
				sum_r[i] += st.r[i]
		var crest := float(def.get("crest", 13.0))
		var thresh := Dsp.active_rms(sum_l, sum_r) * pow(10.0, crest / 20.0)
		var gains := Dsp.limiter_gains(sum_l, sum_r, thresh, 0.08)
		var min_g := 1.0
		for v: float in gains:
			min_g = minf(min_g, v)
		for st: Stereo in stems:
			Dsp.apply_gains(st.l, gains)
			Dsp.apply_gains(st.r, gains)
		# 実際に鳴る組み合わせ（ドラムだけ・ドラム+ベース・全部・ベース+リード）の最大ピークが -1 dBFS になるように揃える
		var d := stems[0]
		var b := stems[1]
		var l := stems[2]
		var pk_d := 0.0
		var pk_db := 0.0
		var pk_all := 0.0
		var pk_bl := 0.0
		for i: int in n:
			var dl_ := d.l[i]
			var dr_ := d.r[i]
			pk_d = maxf(pk_d, maxf(absf(dl_), absf(dr_)))
			pk_db = maxf(pk_db, maxf(absf(dl_ + b.l[i]), absf(dr_ + b.r[i])))
			pk_all = maxf(pk_all, maxf(absf(dl_ + b.l[i] + l.l[i]), absf(dr_ + b.r[i] + l.r[i])))
			pk_bl = maxf(pk_bl, maxf(absf(b.l[i] + l.l[i]), absf(b.r[i] + l.r[i])))
		var k_final := pow(10.0, PEAK_DB / 20.0) / maxf(maxf(pk_d, pk_db), maxf(pk_all, pk_bl))
		for st: Stereo in stems:
			st.l = Dsp.scaled(st.l, k_final)
			st.r = Dsp.scaled(st.r, k_final)
		_log("limiter + normalise")
		# --- 測定 ---
		for i: int in n:
			sum_l[i] = d.l[i] + b.l[i] + l.l[i]
			sum_r[i] = d.r[i] + b.r[i] + l.r[i]
		var rep := {
			"id": id, "bpm": bpm, "dur": float(n) / SR, "loop_start": loop_start, "audio": stems,
			"peak_all": Dsp.to_db(pk_all * k_final), "peak_db": Dsp.to_db(pk_db * k_final),
			"peak_d": Dsp.to_db(pk_d * k_final), "peak_bl": Dsp.to_db(pk_bl * k_final),
			"gr": -Dsp.to_db(min_g), "corr": Dsp.correlation(sum_l, sum_r), "hf": Dsp.high_ratio(sum_l, sum_r, 16000.0),
			"rms_all": Dsp.to_db(Dsp.active_rms(sum_l, sum_r)),
		}
		var sl: Array = []
		for k: int in 3:
			var st: Stereo = stems[k]
			sl.append([STEMS[k], Dsp.to_db(Dsp.active_rms(st.l, st.r)), Dsp.centroid(st.l, st.r), Dsp.to_db(maxf(Dsp.peak(st.l), Dsp.peak(st.r)))])
		rep["stems"] = sl
		var sec_l: Array = []
		for sec: Dictionary in secs:
			var s0 := int(round(float(sec["bar0"]) * bar_len))
			var s1 := mini(int(round(float(int(sec["bar0"]) + int(sec["bars"])) * bar_len)), n)
			sec_l.append([str(sec["name"]), Dsp.to_db(Dsp.rms(sum_l, sum_r, s0, s1))])
		rep["sections"] = sec_l
		return rep

# --- 曲の定義 --------------------------------------------------------------------------
## 書き方（Song が読む）:
##   bpm / swing（裏の16分を8分音符の何割後ろへ。0.17 で3連ノリ）/ key（主音 0 = C … 9 = A）/ minor / kit / loop_from（ループ点にする区間の番号。0 = 曲の頭）/ crest（リミッタが残すピークの高さ dB）
##   stem_db（層ごとの目標の実効値 dBFS）/ duck（サイドチェイン [パッド, ベース, リードの深さ, 戻る秒]）/ pad_lfo [Hz, 振れ幅 oct, 既定の口 Hz, Q]
##   sat（層ごとの飽和）/ width / rev（層ごとの残響）/ arp_delay・lead_delay [16分音符の数, 反復, 混ぜる量] / lead_chorus
##   progs: 名前 → [[コード名, 小節数], …]（区間の長さの数だけ繰り返す）
##   drums: 名前 → {楽器: パターン}。パターンは 16文字 = 1小節（'.' 休み、'1'〜'9' 強さ）、複数小節ぶん続けて書くと周期になる
##   bass / pads / comps / leads / arps: 音色と置き方（Song の各関数を参照）
##   sections: 名前・progs の名前・使う drums / bass / bass2 / pad / comp / lead / arp、fx（crash / impact / riser）、cut（パッドの口 [始め, 終わり] Hz）、
##   ramp（ドラムの強さを区間の中で [始め, 終わり] 倍）、pad_gain・comp_gain・arp_gain
const DEFS: Dictionary = {
	# ================= 朝の屋上：126 BPM・イ長調・明るいハウス（ガラージ寄りの跳ね）=================
	"morning": {
		"bpm": 126.0, "swing": 0.12, "key": 9, "minor": false, "kit": "house", "loop_from": 0, "crest": 13.0,
		"stem_db": [-17.0, -19.0, -20.0],
		"duck": [0.55, 0.32, 0.22, 0.17],
		"pad_lfo": [0.07, 0.5, 2600.0, 0.9],
		"sat": [1.5, 1.4, 1.3],
		"width": [1.0, 1.25, 1.3],
		"rev": [[1.0, 0.8, 0.5, 0.10, 400.0, 10.0], [2.0, 1.2, 0.5, 0.10, 400.0, 18.0], [2.4, 1.3, 0.4, 0.24, 300.0, 22.0]],
		"arp_delay": [3.0, 0.45, 0.55],
		"lead_delay": [3.0, 0.35, 0.3],
		"lead_chorus": [0.5, 14.0, 3.0, 0.45],
		"progs": {
			"i1": [["A", 2], ["E", 2]],
			"i2": [["F#m", 2], ["D", 2]],
			"A": [["A", 2], ["E", 2], ["F#m", 2], ["D", 2]],
			"B": [["D", 2], ["E", 2], ["C#m", 2], ["F#m", 2]],
			"K": [["F#m", 2], ["D", 2], ["A", 2], ["E", 2]],
			"U1": [["D", 2], ["E", 2]],
			"U2": [["D", 1], ["E", 1], ["D", 1], ["E", 1]],
		},
		"drums": {
			"i1": {"h": "5.3.5.3.5.3.5.3.", "r": "2323232323232323"},
			"i2": {"k": "9...9...9...9...", "h": "5.3.5.3.5.3.5.3.", "o": "..4...4...4...4.", "r": "2323232323232323",
					"fill_every": 4, "fill": {"c": "........5.5.7.9."}},
			"A": {"k": "9...9...9...9...", "c": "....9.......9...", "h": "5.3.5.3.5.3.5.3.", "o": "..7...7...7...7.", "r": "3232323232323232",
					"fill_every": 8, "fill": {"c": "....9.....5.7.9.", "h": "................"}},
			"A2": {"k": "9...9...9...9...", "c": "....9.......9...", "h": "6.4.6.4.6.4.6.4.", "o": "..7...7...7...7.", "r": "3232323232323232",
					"n": "..3....3..3.....", "fill_every": 8, "fill": {"c": "....9.....5.7.9.", "h": "................"}},
			"B": {"k": "9...9...9...9...", "c": "....9.......9...", "h": "6.4.6.4.6.4.6.4.", "o": "..8...8...8...8.", "r": "4343434343434343",
					"n": "..3....3..3.....", "fill_every": 8, "fill": {"c": "....9...5.5.7.9.", "h": "................"}},
			"K": {"h": "4.2.4.2.4.2.4.2.", "r": "2323232323232323", "n": "............................3..."},
			"U1": {"k": "9...............", "h": "4.2.4.2.4.2.4.2.", "r": "3232323232323232", "fill_every": 2, "fill": {"c": "........5.5.7.7."}},
			"U2": {"k": "9...9...9...9...", "c": "........5.5.7.7.", "h": "5.3.5.3.5.3.5.3.", "r": "4343434343434343",
					"fill_every": 4, "fill": {"c": "3344556677889999"}},
		},
		"bass": {
			"A": {"kind": "saw", "lo": 33, "level": 0.8, "cut_hi": 2200.0, "cut_lo": 380.0, "env": 0.09, "q": 1.6, "sub": 0.55, "drive": 1.4,
					"pat": ["2:2:0 6:2:0 10:2:0 14:2:12", "2:2:0 6:2:0 10:2:7 14:2:12"]},
			"B": {"kind": "saw", "lo": 33, "level": 0.8, "cut_hi": 2600.0, "cut_lo": 420.0, "env": 0.09, "q": 1.7, "sub": 0.55, "drive": 1.5,
					"pat": ["0:1.5:0 2:2:0 6:2:0 8:1.5:0 10:2:7 14:2:12", "0:1.5:0 2:2:0 6:2:12 8:1.5:0 10:2:7 14:2:5"]},
			"U": {"kind": "saw", "lo": 33, "level": 0.75, "cut_hi": 1800.0, "cut_lo": 300.0, "env": 0.1, "q": 1.4, "sub": 0.6, "drive": 1.3,
					"pat": ["0:3:0 4:3:0 8:3:0 12:3:0"]},
		},
		"pads": {
			"soft": {"count": 3, "center": 64, "voices": 5, "spread": 11.0, "level": 0.4, "att": 0.6, "rel": 0.8, "width": 0.9},
			"A": {"count": 4, "center": 63, "voices": 5, "spread": 12.0, "level": 0.5, "att": 0.4, "rel": 0.6, "width": 0.9},
			"B": {"count": 4, "center": 66, "voices": 5, "spread": 13.0, "level": 0.55, "att": 0.3, "rel": 0.6, "width": 1.0},
			"K": {"count": 4, "center": 64, "voices": 5, "spread": 12.0, "level": 0.65, "att": 0.8, "rel": 0.9, "width": 1.0},
		},
		"comps": {
			"A": {"kind": "stab", "count": 3, "center": 64, "level": 0.5, "stem": "lead", "cut_hi": 5200.0, "cut_lo": 1100.0, "cut_dec": 0.07, "dec": 0.11,
					"pat": ["0:1.5 3:1.5 6:1.5 10:1.5"]},
			"B": {"kind": "stab", "count": 3, "center": 66, "level": 0.5, "stem": "lead", "cut_hi": 6000.0, "cut_lo": 1300.0, "cut_dec": 0.07, "dec": 0.11,
					"pat": ["0:1.5 3:1.5 6:1.5 8:1.5 11:1.5 14:1.5"]},
			"U": {"kind": "stab", "count": 3, "center": 66, "level": 0.45, "stem": "lead", "cut_hi": 6000.0, "cut_lo": 1500.0, "cut_dec": 0.06, "dec": 0.09,
					"pat": ["0:1.5 2:1.5 4:1.5 6:1.5 8:1.5 10:1.5 12:1.5 14:1.5"]},
		},
		"arps": {
			"lo": {"kind": "pluck", "idx": "0 2 4 2 3 2 4 2 0 2 4 2 3 2 4 5", "vel": "9 4 6 4 8 4 6 4", "center": 62.0, "level": 0.32, "len": 1.5,
					"lo": 600.0, "hi": 2400.0, "cut_dec": 0.08, "dec": 0.14, "q": 1.3, "pan": 0.35},
			"A": {"kind": "pluck", "idx": "0 2 4 2 3 2 4 2 0 2 4 2 3 2 4 5", "vel": "9 4 6 4 8 4 6 4", "center": 66.0, "level": 0.4, "len": 1.5,
					"lo": 900.0, "hi": 4200.0, "cut_dec": 0.07, "dec": 0.14, "q": 1.3, "pan": 0.4},
			"B": {"kind": "pluck", "idx": "0 2 4 2 5 2 4 2 3 2 4 2 5 2 4 6", "vel": "9 4 6 4 8 4 6 4", "center": 68.0, "level": 0.4, "len": 1.5,
					"lo": 1100.0, "hi": 5200.0, "cut_dec": 0.07, "dec": 0.14, "q": 1.3, "pan": 0.45},
			"K": {"kind": "pluck", "idx": "0 . . . 2 . . . 4 . . . 2 . . .", "vel": "9 4 6 4", "center": 66.0, "level": 0.4, "len": 3.0,
					"lo": 700.0, "hi": 3000.0, "cut_dec": 0.12, "dec": 0.3, "q": 1.2, "pan": 0.5},
		},
		"leads": {
			"H": {"kind": "saw", "phrase_bars": 2, "center": 72.0, "level": 0.6, "seq": [0, 1], "lo": 1800.0, "hi": 5200.0, "cut_dec": 0.12,
					"detune": 0.0035, "vib": 0.004, "sub": 0.15, "dec": 2.5,
					"phrases": ["0:3:1 3:1:0 4:2:1 6:2:2 8:6:1 16:3:2 19:1:1 20:2:0 22:2:1 24:8:-1",
							"0:2:2 2:2:1 4:2:2 6:2:3 8:4:2 12:4:1 16:3:3 19:1:2 20:4:1 24:8:0"]},
			"H2": {"kind": "saw", "phrase_bars": 2, "center": 72.0, "level": 0.6, "seq": [1, 0], "lo": 1800.0, "hi": 5200.0, "cut_dec": 0.12,
					"detune": 0.0035, "vib": 0.004, "sub": 0.15, "dec": 2.5,
					"phrases": ["0:3:1 3:1:0 4:2:1 6:2:2 8:6:1 16:3:2 19:1:1 20:2:0 22:2:1 24:8:-1",
							"0:2:2 2:2:1 4:2:2 6:2:3 8:4:2 12:4:1 16:3:3 19:1:2 20:4:1 24:8:0"]},
			"S": {"kind": "saw", "phrase_bars": 2, "center": 70.0, "level": 0.5, "seq": [0], "lo": 1200.0, "hi": 2800.0, "cut_dec": 0.3,
					"detune": 0.004, "vib": 0.006, "sub": 0.1, "dec": 4.0, "att": 0.05, "rel": 0.3,
					"phrases": ["0:12:1 12:4:0 16:16:2"]},
		},
		"sections": [
			{"name": "intro1", "prog": "i1", "drums": "i1", "pad": "soft", "arp": "lo", "cut": [700.0, 1400.0], "ramp": [0.6, 1.0]},
			{"name": "intro2", "prog": "i2", "drums": "i2", "bass": "A", "pad": "soft", "arp": "lo", "cut": [1400.0, 2200.0], "fx": {"riser": 2}},
			{"name": "A1", "prog": "A", "drums": "A", "bass": "A", "pad": "A", "arp": "A", "fx": {"crash": 1.0}},
			{"name": "A2", "prog": "A", "drums": "A2", "bass": "A", "pad": "A", "comp": "A", "arp": "A"},
			{"name": "B1", "prog": "B", "drums": "B", "bass": "B", "pad": "B", "comp": "B", "arp": "B", "lead": "H", "fx": {"crash": 1.1}},
			{"name": "B2", "prog": "B", "drums": "B", "bass": "B", "pad": "B", "comp": "B", "arp": "B", "lead": "H2"},
			{"name": "break", "prog": "K", "drums": "K", "pad": "K", "pad_gain": 0.75, "arp": "K", "lead": "S", "cut": [900.0, 1800.0], "fx": {"impact": 0.7}},
			{"name": "build1", "prog": "U1", "drums": "U1", "pad": "K", "arp": "B", "cut": [1800.0, 4200.0], "arp_gain": 0.8, "fx": {"riser": 4}},
			{"name": "build2", "prog": "U2", "drums": "U2", "bass": "U", "pad": "B", "comp": "U", "arp": "B", "cut": [4200.0, 5000.0], "fx": {"riser": 4}},
			{"name": "drop1", "prog": "A", "drums": "B", "bass": "B", "pad": "B", "comp": "B", "arp": "B", "lead": "H", "fx": {"crash": 1.3, "impact": 0.5}},
			{"name": "drop2", "prog": "B", "drums": "A2", "bass": "A", "pad": "A", "comp": "A", "arp": "A", "lead": "H2", "fx": {"riser": 2}},
		],
	},
	# ================= 昼の工事中の高層：140 BPM・ホ短調・ブレイクビーツ + 金属の打楽器 =================
	"noon": {
		"bpm": 140.0, "swing": 0.0, "key": 4, "minor": true, "kit": "break", "loop_from": 0, "crest": 12.5,
		"stem_db": [-16.5, -19.0, -20.0],
		"duck": [0.45, 0.28, 0.2, 0.14],
		"pad_lfo": [0.05, 0.45, 1500.0, 1.1],
		"sat": [1.8, 1.9, 1.5],
		"width": [1.0, 1.15, 1.3],
		"rev": [[0.9, 0.7, 0.55, 0.09, 400.0, 6.0], [1.8, 1.1, 0.6, 0.08, 400.0, 15.0], [1.8, 1.2, 0.5, 0.18, 350.0, 12.0]],
		"arp_delay": [3.0, 0.4, 0.4],
		"progs": {
			"i1": [["Em", 4]],
			"i2": [["C", 2], ["D", 2]],
			"A": [["Em", 2], ["C", 2], ["Em", 2], ["D", 2]],
			"B": [["C", 2], ["D", 2], ["Em", 2], ["B", 2]],
			"K": [["Em", 4], ["C", 2], ["D", 2]],
			"U": [["C", 1], ["D", 1], ["Em", 1], ["B", 1]],
		},
		"drums": {
			"i1": {"h": "5.3.5.3.5.3.5.3.", "m": "5...............................", "n": "6..4..6.4..4..6."},
			"i2": {"k": "9.....7..9......9.....7.....9.5.", "s": "....9.......9...", "h": "5.3.5.3.5.3.5.3.", "m": "5...............",
					"fill_every": 4, "fill": {"s": "....5.5.7.7.9999"}},
			"A": {"k": "9.....7..9......9.....7.....9.5.", "s": "....9...........", "g": ".......4.3....4.", "h": "7.5.7.5.7.5.7.5.7.5.7.5.7.5.7.55",
					"o": "..............6.................", "m": "5.......3.......",
					"fill_every": 8, "fill": {"s": "....5.5.7.7.9999", "g": "................", "k": "9..............."}},
			"A2": {"k": "9.....7..9......9.....7.....9.5.", "s": "....9...........", "g": ".......4.3....4.", "h": "7.5.7.5.7.5.7.5.7.5.7.5.7.5.7.55",
					"o": "..............6.................", "m": "5.......3.......", "n": "6..4..6.4..4..6.",
					"fill_every": 8, "fill": {"s": "....5.5.7.7.9999", "g": "................", "k": "9..............."}},
			"B": {"k": "9.....7..9......9.....7.....9.5.", "s": "....9...........", "g": ".......4.3....4.", "h": "8545854585458545",
					"o": "..............6.................", "m": "7.......4.......", "n": "6..4..6.4..4..6.",
					"fill_every": 4, "fill": {"s": "....5.5.7.7.9999", "g": "................", "t": "................", "k": "9..............."}},
			"K": {"h": "4.4.4.4.4.4.4.4.", "m": "6...............3.......3.......", "v": "9...............", "n": "..............3."},
			"U": {"k": "9...9...9...9...", "s": "........9.......", "h": "6.4.6.4.6.4.6.4.", "n": "6..4..6.4..4..6.",
					"fill_every": 4, "fill": {"s": "5.5.5.5.7.7.9999", "k": "9..............."}},
		},
		"bass": {
			"I": {"kind": "saw", "lo": 28, "level": 0.8, "cut_hi": 1500.0, "cut_lo": 260.0, "env": 0.07, "q": 1.8, "sub": 0.6, "drive": 2.4, "pulse": 0.3,
					"pat": ["0:2:0 4:2:0 8:2:0 12:2:0"]},
			"A": {"kind": "saw", "lo": 28, "level": 0.8, "cut_hi": 1700.0, "cut_lo": 280.0, "env": 0.07, "q": 1.9, "sub": 0.6, "drive": 2.6, "pulse": 0.3,
					"pat": ["0:2:0 2:2:0 4:2:12 6:2:0 8:2:0 10:2:0 12:2:12 14:1:10 15:1:7"]},
			"B": {"kind": "saw", "lo": 28, "level": 0.8, "cut_hi": 2000.0, "cut_lo": 300.0, "env": 0.06, "q": 2.0, "sub": 0.6, "drive": 2.8, "pulse": 0.35,
					"pat": ["0:1:0 1:1:0 2:1:12 3:1:0 4:2:0 6:2:7 8:1:0 9:1:0 10:1:12 11:1:0 12:2:0 14:2:5"]},
			"U": {"kind": "saw", "lo": 28, "level": 0.75, "cut_hi": 1600.0, "cut_lo": 280.0, "env": 0.07, "q": 1.8, "sub": 0.6, "drive": 2.4, "pulse": 0.3,
					"pat": ["0:1:0 2:1:0 4:1:0 6:1:0 8:1:0 10:1:0 12:1:0 14:1:0"]},
		},
		"pads": {
			"dark": {"count": 3, "center": 58, "voices": 5, "spread": 14.0, "level": 0.5, "att": 0.5, "rel": 0.7, "width": 0.9},
			"wide": {"count": 4, "center": 62, "voices": 5, "spread": 15.0, "level": 0.6, "att": 0.5, "rel": 0.8, "width": 1.0},
		},
		"comps": {
			"A": {"kind": "stab", "count": 3, "center": 60, "level": 0.5, "stem": "lead", "cut_hi": 3200.0, "cut_lo": 500.0, "cut_dec": 0.07, "dec": 0.09,
					"pat": ["0:2 6:1.5 10:1.5 14:1"]},
			"B": {"kind": "stab", "count": 3, "center": 62, "level": 0.5, "stem": "lead", "cut_hi": 4000.0, "cut_lo": 600.0, "cut_dec": 0.07, "dec": 0.09,
					"pat": ["0:2 3:1 6:1.5 8:2 11:1 14:1"]},
		},
		"arps": {
			"lo": {"kind": "pluck", "idx": "0 0 2 0 3 0 2 0 0 0 2 0 3 0 4 3", "vel": "9 5 7 5", "center": 59.0, "level": 0.3, "len": 1.2, "pulse": 0.8,
					"lo": 500.0, "hi": 1800.0, "cut_dec": 0.06, "dec": 0.1, "q": 1.4, "pan": 0.3},
			"A": {"kind": "pluck", "idx": "0 0 2 0 3 0 2 0 0 0 2 0 3 0 4 3", "vel": "9 5 7 5", "center": 64.0, "level": 0.36, "len": 1.2, "pulse": 0.8,
					"lo": 700.0, "hi": 3000.0, "cut_dec": 0.06, "dec": 0.1, "q": 1.4, "pan": 0.4},
			"B": {"kind": "pluck", "idx": "0 2 3 2 4 2 3 2 0 2 3 2 5 4 3 2", "vel": "9 5 7 5", "center": 66.0, "level": 0.38, "len": 1.2, "pulse": 0.8,
					"lo": 800.0, "hi": 3800.0, "cut_dec": 0.06, "dec": 0.1, "q": 1.4, "pan": 0.45},
			"K": {"kind": "pluck", "idx": "0 . . . . . 2 . . . 3 . . . . .", "vel": "9 5", "center": 64.0, "level": 0.4, "len": 2.5, "pulse": 0.5,
					"lo": 600.0, "hi": 2400.0, "cut_dec": 0.1, "dec": 0.25, "q": 1.3, "pan": 0.5},
		},
		"leads": {
			"H": {"kind": "bell", "phrase_bars": 2, "center": 76.0, "level": 0.55, "seq": [0, 1], "ratio": 3.5, "idx0": 2.6, "idx1": 0.25,
					"mod_decay": 0.45, "decay": 1.0, "tine": 0.0, "pan": 0.0,
					"phrases": ["0:3:2 3:1:1 4:2:2 8:2:3 10:2:2 12:4:1 16:3:3 19:1:2 20:4:1 24:8:0",
							"0:2:3 2:2:2 4:2:3 6:2:4 8:4:3 12:4:2 16:3:4 19:1:3 20:4:2 24:8:1"]},
			"H2": {"kind": "bell", "phrase_bars": 2, "center": 76.0, "level": 0.55, "seq": [1, 0], "ratio": 3.5, "idx0": 2.6, "idx1": 0.25,
					"mod_decay": 0.45, "decay": 1.0, "tine": 0.0, "pan": 0.0,
					"phrases": ["0:3:2 3:1:1 4:2:2 8:2:3 10:2:2 12:4:1 16:3:3 19:1:2 20:4:1 24:8:0",
							"0:2:3 2:2:2 4:2:3 6:2:4 8:4:3 12:4:2 16:3:4 19:1:3 20:4:2 24:8:1"]},
			"S": {"kind": "bell", "phrase_bars": 4, "center": 76.0, "level": 0.5, "seq": [0], "ratio": 3.5, "idx0": 2.2, "idx1": 0.2,
					"mod_decay": 0.6, "decay": 1.6, "tine": 0.0, "pan": 0.0,
					"phrases": ["0:12:2 16:8:1 24:8:0 32:12:3 48:16:2"]},
		},
		"sections": [
			{"name": "intro1", "prog": "i1", "drums": "i1", "pad": "dark", "arp": "lo", "cut": [500.0, 1000.0], "ramp": [0.7, 1.0]},
			{"name": "intro2", "prog": "i2", "drums": "i2", "bass": "I", "pad": "dark", "arp": "lo", "cut": [1000.0, 1800.0], "fx": {"riser": 2}},
			{"name": "A1", "prog": "A", "drums": "A", "bass": "A", "pad": "dark", "arp": "A", "fx": {"crash": 1.0}},
			{"name": "A2", "prog": "A", "drums": "A2", "bass": "A", "pad": "dark", "comp": "A", "arp": "A"},
			{"name": "B1", "prog": "B", "drums": "B", "bass": "B", "pad": "wide", "comp": "B", "arp": "B", "lead": "H", "fx": {"crash": 1.1}},
			{"name": "B2", "prog": "B", "drums": "B", "bass": "B", "pad": "wide", "comp": "B", "arp": "B", "lead": "H2"},
			{"name": "break", "prog": "K", "drums": "K", "pad": "wide", "pad_gain": 0.75, "arp": "K", "lead": "S", "cut": [700.0, 2200.0], "fx": {"impact": 0.9}},
			{"name": "build", "prog": "U", "bars": 8, "drums": "U", "bass": "U", "pad": "wide", "arp": "B", "cut": [2200.0, 5000.0], "arp_gain": 0.8, "fx": {"riser": 8}},
			{"name": "drop1", "prog": "A", "drums": "B", "bass": "B", "pad": "wide", "comp": "B", "arp": "B", "lead": "H", "fx": {"crash": 1.3, "impact": 0.7}},
			{"name": "drop2", "prog": "B", "drums": "B", "bass": "B", "pad": "wide", "comp": "A", "arp": "A", "lead": "H2"},
			{"name": "outro", "prog": "A", "drums": "A", "bass": "A", "pad": "dark", "arp": "A", "fx": {"riser": 2}},
		],
	},
	# ================= 夕方の繁華街：108 BPM・ハ長調・シティポップ / シンセウェーブ（ゲートリバーブのスネア）=================
	"evening": {
		"bpm": 108.0, "swing": 0.05, "key": 0, "minor": false, "kit": "synth", "loop_from": 0, "crest": 13.0,
		"stem_db": [-17.0, -19.0, -20.0],
		"duck": [0.35, 0.2, 0.15, 0.2],
		"pad_lfo": [0.05, 0.4, 2200.0, 0.9],
		"sat": [1.4, 1.3, 1.25],
		"width": [1.0, 1.25, 1.3],
		"rev": [[1.6, 1.0, 0.4, 0.14, 300.0, 8.0], [2.2, 1.2, 0.5, 0.12, 400.0, 15.0], [2.8, 1.3, 0.45, 0.28, 300.0, 22.0]],
		"arp_delay": [3.0, 0.4, 0.5],
		"lead_delay": [3.0, 0.3, 0.3],
		"lead_chorus": [0.4, 15.0, 3.5, 0.5],
		"progs": {
			"i": [["Fmaj7", 1], ["G7", 1], ["Em7", 1], ["Am7", 1]],
			"A": [["Fmaj7", 1], ["G7", 1], ["Em7", 1], ["Am7", 1], ["Dm7", 1], ["G7", 1], ["Cmaj7", 1], ["C7", 1]],
			"B": [["Fmaj7", 1], ["Em7", 1], ["Dm7", 1], ["Cmaj7", 1], ["Bbmaj7", 1], ["Am7", 1], ["Dm7", 1], ["G7", 1]],
			"K": [["Am7", 2], ["Dm7", 2], ["Bbmaj7", 2], ["G7", 2]],
		},
		"drums": {
			"i": {"k": "9.......9.5.....9.....5.9.......", "s": "....9.......9...", "h": "6.4.6.4.6.4.6.4.", "r": "3.2.3.2.3.2.3.2.",
					"fill_every": 4, "fill": {"s": "....9...........", "t": "........9.9.....", "u": "............9...", "v": "..............9."}},
			"A": {"k": "9.......9.5.....9.....5.9.......", "s": "....9.......9...", "h": "6.4.6.4.6.4.6.4.", "o": "..............5.................",
					"r": "3.2.3.2.3.2.3.2.", "fill_every": 8,
					"fill": {"s": "....9...........", "t": "........9.9.....", "u": "............9...", "v": "..............9."}},
			"B": {"k": "9.......9.5.....9.....5.9.......", "s": "....9.......9...", "h": "6.4.6.4.6.4.6.45", "o": "..............5.................",
					"r": "3.2.3.2.3.2.3.2.", "fill_every": 4,
					"fill": {"s": "....9...........", "t": "........9.9.....", "u": "............9...", "v": "..............9."}},
			"K": {"k": "9...............", "s": "........9.......", "h": "4.2.4.2.4.2.4.2.", "r": "2.2.2.2.2.2.2.2.", "c": "................................",
					"fill_every": 8, "fill": {"t": "........5.5.....", "u": "............7...", "v": "..............9."}},
		},
		"bass": {
			"A": {"kind": "saw", "lo": 28, "level": 0.8, "cut_hi": 1400.0, "cut_lo": 320.0, "env": 0.1, "q": 1.3, "sub": 0.45, "drive": 1.3,
					"pat": ["0:2:0 2:2:12 4:2:0 6:2:12 8:2:0 10:2:12 12:2:0 14:2:12"]},
			"B": {"kind": "saw", "lo": 28, "level": 0.8, "cut_hi": 1700.0, "cut_lo": 350.0, "env": 0.1, "q": 1.4, "sub": 0.45, "drive": 1.35,
					"pat": ["0:3:0 3:1:7 4:2:12 8:3:0 11:1:7 12:2:10 14:2:12", "0:3:0 3:1:7 4:2:12 8:2:0 10:2:7 12:2:5 14:2:7"]},
			"K": {"kind": "sub", "lo": 28, "level": 0.8, "drive": 1.6, "pat": ["0:8:0 8:8:0"]},
		},
		"pads": {
			"A": {"count": 4, "center": 60, "voices": 5, "spread": 9.0, "level": 0.5, "att": 0.5, "rel": 0.8, "width": 0.9},
			"B": {"count": 4, "center": 62, "voices": 5, "spread": 10.0, "level": 0.6, "att": 0.4, "rel": 0.8, "width": 1.0},
			"K": {"count": 4, "center": 60, "voices": 5, "spread": 10.0, "level": 0.7, "att": 0.9, "rel": 1.0, "width": 1.0},
		},
		"comps": {
			"A": {"kind": "ep", "count": 4, "center": 64, "level": 0.55, "stem": "lead", "idx0": 2.0, "idx1": 0.4, "mod_decay": 0.35, "decay": 1.1,
					"pat": ["0:3 3:3 6:2 8:3 11:3 14:2"]},
			"B": {"kind": "ep", "count": 4, "center": 65, "level": 0.55, "stem": "lead", "idx0": 2.2, "idx1": 0.45, "mod_decay": 0.35, "decay": 1.1,
					"pat": ["0:6 6:2 8:6 14:2", "0:3 3:3 6:2 8:6 14:2"]},
			"K": {"kind": "ep", "count": 4, "center": 62, "level": 0.6, "stem": "lead", "idx0": 1.8, "idx1": 0.35, "mod_decay": 0.4, "decay": 1.6,
					"pat": ["0:16", "0:8 8:8"]},
		},
		"arps": {
			"A": {"kind": "bell", "idx": "0 . 1 . 2 . 3 . 2 . 1 . 2 . 3 .", "vel": "9 4 7 4 8 4 7 4", "center": 72.0, "level": 0.35, "len": 2.5,
					"ratio": 2.76, "idx0": 1.6, "idx1": 0.2, "mod_decay": 0.3, "decay": 0.5, "tine": 0.0, "pan": 0.45},
			"B": {"kind": "bell", "idx": "0 1 2 3 2 1 2 3 4 3 2 3 2 1 2 3", "vel": "9 4 7 4 8 4 7 4", "center": 72.0, "level": 0.36, "len": 2.0,
					"ratio": 2.76, "idx0": 1.8, "idx1": 0.2, "mod_decay": 0.3, "decay": 0.45, "tine": 0.0, "pan": 0.45},
		},
		"leads": {
			"V": {"kind": "saw", "phrase_bars": 2, "center": 72.0, "level": 0.55, "seq": [0, 1, 0, 2], "lo": 1400.0, "hi": 3600.0, "cut_dec": 0.2,
					"detune": 0.004, "vib": 0.005, "sub": 0.12, "dec": 3.0, "att": 0.02, "rel": 0.25,
					"phrases": ["0:4:2 4:2:1 6:2:2 8:6:3 14:2:2 16:4:2 20:2:1 22:2:0 24:8:1",
							"0:4:1 4:2:2 6:2:3 8:6:2 14:2:1 16:4:3 20:2:2 22:2:1 24:8:2",
							"0:4:2 4:2:3 6:2:2 8:4:1 12:4:2 16:4:3 20:4:2 24:8:1"]},
			"C": {"kind": "saw", "phrase_bars": 2, "center": 74.0, "level": 0.6, "seq": [0, 1], "lo": 1600.0, "hi": 4400.0, "cut_dec": 0.15,
					"detune": 0.004, "vib": 0.005, "sub": 0.12, "dec": 3.0, "att": 0.015, "rel": 0.2,
					"phrases": ["0:2:3 2:2:2 4:4:3 8:2:4 10:2:3 12:4:2 16:2:3 18:2:2 20:2:1 22:2:2 24:8:3",
							"0:2:2 2:2:3 4:4:4 8:2:3 10:2:2 12:4:3 16:4:2 20:4:3 24:8:4"]},
			"S": {"kind": "saw", "phrase_bars": 4, "center": 72.0, "level": 0.55, "seq": [0], "lo": 1200.0, "hi": 3200.0, "cut_dec": 0.3,
					"detune": 0.005, "vib": 0.007, "sub": 0.1, "dec": 4.0, "att": 0.05, "rel": 0.4,
					"phrases": ["0:12:2 12:4:3 16:12:4 28:4:3 32:12:3 44:4:2 48:16:1"]},
		},
		"sections": [
			{"name": "intro", "prog": "i", "drums": "i", "pad": "A", "comp": "A", "cut": [900.0, 2200.0], "ramp": [0.7, 1.0]},
			{"name": "A1", "prog": "A", "drums": "A", "bass": "A", "pad": "A", "comp": "A", "arp": "A", "fx": {"crash": 0.9}},
			{"name": "A2", "prog": "A", "drums": "A", "bass": "A", "pad": "A", "comp": "A", "arp": "A", "lead": "V"},
			{"name": "B1", "prog": "B", "drums": "B", "bass": "B", "pad": "B", "comp": "B", "arp": "B", "lead": "C", "fx": {"crash": 1.1}},
			{"name": "B2", "prog": "B", "drums": "B", "bass": "B", "pad": "B", "comp": "B", "arp": "B", "lead": "C"},
			{"name": "bridge", "prog": "K", "drums": "K", "bass": "K", "pad": "K", "pad_gain": 0.8, "comp": "K", "lead": "S", "cut": [1000.0, 3000.0], "fx": {"impact": 0.6}},
			{"name": "final", "prog": "B", "drums": "B", "bass": "B", "pad": "B", "comp": "B", "arp": "B", "lead": "C", "fx": {"crash": 1.2}},
			{"name": "outro", "prog": "A", "drums": "A", "bass": "A", "pad": "A", "comp": "A", "arp": "A", "lead": "V", "fx": {"riser": 2, "riser_gain": 0.7}},
		],
	},
	# ================= 夜の駅前：168 BPM・イ短調・リキッドドラムンベース（サブベース）=================
	"night": {
		"bpm": 168.0, "swing": 0.0, "key": 9, "minor": true, "kit": "dnb", "loop_from": 0, "crest": 12.5,
		"stem_db": [-17.0, -18.5, -20.0],
		"duck": [0.3, 0.18, 0.14, 0.1],
		"pad_lfo": [0.04, 0.5, 2000.0, 0.9],
		"sat": [1.6, 1.7, 1.3],
		"width": [1.0, 1.3, 1.3],
		"rev": [[1.4, 0.9, 0.5, 0.12, 400.0, 8.0], [3.0, 1.3, 0.55, 0.14, 400.0, 20.0], [3.2, 1.4, 0.5, 0.3, 300.0, 26.0]],
		"arp_delay": [3.0, 0.45, 0.5],
		"lead_delay": [3.0, 0.3, 0.35],
		"lead_chorus": [0.35, 16.0, 4.0, 0.5],
		"progs": {
			"i1": [["Am9", 2], ["Fmaj7", 2]],
			"i2": [["Cmaj7", 2], ["G6", 2]],
			"A": [["Am9", 2], ["Fmaj7", 2], ["Cmaj7", 2], ["G6", 2]],
			"B": [["Dm9", 2], ["Fmaj7", 2], ["Am9", 2], ["E7", 2]],
			"K": [["Am9", 4], ["Fmaj7", 4]],
			"K2": [["Cmaj7", 4], ["G6", 4]],
		},
		"drums": {
			"i1": {"h": "5.3.5.3.5.3.5.3.", "q": "2323232323232323", "o": "..4.......4....."},
			"i2": {"k": "9.........9.....9.........9.5...", "s": "....9...........", "h": "5.3.5.3.5.3.5.3.", "q": "2323232323232323",
					"fill_every": 4, "fill": {"s": "....9.....5.7.9."}},
			"A": {"k": "9.........9.....9.........9.5...", "s": "....9.......9...", "g": ".......3.......3","h": "6.3.6.3.6.3.6.3.", "o": "..5.......5.....",
					"q": "2323232323232323", "fill_every": 8, "fill": {"s": "3344556677889999", "g": "................"}},
			"B": {"k": "9.........9.....9.........9.5...", "s": "....9.......9...", "g": ".......3.......3","h": "6.3.6.3.6.3.6.3.", "o": "..5.......5.....",
					"r": "6.4.6.4.6.4.6.4.", "q": "2323232323232323", "fill_every": 8, "fill": {"s": "3344556677889999", "g": "................"}},
			"K": {"k": "9...............", "s": "........9.......", "h": "5.3.5.3.5.3.5.3.", "r": "6.4.6.4.6.4.6.4.",
					"fill_every": 8, "fill": {"s": "........5.5.7.9."}},
			"U": {"k": "9.........9.....", "s": "........9.......", "h": "6.3.6.3.6.3.6.3.", "q": "2323232323232323",
					"fill_every": 4, "fill": {"s": "3344556677889999", "k": "9..............."}},
		},
		"bass": {
			"S": {"kind": "sub", "lo": 28, "level": 0.9, "drive": 1.8, "pat": ["0:7:0 8:3:0 11:5:7", "0:6:0 7:1:0 10:6:12"]},
			"S2": {"kind": "sub", "lo": 28, "level": 0.85, "drive": 1.7, "pat": ["0:16:0"]},
			"R": {"kind": "reese", "lo": 40, "level": 0.5, "cut": 700.0, "depth": 0.6, "lfo": 0.6, "drive": 1.5,
					"pat": ["0:3:0 4:2:0 8:3:0 12:2:3", "0:3:0 4:2:0 8:3:0 12:2:7"]},
		},
		"pads": {
			"lush": {"count": 4, "center": 62, "voices": 7, "spread": 14.0, "level": 0.55, "att": 0.8, "rel": 1.0, "width": 1.0},
			"A": {"count": 4, "center": 60, "voices": 5, "spread": 12.0, "level": 0.5, "att": 0.7, "rel": 1.0, "width": 0.9},
		},
		"comps": {
			"A": {"kind": "ep", "count": 4, "center": 66, "level": 0.5, "stem": "lead", "ext": true, "idx0": 2.0, "idx1": 0.4, "mod_decay": 0.35, "decay": 1.2,
					"pat": ["0:6 6:4 12:4"]},
			"B": {"kind": "ep", "count": 4, "center": 67, "level": 0.5, "stem": "lead", "ext": true, "idx0": 2.2, "idx1": 0.45, "mod_decay": 0.35, "decay": 1.2,
					"pat": ["0:3 3:3 6:3 10:6", "0:6 6:4 12:4"]},
			"K": {"kind": "ep", "count": 4, "center": 64, "level": 0.55, "stem": "lead", "ext": true, "idx0": 1.8, "idx1": 0.35, "mod_decay": 0.4, "decay": 1.8,
					"pat": ["0:16"]},
		},
		"arps": {
			"A": {"kind": "bell", "idx": "0 . 2 . 4 . 2 . 3 . 2 . 4 . 5 .", "vel": "9 4 7 4 8 4 7 4", "center": 74.0, "level": 0.33, "len": 2.5,
					"ratio": 2.76, "idx0": 1.6, "idx1": 0.2, "mod_decay": 0.3, "decay": 0.5, "tine": 0.0, "pan": 0.45},
			"B": {"kind": "bell", "idx": "0 2 4 2 3 2 4 5 4 2 3 2 4 2 5 6", "vel": "9 4 7 4 8 4 7 4", "center": 74.0, "level": 0.33, "len": 2.0,
					"ratio": 2.76, "idx0": 1.8, "idx1": 0.2, "mod_decay": 0.3, "decay": 0.45, "tine": 0.0, "pan": 0.45},
		},
		"leads": {
			"V": {"kind": "saw", "phrase_bars": 4, "center": 74.0, "level": 0.5, "seq": [0, 1], "lo": 1400.0, "hi": 3600.0, "cut_dec": 0.25,
					"detune": 0.004, "vib": 0.005, "sub": 0.1, "dec": 3.5, "att": 0.03, "rel": 0.3,
					"phrases": ["0:8:2 8:4:3 12:4:2 16:10:3 28:4:2 32:8:4 40:4:3 44:4:2 48:12:3 60:4:2",
							"0:6:3 6:2:2 8:6:3 14:2:4 16:12:3 32:6:2 38:2:3 40:8:4 48:16:3"]},
			"C": {"kind": "saw", "phrase_bars": 4, "center": 76.0, "level": 0.55, "seq": [0, 1], "lo": 1600.0, "hi": 4400.0, "cut_dec": 0.2,
					"detune": 0.004, "vib": 0.005, "sub": 0.1, "dec": 3.0, "att": 0.02, "rel": 0.25,
					"phrases": ["0:4:2 4:4:3 8:4:4 12:4:3 16:6:4 22:2:3 24:8:2 32:4:2 36:4:3 40:4:4 44:4:5 48:12:4",
							"0:3:3 3:1:4 4:4:3 8:8:2 16:4:3 20:4:4 24:8:3 32:4:4 36:4:3 40:8:2 48:16:3"]},
		},
		"sections": [
			{"name": "intro1", "prog": "i1", "drums": "i1", "pad": "lush", "arp": "A", "cut": [600.0, 1200.0], "ramp": [0.6, 1.0]},
			{"name": "intro2", "prog": "i2", "drums": "i2", "bass": "S", "pad": "lush", "arp": "A", "cut": [1200.0, 2200.0], "fx": {"riser": 2}},
			{"name": "A1", "prog": "A", "drums": "A", "bass": "S", "pad": "lush", "comp": "A", "arp": "A", "fx": {"crash": 1.0}},
			{"name": "A2", "prog": "A", "drums": "A", "bass": "S", "pad": "lush", "comp": "A", "arp": "A", "lead": "V"},
			{"name": "B1", "prog": "B", "drums": "B", "bass": "S", "bass2": "R", "pad": "lush", "comp": "B", "arp": "B", "lead": "C", "fx": {"crash": 1.1}},
			{"name": "B2", "prog": "B", "drums": "B", "bass": "S", "bass2": "R", "pad": "lush", "comp": "B", "arp": "B", "lead": "C"},
			{"name": "break1", "prog": "K", "drums": "K", "bass": "S2", "pad": "lush", "pad_gain": 0.75, "comp": "K", "lead": "V", "cut": [900.0, 1800.0], "fx": {"impact": 0.7}},
			{"name": "break2", "prog": "K2", "drums": "U", "bass": "S2", "pad": "lush", "comp": "K", "arp": "B", "cut": [1800.0, 4500.0], "arp_gain": 0.8, "fx": {"riser": 8}},
			{"name": "drop1", "prog": "A", "drums": "B", "bass": "S", "bass2": "R", "pad": "lush", "comp": "B", "arp": "B", "lead": "C", "fx": {"crash": 1.3, "impact": 0.6}},
			{"name": "drop2", "prog": "A", "drums": "B", "bass": "S", "bass2": "R", "pad": "lush", "comp": "B", "arp": "B", "lead": "V"},
			{"name": "B3", "prog": "B", "drums": "B", "bass": "S", "bass2": "R", "pad": "lush", "comp": "B", "arp": "B", "lead": "C", "fx": {"crash": 1.1}},
			{"name": "B4", "prog": "B", "drums": "A", "bass": "S", "pad": "lush", "comp": "A", "arp": "A", "lead": "V"},
			{"name": "outro", "prog": "A", "drums": "A", "bass": "S", "pad": "A", "comp": "A", "arp": "A", "fx": {"riser": 2}},
		],
	},
	# ================= メニュー：84 BPM・ニ長調・静かなローファイ =================
	"menu": {
		"bpm": 84.0, "swing": 0.2, "key": 2, "minor": false, "kit": "soft", "loop_from": 0, "crest": 14.0,
		"stem_db": [-21.0, -19.0, -20.0],
		"duck": [0.12, 0.08, 0.08, 0.3],
		"pad_lfo": [0.04, 0.4, 1500.0, 0.8],
		"sat": [1.2, 1.2, 1.15],
		"width": [1.0, 1.3, 1.3],
		"rev": [[1.8, 1.0, 0.5, 0.16, 400.0, 10.0], [3.0, 1.3, 0.55, 0.16, 400.0, 22.0], [3.4, 1.4, 0.5, 0.3, 300.0, 26.0]],
		"arp_delay": [3.0, 0.5, 0.55],
		"lead_delay": [3.0, 0.4, 0.4],
		"progs": {
			"i": [["Dmaj7", 2], ["Bm7", 2]],
			"A": [["Dmaj7", 2], ["Bm7", 2], ["Gmaj7", 2], ["Asus4", 1], ["A", 1]],
			"B": [["Gmaj7", 2], ["F#m7", 2], ["Em7", 2], ["A", 2]],
			"C": [["Bm7", 2], ["Gmaj7", 2], ["Dmaj7", 2], ["A", 2]],
			"O": [["Gmaj7", 2], ["A", 2]],
		},
		"drums": {
			"i": {"h": "4.2.4.2.4.2.4.2.", "r": "2.2.2.2.2.2.2.2."},
			"A": {"k": "9.......6.......9.....6.........", "s": "........7.......", "h": "4.2.4.2.4.2.4.2.", "r": "2.2.2.2.2.2.2.2.", "n": "............3..."},
			"B": {"k": "9.......6.......9.....6...6.....", "s": "........7.......", "h": "5.3.5.3.5.3.5.3.", "o": "..............3.................",
					"r": "3.2.3.2.3.2.3.2.", "n": "............3..."},
			"C": {"h": "4.2.4.2.4.2.4.2.", "r": "2.2.2.2.2.2.2.2.", "k": "9..............."},
			"O": {"k": "9.......6.......", "s": "........7.......", "h": "4.2.4.2.4.2.4.2."},
		},
		"bass": {
			"A": {"kind": "sub", "lo": 28, "level": 0.8, "drive": 1.5, "pat": ["0:8:0 8:6:0 14:2:7"]},
			"C": {"kind": "sub", "lo": 28, "level": 0.8, "drive": 1.5, "pat": ["0:16:0"]},
		},
		"pads": {
			"A": {"count": 4, "center": 62, "voices": 5, "spread": 9.0, "level": 0.55, "att": 0.9, "rel": 1.2, "width": 1.0},
		},
		"comps": {
			"A": {"kind": "ep", "count": 4, "center": 64, "level": 0.55, "stem": "bass", "idx0": 1.6, "idx1": 0.3, "mod_decay": 0.4, "decay": 1.3,
					"pat": ["0:6 6:4 12:4"]},
			"B": {"kind": "ep", "count": 4, "center": 66, "level": 0.55, "stem": "bass", "idx0": 1.8, "idx1": 0.3, "mod_decay": 0.4, "decay": 1.3,
					"pat": ["0:4 4:4 8:4 12:4", "0:6 6:4 12:4"]},
		},
		"arps": {
			"A": {"kind": "bell", "idx": "0 . . 1 . . 2 . . 1 . . 3 . . .", "vel": "9 4 6 4", "center": 74.0, "level": 0.4, "len": 4.0,
					"ratio": 2.76, "idx0": 1.4, "idx1": 0.15, "mod_decay": 0.35, "decay": 0.7, "tine": 0.0, "pan": 0.5},
			"B": {"kind": "bell", "idx": "0 . 1 . 2 . 1 . 3 . 2 . 1 . 2 .", "vel": "9 4 6 4", "center": 74.0, "level": 0.4, "len": 3.0,
					"ratio": 2.76, "idx0": 1.5, "idx1": 0.15, "mod_decay": 0.35, "decay": 0.6, "tine": 0.0, "pan": 0.5},
		},
		"leads": {
			"M": {"kind": "bell", "phrase_bars": 4, "center": 78.0, "level": 0.5, "seq": [0, 1], "ratio": 2.76, "idx0": 1.3, "idx1": 0.12,
					"mod_decay": 0.4, "decay": 1.1, "tine": 0.0, "pan": 0.0,
					"phrases": ["0:6:2 8:4:1 12:4:2 16:8:3 28:4:2 32:6:1 40:4:2 44:4:1 48:12:0",
							"0:4:3 6:4:2 12:4:3 16:6:2 24:8:1 32:6:3 40:6:2 48:12:1"]},
		},
		"sections": [
			{"name": "intro", "prog": "i", "drums": "i", "pad": "A", "comp": "A", "cut": [700.0, 1500.0], "ramp": [0.6, 1.0]},
			{"name": "A1", "prog": "A", "drums": "A", "bass": "A", "pad": "A", "comp": "A", "arp": "A"},
			{"name": "B1", "prog": "B", "drums": "B", "bass": "A", "pad": "A", "comp": "B", "arp": "B", "lead": "M"},
			{"name": "bridge", "prog": "C", "drums": "C", "bass": "C", "pad": "A", "comp": "A", "arp": "A", "cut": [900.0, 2000.0], "pad_gain": 1.2},
			{"name": "A2", "prog": "A", "drums": "A", "bass": "A", "pad": "A", "comp": "A", "arp": "A", "lead": "M"},
			{"name": "B2", "prog": "B", "drums": "B", "bass": "A", "pad": "A", "comp": "B", "arp": "B", "lead": "M"},
			{"name": "outro", "prog": "O", "drums": "O", "bass": "C", "pad": "A", "comp": "A", "arp": "A"},
		],
	},
}

