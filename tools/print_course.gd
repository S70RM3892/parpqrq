extends SceneTree
## コースのレシピ（型を展開した結果）と自動走行の道しるべ・隠れた近道を表示する（コースを直す時の確認用）。
##   godot --headless --path . -s tools/print_course.gd -- 2-3


func _init() -> void:
	var id := "1-1"
	for a: String in OS.get_cmdline_user_args():
		id = a
	var r := CourseCatalog.recipe(id)
	print("\n".join(r))
	var geo := LevelGeometry.new()
	var b := CourseBuilder.new(geo, CourseCatalog.area_of(id), int(CourseCatalog.get_course(id).get("seed", 1)))
	b.build(r)
	for i: int in b.nodes.size():
		var n: Dictionary = b.nodes[i]
		print("%3d %s act %d  %.1f m" % [i, str(n.p), n.act, n.dist])
	print("route %.0f m, %d primitives" % [b.route_len, geo.primitive_count])
	# 隠れた近道：主ルートの道しるべ from で分かれ、to で戻る
	for sc: Dictionary in b.shortcuts:
		print("shortcut %-14s from %3d to %3d" % [sc.name, sc.from, sc.to])
		for n: Dictionary in sc.nodes:
			print("      %s act %d" % [str(n.p), n.act])
	geo.free()
	quit()
