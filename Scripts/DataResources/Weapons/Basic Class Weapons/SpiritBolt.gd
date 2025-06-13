# SpiritBolt.gd
# A simple projectile fired by summoned spirits. This script handles its own
# movement, collision, and damage application.
# CORRECTED: Scale calculation now ignores inherited scale to prevent the projectile from being too small.

class_name SpiritBolt
extends CharacterBody2D

# --- Internal State ---
var final_damage_amount: int
var final_speed: float
var final_applied_scale: Vector2
var direction: Vector2 = Vector2.RIGHT

var max_pierce_count: int = 0
var current_pierce_count: int = 0

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var damage_area: Area2D = $DamageArea

var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}
var _owner_player_stats: PlayerStats

func _ready():
	if not is_instance_valid(animated_sprite):
		push_error("SpiritBolt ERROR: AnimatedSprite2D node not found at path '$AnimatedSprite2D'. Scene will be destroyed."); queue_free(); return
	if not is_instance_valid(lifetime_timer):
		push_error("SpiritBolt ERROR: LifetimeTimer node not found at path '$LifetimeTimer'. Scene will be destroyed."); queue_free(); return
	if not is_instance_valid(collision_shape):
		push_error("SpiritBolt ERROR: CollisionShape2D node not found at path '$CollisionShape2D'. Scene will be destroyed."); queue_free(); return
	if not is_instance_valid(damage_area):
		push_error("SpiritBolt ERROR: DamageArea node not found at path '$DamageArea'. Scene will be destroyed."); queue_free(); return
		
	lifetime_timer.timeout.connect(queue_free)
	damage_area.body_entered.connect(_on_body_entered)
	
	if _stats_have_been_set:
		_apply_all_stats_effects()

func _physics_process(_delta: float):
	velocity = direction * final_speed
	move_and_slide()

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

	var weapon_damage_percent = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.0))
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", [])
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
	final_damage_amount = int(round(maxf(1.0, calculated_damage_float)))
	
	var base_projectile_speed = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED], 400.0)
	var player_proj_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	final_speed = base_projectile_speed * player_proj_speed_mult
	
	var base_pierce = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PIERCE_COUNT], 0)
	var global_pierce_add = int(_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_PIERCE_COUNT_ADD))
	max_pierce_count = base_pierce + global_pierce_add

	# --- FIXED: SCALE CALCULATION ---
	# We no longer read the 'inherent_visual_scale' from the received stats,
	# as that belongs to the summoner (LesserSpiritInstance), not the projectile.
	# We start with a base scale of 1.0 for the projectile itself.
	var base_scale_x = 1.0
	var base_scale_y = 1.0
	var player_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	final_applied_scale = Vector2(base_scale_x * player_size_mult, base_scale_y * player_size_mult)
	_apply_visual_scale()
	
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 1.0))
	var duration_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = maxf(0.1, base_lifetime * duration_mult)
	lifetime_timer.start()
	
	if is_instance_valid(animated_sprite):
		animated_sprite.play("default")

func _apply_visual_scale():
	# Since the projectile's root node (this CharacterBody2D) is not scaled by default,
	# we apply the final calculated scale directly to the visual components.
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale

func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return

		var owner_player_char = _owner_player_stats.get_parent() as PlayerCharacter
		var attack_stats_for_enemy = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}

		enemy_target.take_damage(final_damage_amount, owner_player_char, attack_stats_for_enemy)
		
		var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
				owner_player_char.heal(final_damage_amount * global_lifesteal_percent)

		current_pierce_count += 1
		if current_pierce_count > max_pierce_count:
			queue_free()
	
	elif body.is_in_group("world_obstacles"):
		queue_free()
