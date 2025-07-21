# File: res://Scripts/Weapons/Advanced/Turrets/AegisProtector.gd
# REVISED: This script now correctly inherits from BaseTurret and fires correctly.
class_name AegisProtector
extends BaseTurret

const AEGIS_PROJECTILE_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/AegisProjectile.tscn")

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	super.initialize(p_stats, p_player_stats)
	
	var visual_scale = float(specific_stats.get("aegis_visual_scale", 0.75))
	animated_sprite.scale = Vector2.ONE * visual_scale
	
	var radius = float(specific_stats.get("aegis_targeting_range", 100.0))
	var shape = targeting_range.get_node("CollisionShape2D") as CollisionShape2D
	if shape and shape.shape is CircleShape2D:
		shape.shape.radius = radius

func _get_base_lifetime() -> float:
	return float(specific_stats.get("aegis_lifetime", 4.0))

func _get_base_attack_cooldown() -> float:
	return float(specific_stats.get("aegis_attack_cooldown", 1.5))

# --- Override Parent Behavior ---

# This turret does not have a single target, so this function does nothing.
func _find_target() -> BaseEnemy:
	# Instead of a single target, we just need to know if any target exists.
	var bodies = targeting_range.get_overlapping_bodies()
	for body in bodies:
		if body is BaseEnemy and _is_target_valid(body):
			return body # Return the first valid enemy found
	return null

# This turret does not have directional animations, so this function does nothing.
func _update_facing_direction():
	pass

# This turret has simple 'idle' and 'fire' animations.
func _update_animation():
	var anim_to_play = "idle"
	if current_state == State.FIRING:
		anim_to_play = "fire"
	
	if animated_sprite.animation != anim_to_play:
		animated_sprite.play(anim_to_play)

# Override the attack method for the multi-shot volley.
func _perform_attack():
	if current_state == State.FIRING: return
	
	var targets = targeting_range.get_overlapping_bodies()
	if targets.is_empty():
		# This case is now handled by the parent's _on_attack_cooldown_timeout
		return
	
	current_state = State.FIRING
	_update_animation() # Play the 'fire' animation
	fire_anim_timer.start()
	_restart_attack_cooldown()
	
	for body in targets:
		if body is BaseEnemy and _is_target_valid(body):
			_spawn_projectile_at(body)

func _spawn_projectile_at(target_enemy: BaseEnemy):
	if not is_instance_valid(AEGIS_PROJECTILE_SCENE): return

	var projectile = AEGIS_PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(projectile)
	
	# Projectiles spawn from the turret's center (its spawn point)
	projectile.global_position = projectile_spawn_point.global_position
	
	# Each projectile gets its own unique direction
	var direction = (target_enemy.global_position - global_position).normalized()
	
	if projectile.has_method("initialize"):
		projectile.initialize(direction, specific_stats, owner_player_stats)
