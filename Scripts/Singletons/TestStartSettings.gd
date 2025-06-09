# TestStartSettings.gd
# This script acts as a temporary data holder between scenes.
extends Node

var _chosen_basic_class: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE
var _chosen_weapon_id: StringName = &""
var _settings_were_applied_this_run: bool = false

func set_test_start_conditions(basic_class: PlayerCharacter.BasicClass, weapon_id: String):
	_chosen_basic_class = basic_class
	_chosen_weapon_id = weapon_id
	_settings_were_applied_this_run = false 
	print("DEBUG (TestStartSettings): Conditions set - Chosen Class Enum: ", _chosen_basic_class, " (Name: ", PlayerCharacter.BasicClass.keys()[_chosen_basic_class], "), Chosen Weapon ID: '", weapon_id, "'")

func get_chosen_basic_class() -> PlayerCharacter.BasicClass:
	print("DEBUG (TestStartSettings): get_chosen_basic_class() returning: ", _chosen_basic_class)
	return _chosen_basic_class

func get_chosen_weapon_id() -> String:
	print("DEBUG (TestStartSettings): get_chosen_weapon_id() returning: '", _chosen_weapon_id, "'")
	return _chosen_weapon_id

func are_test_settings_available() -> bool:
	var available = (_chosen_basic_class != PlayerCharacter.BasicClass.NONE or not _chosen_weapon_id.is_empty())
	# print("DEBUG (TestStartSettings): are_test_settings_available() called. Result: ", available) # Can be spammy
	return available

func mark_settings_as_applied():
	print("DEBUG (TestStartSettings): mark_settings_as_applied() CALLED.")
	_settings_were_applied_this_run = true

func were_settings_applied_this_run() -> bool:
	# print("DEBUG (TestStartSettings): were_settings_applied_this_run() called. Result: ", test_settings_applied) # Can be spammy
	return _settings_were_applied_this_run

func reset_settings(): # Call this if you want to clear settings, e.g., on game over or returning to main menu
	_chosen_basic_class = PlayerCharacter.BasicClass.NONE
	_chosen_weapon_id = ""
	_settings_were_applied_this_run = false
	print("DEBUG (TestStartSettings): Settings reset.")
