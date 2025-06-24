# File: res/Scripts/DataResources/Weapons/Basic Class Weapons/SpiritBolt.gd
# REVISED: Corrected damage calculation and implements deferred destruction.

class_name SpiritBolt
extends CharacterBody2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var homing_component: HomingComponent = get_node_or_null("HomingComponent")
@onready var damage_area: Area2D = $DamageArea

var final_damage_amount: int
var final_speed: float
var direction: Vector2 = Vector2.RIGHT

var max_pierce_count: int = 0
var current_pierce_count: int = 0
var _enemies_hit_this_instance: Array[Node2D] = []

var _received_stats: Dictionary = {}
var _owner_player_stats: PlayerStats
var _is_destroying: bool = false

func _ready():
	lifetime_timer.timeout.connect(_start_destruction)
	if is_instance_valid(damage_area):
		damage_area.body_entered.connect(_on_body_entered)

func _physics_process(delta: float):
	if _is_destroying: return

	if not (is_instance_valid(homing_component) and homing_component.is_active):
		velocity = direction * final_speed
	move_and_slide()

func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats
	if is_inside_tree():
		_apply_all_stats_effects()

func _apply_all_stats_effects():
	if not is_instance_valid(_owner_player_stats): return

	var weapon_damage_percent = float(_received_stats.get(&"weapon_damage_percentage", 1.0))
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", [])
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
	
	var total_crit_chance = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE)
	if randf() < total_crit_chance:
		calculated_damage_float *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
		
	final_damage_amount = int(round(maxf(1.0, calculated_damage_float)))
	
	var base_projectile_speed = float(_received_stats.get(&"projectile_speed", 400.0))
	var player_proj_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	final_speed = base_projectile_speed * player_proj_speed_mult

	max_pierce_count = int(_received_stats.get(&"pierce_count", 0))

	var player_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	var final_applied_scale = Vector2.ONE * player_size_mult
	animated_sprite.scale = final_applied_scale; collision_shape.scale = final_applied_scale

	var base_lifetime = float(_received_stats.get(&"projectile_lifetime", 1.2))
	var global_range_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
	var time_from_added_range = 0.0
	if final_speed > 0:
		time_from_added_range = global_range_add / final_speed
		
	var duration_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = maxf(0.1, (base_lifetime + time_from_added_range) * duration_mult)
	lifetime_timer.start()

	rotation = direction.angle()
	animated_sprite.play("default")

	if _received_stats.get(&"has_homing", false) and is_instance_valid(homing_component):
		var target = _find_nearest_enemy()
		if is_instance_valid(target):
			homing_component.activate(target)

func _on_body_entered(body: Node2D):
	if _is_destroying: return

	if body is BaseEnemy and not _enemies_hit_this_instance.has(body):
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return

		_enemies_hit_this_instance.append(enemy_target)
		var owner_player_char = _owner_player_stats.get_parent()
		
		enemy_target.take_damage(final_damage_amount, owner_player_char)

		if _received_stats.get(&"has_arcane_infusion", false):
			var proc_chance = float(_received_stats.get(&"debuff_on_hit_chance", 0.0))
			if randf() < proc_chance:
				_apply_random_debuff(enemy_target)

		current_pierce_count += 1
		if current_pierce_count > max_pierce_count:
			_start_destruction()

func _start_destruction():
	if _is_destroying: return
	_is_destroying = true
	set_physics_process(false)
	collision_shape.set_deferred("disabled", true)
	get_tree().create_timer(0.1, true, false, true).timeout.connect(queue_free)

func _apply_random_debuff(enemy: BaseEnemy):
	# This function remains unchanged.
	if not is_instance_valid(enemy.status_effect_component): return
	var debuffs = [
		"res://DataResources/StatusEffects/slow_status.tres",
		"res://DataResources/StatusEffects/weakened_status.tres",
		"res://DataResources/StatusEffects/vulnerable_status.tres",
		"res://DataResources/StatusEffects/stun_status.tres"
	]
	var random_debuff_path = debuffs.pick_random()
	var effect_data = load(random_debuff_path) as StatusEffectData
	if is_instance_valid(effect_data):
		enemy.status_effect_component.apply_effect(effect_data, _owner_player_stats.get_parent())

func _find_nearest_enemy() -> Node2D:
	# This function remains unchanged.
	var enemies_in_scene = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy: Node2D = null; var min_dist_sq = INF
	for enemy_node in enemies_in_scene:
		if is_instance_valid(enemy_node) and not (enemy_node as BaseEnemy).is_dead():
			var dist_sq = global_position.distance_squared_to(enemy_node.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				nearest_enemy = enemy_node
	return nearest_enemy
