# File: ChakramController.gd
# Attach to: ChakramController.tscn (root Node2D)
# Purpose: This controller is the main entry point for the Sylvan Chakram attack.
# It is spawned by WeaponManager and handles the logic for spawning the primary
# chakram and the second one for the "Mirrored Strike" upgrade.
# REVISED: Now passes its own scene resource to the projectile's initialize function.

class_name ChakramController
extends Node2D

# Assign the SylvanChakramProjectile.tscn scene in the Godot Inspector.
@export var chakram_projectile_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager

# This is the main entry point, called by WeaponManager.
func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	if not is_instance_valid(chakram_projectile_scene):
		push_error("ChakramController: Chakram Projectile Scene is not assigned! Aborting attack.")
		queue_free()
		return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	
	# --- NEW: Fixed Directional Logic ---
	# Determine direction based on the shot counter provided by WeaponManager.
	var shot_index = int(_specific_stats.get("shot_counter", 1)) % 4
	var fire_direction: Vector2
	match shot_index:
		0: fire_direction = Vector2.LEFT
		1: fire_direction = Vector2.DOWN
		2: fire_direction = Vector2.RIGHT
		3: fire_direction = Vector2.UP

	# Spawn the primary chakram immediately.
	_spawn_chakram_instance(fire_direction, false)

	# If the Mirrored Strike upgrade is active, spawn the second chakram after a short delay.
	if _specific_stats.get("has_mirrored_strike", false):
		var delay = float(_specific_stats.get("mirrored_strike_delay", 0.2))
		# Use a timer to spawn the second projectile.
		get_tree().create_timer(delay, true, false, true).timeout.connect(_spawn_chakram_instance.bind(fire_direction, true))
	
	# The controller's only job is to spawn the projectiles, so it can be freed shortly after.
	# The delay should be slightly longer than the Mirrored Strike delay to ensure it can fire.
	get_tree().create_timer(0.3, true, false, true).timeout.connect(queue_free)

# Spawns a single instance of the Sylvan Chakram projectile.
func _spawn_chakram_instance(direction: Vector2, is_mirrored: bool):
	# Failsafe in case the controller is freed before the timer fires.
	if not is_instance_valid(self): return

	var owner_player = _owner_player_stats.get_parent()
	if not is_instance_valid(owner_player): return

	var projectile_instance = chakram_projectile_scene.instantiate()
	
	# Add the projectile to a container in the main scene to keep the tree clean.
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(projectile_instance)
	else:
		get_tree().current_scene.add_child(projectile_instance) # Fallback

	projectile_instance.global_position = owner_player.global_position
	
	# Pass all necessary data to the projectile instance.
	if projectile_instance.has_method("initialize"):
		var stats_to_pass = _specific_stats.duplicate(true)
		# Add a flag to tell the projectile if it should use a mirrored arc.
		stats_to_pass["is_mirrored_arc"] = is_mirrored
		# FIX: Pass the scene resource as the fifth argument.
		projectile_instance.initialize(direction, stats_to_pass, _owner_player_stats, _weapon_manager, chakram_projectile_scene)
