# StatusEffectApplicationData.gd
# Path: res://Scripts/DataResources/Effects/StatusEffectApplicationData.gd
# Extends EffectData to define how a specific status effect should be applied.
# This resource is used when an upgrade or ability grants the capability to apply a status.
class_name StatusEffectApplicationData
extends EffectData

## The resource path to the StatusEffectData.tres file that defines the actual status effect
## (e.g., "res://DataResources/StatusEffects/burn.tres").
@export_file("*.tres") var status_effect_resource_path: String = ""
# Alternatively, for direct linking in editor (but less flexible if status effect definitions change often):
# @export var status_effect_data: StatusEffectData = null

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
# @export var potency_params_override: Dictionary = {}


func _init():
	# Automatically set the effect_type_id for this specific subclass.
	effect_type_id = &"apply_status"
	# developer_note = "Defines the application parameters for a status effect."

# This resource primarily holds data. The logic to load the 'status_effect_resource_path',
# check 'application_chance', and then call 'StatusEffectComponent.apply_effect()' with
# the loaded StatusEffectData and any overrides will be in the system that processes
# an array of EffectData (e.g., in PlayerCharacter.gd for general upgrades, or
# in a weapon's attack script for weapon-specific status applications).

# Example of how a processing system might use this:
# func _try_apply_status_from_data(target_status_component: StatusEffectComponent, app_data: StatusEffectApplicationData, source_node: Node, weapon_stats: Dictionary):
# 	if not is_instance_valid(target_status_component) or not is_instance_valid(app_data):
# 		return
# 
# 	if randf() >= app_data.application_chance:
# 		return # Failed chance roll
# 
# 	if app_data.status_effect_resource_path.is_empty():
# 		print_debug("StatusEffectApplicationData: status_effect_resource_path is empty.")
# 		return
# 
# 	var status_effect_def = load(app_data.status_effect_resource_path) as StatusEffectData
# 	if not is_instance_valid(status_effect_def):
# 		print_debug("StatusEffectApplicationData: Failed to load StatusEffectData from path: ", app_data.status_effect_resource_path)
# 		return
# 
# 	# Here, you would pass the status_effect_def to the target's StatusEffectComponent.
# 	# The StatusEffectComponent.apply_effect() method would then need to be able
# 	# to handle potential duration_override and potency_override from app_data.
# 	# This might involve passing app_data itself or specific override values.
# 	
#   # Simplified example - actual apply_effect might take more args or a dictionary of overrides
# 	target_status_component.apply_effect(status_effect_def, source_node, weapon_stats, app_data.duration_override, app_data.potency_override)
# 
#   # Or, StatusEffectComponent.apply_effect could take the StatusEffectApplicationData directly:
#   # target_status_component.apply_effect_from_application_data(app_data, source_node, weapon_stats)
