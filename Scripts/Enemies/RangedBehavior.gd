# RangedBehavior.gd
# A component that provides ranged combat AI for BaseEnemy.
# It reads data from the owner's EnemyData resource to determine
# its movement and firing patterns.

class_name RangedBehavior
extends Node

# --- References ---
var owner_enemy: BaseEnemy
var player_node: PlayerCharacter
var enemy_data: EnemyData
var game_node_ref: Node

# --- Timers ---
var _firing_timer: Timer
var _circle_direction_timer: Timer
var _burst_shot_timer: Timer # For the delay between burst shots

# --- State ---
var _is_initialized: bool = false
var _circle_direction: int = 1 # 1 for clockwise, -1 for counter-clockwise
var _irratic_wobble: float = 0.0
var _burst_shots_remaining: int = 0

# --- Public API ---

func initialize(p_owner_enemy: BaseEnemy):
	owner_enemy = p_owner_enemy
	player_node = owner_enemy.player_node
	enemy_data = owner_enemy.enemy_data_resource
	game_node_ref = owner_enemy.game_node_ref
	
	# Create and configure the main firing timer
	_firing_timer = Timer.new()
	_firing_timer.name = "RangedFiringTimer"
	_firing_timer.one_shot = true
	add_child(_firing_timer)
	
	# Create and configure the timer for changing circle/irratic direction
	_circle_direction_timer = Timer.new()
	_circle_direction_timer.name = "DirectionChangeTimer"
	_circle_direction_timer.wait_time = enemy_data.circle_direction_change_interval
	_circle_direction_timer.one_shot = false # This timer will repeat
	_circle_direction_timer.autostart = true
	add_child(_circle_direction_timer)
	_circle_direction_timer.timeout.connect(_on_direction_timer_timeout)
	
	# Create and configure the timer for burst shots
	_burst_shot_timer = Timer.new()
	_burst_shot_timer.name = "BurstShotTimer"
	_burst_shot_timer.one_shot = true
	add_child(_burst_shot_timer)
	_burst_shot_timer.timeout.connect(_fire_next_burst_shot)
	
	_is_initialized = true

# This is the main entry point called by BaseEnemy every physics frame.
func process_behavior(current_velocity: Vector2, delta: float) -> Vector2:
	if not _is_initialized or not is_instance_valid(player_node):
		return Vector2.ZERO

	var new_velocity = current_velocity
	
	# --- 1. Handle Movement ---
	match enemy_data.movement_pattern:
		EnemyData.RangedMovementPattern.STATIONARY:
			new_velocity = _process_stationary_movement()
		EnemyData.RangedMovementPattern.KITE:
			new_velocity = _process_kite_movement()
		EnemyData.RangedMovementPattern.CIRCLE:
			new_velocity = _process_circle_movement()
		EnemyData.RangedMovementPattern.IRRATIC:
			new_velocity = _process_irratic_movement()
			
	# --- 2. Handle Firing ---
	match enemy_data.firing_pattern:
		EnemyData.RangedFiringPattern.AUTO:
			_process_auto_fire()
		EnemyData.RangedFiringPattern.BURST:
			_process_burst_fire()
		EnemyData.RangedFiringPattern.IRRATIC_BURST:
			_process_irratic_burst_fire()
		EnemyData.RangedFiringPattern.HOMING:
			_process_homing_fire()
			
	return new_velocity

# --- Movement Logic Functions ---

func _process_stationary_movement() -> Vector2:
	var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
	var ideal_range = enemy_data.max_firing_range * 0.5
	
	if distance_to_player > ideal_range:
		var direction_to_player = owner_enemy.global_position.direction_to(player_node.global_position)
		return direction_to_player * owner_enemy.speed
	else:
		return Vector2.ZERO

func _process_kite_movement() -> Vector2:
	var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
	var ideal_range = enemy_data.max_firing_range * 0.5
	var buffer = enemy_data.kite_comfort_zone_buffer
	
	var comfort_zone_min = ideal_range - buffer
	var comfort_zone_max = ideal_range + buffer
	
	if distance_to_player > comfort_zone_max:
		var direction_to_player = owner_enemy.global_position.direction_to(player_node.global_position)
		return direction_to_player * owner_enemy.speed
	elif distance_to_player < comfort_zone_min:
		var direction_away_from_player = owner_enemy.global_position.direction_to(player_node.global_position) * -1.0
		var flee_speed = owner_enemy.speed * enemy_data.kite_flee_speed_multiplier
		return direction_away_from_player * flee_speed
	else:
		return Vector2.ZERO

func _process_circle_movement() -> Vector2:
	var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
	var ideal_range = enemy_data.max_firing_range * 0.5
	var buffer = enemy_data.circle_comfort_zone_buffer
	
	var comfort_zone_min = ideal_range - buffer
	var comfort_zone_max = ideal_range + buffer
	
	if distance_to_player > comfort_zone_max:
		var direction_to_player = owner_enemy.global_position.direction_to(player_node.global_position)
		return direction_to_player * owner_enemy.speed
	elif distance_to_player < comfort_zone_min:
		var direction_away_from_player = owner_enemy.global_position.direction_to(player_node.global_position) * -1.0
		var flee_speed = owner_enemy.speed * enemy_data.circle_flee_speed_multiplier
		return direction_away_from_player * flee_speed
	else:
		var direction_from_player = player_node.global_position.direction_to(owner_enemy.global_position)
		var tangent_direction = direction_from_player.orthogonal() * _circle_direction
		var circle_speed = owner_enemy.speed * enemy_data.circle_speed_multiplier
		return tangent_direction * circle_speed

func _process_irratic_movement() -> Vector2:
	var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
	var min_range = enemy_data.max_firing_range * enemy_data.irratic_min_range_percent
	var max_range = enemy_data.max_firing_range * enemy_data.irratic_max_range_percent
	
	if distance_to_player > max_range:
		var direction_to_player = owner_enemy.global_position.direction_to(player_node.global_position)
		var adjust_speed = owner_enemy.speed * enemy_data.irratic_adjust_speed_multiplier
		return direction_to_player * adjust_speed
	elif distance_to_player < min_range:
		var direction_away_from_player = owner_enemy.global_position.direction_to(player_node.global_position) * -1.0
		var flee_speed = owner_enemy.speed * enemy_data.irratic_flee_speed_multiplier
		return direction_away_from_player * flee_speed
	else:
		var direction_from_player = player_node.global_position.direction_to(owner_enemy.global_position)
		var tangent_vector = direction_from_player.orthogonal() * _circle_direction
		var radial_vector = direction_from_player
		var combined_vector = (tangent_vector + radial_vector * _irratic_wobble).normalized()
		var comfort_zone_speed = owner_enemy.speed * enemy_data.irratic_comfort_zone_speed_multiplier
		return combined_vector * comfort_zone_speed

# --- Firing Logic Functions ---

func _process_auto_fire():
	if _firing_timer.is_stopped():
		var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
		if distance_to_player <= enemy_data.max_firing_range:
			_fire_projectile()
			_firing_timer.wait_time = enemy_data.auto_fire_cooldown
			_firing_timer.start()

func _process_burst_fire():
	if _firing_timer.is_stopped():
		var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
		if distance_to_player <= enemy_data.max_firing_range:
			_burst_shots_remaining = enemy_data.burst_shot_count
			_fire_next_burst_shot()
			_firing_timer.wait_time = enemy_data.burst_fire_cooldown
			_firing_timer.start()

func _process_irratic_burst_fire():
	if _firing_timer.is_stopped():
		var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
		if distance_to_player <= enemy_data.max_firing_range:
			_burst_shots_remaining = enemy_data.irratic_shot_count
			_fire_next_burst_shot() # This function is reused for both burst types
			var cooldown = randf_range(enemy_data.irratic_cooldown_min, enemy_data.irratic_cooldown_max)
			_firing_timer.wait_time = cooldown
			_firing_timer.start()

func _process_homing_fire():
	if _firing_timer.is_stopped():
		var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
		if distance_to_player <= enemy_data.max_firing_range:
			_fire_projectile()
			_firing_timer.wait_time = enemy_data.homing_fire_cooldown
			_firing_timer.start()

# --- Utility Functions ---

func _fire_next_burst_shot():
	if _burst_shots_remaining <= 0:
		return
	
	_fire_projectile()
	_burst_shots_remaining -= 1
	
	if _burst_shots_remaining > 0:
		var delay = 0.0
		if enemy_data.firing_pattern == EnemyData.RangedFiringPattern.BURST:
			delay = enemy_data.burst_shot_delay
		else: # Irratic Burst
			delay = randf_range(enemy_data.irratic_shot_delay_min, enemy_data.irratic_shot_delay_max)
		
		_burst_shot_timer.wait_time = delay
		_burst_shot_timer.start()

func _fire_projectile():
	if not is_instance_valid(enemy_data.ranged_projectile_scene):
		push_warning("Ranged enemy '", owner_enemy.name, "' is missing its ranged_projectile_scene.")
		return

	var attacks_container = game_node_ref.get_node_or_null("EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("RangedBehavior: Could not find 'EnemyAttacksContainer' node. Projectile not spawned.")
		return
		
	var projectile_instance = enemy_data.ranged_projectile_scene.instantiate()
	attacks_container.add_child(projectile_instance)
	
	# --- SOLUTION: Calculate predicted position for aiming ---
	var target_pos = player_node.global_position
	if enemy_data.use_shot_prediction and player_node.has_method("get_current_velocity"):
		var player_velocity = player_node.get_current_velocity()
		target_pos = player_node.global_position + (player_velocity * enemy_data.shot_prediction_time)
	
	var direction_to_target = owner_enemy.global_position.direction_to(target_pos)
	# --- END SOLUTION ---
	
	if projectile_instance.has_method("initialize"):
		var init_args = [
			owner_enemy.global_position,
			direction_to_target, # Use the potentially predicted direction
			enemy_data.ranged_projectile_speed,
			enemy_data.ranged_projectile_damage,
			enemy_data.ranged_projectile_lifespan
		]

		if enemy_data.firing_pattern == EnemyData.RangedFiringPattern.HOMING:
			init_args.append(enemy_data.homing_strength)
			init_args.append(player_node)

		projectile_instance.initialize.callv(init_args)
	else:
		projectile_instance.global_position = owner_enemy.global_position

func _on_direction_timer_timeout():
	# Flip the strafe direction
	_circle_direction *= -1
	# For irratic movement, also pick a new random "wobble" factor
	_irratic_wobble = randf_range(-0.7, 0.7)
