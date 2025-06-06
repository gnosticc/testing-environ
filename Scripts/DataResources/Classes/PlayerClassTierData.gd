# PlayerClassTierData.gd
# Path: res://Scripts/DataResources/Classes/PlayerClassTierData.gd
# Extends Resource to define the properties of a specific player class tier (e.g., Basic Warrior, Advanced Paladin).
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
	# developer_note = "Defines a specific tier of a player class, its bonuses, and unlocks."
	pass

# You could add helper functions here if needed, for example, to check if a specific ability is unlocked by this tier.
# func has_ability(ability_id_to_check: StringName) -> bool:
#	 return ability_id_to_check in unlocked_abilities
