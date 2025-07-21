# File: res://Scripts/Weapons/Advanced/Turrets/BaseTurret.gd
# Base class for all turrets, now includes directional animation and scaling logic.
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
	
	# Apply stats common to all turrets
	var lifetime = _get_base_lifetime()
	var lifetime_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = lifetime * lifetime_mult
	lifetime_timer.start()

	# Start the first attack cooldown
	_restart_attack_cooldown()

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
	if not _is_target_valid(current_target):
		return

	var direction_vector = (current_target.global_position - global_position).normalized()
	
	# Set the rotation of the spawn point to the exact angle
	projectile_spawn_point.rotation = direction_vector.angle()
	
	# Determine the cardinal direction for the animation
	if abs(direction_vector.x) > abs(direction_vector.y):
		facing_direction = "east" if direction_vector.x > 0 else "west"
	else:
		facing_direction = "south" if direction_vector.y > 0 else "north"

func _update_animation():
	var state_string = "idle"
	if current_state == State.FIRING:
		state_string = "fire"
	
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
		_perform_attack()
	else:
		attack_cooldown_timer.start() # Try again soon if no target

func _on_fire_anim_timer_timeout():
	if current_state == State.FIRING:
		current_state = State.IDLE
		_update_animation()

func _restart_attack_cooldown():
	var base_cooldown = _get_base_attack_cooldown()
	var attack_speed_mult = float(specific_stats.get("turret_attack_speed_mult", 1.0))
	var global_attack_speed_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	
	var final_cooldown = base_cooldown / (attack_speed_mult * global_attack_speed_mult)
	attack_cooldown_timer.wait_time = max(0.1, final_cooldown)
	attack_cooldown_timer.start()

# --- Virtual Methods for Subclasses to Override ---

func _get_base_lifetime() -> float:
	return 8.0 # Fallback

func _get_base_attack_cooldown() -> float:
	return 1.0 # Fallback

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

func _perform_attack():
	if current_state == State.FIRING: return
	current_state = State.FIRING
	_update_animation()
	fire_anim_timer.start()
	_restart_attack_cooldown()
	
	var projectile_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/SentryProjectile.tscn")
	if not is_instance_valid(projectile_scene): return

	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	
	projectile.global_position = projectile_spawn_point.global_position

	if projectile.has_method("initialize"):
		projectile.initialize(current_target, specific_stats, owner_player_stats)

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
		
		# --- REFACTORED DAMAGE CALCULATION ---
		var explosion_damage_percent = specific_stats.get("turret_explosion_damage_percent", 0.5)
		var weapon_tags: Array[StringName] = specific_stats.get("tags", [])
		var base_damage = owner_player_stats.get_calculated_base_damage(explosion_damage_percent)
		var final_damage = owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		var explosion_damage = int(final_damage)
		# --- END REFACTOR ---

		var explosion_radius = float(specific_stats.get("turret_explosion_radius", 40.0))
		
		if explosion.has_method("initialize"):
			explosion.initialize(explosion_damage, explosion_radius, owner_player_stats.get_parent(), {}, specific_stats)
			
	queue_free()
