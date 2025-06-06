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
	# developer_note = "Defines a single upgrade for a weapon."
	pass
