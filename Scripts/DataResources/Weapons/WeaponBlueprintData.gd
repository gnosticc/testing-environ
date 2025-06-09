# WeaponBlueprintData.gd
# ADDED: `base_lifetime` as an export variable for projectiles and other timed attacks.
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
## Tags for categorizing the weapon (e.g., "Melee", "Projectile", "Piercing").
@export var tags: Array[String] = []
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
@export var targeting_type: String = "mouse"

## A dictionary holding the initial, inherent stats for this weapon type.
@export var initial_specific_stats: Dictionary = {
	"weapon_damage_percentage": 1.0, # Scales with player's base damage
	"pierce_count": 0,
	"projectile_speed": 200.0
}


@export_group("Upgrade Path")
## An array where you will assign/drag `WeaponUpgradeData.tres` resources.
@export var available_upgrades: Array[WeaponUpgradeData] = []


func _init():
	pass

# Helper function to get a specific upgrade data by its ID from this blueprint
func get_upgrade_by_id(p_upgrade_id: StringName) -> WeaponUpgradeData:
	for upgrade_res in available_upgrades:
		if is_instance_valid(upgrade_res) and upgrade_res.upgrade_id == p_upgrade_id:
			return upgrade_res
	return null
