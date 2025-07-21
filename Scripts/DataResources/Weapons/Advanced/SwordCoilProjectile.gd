# File: res://Scripts/Weapons/SwordCoilProjectile.gd
# FIX: Now accepts and stores a reference to the player node to pass as the attacker.

class_name SwordCoilProjectile
extends Area2D

signal spell_siphon_hit

@onready var pivot: Node2D = $Pivot
@onready var animation_player: AnimationPlayer = $Pivot/AnimationPlayer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _damage: int
var _speed: float
var _direction: Vector2
var _enemies_hit: Array[Node] = []
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _owner_player: PlayerCharacter # NEW: Variable to store the player reference

# -- State for Upgrades --
var _is_returning: bool = false
var _distance_traveled: float = 0.0
var _origin_point: Vector2

func _ready():
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	body_entered.connect(_on_body_entered)
	
func setup(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager, p_owner_player: PlayerCharacter):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_owner_player = p_owner_player # Store the player reference
	_direction = p_direction.normalized()
	_origin_point = global_position
	
	_speed = float(_specific_stats.get("projectile_speed", 300.0)) * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	
	var lifetime = float(_specific_stats.get("base_lifetime", 1.5)) * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = lifetime
	lifetime_timer.start()
	
	animation_player.play("rotate")
	_update_damage_and_scale()

func _physics_process(delta: float):
	var move_vector = _direction * _speed * delta
	global_position += move_vector
	_distance_traveled += move_vector.length()
	
	if _specific_stats.get("has_kinetic_resonance", false):
		_update_damage_and_scale()

func _update_damage_and_scale():
	var weapon_damage_percent = float(_specific_stats.get("weapon_damage_percentage", 1.2))
	var damage_bonus_from_levels = 0.0
	
	if is_instance_valid(_owner_player):
		if _specific_stats.get("has_arcane_battery", false):
			var wizard_levels = _owner_player.get_total_levels_for_class(PlayerCharacter.BasicClass.WIZARD)
			damage_bonus_from_levels += float(wizard_levels) * float(_specific_stats.get("arcane_battery_bonus_per_level", 0.05))
			
		if _specific_stats.get("has_blade_echo", false):
			var warrior_levels = _owner_player.get_total_levels_for_class(PlayerCharacter.BasicClass.WARRIOR)
			damage_bonus_from_levels += float(warrior_levels) * float(_specific_stats.get("blade_echo_bonus_per_level", 0.05))
	
	var final_damage_percent = weapon_damage_percent * (1.0 + damage_bonus_from_levels)
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_calculated_damage = _owner_player_stats.get_calculated_base_damage(final_damage_percent)

	var kinetic_bonus_mult = 1.0
	if _specific_stats.get("has_kinetic_resonance", false):
		var distance_increment = float(_specific_stats.get("kinetic_resonance_distance", 50.0))
		var bonus_per_increment = float(_specific_stats.get("kinetic_resonance_bonus", 0.10))
		var increments = floor(_distance_traveled / distance_increment)
		kinetic_bonus_mult += increments * bonus_per_increment

	_damage = int(round(base_calculated_damage * kinetic_bonus_mult))
	
	var weapon_size_mult = float(_specific_stats.get("projectile_size_multiplier", 1.0))
	var player_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	var blade_storm_scale_mult = float(_specific_stats.get("scale_multiplier", 1.0))
	var final_scale = weapon_size_mult * player_size_mult * kinetic_bonus_mult * blade_storm_scale_mult
	self.scale = Vector2.ONE * final_scale

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not _enemies_hit.has(body):
		var enemy = body as BaseEnemy
		if not enemy.is_dead():
			var weapon_tags: Array[StringName] = []
			if _specific_stats.has("tags"):
				weapon_tags = _specific_stats.get("tags")
			enemy.take_damage(_damage, _owner_player, {}, weapon_tags) # Pass tags
			_enemies_hit.append(enemy)
			
			if _specific_stats.get("has_spell_siphon", false):
				emit_signal("spell_siphon_hit")

func _on_lifetime_expired():
	if _specific_stats.get("has_phase_blade", false) and not _is_returning:
		_is_returning = true
		_direction *= -1.0 # Reverse direction
		self.rotation = _direction.angle() # FIX: Update rotation to match new direction
		_enemies_hit.clear() # Allow hitting enemies on the return trip
		lifetime_timer.start() # Restart the timer for the return journey
	else:
		queue_free()
