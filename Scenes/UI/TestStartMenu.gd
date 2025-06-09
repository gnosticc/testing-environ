# TestStartMenu.gd
# Attach this script to the root Control node of your TestStartMenu.tscn scene.
extends Control

# --- Node References (Ensure these paths match your TestStartMenu.tscn structure) ---
@onready var class_option_button: OptionButton = $MarginContainer/VBoxContainer/ClassOptionButton
@onready var weapon_option_button: OptionButton = $MarginContainer/VBoxContainer/WeaponOptionButton
@onready var start_game_button: Button = $MarginContainer/VBoxContainer/StartGameButton

# --- Data ---
var class_weapon_options: Dictionary = {
	PlayerCharacter.BasicClass.WARRIOR: [
		{"id": "warrior_scythe", "title": "Scythe"},
		{"id": "warrior_crossbow", "title": "Crossbow"},
	],
	PlayerCharacter.BasicClass.KNIGHT: [ 
		{"id": "knight_longsword", "title": "Longsword"},
		{"id": "knight_shield_bash", "title": "Shield Bash"},
	],
	PlayerCharacter.BasicClass.ROGUE: [ 
		{"id": "rogue_shortbow", "title": "Shortbow"},
		{"id": "rogue_dagger_strike", "title": "Dagger Strike"},
	],
	PlayerCharacter.BasicClass.WIZARD: [
		{"id": "wizard_spark", "title": "Spark"},
		{"id": "wizard_frozen_territory", "title": "Frozen Territory"},
	],
	PlayerCharacter.BasicClass.DRUID: [ 
		{"id": "druid_vine_whip", "title": "Vine Whip"},
		{"id": "druid_torrent", "title": "Torrent"},
	],
	PlayerCharacter.BasicClass.CONJURER: [ # NEW
		{"id": "conjurer_lesser_spirit", "title": "Lesser Spirit"},
		{"id": "conjurer_moth_golem", "title": "Moth Golem"},
	]
}

var selected_class_enum_val: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE
var selected_weapon_id: String = ""

const MAIN_GAME_SCENE_PATH = "res://Scenes/game.tscn" # ADJUST THIS PATH if needed

func _ready():
	if not class_option_button or not weapon_option_button or not start_game_button:
		print("ERROR (TestStartMenu): UI nodes not found. Check paths.")
		return

	_populate_class_options()
	if not class_option_button.is_connected("item_selected", Callable(self, "_on_class_option_button_item_selected")):
		class_option_button.item_selected.connect(self._on_class_option_button_item_selected)
	
	if not weapon_option_button.is_connected("item_selected", Callable(self, "_on_weapon_option_button_item_selected")):
		weapon_option_button.item_selected.connect(self._on_weapon_option_button_item_selected)

	if not start_game_button.is_connected("pressed", Callable(self, "_on_start_game_button_pressed")):
		start_game_button.pressed.connect(self._on_start_game_button_pressed)
	
	# Select the first available actual class by default if "None" is the first item
	if class_option_button.get_item_count() > 0:
		var initial_selection_index = 0
		if class_option_button.get_item_id(0) == PlayerCharacter.BasicClass.NONE and class_option_button.get_item_count() > 1:
			initial_selection_index = 1 # Select the first actual class (e.g., Warrior)
		
		class_option_button.select(initial_selection_index)
		_on_class_option_button_item_selected(initial_selection_index) # Trigger weapon list update


func _populate_class_options():
	if not class_option_button: return
	class_option_button.clear()
	
	# Add "None" option first if you want a true default without a specific class
	# class_option_button.add_item("Default (No Specific Class)", PlayerCharacter.BasicClass.NONE) 

	var basic_class_keys = PlayerCharacter.BasicClass.keys()
	for i in range(basic_class_keys.size()):
		var class_name_str = basic_class_keys[i]
		var class_enum_val_int = PlayerCharacter.BasicClass.values()[i]
		
		if class_enum_val_int == PlayerCharacter.BasicClass.NONE: # Skip adding "NONE" as a selectable class here
			continue 
			
		class_option_button.add_item(class_name_str.capitalize(), class_enum_val_int)


func _on_class_option_button_item_selected(index: int):
	if not class_option_button or not weapon_option_button: return
	
	selected_class_enum_val = class_option_button.get_item_id(index) as PlayerCharacter.BasicClass
	# print("DEBUG (TestStartMenu): Class selected - Index: ", index, " Enum Value: ", selected_class_enum_val, " (Name: ", PlayerCharacter.BasicClass.keys()[selected_class_enum_val], ")")
	
	weapon_option_button.clear()
	selected_weapon_id = "" 
	
	if class_weapon_options.has(selected_class_enum_val) and not class_weapon_options[selected_class_enum_val].is_empty():
		var weapons_for_class = class_weapon_options[selected_class_enum_val]
		weapon_option_button.disabled = false
		for i in range(weapons_for_class.size()):
			var weapon_info = weapons_for_class[i]
			weapon_option_button.add_item(weapon_info.title, i) # Use weapon_info.id as metadata if needed later
		if weapon_option_button.get_item_count() > 0:
			weapon_option_button.select(0) 
			_on_weapon_option_button_item_selected(0) # Ensure first weapon is selected by default
	else:
		weapon_option_button.add_item("No Weapons Defined", -1) # -1 or some other invalid ID
		weapon_option_button.disabled = true


func _on_weapon_option_button_item_selected(index: int):
	if not weapon_option_button: return
	if index < 0 or index >= weapon_option_button.get_item_count(): # Guard against invalid index
		selected_weapon_id = ""
		return

	var item_id_in_optionbutton = weapon_option_button.get_item_id(index) # This is the index in the current list
	
	if class_weapon_options.has(selected_class_enum_val):
		var weapons_for_class = class_weapon_options[selected_class_enum_val]
		if item_id_in_optionbutton >= 0 and item_id_in_optionbutton < weapons_for_class.size():
			selected_weapon_id = weapons_for_class[item_id_in_optionbutton].id
			# print("DEBUG (TestStartMenu): Weapon selected - Weapon ID: '", selected_weapon_id, "'")
		else:
			selected_weapon_id = "" # Should not happen if list is populated correctly
	else:
		selected_weapon_id = ""


func _on_start_game_button_pressed():
	# Ensure a valid weapon is selected if a class with weapons is chosen
	if selected_class_enum_val != PlayerCharacter.BasicClass.NONE and \
	   class_weapon_options.has(selected_class_enum_val) and \
	   not class_weapon_options[selected_class_enum_val].is_empty() and \
	   selected_weapon_id.is_empty():
		
		if weapon_option_button.get_item_count() > 0 and weapon_option_button.get_item_id(0) != -1 :
			weapon_option_button.select(0) 
			_on_weapon_option_button_item_selected(0) 
	
	TestStartSettings.set_test_start_conditions(selected_class_enum_val, selected_weapon_id)
	
	var error = get_tree().change_scene_to_file(MAIN_GAME_SCENE_PATH)
	if error != OK:
		print("ERROR (TestStartMenu): Failed to change scene to '", MAIN_GAME_SCENE_PATH, "'. Error code: ", error)
