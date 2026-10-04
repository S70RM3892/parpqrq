extends SceneTree
## 効果音とBGMを合成して assets/audio/*.wav に書き出す（仕様書 4・5章「サウンド」。音素材が無いので手続き的に作る）。
##   godot --headless --path . -s tools/build_audio.gd
## 実行時に合成すると読み込みが3秒を超えるので、ここで一度だけ作ってコミットする。
## ループする音は WAV の smpl チャンクにループ点を書く（Godot の取り込みが「WAVから検出」で読む）。

const OUT := "res://assets/audio/"
const SR := 44100        ## 効果音
const SR_LOOP := 22050   ## BGM・環境音のループ（容量を抑える）
const BPM := 140.0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 20261004
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_sfx()
	_build_loops()
	_build_music()
	print("build_audio: done")
	quit()


# --- 効果音 -----------------------------------------------------------------

func _build_sfx() -> void:
	for i: int in 3:
		_save("step_concrete_%d" % i, _step_concrete(), SR)
		_save("step_metal_%d" % i, _step_metal(), SR)
		_save("step_glass_%d" % i, _step_glass(), SR)
		_save("step_gravel_%d" % i, _step_gravel(), SR)
	for i: int in 2:
		_save("hand_%d" % i, _hand(), SR)
	_save("land_light", _land(0.35, 0.10, false), SR)
	_save("land_mid", _land(0.65, 0.16, false), SR)
	_save("land_heavy", _land(1.0, 0.30, true), SR)
	_save("roll", _roll(), SR)
	_save("jump", _whoosh(0.16, 900.0, 2600.0, 0.35), SR)
	_save("crash", _crash(), SR)
	_save("perfect", _chime([1567.98, 2349.32], 0.55, 0.5), SR)
	_save("checkpoint", _chime([880.0, 1318.51], 0.5, 0.35), SR)
	_save("split", _chime([1760.0], 0.18, 0.3), SR)
	_save("goal", _goal(), SR)
	_save("respawn", _whoosh(0.22, 500.0, 3000.0, 0.4), SR)
	_save("ui_move", _click(2400.0, 0.025, 0.25), SR)
	_save("ui_ok", _chime([1318.51, 1975.53], 0.18, 0.35), SR)
	_save("ui_back", _chime([987.77, 659.26], 0.16, 0.3), SR)


## 足音：コンクリ = 低い「トン」と短いザッ
func _step_concrete() -> PackedFloat32Array:
	var n := int(SR * 0.16)
	var out := _thump(n, _rng.randf_range(75.0, 95.0), 0.045, 0.7)
	var scuff := _bp(_noise(n), 400.0, 2600.0, SR)
	_mul_env(scuff, 0.002, 0.05)
	_add(out, scuff, 0, 0.9)
	return _normalized(out, 0.8)


## 金属：トンの上に響く倍音（調和しない比で鳴らすと金属らしい）
func _step_metal() -> PackedFloat32Array:
	var n := int(SR * 0.45)
	var out := _thump(n, 110.0, 0.04, 0.5)
	var base := _rng.randf_range(380.0, 460.0)
	for k: float in [1.0, 2.71, 5.18, 8.43]:
		var tone := _sine(n, base * k, 0.0)
		_mul_env(tone, 0.001, 0.22 / sqrt(k))
		_add(out, tone, 0, 0.35 / k)
	var clank := _bp(_noise(n), 1500.0, 6000.0, SR)
	_mul_env(clank, 0.001, 0.02)
	_add(out, clank, 0, 0.6)
	return _normalized(out, 0.75)


## ガラス：高いカチッと短い響き
func _step_glass() -> PackedFloat32Array:
	var n := int(SR * 0.3)
	var out := _thump(n, 95.0, 0.035, 0.5)
	var base := _rng.randf_range(2300.0, 2700.0)
	for k: float in [1.0, 1.63, 2.52]:
		var tone := _sine(n, base * k, _rng.randf() * TAU)
		_mul_env(tone, 0.0005, 0.11 / k)
		_add(out, tone, 0, 0.3 / k)
	var tick := _hp(_noise(n), 4000.0, SR)
	_mul_env(tick, 0.0003, 0.006)
	_add(out, tick, 0, 0.7)
	return _normalized(out, 0.7)


## 砂利：細かい粒がザクッと
func _step_gravel() -> PackedFloat32Array:
	var n := int(SR * 0.2)
	var out := _thump(n, 80.0, 0.04, 0.45)
	var grains := PackedFloat32Array()
	grains.resize(n)
	for g: int in 40:
		var at := int(_rng.randf_range(0.0, 0.11) * SR)
		var len := int(SR * _rng.randf_range(0.003, 0.012))
		var amp := _rng.randf_range(0.3, 1.0) * (1.0 - float(at) / n)
		for i: int in len:
			if at + i < n:
				grains[at + i] += _rng.randf_range(-1.0, 1.0) * amp * (1.0 - float(i) / len)
	_add(out, _bp(grains, 1200.0, 7000.0, SR), 0, 1.4)
	return _normalized(out, 0.75)


## 手が触れる「パシッ」（ヴォルト・クライム・縁を掴む）
func _hand() -> PackedFloat32Array:
	var n := int(SR * 0.14)
	var slap := _bp(_noise(n), _rng.randf_range(900.0, 1200.0), 5000.0, SR)
	_mul_env(slap, 0.0004, 0.028)
	var out := _thump(n, 160.0, 0.025, 0.35)
	_add(out, slap, 0, 1.0)
	return _normalized(out, 0.85)


## 着地：落下速度で3段階。ハードランディングは低音を強調
func _land(weight: float, length: float, boom: bool) -> PackedFloat32Array:
	var n := int(SR * (length + 0.25))
	var out := _thump(n, lerpf(85.0, 60.0, weight), length * 0.5, 1.0)
	var dust := _bp(_noise(n), 200.0, lerpf(1800.0, 1200.0, weight), SR)
	_mul_env(dust, 0.002, length * 0.6)
	_add(out, dust, 0, 0.6 + weight * 0.4)
	if boom:
		var sub := _sweep(n, 70.0, 38.0, 0.25)
		_mul_env(sub, 0.004, 0.35)
		_add(out, sub, 0, 1.1)
	return _normalized(out, lerpf(0.55, 0.95, weight))


func _roll() -> PackedFloat32Array:
	var n := int(SR * 0.55)
	var out := _whoosh(0.5, 300.0, 1400.0, 0.7)
	var thud := _thump(n, 70.0, 0.08, 0.7)
	_add(out, thud, int(SR * 0.05), 0.8)
	var thud2 := _thump(n, 90.0, 0.05, 0.4)
	_add(out, thud2, int(SR * 0.3), 0.6)
	return _normalized(out, 0.7)


func _crash() -> PackedFloat32Array:
	var n := int(SR * 0.5)
	var out := _thump(n, 55.0, 0.18, 1.0)
	var hit := _bp(_noise(n), 150.0, 2500.0, SR)
	_mul_env(hit, 0.001, 0.09)
	_add(out, hit, 0, 1.0)
	return _normalized(out, 0.95)


## 風を切る「シュッ」：帯域を動かしたノイズ
func _whoosh(length: float, lo: float, hi: float, peak_at: float) -> PackedFloat32Array:
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
	return _normalized(out, 0.6)


## 鐘のような音（Perfect・チェックポイント・UI）
func _chime(freqs: Array, length: float, peak: float) -> PackedFloat32Array:
	var n := int(SR * length)
	var out := PackedFloat32Array()
	out.resize(n)
	for j: int in freqs.size():
		var f: float = freqs[j]
		var at := int(SR * 0.045 * j)
		for k: float in [1.0, 2.0, 3.01]:
			var tone := _sine(n - at, f * k, 0.0)
			_mul_env(tone, 0.002, length * 0.35 / k)
			_add(out, tone, at, 0.5 / (k * k))
	return _normalized(out, peak)


func _goal() -> PackedFloat32Array:
	var notes := [880.0, 1108.73, 1318.51, 1760.0]
	var n := int(SR * 1.2)
	var out := PackedFloat32Array()
	out.resize(n)
	for j: int in notes.size():
		var c := _chime([notes[j]], 0.9 - j * 0.1, 1.0)
		_add(out, c, int(SR * 0.09 * j), 0.6)
	return _normalized(out, 0.7)


func _click(freq: float, length: float, peak: float) -> PackedFloat32Array:
	var n := int(SR * length)
	var out := _sine(n, freq, 0.0)
	_mul_env(out, 0.0005, length * 0.3)
	return _normalized(out, peak)


# --- 環境音のループ ---------------------------------------------------------

func _build_loops() -> void:
	# 風切り音（低）：茶色ノイズにゆっくりした息継ぎ
	var n := int(SR_LOOP * 4.0)
	var low := _lp(_lp(_noise(n), 500.0, SR_LOOP), 700.0, SR_LOOP)
	for i: int in n:
		var t := float(i) / SR_LOOP
		low[i] *= 0.75 + 0.25 * sin(TAU * t * 0.5) * sin(TAU * t * 0.25 + 1.0)
	_save("wind_low", _normalized(_looped(low, SR_LOOP / 4), 0.8), SR_LOOP, true)
	# 風切り音（高）：速くなると足す高音
	n = int(SR_LOOP * 3.0)
	var high := _bp(_noise(n), 2500.0, 7000.0, SR_LOOP)
	for i: int in n:
		var t := float(i) / SR_LOOP
		high[i] *= 0.7 + 0.3 * sin(TAU * t * (1.0 / 3.0) * 2.0)
	_save("wind_high", _normalized(_looped(high, SR_LOOP / 4), 0.6), SR_LOOP, true)
	# スライドの擦れ
	n = int(SR_LOOP * 2.0)
	var scrape := _bp(_noise(n), 500.0, 2400.0, SR_LOOP)
	for i: int in n:
		scrape[i] *= 0.6 + 0.4 * absf(sin(float(i) / SR_LOOP * TAU * 13.0)) * _rng.randf_range(0.7, 1.0)
	_save("slide_loop", _normalized(_looped(scrape, SR_LOOP / 8), 0.7), SR_LOOP, true)
	# 息づかい：吸う→吐く（勢い値で速く・荒くする：再生速度と音量を変える）
	n = int(SR_LOOP * 2.4)
	var breath := PackedFloat32Array()
	breath.resize(n)
	var inhale := _bp(_noise(n), 900.0, 2600.0, SR_LOOP)
	var exhale := _bp(_noise(n), 450.0, 1600.0, SR_LOOP)
	for i: int in n:
		var t := float(i) / SR_LOOP
		var e_in := smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(0.6, 0.9, t))
		var e_out := smoothstep(1.0, 1.15, t) * (1.0 - smoothstep(1.2, 2.1, t))
		breath[i] = inhale[i] * e_in * 0.6 + exhale[i] * e_out
	_save("breath", _normalized(breath, 0.6), SR_LOOP, true)


# --- BGM（仕様書 5章：勢い値で3段階にレイヤーを重ねる。ドラム→ベース→リード）---------------

func _build_music() -> void:
	var bars := 8
	var step_len := 60.0 / BPM / 4.0  # 16分音符
	var total := int(round(bars * 16 * step_len * SR_LOOP))
	_save("music_drums", _normalized(_drums(bars, step_len, total), 0.55), SR_LOOP, true)
	_save("music_bass", _normalized(_bass(bars, step_len, total), 0.5), SR_LOOP, true)
	_save("music_lead", _normalized(_lead(bars, step_len, total), 0.45), SR_LOOP, true)


## 2小節ずつ Am → F → C → G
const CHORDS: Array[Array] = [
	[57, 60, 64, 69], [53, 57, 60, 65], [48, 52, 55, 60], [55, 59, 62, 67],
]


func _drums(bars: int, step_len: float, total: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(total)
	var kick := _kick()
	var snare := _snare()
	var hat := _hat(0.035)
	var open_hat := _hat(0.16)
	for bar: int in bars:
		var fill := bar == bars - 1
		for s: int in 16:
			var at := int(round((bar * 16 + s) * step_len * SR_LOOP))
			if s in [0, 6, 10] or (bar % 2 == 1 and s == 3):
				_add_wrap(out, kick, at, 1.0)
			if s in [4, 12]:
				_add_wrap(out, snare, at, 0.9)
			elif s in [7, 15] and not fill:
				_add_wrap(out, snare, at, 0.18)
			if fill and s >= 12:
				_add_wrap(out, snare, at, 0.35 + 0.15 * (s - 12))
			if s % 2 == 0:
				_add_wrap(out, open_hat if s == 14 else hat, at, 0.45 if s % 4 == 2 else 0.3)
			elif bar % 4 == 3:
				_add_wrap(out, hat, at, 0.18)
	return out


func _bass(bars: int, step_len: float, total: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(total)
	# 8分音符：ルート・ルート・オクターブ・ルート・5度・ルート・オクターブ・5度
	var pattern := [0, 0, 12, 0, 7, 0, 12, 7]
	for bar: int in bars:
		var chord: Array = CHORDS[(bar / 2) % 4]
		var root: int = chord[0] - 24
		for e: int in 8:
			var at := int(round((bar * 16 + e * 2) * step_len * SR_LOOP))
			var note := _saw_note(_midi(root + pattern[e]), step_len * 1.8, 1600.0, 260.0)
			_add_wrap(out, note, at, 0.9 if e % 2 == 0 else 0.7)
	return out


func _lead(bars: int, step_len: float, total: int) -> PackedFloat32Array:
	var dry := PackedFloat32Array()
	dry.resize(total)
	var order := [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 3, 2, 1, 2]
	for bar: int in bars:
		var chord: Array = CHORDS[(bar / 2) % 4]
		for s: int in 16:
			var at := int(round((bar * 16 + s) * step_len * SR_LOOP))
			var octave := 12 if (bar % 2 == 1 and s >= 8) else 0
			var note := _pluck(_midi(chord[order[s]] + octave), step_len * 2.5)
			_add_wrap(dry, note, at, 0.9 if s % 4 == 0 else 0.55)
	# 付点8分のディレイで広がりを出す（ループの頭へ回り込む）
	var out := dry.duplicate()
	var d := int(round(step_len * 3.0 * SR_LOOP))
	for pass_i: int in 3:
		var g := 0.35 * pow(0.5, pass_i)
		for i: int in total:
			out[(i + d * (pass_i + 1)) % total] += dry[i] * g
	return _lp(out, 5000.0, SR_LOOP)


func _kick() -> PackedFloat32Array:
	var n := int(SR_LOOP * 0.32)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i: int in n:
		var t := float(i) / SR_LOOP
		var f := 48.0 + 110.0 * exp(-t / 0.03)
		ph += TAU * f / SR_LOOP
		out[i] = sin(ph) * exp(-t / 0.13)
	var click := _hp(_noise(n), 2000.0, SR_LOOP)
	_mul_env_sr(click, 0.0002, 0.003, SR_LOOP)
	_add(out, click, 0, 0.4)
	return out


func _snare() -> PackedFloat32Array:
	var n := int(SR_LOOP * 0.25)
	var noise := _hp(_noise(n), 1200.0, SR_LOOP)
	_mul_env_sr(noise, 0.0005, 0.07, SR_LOOP)
	var tone := PackedFloat32Array()
	tone.resize(n)
	for i: int in n:
		var t := float(i) / SR_LOOP
		tone[i] = sin(TAU * 190.0 * t) * exp(-t / 0.05)
	_add(noise, tone, 0, 0.6)
	return noise


func _hat(decay: float) -> PackedFloat32Array:
	var n := int(SR_LOOP * (decay * 4.0 + 0.01))
	var out := _hp(_hp(_noise(n), 6000.0, SR_LOOP), 6000.0, SR_LOOP)
	_mul_env_sr(out, 0.0003, decay, SR_LOOP)
	return out


## ノコギリ波のベース：音の頭でフィルタが開いて閉じる
func _saw_note(freq: float, length: float, cut_hi: float, cut_lo: float) -> PackedFloat32Array:
	var n := int(SR_LOOP * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var y := 0.0
	var y2 := 0.0
	for i: int in n:
		var t := float(i) / SR_LOOP
		ph = fmod(ph + freq / SR_LOOP, 1.0)
		var saw := ph * 2.0 - 1.0
		var fc := cut_lo + (cut_hi - cut_lo) * exp(-t / 0.06)
		var a := 1.0 - exp(-TAU * fc / SR_LOOP)
		y += a * (saw - y)
		y2 += a * (y - y2)
		var env := minf(t / 0.004, 1.0) * (1.0 - smoothstep(length * 0.7, length, t)) * (0.6 + 0.4 * exp(-t / 0.1))
		out[i] = y2 * env
	return out


## つま弾く音（リード）：矩形に近い波を素早く減衰
func _pluck(freq: float, length: float) -> PackedFloat32Array:
	var n := int(SR_LOOP * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i: int in n:
		var t := float(i) / SR_LOOP
		var sq := tanh(sin(TAU * freq * t) * 3.0) * 0.7 + sin(TAU * freq * 2.0 * t) * 0.2
		var fc := 900.0 + 3500.0 * exp(-t / 0.05)
		y += (1.0 - exp(-TAU * fc / SR_LOOP)) * (sq - y)
		out[i] = y * minf(t / 0.002, 1.0) * exp(-t / 0.09)
	return out


func _midi(m: int) -> float:
	return 440.0 * pow(2.0, (m - 69) / 12.0)


# --- 部品 -------------------------------------------------------------------

func _noise(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in n:
		out[i] = _rng.randf_range(-1.0, 1.0)
	return out


func _sine(n: int, freq: float, phase: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(n, 0))
	for i: int in n:
		out[i] = sin(phase + TAU * freq * i / SR)
	return out


## 下へ滑る正弦波の「ドン」
func _thump(n: int, freq: float, decay: float, amp: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i: int in n:
		var t := float(i) / SR
		ph += TAU * freq * (1.0 + 0.8 * exp(-t / 0.012)) / SR
		out[i] = sin(ph) * exp(-t / decay) * amp * minf(t / 0.001, 1.0)
	return out


func _sweep(n: int, f0: float, f1: float, length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i: int in n:
		var t := float(i) / SR
		ph += TAU * lerpf(f0, f1, minf(t / length, 1.0)) / SR
		out[i] = sin(ph)
	return out


func _lp(x: PackedFloat32Array, fc: float, sr: int) -> PackedFloat32Array:
	var out := x.duplicate()
	var a := 1.0 - exp(-TAU * fc / sr)
	var y := 0.0
	for i: int in out.size():
		y += a * (x[i] - y)
		out[i] = y
	return out


func _hp(x: PackedFloat32Array, fc: float, sr: int) -> PackedFloat32Array:
	var low := _lp(x, fc, sr)
	var out := x.duplicate()
	for i: int in out.size():
		out[i] = x[i] - low[i]
	return out


func _bp(x: PackedFloat32Array, lo: float, hi: float, sr: int) -> PackedFloat32Array:
	return _hp(_lp(x, hi, sr), lo, sr)


func _mul_env(x: PackedFloat32Array, attack: float, decay: float) -> void:
	_mul_env_sr(x, attack, decay, SR)


func _mul_env_sr(x: PackedFloat32Array, attack: float, decay: float, sr: int) -> void:
	for i: int in x.size():
		var t := float(i) / sr
		x[i] *= minf(t / maxf(attack, 0.00001), 1.0) * exp(-maxf(t - attack, 0.0) / decay)


func _add(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> void:
	for i: int in src.size():
		if at + i >= dst.size():
			return
		dst[at + i] += src[i] * gain


## ループの終わりからはみ出した分は頭へ回す（継ぎ目で音が切れない）
func _add_wrap(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> void:
	var n := dst.size()
	for i: int in src.size():
		dst[(at + i) % n] += src[i] * gain


## 終わりの fade サンプルを頭に重ねて継ぎ目をなくす（長さは fade だけ短くなる）
func _looped(x: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := x.size() - fade
	var out := x.slice(0, n)
	for i: int in fade:
		var k := float(i) / fade
		out[i] = x[i] * k + x[n + i] * (1.0 - k)
	return out


func _normalized(x: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v: float in x:
		m = maxf(m, absf(v))
	if m < 1e-6:
		return x
	var out := x.duplicate()
	var k := peak / m
	for i: int in out.size():
		out[i] *= k
	return out


## 16bit モノラルの WAV を書く。loop = true なら smpl チャンクに全体のループを入れる
func _save(file_name: String, x: PackedFloat32Array, sr: int, loop: bool = false) -> void:
	var pcm := PackedByteArray()
	pcm.resize(x.size() * 2)
	for i: int in x.size():
		pcm.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(OUT + file_name + ".wav", FileAccess.WRITE)
	var smpl_size := 36 + 24 if loop else 0
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(4 + (8 + 16) + (8 + pcm.size()) + (8 + smpl_size if loop else 0))
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)        # PCM
	f.store_16(1)        # モノラル
	f.store_32(sr)
	f.store_32(sr * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	if loop:
		f.store_buffer("smpl".to_ascii_buffer())
		f.store_32(smpl_size)
		for v: int in [0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0]:
			f.store_32(v)
		# ループ1つ：前向き、0 から最後のサンプルまで
		for v: int in [0, 0, 0, x.size() - 1, 0, 0]:
			f.store_32(v)
	f.close()
