# File: res/Scripts/DataResources/StatusEffects/StatusEffectData.gd
# MERGED: This version combines your comprehensive script with the new visual_effect_scene property.

class_name StatusEffectData
extends Resource

# NEW: Enum to define where the visual effect should anchor on the enemy.
enum VisualAnchor {
	ABOVE,   # Positions the effect above the enemy's sprite.
	CENTER,  # Positions the effect at the enemy's origin point.
	BELOW    # Positions the effect below the enemy's sprite.
}

## Unique identifier for this status effect.
@export var id: StringName = &""

## Display name for UI purposes.
@export var display_name: String = "Status Effect"

## Optional: Path to an icon texture for this status effect.
@export var icon: Texture2D = null

## Default duration of the status effect in seconds.
@export var duration: float = 5.0

## If true, this effect can stack multiple times on a target.
@export var is_stackable: bool = false

## How many times this status effect can stack on a single target.
@export var max_stacks: int = 1

## If true, re-applying the effect will refresh its duration.
@export var refresh_duration_on_reapply: bool = true

# NEW: This flag allows an effect to trigger a one-shot event upon expiration.
@export var has_effect_on_expire: bool = false

@export_group("Tick-Based Effects (for DoTs, HoTs, etc.)")
## Interval in seconds for tick-based effects.
@export var tick_interval: float = 0.0
## If true, the first tick happens immediately upon application.
@export var tick_on_application: bool = false

@export_group("Core Effects")
## An array of EffectData resources that are applied to the target.
@export var effects_while_active: Array[EffectData] = []

## Optional: StringName ID of another StatusEffectData to apply when this one expires.
@export var next_status_effect_on_expire: StringName = &""

@export_group("Visuals")
# Optional scene to instantiate when this status effect is applied.
@export var visual_effect_scene: PackedScene = null
# NEW: Choose where the visual effect should appear relative to the enemy sprite.
@export var visual_anchor_point: VisualAnchor = VisualAnchor.ABOVE
@export var visual_scale_multiplier: float = 1.0


func _init():
	pass

func _validate_property(property: Dictionary):
	if property.name == &"id" and (property.get("value", &"") == &""):
		push_warning("StatusEffectData: 'id' cannot be empty for resource: ", resource_path)
	
	if property.name == &"effects_while_active":
		var current_effects_array = property.get("value", [])
		for i in range(current_effects_array.size()):
			var effect = current_effects_array[i]
			if not is_instance_valid(effect):
				push_warning("StatusEffectData: Effect in 'effects_while_active' at index ", i, " is invalid (null).")
			elif not effect is EffectData:
				push_warning("StatusEffectData: Effect in 'effects_while_active' at index ", i, " is not an EffectData resource or its subclass (Class: %s)." % effect.get_class())
			elif effect is StatModificationEffectData:
				var stat_mod_effect = effect as StatModificationEffectData
				if not PlayerStatKeys.KEY_NAMES.values().has(stat_mod_effect.stat_key):
					push_warning("StatusEffectData: StatModificationEffectData in 'effects_while_active' at index ", i, 
								 " has an unrecognized 'stat_key': '", stat_mod_effect.stat_key, "'. Consider adding it to PlayerStatKeys.")
			elif effect is CustomFlagEffectData:
				var flag_effect = effect as CustomFlagEffectData
				if flag_effect.flag_key == &"":
					push_warning("StatusEffectData: CustomFlagEffectData in 'effects_while_active' at index ", i, 
								 " has an empty 'flag_key'.")

	if property.name == &"next_status_effect_on_expire" and (property.get("value", &"") != &""):
		pass # Validation logic can be expanded here if needed.
