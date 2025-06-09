# WeaponUpgradeData.gd
# Path: res://Scripts/DataResources/Upgrades/WeaponUpgradeData.gd
# Extends Resource to define the properties and effects of a single weapon upgrade.
class_name WeaponUpgradeData
extends Resource

## Unique identifier for this specific upgrade.
## Example: "scythe_sharpened_edge_1", "spark_chain_lightning_1"
@export var upgrade_id: StringName = &""

## The display name of the upgrade as it would appear in the UI.
@export var title: String = "Upgrade Title"

## A description of what the upgrade does, for UI display.
@export var description: String = "Upgrade Description."

## Optional: Path to an icon texture for this upgrade.
## Using Texture2D directly allows drag-and-drop in Inspector.
@export var icon: Texture2D = null

@export_group("Requirements & Offering")
## An array of 'upgrade_id' StringNames (from other WeaponUpgradeData resources for THE SAME WEAPON)
## that must be acquired before this upgrade can be offered or taken.
@export var prerequisites_on_this_weapon: Array[StringName] = []

## Relative weight for this upgrade to be chosen when offering upgrade options.
## Higher values mean it's more likely to appear, assuming prerequisites are met.
@export var weight: float = 100.0

## How many times this specific upgrade can be acquired for a single weapon instance.
## Most unique upgrades will be 1. Some generic "+damage" upgrades might have more.
@export var max_stacks: int = 1

@export_group("Effects & Tracking")
## An array of EffectData resources (or its subclasses like StatModificationEffectData,
## CustomFlagEffectData, TriggerAbilityEffectData, StatusEffectApplicationData)
## that define what this upgrade actually does.
@export var effects: Array[EffectData] = []

## IMPORTANT: This StringName should match a 'flag_key' that one of the 'effects'
## (typically a CustomFlagEffectData) will set to true in the weapon's specific_stats.
## The game logic (e.g., in game.gd's get_weapon_next_level_upgrades) uses this
## to check if this particular upgrade card has already been applied to a weapon instance.
## Example: "scythe_sharpened_edge_1_acquired"
@export var set_acquired_flag_on_weapon: StringName = &""


func _init():
	pass

# Optional: Add a validation method for use in the editor to check for common setup issues.
func _validate_property(property: Dictionary):
	if property.name == "upgrade_id" and (property.get("value", &"") == &""):
		push_warning("WeaponUpgradeData: 'upgrade_id' cannot be empty for resource: ", resource_path)
	
	if property.name == "effects":
		var current_effects_array = property.get("value", [])
		for i in range(current_effects_array.size()):
			var effect = current_effects_array[i]
			if not is_instance_valid(effect):
				push_warning("WeaponUpgradeData: Effect at index ", i, " is invalid (null).")
			elif not effect is EffectData:
				push_warning("WeaponUpgradeData: Effect at index ", i, " is not an EffectData resource or its subclass.")
			elif effect is StatModificationEffectData:
				var stat_mod = effect as StatModificationEffectData
				if stat_mod.stat_key == &"":
					push_warning("WeaponUpgradeData: StatModificationEffectData at index ", i, " has an empty 'stat_key'.")
				# You could add further validation here to check if stat_key exists in GameStatConstants.KEY_NAMES
				# if stat_mod.target_scope == &"player_stats" and Engine.has_singleton("GameStatConstants"):
				# 	if not GameStatConstants.KEY_NAMES.values().has(stat_mod.stat_key):
				# 		push_warning("WeaponUpgradeData: Player stat key '", stat_mod.stat_key, "' in effect at index ", i, " is not in GameStatConstants.KEY_NAMES.")
			elif effect is CustomFlagEffectData:
				var flag_mod = effect as CustomFlagEffectData
				if flag_mod.flag_key == &"":
					push_warning("WeaponUpgradeData: CustomFlagEffectData at index ", i, " has an empty 'flag_key'.")
	
	if property.name == "set_acquired_flag_on_weapon" and (property.get("value", &"") == &"") and (max_stacks == 1) and (not effects.is_empty()):
		# Suggest setting an acquired flag if it's a single-stack upgrade with effects, and flag is empty
		push_warning("WeaponUpgradeData: Consider setting 'set_acquired_flag_on_weapon' for single-stack upgrade '", upgrade_id, "' to ensure it's tracked as acquired.")
