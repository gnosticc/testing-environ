# --- Path: res://Scripts/Weapons/Advanced/Effects/LightningBolt.gd ---
class_name LightningBolt
extends AnimatedSprite2D

var _specific_stats: Dictionary
func _ready():
	animation_finished.connect(queue_free)

func strike(target: BaseEnemy, p_stats: Dictionary, p_player_stats: PlayerStats):
	global_position = target.global_position
	
	# FIX: Offset the sprite so its bottom edge is slightly below the target's center.
	if sprite_frames:
		var frame_texture = sprite_frames.get_frame_texture("strike", 0)
		if is_instance_valid(frame_texture):
			offset.y = (-frame_texture.get_height() / 2.0) + 20.0
			
	play("strike")
	
	var damage_percent = float(p_stats.get(&"initial_bolt_damage_percentage", 3.0))
	var weapon_tags: Array[StringName] = []
	if p_stats.has("tags"):
		weapon_tags = p_stats.get("tags")

	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)

	target.take_damage(damage, p_player_stats.get_parent(), {}, weapon_tags)
	
	var conduit_status = load("res://DataResources/StatusEffects/living_conduit_status.tres") as StatusEffectData
	if is_instance_valid(conduit_status) and is_instance_valid(target.status_effect_component):
		target.status_effect_component.apply_effect(conduit_status, p_player_stats.get_parent(), p_stats)
