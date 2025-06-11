# player_stat_keys.gd
# This script defines standardized StringName constants for all player and weapon-specific stats,
# as well as behavioral flags.
# It should be set as an Autoload Singleton in Project Settings (e.g., as 'PlayerStatKeys').
# Using StringName constants prevents typos and enables autocompletion, improving code robustness.

extends Node # CRITICAL: Must extend Node to be a valid Autoload singleton.

# The enum holds symbolic names for each stat. These provide autocompletion benefits
# in the script editor and make your code more readable.
enum Keys {
	# --- Core Health & Regeneration ---
	MAX_HEALTH, # Total health capacity
	HEALTH_REGENERATION, # HP restored per second
	HEALTH_ON_HIT_FLAT, # Flat HP restored on hitting an enemy
	HEALTH_ON_KILL_FLAT, # Flat HP restored on killing an enemy
	HEALTH_ON_KILL_PERCENT_MAX, # Percentage of Max HP restored on killing an enemy

	# --- Core Combat Stats ---
	NUMERICAL_DAMAGE, # Player's base damage value (weapons use this as a base)
	GLOBAL_DAMAGE_MULTIPLIER, # Multiplier applied to ALL player damage (e.g., from buffs like Empower)
	ATTACK_SPEED_MULTIPLIER, # Multiplier affecting weapon cooldowns/attack rates
	ARMOR, # Flat damage reduction against physical attacks
	ARMOR_PENETRATION, # Player's base armor penetration

	# --- Movement & Utility ---
	MOVEMENT_SPEED, # Player's base movement speed
	MAGNET_RANGE, # Radius for auto-collecting experience and other pickups
	EXPERIENCE_GAIN_MULTIPLIER, # Multiplier for experience gained

	# --- Weapon Effect Modifiers (affecting ALL weapons and abilities) ---
	AOE_AREA_MULTIPLIER, # Multiplier for the radius/area of effect abilities
	PROJECTILE_SIZE_MULTIPLIER, # Multiplier for the visual size and collision of projectiles
	PROJECTILE_SPEED_MULTIPLIER, # Multiplier for the travel speed of projectiles
	EFFECT_DURATION_MULTIPLIER, # Multiplier for the duration of player-applied effects (buffs/debuffs)

	# --- Critical Hit Stats ---
	CRIT_CHANCE, # Probability (0.0 to 1.0) of landing a critical hit
	CRIT_DAMAGE_MULTIPLIER, # Multiplier for damage when a critical hit occurs (e.g., 1.5 for 150% damage)

	# --- Other Core Stats ---
	LUCK, # Affects various probabilistic outcomes (e.g., item drops, rare events)

	# --- Advanced Defensive Stats (typically gained from upgrades/effects) ---
	GLOBAL_PERCENT_DAMAGE_REDUCTION, # NEW: Reduces all incoming damage by a percentage (e.g., 0.1 for 10% reduction)
	DAMAGE_REDUCTION_MULTIPLIER, # Overall percentage reduction to incoming damage (e.g., 10% less) - kept for existing uses
	DAMAGE_TAKEN_MULTIPLIER, # Multiplier to damage taken (e.g., from Vulnerable debuff)
	DODGE_CHANCE, # NEW: Probability (0.0 to 1.0) to completely avoid an attack
	BLOCK_CHANCE, # Probability (0.0 to 1.0) to block an attack
	BLOCK_EFFECTIVENESS_MULTIPLIER, # Multiplier for the amount of damage blocked
	KNOCKBACK_RESISTANCE_FLAT, # Flat reduction to incoming knockback resistance
	INVULNERABILITY_DURATION_ADD, # NEW: Flat duration added to invulnerability frames after taking damage
	GLOBAL_FLAT_DAMAGE_REDUCTION, # NEW: Flat damage reduction against all incoming damage

	# --- Resource Management (Examples: Mana/Stamina/Energy - extend as needed) ---
	MAX_RESOURCE, # Generic placeholder for max capacity of any resource
	RESOURCE_REGENERATION, # Generic placeholder for resource regeneration per second
	RESOURCE_ON_HIT, # Generic placeholder for resource gained on hitting an enemy
	RESOURCE_ON_KILL, # Generic placeholder for resource gained on killing an enemy
	RESOURCE_COST_REDUCTION_MULT, # Percentage reduction in resource costs for abilities

	# --- Offensive - General (additional modifiers, not typically base class stats) ---
	GLOBAL_FLAT_DAMAGE_ADD, # Flat damage added to every hit (e.g., from "Might" upgrade)
	GLOBAL_COOLDOWN_REDUCTION_FLAT, # Flat seconds reduced from all weapon/ability cooldowns
	GLOBAL_COOLDOWN_REDUCTION_MULT, # Percentage reduction from all weapon/ability cooldowns
	GLOBAL_PROJECTILE_COUNT_ADD, # Flat number of additional projectiles for relevant abilities
	GLOBAL_DEBUFF_POTENCY_MULT, # Multiplier for the strength/potency of debuffs applied by player
	GLOBAL_BUFF_POTENCY_MULT, # Multiplier for the strength/potency of buffs applied to player/allies
	GLOBAL_STATUS_EFFECT_CHANCE_ADD, # NEW: Adds a flat bonus to the chance of applying any status effect.
	GLOBAL_PROJECTILE_FORK_COUNT_ADD, # NEW: Adds a flat number of extra projectiles that split off.
	GLOBAL_PROJECTILE_BOUNCE_COUNT_ADD, # NEW: Adds a flat number of extra bounces for projectiles.
	GLOBAL_PROJECTILE_EXPLODE_ON_DEATH_CHANCE, # NEW: Chance for any projectile to explode in a small AoE when it despawns.
	GLOBAL_CHAIN_LIGHTNING_COUNT, # NEW: Adds a flat number of chain targets for chaining projectiles.
	GLOBAL_LIFESTEAL_PERCENT, # NEW: Percentage of damage dealt converted to healing.

	# --- Utility & Economy (additional modifiers) ---
	CURRENCY_GAIN_MULTIPLIER, # Multiplier for gold/currency gained
	ITEM_DROP_CHANCE_ADD, # Flat addition to the chance of items dropping
	GLOBAL_GOLD_GAIN_MULTIPLIER, # NEW: Multiplies gold received (redundant with CURRENCY_GAIN_MULTIPLIER but kept for clarity if preferred)

	# --- Shield System Stats (if implemented) ---
	SHIELD_CAPACITY_FLAT, # Flat increase to shield capacity
	SHIELD_REGEN_RATE_FLAT, # Flat increase to shield regeneration rate
	SHIELD_REGEN_DELAY_REDUCTION, # Flat reduction to shield regeneration delay

	# --- Magic Penetration (if magic resistance exists) ---
	MAGIC_RESIST_PEN_FLAT, # Flat amount of enemy magic resistance ignored
	MAGIC_RESIST_PEN_PERCENT, # Percentage of enemy magic resistance ignored

	# --- Threat Management ---
	THREAT_GENERATION_MULTIPLIER, # Multiplier for threat generated by player actions (for aggro systems)

	# --- Specific Temporary Bonuses (consumed after use) ---
	NEXT_ATTACK_FLAT_DAMAGE_BONUS, # Flat damage added to the very next attack (e.g., from an ability)

	# --- Specific Resource Keys (if you differentiate resources like Mana/Stamina) ---
	MANA_MAX, # Maximum mana capacity
	MANA_REGENERATION_RATE, # Mana restored per second
	MANA_ON_HIT_FLAT, # Flat mana restored on hitting an enemy
	MANA_ON_KILL_FLAT, # Flat mana restored on killing an enemy
	MANA_COST_REDUCTION_PERCENT, # Percentage reduction in mana costs

	# --- Damage Type Conversions (if applicable) ---
	PHYSICAL_TO_FIRE_CONVERSION_PERCENT, # Percentage of physical damage converted to fire damage
	# Add other conversion types (e.g., ICE_TO_LIGHTNING_CONVERSION_PERCENT) as needed
	
	# --- Weapon Specific Stats ---
	WEAPON_DAMAGE_PERCENTAGE, # Multiplier for player's numerical_damage
	PIERCE_COUNT, # How many enemies a projectile can pierce
	PROJECTILE_SPEED, # Speed of projectiles
	SHOT_DELAY, # Delay between individual shots/hits in an attack
	BASE_ATTACK_DURATION, # Base duration of an attack animation/hitbox
	AREA_SCALE, # Scaling factor for weapon hitboxes/areas
	DAMAGE_TICK_INTERVAL, # Interval for damage-over-time effects
	MAX_CAST_RANGE, # Maximum range for casting abilities/projectiles
	MAX_SUMMONS_OF_TYPE, # Max number of a specific type of summon
	INHERENT_VISUAL_SCALE_X, # X-scale for the weapon's visual
	INHERENT_VISUAL_SCALE_Y, # Y-scale for the weapon's visual
	WHIRLWIND_COUNT, # Number of whirlwind spins (Scythe-specific)
	ORBIT_RADIUS, # Radius for orbiting attacks (e.g., Lesser Spirit)
	NUMBER_OF_ORBITS, # Number of orbiting instances

	# --- Summon Specific Stats (GLOBAL MODIFIERS TO SUMMONS) ---
	GLOBAL_SUMMON_DAMAGE_MULTIPLIER, # NEW: Multiplies damage dealt by all player summons.
	GLOBAL_SUMMON_LIFETIME_MULTIPLIER, # NEW: Multiplies the duration of all player summons.
	GLOBAL_SUMMON_COUNT_ADD, # NEW: Adds a flat number of extra summons allowed simultaneously.
	GLOBAL_SUMMON_COOLDOWN_REDUCTION_PERCENT, # NEW: Reduces cooldown for summoning new units.

	# --- Global Modifiers for Specific Weapon Tags (NEW) ---
	# These multipliers affect weapons that have the corresponding tag in their WeaponBlueprintData.tags array.
	# The naming convention is TAG_STAT_TYPE_MODIFIER for clarity.
	MELEE_DAMAGE_MULTIPLIER,
	PROJECTILE_DAMAGE_MULTIPLIER,
	MAGIC_DAMAGE_MULTIPLIER,
	PHYSICAL_DAMAGE_MULTIPLIER, # This is a tag, not a damage type (use NUMERICAL_DAMAGE for general physical damage)
	FIRE_DAMAGE_MULTIPLIER, # If elemental damage types exist
	ICE_DAMAGE_MULTIPLIER,

	MELEE_ATTACK_SPEED_MULTIPLIER,
	PROJECTILE_ATTACK_SPEED_MULTIPLIER,
	MAGIC_ATTACK_SPEED_MULTIPLIER,

	MELEE_AOE_AREA_MULTIPLIER,
	MAGIC_AOE_AREA_MULTIPLIER,

	PROJECTILE_PIERCE_COUNT_ADD, # Adds flat pierce count to projectiles
	PROJECTILE_MAX_RANGE_ADD, # Adds flat range to projectiles

	# --- Behavioral Flags (Used by Effects and WeaponManager) ---
	APPLIES_BLEED,
	APPLIES_VULNERABLE,
	HAS_REAPING_MOMENTUM, # Scythe-specific: grants damage on kill
	HAS_SOUL_SIPHON, # Scythe-specific: grants health on kill
	WHIRLWIND_ACTIVE, # Scythe-specific: enables whirlwind attacks
	CAN_DASH, # Player-specific: enables dashing ability

	# --- Target Scopes for Effects (Used in EffectData.gd subclasses) ---
	PLAYER_STATS, # Effect applies to the player's main stat system
	PLAYER_BEHAVIOR, # Effect applies to player-specific flags/behaviors
	WEAPON_SPECIFIC_STATS, # Effect applies to a specific weapon's stats (e.g., Scythe's damage)
	WEAPON_BEHAVIOR, # Effect applies to a specific weapon's flags/behaviors
	ENEMY_STATS,
	TARGET_STATS,
	TARGET_ENEMY,

	# --- Reaping Momentum Specific Keys (clarified from previous discussion) ---
	REAPING_MOMENTUM_DAMAGE_PER_HIT, # The base damage per hit for Reaping Momentum
	REAPING_MOMENTUM_ACCUMULATED_BONUS, # The current accumulated bonus for Reaping Momentum
	
	# --- Enemy Debuff Resistance ---
	ENEMY_DEBUFF_RESISTANCE_REDUCTION, # Reduces enemy resistance to your debuffs.

	# Acquired Upgrade Flags (Used by WeaponManager to track acquired upgrades for a weapon)
	SCYTHE_SHARPENED_EDGE_1_ACQUIRED,
	SCYTHE_SHARPENED_EDGE_2_ACQUIRED,
	SCYTHE_SHARPENED_EDGE_3_ACQUIRED,
	SCYTHE_CURSED_EDGE_ACQUIRED,
	SCYTHE_REAPING_MOMENTUM_ACQUIRED,
	SCYTHE_SERRATED_BLADE_ACQUIRED,
	SCYTHE_SOUL_SIPHON_ACQUIRED,
	SCYTHE_WHIRLWIND_TECHNIQUE_ACQUIRED,
	SCYTHE_WIDER_ARC_ACQUIRED,
	CROSSBOW_PIERCING_BOLTS_ACQUIRED,
	DAGGER_SHADOW_STEP_ACQUIRED,
}

# This dictionary maps the enum keys to their actual StringName values.
# StringName is optimized for dictionary keys and lookups in Godot and is more efficient
# than regular Strings for this purpose. Use the `&""` syntax for StringName literals.
const KEY_NAMES: Dictionary = {
	Keys.MAX_HEALTH: &"max_health",
	Keys.HEALTH_REGENERATION: &"health_regeneration",
	Keys.HEALTH_ON_HIT_FLAT: &"health_on_hit_flat",
	Keys.HEALTH_ON_KILL_FLAT: &"health_on_kill_flat",
	Keys.HEALTH_ON_KILL_PERCENT_MAX: &"health_on_kill_percent_max",

	Keys.NUMERICAL_DAMAGE: &"numerical_damage",
	Keys.GLOBAL_DAMAGE_MULTIPLIER: &"global_damage_multiplier",
	Keys.ATTACK_SPEED_MULTIPLIER: &"attack_speed_multiplier",
	Keys.ARMOR: &"armor",
	Keys.ARMOR_PENETRATION: &"armor_penetration",

	Keys.MOVEMENT_SPEED: &"movement_speed",
	Keys.MAGNET_RANGE: &"magnet_range",
	Keys.EXPERIENCE_GAIN_MULTIPLIER: &"experience_gain_multiplier",

	Keys.AOE_AREA_MULTIPLIER: &"aoe_area_multiplier",
	Keys.PROJECTILE_SIZE_MULTIPLIER: &"projectile_size_multiplier",
	Keys.PROJECTILE_SPEED_MULTIPLIER: &"projectile_speed_multiplier",
	Keys.EFFECT_DURATION_MULTIPLIER: &"effect_duration_multiplier",

	Keys.CRIT_CHANCE: &"crit_chance",
	Keys.CRIT_DAMAGE_MULTIPLIER: &"crit_damage_multiplier",

	Keys.LUCK: &"luck",

	Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION: &"global_percent_damage_reduction",
	Keys.DAMAGE_REDUCTION_MULTIPLIER: &"damage_reduction_multiplier",
	Keys.DAMAGE_TAKEN_MULTIPLIER: &"damage_taken_multiplier",
	Keys.DODGE_CHANCE: &"dodge_chance",
	Keys.BLOCK_CHANCE: &"block_chance",
	Keys.BLOCK_EFFECTIVENESS_MULTIPLIER: &"block_effectiveness_multiplier",
	Keys.KNOCKBACK_RESISTANCE_FLAT: &"knockback_resistance_flat",
	Keys.INVULNERABILITY_DURATION_ADD: &"invulnerability_duration_add",
	Keys.GLOBAL_FLAT_DAMAGE_REDUCTION: &"global_flat_damage_reduction", # Corrected key for GLOBAL_FLAT_DAMAGE_REDUCTION

	Keys.MAX_RESOURCE: &"max_resource",
	Keys.RESOURCE_REGENERATION: &"resource_regeneration",
	Keys.RESOURCE_ON_HIT: &"resource_on_hit",
	Keys.RESOURCE_ON_KILL: &"resource_on_kill",
	Keys.RESOURCE_COST_REDUCTION_MULT: &"resource_cost_reduction_mult",

	Keys.GLOBAL_FLAT_DAMAGE_ADD: &"global_flat_damage_add",
	Keys.GLOBAL_COOLDOWN_REDUCTION_FLAT: &"global_cooldown_reduction_flat",
	Keys.GLOBAL_COOLDOWN_REDUCTION_MULT: &"global_cooldown_reduction_mult",
	Keys.GLOBAL_PROJECTILE_COUNT_ADD: &"global_projectile_count_add",
	Keys.GLOBAL_DEBUFF_POTENCY_MULT: &"global_debuff_potency_mult",
	Keys.GLOBAL_BUFF_POTENCY_MULT: &"global_buff_potency_mult",
	Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD: &"global_status_effect_chance_add",
	Keys.GLOBAL_PROJECTILE_FORK_COUNT_ADD: &"global_projectile_fork_count_add",
	Keys.GLOBAL_PROJECTILE_BOUNCE_COUNT_ADD: &"global_projectile_bounce_count_add",
	Keys.GLOBAL_PROJECTILE_EXPLODE_ON_DEATH_CHANCE: &"global_projectile_explode_on_death_chance",
	Keys.GLOBAL_CHAIN_LIGHTNING_COUNT: &"global_chain_lightning_count",
	Keys.GLOBAL_LIFESTEAL_PERCENT: &"global_lifesteal_percent",

	Keys.CURRENCY_GAIN_MULTIPLIER: &"currency_gain_multiplier",
	Keys.ITEM_DROP_CHANCE_ADD: &"item_drop_chance_add",
	Keys.GLOBAL_GOLD_GAIN_MULTIPLIER: &"global_gold_gain_multiplier",

	Keys.SHIELD_CAPACITY_FLAT: &"shield_capacity_flat",
	Keys.SHIELD_REGEN_RATE_FLAT: &"shield_regeneration_rate",
	Keys.SHIELD_REGEN_DELAY_REDUCTION: &"shield_regen_delay_reduction",

	Keys.MAGIC_RESIST_PEN_FLAT: &"magic_resist_pen_flat",
	Keys.MAGIC_RESIST_PEN_PERCENT: &"magic_resist_pen_percent",

	Keys.THREAT_GENERATION_MULTIPLIER: &"threat_generation_multiplier",

	Keys.NEXT_ATTACK_FLAT_DAMAGE_BONUS: &"next_attack_flat_damage_bonus",

	Keys.MANA_MAX: &"mana_max",
	Keys.MANA_REGENERATION_RATE: &"mana_regeneration_rate",
	Keys.MANA_ON_HIT_FLAT: &"mana_on_hit_flat",
	Keys.MANA_ON_KILL_FLAT: &"mana_on_kill_flat",
	Keys.MANA_COST_REDUCTION_PERCENT: &"mana_cost_reduction_percent",

	Keys.PHYSICAL_TO_FIRE_CONVERSION_PERCENT: &"physical_to_fire_conversion_percent",
	
	# Weapon Specific Stats (Integrated from previous version)
	Keys.WEAPON_DAMAGE_PERCENTAGE: &"weapon_damage_percentage",
	Keys.PIERCE_COUNT: &"pierce_count",
	Keys.PROJECTILE_SPEED: &"projectile_speed",
	Keys.SHOT_DELAY: &"shot_delay",
	Keys.BASE_ATTACK_DURATION: &"base_attack_duration",
	Keys.AREA_SCALE: &"area_scale",
	Keys.DAMAGE_TICK_INTERVAL: &"damage_tick_interval",
	Keys.MAX_CAST_RANGE: &"max_cast_range",
	Keys.MAX_SUMMONS_OF_TYPE: &"max_summons_of_type",
	Keys.INHERENT_VISUAL_SCALE_X: &"inherent_visual_scale_x",
	Keys.INHERENT_VISUAL_SCALE_Y: &"inherent_visual_scale_y",
	Keys.WHIRLWIND_COUNT: &"whirlwind_count",
	Keys.ORBIT_RADIUS: &"orbit_radius",
	Keys.NUMBER_OF_ORBITS: &"number_of_orbits",

	# Summon Specific Stats (GLOBAL MODIFIERS TO SUMMONS)
	Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER: &"global_summon_damage_multiplier",
	Keys.GLOBAL_SUMMON_LIFETIME_MULTIPLIER: &"global_summon_lifetime_multiplier",
	Keys.GLOBAL_SUMMON_COUNT_ADD: &"global_summon_count_add",
	Keys.GLOBAL_SUMMON_COOLDOWN_REDUCTION_PERCENT: &"global_summon_cooldown_reduction_percent",

	# Global Modifiers for Specific Weapon Tags (NEW)
	# These multipliers affect weapons that have the corresponding tag in their WeaponBlueprintData.tags array.
	# The naming convention is TAG_STAT_TYPE_MODIFIER for clarity.
	Keys.MELEE_DAMAGE_MULTIPLIER: &"melee_damage_multiplier",
	Keys.PROJECTILE_DAMAGE_MULTIPLIER: &"projectile_damage_multiplier",
	Keys.MAGIC_DAMAGE_MULTIPLIER: &"magic_damage_multiplier",
	Keys.PHYSICAL_DAMAGE_MULTIPLIER: &"physical_damage_multiplier", # Note: This refers to the 'physical' tag, not a damage type.
	Keys.FIRE_DAMAGE_MULTIPLIER: &"fire_damage_multiplier", # For elemental damage types
	Keys.ICE_DAMAGE_MULTIPLIER: &"ice_damage_multiplier",

	Keys.MELEE_ATTACK_SPEED_MULTIPLIER: &"melee_attack_speed_multiplier",
	Keys.PROJECTILE_ATTACK_SPEED_MULTIPLIER: &"projectile_attack_speed_multiplier",
	Keys.MAGIC_ATTACK_SPEED_MULTIPLIER: &"magic_attack_speed_multiplier",

	Keys.MELEE_AOE_AREA_MULTIPLIER: &"melee_aoe_area_multiplier",
	Keys.MAGIC_AOE_AREA_MULTIPLIER: &"magic_aoe_area_multiplier",

	Keys.PROJECTILE_PIERCE_COUNT_ADD: &"projectile_pierce_count_add",
	Keys.PROJECTILE_MAX_RANGE_ADD: &"projectile_max_range_add",

	# Behavioral Flags (Used by Effects and WeaponManager)
	Keys.APPLIES_BLEED: &"applies_bleed",
	Keys.APPLIES_VULNERABLE: &"applies_vulnerable",
	Keys.HAS_REAPING_MOMENTUM: &"has_reaping_momentum", # This is the boolean flag for the ability itself
	Keys.HAS_SOUL_SIPHON: &"has_soul_siphon",
	Keys.WHIRLWIND_ACTIVE: &"whirlwind_active",
	Keys.CAN_DASH: &"can_dash",

	# Target Scopes for Effects (Used in EffectData.gd subclasses)
	Keys.PLAYER_STATS: &"player_stats",
	Keys.PLAYER_BEHAVIOR: &"player_behavior",
	Keys.WEAPON_SPECIFIC_STATS: &"weapon_specific_stats",
	Keys.WEAPON_BEHAVIOR: &"weapon_behavior",
	Keys.ENEMY_STATS: &"enemy_stats",
	Keys.TARGET_STATS: &"target_stats",
	Keys.TARGET_ENEMY: &"target_enemy",

	# Reaping Momentum Specific Keys (clarified from previous discussion)
	Keys.REAPING_MOMENTUM_DAMAGE_PER_HIT: &"reaping_momentum_damage_per_hit", # The static damage per hit value
	Keys.REAPING_MOMENTUM_ACCUMULATED_BONUS: &"reaping_momentum_accumulated_bonus", # The dynamic, accumulated bonus
	
	# Enemy Debuff Resistance
	Keys.ENEMY_DEBUFF_RESISTANCE_REDUCTION: &"enemy_debuff_resistance_reduction",

	# Acquired Upgrade Flags (Used by WeaponManager to track acquired upgrades for a weapon)
	Keys.SCYTHE_SHARPENED_EDGE_1_ACQUIRED: &"scythe_sharpened_edge_1_acquired",
	Keys.SCYTHE_SHARPENED_EDGE_2_ACQUIRED: &"scythe_sharpened_edge_2_acquired",
	Keys.SCYTHE_SHARPENED_EDGE_3_ACQUIRED: &"scythe_sharpened_edge_3_acquired",
	Keys.SCYTHE_CURSED_EDGE_ACQUIRED: &"scythe_cursed_edge_acquired",
	Keys.SCYTHE_REAPING_MOMENTUM_ACQUIRED: &"scythe_reaping_momentum_acquired",
	Keys.SCYTHE_SERRATED_BLADE_ACQUIRED: &"scythe_serrated_blade_acquired",
	Keys.SCYTHE_SOUL_SIPHON_ACQUIRED: &"scythe_soul_siphon_acquired",
	Keys.SCYTHE_WHIRLWIND_TECHNIQUE_ACQUIRED: &"scythe_whirlwind_technique_acquired",
	Keys.SCYTHE_WIDER_ARC_ACQUIRED: &"scythe_wider_arc_acquired",
	Keys.CROSSBOW_PIERCING_BOLTS_ACQUIRED: &"crossbow_piercing_bolts_acquired",
	Keys.DAGGER_SHADOW_STEP_ACQUIRED: &"dagger_shadow_step_acquired",
}
