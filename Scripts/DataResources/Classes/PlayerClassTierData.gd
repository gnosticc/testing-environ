# PlayerClassTierData.gd
# Path: res://Scripts/DataResources/Classes/PlayerClassTierData.gd
# Extends Resource to define the properties of a specific player class tier (e.g., Basic Warrior, Advanced Paladin).
# Updated error reporting and added editor validation for data integrity.

class_name PlayerClassTierData
extends Resource

## Unique identifier for this specific class tier.
## Examples: "warrior_basic", "paladin_advanced", "archmage_master"
@export var class_id: StringName = &""

## The display name of the class tier for UI purposes.
@export var display_name: String = "Class Tier Name"

## Numerical representation of the tier (e.g., 0 for Basic, 1 for Advanced, 2 for Master).
## This can be used for sorting or conditional logic.
@export var tier_level: int = 0 # 0: Basic, 1: Advanced, 2: Master, etc.

## Optional: Path to a PackedScene or Texture2D to override the player's default appearance
## when this class tier is active or selected. Leave empty if no visual change.
@export var sprite_override_path: String = "" # Could also be @export var sprite_override: Texture2D or PackedScene

## An array of EffectData resources (likely StatModificationEffectData) that are
## permanently applied to the player's base stats upon unlocking or activating this class tier.
@export var permanent_stat_bonuses: Array[EffectData] = []

## An array of WeaponBlueprintData resources (or their StringName IDs)
## that become available for the player to find or be offered when this class tier is active/unlocked.
## Using StringName IDs for blueprints might be more flexible for later blueprint changes.
@export var unlocked_weapon_blueprint_ids: Array[StringName] = []
# Alternatively, for direct linking in editor (but less flexible if blueprints change often):
# @export var unlocked_weapon_blueprints: Array[WeaponBlueprintData] = []


## An array of StringName identifiers for special abilities or passive traits unlocked with this class tier.
## The PlayerCharacter.gd script would need to interpret these ability IDs.
## Examples: "dash_attack_unlocked", "mana_shield_passive", "dual_wield_enabled"
@export var unlocked_abilities: Array[StringName] = []

## Optional: A brief description of this class tier, its playstyle, or unique features for UI.
@export var tier_description: String = "Description of this class tier."


func _init():
	pass

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings for common setup issues.
func _validate_property(property: Dictionary):
	# Validate 'class_id'
	if property.name == "class_id" and (property.get("value", &"") == &""):
		push_warning("PlayerClassTierData: 'class_id' cannot be empty for resource: ", resource_path)

	# Validate 'permanent_stat_bonuses' array
	if property.name == "permanent_stat_bonuses":
		var current_effects_array = property.get("value", [])
		for i in range(current_effects_array.size()):
			var effect = current_effects_array[i]
			if not is_instance_valid(effect):
				push_warning("PlayerClassTierData: 'permanent_stat_bonuses' effect at index ", i, " is invalid (null).")
				continue
			if not effect is EffectData:
				push_warning("PlayerClassTierData: 'permanent_stat_bonuses' effect at index ", i, " is not an EffectData resource or its subclass (type: ", effect.get_class(), ").")
				continue
			
			if effect is StatModificationEffectData:
				var stat_mod = effect as StatModificationEffectData
				if stat_mod.stat_key == &"":
					push_warning("PlayerClassTierData: StatModificationEffectData in 'permanent_stat_bonuses' at index ", i, " has an empty 'stat_key'.")
				# Check if the player_stats-targeted key is valid (assuming these bonuses only target player_stats)
				if stat_mod.target_scope == &"player_stats" and Engine.has_singleton("PlayerStatKeys"):
					if not PlayerStatKeys.KEY_NAMES.values().has(stat_mod.stat_key):
						push_warning("PlayerClassTierData: Player stat key '", stat_mod.stat_key, "' in 'permanent_stat_bonuses' at index ", i, " is not a recognized key in PlayerStatKeys.KEY_NAMES.")
			elif effect is CustomFlagEffectData:
				var flag_mod = effect as CustomFlagEffectData
				if flag_mod.flag_key == &"":
					push_warning("PlayerClassTierData: CustomFlagEffectData in 'permanent_stat_bonuses' at index ", i, " has an empty 'flag_key'.")
			# Add validation for other EffectData subclasses in permanent_stat_bonuses if applicable

	# Validate 'unlocked_weapon_blueprint_ids'
	if property.name == "unlocked_weapon_blueprint_ids":
		var current_ids_array = property.get("value", [])
		for i in range(current_ids_array.size()):
			var blueprint_id = current_ids_array[i]
			if not blueprint_id is StringName or blueprint_id == &"":
				push_warning("PlayerClassTierData: 'unlocked_weapon_blueprint_ids' at index ", i, " is empty or not a StringName.")
			# Further validation could include checking if the blueprint actually exists in Game.all_loaded_weapon_blueprints
			# (Requires Game to be an Autoload and a method to query blueprints).

	# Validate 'unlocked_abilities'
	if property.name == "unlocked_abilities":
		var current_abilities_array = property.get("value", [])
		for i in range(current_abilities_array.size()):
			var ability_id = current_abilities_array[i]
			if not ability_id is StringName or ability_id == &"":
				push_warning("PlayerClassTierData: 'unlocked_abilities' at index ", i, " is empty or not a StringName.")
			# Further validation could check against a global list of known ability IDs.


# Helper function to check if a specific ability is unlocked by this tier.
func has_ability(ability_id_to_check: StringName) -> bool:
	return ability_id_to_check in unlocked_abilities
