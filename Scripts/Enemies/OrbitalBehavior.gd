# OrbitalBehavior.gd
# A component that spawns and manages a set of orbiting projectiles around its owner.
# It also controls the owner's movement to maintain the ideal orbit distance.

class_name OrbitalBehavior
extends Node

# --- References ---
var owner_enemy: BaseEnemy
var player_node: PlayerCharacter
var enemy_data: EnemyData
var game_node_ref: Node

# --- Timers ---
var _spawn_timer: Timer

# --- State ---
var _orb_slots: Array = [] # Will be a fixed-size array holding orbs or null
var _current_angle: float = 0.0
var _is_initialized: bool = false

func initialize(p_owner_enemy: BaseEnemy):
	if not p_owner_enemy.behavior_tags.has(&"orbital"):
		queue_free() 
		return

	owner_enemy = p_owner_enemy
	player_node = owner_enemy.player_node
	enemy_data = owner_enemy.enemy_data_resource
	game_node_ref = owner_enemy.game_node_ref
	
	# --- SOLUTION: Connect to the owner's tree_exiting signal for cleanup ---
	owner_enemy.tree_exiting.connect(_on_owner_exiting_tree)
	
	_orb_slots.resize(enemy_data.max_orbs)
	_orb_slots.fill(null)
	
	_spawn_timer = Timer.new()
	_spawn_timer.name = "OrbSpawnTimer"
	_spawn_timer.wait_time = enemy_data.orb_spawn_rate
	_spawn_timer.one_shot = false
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	_spawn_timer.start()
	
	_is_initialized = true

# This is the main entry point called by BaseEnemy every physics frame.
func process_behavior(current_velocity: Vector2, delta: float) -> Vector2:
	if not _is_initialized or not is_instance_valid(player_node):
		return Vector2.ZERO

	_update_orb_positions(delta)
	
	if enemy_data.use_predictive_aiming:
		return _process_predictive_movement()
	else:
		return _process_kiting_movement()


func _process_kiting_movement() -> Vector2:
	var distance_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
	var ideal_range = enemy_data.orbit_distance
	var buffer = enemy_data.orbital_comfort_zone_buffer
	
	var comfort_zone_min = ideal_range - buffer
	var comfort_zone_max = ideal_range + buffer
	
	if distance_to_player > comfort_zone_max:
		var direction_to_player = owner_enemy.global_position.direction_to(player_node.global_position)
		return direction_to_player * owner_enemy.speed
	elif distance_to_player < comfort_zone_min:
		var direction_away_from_player = owner_enemy.global_position.direction_to(player_node.global_position) * -1.0
		var flee_speed = owner_enemy.speed * enemy_data.orbital_flee_speed_multiplier
		return direction_away_from_player * flee_speed
	else:
		return Vector2.ZERO

func _process_predictive_movement() -> Vector2:
	if not player_node.has_method("get_current_velocity"):
		push_warning("Orbital enemy cannot use predictive aiming: PlayerCharacter is missing get_current_velocity().")
		return _process_kiting_movement()

	var player_velocity = player_node.get_current_velocity()
	var predicted_player_pos = player_node.global_position + (player_velocity * enemy_data.prediction_time)

	var direction_to_player = owner_enemy.global_position.direction_to(player_node.global_position)
	var attack_vector = direction_to_player.orthogonal()

	var ideal_enemy_pos = predicted_player_pos - (attack_vector * enemy_data.orbit_distance)

	var direction_to_ideal_pos = owner_enemy.global_position.direction_to(ideal_enemy_pos)
	return direction_to_ideal_pos * owner_enemy.speed


func _update_orb_positions(delta: float):
	if not is_instance_valid(owner_enemy):
		return

	_current_angle += enemy_data.orbit_speed * delta
	
	var angle_step = TAU / enemy_data.max_orbs
	
	for i in range(_orb_slots.size()):
		var orb = _orb_slots[i]
		if is_instance_valid(orb):
			var angle = _current_angle + (i * angle_step)
			
			var pulse_factor = (sin(_current_angle * enemy_data.orb_pulse_frequency) + 1.0) / 2.0
			var dynamic_orbit_distance = enemy_data.orbit_distance + (pulse_factor * enemy_data.orb_pulse_magnitude)
			
			var offset = Vector2.RIGHT.rotated(angle) * dynamic_orbit_distance
			orb.global_position = owner_enemy.global_position + offset
			
			var wave = sin((_current_angle + i * angle_step) * enemy_data.orb_wave_frequency) * enemy_data.orb_wave_magnitude
			orb.z_index = owner_enemy.z_index + int(wave)
		else:
			_orb_slots[i] = null

func _on_spawn_timer_timeout():
	var empty_slot_index = -1
	for i in range(_orb_slots.size()):
		if not is_instance_valid(_orb_slots[i]):
			empty_slot_index = i
			break
			
	if empty_slot_index == -1:
		return
		
	if not is_instance_valid(enemy_data.orbital_projectile_scene):
		push_warning("Orbital enemy '", owner_enemy.name, "' is missing its orbital_projectile_scene.")
		return
		
	var orb_instance = enemy_data.orbital_projectile_scene.instantiate() as Area2D
	
	if "damage" in orb_instance:
		orb_instance.damage = enemy_data.orb_damage
	
	var attacks_container = game_node_ref.get_node_or_null("EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OrbitalBehavior: Could not find 'EnemyAttacksContainer' node. Orb not spawned.")
		orb_instance.queue_free()
		return
	
	attacks_container.add_child(orb_instance)
	
	_orb_slots[empty_slot_index] = orb_instance

# --- SOLUTION: New function to handle cleanup when the owner is destroyed ---
func _on_owner_exiting_tree():
	# The owner is being deleted, so we must clean up all active orbs.
	for orb in _orb_slots:
		if is_instance_valid(orb):
			orb.queue_free()
	# This component can now also be safely removed.
	queue_free()
