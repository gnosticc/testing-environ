# File: res://Scripts/Weapons/Advanced/Turrets/ArtilleryBot.gd
class_name ArtilleryBot
extends BaseTurret

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	super.initialize(p_stats, p_player_stats)
	
	var visual_scale = float(specific_stats.get("artillery_visual_scale", 0.9))
	animated_sprite.scale = Vector2.ONE * visual_scale
	
	var radius = float(specific_stats.get("artillery_targeting_range", 350.0))
	var shape = targeting_range.get_node("CollisionShape2D") as CollisionShape2D
	if shape and shape.shape is CircleShape2D:
		shape.shape.radius = radius

func _get_base_lifetime() -> float:
	return float(specific_stats.get("artillery_lifetime", 10.0))

func _get_base_attack_cooldown() -> float:
	return float(specific_stats.get("artillery_attack_cooldown", 2.5))

# Override the find target method for cluster targeting
func _find_target() -> BaseEnemy:
	var best_target: BaseEnemy = null
	var max_enemies_in_radius = -1
	var cluster_radius = float(specific_stats.get("artillery_cluster_radius", 75.0))
	
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	if all_enemies.size() < 2:
		return super._find_target()

	for _i in range(min(10, all_enemies.size())):
		var candidate = all_enemies.pick_random()
		if not _is_target_valid(candidate): continue
		
		var enemies_in_radius = 0
		for other_enemy in all_enemies:
			if candidate.global_position.distance_squared_to(other_enemy.global_position) < cluster_radius * cluster_radius:
				enemies_in_radius += 1
		
		if enemies_in_radius > max_enemies_in_radius:
			max_enemies_in_radius = enemies_in_radius
			best_target = candidate
			
	return best_target

# Override the attack method to fire the artillery projectile
func _perform_attack():
	if current_state == State.FIRING: return
	current_state = State.FIRING
	_update_animation()
	fire_anim_timer.start()
	_restart_attack_cooldown()

	var projectile_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/ArtilleryProjectile.tscn")
	if not is_instance_valid(projectile_scene): return

	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = projectile_spawn_point.global_position
	
	if projectile.has_method("initialize"):
		projectile.initialize(current_target, specific_stats, owner_player_stats)
