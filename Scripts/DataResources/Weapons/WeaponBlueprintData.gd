# WeaponBlueprintData.gd
# Path: res://Scripts/DataResources/Weapons/WeaponBlueprintData.gd
# Extends Resource to define the properties, base stats, behavior, 
# and available upgrades for a weapon type.
class_name WeaponBlueprintData
extends Resource

## Unique identifier for this weapon blueprint.
## Example: "warrior_scythe", "wizard_spark_bolt"
@export var id: StringName = &""

## The display name of the weapon as it would appear in UI (e.g., level-up screen).
@export var title: String = "Weapon Title"

## A brief description of the weapon for UI display.
@export var description: String = "Weapon Description."

## The PackedScene file (.tscn) for the weapon's attack/projectile/aura.
## This is what will be instanced when the weapon attacks or is activated.
@export var weapon_scene: PackedScene

## Optional: Path to an icon texture for this weapon, for UI display.
## Using Texture2D directly allows drag-and-drop in Inspector.
@export var icon: Texture2D = null 

## Tags for categorizing the weapon (e.g., "Melee", "Projectile", "AoE", "Spell", "Summon").
## Useful for general upgrades that affect specific weapon types.
@export var tags: Array[String] = []

## Defines which basic player classes can initially acquire or be offered this weapon.
## An empty array means it's potentially available to all (or managed by other game logic).
## Uses the PlayerCharacter.BasicClass enum values.
@export var class_tag_restrictions: Array[PlayerCharacter.BasicClass] = []


@export_group("Base Behavior & Stats")
## Base cooldown time in seconds between uses/attacks of this weapon.
@export var cooldown: float = 2.0

## The maximum number of times this specific weapon can be "leveled up" by acquiring its unique upgrades.
## This helps determine when to stop offering its specific upgrades.
@export var max_level: int = 7

## If true, the weapon_scene is instanced as a direct child of the WeaponManager (or player).
## If false, it's typically instanced in the main game world (e.g., projectiles).
@export var spawn_as_child: bool = false 

## If true, the weapon requires a direction vector (e.g., towards mouse or an enemy) when attacking.
@export var requires_direction: bool = true

## Defines how the weapon targets (if it requires direction).
## Examples: "mouse", "nearest_enemy", "random_enemy_in_range", "fixed_player_facing"
@export var targeting_type: String = "mouse" 

## If true, this weapon functions as an aura around the player.
@export var is_aura: bool = false

## If true, this weapon creates a group of orbiting entities.
@export var is_orbital_group: bool = false

## If true, a single activation of this weapon performs multiple hits/actions in a sequence.
@export var is_multi_hit_sequence: bool = false
## Number of hits/actions in a multi-hit sequence.
@export var multi_hit_count: int = 1
## Delay in seconds between hits/actions in a multi-hit sequence.
@export var multi_hit_delay: float = 0.1

## If true, this weapon is a persistent summon/pet rather than a one-off attack.
@export var is_persistent_summon: bool = false
## Maximum number of this specific type of summon allowed at once. (0 or -1 for no limit if appropriate)
@export var max_summons_of_type: int = 0 

# In WeaponBlueprintData.gd, under the "Base Behavior & Stats" group
@export var is_temporary_effect: bool = false # True if the instanced scene should queue_free itself after its action

@export_group("Initial Weapon-Specific Stats")
## A dictionary holding the initial, inherent stats for this weapon type.
## These are the values before any player stats or upgrades (other than its own initial ones) are applied.
## Keys should be consistent (e.g., "base_damage", "projectile_speed", "area_of_effect_radius", 
## "projectile_count", "pierce_count", "duration", "visual_scale_x", "visual_scale_y").
## Also include any initial boolean flags specific to this weapon's behavior,
## e.g., {"applies_bleed_innately": false, "innate_homing_strength": 0.5}
@export var initial_specific_stats: Dictionary = {
	"damage": 10, # Example: Base damage value for this weapon
	"projectile_speed": 300.0, # Example
	"player_damage_scale_percent": 1.0 # Example: Scales 100% with player's base numerical damage by default
}


@export_group("Upgrade Path")
## An array where you will assign/drag `WeaponUpgradeData.tres` resources.
## These are all the potential unique upgrades specifically designed for this weapon.
@export var available_upgrades: Array[WeaponUpgradeData] = []


func _init():
	# developer_note = "Defines a base weapon type, its behavior, stats, and potential upgrades."
	pass

# Helper function to get a specific upgrade data by its ID from this blueprint
func get_upgrade_by_id(p_upgrade_id: StringName) -> WeaponUpgradeData:
	for upgrade_res in available_upgrades:
		if is_instance_valid(upgrade_res) and upgrade_res.upgrade_id == p_upgrade_id:
			return upgrade_res
	return null
