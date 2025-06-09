# WeaponBlueprintData.gd
# This resource defines the blueprint for a specific weapon type,
# including its base stats, scene, and available upgrades.
# It uses StringName literals for dictionary keys for efficiency and consistency.

class_name WeaponBlueprintData
extends Resource

## Unique identifier for this weapon blueprint.
@export var id: StringName = &""
## The display name of the weapon as it would appear in UI.
@export var title: String = "Weapon Title"
## A brief description of the weapon for UI display.
@export var description: String = "Weapon Description."
## The PackedScene file (.tscn) for the weapon's attack/projectile/aura.
@export var weapon_scene: PackedScene
## Optional: Path to an icon texture for this weapon, for UI display.
@export var icon: Texture2D = null
## Tags for categorizing the weapon (e.g., "Melee", "Projectile", "Piercing", "Summon").
@export var tags: Array[StringName] = [] # Changed to StringName array for consistency
## Defines which basic player classes this weapon contributes level-up points to.
@export var class_tag_restrictions: Array[PlayerCharacter.BasicClass] = []


@export_group("Base Behavior & Stats")
## Base cooldown time in seconds between uses/attacks of this weapon.
@export var cooldown: float = 2.0
## The maximum number of times this specific weapon can be "leveled up".
@export var max_level: int = 7
## Base lifetime in seconds for projectiles or temporary effects. Set to 0 if not applicable.
@export var base_lifetime: float = 3.0
## If true, the weapon_scene is instanced as a direct child of the WeaponManager (or player).
@export var spawn_as_child: bool = false
## If true, the weapon requires a direction vector (e.g., towards mouse or an enemy).
@export var requires_direction: bool = true
## Defines how the weapon targets (if it requires direction).
@export var targeting_type: StringName = &"mouse_direction" # Changed to StringName, example default


## A dictionary holding the initial, inherent stats for this weapon type.
# Keys here should be consistent within the weapon's specific domain.
# Ensure you use StringName literals (e.g., &"key_name").
@export var initial_specific_stats: Dictionary = {
	# These keys are specific to this weapon type.
	# Examples:
	&"weapon_damage_percentage": 1.0, # Scales with player's base numerical damage
	&"pierce_count": 0,               # How many enemies a projectile can pierce
	&"projectile_speed": 200.0,       # Base speed for projectiles spawned by this weapon
	&"max_cast_range": 300.0,         # Max range for mouse_location targeting
	&"reaping_momentum_dmg_per_hit": 1, # Scythe specific: damage per hit for reaping momentum
	&"whirlwind_count": 1,            # Scythe specific: number of extra spins for whirlwind
	&"whirlwind_delay": 0.1,          # Scythe specific: delay between whirlwind spins
	&"max_summons_of_type": 1,        # Summoner specific: max active summons of this type
	&"summoner_minion_ids": [&"slime_green"], # Summoner specific: IDs of minions it can summon
}


@export_group("Upgrade Path")
## An array where you will assign/drag `WeaponUpgradeData.tres` resources.
## These define the available upgrades for this specific weapon.
@export var available_upgrades: Array[WeaponUpgradeData] = []


func _init():
	pass

# Helper function to get a specific upgrade data by its ID from this blueprint's available upgrades.
func get_upgrade_by_id(p_upgrade_id: StringName) -> WeaponUpgradeData:
	for upgrade_res in available_upgrades:
		if not is_instance_valid(upgrade_res):
			push_warning("WeaponBlueprintData: Invalid upgrade resource found in available_upgrades for ID: ", p_upgrade_id)
			continue
		if upgrade_res is WeaponUpgradeData and upgrade_res.upgrade_id == p_upgrade_id:
			return upgrade_res
	return null
