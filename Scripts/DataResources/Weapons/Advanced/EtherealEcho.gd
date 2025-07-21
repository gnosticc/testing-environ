# File: EtherealEcho.gd
# Attach to: EtherealEcho.tscn
# REVISED: Implemented a new AI state machine for movement to prevent jitter.
# --------------------------------------------------------------------
class_name EtherealEcho
extends CharacterBody2D

enum AIState { CHASING, IDLING_IN_RANGE }
var _ai_state: AIState = AIState.CHASING

@export var primary_projectile_scene: PackedScene
@export var phantom_reach_projectile_scene: PackedScene
@export var eldritch_orb_scene: PackedScene
@export var echoing_demise_scene: PackedScene

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var primary_attack_timer: Timer = $PrimaryAttackTimer
@onready var phantom_reach_timer: Timer = $PhantomReachTimer
@onready var encroaching_darkness_timer: Timer = $EncroachingDarknessTimer
@onready var projectile_spawn_point: Marker2D = $ProjectileSpawnPoint
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _owner_player: PlayerCharacter
var _game_node: Node

func initialize(p_owner: PlayerCharacter, p_stats: Dictionary):
	_owner_player = p_owner
	_owner_player_stats = _owner_player.player_stats
	_specific_stats = p_stats

	self.visible = false
	set_physics_process(false)

	await get_tree().create_timer(0.25).timeout
	
	if not is_instance_id_valid(self.get_instance_id()): return

	self.visible = true
	set_physics_process(true)
	
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	primary_attack_timer.timeout.connect(_fire_primary_attack)
	phantom_reach_timer.timeout.connect(_fire_phantom_reach)
	encroaching_darkness_timer.timeout.connect(_fire_eldritch_orb)
	
	_game_node = get_tree().root.get_node_or_null("Game")
	if is_instance_valid(_game_node) and _game_node.has_signal("enemy_was_killed"):
		_game_node.enemy_was_killed.connect(_on_any_enemy_killed)

	update_stats(p_stats)
	
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_game_node) and _game_node.is_connected("enemy_was_killed", _on_any_enemy_killed):
			_game_node.enemy_was_killed.disconnect(_on_any_enemy_killed)

func update_stats(new_stats: Dictionary):
	_specific_stats = new_stats
	
	lifetime_timer.wait_time = float(_specific_stats.get("echo_duration", 5.0))
	primary_attack_timer.wait_time = float(_specific_stats.get("primary_attack_cooldown", 1.2))
	
	if _specific_stats.get("has_phantom_reach", false):
		phantom_reach_timer.wait_time = float(_specific_stats.get("phantom_reach_cooldown", 0.4))
		if phantom_reach_timer.is_stopped(): phantom_reach_timer.start()
	else:
		phantom_reach_timer.stop()
		
	if _specific_stats.get("has_encroaching_darkness", false):
		encroaching_darkness_timer.wait_time = float(_specific_stats.get("eldritch_orb_cooldown", 2.0))
		if encroaching_darkness_timer.is_stopped(): encroaching_darkness_timer.start()
	else:
		encroaching_darkness_timer.stop()
		
	if lifetime_timer.is_stopped(): lifetime_timer.start()
	if primary_attack_timer.is_stopped(): primary_attack_timer.start()
	
	var base_scale = float(_specific_stats.get("echo_scale", 1.0))
	self.scale = Vector2.ONE * base_scale

func _physics_process(delta: float):
	if not is_instance_valid(_owner_player):
		queue_free()
		return
	
	var primary_attack_range_sq = pow(float(_specific_stats.get("primary_attack_range", 200.0)), 2)
	var move_target = _find_movement_target()

	if not is_instance_valid(move_target):
		# No enemies exist, so just stop moving.
		_ai_state = AIState.IDLING_IN_RANGE
	else:
		var distance_to_target_sq = global_position.distance_squared_to(move_target.global_position)
		if distance_to_target_sq > primary_attack_range_sq * 0.5: # Chase if outside 80% of attack range
			_ai_state = AIState.CHASING
		else:
			_ai_state = AIState.IDLING_IN_RANGE

	match _ai_state:
		AIState.CHASING:
			if is_instance_valid(move_target):
				var direction = (move_target.global_position - global_position).normalized()
				velocity = direction * float(_specific_stats.get("echo_movement_speed", 80.0))
		AIState.IDLING_IN_RANGE:
			velocity = velocity.move_toward(Vector2.ZERO, 300 * delta) # Slow down to a stop
		
	if abs(velocity.x) > 1.0:
		animated_sprite.flip_h = velocity.x < 0

	move_and_slide()

func _find_movement_target() -> Node2D:
	var best_cluster_target = _find_best_enemy_cluster_target()
	if is_instance_valid(best_cluster_target):
		return best_cluster_target
		
	var single_enemy = _find_nearest_enemy(global_position)
	if is_instance_valid(single_enemy):
		return single_enemy
		
	return _owner_player

func _find_best_enemy_cluster_target() -> BaseEnemy:
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	var best_target: BaseEnemy = null
	var highest_score = 1
	
	for enemy in all_enemies:
		if not (enemy is BaseEnemy) or enemy.is_dead(): continue
		var nearby_count = _get_enemies_in_radius(enemy.global_position, 150.0, [enemy]).size()
		var current_score = 1 + nearby_count
		if current_score > highest_score:
			highest_score = current_score
			best_target = enemy
			
	return best_target

func _fire_primary_attack():
	var target = _find_nearest_enemy(projectile_spawn_point.global_position, float(_specific_stats.get("primary_attack_range", 200.0)))
	if is_instance_valid(target):
		var base_direction = (target.global_position - projectile_spawn_point.global_position).normalized()
		var spread_angle = deg_to_rad(15)
		for i in range(5):
			var offset = (float(i) - 2.0) / 2.0
			var direction = base_direction.rotated(spread_angle * offset)
			_spawn_primary_projectile(direction)

func _spawn_primary_projectile(direction: Vector2):
	var projectile = primary_projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = projectile_spawn_point.global_position
	projectile.initialize(direction, _specific_stats, _owner_player_stats, self.get_instance_id())

func _fire_phantom_reach():
	var target = _find_lowest_health_percent_enemy(float(_specific_stats.get("phantom_reach_range", 500.0)))
	if is_instance_valid(target):
		var projectile = phantom_reach_projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		projectile.global_position = projectile_spawn_point.global_position
		projectile.initialize(target, _specific_stats, _owner_player_stats, self.get_instance_id())

func _fire_eldritch_orb():
	var target = _find_nearest_enemy(projectile_spawn_point.global_position)
	if is_instance_valid(target):
		var orb = eldritch_orb_scene.instantiate()
		get_tree().current_scene.add_child(orb)
		orb.global_position = projectile_spawn_point.global_position
		var direction = (target.global_position - orb.global_position).normalized()
		orb.initialize(direction, _specific_stats, _owner_player_stats, self.get_instance_id())

func _on_lifetime_expired():
	# Stop all activity before spawning the demise effect.
	set_physics_process(false)
	lifetime_timer.stop()
	primary_attack_timer.stop()
	phantom_reach_timer.stop()
	encroaching_darkness_timer.stop()
	velocity = Vector2.ZERO
	
	if _specific_stats.get("has_echoing_demise", false):
		var demise = echoing_demise_scene.instantiate()
		get_tree().current_scene.add_child(demise)
		demise.global_position = self.global_position
		demise.initialize(_specific_stats, _owner_player_stats)
	
	# Hide the Echo and wait for one physics frame before deleting.
	# This gives the EchoingDemise scene time to register its Area2D.
	self.visible = false
	collision_shape.disabled = true
	await get_tree().physics_frame
	queue_free()

func _on_any_enemy_killed(_attacker_node: Node, killed_enemy_node: Node):
	if _specific_stats.get("has_unstable_rift", false):
		if CombatTracker.was_enemy_hit_by_weapon_within_seconds(StringName(str(self.get_instance_id())), killed_enemy_node, 0.3):
			if randf() < float(_specific_stats.get("unstable_rift_chance", 0.1)):
				call_deferred("_spawn_new_echo", killed_enemy_node.global_position)

func _spawn_new_echo(position: Vector2):
	# Spawn the portal visual effect
	var portal_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/SummoningPortal.tscn")
	var portal_instance = portal_scene.instantiate()
	get_tree().current_scene.add_child(portal_instance)
	portal_instance.global_position = position
	
	# Create a modified set of stats for the new Echo
	var rift_stats = _specific_stats.duplicate(true)
	rift_stats["echo_duration"] = 4.0 # Cap lifetime at 4 seconds
	
	# Spawn the new Echo
	var echo_instance = load("res://Scenes/Weapons/Advanced/EtherealEcho.tscn").instantiate()
	get_tree().current_scene.add_child(echo_instance)
	echo_instance.global_position = position
	echo_instance.initialize(_owner_player, rift_stats)

# --- Helper Functions ---
func _find_nearest_enemy(from_position: Vector2, max_range: float = INF) -> BaseEnemy:
	var nearest_enemy: BaseEnemy = null
	var min_dist_sq = max_range * max_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is BaseEnemy and not enemy.is_dead():
			var dist_sq = from_position.distance_squared_to(enemy.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				nearest_enemy = enemy
	return nearest_enemy
	
func _find_lowest_health_percent_enemy(max_range: float) -> BaseEnemy:
	var best_target: BaseEnemy = null
	var lowest_health_percent = 2.0
	var max_range_sq = max_range * max_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is BaseEnemy and not enemy.is_dead():
			if global_position.distance_squared_to(enemy.global_position) < max_range_sq:
				var health_percent = enemy.current_health / enemy.max_health
				if health_percent < lowest_health_percent:
					lowest_health_percent = health_percent
					best_target = enemy
	return best_target

func _get_enemies_in_radius(p_position: Vector2, p_radius: float, p_exclude_list: Array[BaseEnemy] = []) -> Array[BaseEnemy]:
	var enemies_in_radius: Array[BaseEnemy] = []
	var radius_sq = p_radius * p_radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is BaseEnemy) or enemy.is_dead() or p_exclude_list.has(enemy):
			continue
		if p_position.distance_squared_to(enemy.global_position) < radius_sq:
			enemies_in_radius.append(enemy)
	return enemies_in_radius
