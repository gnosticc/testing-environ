# EffectData.gd
# Base resource for all game effects.
# Added target_scope to define where the effect should be applied.
# Updated error reporting and added editor validation.

class_name EffectData
extends Resource

## A unique identifier for the type of effect (e.g., "stat_mod", "set_flag", "apply_status").
## This is set by the _init() function of each subclass.
@export var effect_type_id: StringName = &""

## Defines the scope where the effect is applied.
## Examples: "player_stats", "weapon_specific_stats", "enemy_stats", "enemy_behavior", "player_behavior".
## The system processing this effect will use this to target the correct component/dictionary.
@export var target_scope: StringName = &""

## Optional: A note for developers to understand the purpose of this specific effect resource.
@export_multiline var developer_note: String = ""


func _init():
	# Base class has no specific type ID. Subclasses should set this.
	effect_type_id = &"base_effect_data"

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings for common setup issues.
func _validate_property(property: Dictionary):
	# Validate 'target_scope'
	if property.name == "target_scope" and (property.get("value", &"") == &""):
		push_warning("EffectData: 'target_scope' cannot be empty for resource: ", resource_path)
	# You could add further validation here to check for a predefined list of valid target scopes.
