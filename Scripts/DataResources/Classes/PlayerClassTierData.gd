# File: res://Scripts/DataResources/Classes/PlayerClassTierData.gd
# This is the user-provided, more complete version of the script.
class_name PlayerClassTierData
extends Resource

## Unique identifier for this specific class tier.
@export var class_id: StringName = &""

## The display name of the class tier for UI purposes.
@export var display_name: String = "Class Tier Name"

## Numerical representation of the tier (e.g., 0 for Basic, 1 for Advanced, 2 for Master).
@export var tier_level: int = 1

## Optional: Path to a PackedScene or Texture2D to override the player's default appearance.
@export var sprite_override_path: String = ""

## An array of EffectData resources that are permanently applied to the player's base stats upon unlocking.
@export var permanent_stat_bonuses: Array[EffectData] = []

## An array of WeaponBlueprintData StringName IDs that become available when this class is unlocked.
@export var unlocked_weapon_blueprint_ids: Array[StringName] = []

## An array of StringName identifiers for special abilities unlocked with this class tier.
@export var unlocked_abilities: Array[StringName] = []

## A brief description of this class tier for UI display.
@export_multiline var tier_description: String = "Description of this class tier."

func _init():
	pass

func _validate_property(property: Dictionary):
	if property.name == "class_id" and (property.get("value", &"") == &""):
		push_warning("PlayerClassTierData: 'class_id' cannot be empty for resource: ", resource_path)

	if property.name == "permanent_stat_bonuses":
		var effects_array = property.get("value", [])
		for i in range(effects_array.size()):
			var effect = effects_array[i]
			if not is_instance_valid(effect):
				push_warning("PlayerClassTierData: 'permanent_stat_bonuses' effect at index ", i, " is invalid (null).")
			elif not effect is EffectData:
				push_warning("PlayerClassTierData: 'permanent_stat_bonuses' effect at index ", i, " is not an EffectData resource.")
			elif effect is StatModificationEffectData:
				var stat_mod = effect as StatModificationEffectData
				if stat_mod.stat_key == &"":
					push_warning("PlayerClassTierData: StatModificationEffectData at index ", i, " has an empty 'stat_key'.")
				if stat_mod.target_scope == &"player_stats" and Engine.has_singleton("PlayerStatKeys"):
					if not PlayerStatKeys.KEY_NAMES.values().has(stat_mod.stat_key):
						push_warning("PlayerClassTierData: Player stat key '", stat_mod.stat_key, "' at index ", i, " is not a recognized key.")
			elif effect is CustomFlagEffectData:
				var flag_mod = effect as CustomFlagEffectData
				if flag_mod.flag_key == &"":
					push_warning("PlayerClassTierData: CustomFlagEffectData at index ", i, " has an empty 'flag_key'.")

	if property.name == "unlocked_weapon_blueprint_ids":
		var ids_array = property.get("value", [])
		for i in range(ids_array.size()):
			if not ids_array[i] is StringName or ids_array[i] == &"":
				push_warning("PlayerClassTierData: 'unlocked_weapon_blueprint_ids' at index ", i, " is not a valid StringName.")

	if property.name == "unlocked_abilities":
		var abilities_array = property.get("value", [])
		for i in range(abilities_array.size()):
			if not abilities_array[i] is StringName or abilities_array[i] == &"":
				push_warning("PlayerClassTierData: 'unlocked_abilities' at index ", i, " is not a valid StringName.")

func has_ability(ability_id_to_check: StringName) -> bool:
	return ability_id_to_check in unlocked_abilities
