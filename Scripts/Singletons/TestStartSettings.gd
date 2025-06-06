# TestStartSettings.gd
# This script should be set up as an Autoload singleton in your project.
# Name it (e.g., "TestStartSettings") in Project > Project Settings > Autoload.
extends Node

# Assuming PlayerCharacter is a class_name defined in player.gd
# If not, you'd use integers for class representation here and map them in TestStartMenu.gd

var chosen_basic_class: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE 
var chosen_weapon_id: String = "" 
var test_settings_applied: bool = false 

func set_test_start_conditions(basic_class: PlayerCharacter.BasicClass, weapon_id: String):
	chosen_basic_class = basic_class
	chosen_weapon_id = weapon_id
	test_settings_applied = false 
	print("DEBUG (TestStartSettings): Conditions set - Chosen Class Enum: ", chosen_basic_class, " (Name: ", PlayerCharacter.BasicClass.keys()[chosen_basic_class], "), Chosen Weapon ID: '", weapon_id, "'")

func get_chosen_basic_class() -> PlayerCharacter.BasicClass:
	print("DEBUG (TestStartSettings): get_chosen_basic_class() returning: ", chosen_basic_class)
	return chosen_basic_class

func get_chosen_weapon_id() -> String:
	print("DEBUG (TestStartSettings): get_chosen_weapon_id() returning: '", chosen_weapon_id, "'")
	return chosen_weapon_id

func are_test_settings_available() -> bool:
	var available = (chosen_basic_class != PlayerCharacter.BasicClass.NONE or not chosen_weapon_id.is_empty())
	# print("DEBUG (TestStartSettings): are_test_settings_available() called. Result: ", available) # Can be spammy
	return available

func mark_settings_as_applied():
	print("DEBUG (TestStartSettings): mark_settings_as_applied() CALLED.")
	test_settings_applied = true

func were_settings_applied_this_run() -> bool:
	# print("DEBUG (TestStartSettings): were_settings_applied_this_run() called. Result: ", test_settings_applied) # Can be spammy
	return test_settings_applied

func reset_settings(): # Call this if you want to clear settings, e.g., on game over or returning to main menu
	chosen_basic_class = PlayerCharacter.BasicClass.NONE
	chosen_weapon_id = ""
	test_settings_applied = false
	print("DEBUG (TestStartSettings): Settings reset.")
