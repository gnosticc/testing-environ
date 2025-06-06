# CustomFlagEffectData.gd
# Path: res://Scripts/DataResources/Effects/CustomFlagEffectData.gd
# Extends EffectData to define setting a boolean flag.
# REMOVED target_scope as it's now inherited from EffectData.gd.
class_name CustomFlagEffectData
extends EffectData

## The name of the flag to set.
## Examples: "has_reaping_momentum", "applies_bleed", "is_stunned"
@export var flag_key: StringName = &""

## The boolean value to set the flag to.
@export var flag_value: bool = false


func _init():
	# Automatically set the effect_type_id for this specific subclass.
	effect_type_id = &"set_flag"
	# developer_note = "Sets a boolean flag to true or false within the target_scope."
