# player_class_data.gd
# This resource defines the base attributes for each player class,
# using the specific set of base stats you've provided and maps them
# to the standardized PlayerStatKeys.
#
# IMPORTANT: This script should replace your existing PlayerClassData.gd.
# It now accesses the global stat keys via the 'GameStatConstants' Autoload.

extends Resource
class_name PlayerClassData

# Exported variables that can be set directly in the Godot Inspector
@export var id: StringName = &""
@export var display_name: String = "New Class"

@export_group("Core Combat Stats")
@export_range(1, 1000) var base_max_health: int = 100
@export_range(0.0, 10.0, 0.01) var base_health_regeneration: float = 0.0 # HP per second
@export_range(1, 500) var base_numerical_damage: int = 10 # Player's core damage value
@export_range(0.5, 5.0, 0.01) var base_global_damage_multiplier: float = 1.0 # Player's global damage multiplier
@export_range(0.1, 5.0, 0.01) var base_attack_speed_multiplier: float = 1.0
@export_range(0, 100) var base_armor: int = 0
@export_range(0.0, 100.0, 0.1) var base_armor_penetration: float = 0.0 # Player's base armor penetration

@export_group("Movement & Utility")
@export_range(10.0, 500.0, 1.0) var base_movement_speed: float = 60.0
@export_range(0.0, 1000.0, 1.0) var base_magnet_range: float = 40.0
@export_range(0.5, 5.0, 0.01) var base_experience_gain_multiplier: float = 1.0

@export_group("Weapon Effect Modifiers")
@export_range(0.5, 5.0, 0.01) var base_aoe_area_multiplier: float = 1.0
@export_range(0.5, 5.0, 0.01) var base_projectile_size_multiplier: float = 1.0
@export_range(0.5, 5.0, 0.01) var base_projectile_speed_multiplier: float = 1.0
@export_range(0.5, 5.0, 0.01) var base_effect_duration_multiplier: float = 1.0

@export_group("Critical Hit Stats")
@export_range(0.0, 1.0, 0.01) var base_crit_chance: float = 0.05
@export_range(1.0, 5.0, 0.01) var base_crit_damage_multiplier: float = 1.5

@export_group("Other Stats")
@export_range(0, 1000) var base_luck: int = 0

# --- Helper to convert exported properties to a dictionary using standardized keys ---
# This method will be called by PlayerCharacter.gd when initializing PlayerStats.
# It ensures that PlayerStats receives a dictionary with consistent StringName keys.
func get_base_stats_as_standardized_dict() -> Dictionary:
	var stats_dict = {}

	# Map each exported 'base_' property to its corresponding GameStatConstants.KEY_NAMES
	# This ensures consistency in how stats are referenced in PlayerStats.gd
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.MAX_HEALTH]] = base_max_health
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.HEALTH_REGENERATION]] = base_health_regeneration
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.NUMERICAL_DAMAGE]] = base_numerical_damage
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.GLOBAL_DAMAGE_MULTIPLIER]] = base_global_damage_multiplier
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.ATTACK_SPEED_MULTIPLIER]] = base_attack_speed_multiplier
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.ARMOR]] = base_armor
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.ARMOR_PENETRATION]] = base_armor_penetration

	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.MOVEMENT_SPEED]] = base_movement_speed
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.MAGNET_RANGE]] = base_magnet_range
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.EXPERIENCE_GAIN_MULTIPLIER]] = base_experience_gain_multiplier

	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.AOE_AREA_MULTIPLIER]] = base_aoe_area_multiplier
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.PROJECTILE_SIZE_MULTIPLIER]] = base_projectile_size_multiplier
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.PROJECTILE_SPEED_MULTIPLIER]] = base_projectile_speed_multiplier
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.EFFECT_DURATION_MULTIPLIER]] = base_effect_duration_multiplier

	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.CRIT_CHANCE]] = base_crit_chance
	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.CRIT_DAMAGE_MULTIPLIER]] = base_crit_damage_multiplier

	stats_dict[GameStatConstants.KEY_NAMES[GameStatConstants.Keys.LUCK]] = base_luck

	return stats_dict
