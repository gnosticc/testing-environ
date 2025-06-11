# player_stats.gd
# This script manages all player statistics. It will now use the standardized keys
# defined via the 'PlayerStatKeys' Autoload.
# It is designed to be a child node of PlayerCharacter.
#
# IMPORTANT: This script should replace your existing PlayerStats.gd.
# 'PlayerStatKeys' must be set as an Autoload (see Step 2 in previous instructions).
#
# UPDATED: Added new global stat properties and their recalculation.
# UPDATED: get_calculated_player_damage now accepts weapon tags to apply tag-specific multipliers.
# FIXED: Ensured ALL PlayerStatKeys are properly initialized in base_stat_values and modifier dictionaries.
# ADDED: More comprehensive debug prints for stat initialization and recalculation.

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

# NEW: Current calculated values for recently added global stats
var current_global_percent_damage_reduction: float = 0.0
var current_global_status_effect_chance_add: float = 0.0
var current_global_projectile_fork_count_add: int = 0
var current_global_projectile_bounce_count_add: int = 0
var current_global_projectile_explode_on_death_chance: float = 0.0
var current_global_chain_lightning_count: int = 0
var current_global_lifesteal_percent: float = 0.0
var current_global_flat_damage_reduction: float = 0.0
var current_invulnerability_duration_add: float = 0.0
var current_global_gold_gain_multiplier: float = 1.0
var current_item_drop_chance_add: float = 0.0 # Assuming this is an additive chance (e.g., +0.05 for 5%)
var current_global_summon_damage_multiplier: float = 1.0
var current_global_summon_lifetime_multiplier: float = 1.0
var current_global_summon_count_add: int = 0
var current_global_summon_cooldown_reduction_percent: float = 0.0
var current_enemy_debuff_resistance_reduction: float = 0.0
var current_dodge_chance: float = 0.0

# Add other 'current_' stats here as needed, based on your PlayerStatKeys.Keys
# For Tag-Specific Multipliers (these are read directly from get_final_stat_by_string, not cached here)
# MELEE_DAMAGE_MULTIPLIER
# PROJECTILE_DAMAGE_MULTIPLIER
# MAGIC_DAMAGE_MULTIPLIER
# PHYSICAL_DAMAGE_MULTIPLIER
# FIRE_DAMAGE_MULTIPLIER
# ICE_DAMAGE_MULTIPLIER
# MELEE_ATTACK_SPEED_MULTIPLIER
# PROJECTILE_ATTACK_SPEED_MULTIPLIER
# MAGIC_ATTACK_SPEED_MULTIPLIER
# MELEE_AOE_AREA_MULTIPLIER
# MAGIC_AOE_AREA_MULTIPLIER
# PROJECTILE_PIERCE_COUNT_ADD (already cached as int)
# PROJECTILE_MAX_RANGE_ADD (already cached as float)

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

	# FIXED: Ensure ALL PlayerStatKeys are properly initialized here.
	# Iterate through all known stat keys defined in PlayerStatKeys.Keys
	for key_enum_value in PlayerStatKeys.Keys.values():
		var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum_value]

		# Initialize base_stat_values using the values from PlayerClassData if available.
		# For new stats not in PlayerClassData, they will be initialized to 0.0 (or 1.0 for multipliers).
		var base_val = float(initial_class_stats.get(key_string, 0.0))
		
		# Specific defaults for multipliers
		if key_string in [
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_DEBUFF_POTENCY_MULT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_BUFF_POTENCY_MULT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CURRENCY_GAIN_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_GOLD_GAIN_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_SUMMON_LIFETIME_MULTIPLIER],
			# Tag-specific multipliers default to 1.0
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MELEE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGIC_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PHYSICAL_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.FIRE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ICE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MELEE_ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGIC_ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MELEE_AOE_AREA_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGIC_AOE_AREA_MULTIPLIER],
		]:
			# If the class data provides a value, use it, otherwise default to 1.0 for multipliers
			base_stat_values[key_string] = float(initial_class_stats.get(key_string, 1.0))
			percent_mult_final_modifiers[key_string] = 1.0 # Initialize multiplier modifier to 1.0
		# For percentage reduction stats, default to 0.0 as it's a reduction amount
		elif key_string in [
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DODGE_CHANCE],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_SUMMON_COOLDOWN_REDUCTION_PERCENT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ENEMY_DEBUFF_RESISTANCE_REDUCTION],
		]:
			base_stat_values[key_string] = float(initial_class_stats.get(key_string, 0.0))
			percent_add_modifiers[key_string] = 0.0 # These are typically added percentages
		else:
			# For all other stats (flat adds, counts, etc.), use 0.0 as default
			base_stat_values[key_string] = base_val
			flat_modifiers[key_string] = 0.0
			percent_add_modifiers[key_string] = 0.0
			percent_mult_final_modifiers[key_string] = 1.0 # Default all remaining to 1.0 if not already set

	print("PlayerStats: Initialized base stats for class: ", class_data.display_name)
	# After initial setup, recalculate and emit signal
	recalculate_all_stats()
	print("PlayerStats DEBUG: After initialization and first recalculation:")
	print("  MAX_HEALTH: ", current_max_health)
	print("  NUMERICAL_DAMAGE: ", current_numerical_damage)
	print("  GLOBAL_DAMAGE_MULTIPLIER: ", current_global_damage_multiplier)
	print("  GLOBAL_FLAT_DAMAGE_ADD: ", current_global_flat_damage_add)
	print("  MOVEMENT_SPEED: ", current_movement_speed)
	print("  PROJECTILE_DAMAGE_MULTIPLIER (example): ", get_final_stat(PlayerStatKeys.Keys.PROJECTILE_DAMAGE_MULTIPLIER))


# This method is a fallback for debugging, to initialize with raw dictionary data.
func initialize_base_stats_with_raw_dict(raw_stats_dict: Dictionary):
	base_stat_values.clear()
	flat_modifiers.clear()
	percent_add_modifiers.clear()
	percent_mult_final_modifiers.clear()

	# FIXED: Ensure ALL PlayerStatKeys are properly initialized here for debug fallback too.
	for key_enum_value in PlayerStatKeys.Keys.values(): # Use PlayerStatKeys
		var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum_value] # Use PlayerStatKeys
		
		var base_val = float(raw_stats_dict.get(key_string, 0.0))
		
		# Specific defaults for multipliers (copied from initialize_base_stats)
		if key_string in [
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_DEBUFF_POTENCY_MULT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_BUFF_POTENCY_MULT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CURRENCY_GAIN_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_GOLD_GAIN_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_SUMMON_LIFETIME_MULTIPLIER],
			# Tag-specific multipliers default to 1.0
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MELEE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGIC_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PHYSICAL_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.FIRE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ICE_DAMAGE_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MELEE_ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGIC_ATTACK_SPEED_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MELEE_AOE_AREA_MULTIPLIER],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGIC_AOE_AREA_MULTIPLIER],
		]:
			base_stat_values[key_string] = float(raw_stats_dict.get(key_string, 1.0))
			percent_mult_final_modifiers[key_string] = 1.0
		elif key_string in [
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DODGE_CHANCE],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_SUMMON_COOLDOWN_REDUCTION_PERCENT],
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ENEMY_DEBUFF_RESISTANCE_REDUCTION],
		]:
			base_stat_values[key_string] = float(raw_stats_dict.get(key_string, 0.0))
			percent_add_modifiers[key_string] = 0.0
		else:
			base_stat_values[key_string] = base_val
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
	elif key_string == PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION]:
		final_value = final_value * (1.0 - final_multiplier) # Apply as a percentage reduction from 1.0
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
# It now accepts an array of weapon tags to apply tag-specific multipliers.
func get_calculated_player_damage(weapon_damage_percentage: float = 1.0, weapon_tags: Array[StringName] = []) -> float:
	# This function uses the 'current_' cached values from recalculate_all_stats()
	# to ensure consistency and avoid re-calculating base stats.

	# Formula: (player_base_numerical_damage * weapon_damage_percentage * tag_multipliers) * player_global_damage_multiplier + player_global_flat_damage_add

	# 1. Start with the player's current numerical damage (which includes class base + flat/percent_add modifiers to it).
	var damage_from_player_base = current_numerical_damage

	# 2. Apply the weapon's specific percentage multiplier to the player's base damage component.
	var weapon_scaled_damage = damage_from_player_base * weapon_damage_percentage

	# 3. Apply tag-specific damage multipliers.
	var tag_damage_multiplier = 1.0
	for tag in weapon_tags:
		# Map tags to their corresponding damage multiplier keys
		var tag_key: StringName = &""
		match tag:
			&"melee": tag_key = PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MELEE_DAMAGE_MULTIPLIER]
			&"projectile": tag_key = PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_DAMAGE_MULTIPLIER]
			&"magic": tag_key = PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGIC_DAMAGE_MULTIPLIER]
			&"physical": tag_key = PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PHYSICAL_DAMAGE_MULTIPLIER] # Refers to the 'physical' tag
			&"fire": tag_key = PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.FIRE_DAMAGE_MULTIPLIER]
			&"ice": tag_key = PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ICE_DAMAGE_MULTIPLIER]
			_: continue # Skip if tag doesn't have a corresponding damage multiplier stat

		# Get and apply the multiplier for this tag.
		# Note: get_final_stat_by_string will return 1.0 if the stat is not found/initialized.
		tag_damage_multiplier *= get_final_stat_by_string(tag_key)

	weapon_scaled_damage *= tag_damage_multiplier

	# 4. Apply the player's global damage multiplier (from class, general upgrades, etc.).
	var final_multiplied_damage = weapon_scaled_damage * current_global_damage_multiplier

	# 5. Add any flat damage bonuses from global player upgrades.
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
	if is_instance_valid(owner_player) and owner_player.has_method("get_current_basic_class_id"): # Changed to get_current_basic_class_id
		var class_id_string: StringName = owner_player.get_current_basic_class_id() # Use new method
		
		if class_id_string != &"none": # Assuming 'none' or similar for uninitialized
			var class_data_path = "res://Data/Classes/" + str(class_id_string) + "_class_data.tres" # Corrected path to res://Data/Classes
			
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

	# NEW: Recalculate newly added global stats
	current_global_percent_damage_reduction = get_final_stat(PlayerStatKeys.Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION)
	current_global_status_effect_chance_add = get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)
	current_global_projectile_fork_count_add = int(get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_FORK_COUNT_ADD))
	current_global_projectile_bounce_count_add = int(get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_BOUNCE_COUNT_ADD))
	current_global_projectile_explode_on_death_chance = get_final_stat(PlayerStatKeys.Keys.GLOBAL_PROJECTILE_EXPLODE_ON_DEATH_CHANCE)
	current_global_chain_lightning_count = int(get_final_stat(PlayerStatKeys.Keys.GLOBAL_CHAIN_LIGHTNING_COUNT))
	current_global_lifesteal_percent = get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
	current_global_flat_damage_reduction = get_final_stat(PlayerStatKeys.Keys.GLOBAL_FLAT_DAMAGE_REDUCTION)
	current_invulnerability_duration_add = get_final_stat(PlayerStatKeys.Keys.INVULNERABILITY_DURATION_ADD)
	current_global_gold_gain_multiplier = get_final_stat(PlayerStatKeys.Keys.GLOBAL_GOLD_GAIN_MULTIPLIER)
	current_item_drop_chance_add = get_final_stat(PlayerStatKeys.Keys.ITEM_DROP_CHANCE_ADD)
	current_global_summon_damage_multiplier = get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER)
	current_global_summon_lifetime_multiplier = get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_LIFETIME_MULTIPLIER)
	current_global_summon_count_add = int(get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_COUNT_ADD))
	current_global_summon_cooldown_reduction_percent = get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_COOLDOWN_REDUCTION_PERCENT)
	current_enemy_debuff_resistance_reduction = get_final_stat(PlayerStatKeys.Keys.ENEMY_DEBUFF_RESISTANCE_REDUCTION)
	current_dodge_chance = get_final_stat(PlayerStatKeys.Keys.DODGE_CHANCE)
	# Add more 'current_' stat updates here for any other relevant keys

	# Emit signal with current critical stats for listeners to update.
	emit_signal("stats_recalculated",
				current_max_health, # Use the updated 'current_' value
				current_movement_speed) # Use the updated 'current_' value
