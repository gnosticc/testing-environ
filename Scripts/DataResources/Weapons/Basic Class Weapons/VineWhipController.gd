# File: res://Scripts/Weapons/Controllers/VineWhipController.gd
# REVISED: Logic simplified. It no longer needs to know how to reset the counter.

class_name VineWhipController
extends Node2D

@export var whip_attack_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	if not is_instance_valid(whip_attack_scene):
		push_error("VineWhipController ERROR: whip_attack_scene is not assigned! Aborting attack."); queue_free(); return
	
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats

	# --- Nature's Fury (Proc Chance) ---
	if _specific_stats.get(&"has_natures_fury", false):
		var proc_chance = float(_specific_stats.get(&"natures_fury_proc_chance", 0.0))
		if randf() < proc_chance:
			# Use a timer to delay the second attack for visual clarity.
			get_tree().create_timer(0.2).timeout.connect(_spawn_whip_instance.bind(direction, _specific_stats))

	# --- Wrath of the Wilds (Nth Attack) ---
	var is_wrath_attack = false
	if _specific_stats.get(&"has_wrath_of_the_wilds", false):
		var attack_count = _specific_stats.get("shot_counter", 0)
		if attack_count >= 4:
			is_wrath_attack = true
			# This controller no longer resets the count. WeaponManager does.
	
	if is_wrath_attack:
		_execute_wrath_of_the_wilds()
	else:
		_execute_normal_whip(direction)
	
	# Don't queue_free immediately; let the Nature's Fury timer fire if it needs to.
	get_tree().create_timer(0.3).timeout.connect(queue_free)

func _execute_normal_whip(direction: Vector2):
	_spawn_whip_instance(direction, _specific_stats)

func _execute_wrath_of_the_wilds():
	var number_of_whips = 8
	var angle_step = TAU / float(number_of_whips)
	for i in range(number_of_whips):
		var whip_direction = Vector2.RIGHT.rotated(i * angle_step)
		_spawn_whip_instance(whip_direction, _specific_stats)
		
func _spawn_whip_instance(direction: Vector2, stats_to_pass: Dictionary):
	if not is_instance_valid(self): return # Controller might have been freed.
	
	var owner_player = _owner_player_stats.get_parent()
	if not is_instance_valid(owner_player) or not is_instance_valid(whip_attack_scene): return

	var whip_instance = whip_attack_scene.instantiate()
	owner_player.add_child(whip_instance)
	
	if is_instance_valid(owner_player.melee_aiming_dot):
		whip_instance.global_position = owner_player.melee_aiming_dot.global_position
	else:
		whip_instance.global_position = owner_player.global_position
	
	if whip_instance.has_method("set_attack_properties"):
		whip_instance.set_attack_properties(direction, stats_to_pass, _owner_player_stats)
	
	# Connect the signal for Constricting Grip to work
	if not whip_instance.is_connected("enemy_hit", _on_whip_enemy_hit):
		whip_instance.enemy_hit.connect(_on_whip_enemy_hit)

# Handler for the enemy_hit signal
func _on_whip_enemy_hit(enemy_node: Node):
	# Call the global CombatTracker to record the hit
	if is_instance_valid(enemy_node):
		CombatTracker.record_hit(&"druid_vine_whip", enemy_node)
