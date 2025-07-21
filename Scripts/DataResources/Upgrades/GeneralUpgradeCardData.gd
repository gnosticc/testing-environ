# GeneralUpgradeCardData.gd
# Path: res://Scripts/DataResources/Upgrades/GeneralUpgradeCardData.gd
# Extends Resource to define general player upgrades that are not specific to a single weapon.
# Examples: "Might" (global damage up), "Swiftness" (movement speed up), "Vitality" (max health up).
# Updated error reporting, added editor validation, and a new getter for effects.

class_name GeneralUpgradeCardData
extends Resource

## Unique identifier for this general upgrade card.
## Example: "gen_might_1", "gen_swiftness_1", "player_aura_thorns"
@export var id: StringName = &""

## The display name of the upgrade as it would appear in the UI (e.g., level-up screen).
@export var title: String = "General Upgrade Title"

## A description of what the upgrade does, for UI display.
@export var description: String = "General upgrade description."

## Optional: Path to an icon texture for this upgrade.
## Using Texture2D directly allows drag-and-drop in Inspector.
@export var icon: Texture2D = null

## Defines which basic player classes can be offered this upgrade.
## An empty array means it's available to all classes.
## If populated, only players whose current basic class(es) are in this list will see it.
## Uses the PlayerCharacter.BasicClass enum values.
@export var class_tag_filter: Array[PlayerCharacter.BasicClass] = []

@export_group("Effects & Offering")
## An array of EffectData resources (StatModificationEffectData, CustomFlagEffectData,
## TriggerAbilityEffectData, StatusEffectApplicationData) that define what this upgrade actually does.
## Most general upgrades will likely use StatModificationEffectData targeting "player_stats".
@export var effects: Array[EffectData] = []

## Relative weight for this upgrade to be chosen when offering upgrade options.
## Higher values mean it's more likely to appear (if class filter and prerequisites are met).
@export var weight: float = 60.0

## How many times this specific general upgrade can be acquired by the player.
## Some might be unique (1), others might be stackable (e.g., "+5 Max Health" up to 5 times).
@export var max_stacks: int = 1

## An array of StringName IDs of other GeneralUpgradeCardData (or potentially WeaponUpgradeData IDs
## or even specific weapon level achievements like "weapon_scythe_level_5")
## that must be acquired/achieved before this upgrade can be offered or taken.
@export var prerequisites: Array[StringName] = []
# Example for prerequisites: [&"gen_might_1"] (to unlock "gen_might_2")
# Or for a more complex one: [&"weapon_any_melee_level_3", &"player_level_10"] (conceptual)


func _init():
	pass

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings for common setup issues and data integrity.
func _validate_property(property: Dictionary):
	# Validate 'id'
	if property.name == "id" and (property.get("value", &"") == &""):
		push_warning("GeneralUpgradeCardData: 'id' cannot be empty for resource: ", resource_path)
	
	# Validate 'effects' array
	if property.name == "effects":
		var current_effects_array = property.get("value", [])
		for i in range(current_effects_array.size()):
			var effect = current_effects_array[i]
			if not is_instance_valid(effect):
				push_warning("GeneralUpgradeCardData: Effect in 'effects' at index ", i, " is invalid (null).")
				continue
			if not effect is EffectData:
				push_warning("GeneralUpgradeCardData: Effect in 'effects' at index ", i, " is not an EffectData resource or its subclass (type: ", effect.get_class(), ").")
				continue
			
			if effect is StatModificationEffectData:
				var stat_mod = effect as StatModificationEffectData
				if stat_mod.stat_key == &"":
					push_warning("GeneralUpgradeCardData: StatModificationEffectData in 'effects' at index ", i, " has an empty 'stat_key'.")
				# If targeting player stats, ensure the key is recognized
				if stat_mod.target_scope == &"player_stats" and Engine.has_singleton("PlayerStatKeys"):
					if not PlayerStatKeys.KEY_NAMES.values().has(stat_mod.stat_key):
						push_warning("GeneralUpgradeCardData: Player stat key '", stat_mod.stat_key, "' in effect at index ", i, " is not a recognized key in PlayerStatKeys.KEY_NAMES.")
			elif effect is CustomFlagEffectData:
				var flag_mod = effect as CustomFlagEffectData
				if flag_mod.flag_key == &"":
					push_warning("GeneralUpgradeCardData: CustomFlagEffectData in 'effects' at index ", i, " has an empty 'flag_key'.")
			# Add validation for other EffectData subclasses in 'effects' if applicable

	# Validate 'prerequisites' array
	if property.name == "prerequisites":
		var current_prereqs_array = property.get("value", [])
		for i in range(current_prereqs_array.size()):
			var prereq_id = current_prereqs_array[i]
			if not prereq_id is StringName or prereq_id == &"":
				push_warning("GeneralUpgradeCardData: Prerequisite ID at index ", i, " is empty or not a StringName.")


# New helper function to return the effects array.
# This will be called by PlayerCharacter.gd to apply the upgrade's effects.
func get_effects_to_apply() -> Array[EffectData]:
	return effects

# The commented-out example usage from PlayerCharacter.gd shows the intended data flow.
# When a player chooses this card, PlayerCharacter.gd will iterate through the
# 'effects' array and apply each effect using PlayerStats.gd's methods.
