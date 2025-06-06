# PlayerClassProgressionData.gd
# Path: res://Scripts/DataResources/Classes/PlayerClassProgressionData.gd
# Extends Resource to define the requirements for unlocking a specific advanced or master player class tier.
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
##           {"class_tag": PlayerCharacter.BasicClass.KNIGHT, "total_weapon_levels_needed": 10}]
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
	# developer_note = "Defines how a specific player class tier is unlocked."
	pass

# Helper function to check if this progression is currently met by the player.
# This would be called by a system in PlayerCharacter.gd or Game.gd.
# It needs access to the player's current weapon levels per class and unlocked advanced classes.
# func are_requirements_met(player_weapon_levels_by_class: Dictionary, unlocked_advanced_class_ids: Array[StringName], p_player_level: int) -> bool:
# 	if p_player_level < minimum_player_level:
# 		return false
# 
# 	for req_basic in required_basic_class_contributions:
# 		var class_tag_val = req_basic.get("class_tag") # This will be an int if PlayerCharacter.BasicClass is an enum
# 		var levels_needed = req_basic.get("total_weapon_levels_needed", 0)
# 		if player_weapon_levels_by_class.get(class_tag_val, 0) < levels_needed:
# 			return false # Requirement for this basic class not met
# 
# 	for req_advanced_id in required_advanced_class_ids:
# 		if not req_advanced_id in unlocked_advanced_class_ids:
# 			return false # Required advanced class not yet unlocked
# 
# 	# Check other_required_flags if implemented
# 
# 	return true
