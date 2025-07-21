# File: EldritchOrbSplinter.gd
# Attach to: EldritchOrbSplinter.tscn
# --------------------------------------------------------------------
class_name EldritchOrbSplinter
extends Area2D

var _direction: Vector2
var _speed: float = 300.0
var _damage: int
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _parent_echo_instance_id: int

func _ready():
	get_tree().create_timer(1.0).timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats, p_parent_echo_id: int):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_parent_echo_instance_id = p_parent_echo_id
	
	var damage_percent = float(p_stats.get("eldritch_splinter_damage_percentage", 0.25))
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage
	
	var base_scale = float(p_stats.get("eldritch_splinter_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	rotation = _direction.angle()

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead():
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		body.take_damage(_damage, _owner_player_stats.get_parent(), {}, weapon_tags)
		
		CombatTracker.record_hit(StringName(str(_parent_echo_instance_id)), body)
		
		queue_free()
