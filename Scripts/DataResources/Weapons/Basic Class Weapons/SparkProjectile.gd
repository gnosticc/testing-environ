# File: res://Scripts/DataResources/Weapons/Basic Class Weapons/SparkProjectile.gd
# Purpose: UPDATED version of the projectile script.
# FIX: The call to spawn the explosion is now deferred, which is the definitive
# fix for the "Can't change this state while flushing queries" error.

class_name SparkProjectile
extends CharacterBody2D

const EXPLOSION_SCENE = preload("res://Scenes/Weapons/Projectiles/SparkExplosion.tscn")

var final_base_damage: int = 0
var final_speed: float = 0.0
var final_applied_scale: Vector2 = Vector2(1,1)
var direction: Vector2 = Vector2.RIGHT

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var damage_area: Area2D = $DamageArea

var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}
var _owner_player_stats: PlayerStats
var _is_destroying: bool = false # Flag to prevent multiple destructions

func _ready():
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	damage_area.body_entered.connect(_handle_hit)
	if _stats_have_been_set:
		_apply_all_stats_effects()

func _physics_process(delta: float):
	if _is_destroying: return
	velocity = direction * final_speed
	move_and_slide()

func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats
	_stats_have_been_set = true
	if is_inside_tree():
		_apply_all_stats_effects()

func _apply_all_stats_effects():
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats): return

	var weapon_damage_percent = float(_received_stats.get(&"weapon_damage_percentage", 1.8))
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", [])
	final_base_damage = int(round(maxf(1.0, _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags))))
	
	var base_speed = float(_received_stats.get(&"projectile_speed", 200.0))
	var player_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	final_speed = base_speed * player_speed_mult
	
	var base_scale_x = float(_received_stats.get(&"inherent_visual_scale_x", 0.4))
	var base_scale_y = float(_received_stats.get(&"inherent_visual_scale_y", 0.4))
	var weapon_size_mult = float(_received_stats.get(&"projectile_size_multiplier", 1.0))
	var player_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	final_applied_scale = Vector2(base_scale_x * weapon_size_mult * player_size_mult, base_scale_y * weapon_size_mult * player_size_mult)
	
	_apply_visual_scale()
	
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 1.5))
	var duration_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = base_lifetime * duration_mult
	lifetime_timer.start()

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale

func _handle_hit(body: Node2D):
	if _is_destroying: return

	var damage_dealt_this_hit = 0

	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return

		var damage_to_deal = float(final_base_damage)
		var total_crit_chance = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE)
		if randf() < total_crit_chance:
			damage_to_deal *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
		
		damage_dealt_this_hit = int(round(damage_to_deal))
		
		var owner_player_char = _owner_player_stats.get_parent()
		var attack_stats_for_enemy = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		enemy_target.take_damage(damage_dealt_this_hit, owner_player_char, attack_stats_for_enemy)
		
		_start_destruction(damage_dealt_this_hit)

	elif body.is_in_group("world_obstacles"):
		damage_dealt_this_hit = final_base_damage
		_start_destruction(damage_dealt_this_hit)

func _on_lifetime_expired():
	_start_destruction(final_base_damage)

func _start_destruction(p_damage_from_hit: int):
	if _is_destroying: return
	_is_destroying = true
	
	# Stop all processing and disable collision immediately.
	set_process(false)
	set_physics_process(false)
	
	# FIX: Use set_deferred for physics properties to avoid "flushing queries" errors.
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(damage_area):
		damage_area.set_deferred("monitoring", false)
		
	# --- FIX: Defer the entire explosion spawning logic ---
	# This schedules the function to run after the physics step is over,
	# preventing the "flushing queries" crash.
	call_deferred("_try_spawn_explosion", p_damage_from_hit)

	# Hide the projectile while it waits to be freed.
	visible = false
	
	# Use a timer to safely remove the node from the scene tree.
	get_tree().create_timer(0.1, true, false, true).timeout.connect(queue_free)

func _try_spawn_explosion(p_proccing_hit_damage: int):
	if not _received_stats.get(&"has_explosion", false):
		return

	var chance = float(_received_stats.get(&"explosion_chance", 0.0))
	if randf() < chance:
		var can_echo = _received_stats.get(&"explosion_echoes", false)
		var explosion_damage = int(round(p_proccing_hit_damage * 0.5))
		
		var base_radius = float(_received_stats.get(&"explosion_radius", 50.0))
		var aoe_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
		var final_radius = base_radius * aoe_multiplier
		
		var explosion = EXPLOSION_SCENE.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = self.global_position
		
		if explosion.has_method("detonate"):
			# Since this whole function is now deferred, we can call detonate directly.
			explosion.detonate(explosion_damage, final_radius, _owner_player_stats.get_parent(), {}, can_echo)
