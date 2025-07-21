# File: res://Scripts/Weapons/ScytheController.gd
# This controller manages the Scythe's attack logic, including Whirlwind.
# It is spawned by the WeaponManager and, in turn, spawns the actual ScytheAttack instances.
# FIX: Corrected the function call in _spawn_attack_instance to pass the correct number of arguments.

class_name ScytheController
extends Node2D

# In the Godot editor, assign your scythe_attack.tscn scene to this variable.
@export var scythe_attack_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager # Store the reference to the WeaponManager

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	if not is_instance_valid(scythe_attack_scene):
		push_error("ScytheController: scythe_attack_scene is not assigned! Aborting attack."); queue_free(); return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager # Store the manager reference

	# Spawn the primary attack instance
	var primary_attack = _spawn_attack_instance()
	
	# Connect to the reaping momentum signal from this specific attack instance
	if is_instance_valid(primary_attack) and primary_attack.has_signal("reaping_momentum_hit"):
		primary_attack.reaping_momentum_hit.connect(_on_reaping_momentum_hit)

	# --- LIFETIME MANAGEMENT FIX ---
	var total_lifetime = 0.5 # Base lifetime for the initial swing to complete
	
	# Handle Whirlwind Technique
	if _specific_stats.get(&"has_whirlwind", false):
		var number_of_spins = int(_specific_stats.get(&"whirlwind_count", 1))
		if number_of_spins > 1:
			var spin_delay = float(_specific_stats.get(&"whirlwind_delay", 0.1))
			# Start the recursive spin process
			_execute_whirlwind_spins(number_of_spins - 1, spin_delay)
			# Calculate total lifetime including all whirlwind delays
			total_lifetime += (number_of_spins - 1) * spin_delay
	
	# Create a timer to delete the controller after all actions are complete
	get_tree().create_timer(total_lifetime + 0.1, true, false, true).timeout.connect(queue_free)


func _execute_whirlwind_spins(spins_left: int, delay: float):
	if not is_instance_valid(self) or spins_left <= 0:
		# No need to queue_free here, the master timer will handle it.
		return
		
	# Spawn the attack for this spin
	var new_attack = _spawn_attack_instance()
	if is_instance_valid(new_attack) and new_attack.has_signal("reaping_momentum_hit"):
		new_attack.reaping_momentum_hit.connect(_on_reaping_momentum_hit)
		
	# Create a new timer for the *next* spin
	get_tree().create_timer(delay, true, false, true).timeout.connect(_execute_whirlwind_spins.bind(spins_left - 1, delay))


func _spawn_attack_instance() -> Node2D:
	var owner_player = _owner_player_stats.get_parent() as PlayerCharacter
	var direction = (owner_player.get_global_mouse_position() - owner_player.global_position).normalized()

	var attack_instance = scythe_attack_scene.instantiate() as ScytheAttack
	owner_player.add_child(attack_instance)
	attack_instance.global_position = owner_player.global_position
	
	if attack_instance.has_method("set_attack_properties"):
		# FIX: Pass only the 3 arguments that ScytheAttack.gd expects.
		attack_instance.set_attack_properties(direction, _specific_stats, _owner_player_stats, _weapon_manager)
		
	return attack_instance


func _on_reaping_momentum_hit(hit_count: int):
	var weapon_id = _specific_stats.get("id")
	print_debug("Reaping Momentum: Signal received for weapon '", weapon_id, "' with hit_count: ", hit_count)
	
	var reaping_bonus = _specific_stats.get(&"reaping_momentum_accumulated_bonus", 0)
	print_debug("  - Bonus before this hit: ", reaping_bonus)
	
	var dmg_per_hit = int(_specific_stats.get(&"reaping_momentum_damage_per_hit", 1))
	print_debug("  - Damage per hit calculated: ", dmg_per_hit)
	
	reaping_bonus += (hit_count * dmg_per_hit)
	
	print_debug("  - New bonus calculated: ", reaping_bonus)
	
	# Call back to the WeaponManager to update the persistent stat
	if is_instance_valid(_weapon_manager) and _weapon_manager.has_method("set_specific_weapon_stat"):
		_weapon_manager.set_specific_weapon_stat(weapon_id, &"reaping_momentum_accumulated_bonus", reaping_bonus)
		print_debug("  - Called WeaponManager to store new bonus.")
	else:
		print_debug("  - ERROR: WeaponManager invalid or missing set_specific_weapon_stat method.")
