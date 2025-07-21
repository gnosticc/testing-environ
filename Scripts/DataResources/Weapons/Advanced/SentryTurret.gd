# File: res://Scripts/Weapons/Advanced/Turrets/SentryTurret.gd
class_name SentryTurret
extends BaseTurret

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	super.initialize(p_stats, p_player_stats)
	
	var visual_scale = float(specific_stats.get("sentry_visual_scale", 0.8))
	animated_sprite.scale = Vector2.ONE * visual_scale
	
	var radius = float(specific_stats.get("sentry_targeting_range", 250.0))
	var shape = targeting_range.get_node("CollisionShape2D") as CollisionShape2D
	if shape and shape.shape is CircleShape2D:
		shape.shape.radius = radius

func _get_base_lifetime() -> float:
	return float(specific_stats.get("sentry_lifetime", 8.0))

func _get_base_attack_cooldown() -> float:
	return float(specific_stats.get("sentry_attack_cooldown", 0.5))
