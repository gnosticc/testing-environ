# File: ConjoinedSpirit.gd
# Attach to: ConjoinedSpirit.tscn (root CharacterBody2D)
# REVISED: Corrected timer logic to ensure continuous firing on cooldown.
# Removed deferred initialization for better stability.
# --------------------------------------------------------------------
class_name ConjoinedSpirit
extends CharacterBody2D

# --- Enum for State Machine ---
enum State { ROAMING, ATTUNING, RETURNING }
var current_state: State = State.ROAMING

# --- Scene Preloads ---
@export var ice_shard_scene: PackedScene
@export var water_ball_scene: PackedScene

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var contact_damage_area: Area2D = $ContactDamageArea
@onready var roaming_timer: Timer = $RoamingTimer
@onready var attunement_timer: Timer = $AttunementTimer
@onready var ice_shard_attack_timer: Timer = $IceShardAttackTimer
@onready var water_ball_attack_timer: Timer = $WaterBallAttackTimer
@onready var permafrost_storm_timer: Timer = $PermafrostStormTimer
@onready var ice_projectile_spawn: Marker2D = $IceProjectileSpawn
@onready var water_projectile_spawn: Marker2D = $WaterProjectileSpawn

# --- Internal State ---
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _owner_player: PlayerCharacter
var _weapon_manager: WeaponManager
var _roaming_target_position: Vector2

# This initialize function now matches the expected signature for summons.
# All setup logic is now here, and the deferred call has been removed.
func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, _start_angle: float):
	_owner_player = p_owner
	_owner_player_stats = p_owner.player_stats
	_specific_stats = p_stats
	_weapon_manager = _owner_player.get_node_or_null("WeaponManager")
	
	if not is_instance_valid(_weapon_manager):
		push_error("ConjoinedSpirit CRITICAL ERROR: Could not find 'WeaponManager' on player node. Deleting self.")
		queue_free()
		return

	# Connect signals
	roaming_timer.timeout.connect(_on_roaming_timer_timeout)
	attunement_timer.timeout.connect(_on_attunement_timer_timeout)
	ice_shard_attack_timer.timeout.connect(_fire_ice_shard)
	water_ball_attack_timer.timeout.connect(_fire_water_ball)
	permafrost_storm_timer.timeout.connect(_execute_permafrost_storm)
	contact_damage_area.body_entered.connect(_on_contact_damage_body_entered)
	
	# FIX: Set attack timers to be repeating, not one-shot.
	ice_shard_attack_timer.one_shot = false
	water_ball_attack_timer.one_shot = false
	permafrost_storm_timer.one_shot = false
	
	# Initial setup
	update_stats(p_stats)
	_enter_roaming_state()

func _notification(what):
	# Disconnect signals on deletion to prevent memory leaks.
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_owner_player_stats) and _owner_player_stats.is_connected("stats_recalculated", update_stats):
			_owner_player_stats.stats_recalculated.disconnect(update_stats)

func update_stats(new_stats: Dictionary = {}):
	if not new_stats.is_empty():
		_specific_stats = new_stats
	
	# Update timer durations based on current stats
	roaming_timer.wait_time = float(_specific_stats.get("roaming_duration", 10.0))
	attunement_timer.wait_time = float(_specific_stats.get("attunement_duration", 4.0))
	
	var ice_cooldown = float(_specific_stats.get("ice_shard_cooldown", 0.5))
	var water_cooldown = float(_specific_stats.get("water_ball_cooldown", 1.5))
	var player_atk_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	
	ice_shard_attack_timer.wait_time = max(0.1, ice_cooldown / player_atk_speed_mult)
	water_ball_attack_timer.wait_time = max(0.1, water_cooldown / player_atk_speed_mult)
	
	permafrost_storm_timer.wait_time = float(_specific_stats.get("permafrost_storm_interval", 3.0))

	# Enable/disable contact damage area based on upgrade flag
	contact_damage_area.monitoring = _specific_stats.get("has_planar_attachment", false)

func _physics_process(delta: float):
	if not is_instance_valid(_owner_player):
		queue_free()
		return

	var move_target_position: Vector2
	match current_state:
		State.ROAMING:
			move_target_position = _roaming_target_position
			if global_position.distance_to(move_target_position) < 20:
				_pick_new_roaming_target()
		State.RETURNING:
			move_target_position = _owner_player.global_position
			if global_position.distance_to(move_target_position) < 25:
				_enter_attunement_state()
		State.ATTUNING:
			var orbit_radius = 40.0
			var orbit_speed = 2.0
			var angle_offset = Time.get_ticks_msec() * 0.001 * orbit_speed
			var offset = Vector2.RIGHT.rotated(angle_offset) * orbit_radius
			move_target_position = _owner_player.global_position + offset

	if current_state != State.ATTUNING:
		var direction = (move_target_position - global_position).normalized()
		velocity = direction * float(_specific_stats.get("movement_speed", 120.0))
	else:
		velocity = velocity.lerp((move_target_position - global_position) / delta, delta * 5.0)
	
	move_and_slide()

# --- State Management ---

func _enter_roaming_state():
	current_state = State.ROAMING
	animated_sprite.play("roam")
	_pick_new_roaming_target()
	roaming_timer.start()
	ice_shard_attack_timer.start()
	water_ball_attack_timer.start()
	if _specific_stats.get("has_permafrost_storm", false):
		permafrost_storm_timer.start()

func _enter_returning_state():
	current_state = State.RETURNING
	animated_sprite.play("roam")
	ice_shard_attack_timer.stop()
	water_ball_attack_timer.stop()
	permafrost_storm_timer.stop()
	if _specific_stats.get("has_elemental_fusion", false):
		_execute_elemental_fusion_nova()
	if _specific_stats.get("has_symbiotic_attunement", false):
		_apply_symbiotic_attunement_buff(true)

func _enter_attunement_state():
	current_state = State.ATTUNING
	animated_sprite.play("attune")
	attunement_timer.start()

func _on_roaming_timer_timeout():
	_enter_returning_state()

func _on_attunement_timer_timeout():
	if _specific_stats.get("has_elemental_fusion", false):
		_execute_elemental_fusion_nova()
	if _specific_stats.get("has_symbiotic_attunement", false):
		_apply_symbiotic_attunement_buff(false)
	_enter_roaming_state()

func _pick_new_roaming_target():
	var roam_radius = float(_specific_stats.get("roaming_radius", 250.0))
	var random_direction = Vector2.RIGHT.rotated(randf_range(0, TAU))
	_roaming_target_position = _owner_player.global_position + random_direction * randf_range(50, roam_radius)

# --- Attack Logic ---

func _fire_ice_shard():
	var target = _find_nearest_enemy(ice_projectile_spawn.global_position)
	if is_instance_valid(target):
		var base_direction = (target.global_position - ice_projectile_spawn.global_position).normalized()
		
		# Check for Splintering Chill upgrade
		if _specific_stats.get("has_splintering_chill", false):
			# Fire 3 shards in a spread
			var spread_angle = deg_to_rad(10)
			_spawn_ice_shard_instance(base_direction.rotated(-spread_angle))
			_spawn_ice_shard_instance(base_direction)
			_spawn_ice_shard_instance(base_direction.rotated(spread_angle))
		else:
			# Fire a single shard
			_spawn_ice_shard_instance(base_direction)

func _spawn_ice_shard_instance(direction: Vector2):
	var projectile = ice_shard_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = ice_projectile_spawn.global_position
	if projectile.has_method("initialize"):
		projectile.initialize(direction, _specific_stats, _owner_player_stats)

func _fire_water_ball():
	var target = _find_nearest_enemy(water_projectile_spawn.global_position)
	if is_instance_valid(target):
		var projectile = water_ball_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		projectile.global_position = water_projectile_spawn.global_position
		var direction = (target.global_position - projectile.global_position).normalized()
		if projectile.has_method("initialize"):
			projectile.initialize(direction, _specific_stats, _owner_player_stats)

func _on_contact_damage_body_entered(body: Node2D):
	if body is BaseEnemy and not body.is_dead():
		var damage_percent = float(_specific_stats.get("planar_attachment_damage", 0.2))
		var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
		
		# --- REFACTORED DAMAGE CALCULATION ---
		var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
		var damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		# --- END REFACTOR ---
		
		body.take_damage(damage, _owner_player, {}, weapon_tags)

func _execute_elemental_fusion_nova():
	_execute_nova(8, 8, _owner_player.global_position)

func _execute_permafrost_storm():
	_execute_nova(4, 4, self.global_position)

func _execute_nova(ice_count: int, water_count: int, spawn_origin: Vector2):
	var total_projectiles = ice_count + water_count
	var angle_step = TAU / float(total_projectiles)
	for i in range(total_projectiles):
		var direction = Vector2.RIGHT.rotated(i * angle_step)
		if i % 2 == 0:
			var projectile = ice_shard_scene.instantiate()
			get_tree().current_scene.add_child(projectile)
			projectile.global_position = spawn_origin
			if projectile.has_method("initialize"):
				projectile.initialize(direction, _specific_stats, _owner_player_stats)
		else:
			var projectile = water_ball_scene.instantiate()
			get_tree().current_scene.add_child(projectile)
			projectile.global_position = spawn_origin
			if projectile.has_method("initialize"):
				projectile.initialize(direction, _specific_stats, _owner_player_stats)


# --- Upgrade Logic ---

func _apply_symbiotic_attunement_buff(should_apply: bool):
	var status_comp = _owner_player.status_effect_component
	if not is_instance_valid(status_comp): return
	
	var buff_id = &"symbiotic_attunement_buff"
	if should_apply:
		var buff_data = load("res://DataResources/StatusEffects/ConjoinedSpirit/symbiotic_attunement_buff.tres")
		status_comp.apply_effect(buff_data, _owner_player, {}, -1.0, -1.0, buff_id)
	else:
		status_comp.remove_effect_by_unique_id(buff_id)

# --- Helper Functions ---

func _find_nearest_enemy(from_position: Vector2) -> BaseEnemy:
	var nearest_enemy: BaseEnemy = null
	var min_dist_sq = INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is BaseEnemy and not enemy.is_dead():
			var dist_sq = from_position.distance_squared_to(enemy.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				nearest_enemy = enemy
	return nearest_enemy
