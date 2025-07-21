# Path: res://Scripts/Weapons/Advanced/Effect Scenes/ChemtrailSegment.gd
# FIX: Added .start() calls for the timers in the initialize function.
# =====================================================================
class_name ChemtrailSegment
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var damage_tick_timer: Timer = $DamageTickTimer

var _damage_per_tick: int
var _owner_player: PlayerCharacter
var _specific_stats: Dictionary

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	damage_tick_timer.timeout.connect(_on_damage_tick)
	animated_sprite.play("default")

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_stats
	_owner_player = p_player_stats.get_parent()
	var damage_percent = float(p_stats.get("chemtrail_damage_percent", 1.5))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = p_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage_per_tick = final_damage
	
	var tick_interval = float(p_stats.get("chemtrail_tick_interval", 1.0))
	damage_tick_timer.wait_time = tick_interval
	
	var duration = float(p_stats.get("chemtrail_segment_duration", 2.0))
	lifetime_timer.wait_time = duration
	
	var visual_scale = float(p_stats.get("chemtrail_segment_scale", 1.0))
	var aoe_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_scale = visual_scale * aoe_mult

	animated_sprite.scale = Vector2.ONE * final_scale
	collision_shape.scale = Vector2.ONE * final_scale
	
	animated_sprite.rotation_degrees = randf_range(0, 360)

	# FIX: Start the timers after they have been configured.
	lifetime_timer.start()
	damage_tick_timer.start()

func _on_damage_tick():
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body is BaseEnemy and not body.is_dead():
			var weapon_tags: Array[StringName] = []
			if _specific_stats.has("tags"):
				weapon_tags = _specific_stats.get("tags")
			body.take_damage(_damage_per_tick, _owner_player, {}, weapon_tags)
