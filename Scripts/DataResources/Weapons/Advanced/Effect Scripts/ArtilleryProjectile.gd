# File: res://Scripts/Weapons/Advanced/Turrets/ArtilleryProjectile.gd
class_name ArtilleryProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var target_position: Vector2
var damage: int
var explosion_radius: float
var owner_player: PlayerCharacter
var _specific_stats: Dictionary


func initialize(p_target: BaseEnemy, p_stats: Dictionary, p_player_stats: PlayerStats):
	target_position = p_target.global_position
	owner_player = p_player_stats.get_parent()
	
	var base_scale = float(p_stats.get("artillery_projectile_scale", 1.0))
	self.scale = Vector2.ONE * base_scale
	
	var damage_percent = float(p_stats.get("artillery_damage_percent", 2.5)) * float(p_stats.get("turret_damage_mult", 1.0))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	damage = int(final_damage)
	
	explosion_radius = float(p_stats.get("artillery_explosion_base_radius", 60.0)) * p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_position, 1.2)
	tween.tween_property(self, "scale", self.scale * 0.5, 1.2)
	tween.tween_callback(_explode)

func _explode():
	var explosion_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/ArtilleryProjectileExplosion.tscn")
	var explosion = explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = self.global_position
	
	if explosion.has_method("initialize"):
		explosion.initialize(damage, explosion_radius, owner_player, {}, _specific_stats)
	
	queue_free()
