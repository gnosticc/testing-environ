# File: res://Scripts/DataResources/Classes/PlayerClassProgressionData.gd
# This is the user-provided, more complete version of the script.
class_name PlayerClassProgressionData
extends Resource

## Unique identifier for this progression path (e.g., "unlock_paladin").
@export var progression_id: StringName = &""

## The PlayerClassTierData resource that this progression path unlocks.
@export var class_tier_to_unlock: PlayerClassTierData = null

## A user-friendly description of how to unlock this class, for the level-up card.
@export_multiline var unlock_description: String = "Unlock requirements for this class."

@export_group("Requirements for Unlocking")
## Array of dictionaries defining requirements from Basic classes.
## e.g., [{"class_tag": PlayerCharacter.BasicClass.WARRIOR, "total_weapon_levels_needed": 10}]
@export var required_basic_class_contributions: Array[Dictionary] = []

## Array of StringName IDs of Advanced class tiers that must be unlocked first.
@export var required_advanced_class_ids: Array[StringName] = []

## Optional: Minimum player overall level required.
@export var minimum_player_level: int = 0

func _init():
	pass

func _validate_property(property: Dictionary):
	if property.name == "progression_id" and (property.get("value", &"") == &""):
		push_warning("PlayerClassProgressionData: 'progression_id' cannot be empty for resource: ", resource_path)
	
	if property.name == "class_tier_to_unlock" and not is_instance_valid(property.get("value")):
		push_warning("PlayerClassProgressionData: 'class_tier_to_unlock' is not assigned for resource: ", resource_path)
	elif property.name == "class_tier_to_unlock" and is_instance_valid(property.get("value")) and not property.get("value") is PlayerClassTierData:
		push_warning("PlayerClassProgressionData: 'class_tier_to_unlock' must be a PlayerClassTierData resource.")

	if property.name == "required_basic_class_contributions":
		var reqs_array = property.get("value", [])
		for i in range(reqs_array.size()):
			var req = reqs_array[i]
			if not req is Dictionary:
				push_warning("PlayerClassProgressionData: Entry at index ", i, " is not a Dictionary.")
			elif not req.has("class_tag") or not req.get("class_tag") is int:
				push_warning("PlayerClassProgressionData: Entry at index ", i, " is missing 'class_tag' (int).")
			elif not req.has("total_weapon_levels_needed") or not req.get("total_weapon_levels_needed") is int:
				push_warning("PlayerClassProgressionData: Entry at index ", i, " is missing 'total_weapon_levels_needed' (int).")

	if property.name == "required_advanced_class_ids":
		var ids_array = property.get("value", [])
		for i in range(ids_array.size()):
			if not ids_array[i] is StringName or ids_array[i] == &"":
				push_warning("PlayerClassProgressionData: 'required_advanced_class_ids' at index ", i, " is not a valid StringName.")

func are_requirements_met(player_weapon_levels_by_class: Dictionary, unlocked_advanced_class_ids: Array[StringName], p_player_level: int) -> bool:
	if p_player_level < minimum_player_level:
		return false
	
	for req_basic in required_basic_class_contributions:
		var class_tag_val = req_basic.get("class_tag")
		var levels_needed = req_basic.get("total_weapon_levels_needed", 0)
		if class_tag_val == null:
			push_error("PlayerClassProgressionData: Invalid 'class_tag' in requirements.")
			return false
		if player_weapon_levels_by_class.get(class_tag_val, 0) < levels_needed:
			return false
			
	for req_advanced_id in required_advanced_class_ids:
		if not req_advanced_id in unlocked_advanced_class_ids:
			return false
			
	return true
