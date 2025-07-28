# File: res://Scripts/Weapons/Advanced/Turrets/SentryTurret.gd
# This script defines the specific behavior for the Sentry Turret.
# It inherits from BaseTurret and provides its unique cooldown and projectile.
# REVISED: Now overrides all base stat functions to be fully data-driven from the blueprint.

class_name SentryTurret
extends BaseTurret

# --- Overridden Virtual Methods ---

func _get_base_attack_cooldown() -> float:
	# Read the unique cooldown for this turret from the stats dictionary.
	return float(specific_stats.get("sentry_attack_cooldown", 0.8))

func _get_base_lifetime() -> float:
	# Read the unique lifetime for this turret from the stats dictionary.
	return float(specific_stats.get("sentry_lifetime", 8.0))

func _get_base_targeting_range() -> float:
	# Read the unique targeting range for this turret from the stats dictionary.
	return float(specific_stats.get("sentry_targeting_range", 150.0))

func _get_base_visual_scale() -> float:
	# Read the unique visual scale for this turret from the stats dictionary.
	return float(specific_stats.get("sentry_visual_scale", 1.0))

func _spawn_projectile():
	# This function contains the logic that was previously in the base class.
	# It loads and initializes the specific projectile for the Sentry Turret.
	var projectile_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/SentryProjectile.tscn")
	if not is_instance_valid(projectile_scene):
		return

	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	
	projectile.global_position = projectile_spawn_point.global_position

	if projectile.has_method("initialize"):
		projectile.initialize(current_target, specific_stats, owner_player_stats)
