# TestStartMenu.gd (Refactored)
# This script is now fully data-driven. It dynamically populates the class
# and weapon options by loading WeaponBlueprintData resources directly,
# eliminating the need for hardcoded dictionaries.
# FIX: Now includes "None" as a selectable class for class-agnostic weapons.

extends Control

# --- Node References ---
@onready var class_option_button: OptionButton = $MarginContainer/VBoxContainer/ClassOptionButton
@onready var weapon_option_button: OptionButton = $MarginContainer/VBoxContainer/WeaponOptionButton
@onready var start_game_button: Button = $MarginContainer/VBoxContainer/StartGameButton

# --- Data Loading ---
# This list should mirror the one in game.gd. This is the only place you
# need to add new weapon blueprint paths.
@export var weapon_blueprint_files: Array[String] = [
	"res://DataResources/Weapons/Scythe/warrior_scythe_blueprint.tres",
	"res://DataResources/Weapons/Crossbow/warrior_crossbow_blueprint.tres",
	"res://DataResources/Weapons/Longsword/knight_longsword_blueprint.tres",
	"res://DataResources/Weapons/ShieldBash/knight_shield_bash_blueprint.tres",
	"res://DataResources/Weapons/Shortbow/rogue_shortbow_blueprint.tres",
	"res://DataResources/Weapons/DaggerStrike/rogue_dagger_strike_blueprint.tres",
	"res://DataResources/Weapons/Spark/wizard_spark_blueprint.tres",
	"res://DataResources/Weapons/FrozenTerritory/wizard_frozen_territory_blueprint.tres",
	"res://DataResources/Weapons/VineWhip/druid_vine_whip_blueprint.tres",
	"res://DataResources/Weapons/Torrent/druid_torrent_blueprint.tres",
	"res://DataResources/Weapons/LesserSpirit/conjurer_lesser_spirit_blueprint.tres",
	"res://DataResources/Weapons/MothGolem/conjurer_moth_golem_blueprint.tres",
	# Warhammer and future weapons are added here.
	"res://DataResources/Weapons/Warhammer/champion_warhammer_blueprint.tres",
	"res://DataResources/Weapons/Katana/samurai_katana_blueprint.tres",
	"res://DataResources/Weapons/SwordCoil/spellsword_sword_coil_blueprint.tres",
	"res://DataResources/Weapons/Throwing Axe/berserker_throwing_axe_blueprint.tres",
	"res://DataResources/Weapons/Shuriken/shuriken_blueprint.tres",
	"res://DataResources/Weapons/Polearm/sentinel_polearm_blueprint.tres",
	"res://DataResources/Weapons/Living Conduit/living_conduit_blueprint.tres",
	"res://DataResources/Weapons/Bramble Censer/bramble_censer_blueprint.tres",
	"res://DataResources/Weapons/Reinforcements/mechamaster_reinforcements_blueprint.tres",
	"res://DataResources/Weapons/ExperimentalMaterials/alchemist_experimental_materials_blueprint.tres",
	"res://DataResources/Weapons/SylvanChakram/sylvan_chakram_blueprint.tres",
	"res://DataResources/Weapons/LuringPrism/luring_prism_blueprint.tres",
	"res://DataResources/Weapons/ConjoinedSpirits/conjoined_spirit_blueprint.tres",
	"res://DataResources/Weapons/ReturnFromBeyond/return_from_beyond_blueprint.tres",
	"res://DataResources/Weapons/ChromaticAberration/chromatic_aberration_blueprint.tres"
]

var _all_loaded_blueprints: Array[WeaponBlueprintData] = []
var _current_class_weapons: Array[WeaponBlueprintData] = []

var selected_class_enum_val: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE
var selected_weapon_id: StringName = &""

const MAIN_GAME_SCENE_PATH = "res://Scenes/game.tscn"

func _ready():
	_load_all_weapon_blueprints()
	_populate_class_options()

	class_option_button.item_selected.connect(_on_class_option_button_item_selected)
	weapon_option_button.item_selected.connect(_on_weapon_option_button_item_selected)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	
	# Select the first class and populate its weapons by default.
	if class_option_button.get_item_count() > 0:
		class_option_button.select(0)
		_on_class_option_button_item_selected(0)

# Loads all blueprint .tres files into memory.
func _load_all_weapon_blueprints():
	_all_loaded_blueprints.clear()
	for path in weapon_blueprint_files:
		var bp_res = load(path) as WeaponBlueprintData
		if is_instance_valid(bp_res):
			_all_loaded_blueprints.append(bp_res)
		else:
			push_error("TestStartMenu: Failed to load WeaponBlueprintData from path: ", path)

# Populates the class dropdown from the PlayerCharacter enum.
func _populate_class_options():
	class_option_button.clear()
	# Now includes the "NONE" class as a selectable option.
	for class_name_str in PlayerCharacter.BasicClass.keys():
		var class_enum_val = PlayerCharacter.BasicClass[class_name_str]
		# The check to skip NONE has been removed.
		class_option_button.add_item(class_name_str.capitalize(), class_enum_val)

# Called when a class is selected. It now filters the loaded blueprints.
func _on_class_option_button_item_selected(index: int):
	selected_class_enum_val = class_option_button.get_item_id(index)
	
	_current_class_weapons.clear()
	
	# If "None" is selected, find weapons with no class restrictions.
	if selected_class_enum_val == PlayerCharacter.BasicClass.NONE:
		for blueprint in _all_loaded_blueprints:
			if blueprint.class_tag_restrictions.is_empty():
				_current_class_weapons.append(blueprint)
	# Otherwise, find weapons that match the selected class.
	else:
		for blueprint in _all_loaded_blueprints:
			if blueprint.class_tag_restrictions.has(selected_class_enum_val):
				_current_class_weapons.append(blueprint)
			
	_populate_weapon_options()

# Populates the weapon dropdown based on the filtered list.
func _populate_weapon_options():
	weapon_option_button.clear()
	selected_weapon_id = &""
	
	if _current_class_weapons.is_empty():
		weapon_option_button.add_item("No Weapons for this Class", -1)
		weapon_option_button.disabled = true
	else:
		weapon_option_button.disabled = false
		for i in range(_current_class_weapons.size()):
			var blueprint = _current_class_weapons[i]
			weapon_option_button.add_item(blueprint.title, i)
		
		if weapon_option_button.get_item_count() > 0:
			weapon_option_button.select(0)
			_on_weapon_option_button_item_selected(0)

# Stores the ID of the selected weapon.
func _on_weapon_option_button_item_selected(index: int):
	if index >= 0 and index < _current_class_weapons.size():
		selected_weapon_id = _current_class_weapons[index].id
	else:
		selected_weapon_id = &""

# Starts the game with the selected settings.
func _on_start_game_button_pressed():
	# We only need to check if a valid weapon is selected. The class selection
	# dictates which weapons are available.
	if not selected_weapon_id.is_empty():
		TestStartSettings.set_test_start_conditions(selected_class_enum_val, selected_weapon_id)
		get_tree().change_scene_to_file(MAIN_GAME_SCENE_PATH)
	else:
		push_warning("TestStartMenu: Please select a class with available weapons.")
