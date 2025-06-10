# stat_modification_effect_data.gd
# This resource defines a numerical modification to a player stat.
# It uses standardized stat keys from the 'PlayerStatKeys' Autoload.
#
# This script should be saved as 'res://Scripts/DataResources/Effects/StatModificationEffectData.gd'
# (or its equivalent path in your project structure).

extends EffectData
class_name StatModificationEffectData

# Define an enum for the type of value, ensuring flexibility for integer or float stats.
enum ValueType {
	INT,    # For integer-based stats like ARMOR, LUCK, NUMERICAL_DAMAGE
	FLOAT   # For float-based stats like MOVEMENT_SPEED, CRIT_CHANCE, MULTIPLIERS
}

@export var id: StringName = &""
# The type of modification to apply to the stat.
# This should be set in the Inspector using StringName literals like &"flat_add".
@export var modification_type: StringName = &"flat_add" # e.g., &"flat_add", &"percent_add_to_base", &"percent_mult_final", &"override_value"

# The stat key to be modified. This *must* be one of the StringNames defined in PlayerStatKeys.KEY_NAMES.
# When creating .tres files, you will manually type the StringName (e.g., &"max_health") here.
# In a more advanced setup, this could be made into a dropdown in a custom editor plugin.
@export var stat_key: StringName = &"" # e.g., &"max_health", &"movement_speed", &"numerical_damage"

# Export two separate value fields, one for integers and one for floats,
# controlled by the 'value_type' enum.
# Removed @export_enum as it's automatically handled when the type is an enum.
@export var value_type: ValueType = ValueType.FLOAT # Specify if the value is int or float
@export_range(-99999.0, 99999.0, 0.01) var value_float: float = 0.0
@export_range(-99999, 99999) var value_int: int = 0


# Called when the resource is initialized.
func _init():
	# Set the unique identifier for this type of effect data.
	# This helps PlayerStats.gd or WeaponManager.gd identify how to process it.
	effect_type_id = &"stat_mod"


# Helper function to retrieve the value based on its specified type.
# PlayerStats.gd will call this method to get the correct numerical value.
func get_value():
	if value_type == ValueType.INT:
		return value_int
	else:
		return value_float


# Optional: Add a validation method for use in the editor.
# This method runs when the resource is saved or modified in the editor,
# providing warnings if the stat_key isn't recognized.
func _validate_property(property: Dictionary):
	# Check if the property being validated is 'stat_key'.
	if property.name == "stat_key":
		var current_value = property.get("value", &"") # Get the value currently entered for stat_key.

		# Ensure that the PlayerStatKeys Autoload is available.
		# This check prevents errors if the Autoload isn't set up yet.
		if Engine.has_singleton("PlayerStatKeys"):
			# Check if the entered stat_key exists in our standardized list of keys.
			if not PlayerStatKeys.KEY_NAMES.values().has(current_value):
				# If it doesn't exist, push a warning to the editor's output.
				push_warning("StatModificationEffectData: 'stat_key' (", current_value, ") is not a recognized key in PlayerStatKeys.KEY_NAMES. Please check for typos.")
		else:
			# If the Autoload isn't found, warn the user to set it up.
			push_warning("StatModificationEffectData: PlayerStatKeys Autoload not found. Stat key validation is skipped. Please ensure 'PlayerStatKeys.gd' is added as an Autoload with the name 'PlayerStatKeys' in Project Settings.")
