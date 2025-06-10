# player_stats.gd
# This script manages all player statistics. It will now use the standardized keys
# defined via the 'PlayerStatKeys' Autoload.
# It is designed to be a child node of PlayerCharacter.
#
# IMPORTANT: This script should replace your existing PlayerStats.gd.
# 'PlayerStatKeys' must be set as an Autoload (see Step 2 in previous instructions).

extends Node
class_name PlayerStats # Explicit class name for clarity and type hinting

# Signal to notify listeners (e.g., PlayerCharacter, UI) when player stats have been recalculated.
# It's good practice to emit more specific signals or pass a dictionary of changed stats
# if performance becomes an issue with many UI updates.
signal stats_recalculated(current_max_health_val, current_movement_speed_val)

# Dictionary to hold the final calculated base stats after initialization.
# This represents the player's core stats before temporary buffs/debuffs are applied.
var base_stat_values: Dictionary = {}

# Dictionaries to hold modifiers. These will accumulate modifications from upgrades
# and temporary effects.
var flat_modifiers: Dictionary = {} 		   # For flat additions (e.g., +5 Health)
var percent_add_modifiers: Dictionary = {} 	   # For percentage additions to base (e.g., +10% Movement Speed)
var percent_mult_final_modifiers: Dictionary = {} # For final percentage multipliers (e.g., +20% Global Damage)

# --- CURRENT CALCULATED STATS ---
# These variables hold the final, fully calculated values of key stats, updated
# every time recalculate_all_stats() is called. This provides quick access
# without needing to call get_final_stat() repeatedly for common values.
var current_max_health: float = 0.0
var current_numerical_damage: float = 0.0
var current_global_damage_multiplier: float = 1.0
var current_global_flat_damage_add: float = 0.0
var current_attack_speed_multiplier: float = 1.0
var current_armor: float = 0.0
var current_armor_penetration: float = 0.0
var current_movement_speed: float = 0.0
var current_magnet_range: float = 0.0
var current_experience_gain_multiplier: float = 1.0
var current_aoe_area_multiplier: float = 1.0
var current_projectile_size_multiplier: float = 1.0
var current_projectile_speed_multiplier: float = 1.0
var current_effect_duration_multiplier: float = 1.0
var current_crit_chance: float = 0.0
var current_crit_damage_multiplier: float = 1.0
var current_luck: float = 0.0
var current_health_regeneration: float = 0.0
# Add other 'current_' stats here as needed, based on your PlayerStatKeys.Keys

# --- Initialization ---
func _ready():
	# PlayerStats should be initialized externally by PlayerCharacter.gd
	# after PlayerCharacter has loaded the PlayerClassData.tres resource.
	# So, _ready() here just ensures dictionaries are ready.
	pass

# This method sets the initial base stats for the player,
# based on the chosen PlayerClassData.
# It should be called once by PlayerCharacter.gd during player setup.
func initialize_base_stats(class_data: PlayerClassData):
	# Clear any previous stats to ensure a clean slate for the new class
	base_stat_values.clear()
	flat_modifiers.clear()
	percent_add_modifiers.clear()
	percent_mult_final_modifiers.clear()

	# Get the standardized dictionary of initial stats from PlayerClassData
	var initial_class_stats: Dictionary = class_data.get_base_stats_as_standardized_dict()

	# Iterate through all known stat keys defined in PlayerStatKeys.Keys
	for key_enum_value in PlayerStatKeys.Keys.values():
		var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum_value]

		# Initialize base_stat_values using the values from PlayerClassData.
		# If a stat is not provided by PlayerClassData, it defaults to 0.0.
		# Ensure values are floats for consistency in calculations.
		base_stat_values[key_string] = float(initial_class_stats.get(key_string, 0.0))

		# Initialize modifier dictionaries for each stat key.
		# Flat and percent_add start at 0.0 (no modification).
		# Percent_mult_final starts at 1.0 (no multiplicative change).
		flat_modifiers[key_string] = 0.0
		percent_add_modifiers[key_string] = 0.0
		percent_mult_final_modifiers[key_string] = 1.0 # Default to 1.0 for multipliers

	print("Player stats initialized for class: ", class_data.display_name)
	# After initial setup, recalculate and emit signal
	recalculate_all_stats()
	print("Initial Max Health: ", current_max_health) # Use current_max_health
	print("Initial Numerical Damage: ", current_numerical_damage) # Use current_numerical_damage


# This method is a fallback for debugging, to initialize with raw dictionary data.
func initialize_base_stats_with_raw_dict(raw_stats_dict: Dictionary):
	base_stat_values.clear()
	flat_modifiers.clear()
	percent_add_modifiers.clear()
	percent_mult_final_modifiers.clear()

	for key_enum_value in PlayerStatKeys.Keys.values(): # Use PlayerStatKeys
		var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum_value] # Use PlayerStatKeys
		base_stat_values[key_string] = float(raw_stats_dict.get(key_string, 0.0))
		flat_modifiers[key_string] = 0.0
		percent_add_modifiers[key_string] = 0.0
		percent_mult_final_modifiers[key_string] = 1.0

	print("Player stats initialized with raw dictionary for debugging.")
	recalculate_all_stats()


# --- Applying Stat Modifications from EffectData ---
# This function is called by PlayerCharacter.gd or WeaponManager.gd
# when a StatModificationEffectData is applied to "player_stats".
func apply_stat_modification(effect_data: StatModificationEffectData):
	# Assuming effect_data.modification_type is already a StringName (e.g., &"flat_add")
	# If not, ensure StatModificationEffectData exposes it as StringName.
	var modification_type_string_name: StringName = effect_data.modification_type
	var target_stat_key_string: StringName = effect_data.stat_key
	var value = effect_data.get_value()

	# Validate if the target_stat_key_string is a recognized player stat.
	# It's good to also check if it exists in base_stat_values as a quick check.
	if not PlayerStatKeys.KEY_NAMES.values().has(target_stat_key_string):
		push_error("PlayerStats: Attempted to modify unrecognized player stat key: ", target_stat_key_string)
		return
	
	# Only modify if the stat is intended to be modified (e.g., if it's in our base_stat_values,
	# which it should be after initialize_base_stats).
	if not base_stat_values.has(target_stat_key_string):
		push_error("PlayerStats: Stat '", target_stat_key_string, "' not properly initialized in base_stat_values. Cannot apply modification.")
		return

	match modification_type_string_name:
		&"flat_add": # Use StringName literals for match
			base_stat_values[target_stat_key_string] += value
		&"percent_add_to_base": # Use StringName literals for match
			percent_add_modifiers[target_stat_key_string] += value
		&"percent_mult_final": # Use StringName literals for match
			percent_mult_final_modifiers[target_stat_key_string] *= (1.0 + value)
		&"override_value": # Use StringName literals for match
			base_stat_values[target_stat_key_string] = value
		_:
			push_error("PlayerStats: Unknown modification type: '", modification_type_string_name, "' for stat '", target_stat_key_string, "'.")

	print("PlayerStats: Applied stat modification to '", target_stat_key_string, "'. Type: '", modification_type_string_name, "', Value: ", value)
	recalculate_all_stats()


# --- Handling Custom Flags (Boolean states) ---
# These are handled by CustomFlagEffectData and stored in a separate dictionary.
var player_flags: Dictionary = {}

func apply_custom_flag(effect_data: CustomFlagEffectData):
	var flag_key_string: StringName = effect_data.flag_key
	var flag_value: bool = effect_data.flag_value

	player_flags[flag_key_string] = flag_value
	print("PlayerStats: Flag '", flag_key_string, "' set to ", flag_value)
	# Flags generally don't trigger a full stat recalculation unless they directly affect a calculated stat's formula,
	# which is usually handled within the get_final_stat logic or in the consuming script.


func get_flag(flag_key_enum: PlayerStatKeys.Keys) -> bool: # Use PlayerStatKeys
	var flag_key_string: StringName = PlayerStatKeys.KEY_NAMES[flag_key_enum] # Use PlayerStatKeys
	return player_flags.get(flag_key_string, false) # Default to false if flag not set


# --- Getting Final Stat Value ---
# This function calculates the final value of a stat after applying all modifiers.
func get_final_stat(key_enum: PlayerStatKeys.Keys) -> float: # Use PlayerStatKeys
	var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum] # Use PlayerStatKeys
	return get_final_stat_by_string(key_string)

func get_final_stat_by_string(key_string: StringName) -> float:
	if not base_stat_values.has(key_string):
		push_error("PlayerStats: Attempted to get unknown player stat: '", key_string, "'. Returning 0.0")
		return 0.0

	var final_value = base_stat_values.get(key_string, 0.0)

	# Apply flat modifiers directly to the base value.
	final_value += flat_modifiers.get(key_string, 0.0)

	# Apply percentage additions to base. This compounds additively.
	final_value *= (1.0 + percent_add_modifiers.get(key_string, 0.0))

	# Apply final multiplicative modifiers. This compounds multiplicatively.
	var final_multiplier = percent_mult_final_modifiers.get(key_string, 1.0)

	# Specific handling for stats that represent 'reduction' where a higher value means less effect.
	# For example, DAMAGE_REDUCTION_MULTIPLIER: 0.1 means 10% reduction, so (1.0 - 0.1) = 0.9 multiplier.
	if key_string == PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_REDUCTION_MULTIPLIER]:
		final_value *= (1.0 - final_multiplier) # Apply as a reduction
	elif key_string == PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_TAKEN_MULTIPLIER]:
		final_value *= final_multiplier # This is already a multiplier to damage taken, so it applies directly.
	# Add similar conditional logic for other reduction/inverse stats if needed.
	else:
		final_value *= final_multiplier # Default multiplication for most stats

	# Ensure minimum values for certain stats (e.g., damage/speed should not be negative)
	if (key_string == PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.NUMERICAL_DAMAGE] or
		key_string == PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED] or
		key_string == PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER]):
		return max(0.0, final_value)
	
	return final_value

# --- Unified Damage Calculation ---
# This method should be called by WeaponManager or individual attack scripts
# when they need to determine the final damage output from the player.
# It takes the 'weapon_damage_percentage' from the *specific weapon's* blueprint/instance data.
func get_calculated_player_damage(weapon_damage_percentage: float = 1.0) -> float:
	# This function uses the 'current_' cached values from recalculate_all_stats()
	# to ensure consistency and avoid re-calculating base stats.

	# Formula: (player_base_numerical_damage * weapon_damage_percentage) * player_global_damage_multiplier + player_global_flat_damage_add

	# 1. Start with the player's current numerical damage (which includes class base + flat/percent_add modifiers to it).
	var damage_from_player_base = current_numerical_damage

	# 2. Apply the weapon's specific percentage multiplier to the player's base damage component.
	var weapon_scaled_damage = damage_from_player_base * weapon_damage_percentage

	# 3. Apply the player's global damage multiplier (from class, general upgrades, etc.).
	var final_multiplied_damage = weapon_scaled_damage * current_global_damage_multiplier

	# 4. Add any flat damage bonuses from global player upgrades.
	var final_damage = final_multiplied_damage + current_global_flat_damage_add

	# Ensure damage is never negative
	return max(0.0, final_damage)


# --- Debug Setters for Player Stats (Used by DebugPanel) ---
# These methods allow direct modification of base stat values for testing/debugging.
# After modification, they trigger a full stat recalculation.
func debug_set_stat_base_value(key_enum: PlayerStatKeys.Keys, value): # Use PlayerStatKeys
	var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum] # Use PlayerStatKeys
	if base_stat_values.has(key_string):
		base_stat_values[key_string] = float(value)
		print("PlayerStats DEBUG: Set base value for '", key_string, "' to ", value)
		recalculate_all_stats()
	else:
		push_warning("PlayerStats DEBUG: Attempted to set unknown base stat: '", key_string, "'.")

func debug_reset_to_class_defaults():
	# This needs to re-load the initial class data and re-initialize stats.
	# It assumes the PlayerCharacter knows the initial class ID.
	var owner_player = get_parent() as PlayerCharacter
	if is_instance_valid(owner_player) and owner_player.has_method("get_current_basic_class_enum"):
		var initial_class_enum = owner_player.get_current_basic_class_enum()
		# Assuming PlayerCharacter.BasicClass is an accessible enum or StringName constant
		# If PlayerCharacter.BasicClass is an enum, you'd get its name like this:
		# var class_name_str = PlayerCharacter.BasicClass.keys()[initial_class_enum].to_lower()
		# If PlayerCharacter.BasicClass is a StringName (e.g., &"WARRIOR"), it's simpler.
		
		# For demonstration, let's assume `get_current_basic_class_id()` returns a StringName like &"warrior"
		# or that `get_current_basic_class_enum()` allows you to map to a string.
		var class_id_string: StringName = owner_player.get_current_basic_class_id() # Assuming this method exists and returns StringName
		
		if class_id_string != &"none": # Assuming 'none' or similar for uninitialized
			var class_data_path = "res://DataResources/Classes/" + str(class_id_string) + "_class_data.tres"
			
			if ResourceLoader.exists(class_data_path):
				var class_data_res = load(class_data_path) as PlayerClassData
				if is_instance_valid(class_data_res):
					initialize_base_stats(class_data_res) # Re-initialize with class defaults
					print("PlayerStats DEBUG: Reset to class defaults for ", class_data_res.display_name, ".")
				else:
					push_error("PlayerStats DEBUG: Failed to load PlayerClassData for reset: '", class_data_path, "'.")
			else:
				push_error("PlayerStats DEBUG: PlayerClassData path does not exist for reset: '", class_data_path, "'.")
		else:
			push_warning("PlayerStats DEBUG: Cannot reset to class defaults, initial basic class ID is 'none'.")
	else:
		push_error("PlayerStats DEBUG: Owner PlayerCharacter invalid or missing 'get_current_basic_class_id' for reset. Cannot reset stats.")


# --- Recalculation and Signal Emission ---
# This method should be called whenever player stats (base or modifiers) change.
# It recalculates final stats and updates the 'current_' properties.
func recalculate_all_stats():
	# Update all 'current_' stat properties from their calculated final values
	current_max_health = get_final_stat(PlayerStatKeys.Keys.MAX_HEALTH)
	current_numerical_damage = get_final_stat(PlayerStatKeys.Keys.NUMERICAL_DAMAGE)
	current_global_damage_multiplier = get_final_stat(PlayerStatKeys.Keys.GLOBAL_DAMAGE_MULTIPLIER)
	current_global_flat_damage_add = get_final_stat(PlayerStatKeys.Keys.GLOBAL_FLAT_DAMAGE_ADD)
	current_attack_speed_multiplier = get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	current_armor = get_final_stat(PlayerStatKeys.Keys.ARMOR)
	current_armor_penetration = get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
	current_movement_speed = get_final_stat(PlayerStatKeys.Keys.MOVEMENT_SPEED)
	current_magnet_range = get_final_stat(PlayerStatKeys.Keys.MAGNET_RANGE)
	current_experience_gain_multiplier = get_final_stat(PlayerStatKeys.Keys.EXPERIENCE_GAIN_MULTIPLIER)
	current_aoe_area_multiplier = get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	current_projectile_size_multiplier = get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	current_projectile_speed_multiplier = get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	current_effect_duration_multiplier = get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	current_crit_chance = get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE)
	current_crit_damage_multiplier = get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
	current_luck = get_final_stat(PlayerStatKeys.Keys.LUCK)
	current_health_regeneration = get_final_stat(PlayerStatKeys.Keys.HEALTH_REGENERATION)
	# Add more 'current_' stat updates here for any other relevant keys

	# Emit signal with current critical stats for listeners to update.
	emit_signal("stats_recalculated",
				current_max_health, # Use the updated 'current_' value
				current_movement_speed) # Use the updated 'current_' value
