# Path: res://Scripts/Weapons/Advanced/Effect Scenes/ReagentPuddle.gd
# =====================================================================
class_name ReagentPuddle
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
const SOAKED_STATUS_DATA = preload("res://DataResources/StatusEffects/Alchemist/soaked_status.tres")

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)
	animated_sprite.play("default")

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats

	var base_radius = float(p_stats.get("puddle_radius", 35.0))
	var aoe_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_radius = base_radius * aoe_mult

	var visual_scale_multiplier = float(p_stats.get("puddle_visual_scale", 1.0))
	
	if collision_shape.shape is CapsuleShape2D:
		(collision_shape.shape as CapsuleShape2D).radius = final_radius / 2.0
		(collision_shape.shape as CapsuleShape2D).height = final_radius
	elif collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = final_radius
	
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("default", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_size()
		if texture_size.x > 0:
			var desired_diameter = final_radius * 2.0
			var scale_factor = desired_diameter / texture_size.x
			animated_sprite.scale = Vector2.ONE * scale_factor * visual_scale_multiplier

	var duration = float(p_stats.get("puddle_duration", 5.0))
	lifetime_timer.wait_time = duration
	lifetime_timer.start()


func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body.status_effect_component):
		if not body.status_effect_component.has_status_effect(&"soaked"):
			body.status_effect_component.apply_effect(SOAKED_STATUS_DATA, _owner_player_stats.get_parent())
