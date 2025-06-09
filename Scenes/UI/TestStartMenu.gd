# TestStartMenu.gd
# Attach this script to the root Control node of your TestStartMenu.tscn scene.
# This script handles the UI for selecting a starting class and weapon for testing.
# It uses the TestStartSettings Autoload to pass selections to the main game scene.

extends Control

# --- Node References (Ensure these paths match your TestStartMenu.tscn structure) ---
@onready var class_option_button: OptionButton = $MarginContainer/VBoxContainer/ClassOptionButton
@onready var weapon_option_button: OptionButton = $MarginContainer/VBoxContainer/WeaponOptionButton
@onready var start_game_button: Button = $MarginContainer/VBoxContainer/StartGameButton

# --- Data ---
# Dictionary mapping BasicClass enums to arrays of weapon dictionaries.
# Each weapon dictionary defines its 'id' (StringName) and 'title'.
var class_weapon_options: Dictionary = {
	PlayerCharacter.BasicClass.WARRIOR: [
		{"id": &"warrior_scythe", "title": "Scythe"}, # Use StringName for IDs
		{"id": &"warrior_crossbow", "title": "Crossbow"},
	],
	PlayerCharacter.BasicClass.KNIGHT: [
		{"id": &"knight_longsword", "title": "Longsword"},
		{"id": &"knight_shield_bash", "title": "Shield Bash"},
	],
	PlayerCharacter.BasicClass.ROGUE: [
		{"id": &"rogue_shortbow", "title": "Shortbow"},
		{"id": &"rogue_dagger_strike", "title": "Dagger Strike"},
	],
	PlayerCharacter.BasicClass.WIZARD: [
		{"id": &"wizard_spark", "title": "Spark"},
		{"id": &"wizard_frozen_territory", "title": "Frozen Territory"},
	],
	PlayerCharacter.BasicClass.DRUID: [
		{"id": &"druid_vine_whip", "title": "Vine Whip"},
		{"id": &"druid_torrent", "title": "Torrent"},
	],
	PlayerCharacter.BasicClass.CONJURER: [
		{"id": &"conjurer_lesser_spirit", "title": "Lesser Spirit"},
		{"id": &"conjurer_moth_golem", "title": "Moth Golem"},
	]
}

var selected_class_enum_val: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE
var selected_weapon_id: StringName = &"" # Changed to StringName

const MAIN_GAME_SCENE_PATH = "res://Scenes/game.tscn" # ADJUST THIS PATH if needed


func _ready():
	# Validate @onready node references.
	if not class_option_button or not weapon_option_button or not start_game_button:
		push_error("ERROR (TestStartMenu): UI nodes not found. Check paths in scene.")
		return

	_populate_class_options() # Populate the class selection dropdown

	# Connect signals for UI interaction.
	if not class_option_button.is_connected("item_selected", Callable(self, "_on_class_option_button_item_selected")):
		class_option_button.item_selected.connect(self._on_class_option_button_item_selected)
	else:
		push_warning("TestStartMenu: class_option_button signal already connected.")
	
	if not weapon_option_button.is_connected("item_selected", Callable(self, "_on_weapon_option_button_item_selected")):
		weapon_option_button.item_selected.connect(self._on_weapon_option_button_item_selected)
	else:
		push_warning("TestStartMenu: weapon_option_button signal already connected.")

	if not start_game_button.is_connected("pressed", Callable(self, "_on_start_game_button_pressed")):
		start_game_button.pressed.connect(self._on_start_game_button_pressed)
	else:
		push_warning("TestStartMenu: start_game_button signal already connected.")
	
	# Select the first available actual class by default.
	if class_option_button.get_item_count() > 0:
		var initial_selection_index = 0
		# If "None" is the first item and there's more than one option, select the second (first actual class).
		if class_option_button.get_item_id(0) == PlayerCharacter.BasicClass.NONE and class_option_button.get_item_count() > 1:
			initial_selection_index = 1
		
		class_option_button.select(initial_selection_index)
		# Manually trigger the selection callback to populate weapon options for the default class.
		_on_class_option_button_item_selected(initial_selection_index)


# Populates the class selection OptionButton.
func _populate_class_options():
	if not class_option_button: return
	class_option_button.clear()
	
	# Iterate through PlayerCharacter.BasicClass enum keys and add them to the OptionButton.
	var basic_class_keys = PlayerCharacter.BasicClass.keys()
	for i in range(basic_class_keys.size()):
		var class_name_str = basic_class_keys[i]
		var class_enum_val_int = PlayerCharacter.BasicClass.values()[i]
		
		# Skip adding "NONE" as a selectable class item if it exists in the enum.
		if class_enum_val_int == PlayerCharacter.BasicClass.NONE:
			continue
			
		class_option_button.add_item(class_name_str.capitalize(), class_enum_val_int)


# Called when a class is selected from the OptionButton.
func _on_class_option_button_item_selected(index: int):
	if not class_option_button or not weapon_option_button: return
	
	selected_class_enum_val = class_option_button.get_item_id(index) as PlayerCharacter.BasicClass
	# print("DEBUG (TestStartMenu): Class selected - Index: ", index, " Enum Value: ", selected_class_enum_val, " (Name: ", PlayerCharacter.BasicClass.keys()[selected_class_enum_val], ")")
	
	weapon_option_button.clear() # Clear previous weapon options
	selected_weapon_id = &"" # Reset selected weapon ID
	
	# Populate weapon options based on the selected class.
	if class_weapon_options.has(selected_class_enum_val) and not class_weapon_options[selected_class_enum_val].is_empty():
		var weapons_for_class = class_weapon_options[selected_class_enum_val]
		weapon_option_button.disabled = false
		for i in range(weapons_for_class.size()):
			var weapon_info = weapons_for_class[i]
			# Add weapon item using its title and its index in the array as item_id.
			# We'll use this item_id (index) to retrieve the actual weapon_info.id later.
			weapon_option_button.add_item(weapon_info.title, i)
		
		if weapon_option_button.get_item_count() > 0:
			weapon_option_button.select(0) # Select the first weapon by default
			_on_weapon_option_button_item_selected(0) # Trigger its selection callback
	else:
		# If no weapons defined for class, disable weapon selection.
		weapon_option_button.add_item("No Weapons Defined", -1) # Add a placeholder
		weapon_option_button.disabled = true
		selected_weapon_id = &"" # Ensure weapon ID is empty if no weapons are available


# Called when a weapon is selected from the OptionButton.
func _on_weapon_option_button_item_selected(index: int):
	if not weapon_option_button: return
	
	# Guard against invalid index (e.g., "No Weapons Defined" selected).
	if index < 0 or index >= weapon_option_button.get_item_count():
		selected_weapon_id = &""
		return

	# The item_id of the OptionButton holds the *index* within the class_weapon_options array.
	var index_in_weapon_list = weapon_option_button.get_item_id(index)
	
	if class_weapon_options.has(selected_class_enum_val):
		var weapons_for_class = class_weapon_options[selected_class_enum_val]
		if index_in_weapon_list >= 0 and index_in_weapon_list < weapons_for_class.size():
			selected_weapon_id = weapons_for_class[index_in_weapon_list].id # Get the actual weapon ID (StringName)
			# print("DEBUG (TestStartMenu): Weapon selected - Weapon ID: '", selected_weapon_id, "'")
		else:
			selected_weapon_id = &"" # Should not happen if lists are populated correctly
	else:
		selected_weapon_id = &"" # No class selected or class has no weapons


# Called when the "Start Game" button is pressed.
func _on_start_game_button_pressed():
	# Auto-select first weapon if a class is chosen but no weapon is explicitly picked.
	if selected_class_enum_val != PlayerCharacter.BasicClass.NONE and \
	   class_weapon_options.has(selected_class_enum_val) and \
	   not class_weapon_options[selected_class_enum_val].is_empty() and \
	   selected_weapon_id.is_empty():
		
		if weapon_option_button.get_item_count() > 0 and weapon_option_button.get_item_id(0) != -1 :
			weapon_option_button.select(0)
			# Manually call the selection handler to ensure selected_weapon_id is set.
			_on_weapon_option_button_item_selected(0)
		else:
			push_warning("TestStartMenu: Class selected but no valid weapon to auto-select. Game might start with no weapon.")
	
	# Pass the selected class and weapon ID to the TestStartSettings Autoload.
	# This ensures the main game scene knows which conditions to use for initialization.
	TestStartSettings.set_test_start_conditions(selected_class_enum_val, selected_weapon_id)
	
	# Change to the main game scene.
	var error = get_tree().change_scene_to_file(MAIN_GAME_SCENE_PATH)
	if error != OK:
		push_error("ERROR (TestStartMenu): Failed to change scene to '", MAIN_GAME_SCENE_PATH, "'. Error code: ", error)
