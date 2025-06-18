# AddTagEffectData.gd
# Path: res://Scripts/DataResources/Effects/AddTagEffectData.gd
# A new type of effect that adds a specified StringName tag to a weapon's 'tags' array.
# This enhances modularity, allowing upgrades to dynamically change a weapon's category.

class_name AddTagEffectData
extends EffectData

## The tag to add to the weapon's tag list.
## Example: &"piercing", &"homing", &"elemental_fire"
@export var tag_to_add: StringName = &""


func _init():
	# Automatically set the effect_type_id for this specific subclass.
	effect_type_id = &"add_tag"
	# The target_scope for this effect should always be "weapon_behavior" or similar.
	target_scope = &"weapon_behavior"
	developer_note = "Adds the specified 'tag_to_add' to the weapon's 'tags' array."

# Optional: Add a validation method for use in the editor.
func _validate_property(property: Dictionary):
	if property.name == "tag_to_add" and (property.get("value", &"") == &""):
		push_warning("AddTagEffectData: 'tag_to_add' cannot be empty for resource: ", resource_path)
