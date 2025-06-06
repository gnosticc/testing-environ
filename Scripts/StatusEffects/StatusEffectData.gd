# StatusEffectData.gd
# Resource to define properties of a status effect.
class_name StatusEffectsData
extends Resource

enum EffectType {
	DAMAGE_OVER_TIME,     # e.g., Bleed, Poison, Burn (classic DoT)
	TIMED_STAT_MODIFIER,  # e.g., Vulnerable, Weaken, Haste, Empower (temp stat changes)
	CONTROL_IMPAIRING,    # e.g., Stun, Root, Slow, Fear
	HEAL_OVER_TIME,       # e.g., Regeneration buff
	ONE_SHOT_DAMAGE,      # e.g., Burn's final explosion
	ONE_SHOT_HEAL,        # e.g., Instant heal proc
	PASSIVE_STAT_MODIFIER,# e.g., Enemy Elite/Champion traits (permanent while active)
	SPECIAL_LOGIC         # For unique effects like Phaser, Summoner, Death's Blessing, Rampage
}

@export var effect_id: StringName = &"" # Unique ID, e.g., "bleed_standard", "vulnerable_enemy"
@export var effect_name: String = "Status Effect" # Display name, e.g., "Bleeding", "Vulnerable"
@export_multiline var description: String = "Effect description."
@export var icon: Texture2D = null

@export var effect_type: EffectType = EffectType.TIMED_STAT_MODIFIER
@export var is_buff: bool = false # True for positive effects, false for debuffs/DoTs

@export_group("Duration & Ticking")
@export var base_duration: float = 5.0 # Seconds; 0 for instant, -1 for permanent until removed by logic
@export var tick_interval: float = 1.0 # Seconds; 0 if no ticking (e.g., for stat mods that apply once)
								   # For your Bleed (20 ticks over 2s), this would be 0.1

@export_group("Stacking & Application")
# true = refresh duration; false = new instance (if different source or effect allows stacking from same source)
# For your design: all effects refresh duration from the same source ID.
# Different sources applying the same effect_id will also refresh (unless we add source tracking)
@export var refresh_on_reapply: bool = true 
# @export var max_stacks: int = 1 # If we were to implement intensity stacking later

@export_group("Damage Over Time (DoT) / Heal Over Time (HoT)")
# For Bleed: total_damage_percent_of_source_hit = 1.0 (100%)
# The component will divide this by (base_duration / tick_interval) to get damage per tick.
@export var total_damage_or_heal_percent_of_source_hit: float = 0.0 # e.g., 1.0 for 100% of source hit over duration
@export var flat_damage_or_heal_per_tick: float = 0.0 # If not based on source hit
@export var dot_damage_type: StringName = &"physical_dot" # For resistances/synergies

@export_group("Stat Modification (Timed or Passive)")
# Example: {"movement_speed_multiplier_add": -0.2} for a 20% slow
# Example: {"damage_taken_multiplier_add": 0.2} for Vulnerable (target takes 20% more)
# These keys should match stat calculation logic in PlayerStats or BaseEnemy's take_damage
@export var stat_modifiers: Dictionary = {} # { "stat_name_to_mod": value, "mod_type": "flat_add"/"percent_add"/"percent_mult" }
										   # Or simpler: { "stat_name_to_mod_flat": value, "stat_name_to_mod_percent_add": value }

@export_group("Control Effects")
@export var control_effect_type: StringName = &"" # e.g., "stun", "root", "fear"

@export_group("Special Logic (for effect_type == SPECIAL_LOGIC)")
@export var special_logic_params: Dictionary = {} # For effects like Phaser, Summoner, Death's Blessing

@export_group("Visuals & Audio (Paths)")
@export var sfx_on_apply: AudioStream = null
@export var sfx_on_tick: AudioStream = null
@export var sfx_on_expire: AudioStream = null
@export var vfx_on_target_scene: PackedScene = null # Particle effect to loop on target
