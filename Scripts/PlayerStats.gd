# PlayerStats.gd
# CORRECTED: All debug getter/setter functions now use the correct "base_" stat keys.
# CORRECTED: The path in `debug_reset_to_class_defaults` now correctly points to DataResources.
class_name PlayerStats
extends Node

signal stats_recalculated

# Base stats dictionary - Keys now match PlayerClassData.gd
var base_stats: Dictionary = {
	"base_max_health": 100, "base_health_regeneration": 0.0, "base_numerical_damage": 10,
	"base_global_damage_multiplier": 1.0, "base_global_flat_damage_add": 0.0,
	"base_attack_speed_multiplier": 1.0, "base_armor": 0, "base_armor_penetration": 0.0,
	"base_movement_speed": 60.0, "base_magnet_range": 40.0, "base_experience_gain_multiplier": 1.0,
	"base_aoe_area_multiplier": 1.0, "base_projectile_size_multiplier": 1.0,
	"base_projectile_speed_multiplier": 1.0, "base_effect_duration_multiplier": 1.0,
	"base_crit_chance": 0.05, "base_crit_damage_multiplier": 1.5, "base_luck": 0
}

# Dictionaries to store modifiers from upgrades/effects
var flat_modifiers: Dictionary = {}          
var percent_add_modifiers: Dictionary = {} 
var percent_mult_modifiers: Dictionary = {}

# Dictionary to store the final calculated stat values
var current_calculated_stats: Dictionary = {}

func _ready():
	recalculate_all_stats() 

func initialize_with_class_data(class_data: PlayerClassData):
	if not is_instance_valid(class_data):
		print_debug("ERROR (PlayerStats): Invalid PlayerClassData provided for initialization.")
		recalculate_all_stats()
		return

	for key in base_stats.keys():
		if class_data.has(key):
			base_stats[key] = class_data.get(key)
	
	recalculate_all_stats()

func initialize_with_raw_stats(raw_stats_dict: Dictionary):
	for key in raw_stats_dict:
		if base_stats.has(key):
			base_stats[key] = raw_stats_dict[key]
	recalculate_all_stats()


func apply_effects_from_card(card_data: GeneralUpgradeCardData):
	if not is_instance_valid(card_data): return
	for effect_res in card_data.effects:
		if effect_res is StatModificationEffectData:
			var stat_mod_effect = effect_res as StatModificationEffectData
			if stat_mod_effect.target_scope == &"player_stats": 
				_process_stat_modification_effect(stat_mod_effect)
	recalculate_all_stats()

func _process_stat_modification_effect(stat_mod_effect: StatModificationEffectData):
	var key = stat_mod_effect.stat_key
	var value = stat_mod_effect.get_value() 
	var mod_type = stat_mod_effect.modification_type

	match mod_type:
		&"flat_add":
			flat_modifiers[key] = flat_modifiers.get(key, 0.0) + value
		&"percent_add_to_base":
			percent_add_modifiers[key] = percent_add_modifiers.get(key, 0.0) + value
		&"percent_mult_final":
			percent_mult_modifiers[key] = percent_mult_modifiers.get(key, 1.0) * (1.0 + value) 
		&"override_value":
			base_stats[key] = value 
			flat_modifiers.erase(key)
			percent_add_modifiers.erase(key)
			percent_mult_modifiers.erase(key)

func recalculate_all_stats():
	current_calculated_stats.clear()
	for stat_name in base_stats:
		var base_val = base_stats.get(stat_name, 0.0)
		var flat_add = flat_modifiers.get(stat_name, 0.0)
		var percent_add_sum = percent_add_modifiers.get(stat_name, 0.0)
		var percent_mult_prod = percent_mult_modifiers.get(stat_name, 1.0)

		var calculated_val = (base_val + flat_add) * (1.0 + percent_add_sum)
		calculated_val *= percent_mult_prod
		
		if stat_name in ["base_max_health", "base_armor", "base_luck", "base_numerical_damage"]: 
			current_calculated_stats[stat_name] = int(round(calculated_val))
		else:
			current_calculated_stats[stat_name] = calculated_val
			
	emit_signal("stats_recalculated")

# --- Getters for current calculated stats ---
func get_max_health() -> int: return current_calculated_stats.get("base_max_health", 100)
func get_health_regeneration() -> float: return current_calculated_stats.get("base_health_regeneration", 0.0)
func get_current_base_numerical_damage() -> int: return current_calculated_stats.get("base_numerical_damage", 10)
func get_current_global_damage_multiplier() -> float: return current_calculated_stats.get("base_global_damage_multiplier", 1.0)
func get_current_global_flat_damage_add() -> float: return current_calculated_stats.get("base_global_flat_damage_add", 0.0)
func get_current_attack_speed_multiplier() -> float: return current_calculated_stats.get("base_attack_speed_multiplier", 1.0)
func get_armor() -> int: return current_calculated_stats.get("base_armor", 0)
func get_current_armor_penetration() -> float: return current_calculated_stats.get("base_armor_penetration", 0.0)
func get_movement_speed() -> float: return current_calculated_stats.get("base_movement_speed", 60.0)
func get_magnet_range() -> float: return current_calculated_stats.get("base_magnet_range", 10.0)
func get_experience_gain_multiplier() -> float: return current_calculated_stats.get("base_experience_gain_multiplier", 1.0)
func get_current_aoe_area_multiplier() -> float: return current_calculated_stats.get("base_aoe_area_multiplier", 1.0)
func get_current_projectile_size_multiplier() -> float: return current_calculated_stats.get("base_projectile_size_multiplier", 1.0)
func get_current_projectile_speed_multiplier() -> float: return current_calculated_stats.get("base_projectile_speed_multiplier", 1.0)
func get_current_effect_duration_multiplier() -> float: return current_calculated_stats.get("base_effect_duration_multiplier", 1.0)
func get_crit_chance() -> float: return current_calculated_stats.get("base_crit_chance", 0.05)
func get_crit_damage_multiplier() -> float: return current_calculated_stats.get("base_crit_damage_multiplier", 1.5)
func get_luck() -> int: return current_calculated_stats.get("base_luck", 0)

# --- CORRECTED Debug Setters for Base Stats (for DebugPanel) ---
func get_base_max_health_for_debug() -> int: return base_stats.get("base_max_health", 100)
func debug_set_base_max_health(value: int): base_stats["base_max_health"] = value; recalculate_all_stats()

func get_base_health_regeneration_for_debug() -> float: return base_stats.get("base_health_regeneration", 0.0)
func debug_set_base_health_regeneration(value: float): base_stats["base_health_regeneration"] = value; recalculate_all_stats()

func get_base_numerical_damage_for_debug() -> int: return base_stats.get("base_numerical_damage", 10)
func debug_set_base_numerical_damage(value: int): base_stats["base_numerical_damage"] = value; recalculate_all_stats()

func get_current_global_flat_damage_add_for_debug() -> float: return flat_modifiers.get("base_global_flat_damage_add", 0.0)
func debug_set_current_global_flat_damage_add(value: float): flat_modifiers["base_global_flat_damage_add"] = value; recalculate_all_stats()

func get_base_attack_speed_multiplier_for_debug() -> float: return base_stats.get("base_attack_speed_multiplier", 1.0)
func debug_set_base_attack_speed_multiplier(value: float): base_stats["base_attack_speed_multiplier"] = value; recalculate_all_stats()

func get_base_armor_for_debug() -> int: return base_stats.get("base_armor", 0)
func debug_set_base_armor(value: int): base_stats["base_armor"] = value; recalculate_all_stats()

func get_base_movement_speed_for_debug() -> float: return base_stats.get("base_movement_speed", 60.0)
func debug_set_base_movement_speed(value: float): base_stats["base_movement_speed"] = value; recalculate_all_stats()

func get_base_luck_for_debug() -> int: return base_stats.get("base_luck", 0)
func debug_set_base_luck(value: int): base_stats["base_luck"] = value; recalculate_all_stats()

func debug_reset_to_class_defaults():
	flat_modifiers.clear()
	percent_add_modifiers.clear()
	percent_mult_modifiers.clear()
	
	if get_parent() and get_parent().has_method("get_current_basic_class_enum"):
		var class_enum = get_parent().get_current_basic_class_enum()
		var class_name_str = PlayerCharacter.BasicClass.keys()[class_enum].to_lower()
		# CORRECTED PATH
		var class_data_path = "res://DataResources/Classes/" + class_name_str + "_class_data.tres"
		var class_data_res = load(class_data_path) as PlayerClassData
		if is_instance_valid(class_data_res):
			initialize_with_class_data(class_data_res)
		else:
			print_debug("PlayerStats DEBUG: Could not reload class data. Recalculating with existing base stats.")
			recalculate_all_stats()
	else:
		recalculate_all_stats()
	print_debug("PlayerStats: Modifiers reset. Recalculated with current class default stats.")
