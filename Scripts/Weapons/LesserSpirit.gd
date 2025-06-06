# LesserSpirit.gd
# Attached to the root Node2D of LesserSpirit.tscn
extends Node2D

# --- Configurable Stats ---
var base_damage: int = 8
var base_fire_interval: float = 1.0 # Seconds between shots
var base_orbit_distance: float = 30.0
var base_orbit_speed: float = 1.0 # Radians per second
var projectile_base_speed: float = 250.0
var projectile_inherent_scale: Vector2 = Vector2(0.05, 0.05) # Example base scale for its projectiles

const PLAYER_TARGETING_RANGE: float = 100.0 # Max distance from PLAYER to acquire target
const PROJECTILE_SCENE_PATH = "res://Scenes/Weapons/Summons/LesserSpiritProjectile.tscn" # ADJUST PATH
var projectile_scene: PackedScene

# --- Player & Target References ---
var player_node: PlayerCharacter 
var current_target: Node2D = null

# --- Internal State ---
var current_orbit_angle: float = 0.0
var final_fire_interval: float = 1.0
var final_damage: int = 8
var final_projectile_speed: float = 250.0
var final_projectile_applied_scale: Vector2 = Vector2(1.0, 1.0)
var final_aoe_scale_for_self: Vector2 = Vector2(1.0, 1.0) # For the spirit's own visual
var final_orbit_speed: float = 1.0 # CORRECTED: Declared
var final_orbit_distance: float = 30.0 # CORRECTED: Declared

# --- Node References ---
@onready var visual: AnimatedSprite2D = get_node_or_null("Visual") as AnimatedSprite2D # Or AnimatedSprite2D
@onready var fire_timer: Timer = get_node_or_null("FireTimer") as Timer
@onready var projectile_spawn_point: Node2D = get_node_or_null("ProjectileSpawnPoint") as Node2D

func _ready():
	projectile_scene = load(PROJECTILE_SCENE_PATH)
	if not projectile_scene:
		print("ERROR (LesserSpirit): Could not load projectile scene at: ", PROJECTILE_SCENE_PATH)
		if is_instance_valid(fire_timer): fire_timer.stop() 
		return

	if not is_instance_valid(player_node): 
		var parent = get_parent()
		if parent is PlayerCharacter:
			player_node = parent
		else:
			print("ERROR (LesserSpirit): Player node not found or not PlayerCharacter type.")
			if is_instance_valid(fire_timer): fire_timer.stop()
			return
	
	if not is_instance_valid(fire_timer):
		print("ERROR (LesserSpirit): FireTimer node not found!")
	else:
		fire_timer.timeout.connect(_on_fire_timer_timeout)

	if not is_instance_valid(projectile_spawn_point):
		print("ERROR (LesserSpirit): ProjectileSpawnPoint node not found!")

	if is_instance_valid(player_node):
		_update_orbit_position() 

	if is_instance_valid(visual) and visual is AnimatedSprite2D:
		if visual.sprite_frames and visual.sprite_frames.has_animation("orbit_loop"): 
			visual.play("orbit_loop")


func _physics_process(delta: float):
	if not is_instance_valid(player_node): return 

	current_orbit_angle += final_orbit_speed * delta 
	current_orbit_angle = fmod(current_orbit_angle, TAU)
	_update_orbit_position()

	if is_instance_valid(visual):
		if is_instance_valid(current_target):
			visual.look_at(current_target.global_position)
		else: 
			var dir_from_player = position.normalized()
			if dir_from_player.length_squared() > 0:
				visual.rotation = dir_from_player.angle() + PI/2.0 
			

func _update_orbit_position():
	position.x = final_orbit_distance * cos(current_orbit_angle)
	position.y = final_orbit_distance * sin(current_orbit_angle)


func set_owner_stats(stats: Dictionary):
	if not is_instance_valid(player_node): 
		var parent = get_parent()
		if parent is PlayerCharacter: player_node = parent
		if not is_instance_valid(player_node):
			print("ERROR (LesserSpirit set_owner_stats): Player node still invalid.")
			return
	
	var weapon_base_damage = stats.get("damage", base_damage) 
	var player_damage_multiplier = stats.get("damage_multiplier", 1.0)
	var player_flat_damage_bonus = stats.get("base_damage_bonus", 0.0)
	final_damage = int(round(weapon_base_damage * player_damage_multiplier + player_flat_damage_bonus))

	var player_attack_speed_multiplier = stats.get("attack_speed_multiplier", 1.0)
	if player_attack_speed_multiplier <= 0: player_attack_speed_multiplier = 0.01
	
	final_fire_interval = stats.get("cooldown", base_fire_interval) / player_attack_speed_multiplier 
	if is_instance_valid(fire_timer):
		fire_timer.wait_time = final_fire_interval
		if fire_timer.is_stopped() or not fire_timer.autostart: fire_timer.start()
		else: fire_timer.stop(); fire_timer.start() 
	
	# Use base_orbit_speed and base_orbit_distance from class variables if not in stats
	final_orbit_speed = stats.get("orbit_speed", base_orbit_speed) * player_attack_speed_multiplier 
	final_orbit_distance = stats.get("orbit_distance", base_orbit_distance) 
	
	if is_instance_valid(visual) and visual is AnimatedSprite2D:
		visual.speed_scale = player_attack_speed_multiplier

	var spirit_inherent_scl_val = stats.get("inherent_visual_scale_pet", Vector2(1.0, 1.0)) 
	var spirit_inherent_base_scale: Vector2
	if spirit_inherent_scl_val is Vector2: spirit_inherent_base_scale = spirit_inherent_scl_val
	elif spirit_inherent_scl_val is float: spirit_inherent_base_scale = Vector2(spirit_inherent_scl_val, spirit_inherent_scl_val)
	else: spirit_inherent_base_scale = Vector2(1.0, 1.0)
	
	var player_aoe_mult = stats.get("aoe_area_multiplier", 1.0) 
	final_aoe_scale_for_self.x = spirit_inherent_base_scale.x * player_aoe_mult
	final_aoe_scale_for_self.y = spirit_inherent_base_scale.y * player_aoe_mult
	if is_instance_valid(visual): visual.scale = final_aoe_scale_for_self

	final_projectile_speed = stats.get("projectile_base_speed", projectile_base_speed) * stats.get("projectile_speed_multiplier", 1.0)
	var proj_inherent_scl_val = stats.get("projectile_inherent_scale", projectile_inherent_scale) 
	var proj_inherent_base_scale : Vector2
	if proj_inherent_scl_val is Vector2: proj_inherent_base_scale = proj_inherent_scl_val
	elif proj_inherent_scl_val is float: proj_inherent_base_scale = Vector2(proj_inherent_scl_val, proj_inherent_scl_val)
	else: proj_inherent_base_scale = projectile_inherent_scale # Use the class var default if not a Vector2
	var player_proj_size_mult = stats.get("projectile_size_multiplier", 1.0)
	final_projectile_applied_scale.x = proj_inherent_base_scale.x * player_proj_size_mult
	final_projectile_applied_scale.y = proj_inherent_base_scale.y * player_proj_size_mult

	# print("DEBUG (LesserSpirit): Stats set. Damage: ", final_damage, " Fire Interval: ", final_fire_interval)


func _on_fire_timer_timeout():
	if not is_instance_valid(player_node): return
	
	_find_target() 
	
	if is_instance_valid(current_target) and is_instance_valid(projectile_spawn_point) and projectile_scene:
		var proj_instance = projectile_scene.instantiate() 
		# Check if the type hint can be applied after instantiation
		if not proj_instance is LesserSpiritProjectile and proj_instance != null: # Check if it's not already the type or null
			# This might not be necessary if projectile_scene is correctly typed, but as a safeguard
			# print_debug("LesserSpirit: proj_instance is not LesserSpiritProjectile, type: ", typeof(proj_instance))
			pass

		var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer") 
		if not is_instance_valid(attacks_container): attacks_container = get_tree().current_scene

		if is_instance_valid(attacks_container):
			attacks_container.add_child(proj_instance)
			proj_instance.global_position = projectile_spawn_point.global_position
			var fire_dir = (current_target.global_position - projectile_spawn_point.global_position).normalized()
			if proj_instance.has_method("setup"): # Check if setup method exists
				proj_instance.setup(fire_dir, final_damage, final_projectile_speed, final_projectile_applied_scale)
			else:
				print("ERROR (LesserSpirit): Projectile instance is missing 'setup' method.")
		else:
			if is_instance_valid(proj_instance): proj_instance.queue_free() 


func _find_target():
	if not is_instance_valid(player_node): return

	var player_pos = player_node.global_position
	
	if is_instance_valid(current_target) and current_target.is_inside_tree():
		if current_target.global_position.distance_squared_to(player_pos) < PLAYER_TARGETING_RANGE * PLAYER_TARGETING_RANGE:
			var target_is_dead = false
			if current_target.has_method("is_dead"): target_is_dead = current_target.is_dead()
			elif current_target.has_method("get_current_health"): target_is_dead = (current_target.get_current_health() <= 0)
			
			if not target_is_dead: return 
		current_target = null 
	else:
		current_target = null

	var potential_targets: Array[Node2D] = []
	var enemies_group = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies_group:
		if is_instance_valid(enemy) and enemy.global_position.distance_squared_to(player_pos) < PLAYER_TARGETING_RANGE * PLAYER_TARGETING_RANGE:
			var enemy_is_dead = false
			if enemy.has_method("is_dead"): enemy_is_dead = enemy.is_dead()
			elif enemy.has_method("get_current_health"): enemy_is_dead = (enemy.get_current_health() <= 0)
			
			if not enemy_is_dead: potential_targets.append(enemy)
	
	if potential_targets.is_empty(): current_target = null; return

	var highest_health_enemy: Node2D = null
	var max_health_found: float = -INF
	for enemy in potential_targets:
		var enemy_health = 0.0
		if enemy.has_method("get_current_health"): enemy_health = float(enemy.get_current_health())
		elif "current_health" in enemy: enemy_health = float(enemy.current_health) 

		if enemy_health > max_health_found:
			max_health_found = enemy_health
			highest_health_enemy = enemy
			
	current_target = highest_health_enemy
