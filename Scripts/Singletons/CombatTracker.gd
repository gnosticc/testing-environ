# File: res://Scripts/Singletons/CombatTracker.gd
# Purpose: A global singleton to track combat events, like last hit times.
# Add this as an Autoload named "CombatTracker" in Project Settings.

extends Node

# Structure: { weapon_id: { enemy_instance_id: timestamp_usec } }
var _last_hit_times_by_weapon: Dictionary = {}

# Called by WeaponManager or attack scripts to record a hit.
# weapon_id: The StringName ID of the weapon that hit.
# enemy_node: The actual enemy node that was hit.
func record_hit(weapon_id: StringName, enemy_node: Node):
	if not is_instance_valid(enemy_node):
		return
		
	var enemy_instance_id = enemy_node.get_instance_id()
	
	if not _last_hit_times_by_weapon.has(weapon_id):
		_last_hit_times_by_weapon[weapon_id] = {}
		
	# Store the time in microseconds for higher precision.
	_last_hit_times_by_weapon[weapon_id][enemy_instance_id] = Time.get_ticks_usec()
	
	# Optional: Clean up old entries periodically if memory becomes a concern.
	# For now, this is simple and effective.

# Called by an attack script to check if an enemy was recently hit by a specific weapon.
# returns: true if the enemy was hit by that weapon within the time window, false otherwise.
func was_enemy_hit_by_weapon_within_seconds(weapon_id: StringName, enemy_node: Node, time_window_seconds: float) -> bool:
	if not is_instance_valid(enemy_node):
		return false

	var enemy_instance_id = enemy_node.get_instance_id()

	if not _last_hit_times_by_weapon.has(weapon_id):
		return false
	
	if not _last_hit_times_by_weapon[weapon_id].has(enemy_instance_id):
		return false
		
	var last_hit_time_usec = _last_hit_times_by_weapon[weapon_id][enemy_instance_id]
	var current_time_usec = Time.get_ticks_usec()
	
	var time_diff_seconds = float(current_time_usec - last_hit_time_usec) / 1000000.0
	
	return time_diff_seconds <= time_window_seconds
