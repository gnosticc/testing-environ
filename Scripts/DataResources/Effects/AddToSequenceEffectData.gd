# AddToSequenceEffectData.gd
# Path: res://Scripts/DataResources/Effects/AddToSequenceEffectData.gd
# A new type of effect that appends a Dictionary to an Array stat on a weapon.
# This is specifically designed for modifying attack sequences.

class_name AddToSequenceEffectData
extends EffectData

## The key of the Array in specific_stats to modify.
## For Dagger Strike, this will be &"attack_sequence".
@export var array_key: StringName = &""

## The Dictionary to append to the end of the array.
@export var dictionary_to_add: Dictionary = {}


func _init():
	# Automatically set the effect_type_id for this specific subclass.
	effect_type_id = &"add_to_sequence"
	target_scope = &"weapon_specific_stats"
	developer_note = "Appends the 'dictionary_to_add' to the Array specified by 'array_key' in the weapon's specific_stats."

# Optional: Add a validation method for use in the editor.
func _validate_property(property: Dictionary):
	if property.name == "array_key" and (property.get("value", &"") == &""):
		push_warning("AddToSequenceEffectData: 'array_key' cannot be empty for resource: ", resource_path)
