# TriggerAbilityEffectData.gd
# Path: res://Scripts/DataResources/Effects/TriggerAbilityEffectData.gd
# Extends EffectData to define triggering a specific, scripted ability.
# REMOVED target_scope as it's now inherited from EffectData.gd.
# Updated error reporting and added editor validation.

class_name TriggerAbilityEffectData
extends EffectData

## The unique name of the ability to trigger.
## The system processing this effect (e.g., WeaponManager, PlayerCharacter)
## will have a 'match' or 'if' statement to handle this ID.
## Examples: "fork_projectile", "trigger_explosion_on_hit", "activate_whirlwind"
@export var ability_id: StringName = &""

## A dictionary of parameters to pass to the ability.
## This allows a single ability to be configured in different ways.
## Example for a "fork_projectile" ability: {"count": 2, "angle_spread_degrees": 30}
@export var ability_params: Dictionary = {}


func _init():
	# Automatically set the effect_type_id for this specific subclass.
	effect_type_id = &"trigger_ability"
	# developer_note = "Triggers a named ability on the target scope, passing parameters."

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings if key properties are empty.
func _validate_property(property: Dictionary):
	if property.name == "ability_id" and (property.get("value", &"") == &""):
		push_warning("TriggerAbilityEffectData: 'ability_id' cannot be empty for resource: ", resource_path)
