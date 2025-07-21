# File: ReturnFromBeyondController.gd
# Attach to: ReturnFromBeyondController.tscn
# --------------------------------------------------------------------
class_name ReturnFromBeyondController
extends Node2D

@export var echo_scene: PackedScene
@export var portal_scene: PackedScene # Assign SummoningPortal.tscn here in the Inspector

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	if not is_instance_valid(echo_scene) or not is_instance_valid(portal_scene):
		push_error("ReturnFromBeyondController: A required scene is not assigned!")
		queue_free()
		return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	
	var spawn_count = 2 if _specific_stats.get("has_split_manifestation", false) else 1
	var exclude_list: Array[BaseEnemy] = []

	for i in range(spawn_count):
		var target_enemy = _find_best_enemy_cluster(exclude_list)
		var spawn_position: Vector2
		if is_instance_valid(target_enemy):
			spawn_position = target_enemy.global_position
		else:
			var owner_player = _owner_player_stats.get_parent()
			var random_offset = Vector2.RIGHT.rotated(randf_range(0, TAU)) * randf_range(100, 200)
			spawn_position = owner_player.global_position + random_offset
		
		_spawn_portal_and_echo(spawn_position)
		
		if is_instance_valid(target_enemy):
			var nearby_enemies = _get_enemies_in_radius(target_enemy.global_position, 150.0)
			exclude_list.append_array(nearby_enemies)

	queue_free()

func _spawn_portal_and_echo(position: Vector2):
	# First, spawn the portal visual effect
	var portal_instance = portal_scene.instantiate()
	get_tree().current_scene.add_child(portal_instance)
	portal_instance.global_position = position
	
	# Then, spawn the Echo itself
	var echo_instance = echo_scene.instantiate()
	get_tree().current_scene.add_child(echo_instance)
	echo_instance.global_position = position
	if echo_instance.has_method("initialize"):
		echo_instance.initialize(_owner_player_stats.get_parent(), _specific_stats)

func _find_best_enemy_cluster(p_exclude_list: Array[BaseEnemy]) -> BaseEnemy:
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	var best_target: BaseEnemy = null
	var highest_score = 0
	var max_spawn_dist = float(_specific_stats.get("max_spawn_distance_from_player", 600.0))
	var owner_player_pos = _owner_player_stats.get_parent().global_position

	for enemy in all_enemies:
		if not (enemy is BaseEnemy) or enemy.is_dead() or p_exclude_list.has(enemy):
			continue
		if owner_player_pos.distance_to(enemy.global_position) > max_spawn_dist:
			continue

		var current_score = 1 + _get_enemies_in_radius(enemy.global_position, 150.0, p_exclude_list).size()

		if current_score > highest_score:
			highest_score = current_score
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
