# PlayerClassProgressionData.gd
# Path: res://Scripts/DataResources/Classes/PlayerClassProgressionData.gd
# Extends Resource to define the requirements for unlocking a specific advanced or master player class tier.
# Updated error reporting and added editor validation for data integrity.

class_name PlayerClassProgressionData
extends Resource

## Unique identifier for this specific progression path.
## Example: "unlock_paladin", "unlock_archmage_tier2"
@export var progression_id: StringName = &""

## The PlayerClassTierData resource that this progression path unlocks.
## You will drag a .tres file (e.g., "paladin_advanced.tres") here in the Inspector.
@export var class_tier_to_unlock: PlayerClassTierData = null

## A user-friendly description of how to unlock this class tier, for UI display.
## Example: "Achieve 10 total levels in Warrior weapons and 10 total levels in Knight weapons."
@export var unlock_description: String = "Unlock requirements for this class."

@export_group("Requirements for Unlocking")
## An array of dictionaries defining the requirements from Basic classes.
## Each dictionary specifies a basic class and the total number of weapon levels
## accumulated across all weapons belonging to that basic class.
## Example: [{"class_tag": PlayerCharacter.BasicClass.WARRIOR, "total_weapon_levels_needed": 10},
##            {"class_tag": PlayerCharacter.BasicClass.KNIGHT, "total_weapon_levels_needed": 10}]
## The PlayerCharacter.BasicClass enum should be defined in your PlayerCharacter.gd script.
@export var required_basic_class_contributions: Array[Dictionary] = []

## An array of StringName IDs (class_id from PlayerClassTierData) of Advanced class tiers
## that must be unlocked before this progression path (typically for a Master tier) can be completed.
## Example: [&"paladin_advanced", &"elementalist_advanced"] to unlock a Master tier.
@export var required_advanced_class_ids: Array[StringName] = []

## Optional: Minimum player overall level required.
@export var minimum_player_level: int = 0

## Optional: Specific other achievements or game flags that must be met.
## (This is a placeholder for more complex unlock conditions if needed later)
# @export var other_required_flags: Array[StringName] = []


func _init():
	pass

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings for common setup issues.
func _validate_property(property: Dictionary):
	# Validate 'progression_id'
	if property.name == "progression_id" and (property.get("value", &"") == &""):
		push_warning("PlayerClassProgressionData: 'progression_id' cannot be empty for resource: ", resource_path)
	
	# Validate 'class_tier_to_unlock'
	if property.name == "class_tier_to_unlock" and not is_instance_valid(property.get("value")):
		push_warning("PlayerClassProgressionData: 'class_tier_to_unlock' is not assigned for resource: ", resource_path)
	elif property.name == "class_tier_to_unlock" and is_instance_valid(property.get("value")) and not property.get("value") is PlayerClassTierData:
		push_warning("PlayerClassProgressionData: 'class_tier_to_unlock' must be a PlayerClassTierData resource for resource: ", resource_path)

	# Validate 'required_basic_class_contributions' array
	if property.name == "required_basic_class_contributions":
		var current_reqs_array = property.get("value", [])
		for i in range(current_reqs_array.size()):
			var req = current_reqs_array[i]
			if not req is Dictionary:
				push_warning("PlayerClassProgressionData: 'required_basic_class_contributions' at index ", i, " is not a Dictionary.")
				continue
			if not req.has("class_tag") or not req.get("class_tag") is int: # Enum values are ints
				push_warning("PlayerClassProgressionData: 'required_basic_class_contributions' at index ", i, " missing 'class_tag' (int).")
			if not req.has("total_weapon_levels_needed") or not req.get("total_weapon_levels_needed") is int:
				push_warning("PlayerClassProgressionData: 'required_basic_class_contributions' at index ", i, " missing 'total_weapon_levels_needed' (int).")
			# Further validation could check if class_tag is a valid PlayerCharacter.BasicClass enum value.

	# Validate 'required_advanced_class_ids' array
	if property.name == "required_advanced_class_ids":
		var current_ids_array = property.get("value", [])
		for i in range(current_ids_array.size()):
			var class_id_sname = current_ids_array[i]
			if not class_id_sname is StringName or class_id_sname == &"":
				push_warning("PlayerClassProgressionData: 'required_advanced_class_ids' at index ", i, " is empty or not a StringName.")
			# Further validation could check if these class IDs actually exist in PlayerClassTierData resources.


# Helper function to check if this progression is currently met by the player.
# This would be called by a system in PlayerCharacter.gd or Game.gd.
# It needs access to the player's current weapon levels per class and unlocked advanced classes.
func are_requirements_met(player_weapon_levels_by_class: Dictionary, unlocked_advanced_class_ids: Array[StringName], p_player_level: int) -> bool:
	if p_player_level < minimum_player_level:
		return false # Minimum player level not met
	
	# Check basic class level contributions
	for req_basic in required_basic_class_contributions:
		var class_tag_val = req_basic.get("class_tag") # This will be an int (PlayerCharacter.BasicClass enum value)
		var levels_needed = req_basic.get("total_weapon_levels_needed", 0)
		
		if class_tag_val == null:
			push_error("PlayerClassProgressionData: Invalid 'class_tag' in required_basic_class_contributions. Check resource setup.")
			return false # Treat as not met due to invalid data
		
		# Ensure the class_tag_val exists in the player's dictionary and has enough levels
		if player_weapon_levels_by_class.get(class_tag_val, 0) < levels_needed:
			return false # Requirement for this basic class not met
			
	# Check required advanced class unlocks
	for req_advanced_id in required_advanced_class_ids:
		if not req_advanced_id in unlocked_advanced_class_ids:
			return false # Required advanced class not yet unlocked
			
	# Check other_required_flags if implemented (currently commented out)
	# if not _check_other_required_flags(): return false
	
	return true # All requirements met

# Example of how you might check other flags (if implemented later)
# func _check_other_required_flags() -> bool:
# 	for flag_id in other_required_flags:
# 		# Assume a global flag manager or player component can check these.
# 		# if not PlayerFlags.get_flag(flag_id): return false
# 		pass
# 	return true
