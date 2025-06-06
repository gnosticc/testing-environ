# EffectData.gd
# Base resource for all game effects.
# Added target_scope to define where the effect should be applied.
class_name EffectData
extends Resource

## A unique identifier for the type of effect (e.g., "stat_mod", "set_flag", "apply_status").
## This is set by the _init() function of each subclass.
@export var effect_type_id: StringName = &""

## NEW: Defines the scope where the effect is applied.
## Examples: "player_stats", "weapon_specific_stats", "enemy_stats", "enemy_behavior".
## The system processing this effect will use this to target the correct component/dictionary.
@export var target_scope: StringName = &""

## Optional: A note for developers to understand the purpose of this specific effect resource.
@export_multiline var developer_note: String = ""


func _init():
	# Base class has no specific type ID. Subclasses should set this.
	effect_type_id = &"base_effect_data"
