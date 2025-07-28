# File: res://Scripts/DataResources/Weapons/Basic Class Weapons/ScytheController.gd
# This controller manages the Scythe's attack logic, including Whirlwind and Reaping Momentum.
# It is spawned by the WeaponManager and, in turn, spawns the actual ScytheAttack instances.
#
# BUG FIX: Reaping Momentum was stacking indefinitely. This version corrects the logic by
# having the controller manage the state for a single attack "turn". It now reads the
# bonus, immediately resets the bonus in the WeaponManager, applies the read bonus to all
# swings in the current turn, accumulates all hits from the current turn, and then writes
# the new, correct bonus back to the WeaponManager upon exiting.
# ADDED: Debug prints to trace the Reaping Momentum logic flow, with added detail for Whirlwind.
# BUG FIX 2: Restored the delay for Whirlwind swings.

class_name ScytheController
extends Node2D

@export var scythe_attack_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager

# --- NEW: State variables for managing a single Reaping Momentum turn ---
var _bonus_damage_for_this_turn: int = 0
var _hits_this_turn: int = 0
var _swing_counter_this_turn: int = 0 # NEW: Counter for distinguishing swings
# ---

func _ready():
	# Connect the tree_exiting signal. This is crucial for the final step of the fix.
	tree_exiting.connect(_on_controller_exiting)

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	if not is_instance_valid(scythe_attack_scene):
		push_error("ScytheController: scythe_attack_scene is not assigned! Aborting attack.")
		queue_free()
		return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	_swing_counter_this_turn = 0 # Reset swing counter for the new attack turn

	# --- REAPING MOMENTUM - STEP 1: READ & RESET ---
	if _specific_stats.get(&"has_reaping_momentum", false):
		# Read the bonus from the last turn. This value will be applied to all swings in THIS turn.
		_bonus_damage_for_this_turn = int(_specific_stats.get(&"reaping_momentum_accumulated_bonus", 0))
		print_debug("--- Scythe Turn Start ---")
		print_debug("Reaping Momentum: Applying +", _bonus_damage_for_this_turn, " bonus damage to this turn's swings.")
		
		# Immediately reset the bonus in the manager. Hits from this turn will be accumulated
		# and written back as the new bonus when this controller is destroyed.
		if is_instance_valid(_weapon_manager):
			_weapon_manager.set_specific_weapon_stat(_specific_stats.get("id"), &"reaping_momentum_accumulated_bonus", 0)

	# Spawn the primary attack instance
	var primary_attack = _spawn_attack_instance()
	
	# Connect to the reaping momentum signal from this specific attack instance
	if is_instance_valid(primary_attack) and primary_attack.has_signal("reaping_momentum_hit"):
		# Bind the current swing number to the signal handler
		primary_attack.reaping_momentum_hit.connect(_on_reaping_momentum_hit.bind(_swing_counter_this_turn))

	# --- Lifetime & Whirlwind Management ---
	var total_lifetime = 0.5 # Base lifetime for the initial swing to complete
	
	if _specific_stats.get(&"has_whirlwind", false):
		var number_of_spins = int(_specific_stats.get(&"whirlwind_count", 1))
		if number_of_spins > 1:
			var spin_delay = float(_specific_stats.get(&"whirlwind_delay", 0.1))
			# FIX: Start the recursive spin process AFTER the initial delay
			get_tree().create_timer(spin_delay, true, false, true).timeout.connect(_execute_whirlwind_spins.bind(number_of_spins - 1, spin_delay))
			total_lifetime += (number_of_spins - 1) * spin_delay
	
	get_tree().create_timer(total_lifetime + 0.1, true, false, true).timeout.connect(queue_free)

func _execute_whirlwind_spins(spins_left: int, delay: float):
	if not is_instance_valid(self) or spins_left <= 0:
		return
		
	var new_attack = _spawn_attack_instance()
	if is_instance_valid(new_attack) and new_attack.has_signal("reaping_momentum_hit"):
		# Bind the current swing number to the signal handler for the whirlwind swing
		new_attack.reaping_momentum_hit.connect(_on_reaping_momentum_hit.bind(_swing_counter_this_turn))
		
	# Create a new timer for the *next* spin
	get_tree().create_timer(delay, true, false, true).timeout.connect(_execute_whirlwind_spins.bind(spins_left - 1, delay))


func _spawn_attack_instance() -> Node2D:
	_swing_counter_this_turn += 1 # Increment for each new swing
	var owner_player = _owner_player_stats.get_parent() as PlayerCharacter
	var direction = (owner_player.get_global_mouse_position() - owner_player.global_position).normalized()

	var attack_instance = scythe_attack_scene.instantiate() as ScytheAttack
	owner_player.add_child(attack_instance)
	attack_instance.global_position = owner_player.global_position
	
	# --- REAPING MOMENTUM - STEP 2: APPLY ---
	# Create a copy of the stats and inject the bonus damage we stored for THIS turn.
	var stats_for_this_swing = _specific_stats.duplicate(true)
	stats_for_this_swing[&"reaping_momentum_accumulated_bonus"] = _bonus_damage_for_this_turn
	
	if attack_instance.has_method("set_attack_properties"):
		attack_instance.set_attack_properties(direction, stats_for_this_swing, _owner_player_stats, _weapon_manager)
		
	return attack_instance

func _on_reaping_momentum_hit(hit_count: int, swing_number: int):
	# --- REAPING MOMENTUM - STEP 3: ACCUMULATE ---
	# Simply add the hits from the completed swing to our turn's total.
	_hits_this_turn += hit_count
	print_debug("Reaping Momentum (Swing #", swing_number, "): Accumulated ", hit_count, " hits. Total hits this turn so far: ", _hits_this_turn)

func _on_controller_exiting():
	# --- REAPING MOMENTUM - STEP 4: WRITE ---
	# This function is called automatically when this controller is about to be deleted.
	# It calculates the new bonus from all accumulated hits and writes it to the WeaponManager
	# for the NEXT attack turn to use.
	if _specific_stats.get(&"has_reaping_momentum", false):
		var dmg_per_hit = int(_specific_stats.get(&"reaping_momentum_damage_per_hit", 1))
		var new_bonus_for_next_turn = _hits_this_turn * dmg_per_hit
		
		if is_instance_valid(_weapon_manager):
			_weapon_manager.set_specific_weapon_stat(_specific_stats.get("id"), &"reaping_momentum_accumulated_bonus", new_bonus_for_next_turn)
			print_debug("Reaping Momentum: Controller exiting. Wrote new bonus of +", new_bonus_for_next_turn, " (from ", _hits_this_turn, " total hits) to WeaponManager for next turn.")
		
		# Add a case for when no enemies are hit to confirm the reset.
		if _hits_this_turn == 0:
			print_debug("Reaping Momentum: Controller exiting. No enemies hit this turn. Bonus for next turn is 0.")
		print_debug("--- Scythe Turn End ---")
