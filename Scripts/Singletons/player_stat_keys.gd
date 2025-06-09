# player_stat_keys.gd
# This script defines all standardized StringName keys for player stats.
# It acts as a single source of truth for stat names throughout the project.
#
# IMPORTANT: This script MUST be set as an Autoload in Project Settings
# (Project -> Project Settings -> Autoload, Node Name: GameStatConstants).
# It now extends Node to be instantiable as an Autoload.

extends Node # FIXED: CRITICAL - Must extend Node to be a valid Autoload singleton.

# The enum holds symbolic names for each stat. These provide autocompletion benefits
# in the script editor and make your code more readable.
enum Keys {
	# --- Core Health & Regeneration ---
	MAX_HEALTH,                     # Total health capacity
	HEALTH_REGENERATION,            # HP restored per second
	HEALTH_ON_HIT_FLAT,             # Flat HP restored on hitting an enemy
	HEALTH_ON_KILL_FLAT,            # Flat HP restored on killing an enemy
	HEALTH_ON_KILL_PERCENT_MAX,     # Percentage of Max HP restored on killing an enemy

	# --- Core Combat Stats ---
	NUMERICAL_DAMAGE,               # Player's base damage value (weapons use this as a base)
	GLOBAL_DAMAGE_MULTIPLIER,       # Multiplier applied to ALL player damage (e.g., from buffs like Empower)
	ATTACK_SPEED_MULTIPLIER,        # Multiplier affecting weapon cooldowns/attack rates
	ARMOR,                          # Flat damage reduction against physical attacks
	ARMOR_PENETRATION,              # Flat amount of enemy armor ignored by player attacks

	# --- Movement & Utility ---
	MOVEMENT_SPEED,                 # Player's base movement speed
	MAGNET_RANGE,                   # Radius for auto-collecting experience and other pickups
	EXPERIENCE_GAIN_MULTIPLIER,     # Multiplier for experience gained

	# --- Weapon Effect Modifiers (affecting ALL weapons and abilities) ---
	AOE_AREA_MULTIPLIER,            # Multiplier for the radius/area of effect abilities
	PROJECTILE_SIZE_MULTIPLIER,     # Multiplier for the visual size and collision of projectiles
	PROJECTILE_SPEED_MULTIPLIER,    # Multiplier for the travel speed of projectiles
	EFFECT_DURATION_MULTIPLIER,     # Multiplier for the duration of player-applied effects (buffs/debuffs)

	# --- Critical Hit Stats ---
	CRIT_CHANCE,                    # Probability (0.0 to 1.0) of landing a critical hit
	CRIT_DAMAGE_MULTIPLIER,         # Multiplier for damage when a critical hit occurs (e.g., 1.5 for 150% damage)

	# --- Other Core Stats ---
	LUCK,                           # Affects various probabilistic outcomes (e.g., item drops, rare events)

	# --- Advanced Defensive Stats (typically gained from upgrades/effects) ---
	DAMAGE_REDUCTION_MULTIPLIER,    # Overall percentage reduction to incoming damage (e.g., 10% less)
	DAMAGE_TAKEN_MULTIPLIER,        # Multiplier to damage taken (e.g., from Vulnerable debuff)
	DODGE_CHANCE,                   # Probability (0.0 to 1.0) to completely avoid an attack
	BLOCK_CHANCE,                   # Probability (0.0 to 1.0) to block an attack
	BLOCK_EFFECTIVENESS_MULTIPLIER, # Multiplier for the amount of damage blocked
	KNOCKBACK_RESISTANCE_FLAT,      # Flat reduction to incoming knockback distance

	# --- Resource Management (Examples: Mana/Stamina/Energy - extend as needed) ---
	MAX_RESOURCE,                   # Generic placeholder for max capacity of any resource
	RESOURCE_REGENERATION,          # Generic placeholder for resource regeneration per second
	RESOURCE_ON_HIT,                # Generic placeholder for resource gained on hitting an enemy
	RESOURCE_ON_KILL,               # Generic placeholder for resource gained on killing an enemy
	RESOURCE_COST_REDUCTION_MULT,   # Percentage reduction in resource costs for abilities

	# --- Offensive - General (additional modifiers, not typically base class stats) ---
	GLOBAL_FLAT_DAMAGE_ADD,         # Flat damage added to every hit (e.g., from "Might" upgrade)
	GLOBAL_COOLDOWN_REDUCTION_FLAT, # Flat seconds reduced from all weapon/ability cooldowns
	GLOBAL_COOLDOWN_REDUCTION_MULT, # Percentage reduction from all weapon/ability cooldowns
	GLOBAL_PROJECTILE_COUNT_ADD,    # Flat number of additional projectiles for relevant abilities
	GLOBAL_DEBUFF_POTENCY_MULT,     # Multiplier for the strength/potency of debuffs applied by player
	GLOBAL_BUFF_POTENCY_MULT,       # Multiplier for the strength/potency of buffs applied to player/allies

	# --- Utility & Economy (additional modifiers) ---
	CURRENCY_GAIN_MULTIPLIER,       # Multiplier for gold/currency gained
	ITEM_DROP_CHANCE_ADD,           # Flat addition to the chance of items dropping
	INVULNERABILITY_FRAMES_ADD,     # Flat duration added to invulnerability frames after taking damage

	# --- Shield System Stats (if implemented) ---
	SHIELD_CAPACITY_FLAT,           # Flat increase to shield capacity
	SHIELD_REGEN_RATE_FLAT,         # Flat increase to shield regeneration rate
	SHIELD_REGEN_DELAY_REDUCTION,   # Flat reduction to shield regeneration delay

	# --- Magic Penetration (if magic resistance exists) ---
	MAGIC_RESIST_PEN_FLAT,          # Flat amount of enemy magic resistance ignored
	MAGIC_RESIST_PEN_PERCENT,       # Percentage of enemy magic resistance ignored

	# --- Threat Management ---
	THREAT_GENERATION_MULTIPLIER,   # Multiplier for threat generated by player actions (for aggro systems)

	# --- Specific Temporary Bonuses (consumed after use) ---
	NEXT_ATTACK_FLAT_DAMAGE_BONUS,  # Flat damage added to the very next attack (e.g., from an ability)

	# --- Specific Resource Keys (if you differentiate resources like Mana/Stamina) ---
	MANA_MAX,                       # Maximum mana capacity
	MANA_REGENERATION_RATE,         # Mana restored per second
	MANA_ON_HIT_FLAT,               # Flat mana restored on hitting an enemy
	MANA_ON_KILL_FLAT,              # Flat mana restored on killing an enemy
	MANA_COST_REDUCTION_PERCENT,    # Percentage reduction in mana costs

	# --- Damage Type Conversions (if applicable) ---
	PHYSICAL_TO_FIRE_CONVERSION_PERCENT, # Percentage of physical damage converted to fire damage
	# Add other conversion types (e.g., ICE_TO_LIGHTNING_CONVERSION_PERCENT) as needed
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

	Keys.DAMAGE_REDUCTION_MULTIPLIER: &"damage_reduction_multiplier",
	Keys.DAMAGE_TAKEN_MULTIPLIER: &"damage_taken_multiplier",
	Keys.DODGE_CHANCE: &"dodge_chance",
	Keys.BLOCK_CHANCE: &"block_chance",
	Keys.BLOCK_EFFECTIVENESS_MULTIPLIER: &"block_effectiveness_multiplier",
	Keys.KNOCKBACK_RESISTANCE_FLAT: &"knockback_resistance_flat",

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

	Keys.CURRENCY_GAIN_MULTIPLIER: &"currency_gain_multiplier",
	Keys.ITEM_DROP_CHANCE_ADD: &"item_drop_chance_add",
	Keys.INVULNERABILITY_FRAMES_ADD: &"invulnerabilities_frames_add", # Corrected typo

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
}
