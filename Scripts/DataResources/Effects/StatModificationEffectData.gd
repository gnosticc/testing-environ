# StatModificationEffectData.gd
# Extends EffectData to define a modification to a numerical game statistic.
# Uses an enum to allow choosing between Int or Float values in the Inspector.
class_name StatModificationEffectData
extends EffectData

enum ValueType { FLOAT, INT }

@export var stat_key: StringName = &""
@export var modification_type: StringName = &"flat_add" 

@export_group("Value Settings")
@export var value_type: ValueType = ValueType.FLOAT

# Only edit the value that corresponds to the chosen value_type above.
@export var value_float: float = 0.0
@export var value_int: int = 0

# Helper function to get the correct value based on the chosen type
func get_value() -> Variant:
	if value_type == ValueType.INT:
		return value_int
	return value_float


func _init():
	effect_type_id = &"stat_mod"
