# EnemyData.gd
# Path: res://Scripts/DataResources/EnemyData.gd
# This script defines the structure for individual enemy data resources.
# Updated error reporting and added editor validation for data integrity.

class_name EnemyData
extends Resource

enum RangedMovementPattern {
	STATIONARY, # Moves to ideal range and stops. Your "&ranged" behavior.
	KITE,       # Maintains ideal range, flees when player is too close.
	CIRCLE,     # Circles the player at ideal range.
	IRRATIC     # Moves randomly within a specified range band.
}

enum RangedFiringPattern {
	AUTO,          # Fires on a fixed cooldown.
	BURST,         # Fires a burst of shots on a fixed cooldown.
	IRRATIC_BURST, # Fires a burst of shots on a randomized cooldown.
	HOMING         # Fires a homing projectile on a fixed cooldown.
}

## Unique identifier for this enemy type. Used for lookups and debugging.
@export var id: StringName = &""
## Display name for this enemy, useful for debugging or potential UI elements.
@export var display_name: String = "Enemy"

@export_group("Spawning & Phasing")
## File path to the enemy's scene file (.tscn). This is what will be instanced.
@export_file("*.tscn") var scene_path: String = ""
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
@export_file("*.tscn") var exp_drop_scene_path: String = "res://Scenes/Pickups/exp_drop_small.tscn" # Default to a common small one

@export_group("Visuals & Variations")
## Modulate color to apply to the enemy's sprite. Useful for creating color-swapped variants
## that reuse the same base scene. Default is white (no change).
@export var sprite_modulate_color: Color = Color(1,1,1,1)
## If the base sprite in the scene file faces left by default, check this.
## If it faces right (standard), leave unchecked. This affects flip_h logic.
@export var sprite_faces_left_by_default: bool = false
## NEW: An array of tags that define unique behaviors for this enemy.
## Logic in BaseEnemy.gd will check for these tags to trigger special actions.
## Example tags: &"slime" (splits on death), &"rusher" (charges at player) or "uses_formation" for HordeFormationManager.
@export var behavior_tags: Array[StringName] = []
# --- Icon Overrides ---
# An optional offset to apply to the EliteMarkersContainer for fine-tuning.
@export var elite_icon_offset: Vector2 = Vector2.ZERO
# An optional multiplier to adjust the size of elite icons for this specific enemy.
@export var elite_icon_scale_multiplier: float = 1.0

# --- Wave Movement Behavior &"wave"---
@export_group("Wave Movement")
@export var wave_amplitude: float = 50.0 # How wide the "S" curve is in pixels.
@export var wave_frequency: float = 5.0 # How fast the enemy weaves back and forth.
@export var wave_disable_range: float = 25.0 # At this range, the enemy stops weaving to make contact.

# TAG LIST: "uses_formation", "hit_and_run"
# --- HIT AND RUN BEHAVIOR ---
@export_group("Hit and Run")
# Multiplier applied to base speed when diving IN for an attack.
@export var dive_speed_multiplier: float = 1.0 
# Multiplier applied to base speed when retreating after an attack.
@export var retreat_speed_multiplier: float = 1.5
# Multiplier applied to base speed when circling (stalking) the player.
@export var stalking_speed_multiplier: float = 1.0
# The ideal distance to maintain from the player while stalking.
@export var hover_distance: float = 150.0
# The cooldown in seconds after a retreat before the next attack dive.
@export var attack_cooldown: float = 2.0
# How much to vary the retreat angle (in degrees). 0 means run straight back.
@export var retreat_angle_variance: float = 20.0
# The chance (0.0 to 1.0) to reverse circling direction each second.
@export var stalk_reverse_direction_chance: float = 0.1

# --- JUGGERNAUT BEHAVIOR ---
@export_group("Juggernaut")
# The distance within which the enemy chases normally.
@export var normal_chase_range: float = 150.0
# The distance beyond which the enemy will try to charge.
@export var charge_trigger_range: float = 300.0
# How long (in seconds) the enemy must be chasing before it can decide to charge.
@export var charge_trigger_timer: float = 3.0
# How long (in seconds) the enemy flashes/telegraphs its charge.
@export var charge_telegraph_duration: float = 0.8
# The speed multiplier applied during the charge.
@export var charge_speed_multiplier: float = 5.0
# The maximum distance the enemy will travel during a single charge.
@export var charge_max_distance: float = 500.0
# How long (in seconds) the enemy is stunned and vulnerable after a charge.
@export var post_charge_stun_duration: float = 1.5
# How strongly the charge corrects its course towards the player. 0 = no homing, ~1-5 = weak homing.
@export var charge_homing_strength: float = 1.0

# --- ON-DEATH BEHAVIORS ---
@export_group("On-Death: Slime Split")
@export var split_enemy_id: StringName = &""
@export var split_count: int = 2
@export var split_scale_multiplier: float = 0.75
@export_range(0.0, 1.0, 0.01) var slime_proc_chance: float = 1.0

@export_group("On-Death: Creeper")
@export var creeper_bullet_scene: PackedScene
@export var creeper_bullet_count: int = 8
@export var creeper_bullet_speed: float = 200.0
@export var creeper_bullet_damage: float = 5.0
@export var creeper_telegraph_duration: float = 2.0 # Time before bullets start firing.
@export var creeper_fire_interval: float = 0.1 # Time between each sequential bullet.
@export_range(0.0, 1.0, 0.01) var creeper_proc_chance: float = 1.0

@export_group("On-Death: Berserker")
@export var berserker_wave_scene: PackedScene
@export var berserker_wave_radius: float = 200.0
@export var berserker_buff_data: StatusEffectData # Link your berserk_buff.tres here
@export_range(0.0, 1.0, 0.01) var berserker_proc_chance: float = 1.0

@export_group("On-Death: Link")
@export var link_heal_projectile_scene: PackedScene
@export var link_projectile_count: int = 1
@export var link_search_radius: float = 400.0
@export var link_heal_percent: float = 0.33 # 33% of the dead enemy's max health
@export var link_arc_height: float = 100.0 # How high the arc of the healing projectile is.
@export_range(0.0, 1.0, 0.01) var link_proc_chance: float = 1.0

@export_group("On-Death: Corpse Explosion")
@export var corpse_explosion_scene: PackedScene
@export var corpse_explosion_damage: float = 25.0
@export var corpse_explosion_radius: float = 100.0
@export var corpse_explosion_telegraph_duration: float = 1.5
@export_range(0.0, 1.0, 0.01) var corpse_explosion_proc_chance: float = 1.0

@export_group("On-Death: Gravity Well")
@export var gravity_well_scene: PackedScene
@export_range(0.0, 1.0, 0.01) var gravity_well_proc_chance: float = 1.0
@export var gravity_well_telegraph_duration: float = 1.0 # Delay before the pull starts
@export var gravity_well_pull_duration: float = 2.5 # How long the pull lasts
@export var gravity_well_radius: float = 200.0 # The radius of the effect
@export var gravity_well_strength: float = 300.0 # The strength of the pull

# --- NEW: Ranged Behavior Data ---
@export_group("Ranged: Core Behavior")
@export var movement_pattern: RangedMovementPattern = RangedMovementPattern.STATIONARY
@export var firing_pattern: RangedFiringPattern = RangedFiringPattern.AUTO
@export var max_firing_range: float = 400.0

@export_group("Ranged: Movement - Kite")
@export_range(0.0, 1.0, 0.01) var kite_flee_speed_multiplier: float = 0.5
@export var kite_comfort_zone_buffer: float = 20.0 # +/- this value around ideal range

@export_group("Ranged: Movement - Circle")
@export_range(0.0, 1.0, 0.01) var circle_speed_multiplier: float = 0.5
@export var circle_direction_change_interval: float = 5.0 # Seconds
@export var circle_comfort_zone_buffer: float = 40.0 # +/- this value around ideal range
@export_range(0.0, 1.0, 0.01) var circle_flee_speed_multiplier: float = 0.5

@export_group("Ranged: Movement - Irratic")
@export_range(0.0, 1.0, 0.01) var irratic_min_range_percent: float = 0.3
@export_range(0.0, 1.0, 0.01) var irratic_max_range_percent: float = 0.7
@export_range(0.0, 2.0, 0.01) var irratic_adjust_speed_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01) var irratic_flee_speed_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01) var irratic_comfort_zone_speed_multiplier: float = 1.0


@export_group("Ranged: Firing - General")
@export var ranged_projectile_scene: PackedScene
@export var ranged_projectile_damage: float = 10.0
@export var ranged_projectile_speed: float = 250.0
@export var ranged_projectile_lifespan: float = 5.0

@export_group("Ranged: Firing - Auto")
@export var auto_fire_cooldown: float = 2.0

@export_group("Ranged: Firing - Burst")
@export var burst_fire_cooldown: float = 3.0
@export var burst_shot_count: int = 3
@export var burst_shot_delay: float = 0.15

@export_group("Ranged: Firing - Irratic Burst")
@export var irratic_cooldown_min: float = 2.0
@export var irratic_cooldown_max: float = 4.0
@export var irratic_shot_count: int = 5
@export var irratic_shot_delay_min: float = 0.1
@export var irratic_shot_delay_max: float = 0.3

@export_group("Ranged: Firing - Homing")
@export var homing_fire_cooldown: float = 4.0
@export_range(0.0, 5.0, 0.01) var homing_strength: float = 0.2

@export_group("Ranged: Firing - Prediction")
@export var use_shot_prediction: bool = false
@export_range(0.1, 5.0, 0.05) var shot_prediction_time: float = 0.5

@export_group("Orbital Behavior")
@export var orbital_projectile_scene: PackedScene
@export var max_orbs: int = 3
@export var orb_spawn_rate: float = 2.0 ## Seconds between each orb spawn
@export var orbit_speed: float = 2.0 ## Radians per second
@export var orbit_distance: float = 75.0 ## The minimum distance from the enemy's center
@export var orb_damage: float = 5.0
@export_group("Orbital Behavior - Kiting Fallback")
@export var orbital_comfort_zone_buffer: float = 10.0 # +/- this value around orbit_distance
@export_range(0.0, 2.0, 0.01) var orbital_flee_speed_multiplier: float = 0.75
@export_group("Orbital Behavior - Dynamic Orb Motion")
@export var orb_pulse_magnitude: float = 0.0 ## Additional distance the orbs pulse outwards
@export var orb_pulse_frequency: float = 1.0 ## How many pulses per second
@export var orb_wave_magnitude: float = 0.0 ## How high/low the orbs move in z-index
@export var orb_wave_frequency: float = 1.0 ## How many waves per orbit
@export_group("Orbital Behavior - Predictive Aiming")
@export var use_predictive_aiming: bool = false
@export_range(0.1, 2.0, 0.05) var prediction_time: float = 0.5 ## How far ahead to predict player movementment

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
## Optional: Specific enemy ID(s) this summoner prefers to summon.
## If empty, BaseEnemy.gd's summoner logic might pick a default or weakest.
@export var summoner_minion_ids: Array[StringName] = []


@export_group("Elite: Shaman Config (if this enemy can be a Shaman)")
## Radius of the Shaman's healing aura. Logic in BaseEnemy.gd.
@export var shaman_heal_radius: float = 120.0
## Percentage of max health healed per tick by the Shaman. Logic in BaseEnemy.gd.
@export_range(0.0, 1.0, 0.01) var shaman_heal_percent: float = 0.10 # 10%
## Interval in seconds for the Shaman's healing pulse. Logic in BaseEnemy.gd.
@export var shaman_heal_interval: float = 1.0

@export_group("Elite: Time-Warper Config (if this enemy can be a Time-Warper)")
## Radius of the Time-Warper's slowing aura. Logic in BaseEnemy.gd (likely applies a status to player).
@export var time_warp_radius: float = 180.0
## Percentage to slow player movement and attack speed. Logic in BaseEnemy.gd/Player StatusEffect.
@export_range(0.0, 1.0, 0.01) var time_warp_slow_percent: float = 0.25 # 25% slow
## Duration in seconds the slow effect lingers after player exits the aura. Logic in Player StatusEffect.
@export var time_warp_linger_duration: float = 2.0

@export_group("Culling & Threat")
## How much this enemy adds to the global threat pool if culled (removed for being too far off-screen).
@export var threat_value_when_culled: int = 1


func _init():
	pass

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings for common setup issues and data integrity.
func _validate_property(property: Dictionary):
	if Engine.is_editor_hint():
	# Validate 'id'
		if property.name == "id" and (property.get("value", &"") == &""):
			push_warning("EnemyData: 'id' cannot be empty for resource: ", resource_path)
		
		# Validate 'scene_path'
		if property.name == "scene_path" and (property.get("value", "") == ""):
			push_warning("EnemyData: 'scene_path' cannot be empty for resource: ", resource_path)
		elif property.name == "scene_path" and (property.get("value", "") != ""):
			var path = property.get("value", "")
			if not ResourceLoader.exists(path):
				push_warning("EnemyData: Enemy scene path '", path, "' does not exist for resource: ", resource_path)
			elif not path.ends_with(".tscn"):
				push_warning("EnemyData: Enemy scene path '", path, "' does not end with '.tscn' for resource: ", resource_path)

		# Validate 'exp_drop_scene_path'
		if property.name == "exp_drop_scene_path" and (property.get("value", "") == ""):
			push_warning("EnemyData: 'exp_drop_scene_path' cannot be empty for resource: ", resource_path)
		elif property.name == "exp_drop_scene_path" and (property.get("value", "") != ""):
			var path = property.get("value", "")
			if not ResourceLoader.exists(path):
				push_warning("EnemyData: EXP drop scene path '", path, "' does not exist for resource: ", resource_path)
			elif not path.ends_with(".tscn"):
				push_warning("EnemyData: EXP drop scene path '", path, "' does not end with '.tscn' for resource: ", resource_path)

		# Validate 'elite_types_available'
		if property.name == "elite_types_available":
			var elite_types_array = property.get("value", [])
			for i in range(elite_types_array.size()):
				var tag = elite_types_array[i]
				if not tag is StringName or tag == &"":
					push_warning("EnemyData: Elite type tag at index ", i, " is empty or not a StringName for resource: ", resource_path)
				# You could add further validation here to check against a global list of known elite types.

		# Validate Summoner config if summoner_minion_ids are used
		if property.name == "summoner_minion_ids":
			var minion_ids_array = property.get("value", [])
			if not minion_ids_array.is_empty() and not elite_types_available.has(&"summoner"):
				push_warning("EnemyData: 'summoner_minion_ids' configured but 'summoner' is not in 'elite_types_available' for resource: ", resource_path)
			for i in range(minion_ids_array.size()):
				var minion_id = minion_ids_array[i]
				if not minion_id is StringName or minion_id == &"":
					push_warning("EnemyData: Summoner minion ID at index ", i, " is empty or not a StringName for resource: ", resource_path)
				# Further validation could ensure these minion_ids correspond to actual EnemyData resources.
