# PlayerClassData.gd
# Resource to define base stats for a player class.
class_name PlayerClassData
extends Resource

# --- Core Combat Stats ---
@export var base_max_health: int = 100
@export var base_health_regeneration: float = 0.0 # HP per second
@export var base_numerical_damage: int = 10 # NEW: Player's core damage value
@export var base_global_damage_multiplier: float = 1.0 # Player's global damage multiplier (usually starts at 1.0)
# Note: base_damage_bonus (flat added at end) will be a general stat, not class-specific base.
@export var base_attack_speed_multiplier: float = 1.0 
@export var base_armor: int = 0 
@export var base_armor_penetration: float = 0.0 

# --- Movement & Utility ---
@export var base_movement_speed: float = 60.0
@export var base_magnet_range: float = 40.0 
@export var base_experience_gain_multiplier: float = 1.0

# --- Weapon Effect Modifiers ---
@export var base_aoe_area_multiplier: float = 1.0 
@export var base_projectile_size_multiplier: float = 1.0 
@export var base_projectile_speed_multiplier: float = 1.0
@export var base_effect_duration_multiplier: float = 1.0 

# --- Other Stats ---
@export var base_crit_chance: float = 0.05 
@export var base_crit_damage_multiplier: float = 1.5 
@export var base_luck: int = 0

@export_multiline var class_description: String = "Description of this class."
