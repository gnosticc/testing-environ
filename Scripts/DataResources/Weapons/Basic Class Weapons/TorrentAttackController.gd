# File: res://Scripts/Weapons/Controllers/TorrentAttackController.gd
# REVISED: Reads min/max distance for Flash Flood from stats.
class_name TorrentAttackController
extends Node2D

@export var torrent_attack_scene: PackedScene

var _weapon_manager: WeaponManager # Reference to call back for cooldown reduction

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	if not is_instance_valid(torrent_attack_scene):
		push_error("TorrentAttackController: Torrent Attack Scene not assigned!"); queue_free(); return
		
	_weapon_manager = _p_weapon_manager
	
	# Spawn the primary torrent at the target location
	_spawn_torrent(p_attack_stats, p_player_stats)
	
	# If Flash Flood is active, spawn a second one nearby
	if p_attack_stats.get(&"has_flash_flood", false):
		var second_torrent_stats = p_attack_stats.duplicate(true)
		var offset_direction = Vector2.RIGHT.rotated(randf_range(0, TAU))
		
		# NEW: Use data-driven distance values
		var min_dist = float(p_attack_stats.get(&"flash_flood_min_distance", 70.0))
		var max_dist = float(p_attack_stats.get(&"flash_flood_max_distance", 150.0))
		var offset_distance = randf_range(min_dist, max_dist)
		
		second_torrent_stats["spawn_offset"] = offset_direction * offset_distance
		
		_spawn_torrent(second_torrent_stats, p_player_stats)
		
	queue_free()

func _spawn_torrent(stats: Dictionary, p_player_stats: PlayerStats):
	var torrent_instance = torrent_attack_scene.instantiate()
	
	# Add to a container to keep the scene tree clean
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(torrent_instance)
	else:
		get_tree().current_scene.add_child(torrent_instance)
		
	# The base torrent position is already set by WeaponManager at the mouse cursor.
	# We just apply the random offset if it exists.
	var offset = stats.get("spawn_offset", Vector2.ZERO)
	torrent_instance.global_position = self.global_position + offset

	if torrent_instance.has_method("set_attack_properties"):
		torrent_instance.set_attack_properties(Vector2.ZERO, stats, p_player_stats, _weapon_manager)
