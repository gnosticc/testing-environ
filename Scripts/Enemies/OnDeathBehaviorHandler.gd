# OnDeathBehaviorHandler.gd
# A component that executes various on-death effects based on the owner's behavior tags.
# VERSION 2.2: Corrected "link" targeting to ensure multiple projectiles seek unique targets.

class_name OnDeathBehaviorHandler
extends Node

# --- Node References ---
var owner_enemy: BaseEnemy
var player_node: PlayerCharacter
var enemy_data: EnemyData
var game_node_ref: Node

# --- Creeper State ---
var _creeper_bullets_to_fire: int = 0
var _creeper_fire_timer: Timer

# --- Public API ---

func initialize(p_owner_enemy: BaseEnemy):
	owner_enemy = p_owner_enemy
	player_node = owner_enemy.player_node
	enemy_data = owner_enemy.enemy_data_resource
	game_node_ref = owner_enemy.game_node_ref

func execute_on_death_effects():
	if not is_instance_valid(owner_enemy): return

	var tags = owner_enemy.behavior_tags
	
	if tags.has(&"slime"):
		_handle_slime_split()
	
	if tags.has(&"creeper"):
		_handle_creeper_bullets()
		
	if tags.has(&"berserker"):
		_handle_berserker_wave()
		
	if tags.has(&"link"):
		_handle_link_heal()

# --- Private Behavior Functions ---

func _handle_slime_split():
	# ... (This function is unchanged) ...
	print_debug("OnDeath: Handling slime split for '", owner_enemy.name, "'")
	if not is_instance_valid(game_node_ref) or not is_instance_valid(enemy_data):
		print_debug(" - Slime split failed: Game node or enemy data is invalid.")
		return
	
	var minion_id_to_spawn = enemy_data.split_enemy_id
	var spawn_count = enemy_data.split_count
	
	print_debug(" - Attempting to spawn ", spawn_count, " minions with ID: '", minion_id_to_spawn, "'")
	if minion_id_to_spawn == &"" or spawn_count <= 0:
		print_debug(" - Slime split failed: Minion ID is blank or spawn count is zero.")
		return

	var minion_data_original = game_node_ref.get_enemy_data_by_id(minion_id_to_spawn)

	if not is_instance_valid(minion_data_original):
		print_debug(" - Slime split failed: Could not find EnemyData for ID '", minion_id_to_spawn, "' in game.gd.")
		return
	
	var minion_scene = load(minion_data_original.scene_path) as PackedScene
	if not is_instance_valid(minion_scene):
		print_debug(" - Slime split failed: Scene path '", minion_data_original.scene_path, "' is invalid or could not be loaded.")
		return
	
	print_debug(" - Successfully found data and scene. Spawning minions.")
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

func _handle_creeper_bullets():
	if not is_instance_valid(enemy_data) or not is_instance_valid(enemy_data.creeper_bullet_scene):
		push_warning("Creeper enemy '", owner_enemy.name, "' is missing its creeper_bullet_scene in its EnemyData.")
		return
	
	var telegraph_sprite = Sprite2D.new()
	telegraph_sprite.texture = owner_enemy.animated_sprite.sprite_frames.get_frame_texture(&"idle", 0)
	telegraph_sprite.global_position = owner_enemy.global_position
	telegraph_sprite.scale = owner_enemy.scale * owner_enemy.animated_sprite.scale
	telegraph_sprite.modulate = owner_enemy._final_base_modulate_color
	add_child(telegraph_sprite)

	var tween = create_tween().set_loops(int(enemy_data.creeper_telegraph_duration / 0.4))
	tween.tween_property(telegraph_sprite, "modulate", Color.RED, 0.2)
	tween.tween_property(telegraph_sprite, "modulate", owner_enemy._final_base_modulate_color, 0.2)
	
	var telegraph_timer = get_tree().create_timer(enemy_data.creeper_telegraph_duration)
	telegraph_timer.timeout.connect(_start_creeper_sequence.bind(telegraph_sprite))

func _start_creeper_sequence(telegraph_sprite: Sprite2D):
	if is_instance_valid(telegraph_sprite):
		telegraph_sprite.queue_free()

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
		if is_instance_valid(_creeper_fire_timer):
			_creeper_fire_timer.queue_free()
		return

	var bullet_scene = enemy_data.creeper_bullet_scene
	var bullet_speed = enemy_data.creeper_bullet_speed
	var bullet_damage = enemy_data.creeper_bullet_damage
	var total_bullets = enemy_data.creeper_bullet_count
	
	var attacks_container = get_tree().root.get_node_or_null("Game/EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OnDeathBehaviorHandler: Could not find 'EnemyAttacksContainer' node. Bullets will not be spawned.")
		if is_instance_valid(_creeper_fire_timer):
			_creeper_fire_timer.queue_free()
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
	# ... (This function is unchanged) ...
	print_debug("Berserker wave triggered!")

func _handle_link_heal():
	if not is_instance_valid(enemy_data) or not is_instance_valid(enemy_data.link_heal_projectile_scene):
		push_warning("Link enemy '", owner_enemy.name, "' is missing its link_heal_projectile_scene in its EnemyData.")
		return

	var space_state = owner_enemy.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = enemy_data.link_search_radius
	query.transform = Transform2D(0, owner_enemy.global_position)
	# Assuming enemies are on physics layer 8
	query.collision_mask = 8 
	
	var results = space_state.intersect_shape(query)
	
	var valid_targets: Array[BaseEnemy] = []
	for result in results:
		var enemy = result.collider as BaseEnemy
		if is_instance_valid(enemy) and enemy != owner_enemy and not enemy.is_dead():
			if enemy.get_current_health() < enemy.max_health:
				valid_targets.append(enemy)

	if valid_targets.is_empty():
		return # No one to heal.

	# --- SOLUTION: Ensure unique targets ---
	# 1. Shuffle the list of potential targets to randomize who gets healed first.
	valid_targets.shuffle()
	
	# 2. Determine how many projectiles to actually fire.
	var projectile_count = min(valid_targets.size(), enemy_data.link_projectile_count)
	
	# 3. Take a "slice" of the shuffled array to get a unique list of targets.
	var final_targets = valid_targets.slice(0, projectile_count -1)
	# --- END SOLUTION ---
	
	var attacks_container = get_tree().root.get_node_or_null("Game/EnemyAttacksContainer")
	if not is_instance_valid(attacks_container):
		push_error("OnDeathBehaviorHandler: Could not find 'EnemyAttacksContainer' node. Link projectiles will not be spawned.")
		return

	# 4. Spawn a projectile for each unique target.
	for target in final_targets:
		var heal_amount = owner_enemy.max_health * enemy_data.link_heal_percent
		
		var projectile_instance = enemy_data.link_heal_projectile_scene.instantiate()
		attacks_container.add_child(projectile_instance)
		
		if projectile_instance.has_method("initialize"):
			projectile_instance.initialize(owner_enemy.global_position, target, heal_amount, owner_enemy)
		else:
			projectile_instance.global_position = owner_enemy.global_position
