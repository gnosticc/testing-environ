# Scripts/DataResources/Weapons/Basic Class Weapons/ShortbowArrow.gd
# MODIFIED SCRIPT
# Handles the behavior of a single Shortbow arrow, now with logic
# for ricocheting, piercing, and corrected scaling.

class_name ShortbowArrow
extends Area2D

var final_damage_amount: int
var final_speed: float
var final_applied_scale: Vector2
var direction: Vector2 = Vector2.RIGHT

var max_pierce_count: int
var current_pierce_count: int = 0

var max_ricochet_count: int = 0
var current_ricochet_count: int = 0
var ricochet_search_range: float = 100.0
var _enemies_hit_this_instance: Array[Node2D] = []

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}
var _owner_player_stats: PlayerStats

func _ready():
	if not is_instance_valid(lifetime_timer):
		push_error("ERROR (ShortbowArrow): LifetimeTimer node missing! Queueing free."); call_deferred("queue_free"); return
	else:
		if not lifetime_timer.is_connected("timeout", Callable(self, "queue_free")):
			lifetime_timer.timeout.connect(self.queue_free)
	
	if _stats_have_been_set:
		_apply_all_stats_effects()

func _physics_process(delta: float):
	global_position += direction * final_speed * delta

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
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats):
		push_warning("WARNING (ShortbowArrow): Stats not set or owner_player_stats invalid. Cannot apply effects."); return

	var weapon_damage_percent = float(_received_stats.get(&"weapon_damage_percentage", 1.0))
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", [])
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
	final_damage_amount = int(round(maxf(1.0, calculated_damage_float)))
	
	var base_projectile_speed = float(_received_stats.get(&"projectile_speed", 160.0))
	var player_projectile_speed_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	final_speed = base_projectile_speed * player_projectile_speed_multiplier
	
	max_ricochet_count = int(_received_stats.get(&"ricochet_count", 0))
	ricochet_search_range = float(_received_stats.get(&"ricochet_search_range", 100.0))

	var base_pierce_count = int(_received_stats.get(&"pierce_count", 0))
	var global_pierce_add = int(_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_PIERCE_COUNT_ADD))
	max_pierce_count = base_pierce_count + global_pierce_add
	
	## FIX: Fletching Mastery size calculation changed for better hitbox feel.
	var base_scale_x = float(_received_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_received_stats.get(&"inherent_visual_scale_y", 1.0))
	var weapon_projectile_size_mult = float(_received_stats.get("projectile_size_multiplier", 1.0))
	var player_projectile_size_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	var total_size_multiplier = weapon_projectile_size_mult * player_projectile_size_multiplier
	
	# Apply the full multiplier to the Y scale (width) and only a fraction to the X scale (length).
	final_applied_scale.y = base_scale_y * total_size_multiplier
	final_applied_scale.x = base_scale_x * (1.0 + (total_size_multiplier - 1.0) * 0.25) # Grow length by 25% of the total growth factor
	
	_apply_visual_scale()
	
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 2.0))
	var effect_duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	var global_max_range_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
	if final_speed > 0:
		base_lifetime += (global_max_range_add / final_speed) * 0.5

	lifetime_timer.wait_time = base_lifetime * effect_duration_multiplier
	
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped():
		lifetime_timer.start()

	if is_instance_valid(animated_sprite):
		animated_sprite.play("fly")

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	else: push_warning("WARNING (ShortbowArrow): AnimatedSprite2D is invalid, cannot apply visual scale.")
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale
	else: push_warning("WARNING (ShortbowArrow): CollisionShape2D is invalid, cannot apply collision scale.")

func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead() or _enemies_hit_this_instance.has(enemy_target): return

		var owner_player = _owner_player_stats.get_parent()
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		enemy_target.take_damage(final_damage_amount, owner_player, attack_stats_for_enemy)
		_enemies_hit_this_instance.append(enemy_target)
		
		var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = final_damage_amount * global_lifesteal_percent
			if is_instance_valid(owner_player) and owner_player.has_method("heal"):
				owner_player.heal(heal_amount)

		if _received_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = _received_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0)
					
					if randf() < final_application_chance:
						enemy_target.status_effect_component.apply_effect(load(app_data.status_effect_resource_path) as StatusEffectData, owner_player, _received_stats, app_data.duration_override, app_data.potency_override)
		
		## FIX: Corrected order of operations for Ricochet and Pierce.
		# 1. Attempt to ricochet first.
		if current_ricochet_count < max_ricochet_count:
			var new_target = _find_new_ricochet_target(enemy_target.global_position)
			if is_instance_valid(new_target):
				direction = (new_target.global_position - global_position).normalized()
				rotation = direction.angle()
				current_ricochet_count += 1
				return # IMPORTANT: Exit the function here so the arrow doesn't get destroyed.
			
		# 2. If no ricochet happens, then check for pierce.
		if current_pierce_count < max_pierce_count:
			current_pierce_count += 1
			return # IMPORTANT: Exit the function to allow piercing.
		
		# 3. If no ricochet or pierce is possible, destroy the arrow.
		call_deferred("queue_free")
			
	elif body.is_in_group("world_obstacles"):
		call_deferred("queue_free")

func _find_new_ricochet_target(hit_position: Vector2) -> Node2D:
	var best_target: Node2D = null
	var min_dist_sq = ricochet_search_range * ricochet_search_range
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or _enemies_hit_this_instance.has(enemy):
			continue
		
		var dist_sq = hit_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_target = enemy
			
	return best_target
