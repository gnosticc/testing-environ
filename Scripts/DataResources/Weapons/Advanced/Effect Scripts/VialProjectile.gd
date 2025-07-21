# Path: res://Scripts/Weapons/Advanced/Effect Scripts/VialProjectile.gd
# FIX: Correctly and safely initialize weapon_tags to prevent type mismatch errors.
# =====================================================================
class_name VialProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats

const PUDDLE_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/ReagentPuddle.tscn")

func initialize(direction: Vector2, is_random_offset: bool, p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	
	var lob_distance = float(p_stats.get("vial_lob_distance", 40.0))
	var lob_height = float(p_stats.get("vial_lob_height", 25.0))
	var projectile_scale = float(p_stats.get("vial_projectile_scale", 1.0))
	
	animated_sprite.scale = Vector2.ONE * projectile_scale
	
	var target_position: Vector2
	if is_random_offset:
		var offset = Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
		target_position = global_position + offset
	else:
		target_position = global_position + direction * lob_distance

	var travel_duration = 0.4

	var main_tween = create_tween().set_parallel()
	var pos_tweener = main_tween.tween_property(self, "global_position", target_position, travel_duration)
	pos_tweener.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	var rot_tweener = main_tween.tween_property(animated_sprite, "rotation_degrees", 720, travel_duration)
	rot_tweener.set_trans(Tween.TRANS_LINEAR)
	
	var arc_tween = create_tween()
	var arc_up_tweener = arc_tween.tween_property(animated_sprite, "offset:y", -lob_height, travel_duration / 2.0)
	arc_up_tweener.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	var arc_down_tweener = arc_tween.tween_property(animated_sprite, "offset:y", 0, travel_duration / 2.0)
	arc_down_tweener.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	main_tween.finished.connect(_on_landed)

func _on_landed():
	if not is_instance_valid(self): return
	
	if _specific_stats.get("deals_impact_damage", false):
		_deal_impact_damage()

	if is_instance_valid(PUDDLE_SCENE):
		var puddle = PUDDLE_SCENE.instantiate()
		get_tree().current_scene.add_child(puddle)
		puddle.global_position = self.global_position
		if puddle.has_method("initialize"):
			puddle.initialize(_specific_stats, _owner_player_stats)
	
	queue_free()

func _deal_impact_damage():
	var base_radius = float(_specific_stats.get("puddle_radius", 35.0)) * 0.5
	var aoe_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_radius = base_radius * aoe_mult

	var damage_percent = float(_specific_stats.get("impact_damage_percent", 0.5))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")

	# Step 1: Get the base damage.
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	# Step 2: Apply tag-specific multipliers to get the final damage.
	var damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new(); query.shape.radius = final_radius
	query.transform = global_transform
	query.collision_mask = 8
		
	var results = space_state.intersect_shape(query)
	for result in results:
		if result.collider is BaseEnemy:
			result.collider.take_damage(damage, _owner_player_stats.get_parent(), {}, weapon_tags)
