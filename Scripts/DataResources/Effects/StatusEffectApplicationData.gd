# StatusEffectApplicationData.gd
# Path: res://Scripts/DataResources/Effects/StatusEffectApplicationData.gd
# Extends EffectData to define how a specific status effect should be applied.
# This resource is used when an upgrade or ability grants the capability to apply a status.
# Updated error reporting and added editor validation.

class_name StatusEffectApplicationData
extends EffectData

## The resource path to the StatusEffectData.tres file that defines the actual status effect
## (e.g., "res://DataResources/StatusEffects/burn.tres").
# COMMENT: Using @export_file is good for path validation, but Godot 4 also allows
# @export var status_effect_data: StatusEffectData = null for direct resource linking.
# The current approach (path string) is perfectly valid for your data-driven design.
@export_file("*.tres") var status_effect_resource_path: String = ""
# Alternatively, for direct linking in editor (but less flexible if status effect definitions change often):
# @export var status_effect_data: StatusEffectData = null # Removed as it's not the primary approach used
@export var id: StringName = &""
## The chance (0.0 to 1.0) that this status effect will be applied upon a successful trigger (e.g., on hit).
## A value of 1.0 means it always applies if triggered.
@export_range(0.0, 1.0, 0.01) var application_chance: float = 1.0

## Optional: Override the default duration of the status effect.
## If -1.0 (or less than 0), the duration from the StatusEffectData resource will be used.
@export var duration_override: float = -1.0

## Optional: Override or scale the potency/magnitude of the status effect.
## The interpretation of this value depends on the specific StatusEffectData being applied.
## For a DoT, it might be a damage multiplier. For a slow, a percentage point increase/decrease.
## If -1.0 (or a conventional 'no override' value), the base potency from StatusEffectData is used.
@export var potency_override: float = -1.0
# Potency could also be a dictionary for more complex overrides:
# @export var potency_params_override: Dictionary = {} # Kept commented out as it's not the current design


func _init():
	# Automatically set the effect_type_id for this specific subclass.
	effect_type_id = &"apply_status"
	# developer_note = "Defines the application parameters for a status effect."

# This resource primarily holds data. The logic to load the 'status_effect_resource_path',
# check 'application_chance', and then call 'StatusEffectComponent.apply_effect()' with
# the loaded StatusEffectData and any overrides will be in the system that processes
# an array of EffectData (e.g., in PlayerCharacter.gd for general upgrades, or
# in a weapon's attack script for weapon-specific status applications).

# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings if key properties are empty or paths are invalid.
func _validate_property(property: Dictionary):
	# Using StringName literals for property.name is slightly more efficient
	if property.name == &"status_effect_resource_path" and (property.get("value", "") == ""):
		push_warning("StatusEffectApplicationData: 'status_effect_resource_path' cannot be empty for resource: ", resource_path)
	elif property.name == &"status_effect_resource_path" and (property.get("value", "") != ""):
		var path = property.get("value", "")
		# Basic check if the path exists.
		if not ResourceLoader.exists(path):
			push_warning("StatusEffectApplicationData: Resource path '", path, "' does not exist for resource: ", resource_path)
		# OPTIONAL: More robust check to ensure it's specifically a StatusEffectData resource.
		# This can be slow if done frequently on many resources.
		# var loaded_res = load(path)
		# if is_instance_valid(loaded_res) and not loaded_res is StatusEffectData:
		#     push_warning("StatusEffectApplicationData: Resource at path '", path, "' is not a StatusEffectData for resource: ", resource_path)

# The example usage from original comments is removed as it's not part of the resource's code itself.
