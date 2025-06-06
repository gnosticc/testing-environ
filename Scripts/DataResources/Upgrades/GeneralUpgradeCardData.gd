# GeneralUpgradeCardData.gd
# Path: res://Scripts/DataResources/Upgrades/GeneralUpgradeCardData.gd
# Extends Resource to define general player upgrades that are not specific to a single weapon.
# Examples: "Might" (global damage up), "Swiftness" (movement speed up), "Vitality" (max health up).
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
@export var weight: float = 100.0

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
	# developer_note = "Defines a general player upgrade card."
	pass

# Example of how this might be used:
# When a player levels up, the system gathers all available GeneralUpgradeCardData.tres files.
# It filters them based on:
# 1. class_tag_filter (if player's current class matches).
# 2. prerequisites (if player has already acquired the required upgrade IDs).
# 3. max_stacks (if player hasn't already taken this upgrade max_stacks times).
# Then, it uses 'weight' to select a few options to present to the player.
#
# When chosen, PlayerCharacter.gd's apply_upgrade method would iterate through this card's 'effects' array:
# func apply_upgrade(upgrade_resource: Resource):
#   if upgrade_resource is GeneralUpgradeCardData:
#       var general_card_data = upgrade_resource as GeneralUpgradeCardData
#       # Record that this general upgrade (general_card_data.id) has been acquired/stacked.
#       # Then apply its effects:
#       for effect_res in general_card_data.effects:
#           if effect_res is StatModificationEffectData:
#               var stat_mod = effect_res as StatModificationEffectData
#               if stat_mod.target_scope == &"player_stats" and is_instance_valid(player_stats_node):
#                   # This part needs to call a method on player_stats_node
#                   # that correctly applies the stat_key, modification_type, and value
#                   # to the player's base_stats or modifier dictionaries.
#                   player_stats_node.apply_stat_modification_effect(stat_mod) # Hypothetical method
#           # ... handle other effect types like CustomFlagEffectData for player_behavior ...
#       player_stats_node.recalculate_all_stats() # Assuming PlayerStats has this
