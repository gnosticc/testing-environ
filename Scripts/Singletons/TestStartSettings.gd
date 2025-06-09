# TestStartSettings.gd
# This script acts as a temporary data holder between scenes,
# specifically for initial game conditions like chosen class and weapon.
# It should be set as an Autoload to persist across scene changes.

extends Node

var _chosen_basic_class: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE
# Changed _chosen_weapon_id to StringName directly for consistency
var _chosen_weapon_id: StringName = &""
var _settings_were_applied_this_run: bool = false

# Sets the initial test conditions for class and weapon.
func set_test_start_conditions(basic_class: PlayerCharacter.BasicClass, weapon_id: StringName):
	_chosen_basic_class = basic_class
	_chosen_weapon_id = weapon_id
	_settings_were_applied_this_run = false # Reset applied status for new run
	print("DEBUG (TestStartSettings): Conditions set - Chosen Class Enum: ", _chosen_basic_class, " (Name: ", PlayerCharacter.BasicClass.keys()[_chosen_basic_class], "), Chosen Weapon ID: '", weapon_id, "'")

# Returns the chosen basic class enum.
func get_chosen_basic_class() -> PlayerCharacter.BasicClass:
	print("DEBUG (TestStartSettings): get_chosen_basic_class() returning: ", _chosen_basic_class)
	return _chosen_basic_class

# Returns the chosen weapon ID.
# Changed return type to StringName for consistency with weapon IDs.
func get_chosen_weapon_id() -> StringName:
	print("DEBUG (TestStartSettings): get_chosen_weapon_id() returning: '", _chosen_weapon_id, "'")
	return _chosen_weapon_id

# Checks if any test settings have been set.
func are_test_settings_available() -> bool:
	var available = (_chosen_basic_class != PlayerCharacter.BasicClass.NONE or not _chosen_weapon_id.is_empty())
	# print("DEBUG (TestStartSettings): are_test_settings_available() called. Result: ", available) # Can be spammy
	return available

# Marks that the settings have been applied in the current game run.
func mark_settings_as_applied():
	print("DEBUG (TestStartSettings): mark_settings_as_applied() CALLED.")
	_settings_were_applied_this_run = true

# Checks if the settings were already applied in the current game run.
func were_settings_applied_this_run() -> bool:
	# print("DEBUG (TestStartSettings): were_settings_applied_this_run() called. Result: ", test_settings_applied) # Can be spammy
	return _settings_were_applied_this_run

# Resets all test settings to their default values.
func reset_settings():
	_chosen_basic_class = PlayerCharacter.BasicClass.NONE
	_chosen_weapon_id = &"" # Reset to empty StringName
	_settings_were_applied_this_run = false
	print("DEBUG (TestStartSettings): Settings reset.")
