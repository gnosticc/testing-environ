# StatusEffectData.gd
# Path: res://Scripts/DataResources/StatusEffects/StatusEffectData.gd
# Extends Resource to define the properties and behaviors of a status effect (buff or debuff).
class_name StatusEffectData
extends Resource

## Unique identifier for this status effect.
## Examples: "burn", "chill", "player_haste", "enemy_vulnerable"
@export var id: StringName = &""

## Display name for UI purposes (e.g., if shown on target's status bar).
@export var display_name: String = "Status Effect"

## Optional: Path to an icon texture for this status effect.
@export var icon: Texture2D = null

## Default duration of the status effect in seconds. 
## A duration of 0 or less might indicate a permanent toggle (if not stackable) or an instant effect.
## Can be overridden by StatusEffectApplicationData.
@export var duration: float = 5.0 

## How many times this status effect can stack on a single target.
## 0 or 1: No stacking (re-application might just refresh duration).
## >1: Allows multiple stacks, potentially increasing potency or duration per stack.
@export var max_stacks: int = 1

## If true, re-applying the effect to a target that already has it will refresh its duration.
@export var refresh_duration_on_reapply: bool = true

## If true, the 'effects_while_active' are re-evaluated and re-applied each time a stack is added.
## If false, they are applied once when the first stack is applied and removed when all stacks expire.
# @export var reapply_effects_on_stack: bool = true # Consider if needed, adds complexity

@export_group("Tick-Based Effects (for DoTs, HoTs, etc.)")
## Interval in seconds for tick-based effects (e.g., damage over time). 
## If 0, this is not a tick-based effect by default (or effects are instant).
@export var tick_interval: float = 0.0 
## If true, the first tick happens immediately upon application, then subsequent ticks follow the interval.
@export var tick_on_application: bool = false

@export_group("Core Effects")
## An array of EffectData resources (StatModificationEffectData, CustomFlagEffectData, etc.)
## that are applied to the target while this status effect is active.
## For DoTs like "burn", one of these effects would be a StatModificationEffectData that deals damage.
## For "chill", one might be a StatModificationEffectData that reduces "movement_speed".
@export var effects_while_active: Array[EffectData] = []

## Optional: Effects to apply *once* when the status effect is first applied.
# @export var effects_on_application: Array[EffectData] = []

## Optional: Effects to apply *once* when the status effect expires or is removed.
# @export var effects_on_expiration: Array[EffectData] = []

## Optional: StringName ID of another StatusEffectData to apply when this one expires (e.g., Chill -> Freeze)
# @export var next_status_effect_on_expire: StringName = &""


func _init():
	# developer_note = "Defines a status effect like Burn, Chill, Haste, etc."
	pass

# Potential helper methods could be added here if needed, e.g.,
# func get_modifier_for_stat(stat_key_to_find: StringName) -> StatModificationEffectData:
# 	for effect in effects_while_active:
# 		if effect is StatModificationEffectData:
# 			var stat_mod_effect = effect as StatModificationEffectData
# 			if stat_mod_effect.stat_key == stat_key_to_find:
# 				return stat_mod_effect
# 	return null
