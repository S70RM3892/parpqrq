extends Node
## 全コース（＋フリーラン・タイトルの背景）の光を焼いて assets/lightmaps/<id>.res に書く。
##   godot --headless --path . res://tools/bake_lighting.tscn [-- --only=1-1,2-3] [--samples=256]
## コースの形（course_catalog.gd・course_builder.gd・course_props.gd）を変えたら焼き直す。
## 焼き直していないコースは光なしで表示され、コーステストが「lightmap stale」で落ちる。
## 焼く本体は C++（tools/lightbaker/lightbaker.cpp）。無ければ g++ で作る（-fopenmp で全コアを使う）。

const TitleScript := preload("res://scripts/ui/title.gd")
const BAKER_SRC := "res://tools/lightbaker/lightbaker.cpp"
const BAKER_BIN := "res://tools/lightbaker/build/lightbaker"

var _samples: int = 256


func _ready() -> void:
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",", false)
		elif a.begins_with("--samples="):
			_samples = a.trim_prefix("--samples=").to_int()
	var baker := _ensure_baker()
	if baker == "":
		Audio.quit_game(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LevelLighting.DIR))
	var ids := CourseCatalog.all_ids()
	ids.append("title")
	var failed := 0
	for id: String in ids:
		if not only.is_empty() and id not in only:
			continue
		var t0 := Time.get_ticks_msec()
		if not _bake(id, baker):
			failed += 1
			continue
		print("bake %s: %d ms" % [id, Time.get_ticks_msec() - t0])
	print("BAKE: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	Audio.quit_game(1 if failed > 0 else 0)


func _ensure_baker() -> String:
	var bin := ProjectSettings.globalize_path(BAKER_BIN)
	var src := ProjectSettings.globalize_path(BAKER_SRC)
	if FileAccess.file_exists(bin) and FileAccess.get_modified_time(bin) >= FileAccess.get_modified_time(src):
		return bin
	DirAccess.make_dir_recursive_absolute(bin.get_base_dir())
	var out: Array = []
	var code := OS.execute("g++", ["-O3", "-march=native", "-fopenmp", "-std=c++17", "-o", bin, src], out, true)
	if code != 0:
		push_error("bake_lighting: g++ failed:\n" + "\n".join(out))
		return ""
	return bin


## コースと同じ手順で形を組む（Course._ready / Title._build_background と同じ）
func _build_geometry(id: String) -> Array:
	var geo := LevelGeometry.new()
	geo.keep_bake_data = true
	var area: Dictionary
	if id == "title":
		area = CourseCatalog.AREAS[0]
		var tb := CourseBuilder.new(geo, area, 7)
		tb.build(TitleScript.BG_RECIPE)
	else:
		var def := CourseCatalog.get_course(id)
		area = CourseCatalog.area_of(id)
		if area.has("accent"):
			LevelStyle.set_accent(area.accent)
		var b := CourseBuilder.new(geo, area, int(def.get("seed", 1)))
		if id == CourseCatalog.FREE_RUN:
			b.build_district()
		else:
			b.build(CourseCatalog.recipe(id))
	geo.build()
	return [geo, area]


func _bake(id: String, baker: String) -> bool:
	var built := _build_geometry(id)
	var geo: LevelGeometry = built[0]
	var area: Dictionary = built[1]
	var p: Dictionary = Atmosphere.preset_for(area.time, Atmosphere.step_for(id))
	LevelStyle.set_night(p.night)
	# atmosphere.gd の apply_preset と同じ太陽の向き
	var elev := deg_to_rad(p.elevation as float)
	var az := deg_to_rad(p.azimuth as float)
	var to_sun := Vector3(sin(az) * cos(elev), sin(elev), -cos(az) * cos(elev))
	# 表示の単位：太陽 = 線形の色 × 強さ（Godot は強さに π を掛け、ランバートで π で割る）
	var sun := (p.sun as Color).srgb_to_linear() * (p.sun_energy as float)
	# 環境光：空 70% と環境光の色 30%（atmosphere.gd の ambient_light_sky_contribution）× 強さ
	var amb_col := (p.horizon as Color).lerp(Color(0.8, 0.8, 0.8), 0.5).srgb_to_linear()
	var amb := func(c: Color) -> Color:
		var l := c.srgb_to_linear()
		var m := l * 0.7 + amb_col * 0.3
		return m * (p.ambient as float)
	var tmp := OS.get_cache_dir().path_join("parkour_bake")
	DirAccess.make_dir_recursive_absolute(tmp)
	var in_path := tmp.path_join(id + ".in")
	var out_path := tmp.path_join(id + ".out")
	geo.write_bake_input(in_path, to_sun, sun, amb.call(p.top), amb.call(p.horizon), amb.call(p.ground), _samples)
	var lines: Array = []
	var code := OS.execute(baker, [in_path, out_path], lines, true)
	print("\n".join(lines).strip_edges())
	if code != 0:
		push_error("bake_lighting: %s failed (%d)" % [id, code])
		geo.free()
		return false
	var img := _read_output(out_path)
	if img == null:
		geo.free()
		return false
	var data := LightmapData.new()
	data.image = img
	data.fingerprint = geo.lightmap_hash
	data.sun_dir = to_sun
	var err := ResourceSaver.save(data, LevelLighting.path_for(id), ResourceSaver.FLAG_COMPRESS)
	print("  %s: %dx%d, %s" % [id, img.get_width(), img.get_height(), "saved" if err == OK else "save failed %d" % err])
	geo.free()
	return err == OK


## lightbaker の出力（"LMO1"、幅・高さ、RGBA float）→ RGBA8（RGB = sqrt(照り返し / 4)、A = 空の見え方）
func _read_output(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "LMO1":
		push_error("bake_lighting: bad output " + path)
		return null
	var w := f.get_32()
	var h := f.get_32()
	var floats := f.get_buffer(w * h * 16).to_float32_array()
	f.close()
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	for i: int in w * h:
		for k: int in 3:
			bytes[i * 4 + k] = clampi(roundi(sqrt(maxf(floats[i * 4 + k], 0.0) / 4.0) * 255.0), 0, 255)
		bytes[i * 4 + 3] = clampi(roundi(floats[i * 4 + 3] * 255.0), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
