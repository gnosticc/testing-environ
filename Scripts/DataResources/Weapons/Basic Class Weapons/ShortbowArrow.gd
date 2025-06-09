# ShortbowArrow.gd
# Behavior for the Shortbow's arrow projectile.
# This script is designed to be a generic, reusable projectile controller.
class_name ShortbowArrow
extends Area2D

var final_damage_amount: int = 10
var final_speed: float = 160.0
var final_applied_scale: Vector2 = Vector2(1,1)
var direction: Vector2 = Vector2.RIGHT

var max_pierce_count: int = 0
var current_pierce_count: int = 0

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}
var _owner_player_stats: PlayerStats

func _ready():
	if not is_instance_valid(lifetime_timer):
		print("ERROR (ShortbowArrow): LifetimeTimer missing!"); call_deferred("queue_free"); return
	else:
		if not lifetime_timer.is_connected("timeout", Callable(self, "queue_free")):
			lifetime_timer.timeout.connect(self.queue_free)
	
	if _stats_have_been_set:
		_apply_all_stats_effects()

func _physics_process(delta: float):
	global_position += direction * final_speed * delta

# Standardized initialization function called by WeaponManager
func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats
	_stats_have_been_set = true
	
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	if is_inside_tree():
		_apply_all_stats_effects()

func _apply_all_stats_effects():
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats): return

	var player_base_damage = float(_owner_player_stats.get_current_base_numerical_damage())
	var player_global_mult = float(_owner_player_stats.get_current_global_damage_multiplier())
	var weapon_damage_percent = float(_received_stats.get("weapon_damage_percentage", 1.0))
	final_damage_amount = int(round(player_base_damage * weapon_damage_percent * player_global_mult))
	
	var base_w_speed = _received_stats.get("projectile_speed", 300.0)
	var p_proj_spd_mult = _owner_player_stats.get_current_projectile_speed_multiplier()
	final_speed = base_w_speed * p_proj_spd_mult
	
	max_pierce_count = _received_stats.get("pierce_count", 0)
	
	var base_scale_x = float(_received_stats.get("inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_received_stats.get("inherent_visual_scale_y", 1.0))
	var p_proj_size_mult = _owner_player_stats.get_current_projectile_size_multiplier()
	final_applied_scale.x = base_scale_x * p_proj_size_mult
	final_applied_scale.y = base_scale_y * p_proj_size_mult
	
	_apply_visual_scale()
	
	var base_lifetime = float(_received_stats.get("base_lifetime", 2.0))
	var duration_mult = _owner_player_stats.get_current_effect_duration_multiplier()
	lifetime_timer.wait_time = base_lifetime * duration_mult
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped():
		lifetime_timer.start()

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale

func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		var owner_player = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		body.take_damage(final_damage_amount, owner_player)
		current_pierce_count += 1
		if current_pierce_count > max_pierce_count:
			call_deferred("queue_free")
	elif body.is_in_group("world_obstacles"):
		call_deferred("queue_free")
