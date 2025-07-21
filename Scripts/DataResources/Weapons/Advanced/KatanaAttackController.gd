# File: res://Scripts/Weapons/KatanaAttackController.gd
# This controller manages the Katana's combo sequence, Focus stacks,
# and triggers for special upgrades.
# FIX: Moved Blade of the Gale trigger to spawn on final hit creation, not on impact.
# FIX: Phantom Step now applies a pre-defined status effect resource.
# FIX: Correctly calculates the spawn position and direction for the mirrored attack
#      from the "Thousand Year Cherry Blossom" upgrade.
# FIX: Corrected the resource path for the Phantom Step buff to load the correct StatusEffectData file.

class_name KatanaAttackController
extends Node2D

@export var katana_attack_scene: PackedScene
@export var gale_wave_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _base_direction: Vector2
var _attack_sequence: Array

# --- Focus Mechanic Tracking ---
# Structure: { enemy_instance_id: {"stacks": int, "timestamp": float} }
var _focus_tracker: Dictionary = {}
var _focus_reset_timer: Timer

func _ready():
	# This timer will periodically clean up expired Focus stacks.
	_focus_reset_timer = Timer.new()
	_focus_reset_timer.name = "FocusResetTimer"
	_focus_reset_timer.wait_time = 1.0 # Check every second
	_focus_reset_timer.autostart = true
	_focus_reset_timer.timeout.connect(_check_focus_expiration)
	add_child(_focus_reset_timer)

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	if not is_instance_valid(katana_attack_scene):
		push_error("KatanaAttackController: Katana Attack Scene is not assigned!"); queue_free(); return
	
	_specific_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats
	_base_direction = direction
	_attack_sequence = _specific_stats.get("attack_sequence", [])
	
	_execute_attack_sequence()
	
	# Self-destruct after the full combo duration has passed
	var total_duration = 0.0
	for hit_data in _attack_sequence:
		total_duration += float(hit_data.get("delay", 0.0))
	var last_slash_duration = float(_specific_stats.get("base_attack_duration", 0.25))
	get_tree().create_timer(total_duration + last_slash_duration + 0.1, true, false, true).timeout.connect(queue_free)

func _execute_attack_sequence():
	var cumulative_delay = 0.0
	for i in range(_attack_sequence.size()):
		var hit_data = _attack_sequence[i]
		cumulative_delay += float(hit_data.get("delay", 0.0))
		var timer = get_tree().create_timer(cumulative_delay)
		# Bind all necessary info for when the timer fires
		timer.timeout.connect(_spawn_single_slash.bind(i, hit_data))

func _spawn_single_slash(hit_index: int, hit_data: Dictionary):
	if not is_instance_valid(self): return # Controller might have been freed

	var owner_player = _owner_player_stats.get_parent()
	var rotation_offset = deg_to_rad(float(hit_data.get("rotation_offset", 0.0)))
	var slash_direction = _base_direction.rotated(rotation_offset)

	# Main attack
	_spawn_slash_instance(slash_direction, hit_data, hit_index, owner_player.melee_aiming_dot.global_position)
	
	# Thousand Year Cherry Blossom - Mirrored attack
	if _specific_stats.get("has_cherry_blossom", false):
		# Calculate the mirrored direction, which is the base aiming direction rotated 180 degrees, plus the slash's offset.
		var mirrored_base_direction = _base_direction.rotated(PI)
		var final_mirrored_direction = mirrored_base_direction.rotated(rotation_offset)
		
		# Calculate the mirrored spawn position by taking the aiming dot's local position, negating it, and converting it back to a global position.
		var mirrored_spawn_position = owner_player.to_global(owner_player.melee_aiming_dot.position * -1)
		
		_spawn_slash_instance(final_mirrored_direction, hit_data, hit_index, mirrored_spawn_position)


func _spawn_slash_instance(direction: Vector2, hit_data: Dictionary, hit_index: int, spawn_position: Vector2) -> Node2D:
	var owner_player = _owner_player_stats.get_parent()
	var attack_instance = katana_attack_scene.instantiate() as KatanaAttack
	
	owner_player.add_child(attack_instance)
	# Use the provided spawn position for this slash instance.
	attack_instance.global_position = spawn_position
	
	var stats_for_slash = _specific_stats.duplicate(true)
	stats_for_slash["damage_multiplier"] = float(hit_data.get("damage_multiplier", 1.0))
	
	# Pass the controller's reference to the attack instance
	attack_instance.set_attack_properties(direction, stats_for_slash, _owner_player_stats, self)
	
	# Connect signal to handle Focus mechanic
	attack_instance.hit_an_enemy.connect(_on_katana_hit_enemy)
	
	# --- Trigger Special Effects ---
	# Phantom Step (on 4th hit execution)
	if hit_index == 3 and _specific_stats.get("has_phantom_step", false):
		var status_comp = owner_player.get_node_or_null("StatusEffectComponent")
		# FIX: Corrected path to load the StatusEffectData container, not just the modification effect.
		var phantom_step_buff_data = load("res://DataResources/StatusEffects/katana_phantom_step_buff.tres") as StatusEffectData
		if is_instance_valid(status_comp) and is_instance_valid(phantom_step_buff_data):
			status_comp.apply_effect(phantom_step_buff_data, owner_player)
	
	# Blade of the Gale / Iaijutsu Spirit (on final hit)
	if hit_index == _attack_sequence.size() - 1:
		attack_instance.is_final_hit = true
		
		# FIX: Trigger Blade of the Gale on slash creation, not on hit.
		if _specific_stats.get("has_gale_wave", false):
			# Calculate the damage the final hit *would* do, without Focus bonus
			var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
			var damage_percent = _specific_stats.get("weapon_damage_percentage", 0.8) * float(hit_data.get("damage_multiplier", 1.0))
			
			# Step 1: Get the base damage.
			var base_damage = _owner_player_stats.get_calculated_base_damage(damage_percent)
			# Step 2: Apply tag multipliers.
			var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
			# --- END REFACTOR ---
			
			var wave_instance = gale_wave_scene.instantiate()
			get_tree().current_scene.add_child(wave_instance)
			wave_instance.global_position = owner_player.global_position
			wave_instance.setup(int(round(final_damage)), _base_direction, _owner_player_stats, _specific_stats)



	return attack_instance

func _on_katana_hit_enemy(enemy_node: BaseEnemy, damage_dealt: int, is_final_hit: bool):
	if not is_instance_valid(enemy_node): return

	var enemy_id = enemy_node.get_instance_id()
	
	# --- Focus Mechanic Logic ---
	if _specific_stats.get("has_focus_mechanic", false):
		if not _focus_tracker.has(enemy_id):
			_focus_tracker[enemy_id] = {"stacks": 0, "timestamp": 0.0}
		
		_focus_tracker[enemy_id].stacks += 1
		_focus_tracker[enemy_id].timestamp = Time.get_ticks_msec()

	# --- Handle Final Hit Effects (Iaijutsu Spirit) ---
	if is_final_hit and _specific_stats.get("has_iaijutsu_spirit", false):
		var focus_stacks = _focus_tracker.get(enemy_id, {"stacks": 0}).stacks
		if focus_stacks > 0:
			# Calculate bonus damage based on the Focus stacks and the base damage of the hit
			var focus_bonus_percent = float(focus_stacks) * _specific_stats.get("focus_damage_bonus_per_stack", 0.10)
			var damage_from_focus = float(damage_dealt) * focus_bonus_percent
			var iaijutsu_damage = int(round(damage_from_focus * 0.5))
			
			if iaijutsu_damage > 0:
				enemy_node.take_damage(iaijutsu_damage, _owner_player_stats.get_parent())

# Called by timer to remove expired Focus stacks
func _check_focus_expiration():
	var current_time = Time.get_ticks_msec()
	var reset_time_ms = float(_specific_stats.get("focus_reset_time", 3.0)) * 1000.0
	var keys_to_remove = []
	for enemy_id in _focus_tracker:
		if current_time - _focus_tracker[enemy_id].timestamp > reset_time_ms:
			keys_to_remove.append(enemy_id)
	
	for key in keys_to_remove:
		_focus_tracker.erase(key)

# Getter for KatanaAttack to calculate Focus damage
func get_focus_stacks_for(enemy: BaseEnemy) -> int:
	if not is_instance_valid(enemy): return 0
	var enemy_id = enemy.get_instance_id()
	return _focus_tracker.get(enemy_id, {"stacks": 0}).stacks
