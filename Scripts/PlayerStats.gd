# player_stats.gd
# This script manages all player statistics. It will now use the standardized keys
# defined via the 'GameStatConstants' Autoload.
# It is designed to be a child node of PlayerCharacter.
#
# IMPORTANT: This script should replace your existing PlayerStats.gd.
# 'GameStatConstants' must be set as an Autoload (see Step 2 in previous instructions).

extends Node
class_name PlayerStats # Explicit class name for clarity and type hinting

# Signal to notify listeners (e.g., PlayerCharacter) when player stats have been recalculated.
signal stats_recalculated(current_max_health_val, current_movement_speed_val) # Added signal declaration

# Dictionary to hold the final calculated base stats after initialization.
# This represents the player's core stats before temporary buffs/debuffs are applied.
var base_stat_values: Dictionary = {}

# Dictionaries to hold modifiers. These will accumulate modifications from upgrades
# and temporary effects.
var flat_modifiers: Dictionary = {}               # For flat additions (e.g., +5 Health)
var percent_add_modifiers: Dictionary = {}        # For percentage additions to base (e.g., +10% Movement Speed)
var percent_mult_final_modifiers: Dictionary = {} # For final percentage multipliers (e.g., +20% Global Damage)
# Note: For effects like 'damage_reduction_multiplier', the percentage is applied as (1.0 - value).
# This is handled in get_final_stat().

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
	# Clear any previous stats to ensure a clean slate
	base_stat_values.clear()
	flat_modifiers.clear()
	percent_add_modifiers.clear()
	percent_mult_final_modifiers.clear()

	# Get the standardized dictionary of initial stats from PlayerClassData
	var initial_class_stats: Dictionary = class_data.get_base_stats_as_standardized_dict()

	# Iterate through all known stat keys defined in GameStatConstants.Keys
	for key_enum_value in GameStatConstants.Keys.values():
		var key_string: StringName = GameStatConstants.KEY_NAMES[key_enum_value]

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
	# Example: print initial health
	print("Initial Max Health: ", get_final_stat(GameStatConstants.Keys.MAX_HEALTH))
	print("Initial Numerical Damage: ", get_final_stat(GameStatConstants.Keys.NUMERICAL_DAMAGE))

	# After initial setup, recalculate and emit signal
	recalculate_all_stats()

# This method is a fallback for debugging, to initialize with raw dictionary data.
func initialize_base_stats_with_raw_dict(raw_stats_dict: Dictionary):
	base_stat_values.clear()
	flat_modifiers.clear()
	percent_add_modifiers.clear()
	percent_mult_final_modifiers.clear()

	for key_enum_value in GameStatConstants.Keys.values():
		var key_string: StringName = GameStatConstants.KEY_NAMES[key_enum_value]
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
	var modification_type_string_name: StringName = &"" + str(effect_data.modification_type)
	var target_stat_key_string: StringName = effect_data.stat_key
	var value = effect_data.get_value()

	if not base_stat_values.has(target_stat_key_string):
		push_error("PlayerStats: Attempted to modify unknown player stat: ", target_stat_key_string)
		return

	match modification_type_string_name:
		&"flat_add":
			base_stat_values[target_stat_key_string] += value
		&"percent_add_to_base":
			percent_add_modifiers[target_stat_key_string] += value
		&"percent_mult_final":
			percent_mult_final_modifiers[target_stat_key_string] *= (1.0 + value)
		&"override_value":
			base_stat_values[target_stat_key_string] = value
		_:
			push_error("PlayerStats: Unknown modification type: ", modification_type_string_name)

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
	# Flags generally don't trigger a full stat recalculation unless they affect calculated stats

func get_flag(flag_key_enum: GameStatConstants.Keys) -> bool:
	var flag_key_string: StringName = GameStatConstants.KEY_NAMES[flag_key_enum]
	return player_flags.get(flag_key_string, false) # Default to false if flag not set


# --- Getting Final Stat Value ---
# This function calculates the final value of a stat after applying all modifiers.
func get_final_stat(key_enum: GameStatConstants.Keys) -> float:
	var key_string: StringName = GameStatConstants.KEY_NAMES[key_enum]
	return get_final_stat_by_string(key_string)

func get_final_stat_by_string(key_string: StringName) -> float:
	if not base_stat_values.has(key_string):
		push_error("PlayerStats: Attempted to get unknown player stat: ", key_string)
		return 0.0

	var final_value = base_stat_values.get(key_string, 0.0)

	final_value += flat_modifiers.get(key_string, 0.0) # Apply flat modifiers

	final_value *= (1.0 + percent_add_modifiers.get(key_string, 0.0)) # Apply percent_add_to_base

	var final_multiplier = percent_mult_final_modifiers.get(key_string, 1.0)

	# Specific handling for stats that are reductions (e.g., Damage Reduction)
	if key_string == GameStatConstants.KEY_NAMES[GameStatConstants.Keys.DAMAGE_REDUCTION_MULTIPLIER]:
		final_value *= (1.0 - final_multiplier)
	else:
		final_value *= final_multiplier

	return final_value


# --- Debug Setters for Player Stats (Used by DebugPanel) ---
# These methods allow direct modification of base stat values for testing/debugging.
# After modification, they trigger a full stat recalculation.
func debug_set_stat_base_value(key_enum: GameStatConstants.Keys, value):
	var key_string: StringName = GameStatConstants.KEY_NAMES[key_enum]
	if base_stat_values.has(key_string):
		base_stat_values[key_string] = float(value)
		print("PlayerStats DEBUG: Set base value for '", key_string, "' to ", value)
		recalculate_all_stats()
	else:
		push_warning("PlayerStats DEBUG: Attempted to set unknown base stat: ", key_string)

func debug_reset_to_class_defaults():
	# This needs to re-load the initial class data and re-initialize stats.
	# It assumes the PlayerCharacter knows the initial class ID.
	var owner_player = get_parent() as PlayerCharacter
	if is_instance_valid(owner_player) and owner_player.has_method("get_current_basic_class_enum"):
		var initial_class_enum = owner_player.get_current_basic_class_enum()
		if initial_class_enum != PlayerCharacter.BasicClass.NONE:
			var class_name_str = PlayerCharacter.BasicClass.keys()[initial_class_enum].to_lower()
			var class_data_path = "res://DataResources/Classes/" + class_name_str + "_class_data.tres"
			
			if ResourceLoader.exists(class_data_path):
				var class_data_res = load(class_data_path) as PlayerClassData
				if is_instance_valid(class_data_res):
					initialize_base_stats(class_data_res) # Re-initialize with class defaults
					print("PlayerStats DEBUG: Reset to class defaults for ", class_name_str)
				else:
					push_error("PlayerStats DEBUG: Failed to load PlayerClassData for reset: ", class_data_path)
			else:
				push_error("PlayerStats DEBUG: PlayerClassData path does not exist for reset: ", class_data_path)
		else:
			push_warning("PlayerStats DEBUG: Cannot reset to class defaults, initial basic class is NONE.")
	else:
		push_error("PlayerStats DEBUG: Owner PlayerCharacter invalid or missing 'get_current_basic_class_enum' for reset.")


# --- Recalculation and Signal Emission ---
# This method should be called whenever player stats (base or modifiers) change.
# It recalculates final stats and emits a signal to notify listeners.
func recalculate_all_stats():
	# In a more complex system, you might aggregate temporary modifiers from StatusEffectComponent here
	# For now, this just recalculates based on base_stat_values and internal modifiers.

	# Emit signal with current critical stats for listeners to update.
	emit_signal("stats_recalculated",
				get_final_stat(GameStatConstants.Keys.MAX_HEALTH),
				get_final_stat(GameStatConstants.Keys.MOVEMENT_SPEED))
