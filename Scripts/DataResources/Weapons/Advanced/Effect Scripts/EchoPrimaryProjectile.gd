# File: EchoPrimaryProjectile.gd
# Attach to: EchoPrimaryProjectile.tscn
# REVISED: Deferred the spawning of the Volatile Essence explosion.
# --------------------------------------------------------------------
class_name EchoPrimaryProjectile
extends Area2D

@onready var lifetime_timer: Timer = $LifetimeTimer

const VOLATILE_ESSENCE_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/VolatileEssenceExplosion.tscn")

var _direction: Vector2
var _speed: float = 500.0
var _damage: int
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _parent_echo_instance_id: int

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats, p_parent_echo_id: int):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_parent_echo_instance_id = p_parent_echo_id
	
	var damage_percent = float(p_stats.get("primary_attack_damage_percentage", 0.8))
	var weapon_tags: Array[StringName] = p_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage
	
	var base_scale = float(p_stats.get("primary_projectile_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	rotation = _direction.angle()
	lifetime_timer.start()

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead():
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		body.take_damage(_damage, _owner_player_stats.get_parent(), {}, weapon_tags)
		
		CombatTracker.record_hit(StringName(str(_parent_echo_instance_id)), body)
		
		if _specific_stats.get("has_soul_sustenance", false):
			var weapon_manager = _owner_player_stats.get_parent().weapon_manager
			var reduction = float(_specific_stats.get("soul_sustenance_cooldown_reduction", 0.05))
			if is_instance_valid(weapon_manager):
				weapon_manager.reduce_cooldown_for_weapon(&"summoner_return_from_beyond", reduction)
		
		if _specific_stats.get("has_volatile_essence", false):
			if randf() < float(_specific_stats.get("volatile_essence_chance", 0.25)):
				var explosion_damage = int(_damage * 0.5)
				var owner = _owner_player_stats.get_parent()
				call_deferred("_spawn_volatile_explosion", global_position, explosion_damage, owner, _specific_stats)

		queue_free()

func _spawn_volatile_explosion(p_position: Vector2, p_damage: int, p_owner: Node, p_stats: Dictionary):
	var explosion = VOLATILE_ESSENCE_SCENE.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = p_position
	explosion.initialize(p_damage, p_owner, p_stats)
