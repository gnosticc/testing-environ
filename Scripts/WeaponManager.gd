# WeaponManager.gd
# This is the definitive, corrected version of the WeaponManager.
# It correctly differentiates between persistent summons and cooldown-based attacks,
# and restores the specific logic for Scythe upgrades.
# It now fully integrates with the standardized stat system via GameStatConstants.

class_name WeaponManager
extends Node

@export var max_weapons: int = 100
var active_weapons: Array[Dictionary] = [] # Stores current active weapons, their level, stats, etc.
var game_node_ref: Node # Reference to the global Game node (Main scene's root)

# Timer and queue specifically for the Scythe's Whirlwind ability (multi-spin attacks)
var _whirlwind_timer: Timer
var _whirlwind_queue: Array[Dictionary] = []

# A dictionary to track active persistent summons by their weapon ID
var _active_summons: Dictionary = {}

# Signals to notify other systems about changes in weapon state
signal weapon_added(weapon_data_dict: Dictionary)
signal weapon_removed(weapon_id: StringName)
signal weapon_upgraded(weapon_id: StringName, new_level: int)
signal active_weapons_changed()

func _ready():
	# Initialize the Whirlwind timer for Scythe's multi-spin ability
	_whirlwind_timer = Timer.new()
	_whirlwind_timer.name = "WhirlwindSpinTimer"
	_whirlwind_timer.one_shot = true # The timer fires once and stops
	add_child(_whirlwind_timer)
	_whirlwind_timer.timeout.connect(Callable(self, "_on_whirlwind_spin_timer_timeout"))

	# Get reference to the global Game node (for accessing weapon blueprints, etc.)
	# This should be valid by the time PlayerCharacter calls _on_game_weapon_blueprints_ready.
	var tree_root = get_tree().root
	game_node_ref = tree_root.get_node_or_null("Game")

# --- Core Weapon Handling ---

# Adds a new weapon to the player's active arsenal.
# blueprint_data: The WeaponBlueprintData resource for the weapon to add.
func add_weapon(blueprint_data: WeaponBlueprintData) -> bool:
	if not is_instance_valid(blueprint_data):
		push_error("WeaponManager: Attempted to add invalid weapon blueprint data."); return false
	if active_weapons.size() >= max_weapons:
		push_warning("WeaponManager: Max weapon limit reached. Cannot add '", blueprint_data.id, "'."); return false
	if _get_weapon_entry_index_by_id(blueprint_data.id) != -1:
		push_warning("WeaponManager: Weapon '", blueprint_data.id, "' already active. Skipping."); return false

	# Create a new weapon entry dictionary
	var weapon_entry = {
		"id": blueprint_data.id,
		"title": blueprint_data.title,
		"weapon_level": 1, # New weapons start at level 1
		"specific_stats": blueprint_data.initial_specific_stats.duplicate(true), # Deep copy of initial stats
		"blueprint_resource": blueprint_data,
		"acquired_upgrade_ids": [] # List of upgrade IDs applied to this weapon
	}
	
	# Differentiated logic based on weapon tags (e.g., "summon" for persistent entities)
	if blueprint_data.tags.has("summon"):
		# For persistent summons (like Moth Golem, Lesser Spirit), spawn them once.
		_spawn_persistent_summon(weapon_entry)
	else:
		# For all other attacks (Melee, Projectile, Orbital) that work on a cooldown.
		if blueprint_data.cooldown <= 0:
			push_error("WeaponManager: Non-summon weapon '", blueprint_data.id, "' has a cooldown of 0 or less. It will not fire."); return false
		else:
			# Create and configure a cooldown timer for this weapon
			var cooldown_timer = Timer.new()
			cooldown_timer.name = str(blueprint_data.id) + "CooldownTimer"
			# Set initial cooldown based on player stats
			cooldown_timer.wait_time = get_weapon_cooldown_value(weapon_entry)
			cooldown_timer.one_shot = true # Timer fires once per attack cycle
			add_child(cooldown_timer) # Add as child to manage automatically
			weapon_entry["cooldown_timer"] = cooldown_timer
			# Connect timeout signal to the attack function
			cooldown_timer.timeout.connect(Callable(self, "_on_attack_cooldown_finished").bind(blueprint_data.id))
			cooldown_timer.start() # Start the first cooldown

	active_weapons.append(weapon_entry)
	emit_signal("weapon_added", weapon_entry.duplicate(true))
	emit_signal("active_weapons_changed")
	return true

# Called when a weapon's cooldown timer finishes.
# weapon_id: The ID of the weapon whose cooldown finished.
func _on_attack_cooldown_finished(weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return # Weapon no longer active

	var weapon_entry = active_weapons[weapon_index]
	var specific_stats = weapon_entry.specific_stats # Get the weapon's specific stats

	# Handle Reaping Momentum bonus (Scythe-specific logic)
	var reaping_bonus = int(specific_stats.get(&"reaping_momentum_bonus", 0))
	_spawn_attack_instance(weapon_entry, reaping_bonus) # Spawn the main attack

	# Handle Whirlwind ability (Scythe-specific multi-spin logic)
	var number_of_spins = 1
	if specific_stats.get(&"has_whirlwind", false):
		# Ensure "whirlwind_count" is accessed using its StringName and defaults correctly
		number_of_spins = int(specific_stats.get(&"whirlwind_count", 1))

	if number_of_spins > 1:
		# Add spin data to the queue for deferred processing
		var spin_data = {
			"weapon_id": weapon_id,
			"spins_left": number_of_spins - 1, # Remaining spins after the first one
			"delay": float(specific_stats.get(&"whirlwind_delay", 0.1)), # Delay between spins
			"reaping_bonus_to_apply": reaping_bonus # Pass the accumulated bonus
		}
		_whirlwind_queue.append(spin_data)
		if _whirlwind_timer.is_stopped(): # Start timer if not already running for the queue
			_whirlwind_timer.wait_time = spin_data.delay
			_whirlwind_timer.start()
			
	_restart_weapon_cooldown(active_weapons[weapon_index]) # Restart the cooldown timer for the next attack cycle

# Called when the Whirlwind multi-spin timer finishes.
func _on_whirlwind_spin_timer_timeout():
	if _whirlwind_queue.is_empty(): return

	var current_whirlwind = _whirlwind_queue.front()
	var weapon_index = _get_weapon_entry_index_by_id(current_whirlwind.weapon_id)
		
	if weapon_index != -1:
		# Spawn the whirlwind attack with the same reaping bonus as the initial hit
		_spawn_attack_instance(active_weapons[weapon_index], current_whirlwind.reaping_bonus_to_apply)
	
	current_whirlwind.spins_left -= 1
	if current_whirlwind.spins_left <= 0:
		_whirlwind_queue.pop_front() # Remove from queue if spins are done
	
	if not _whirlwind_queue.is_empty():
		# Start timer for the next spin in the queue
		var next_whirlwind = _whirlwind_queue.front()
		_whirlwind_timer.wait_time = next_whirlwind.delay
		_whirlwind_timer.start()

# Spawns an instance of a weapon's attack scene.
# weapon_entry: Dictionary containing weapon details and its specific stats.
# p_reaping_bonus: Accumulated Reaping Momentum bonus to apply to this attack.
func _spawn_attack_instance(weapon_entry: Dictionary, p_reaping_bonus: int):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	if not is_instance_valid(blueprint_data) or not is_instance_valid(blueprint_data.weapon_scene):
		push_warning("WeaponManager: Cannot spawn attack. Invalid blueprint or scene for '", weapon_entry.id, "'."); return
	
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(owner_player):
		push_error("WeaponManager: Owner PlayerCharacter is invalid, cannot spawn attack."); return

	var direction: Vector2 = Vector2.ZERO
	var spawn_position: Vector2 = owner_player.global_position
	var target_found: bool = true

	# Determine attack direction and spawn position based on targeting type
	if blueprint_data.requires_direction:
		match blueprint_data.targeting_type:
			&"nearest_enemy": # Targeting the closest enemy
				var nearest_enemy = owner_player._find_nearest_enemy() # Assuming this helper exists in PlayerCharacter
				if is_instance_valid(nearest_enemy):
					direction = (nearest_enemy.global_position - owner_player.global_position).normalized()
				else:
					target_found = false # No target, don't fire
			&"mouse_location": # Targeting mouse position for ranged attacks
				var world_mouse_pos = owner_player.get_global_mouse_position()
				direction = (world_mouse_pos - owner_player.global_position).normalized()
				# Clamp spawn position within a max cast range if specified
				var max_range = float(weapon_entry.specific_stats.get(&"max_cast_range", 300.0))
				if owner_player.global_position.distance_to(world_mouse_pos) > max_range:
					spawn_position = owner_player.global_position + direction * max_range
				else:
					spawn_position = world_mouse_pos
			&"mouse_direction": # Targeting mouse direction (for melee aim dot)
				# Assuming PlayerCharacter.melee_aiming_dot is a node that can provide direction
				if is_instance_valid(owner_player.melee_aiming_dot) and owner_player.melee_aiming_dot.has_method("get_aiming_direction"):
					direction = owner_player.melee_aiming_dot.get_aiming_direction()
				else:
					# Fallback to player facing direction or default if aim dot invalid
					direction = Vector2.RIGHT # Or current player facing direction
	
	if not target_found: return # Abort if no target for a targeting-dependent attack

	var weapon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(weapon_instance):
		push_error("WeaponManager: Failed to instantiate weapon scene for '", blueprint_data.id, "'."); return
	
	# Prepare stats to pass to the attack instance
	var stats_for_this_instance = weapon_entry.specific_stats.duplicate(true)
	stats_for_this_instance[&"base_lifetime"] = blueprint_data.base_lifetime # Pass base lifetime for projectile/melee

	# Apply Reaping Momentum bonus to the instance and reset it in the weapon entry
	if p_reaping_bonus > 0:
		stats_for_this_instance[&"reaping_momentum_bonus_to_apply"] = p_reaping_bonus
		weapon_entry.specific_stats[&"reaping_momentum_bonus"] = 0 # Reset stored bonus after use

	# Determine where to add the weapon instance in the scene tree
	if blueprint_data.tags.has("centered_melee"):
		owner_player.add_child(weapon_instance)
		weapon_instance.position = Vector2.ZERO # Centered on player
	elif blueprint_data.tags.has("melee"):
		owner_player.add_child(weapon_instance)
		# Assumes melee_aiming_dot provides local position relative to player
		weapon_instance.position = owner_player.melee_aiming_dot.position
	else:
		# For projectiles or other non-player-child attacks
		var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
		if is_instance_valid(attacks_container): attacks_container.add_child(weapon_instance)
		else: get_tree().current_scene.add_child(weapon_instance) # Fallback if container not found
		weapon_instance.global_position = spawn_position
	
	# Pass attack properties and player_stats to the attack instance
	if weapon_instance.has_method("set_attack_properties"):
		weapon_instance.set_attack_properties(direction, stats_for_this_instance, owner_player.player_stats)
	else:
		push_warning("WeaponManager: Attack instance '", weapon_instance.name, "' for '", blueprint_data.id, "' is missing 'set_attack_properties' method.")
	
	# Connect to Reaping Momentum signal from the attack instance (if applicable, like Scythe)
	if weapon_instance.has_signal("reaping_momentum_hits"):
		# CONNECT_ONE_SHOT ensures the connection is automatically removed after firing once
		weapon_instance.reaping_momentum_hits.connect(Callable(self, "_on_reaping_momentum_hits").bind(weapon_entry.id), CONNECT_ONE_SHOT)

# Spawns a persistent summon (e.g., Moth Golem, Lesser Spirit).
# weapon_entry: Dictionary containing weapon details and its specific stats.
func _spawn_persistent_summon(weapon_entry: Dictionary):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(blueprint_data) or not is_instance_valid(owner_player):
		push_error("WeaponManager: Cannot spawn persistent summon. Invalid blueprint or owner."); return

	var summon_instance = blueprint_data.weapon_scene.instantiate()
	if not is_instance_valid(summon_instance):
		push_error("WeaponManager: Failed to instantiate summon scene for '", blueprint_data.id, "'."); return
	
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container): attacks_container.add_child(summon_instance)
	else: get_tree().current_scene.add_child(summon_instance) # Fallback
	
	# Spawn near player with slight random offset
	summon_instance.global_position = owner_player.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	if summon_instance.has_method("initialize"):
		var stats_to_pass = weapon_entry.specific_stats.duplicate(true)
		stats_to_pass[&"weapon_level"] = weapon_entry.weapon_level # Pass weapon level as a stat to the summon
		summon_instance.initialize(owner_player, stats_to_pass) # Pass player reference and weapon stats
	else:
		push_warning("WeaponManager: Summon instance '", summon_instance.name, "' for '", blueprint_data.id, "' is missing 'initialize' method.")
	
	# Track active summons
	if not _active_summons.has(blueprint_data.id):
		_active_summons[blueprint_data.id] = []
	_active_summons[blueprint_data.id].append(summon_instance)
	
	# Connect to the summon's tree_exiting signal to clean up tracking
	summon_instance.tree_exiting.connect(_on_summon_destroyed.bind(blueprint_data.id, summon_instance))


# --- Upgrade & Helper Functions ---

# Applies an upgrade to a specific weapon.
# weapon_id: The ID of the weapon to upgrade.
# upgrade_data_resource: The WeaponUpgradeData resource with the upgrade effects.
func apply_weapon_upgrade(weapon_id: StringName, upgrade_data_resource: WeaponUpgradeData):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1:
		push_warning("WeaponManager: Cannot apply upgrade. Weapon '", weapon_id, "' not found."); return

	var weapon_entry = active_weapons[weapon_index]
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData

	# Check max stacks for the upgrade
	var current_stacks = weapon_entry.acquired_upgrade_ids.count(upgrade_data_resource.upgrade_id)
	if upgrade_data_resource.max_stacks > 0 and current_stacks >= upgrade_data_resource.max_stacks:
		push_warning("WeaponManager: Upgrade '", upgrade_data_resource.upgrade_id, "' on '", weapon_id, "' has reached max stacks."); return
	
	# Iterate through each effect defined in the WeaponUpgradeData and apply it.
	for effect_resource in upgrade_data_resource.effects:
		if not is_instance_valid(effect_resource): continue
		
		# --- Stat Modification Effects ---
		if effect_resource is StatModificationEffectData:
			var stat_mod = effect_resource as StatModificationEffectData
			
			match stat_mod.target_scope:
				&"player_stats":
					var p_stats = get_parent().player_stats # Get PlayerStats reference
					if is_instance_valid(p_stats):
						p_stats.apply_stat_modification(stat_mod)
					else:
						push_error("WeaponManager: PlayerStats node is invalid when applying player_stats modification for weapon upgrade.")
				&"weapon_specific_stats":
					# Apply stat modification directly to the weapon's specific_stats dictionary.
					# This mirrors the logic in PlayerStats.gd's apply_stat_modification.
					var key = stat_mod.stat_key
					var value = stat_mod.get_value()
					var modification_type_string_name: StringName = &"" + str(stat_mod.modification_type) # Ensure StringName
					
					# Ensure the stat key exists in the specific_stats, or initialize it
					if not weapon_entry.specific_stats.has(key):
						weapon_entry.specific_stats[key] = 0.0 # Default to float for new stats
					
					match modification_type_string_name:
						&"flat_add":
							weapon_entry.specific_stats[key] += value
						&"percent_add_to_base":
							# For weapon stats, this implies a percentage increase to the base value (e.g., +10% attack damage)
							# Store it as a sum of percentages, then apply later.
							var current_percent_add = weapon_entry.specific_stats.get(key.replace(&"base_", &""), 0.0) # Handle 'base_X' keys for weapon stats
							weapon_entry.specific_stats[key] = current_percent_add + value
						&"percent_mult_final":
							# This might be used for effects like "x% more damage" for a specific weapon.
							# Multipliers stack multiplicatively.
							var current_mult = weapon_entry.specific_stats.get(key, 1.0)
							weapon_entry.specific_stats[key] = current_mult * (1.0 + value)
						&"override_value":
							weapon_entry.specific_stats[key] = value
						_:
							push_error("WeaponManager: Unknown modification type '", modification_type_string_name, "' for weapon_specific_stats on key '", key, "'.")
				_:
					push_warning("WeaponManager: StatModificationEffectData has unhandled target_scope: '", stat_mod.target_scope, "'.")
		
		# --- Custom Flag Effects ---
		elif effect_resource is CustomFlagEffectData:
			var flag_mod = effect_resource as CustomFlagEffectData
			# Custom flags can be applied to weapon-specific stats or behaviors
			if flag_mod.target_scope == &"weapon_specific_stats" or flag_mod.target_scope == &"weapon_behavior":
				weapon_entry.specific_stats[flag_mod.flag_key] = flag_mod.flag_value
			elif flag_mod.target_scope == &"player_behavior": # If a weapon upgrade affects a player flag
				var owner_player = get_parent() as PlayerCharacter
				if is_instance_valid(owner_player) and owner_player.player_stats.has_method("apply_custom_flag"):
					owner_player.player_stats.apply_custom_flag(flag_mod)
			else:
				push_warning("WeaponManager: CustomFlagEffectData has unhandled target_scope: '", flag_mod.target_scope, "'.")
		
		# --- Status Effect Application Effects ---
		elif effect_resource is StatusEffectApplicationData:
			var status_app_data = effect_resource as StatusEffectApplicationData
			# Store status application data within weapon's specific stats to be used by attack instances.
			if not weapon_entry.specific_stats.has(&"on_hit_status_applications"):
				weapon_entry.specific_stats[&"on_hit_status_applications"] = []
			weapon_entry.specific_stats[&"on_hit_status_applications"].append(status_app_data)
		
		# --- Trigger Ability Effects ---
		elif effect_resource is TriggerAbilityEffectData:
			# Trigger ability effects are more complex and depend on where the ability is implemented.
			# For now, we'll just log a warning.
			push_warning("WeaponManager: TriggerAbilityEffectData (", effect_resource.ability_id, ") in weapon upgrade is not yet fully implemented for direct application here.")
		
		else:
			push_warning("WeaponManager: Weapon upgrade contains unhandled effect type: ", effect_resource.get_class())
	
	# Increment weapon level and record acquired upgrade
	weapon_entry.weapon_level += 1
	weapon_entry.acquired_upgrade_ids.append(upgrade_data_resource.upgrade_id)
	
	# If it's a summon weapon, handle potential increase in max summons or stat updates for existing summons
	if blueprint_data.tags.has("summon"):
		var max_summons = int(weapon_entry.specific_stats.get(&"max_summons_of_type", 1))
		var current_summon_list = _active_summons.get(weapon_id, [])
		var current_summon_count = current_summon_list.size()
		
		# Spawn new summons if max_summons increased
		if max_summons > current_summon_count:
			for i in range(max_summons - current_summon_count):
				_spawn_persistent_summon(weapon_entry)
		
		# Update stats of ALL active summons of this type
		var owner_player = get_parent() as PlayerCharacter
		if is_instance_valid(owner_player):
			for summon_instance in current_summon_list:
				if is_instance_valid(summon_instance) and summon_instance.has_method("update_stats"):
					var stats_to_pass = weapon_entry.specific_stats.duplicate(true)
					stats_to_pass[&"weapon_level"] = weapon_entry.weapon_level
					summon_instance.update_stats(owner_player, stats_to_pass) # Pass player ref and updated stats
	
	# Increment basic class level if the weapon has class restrictions
	var owner_player = get_parent() as PlayerCharacter
	if is_instance_valid(owner_player) and owner_player.has_method("increment_basic_class_level"):
		if not blueprint_data.class_tag_restrictions.is_empty():
			var class_enum_to_increment = blueprint_data.class_tag_restrictions[0]
			owner_player.increment_basic_class_level(class_enum_to_increment)

	emit_signal("weapon_upgraded", weapon_id, weapon_entry.weapon_level)
	emit_signal("active_weapons_changed")


# Accumulates hit counts for Reaping Momentum (Scythe)
# hit_count: Number of hits to add to the bonus.
# weapon_id: The ID of the Scythe weapon.
func _on_reaping_momentum_hits(hit_count: int, weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	
	var weapon_entry = active_weapons[weapon_index]
	# Get reaping_momentum_dmg_per_hit from weapon's specific stats
	var dmg_per_hit = int(weapon_entry.specific_stats.get(&"reaping_momentum_dmg_per_hit", 1))
	var bonus_to_add = hit_count * dmg_per_hit
	
	if bonus_to_add > 0:
		var current_stored_bonus = weapon_entry.specific_stats.get(&"reaping_momentum_bonus", 0)
		weapon_entry.specific_stats[&"reaping_momentum_bonus"] = current_stored_bonus + bonus_to_add
		# print("WeaponManager: Reaping Momentum bonus for ", weapon_id, " increased to ", weapon_entry.specific_stats[&"reaping_momentum_bonus"])

# Called when a persistent summon is destroyed (e.g., via queue_free, health 0).
func _on_summon_destroyed(weapon_id: StringName, summon_instance: Node):
	if _active_summons.has(weapon_id):
		if _active_summons[weapon_id].has(summon_instance):
			_active_summons[weapon_id].erase(summon_instance)
			# print("WeaponManager: Summon '", summon_instance.name, "' of '", weapon_id, "' destroyed. Remaining: ", _active_summons[weapon_id].size())

# Restarts a weapon's cooldown timer based on its current effective cooldown.
func _restart_weapon_cooldown(weapon_entry: Dictionary):
	var timer = weapon_entry.get("cooldown_timer") as Timer
	if is_instance_valid(timer):
		timer.wait_time = get_weapon_cooldown_value(weapon_entry)
		timer.start()

# Calculates the effective cooldown time for a weapon based on player stats.
func get_weapon_cooldown_value(weapon_entry: Dictionary) -> float:
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	if not is_instance_valid(blueprint_data): return 999.0
	
	var final_cooldown = blueprint_data.cooldown
	var owner_player = get_parent() as PlayerCharacter
	if is_instance_valid(owner_player) and is_instance_valid(owner_player.player_stats):
		var p_stats = owner_player.player_stats

		# Apply player's Attack Speed Multiplier
		var atk_speed_mult = p_stats.get_final_stat(GameStatConstants.Keys.ATTACK_SPEED_MULTIPLIER)
		if atk_speed_mult > 0: # Prevent division by zero
			final_cooldown /= atk_speed_mult

		# Apply player's Flat Cooldown Reduction
		var global_cdr_flat = p_stats.get_final_stat(GameStatConstants.Keys.GLOBAL_COOLDOWN_REDUCTION_FLAT)
		final_cooldown -= global_cdr_flat

		# Apply player's Percentage Cooldown Reduction
		var global_cdr_mult = p_stats.get_final_stat(GameStatConstants.Keys.GLOBAL_COOLDOWN_REDUCTION_MULT)
		# This multiplier reduces the remaining cooldown (e.g., 0.1 for 10% reduction)
		final_cooldown *= (1.0 - global_cdr_mult)
	
	return maxf(0.05, final_cooldown) # Ensure cooldown doesn't go below a minimum threshold


# Returns a copy of active weapon data suitable for level-up screen display.
func get_active_weapons_data_for_level_up() -> Array[Dictionary]:
	var weapons_data_copy: Array[Dictionary] = []
	for weapon_entry in active_weapons:
		var display_data = {
			"id": weapon_entry.id,
			"title": weapon_entry.title,
			"weapon_level": weapon_entry.weapon_level,
			"specific_stats": weapon_entry.specific_stats.duplicate(true),
			"blueprint_resource_path": weapon_entry.blueprint_resource.resource_path if is_instance_valid(weapon_entry.blueprint_resource) else ""
		}
		weapons_data_copy.append(display_data)
	return weapons_data_copy

# Helper to find the index of a weapon entry by its ID in the active_weapons array.
func _get_weapon_entry_index_by_id(weapon_id: StringName) -> int:
	for i in range(active_weapons.size()):
		if active_weapons[i].id == weapon_id:
			return i
	return -1

# Ensures the game_node_ref is valid and has necessary methods.
func _ensure_game_node_ref() -> bool:
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("get_weapon_blueprint_by_id"):
		return true
	game_node_ref = get_tree().root.get_node_or_null("Game")
	return is_instance_valid(game_node_ref)
