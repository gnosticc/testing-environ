# File: res://Scripts/Weapons/Advanced/Turrets/HunterKillerBot.gd
class_name HunterKillerBot
extends BaseTurret

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	super.initialize(p_stats, p_player_stats)
	
	var visual_scale = float(specific_stats.get("hk_visual_scale", 0.85))
	animated_sprite.scale = Vector2.ONE * visual_scale
	
	var radius = float(specific_stats.get("hk_targeting_range", 400.0))
	var shape = targeting_range.get_node("CollisionShape2D") as CollisionShape2D
	if shape and shape.shape is CircleShape2D:
		shape.shape.radius = radius

func _get_base_lifetime() -> float:
	return float(specific_stats.get("hk_lifetime", 6.0))

func _get_base_attack_cooldown() -> float:
	return float(specific_stats.get("hk_attack_cooldown", 2.0))

# Override the find target method for highest max HP targeting
func _find_target() -> BaseEnemy:
	var best_target: BaseEnemy = null
	var highest_max_hp = -1.0
	
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	for enemy_node in all_enemies:
		if _is_target_valid(enemy_node):
			var enemy = enemy_node as BaseEnemy
			if enemy.max_health > highest_max_hp:
				highest_max_hp = enemy.max_health
				best_target = enemy
				
	return best_target

# Override the attack method to fire the HK projectile
func _perform_attack():
	if current_state == State.FIRING: return
	current_state = State.FIRING
	_update_animation()
	fire_anim_timer.start()
	_restart_attack_cooldown()

	var projectile_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/HunterKillerProjectile.tscn")
	if not is_instance_valid(projectile_scene): return

	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	
	projectile.global_position = projectile_spawn_point.global_position

	if projectile.has_method("initialize"):
		projectile.initialize(current_target, specific_stats, owner_player_stats)
