# StatusEffectData.gd
# Path: res://Scripts/DataResources/StatusEffects/StatusEffectData.gd
# Extends Resource to define the properties and behaviors of a status effect (buff or debuff).
# ADDED: `next_status_effect_on_expire` to chain effects (e.g., Chill -> Freeze).
# Updated error reporting and added editor validation.

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

## NEW: Optional: StringName ID of another StatusEffectData to apply when this one expires (e.g., Chill -> Freeze)
@export var next_status_effect_on_expire: StringName = &""


func _init():
	pass

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings if key properties are empty or effects are invalid.
func _validate_property(property: Dictionary):
	if property.name == "id" and (property.get("value", &"") == &""):
		push_warning("StatusEffectData: 'id' cannot be empty for resource: ", resource_path)
	
	if property.name == "effects_while_active":
		var current_effects_array = property.get("value", [])
		for i in range(current_effects_array.size()):
			var effect = current_effects_array[i]
			if not is_instance_valid(effect):
				push_warning("StatusEffectData: Effect in 'effects_while_active' at index ", i, " is invalid (null).")
			elif not effect is EffectData:
				push_warning("StatusEffectData: Effect in 'effects_while_active' at index ", i, " is not an EffectData resource or its subclass.")
			# You can add more specific validation for StatModificationEffectData's stat_key here if needed
			# similar to what was done in WeaponUpgradeData.gd validation.
	
	if property.name == "next_status_effect_on_expire" and (property.get("value", &"") != &""):
		# You could add more robust validation here, e.g., checking if the resource actually exists
		# However, checking ResourceLoader.exists() in _validate_property can be slow for many resources.
		pass
