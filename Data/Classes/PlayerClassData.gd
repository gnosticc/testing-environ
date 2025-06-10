# player_class_data.gd
# This resource defines the base attributes for each player class,
# using the specific set of base stats you've provided and maps them
# to the standardized PlayerStatKeys.
#
# IMPORTANT: This script should replace your existing PlayerClassData.gd.
# It now accesses the global stat keys via the 'PlayerStatKeys' Autoload.

extends Resource
class_name PlayerClassData

# Exported variables that can be set directly in the Godot Inspector
@export var id: StringName = &""
@export var display_name: String = "New Class"

@export_group("Core Health & Regeneration") # Added group for clarity
@export_range(1, 1000) var base_max_health: int = 100
@export_range(0.0, 10.0, 0.01) var base_health_regeneration: float = 0.0 # HP per second
# Consider if HEALTH_ON_HIT_FLAT, HEALTH_ON_KILL_FLAT, HEALTH_ON_KILL_PERCENT_MAX should be base class stats.
# If they are generally gained from upgrades, they don't need to be here.
# If a class provides a base amount of these, add them with @export_range as appropriate.
# @export_range(0, 100) var base_health_on_hit_flat: int = 0 # Example if you want it as a base stat

@export_group("Core Combat Stats")
@export_range(1, 500) var base_numerical_damage: int = 10 # Player's core damage value
@export_range(0.5, 5.0, 0.01) var base_global_damage_multiplier: float = 1.0 # Player's global damage multiplier
@export_range(0.1, 5.0, 0.01) var base_attack_speed_multiplier: float = 1.0
@export_range(0, 100) var base_armor: int = 0
@export_range(0.0, 100.0, 0.1) var base_armor_penetration: float = 0.0 # Player's base armor penetration

@export_group("Movement & Utility")
@export_range(10.0, 500.0, 1.0) var base_movement_speed: float = 60.0
@export_range(0.0, 1000.0, 1.0) var base_magnet_range: float = 40.0
@export_range(0.5, 5.0, 0.01) var base_experience_gain_multiplier: float = 1.0

@export_group("Weapon Effect Modifiers (Global)") # Renamed group for clarity, these affect ALL weapons
@export_range(0.5, 5.0, 0.01) var base_aoe_area_multiplier: float = 1.0
@export_range(0.5, 5.0, 0.01) var base_projectile_size_multiplier: float = 1.0
@export_range(0.5, 5.0, 0.01) var base_projectile_speed_multiplier: float = 1.0
@export_range(0.5, 5.0, 0.01) var base_effect_duration_multiplier: float = 1.0
# Consider if GLOBAL_PROJECTILE_COUNT_ADD should be a base class stat.
# If so, add it here with @export_range.
# @export_range(0, 10) var base_global_projectile_count_add: int = 0 # Example

@export_group("Critical Hit Stats")
@export_range(0.0, 1.0, 0.01) var base_crit_chance: float = 0.05
@export_range(1.0, 5.0, 0.01) var base_crit_damage_multiplier: float = 1.5

@export_group("Other Core Stats") # Renamed group for clarity
@export_range(0, 1000) var base_luck: int = 0

# --- Advanced Defensive Stats (typically gained from upgrades/effects) ---
# If any class inherently starts with a base amount of these, add them here.
# Otherwise, it's good that they are not here, as they'd typically come from upgrades.
# Example: @export_range(0.0, 1.0, 0.01) var base_damage_reduction_multiplier: float = 0.0
# Example: @export_range(0.0, 1.0, 0.01) var base_dodge_chance: float = 0.0

# --- Resource Management (Mana/Stamina/Energy) ---
# If your player classes will have inherent base values for resources like Mana/Stamina,
# define them here. If not, these would typically be added via upgrades.
# @export_group("Resource Stats")
# @export_range(0, 500) var base_mana_max: int = 0 # Example for Mana
# @export_range(0.0, 10.0, 0.01) var base_mana_regeneration_rate: float = 0.0 # Example

# --- Helper to convert exported properties to a dictionary using standardized keys ---
# This method will be called by PlayerCharacter.gd when initializing PlayerStats.
# It ensures that PlayerStats receives a dictionary with consistent StringName keys.
func get_base_stats_as_standardized_dict() -> Dictionary:
	var stats_dict = {}

	# Map each exported 'base_' property to its corresponding PlayerStatKeys.KEY_NAMES
	# This ensures consistency in how stats are referenced in PlayerStats.gd
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAX_HEALTH]] = base_max_health
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.HEALTH_REGENERATION]] = base_health_regeneration
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.NUMERICAL_DAMAGE]] = base_numerical_damage
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_DAMAGE_MULTIPLIER]] = base_global_damage_multiplier
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER]] = base_attack_speed_multiplier
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR]] = base_armor
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]] = base_armor_penetration

	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED]] = base_movement_speed
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGNET_RANGE]] = base_magnet_range
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.EXPERIENCE_GAIN_MULTIPLIER]] = base_experience_gain_multiplier

	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER]] = base_aoe_area_multiplier
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER]] = base_projectile_size_multiplier
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER]] = base_projectile_speed_multiplier
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER]] = base_effect_duration_multiplier

	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CRIT_CHANCE]] = base_crit_chance
	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER]] = base_crit_damage_multiplier

	stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.LUCK]] = base_luck
	
	# --- Add any newly introduced base stats here, mirroring the pattern above ---
	# Example if you added base_health_on_hit_flat:
	# stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.HEALTH_ON_HIT_FLAT]] = base_health_on_hit_flat
	# Example if you added base_global_projectile_count_add:
	# stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_PROJECTILE_COUNT_ADD]] = base_global_projectile_count_add
	# Example for Mana:
	# stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MANA_MAX]] = base_mana_max
	# stats_dict[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MANA_REGENERATION_RATE]] = base_mana_regeneration_rate

	return stats_dict
