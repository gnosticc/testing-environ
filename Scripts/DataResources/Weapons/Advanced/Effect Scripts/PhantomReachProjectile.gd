# File: PhantomReachProjectile.gd
# Attach to: PhantomReachProjectile.tscn
# --------------------------------------------------------------------
class_name PhantomReachProjectile
extends Area2D

@onready var homing_component: Node = $HomingComponent
@onready var lifetime_timer: Timer = $LifetimeTimer

var _damage: int
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _parent_echo_instance_id: int
var _speed: float = 350.0 # Homing projectiles need a speed property for the component

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_target: BaseEnemy, p_stats: Dictionary, p_player_stats: PlayerStats, p_parent_echo_id: int):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_parent_echo_instance_id = p_parent_echo_id
	
	var damage_percent = float(p_stats.get("phantom_reach_damage_percentage", 0.3))
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage
		
	var base_scale = float(p_stats.get("phantom_reach_projectile_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	if is_instance_valid(homing_component) and homing_component.has_method("activate"):
		homing_component.activate(p_target)
		
	lifetime_timer.start()

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead():
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		body.take_damage(_damage, _owner_player_stats.get_parent(), {}, weapon_tags)
		
		CombatTracker.record_hit(StringName(str(_parent_echo_instance_id)), body)
		
		queue_free()
