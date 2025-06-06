# EnemyData.gd
# Path: res://Scripts/DataResources/EnemyData.gd (adjust if you placed it elsewhere)
# This script defines the structure for individual enemy data resources.
class_name EnemyData
extends Resource

## Unique identifier for this enemy type. Used for lookups and debugging.
@export var id: StringName = &""
## Display name for this enemy, useful for debugging or potential UI elements.
@export var display_name: String = "Enemy"

@export_group("Spawning & Phasing")
## File path to the enemy's scene file (.tscn). This is what will be instanced.
@export var scene_path: String = ""
## The minimum Dynamic Difficulty Score (DDS) required for this enemy to start appearing.
@export var min_DDS_to_spawn: float = 0.0
## The Dynamic Difficulty Score (DDS) after which this enemy will STOP appearing.
## Set to -1.0 (or any negative value) to make the enemy never phase out based on DDS.
@export var max_DDS_to_spawn: float = -1.0
## Relative chance of this enemy spawning when it's part of the active pool and eligible by DDS.
## Higher values mean it's more likely to be picked compared to others with lower weights.
@export var spawn_weight: float = 100.0
## How many "slots" this enemy type consumes in the game's limited active enemy pool (e.g., 5-7 types).
## Most standard enemies will be 1. More complex/large enemies might be 2 or more.
@export var ideal_active_pool_slot_cost: int = 1

@export_group("Base Stats (Static for this type)")
## Base maximum health of the non-elite version of this enemy.
@export var base_health: int = 30
## Base damage dealt by the non-elite enemy on contact.
@export var base_contact_damage: int = 5
## Base movement speed of the non-elite enemy.
@export var base_speed: float = 50.0
## Base armor value of the non-elite enemy, reducing incoming flat damage.
@export var base_armor: int = 0
## The amount of experience this specific non-elite enemy type will drop (this value is passed to the EXP orb).
@export var base_exp_drop: int = 1

@export_group("Drops")
## File path to the specific EXP drop scene (.tscn) this enemy should instantiate.
## Allows for different visual EXP orbs (e.g., small, medium, large).
@export var exp_drop_scene_path: String = "res://Scenes/Pickups/exp_drop_small.tscn" # Default to a common small one

@export_group("Visuals & Variations")
## Modulate color to apply to the enemy's sprite. Useful for creating color-swapped variants
## that reuse the same base scene. Default is white (no change).
@export var sprite_modulate_color: Color = Color(1,1,1,1)
## If the base sprite in the scene file faces left by default, check this.
## If it faces right (standard), leave unchecked. This affects flip_h logic.
@export var sprite_faces_left_by_default: bool = false # NEW
# ## Optional: If you want to specify a scale multiplier directly in data for this enemy type.
# ## Vector2.ZERO could mean use the scale from the enemy's scene file.
# @export var visual_scale_override: Vector2 = Vector2.ZERO

@export_group("Elite Properties")
## An array of StringNames representing the types of elite affixes this enemy can have.
## These tags should correspond to logic in BaseEnemy.gd's make_elite() function.
## Example tags: &"phaser", &"summoner", &"brute", &"tank", &"immovable", &"shaman", &"swift", &"time_warper"
@export var elite_types_available: Array[StringName] = []
## The minimum Dynamic Difficulty Score (DDS) required before this *specific enemy type*
## can start appearing as an elite version (even if general elite chance is met).
@export var min_DDS_for_elites_to_appear: float = 50.0

# --- Configurable Parameters for Specific Elite Types (if this enemy can have them) ---
# These are only relevant if the corresponding tag is in elite_types_available and make_elite() uses them.

@export_group("Elite: Phaser Config (if this enemy can be a Phaser)")
## Cooldown in seconds for the Phaser teleport ability. Logic in BaseEnemy.gd.
@export var phaser_cooldown: float = 5.0
## Max distance the Phaser elite will attempt to teleport. Logic in BaseEnemy.gd.
@export var phaser_teleport_distance: float = 150.0

@export_group("Elite: Summoner Config (if this enemy can be a Summoner)")
## Interval in seconds at which the Summoner elite attempts to summon. Logic in BaseEnemy.gd.
@export var summoner_interval: float = 1.0 # Example: Summons one mob every second
## Maximum number of active summons this specific Summoner elite can maintain. Logic in BaseEnemy.gd.
@export var summoner_max_active_minions: int = 3
# ## Optional: Specific enemy ID(s) this summoner prefers, or leave empty for game.gd to pick weakest relevant.
# @export var summoner_preferred_minion_ids: Array[StringName] = []

@export_group("Elite: Shaman Config (if this enemy can be a Shaman)")
## Radius of the Shaman's healing aura. Logic in BaseEnemy.gd.
@export var shaman_heal_radius: float = 120.0
## Percentage of max health healed per tick by the Shaman. Logic in BaseEnemy.gd.
@export var shaman_heal_percent: float = 0.10 # 10%
## Interval in seconds for the Shaman's healing pulse. Logic in BaseEnemy.gd.
@export var shaman_heal_interval: float = 1.0

@export_group("Elite: Time-Warper Config (if this enemy can be a Time-Warper)")
## Radius of the Time-Warper's slowing aura. Logic in BaseEnemy.gd (likely applies a status to player).
@export var time_warp_radius: float = 180.0
## Percentage to slow player movement and attack speed. Logic in BaseEnemy.gd/Player StatusEffect.
@export var time_warp_slow_percent: float = 0.25 # 25% slow
## Duration in seconds the slow effect lingers after player exits the aura. Logic in Player StatusEffect.
@export var time_warp_linger_duration: float = 2.0

@export_group("Culling & Threat")
## How much this enemy adds to the global threat pool if culled (removed for being too far off-screen).
@export var threat_value_when_culled: int = 1
