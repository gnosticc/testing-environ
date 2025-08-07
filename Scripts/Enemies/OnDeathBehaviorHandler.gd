# OnDeathBehaviorHandler.gd
# A component that executes various on-death effects based on the owner's behavior tags.
# VERSION 3.5: Corrected lifecycle management to prevent premature deletion before deferred calls can execute.

class_name OnDeathBehaviorHandler
extends Node

# --- Node References ---
var owner_enemy: BaseEnemy
var player_node: PlayerCharacter
var enemy_data: EnemyData
var game_node_ref: Node

# --- State ---
var _creeper_bullets_to_fire: int = 0
var _creeper_fire_timer: Timer

# --- Public API ---

func initialize(p_owner_enemy: BaseEnemy):
	owner_enemy = p_owner_enemy
	player_node = owner_enemy.player_node
	enemy_data = owner_enemy.enemy_data_resource
	game_node_ref = owner_enemy.game_node_ref

func execute_on_death_effects() -> float:
	if not is_instance_valid(owner_enemy) or not is_instance_valid(enemy_data): 
		queue_free() 
		return 0.0

	var tags = owner_enemy.behavior_tags
	var max_duration_needed: float = 0.0
	
	if tags.has(&"slime"):
		if randf() < enemy_data.slime_proc_chance:
			call_deferred("_handle_slime_split")
	
	if tags.has(&"creeper"):
		if randf() < enemy_data.creeper_proc_chance:
			var creeper_duration = _handle_creeper_bullets()
			max_duration_needed = max(max_duration_needed, creeper_duration)
		
	if tags.has(&"berserker"):
		if randf() < enemy_data.berserker_proc_chance:
			call_deferred("_handle_berserker_wave")
		
	if tags.has(&"link"):
		if randf() < enemy_data.link_proc_chance:
			call_deferred("_handle_link_heal")
			
	if tags.has(&"corpse_explosion"):
		if randf() < enemy_data.corpse_explosion_proc_chance:
			var explosion_duration = _handle_corpse_explosion()
			max_duration_needed = max(max_duration_needed, explosion_duration)

	if tags.has(&"gravity"):
		if randf() < enemy_data.gravity_well_proc_chance:
			var gravity_duration = _handle_gravity_well()
			max_duration_needed = max(max_duration_needed, gravity_duration)

	# --- SOLUTION: Removed premature queue_free() ---
	# This node will now persist as a child of the dying BaseEnemy. It will be freed
	# automatically when the BaseEnemy's own delayed queue_free() is called.
	# This ensures that any deferred calls made from this function have time to execute.
	
	return max_duration_needed

# --- Private Behavior Functions ---

func _handle_slime_split():
	if not is_instance_valid(owner_enemy): return
	if not is_instance_valid(game_node_ref) or not is_instance_valid(enemy_data): return
	var minion_id_to_spawn = enemy_data.split_enemy_id
	var spawn_count = enemy_data.split_count
	if minion_id_to_spawn == &"" or spawn_count <= 0: return
	var minion_data_original = game_node_ref.get_enemy_data_by_id(minion_id_to_spawn)
	if not is_instance_valid(minion_data_original): return
	var minion_scene = load(minion_data_original.scene_path) as PackedScene
	if not is_instance_valid(minion_scene): return
	for i in range(spawn_count):
		var modified_minion_data = minion_data_original.duplicate()
		modified_minion_data.base_health = owner_enemy.max_health * 0.5
		if modified_minion_data.behavior_tags.has(&"slime"):
			modified_minion_data.behavior_tags.erase(&"slime")
		modified_minion_data.base_exp_drop = 0
		var minion_instance = minion_scene.instantiate() as BaseEnemy
		var spawn_offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		minion_instance.global_position = owner_enemy.global_position + spawn_offset
		minion_instance.scale = owner_enemy.scale * enemy_data.split_scale_multiplier
		var parent_container = owner_enemy.get_parent() if is_instance_valid(owner_enemy.get_parent()) else get_tree().current_scene
		if is_instance_valid(parent_container):
			parent_container.add_child(minion_instance)
			minion_instance.initialize_from_data(modified_minion_data)
		else:
			minion_instance.queue_free()

func _handle_creeper_bullets() -> float:
	if not is_instance_valid(enemy_data) or not is_instance_valid(enemy_data.creeper_bullet_scene):
		push_warning("Creeper enemy '", owner_enemy.name, "' is missing its creeper_bullet_scene in its EnemyData.")
		return 0.0
	var telegraph_duration = enemy_data.creeper_telegraph_duration
	var fire_interval = enemy_data.creeper_fire_interval
	var bullet_count = enemy_data.creeper_bullet_count
	var total_fire_duration = fire_interval * float(bullet_count)
	if owner_enemy.has_method("play_on_death_telegraph"):
		owner_enemy.play_on_death_telegraph(telegraph_duration)
	var telegraph_timer = get_tree().create_timer(telegraph_duration)
	telegraph_timer.timeout.connect(_start_creeper_sequence)
	return telegraph_duration + total_fire_duration

func _start_creeper_sequence():
	if not is_instance_valid(owner_enemy): return
	_creeper_bullets_to_fire = enemy_data.creeper_bullet_count
	_creeper_fire_timer = Timer.new()
	_creeper_fire_timer.name = "CreeperFireTimer"
	_creeper_fire_timer.wait_time = enemy_data.creeper_fire_interval
	_creeper_fire_timer.one_shot = false
	add_child(_creeper_fire_timer)
	_creeper_fire_timer.timeout.connect(_fire_one_creeper_bullet)
	_creeper_fire_timer.start()

func _fire_one_creeper_bullet():
	if _creeper_bullets_to_fire <= 0:
		if is_instance_valid(_creeper_fire_timer): _creeper_fire_timer.queue_free()
		return
	if not is_instance_valid(owner_enemy): return
	var bullet_scene = enemy_data.creeper_bullet_scene
	var bullet_speed = enemy_data.creeper_bullet_speed
	var bullet_damage = enemy_data.creeper_bullet_damage
	var total_bullets = enemy_data.creeper_bullet_count
	var attacks_container = game_node_ref.get_node_or_null("EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OnDeathBehaviorHandler: Could not find 'EnemyAttacksContainer' node in Game scene. Bullets will not be spawned.")
		if is_instance_valid(_creeper_fire_timer): _creeper_fire_timer.queue_free()
		return
	var current_bullet_index = total_bullets - _creeper_bullets_to_fire
	var angle_step = TAU / total_bullets
	var angle = current_bullet_index * angle_step
	var direction = Vector2.UP.rotated(angle)
	var bullet_instance = bullet_scene.instantiate()
	attacks_container.add_child(bullet_instance)
	if bullet_instance.has_method("initialize"):
		bullet_instance.initialize(owner_enemy.global_position, direction, bullet_speed, bullet_damage)
	else:
		bullet_instance.global_position = owner_enemy.global_position
	_creeper_bullets_to_fire -= 1

func _handle_berserker_wave():
	if not is_instance_valid(owner_enemy): return
	if not is_instance_valid(enemy_data) or not is_instance_valid(enemy_data.berserker_wave_scene) or not is_instance_valid(enemy_data.berserker_buff_data):
		push_warning("Berserker enemy '", owner_enemy.name, "' is missing required data (wave scene or buff data).")
		return
	var attacks_container = game_node_ref.get_node_or_null("EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OnDeathBehaviorHandler: Could not find 'EnemyAttacksContainer' node. Berserker wave will not be spawned.")
		return
	var wave_instance = enemy_data.berserker_wave_scene.instantiate()
	attacks_container.add_child(wave_instance)
	wave_instance.global_position = owner_enemy.global_position
	if wave_instance.has_method("initialize"):
		wave_instance.initialize(enemy_data.berserker_wave_radius, enemy_data.berserker_buff_data, owner_enemy)

func _handle_link_heal():
	if not is_instance_valid(owner_enemy): return
	if not is_instance_valid(enemy_data) or not is_instance_valid(enemy_data.link_heal_projectile_scene):
		push_warning("Link enemy '", owner_enemy.name, "' is missing its link_heal_projectile_scene in its EnemyData.")
		return
	var space_state = owner_enemy.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = enemy_data.link_search_radius
	query.transform = Transform2D(0, owner_enemy.global_position)
	query.collision_mask = 8 
	var results = space_state.intersect_shape(query)
	var valid_targets: Array[BaseEnemy] = []
	for result in results:
		var enemy = result.collider as BaseEnemy
		if is_instance_valid(enemy) and enemy != owner_enemy and not enemy.is_dead():
			if enemy.get_current_health() < enemy.max_health:
				valid_targets.append(enemy)
	if valid_targets.is_empty(): return
	valid_targets.shuffle()
	var projectile_count = min(valid_targets.size(), enemy_data.link_projectile_count)
	var final_targets = valid_targets.slice(0, projectile_count)
	var attacks_container = game_node_ref.get_node_or_null("EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OnDeathBehaviorHandler: Could not find 'EnemyAttacksContainer' node. Link projectiles will not be spawned.")
		return
	for i in range(final_targets.size()):
		var target = final_targets[i]
		var heal_amount = owner_enemy.max_health * enemy_data.link_heal_percent
		var start_pos = owner_enemy.global_position
		var end_pos = target.global_position
		var mid_point = (start_pos + end_pos) / 2.0
		var perpendicular = (end_pos - start_pos).orthogonal().normalized()
		var offset_direction = 1 if i % 2 == 0 else -1
		var control_point = mid_point + perpendicular * enemy_data.link_arc_height * offset_direction
		var projectile_instance = enemy_data.link_heal_projectile_scene.instantiate()
		attacks_container.add_child(projectile_instance)
		if projectile_instance.has_method("initialize"):
			projectile_instance.initialize(start_pos, target, heal_amount, control_point)
		else:
			projectile_instance.global_position = start_pos

func _handle_corpse_explosion() -> float:
	if not is_instance_valid(enemy_data) or not is_instance_valid(enemy_data.corpse_explosion_scene):
		push_warning("Corpse Explosion enemy '", owner_enemy.name, "' is missing its corpse_explosion_scene in its EnemyData.")
		return 0.0
	
	var telegraph_duration = enemy_data.corpse_explosion_telegraph_duration
	
	if owner_enemy.has_method("play_on_death_telegraph"):
		owner_enemy.play_on_death_telegraph(telegraph_duration)
	
	var telegraph_timer = get_tree().create_timer(telegraph_duration)
	telegraph_timer.timeout.connect(_spawn_corpse_explosion)
	
	return telegraph_duration

func _spawn_corpse_explosion():
	if not is_instance_valid(owner_enemy): return

	var explosion_scene = enemy_data.corpse_explosion_scene
	var explosion_damage = enemy_data.corpse_explosion_damage
	var explosion_radius = enemy_data.corpse_explosion_radius
	
	var attacks_container = game_node_ref.get_node_or_null("EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OnDeathBehaviorHandler: Could not find 'EnemyAttacksContainer' node. Corpse explosion will not be spawned.")
		return

	var explosion_instance = explosion_scene.instantiate()
	attacks_container.add_child(explosion_instance)
	explosion_instance.global_position = owner_enemy.global_position
	
	if explosion_instance.has_method("initialize"):
		explosion_instance.initialize(explosion_damage, explosion_radius)

func _handle_gravity_well() -> float:
	if not is_instance_valid(enemy_data) or not is_instance_valid(enemy_data.gravity_well_scene):
		push_warning("Gravity Well enemy '", owner_enemy.name, "' is missing its gravity_well_scene in its EnemyData.")
		return 0.0
	
	var telegraph_duration = enemy_data.gravity_well_telegraph_duration
	
	if owner_enemy.has_method("play_on_death_telegraph"):
		owner_enemy.play_on_death_telegraph(telegraph_duration)
	
	# DIAGNOSTIC PRINT 1: Check the values from the .tres file right before creating the timer.
	print_debug("--- OnDeathBehaviorHandler: _handle_gravity_well ---")
	print_debug("  - Reading from EnemyData: ", enemy_data.resource_path)
	print_debug("  - Radius from .tres: ", enemy_data.gravity_well_radius)
	print_debug("  - Strength from .tres: ", enemy_data.gravity_well_strength)
	print_debug("  - Duration from .tres: ", enemy_data.gravity_well_pull_duration)
	print_debug("  - Setting up timer for ", telegraph_duration, " seconds.")
	
	var telegraph_timer = get_tree().create_timer(telegraph_duration)
	telegraph_timer.timeout.connect(_spawn_gravity_well.call_deferred)
	
	return telegraph_duration

func _spawn_gravity_well():
	# DIAGNOSTIC PRINT 2: Confirm that this function is actually being called.
	print_debug("--- OnDeathBehaviorHandler: _spawn_gravity_well ---")
	print_debug("  - This function was successfully called after the timer.")

	if not is_instance_valid(owner_enemy): 
		print_debug("  - ABORTING: Owner enemy is no longer valid.")
		return

	var well_scene = enemy_data.gravity_well_scene
	
	var attacks_container = game_node_ref.get_node_or_null("EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OnDeathBehaviorHandler: Could not find 'EnemyAttacksContainer' node. Gravity Well will not be spawned.")
		return

	var well_instance = well_scene.instantiate()
	attacks_container.add_child(well_instance)
	well_instance.global_position = owner_enemy.global_position
	
	# Pass all the tunable parameters from EnemyData to the new instance.
	if well_instance.has_method("initialize"):
		# DIAGNOSTIC PRINT 3: Log the values being passed to the GravityWell's initialize function.
		print_debug("  - Calling initialize() on new GravityWell instance with:")
		print_debug("    - Radius: ", enemy_data.gravity_well_radius)
		print_debug("    - Strength: ", enemy_data.gravity_well_strength)
		print_debug("    - Duration: ", enemy_data.gravity_well_pull_duration)
		well_instance.initialize(
			enemy_data.gravity_well_radius,
			enemy_data.gravity_well_strength,
			enemy_data.gravity_well_pull_duration
		)
