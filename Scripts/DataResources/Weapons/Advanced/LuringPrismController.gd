# File: LuringPrismController.gd
# Attach to: LuringPrismController.tscn (root Node2D)
# --------------------------------------------------------------------
class_name LuringPrismController
extends Node2D

# In the Godot Inspector, assign your LuringPrismProjectile.tscn scene to this variable.
@export var projectile_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager

# This is the main entry point, called by WeaponManager.
func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	if not is_instance_valid(projectile_scene):
		push_error("LuringPrismController: Projectile Scene is not assigned! Aborting attack.")
		queue_free()
		return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	var owner_player = _owner_player_stats.get_parent()

	# --- Target Finding Logic ---
	var main_target = _find_best_enemy_cluster()
	if not is_instance_valid(main_target):
		queue_free() # No valid targets, do nothing.
		return

	# Spawn the primary projectile
	_spawn_projectile(main_target)

	# --- Hidden Knife Upgrade Logic ---
	if _specific_stats.get("has_hidden_knife", false):
		# Find the nearest enemy, excluding the main target to avoid overlap.
		var secondary_target = owner_player._find_nearest_enemy(owner_player.global_position, [main_target])
		if is_instance_valid(secondary_target):
			_spawn_projectile(secondary_target)

	# The controller's job is done after spawning the projectile(s).
	queue_free()

func _find_best_enemy_cluster() -> BaseEnemy:
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	var best_target: BaseEnemy = null
	var highest_score = -1
	var cluster_radius_sq = 200 * 200 # Check for other enemies within a 200px radius.

	for enemy in all_enemies:
		if not (enemy is BaseEnemy) or enemy.is_dead():
			continue

		var current_score = 1
		for other_enemy in all_enemies:
			if enemy == other_enemy or not (other_enemy is BaseEnemy) or other_enemy.is_dead():
				continue
			if enemy.global_position.distance_squared_to(other_enemy.global_position) < cluster_radius_sq:
				current_score += 1

		if current_score > highest_score:
			highest_score = current_score
			best_target = enemy

	return best_target

func _spawn_projectile(target_enemy: BaseEnemy):
	var owner_player = _owner_player_stats.get_parent()
	var projectile = projectile_scene.instantiate()
	
	# Add to a container to keep the scene tree clean
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(projectile)
	else:
		get_tree().current_scene.add_child(projectile) # Fallback

	projectile.global_position = owner_player.global_position
	
	if projectile.has_method("initialize"):
		projectile.initialize(target_enemy, _specific_stats, _owner_player_stats)
