# File: res://Scripts/Weapons/Advanced/Turrets/BaseTurret.gd
# Base class for all turrets, now includes directional animation and scaling logic.
# REVISED: Refactored to use virtual functions for all key stats, allowing subclasses to be fully data-driven.

class_name BaseTurret
extends CharacterBody2D

enum State { IDLE, FIRING }
var current_state = State.IDLE
var facing_direction = "south" # Default direction

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var targeting_range: Area2D = $TargetingRange
@onready var attack_cooldown_timer: Timer = $AttackCooldownTimer
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var fire_anim_timer: Timer = $FireAnimTimer
@onready var projectile_spawn_point: Marker2D = $ProjectileSpawnPoint

var specific_stats: Dictionary
var owner_player_stats: PlayerStats
var current_target: BaseEnemy
var is_shutting_down: bool = false

func _ready():
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout)
	fire_anim_timer.timeout.connect(_on_fire_anim_timer_timeout)
	
func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_stats
	owner_player_stats = p_player_stats
	
	if owner_player_stats and not owner_player_stats.is_connected("stats_recalculated", update_stats):
		owner_player_stats.stats_recalculated.connect(update_stats)

	# NEW: Apply one-time stats like scale and range here.
	# These are based on the blueprint data at the moment of spawning and should not change.
	targeting_range.get_node("CollisionShape2D").shape.radius = _get_base_targeting_range()
	animated_sprite.scale = Vector2.ONE * _get_base_visual_scale()

	# This will set the initial lifetime and attack cooldown.
	update_stats(p_stats)
	attack_cooldown_timer.start()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(owner_player_stats) and owner_player_stats.is_connected("stats_recalculated", update_stats):
			owner_player_stats.stats_recalculated.disconnect(update_stats)

func update_stats(p_arg1 = {}, _p_arg2 = 0.0):
	if p_arg1 is Dictionary and not p_arg1.is_empty():
		specific_stats = p_arg1.duplicate(true)
	if not is_instance_valid(owner_player_stats): return

	# --- STATS APPLICATION ---
	# Apply lifetime, which doesn't change after initial spawn.
	if lifetime_timer.is_stopped():
		var lifetime = _get_base_lifetime()
		var lifetime_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
		lifetime_timer.wait_time = lifetime * lifetime_mult
		lifetime_timer.start()

	# REMOVED: Scale and range logic moved to initialize()

	# Apply cooldown calculation, which needs to be updated when global stats change.
	var base_cooldown = _get_base_attack_cooldown()
	var final_cooldown = base_cooldown

	var turret_speed_mult = float(specific_stats.get("turret_attack_speed_mult", 1.0))
	if turret_speed_mult > 0.01:
		final_cooldown /= turret_speed_mult

	var global_speed_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	if global_speed_mult > 0.01:
		final_cooldown /= global_speed_mult
		
	var global_cooldown_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_COOLDOWN_REDUCTION_MULT)
	if global_cooldown_mult > 0.01:
		final_cooldown *= global_cooldown_mult
	
	attack_cooldown_timer.wait_time = max(0.05, final_cooldown)

# --- Physics & AI ---

func _physics_process(_delta):
	if is_shutting_down: return
	if not _is_target_valid(current_target):
		current_target = _find_target()
	if _is_target_valid(current_target) and current_state == State.IDLE:
		_update_facing_direction()
	_update_animation()

func _is_target_valid(target_node: Node) -> bool:
	return is_instance_valid(target_node) and not (target_node as BaseEnemy).is_dead()

func _update_facing_direction():
	if not _is_target_valid(current_target): return
	var direction_vector = (current_target.global_position - global_position).normalized()
	projectile_spawn_point.rotation = direction_vector.angle()
	if abs(direction_vector.x) > abs(direction_vector.y):
		facing_direction = "east" if direction_vector.x > 0 else "west"
	else:
		facing_direction = "south" if direction_vector.y > 0 else "north"

func _update_animation():
	var state_string = "idle"
	if current_state == State.FIRING: state_string = "fire"
	var animation_to_play = state_string + "_" + facing_direction
	if animated_sprite.animation != animation_to_play:
		animated_sprite.play(animation_to_play)

func _on_lifetime_expired():
	if is_shutting_down: return
	is_shutting_down = true
	_fire_final_shot()

func _on_attack_cooldown_timeout():
	if is_shutting_down: return
	if not _is_target_valid(current_target):
		current_target = _find_target()
	if _is_target_valid(current_target):
		var did_attack = _perform_attack()
		if not did_attack:
			_restart_attack_cooldown()
	else:
		_restart_attack_cooldown()

func _on_fire_anim_timer_timeout():
	if current_state == State.FIRING:
		current_state = State.IDLE
		_update_animation()

func _restart_attack_cooldown():
	attack_cooldown_timer.start()

# --- Virtual Methods for Subclasses to Override ---

func _get_base_lifetime() -> float:
	return 8.0 # Default

func _get_base_attack_cooldown() -> float:
	return 1.0 # Default

func _get_base_targeting_range() -> float:
	return 150.0 # Default

func _get_base_visual_scale() -> float:
	return 1.0 # Default

func _find_target() -> BaseEnemy:
	var closest_enemy: BaseEnemy = null
	var min_dist_sq = INF
	for body in targeting_range.get_overlapping_bodies():
		if body is BaseEnemy and _is_target_valid(body):
			var dist_sq = global_position.distance_squared_to(body.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				closest_enemy = body
	return closest_enemy

func _perform_attack() -> bool:
	if current_state == State.FIRING: return false
	current_state = State.FIRING
	_update_animation()
	fire_anim_timer.start()
	_restart_attack_cooldown()
	_spawn_projectile()
	return true

func _spawn_projectile():
	pass

func _fire_final_shot():
	current_target = _find_target()
	if _is_target_valid(current_target):
		_perform_attack()
	await get_tree().create_timer(0.2).timeout
	if specific_stats.get("turrets_explode_on_death", false):
		var explosion_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/ArtilleryProjectileExplosion.tscn")
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = self.global_position
		var explosion_damage_percent = specific_stats.get("turret_explosion_damage_percent", 0.5)
		var weapon_tags: Array[StringName] = specific_stats.get("tags", [])
		var base_damage = owner_player_stats.get_calculated_base_damage(explosion_damage_percent)
		var final_damage = owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		var explosion_damage = int(final_damage)
		var explosion_radius = float(specific_stats.get("turret_explosion_radius", 40.0))
		if explosion.has_method("initialize"):
			explosion.initialize(explosion_damage, explosion_radius, owner_player_stats.get_parent(), {}, specific_stats)
	queue_free()
