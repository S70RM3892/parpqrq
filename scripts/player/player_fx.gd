class_name PlayerFX
extends Node3D
## プレイヤーの足元の粒（着地・ローリングの土煙、スライドの擦れ、ウォールランの靴底の擦れ）。Player のシグナルで出す。
## 床の素材で色を変える（コンクリ = 白い粉、砂利 = 茶色い土、金属 = 火花、ガラス = ほとんど出ない）。
## 粒は CPUParticles3D（数が少なく、シェーダーの組み立てで引っかからない）。1人称なので下を見た時と視界の下の端に見える。

const DUST_COLORS: Dictionary[StringName, Color] = {
	&"concrete": Color(0.86, 0.85, 0.82, 0.35), &"gravel": Color(0.66, 0.58, 0.48, 0.45),
	&"metal": Color(0.7, 0.7, 0.72, 0.2), &"glass": Color(0.9, 0.94, 1.0, 0.1),
}

@export var player: Player

var _land: CPUParticles3D
var _slide: CPUParticles3D
var _sparks: CPUParticles3D
var _wall: CPUParticles3D
static var _dust_tex: Texture2D


func _ready() -> void:
	top_level = true
	_land = _particles(28, 0.9, true)
	_land.direction = Vector3.UP
	_land.spread = 80.0
	_land.initial_velocity_min = 1.2
	_land.initial_velocity_max = 3.2
	_land.gravity = Vector3(0, -1.5, 0)
	_land.damping_min = 2.5
	_land.damping_max = 4.0
	_land.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_land.emission_ring_axis = Vector3.UP
	_land.emission_ring_radius = 0.35
	_land.emission_ring_inner_radius = 0.1
	_land.emission_ring_height = 0.05
	_slide = _particles(48, 0.7, false)
	_slide.direction = Vector3(0, 0.6, 1)
	_slide.spread = 35.0
	_slide.initial_velocity_min = 0.8
	_slide.initial_velocity_max = 2.0
	_slide.gravity = Vector3(0, -0.8, 0)
	_slide.damping_min = 1.5
	_slide.damping_max = 3.0
	_sparks = _particles(40, 0.35, false, true)
	_sparks.direction = Vector3(0, 0.5, 1)
	_sparks.spread = 30.0
	_sparks.initial_velocity_min = 3.0
	_sparks.initial_velocity_max = 6.0
	_sparks.gravity = Vector3(0, -9.0, 0)
	_sparks.scale_amount_min = 0.25
	_sparks.scale_amount_max = 0.45
	_wall = _particles(24, 0.5, false)
	_wall.direction = Vector3.UP
	_wall.spread = 50.0
	_wall.initial_velocity_min = 0.4
	_wall.initial_velocity_max = 1.2
	_wall.gravity = Vector3(0, -2.0, 0)
	player.landed.connect(func(_impact: float, drop: float) -> void:
		if drop > 0.6:
			_burst(clampf(drop / 4.0, 0.35, 1.0)))
	player.rolled.connect(func(drop: float) -> void: _burst(clampf(drop / 3.0, 0.5, 1.0)))
	player.hard_landed.connect(func(_drop: float) -> void: _burst(1.2))


func _particles(amount: int, life: float, one_shot: bool, spark: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.emitting = false
	p.explosiveness = 0.95 if one_shot else 0.0
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2) if not spark else Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	# 土煙は光を受ける（夜は暗く、街灯の下だけ明るい）。火花は自分で光る
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if spark else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.albedo_texture = _soft_dot()
	if spark:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = m
	p.mesh = quad
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6 if not spark else 0.3))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	if spark:
		p.color = Color(1.0, 0.62, 0.22, 1.0)
	add_child(p)
	return p


static func _soft_dot() -> Texture2D:
	if _dust_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dust_tex = t
	return _dust_tex


func _surface_color() -> Color:
	return DUST_COLORS.get(player.floor_surface, DUST_COLORS[&"concrete"])


## 着地の土煙（strength 0〜1.2）
func _burst(strength: float) -> void:
	var c := _surface_color()
	c.a *= clampf(strength, 0.3, 1.0)
	_land.color = c
	_land.initial_velocity_max = 1.6 + 2.6 * strength
	_land.global_position = player.get_global_transform_interpolated().origin + Vector3.UP * 0.05
	_land.restart()


func _process(_delta: float) -> void:
	if player == null:
		return
	var feet := player.get_global_transform_interpolated().origin
	var vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var back := -vel.normalized() if vel.length() > 0.5 else Vector3.BACK
	var sliding := player.state == Player.State.SLIDE
	var metal := player.floor_surface == &"metal"
	var ahead := vel.normalized() * 0.55 if vel.length() > 0.5 else Vector3.ZERO
	_slide.emitting = sliding and player.floor_surface != &"glass"
	_sparks.emitting = sliding and metal
	if sliding:
		_slide.color = _surface_color()
		_slide.global_position = feet + ahead + Vector3.UP * 0.05
		_slide.direction = (back + Vector3.UP * 0.6).normalized()
		_sparks.global_position = feet + ahead + Vector3.UP * 0.03
		_sparks.direction = (back + Vector3.UP * 0.5).normalized()
	var walling := player.state in [Player.State.WALL_RUN, Player.State.WALL_CLIMB] and player.wall_normal != Vector3.ZERO
	_wall.emitting = walling
	if walling:
		_wall.color = DUST_COLORS[&"concrete"]
		_wall.global_position = feet - player.wall_normal * 0.33 + Vector3.UP * 0.25
