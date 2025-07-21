# crossbowbolt.gd
# CORRECTED: Now uses a timed, deferred queue_free to prevent physics crashes.
# CORRECTED: Explosion logic now triggers on every valid enemy hit, not just on destruction.
# FIX: Implemented deferred calls for physics state changes and adding new physics bodies to prevent "flushing queries" errors.

extends CharacterBody2D

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var damage_area: Area2D = $DamageArea

# Preload the explosion scene for efficiency.
const EXPLOSION_SCENE = preload("res://Scenes/Weapons/Projectiles/Explosion.tscn")

# --- Internal State Variables ---
var final_damage_amount: int
var final_speed: float
var final_applied_scale: Vector2
var direction: Vector2 = Vector2.RIGHT
var max_pierce_count: int
var current_pierce_count: int = 0
var weapon_specific_crit_chance: float = 0.0

# --- Private Properties ---
var _received_stats: Dictionary
var _owner_player_stats: PlayerStats
var _stats_have_been_set: bool = false
var _is_destroying: bool = false # Flag to prevent multiple destructions

func _ready():
	if not is_instance_valid(lifetime_timer) or not is_instance_valid(damage_area) or not is_instance_valid(collision_shape):
		push_error("CrossbowBolt ERROR: Required child node is missing. Destroying self.")
		queue_free(); return
	
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	damage_area.body_entered.connect(_on_body_entered)
	
	if _stats_have_been_set:
		_apply_all_stats_effects()

func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats
	_stats_have_been_set = true
	
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	if is_inside_tree():
		_apply_all_stats_effects()
	else:
		call_deferred("_apply_all_stats_effects")

func _apply_all_stats_effects():
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats): return

	var weapon_damage_percent = float(_received_stats.get(&"weapon_damage_percentage", 1.0))
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", [])
	
	# --- REFACTORED DAMAGE CALCULATION ---
	var base_damage = _owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
	var calculated_damage_float = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	# --- END REFACTOR ---

	final_damage_amount = int(round(maxf(1.0, calculated_damage_float)))
	
	final_speed = float(_received_stats.get(&"final_projectile_speed", 220.0))
	weapon_specific_crit_chance = float(_received_stats.get(&"crit_chance", 0.0))
	
	var base_pierce_count = int(_received_stats.get(&"pierce_count", 0))
	var global_pierce_add = int(_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_PIERCE_COUNT_ADD))
	max_pierce_count = base_pierce_count + global_pierce_add

	var base_scale_x = float(_received_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_received_stats.get(&"inherent_visual_scale_y", 1.0))
	var player_projectile_size_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	final_applied_scale = Vector2(base_scale_x * player_projectile_size_multiplier, base_scale_y * player_projectile_size_multiplier)
	_apply_visual_scale()
	
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 2.0))
	var effect_duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	var global_max_range_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
	if final_speed > 0:
		base_lifetime += (global_max_range_add / final_speed) * 0.5

	lifetime_timer.wait_time = maxf(0.1, base_lifetime * effect_duration_multiplier)
	if lifetime_timer.is_stopped():
		lifetime_timer.start()

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale

func _physics_process(_delta):
	if _is_destroying: return
	velocity = direction * final_speed
	move_and_slide()

func _on_body_entered(body: Node2D):
	if _is_destroying: return

	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return

		var owner_player = _owner_player_stats.get_parent()
		var damage_to_deal = float(final_damage_amount)
		
		var total_crit_chance = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE) + weapon_specific_crit_chance
		if randf() < total_crit_chance:
			damage_to_deal *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
			
		var attack_stats_for_enemy = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		
		var weapon_tags: Array[StringName] = []
		if _received_stats.has("tags"):
			weapon_tags = _received_stats.get("tags")
		enemy_target.take_damage(int(round(damage_to_deal)), owner_player, attack_stats_for_enemy, weapon_tags)
		
		call_deferred("_try_spawn_explosion", int(round(damage_to_deal)))
		
		if _received_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = _received_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)
			for app_data_res in status_apps:
				if app_data_res is StatusEffectApplicationData:
					var final_application_chance = app_data_res.application_chance + global_status_effect_chance_add
					if randf() < clampf(final_application_chance, 0.0, 1.0):
						enemy_target.status_effect_component.apply_effect(load(app_data_res.status_effect_resource_path) as StatusEffectData, owner_player, _received_stats, app_data_res.duration_override, app_data_res.potency_override)

		current_pierce_count += 1
		if current_pierce_count > max_pierce_count:
			_start_destruction()

	elif body.is_in_group("world_obstacles"):
		_start_destruction()

func _on_lifetime_expired():
	_start_destruction()

# New safe destruction function
func _start_destruction():
	if _is_destroying: return
	_is_destroying = true
	set_physics_process(false) # Stop movement
	# FIX: Use set_deferred for collision_shape.disabled to prevent flushing queries error.
	if is_instance_valid(collision_shape): collision_shape.set_deferred("disabled", true)
	if is_instance_valid(animated_sprite): animated_sprite.visible = false
	# Wait for a very short moment before calling queue_free to exit the physics step.
	get_tree().create_timer(0.1, false, false, true).timeout.connect(queue_free)

# Renamed from _handle_bolt_destruction to be more specific
func _try_spawn_explosion(p_proccing_hit_damage: int):
	if _received_stats.get(&"has_explosive_tip", false):
		var explosion_chance = float(_received_stats.get(&"explosive_tip_chance", 0.0))
		if randf() < explosion_chance:
			var explosion_damage_percent = float(_received_stats.get(&"explosive_tip_damage_percent", 0.35))
			var explosion_radius = float(_received_stats.get(&"explosive_tip_radius", 10.0))
			var explosion_damage = int(round(p_proccing_hit_damage * explosion_damage_percent))
			_spawn_explosion(explosion_damage, explosion_radius)

func _spawn_explosion(damage: int, radius: float):
	if not is_instance_valid(EXPLOSION_SCENE):
		push_error("CrossbowBolt ERROR: EXPLOSION_SCENE is not valid!"); return

	var explosion_instance = EXPLOSION_SCENE.instantiate()
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	
	if is_instance_valid(attacks_container):
		attacks_container.add_child(explosion_instance)
	else:
		get_tree().current_scene.add_child(explosion_instance)

	explosion_instance.global_position = self.global_position
	
	if explosion_instance.has_method("detonate"):
		var owner_player = _owner_player_stats.get_parent()
		var attack_stats = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		# Pass the main weapon's stats dictionary to the explosion
		explosion_instance.call_deferred("detonate", damage, radius, owner_player, attack_stats, false, _received_stats)
