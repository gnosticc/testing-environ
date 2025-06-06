# PlayerStats.gd
# Manages all player statistics.
# Corrected _process_stat_modification_effect to use get_value().
class_name PlayerStats
extends Node

signal stats_recalculated

# Base stats loaded from PlayerClassData
var base_stats: Dictionary = {
	"max_health": 100, "health_regeneration": 0.0, "base_numerical_damage": 10,
	"global_damage_multiplier": 1.0, "global_flat_damage_add": 0.0,
	"attack_speed_multiplier": 1.0, "armor": 0, "armor_penetration": 0.0,
	"movement_speed": 60.0, "magnet_range": 40.0, "experience_gain_multiplier": 1.0,
	"aoe_area_multiplier": 1.0, "projectile_size_multiplier": 1.0,
	"projectile_speed_multiplier": 1.0, "effect_duration_multiplier": 1.0,
	"crit_chance": 0.05, "crit_damage_multiplier": 1.5, "luck": 0
}

# Dictionaries to store modifiers from upgrades/effects
var flat_modifiers: Dictionary = {}          
var percent_add_modifiers: Dictionary = {} 
var percent_mult_modifiers: Dictionary = {}

# Dictionary to store the final calculated stat values after all modifiers
var current_calculated_stats: Dictionary = {}

func _ready():
	recalculate_all_stats() 

func initialize_with_class_data(class_data: PlayerClassData):
	if not is_instance_valid(class_data):
		print_debug("ERROR (PlayerStats): Invalid PlayerClassData provided for initialization.")
		recalculate_all_stats()
		return

	# print_debug("PlayerStats: Initializing with PlayerClassData: ", class_data.resource_path if class_data else "Null")
	base_stats["max_health"] = class_data.base_max_health
	base_stats["health_regeneration"] = class_data.base_health_regeneration
	base_stats["base_numerical_damage"] = class_data.base_numerical_damage
	base_stats["global_damage_multiplier"] = class_data.base_global_damage_multiplier
	base_stats["attack_speed_multiplier"] = class_data.base_attack_speed_multiplier
	base_stats["armor"] = class_data.base_armor
	base_stats["armor_penetration"] = class_data.base_armor_penetration
	base_stats["movement_speed"] = class_data.base_movement_speed
	base_stats["magnet_range"] = class_data.base_magnet_range
	base_stats["experience_gain_multiplier"] = class_data.base_experience_gain_multiplier
	base_stats["aoe_area_multiplier"] = class_data.base_aoe_area_multiplier
	base_stats["projectile_size_multiplier"] = class_data.base_projectile_size_multiplier
	base_stats["projectile_speed_multiplier"] = class_data.base_projectile_speed_multiplier
	base_stats["effect_duration_multiplier"] = class_data.base_effect_duration_multiplier
	base_stats["crit_chance"] = class_data.base_crit_chance
	base_stats["crit_damage_multiplier"] = class_data.base_crit_damage_multiplier
	base_stats["luck"] = class_data.base_luck
	
	recalculate_all_stats()

func initialize_with_raw_stats(raw_stats_dict: Dictionary):
	print_debug("PlayerStats: Initializing with RAW stats dictionary.")
	for key in raw_stats_dict:
		if base_stats.has(key):
			base_stats[key] = raw_stats_dict[key]
		else:
			print_debug("PlayerStats WARN: Raw stat key '", key, "' not found in base_stats template.")
	recalculate_all_stats()


func apply_effects_from_card(card_data: GeneralUpgradeCardData):
	if not is_instance_valid(card_data): return
	print_debug("PlayerStats: Applying effects from GeneralUpgradeCardData: ", card_data.title)
	for effect_res in card_data.effects:
		if effect_res is StatModificationEffectData:
			var stat_mod_effect = effect_res as StatModificationEffectData
			if stat_mod_effect.target_scope == &"player_stats": 
				_process_stat_modification_effect(stat_mod_effect)
	recalculate_all_stats()

# This is the function that needs the fix.
func _process_stat_modification_effect(stat_mod_effect: StatModificationEffectData):
	var key = stat_mod_effect.stat_key
	# CORRECTED: Use get_value() instead of accessing .value
	var value = stat_mod_effect.get_value() 
	var mod_type = stat_mod_effect.modification_type

	match mod_type:
		&"flat_add":
			flat_modifiers[key] = flat_modifiers.get(key, 0.0) + value
			print_debug("  Applied flat_add: ", key, " +=", value, " -> ", flat_modifiers[key])
		&"percent_add_to_base":
			percent_add_modifiers[key] = percent_add_modifiers.get(key, 0.0) + value
			print_debug("  Applied percent_add_to_base: ", key, " +=", value, " -> ", percent_add_modifiers[key])
		&"percent_mult_final":
			percent_mult_modifiers[key] = percent_mult_modifiers.get(key, 1.0) * (1.0 + value) 
			print_debug("  Applied percent_mult_final: ", key, " *=", (1.0 + value), " -> ", percent_mult_modifiers[key])
		&"override_value":
			base_stats[key] = value 
			flat_modifiers.erase(key)
			percent_add_modifiers.erase(key)
			percent_mult_modifiers.erase(key)
			print_debug("  Applied override_value: ", key, " set to ", value)
		_:
			print_debug("PlayerStats WARN: Unknown modification_type '", mod_type, "' for stat '", key, "'")


func recalculate_all_stats():
	current_calculated_stats.clear()
	print_debug("PlayerStats: Recalculating stats.")
	for stat_name in base_stats:
		var base_val = base_stats.get(stat_name, 0.0)
		var flat_add = flat_modifiers.get(stat_name, 0.0)
		var percent_add_sum = percent_add_modifiers.get(stat_name, 0.0)
		var percent_mult_prod = percent_mult_modifiers.get(stat_name, 1.0)

		var calculated_val = (base_val + flat_add) * (1.0 + percent_add_sum)
		calculated_val *= percent_mult_prod
		if stat_name == "max_health":
			print_debug("  max_health base_val: ", base_stats.get("max_health"))
			print_debug("  max_health flat_add: ", flat_modifiers.get("max_health"))
			print_debug("  max_health percent_add_sum: ", percent_add_modifiers.get("max_health"))
			print_debug("  max_health percent_mult_prod: ", percent_mult_modifiers.get("max_health"))
			print_debug("  Calculated max_health before int(round): ", calculated_val)
			print_debug("  Final current_calculated_stats[max_health]: ", int(round(calculated_val)))

		if stat_name in ["max_health", "armor", "luck", "base_numerical_damage"]: 
			current_calculated_stats[stat_name] = int(round(calculated_val))
		else:
			current_calculated_stats[stat_name] = calculated_val
			
	emit_signal("stats_recalculated")

# --- Getters for current calculated stats ---
func get_max_health() -> int: return current_calculated_stats.get("max_health", 100)
func get_health_regeneration() -> float: return current_calculated_stats.get("health_regeneration", 0.0)
func get_current_base_numerical_damage() -> int: return current_calculated_stats.get("base_numerical_damage", 10)
func get_current_global_damage_multiplier() -> float: return current_calculated_stats.get("global_damage_multiplier", 1.0)
func get_current_global_flat_damage_add() -> float: return current_calculated_stats.get("global_flat_damage_add", 0.0)
func get_current_attack_speed_multiplier() -> float: return current_calculated_stats.get("attack_speed_multiplier", 1.0)
func get_armor() -> int: return current_calculated_stats.get("armor", 0)
func get_current_armor_penetration() -> float: return current_calculated_stats.get("armor_penetration", 0.0)
func get_movement_speed() -> float: return current_calculated_stats.get("movement_speed", 60.0)
func get_magnet_range() -> float: return current_calculated_stats.get("magnet_range", 10.0)
func get_experience_gain_multiplier() -> float: return current_calculated_stats.get("experience_gain_multiplier", 1.0)
func get_current_aoe_area_multiplier() -> float: return current_calculated_stats.get("aoe_area_multiplier", 1.0)
func get_current_projectile_size_multiplier() -> float: return current_calculated_stats.get("projectile_size_multiplier", 1.0)
func get_current_projectile_speed_multiplier() -> float: return current_calculated_stats.get("projectile_speed_multiplier", 1.0)
func get_current_effect_duration_multiplier() -> float: return current_calculated_stats.get("effect_duration_multiplier", 1.0)
func get_crit_chance() -> float: return current_calculated_stats.get("crit_chance", 0.05)
func get_crit_damage_multiplier() -> float: return current_calculated_stats.get("crit_damage_multiplier", 1.5)
func get_luck() -> int: return current_calculated_stats.get("luck", 0)

# --- Debug Setters for Base Stats (for DebugPanel) ---
func get_base_max_health_for_debug() -> int: return base_stats.get("max_health", 100)
func debug_set_base_max_health(value: int): base_stats["max_health"] = value; recalculate_all_stats()
func get_base_health_regeneration_for_debug() -> float: return base_stats.get("health_regeneration", 0.0)
func debug_set_base_health_regeneration(value: float): base_stats["health_regeneration"] = value; recalculate_all_stats()
func get_base_numerical_damage_for_debug() -> int: return base_stats.get("base_numerical_damage", 10)
func debug_set_base_numerical_damage(value: int): base_stats["base_numerical_damage"] = value; recalculate_all_stats()
func get_current_global_flat_damage_add_for_debug() -> float: return flat_modifiers.get("global_flat_damage_add", 0.0)
func debug_set_current_global_flat_damage_add(value: float): flat_modifiers["global_flat_damage_add"] = value; recalculate_all_stats()
func get_base_attack_speed_multiplier_for_debug() -> float: return base_stats.get("attack_speed_multiplier", 1.0)
func debug_set_base_attack_speed_multiplier(value: float): base_stats["attack_speed_multiplier"] = value; recalculate_all_stats()
func get_base_armor_for_debug() -> int: return base_stats.get("armor", 0)
func debug_set_base_armor(value: int): base_stats["armor"] = value; recalculate_all_stats()
func get_base_movement_speed_for_debug() -> float: return base_stats.get("movement_speed", 60.0)
func debug_set_base_movement_speed(value: float): base_stats["movement_speed"] = value; recalculate_all_stats()
func get_base_luck_for_debug() -> int: return base_stats.get("luck", 0)
func debug_set_base_luck(value: int): base_stats["luck"] = value; recalculate_all_stats()
func debug_reset_to_class_defaults():
	flat_modifiers.clear()
	percent_add_modifiers.clear()
	percent_mult_modifiers.clear()
	# This requires a reference to the current class data to truly reset.
	# For now, it clears modifiers and recalculates, which reverts to the last loaded class base stats.
	if get_parent() and get_parent().has_method("get_current_basic_class_enum"):
		var class_enum = get_parent().get_current_basic_class_enum()
		# Call initialize_stats again to reload from .tres
		var class_name_str = PlayerCharacter.BasicClass.keys()[class_enum].to_lower()
		var class_data_path = "res://Data/Classes/" + class_name_str + "_class_data.tres"
		var class_data_res = load(class_data_path) as PlayerClassData
		if is_instance_valid(class_data_res):
			initialize_with_class_data(class_data_res)
		else:
			recalculate_all_stats()
	else:
		recalculate_all_stats()
	print_debug("PlayerStats: Modifiers reset. Recalculated with current base stats.")
