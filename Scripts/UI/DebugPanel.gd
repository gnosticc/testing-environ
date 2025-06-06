# DebugPanel.gd
# Corrected all signal connections to use Callable.
# Helper functions moved to class level.
# Corrected player_stats and weapon_manager references.
# Updated _update_weapon_list_display for WeaponBlueprintData and corrected enum check.
# Refined reference gathering and initialization logic.
# Corrected check in _on_apply_upgrade_button_pressed.
extends CanvasLayer

# --- Node References from Scene Tree ---
@onready var main_panel: Panel = $MainPanel
@onready var tab_container: TabContainer = $MainPanel/TabContainer

# --- References to Game World Nodes (Assigned via deferred function) ---
var player_node: PlayerCharacter
var weapon_manager_node 
var game_node: Node2D 
var game_ui_node: Control 
var player_stats_node: Node 

const DEBUG_TOGGLE_ACTION = "debug_panel_toggle" 

# --- UI Node References for dynamically created elements ---
# Info Tab
var dds_label: Label; var elapsed_time_label: Label; var hardcore_status_label: Label
var spawn_interval_label: Label; var target_enemy_count_label: Label
var active_enemy_count_label: Label; var threat_pool_label: Label
var active_pool_label: Label; var player_level_label: Label
var set_dds_line_edit: LineEdit; var set_dds_button: Button
var add_50_dds_button: Button; var sub_50_dds_button: Button
var add_200_dds_button: Button; var sub_200_dds_button: Button

# Weapons Tab
var weapons_tab_content_container: VBoxContainer 
var available_weapons_list: ItemList; var add_weapon_button: Button
var player_active_weapons_list: ItemList; var available_upgrades_list: ItemList  
var apply_upgrade_button: Button       

# Player Stats Tab
var player_stats_tab_content: VBoxContainer
var ps_max_health_edit: LineEdit; var ps_health_regen_edit: LineEdit
var ps_numerical_damage_edit: LineEdit; var ps_global_flat_damage_edit: LineEdit 
var ps_attack_speed_mult_edit: LineEdit; var ps_armor_edit: LineEdit
var ps_move_speed_edit: LineEdit; var ps_luck_edit: LineEdit 
var apply_player_stats_button: Button; var reset_player_stats_button: Button

# Enemy Spawner Tab UI Elements
var enemy_spawner_tab_content: VBoxContainer
var enemy_type_option_button: OptionButton
var elite_type_option_button: OptionButton
var enemy_spawn_count_spinbox: SpinBox
var spawn_enemy_button: Button
var spawn_near_player_checkbox: CheckBox

# Game Tuning Tab UI Elements
var game_tuning_tab_content: VBoxContainer
var gt_base_dds_tick_edit: LineEdit
var gt_dds_lvl_bonus_edit: LineEdit
var gt_dds_rapid_lvl_bonus_edit: LineEdit
var gt_rapid_lvl_thresh_edit: LineEdit
var gt_hc_dds_extra_sec_edit: LineEdit
var gt_hc_lvl_mult_edit: LineEdit
var gt_dds_spawn_factor_edit: LineEdit
var gt_hc_spawn_mult_edit: LineEdit
var gt_base_spawn_int_edit: LineEdit
var gt_min_spawn_int_edit: LineEdit
var gt_enemies_batch_edit: LineEdit
var gt_active_pool_refresh_edit: LineEdit
var gt_max_active_types_edit: LineEdit
var gt_enemy_count_update_dds_edit: LineEdit
var gt_threat_threshold_edit: LineEdit
var gt_threat_batch_mult_edit: LineEdit
var gt_culling_time_edit: LineEdit
var gt_event_interval_edit: LineEdit
var gt_fwd_spawn_bias_edit: LineEdit
var gt_spawn_margin_edit: LineEdit
var gt_override_target_enemies_check: CheckBox
var gt_target_enemies_override_val_edit: LineEdit
var apply_game_tuning_button: Button
var reset_game_tuning_button: Button

var is_initialized_and_ready: bool = false 
var ui_update_timer: Timer
const UI_UPDATE_INTERVAL: float = 0.25

# --- Helper function for Player Stats Tab ---
func _add_stat_editor_to_grid(p_grid: GridContainer, label_text: String, placeholder: String, stat_key: String, p_stats_node_ref: Node) -> LineEdit:
	p_grid.add_child(Label.new()) 
	var lbl = Label.new(); lbl.text = label_text; p_grid.add_child(lbl)
	var line_edit = LineEdit.new(); line_edit.name = "PSEdit" + stat_key.capitalize()
	line_edit.placeholder_text = placeholder
	if is_instance_valid(p_stats_node_ref):
		if p_stats_node_ref.has_method("get_base_" + stat_key + "_for_debug"):
			line_edit.text = str(p_stats_node_ref.call("get_base_" + stat_key + "_for_debug"))
		elif stat_key == "global_flat_damage_add" and p_stats_node_ref.has_method("get_current_global_flat_damage_add"):
			line_edit.text = str(p_stats_node_ref.get_current_global_flat_damage_add())
		else: line_edit.text = "N/A (mthd?)"
	else: line_edit.text = "N/A (no stats)"
	p_grid.add_child(line_edit); return line_edit

# --- Helper function for Player Stats Tab ---
func _update_line_edit_from_stat(le: LineEdit, method_name_base: String, p_stats_node_ref: Node, default_val_str: String = "N/A"):
	if is_instance_valid(le) and is_instance_valid(p_stats_node_ref):
		if p_stats_node_ref.has_method("get_base_" + method_name_base + "_for_debug"):
			le.text = str(p_stats_node_ref.call("get_base_" + method_name_base + "_for_debug"))
		elif method_name_base == "global_flat_damage_add" and p_stats_node_ref.has_method("get_current_global_flat_damage_add"):
			le.text = str(p_stats_node_ref.get_current_global_flat_damage_add())
		else: le.text = default_val_str + " (mthd?)"
	elif is_instance_valid(le): le.text = default_val_str + " (no stats)"

# --- Helper function for getting values from LineEdits (used by Player Stats & Game Tuning) ---
func _get_float_from_line_edit(le: LineEdit, p_target_node: Node, current_val_func_name_or_prop: String, is_property: bool = false) -> float:
	if is_instance_valid(le) and le.text.is_valid_float(): return float(le.text)
	elif is_instance_valid(p_target_node):
		if is_property and current_val_func_name_or_prop in p_target_node: return p_target_node.get(current_val_func_name_or_prop)
		elif not is_property and p_target_node.has_method(current_val_func_name_or_prop): return p_target_node.call(current_val_func_name_or_prop)
	return 0.0 
func _get_int_from_line_edit(le: LineEdit, p_target_node: Node, current_val_func_name_or_prop: String, is_property: bool = false) -> int:
	if is_instance_valid(le) and le.text.is_valid_int(): return int(le.text)
	elif is_instance_valid(p_target_node):
		if is_property and current_val_func_name_or_prop in p_target_node: return p_target_node.get(current_val_func_name_or_prop)
		elif not is_property and p_target_node.has_method(current_val_func_name_or_prop): return p_target_node.call(current_val_func_name_or_prop)
	return 0 

# --- Helper function for Game Tuning Tab ---
func _add_tuning_editor(p_grid: GridContainer, label_text: String, placeholder: String, param_key: String, target_node_ref: Node) -> LineEdit:
	p_grid.add_child(Label.new()) 
	var lbl = Label.new(); lbl.text = label_text; p_grid.add_child(lbl)
	var line_edit = LineEdit.new(); line_edit.name = "GTE" + param_key.capitalize() 
	line_edit.placeholder_text = placeholder
	if is_instance_valid(target_node_ref) and param_key in target_node_ref: 
		line_edit.text = str(target_node_ref.get(param_key))
	else: line_edit.text = "N/A"
	p_grid.add_child(line_edit)
	return line_edit

# --- Helper function for Game Tuning Tab ---
func _update_tuning_line_edit_from_property(le: LineEdit, target_node_ref: Node, param_name: String, default_val_str: String = "N/A"):
	if is_instance_valid(le) and is_instance_valid(target_node_ref) and param_name in target_node_ref:
		le.text = str(target_node_ref.get(param_name))
	elif is_instance_valid(le): le.text = default_val_str 

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	if not is_instance_valid(main_panel): print_debug("DebugPanel ERROR: MainPanel node not found!"); return
	main_panel.hide() 
	if not is_instance_valid(tab_container): 
		print_debug("DebugPanel ERROR: TabContainer node missing! Attempting to create.")
		if is_instance_valid(main_panel):
			tab_container = TabContainer.new(); tab_container.name = "TabContainer"
			main_panel.add_child(tab_container); tab_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		else: return 
	_setup_all_tabs() 
	ui_update_timer = Timer.new(); ui_update_timer.name = "DebugUIRefreshTimer"
	ui_update_timer.wait_time = UI_UPDATE_INTERVAL; ui_update_timer.one_shot = false
	ui_update_timer.timeout.connect(Callable(self, "_update_new_game_state_labels")) 
	add_child(ui_update_timer); ui_update_timer.start()
	call_deferred("_attempt_initial_reference_gathering_and_update") 
	_update_new_game_state_labels()

func _attempt_initial_reference_gathering_and_update():
	await get_tree().process_frame 
	await get_tree().process_frame 
	
	_get_all_game_world_references() 

	if _are_references_valid(): 
		is_initialized_and_ready = true
		print_debug("DebugPanel: All essential game references for weapon system successfully obtained.")
	else:
		is_initialized_and_ready = false 
		print_debug("DebugPanel: Initial references for weapon/upgrade system are NOT valid after defer. Weapon/Upgrade/Enemy Spawner/Game Tuning tabs may not function correctly.")
	
	_full_panel_content_update() 


func _get_all_game_world_references():
	print_debug("DebugPanel: _get_all_game_world_references called.")
	var tree_root = get_tree().root
	var game_node_path = "Game" 
	
	game_node = tree_root.get_node_or_null(game_node_path) as Node2D
	if not is_instance_valid(game_node): 
		print_debug("  DebugPanel ERROR: game_node not found at /root/", game_node_path, ". Ensure your main game scene is named 'Game' and is a direct child of /root.")
	elif not (game_node.has_method("get_all_weapon_blueprints_for_debug") and \
			  game_node.has_method("get_weapon_next_level_upgrades") and \
			  game_node.has_method("get_loaded_enemy_definitions_for_debug") and \
			  game_node.has_method("get_enemy_data_by_id_for_debug")):
		print_debug("  DebugPanel ERROR: game_node at '", game_node_path, "' is missing one or more required methods for debug panel.")
		game_node = null 
	
	if is_instance_valid(game_node): 
		game_ui_node = game_node.get_node_or_null("GameUI") as Control 
		if not is_instance_valid(game_ui_node): 
			print_debug("  DebugPanel ERROR: game_ui_node not found as child 'GameUI' of '", game_node_path, "'.")
	else: 
		var game_ui_node_abs_path = game_node_path + "/GameUI" 
		game_ui_node = tree_root.get_node_or_null(game_ui_node_abs_path) as Control 
		if not is_instance_valid(game_ui_node):
			print_debug("  DebugPanel ERROR: game_ui_node not found at absolute path /root/", game_ui_node_abs_path, " (game_node was also invalid).")

	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		player_node = players[0] as PlayerCharacter
		if is_instance_valid(player_node):
			print_debug("  DebugPanel: Player node found: ", player_node.name)
			if is_instance_valid(player_node.weapon_manager):
				weapon_manager_node = player_node.weapon_manager
				print_debug("    DebugPanel: WeaponManager found on player.")
			else:
				print_debug("  DebugPanel WARNING: player_node.weapon_manager is not valid.")
				weapon_manager_node = null
			
			if is_instance_valid(player_node.player_stats):
				player_stats_node = player_node.player_stats
				print_debug("    DebugPanel: PlayerStats (player_stats_node) found on player.")
			else:
				print_debug("  DebugPanel WARNING: player_node.player_stats is not valid.")
				player_stats_node = null
		else:
			print_debug("  DebugPanel WARNING: Node from 'player_char_group' is not a PlayerCharacter instance.")
			player_node = null; weapon_manager_node = null; player_stats_node = null
	else:
		print_debug("  DebugPanel WARNING: Player node not found in group 'player_char_group'.")
		player_node = null; weapon_manager_node = null; player_stats_node = null
	print_debug("DebugPanel: _get_all_game_world_references finished.")

func _full_panel_content_update(): 
	if not main_panel.visible: return

	_update_new_game_state_labels()
	
	if is_instance_valid(player_stats_node): 
		_update_player_stats_display_fields()
	
	if is_instance_valid(game_ui_node) and is_instance_valid(game_node):
		_update_game_tuning_display_fields()
	
	if is_initialized_and_ready: 
		_update_weapon_list_display() 
		_update_player_active_weapons_display() 
		_update_available_upgrades_display()
		_populate_enemy_spawn_list()
		if is_instance_valid(enemy_type_option_button) and enemy_type_option_button.item_count > 0:
			var current_selected_enemy_idx = enemy_type_option_button.selected
			if current_selected_enemy_idx < 0 or current_selected_enemy_idx >= enemy_type_option_button.item_count:
				current_selected_enemy_idx = 0 
			if enemy_type_option_button.item_count > 0: 
				_on_debug_enemy_type_selected(current_selected_enemy_idx)


func _update_new_game_state_labels(): 
	if not main_panel.visible: return
	if is_instance_valid(game_ui_node):
		if is_instance_valid(dds_label) and game_ui_node.has_method("get_dynamic_difficulty_score"): dds_label.text = "DDS: %.1f" % game_ui_node.get_dynamic_difficulty_score()
		if is_instance_valid(elapsed_time_label) and game_ui_node.has_method("get_elapsed_seconds") and game_ui_node.has_method("format_time"): elapsed_time_label.text = "Time: " + game_ui_node.format_time(game_ui_node.get_elapsed_seconds())
		if is_instance_valid(hardcore_status_label) and game_ui_node.has_method("is_in_hardcore_phase"): hardcore_status_label.text = "Hardcore: " + ("Yes" if game_ui_node.is_in_hardcore_phase() else "No")
	else: 
		if is_instance_valid(dds_label): dds_label.text = "DDS: (No GameUI)"
		if is_instance_valid(elapsed_time_label): elapsed_time_label.text = "Time: (No GameUI)"
		if is_instance_valid(hardcore_status_label): hardcore_status_label.text = "Hardcore: (No GameUI)"
	if is_instance_valid(game_node): 
		if is_instance_valid(spawn_interval_label) and "current_spawn_interval" in game_node: spawn_interval_label.text = "Spawn Int: %.2fs" % game_node.current_spawn_interval
		if is_instance_valid(target_enemy_count_label) and "target_on_screen_enemies" in game_node: target_enemy_count_label.text = "Target N: %d" % game_node.target_on_screen_enemies
		if is_instance_valid(active_enemy_count_label) and "current_active_enemy_count" in game_node: active_enemy_count_label.text = "Active N: %d" % game_node.current_active_enemy_count
		if is_instance_valid(threat_pool_label) and "global_unspent_threat_pool" in game_node: threat_pool_label.text = "Threat Pool: %d" % game_node.global_unspent_threat_pool
		if is_instance_valid(active_pool_label) and "current_active_enemy_pool" in game_node:
			var pool_ids: Array[StringName] = [];
			if game_node.current_active_enemy_pool is Array:
				for edi in game_node.current_active_enemy_pool: 
					if is_instance_valid(edi) and "id" in edi: pool_ids.append(edi.id)
			active_pool_label.text = "Active Pool (%d): " % pool_ids.size() + str(pool_ids)
	else: 
		if is_instance_valid(spawn_interval_label): spawn_interval_label.text = "Spawn Int: (No Game)"
		if is_instance_valid(target_enemy_count_label): target_enemy_count_label.text = "Target N: (No Game)"
		if is_instance_valid(active_enemy_count_label): active_enemy_count_label.text = "Active N: (No Game)"
		if is_instance_valid(threat_pool_label): threat_pool_label.text = "Threat Pool: (No Game)"
		if is_instance_valid(active_pool_label): active_pool_label.text = "Active Pool: (No Game)"
	if is_instance_valid(player_node) and "current_level" in player_node:
		if is_instance_valid(player_level_label): player_level_label.text = "Player Lvl: %d" % player_node.current_level
	elif is_instance_valid(player_level_label): player_level_label.text = "Player Lvl: (No Player)"

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed(DEBUG_TOGGLE_ACTION):
		if not main_panel: return 
		main_panel.visible = not main_panel.visible
		if main_panel.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE); get_tree().paused = true 
			call_deferred("_initialize_panel_on_open_fully") 
		else:
			get_tree().paused = false; Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) 
		get_viewport().set_input_as_handled() 

func _initialize_panel_on_open_fully(): 
	if not _are_all_world_nodes_valid(): 
		_get_all_game_world_references() 
	
	if _are_references_valid(): 
		is_initialized_and_ready = true 
	else: 
		is_initialized_and_ready = false

	if is_instance_valid(tab_container) and tab_container.get_tab_count() == 0 : 
		_setup_all_tabs() 
	
	_full_panel_content_update()


func _are_all_world_nodes_valid() -> bool: 
	return is_instance_valid(player_node) and \
		   is_instance_valid(player_stats_node) and \
		   is_instance_valid(weapon_manager_node) and \
		   is_instance_valid(game_node) and \
		   is_instance_valid(game_ui_node)

func _are_references_valid() -> bool: 
	var player_ok = is_instance_valid(player_node) and is_instance_valid(player_stats_node)
	var wm_ok = is_instance_valid(weapon_manager_node)
	var wm_method_ok = wm_ok and weapon_manager_node.has_method("add_weapon")
	var gn_ok = is_instance_valid(game_node)
	var gn_method1_ok = gn_ok and game_node.has_method("get_all_weapon_blueprints_for_debug")
	var gn_method2_ok = gn_ok and game_node.has_method("get_weapon_next_level_upgrades")
	var gn_method3_ok = gn_ok and game_node.has_method("get_loaded_enemy_definitions_for_debug")
	var gn_method4_ok = gn_ok and game_node.has_method("get_enemy_data_by_id_for_debug")
	
	var all_good = player_ok and wm_ok and wm_method_ok and gn_ok and gn_method1_ok and gn_method2_ok and gn_method3_ok and gn_method4_ok
	
	if not all_good and is_instance_valid(main_panel) and main_panel.visible: 
		print_debug("DebugPanel _are_references_valid (for weapon/enemy systems): FAILED. Details:")
		print_debug("  - Player Valid (and has player_stats): ", player_ok)
		print_debug("  - WeaponManager Valid: ", wm_ok, " (Has add_weapon: ", wm_method_ok, ")")
		print_debug("  - GameNode Valid: ", gn_ok)
		if gn_ok: 
			print_debug("    - GameNode Has get_all_weapon_blueprints_for_debug: ", gn_method1_ok)
			print_debug("    - GameNode Has get_weapon_next_level_upgrades: ", gn_method2_ok)
			print_debug("    - GameNode Has get_loaded_enemy_definitions_for_debug: ", gn_method3_ok)
			print_debug("    - GameNode Has get_enemy_data_by_id_for_debug: ", gn_method4_ok)
	return all_good

func _setup_all_tabs():
	if not is_instance_valid(tab_container): print_debug("DebugPanel ERROR: TabContainer is null."); return
	for i in range(tab_container.get_tab_count() - 1, -1, -1): 
		var child = tab_container.get_tab_control(i)
		if is_instance_valid(child): tab_container.remove_child(child); child.queue_free()
	_setup_info_tab() 
	_setup_player_stats_tab() 
	_setup_enemy_spawner_tab() 
	_setup_game_tuning_tab() 
	_setup_weapons_tab()      

func _setup_info_tab(): 
	var info_tab_content = VBoxContainer.new(); info_tab_content.name = "GameInfoVBox" 
	var grid = GridContainer.new(); grid.columns = 2; info_tab_content.add_child(grid)
	var lbl_title = Label.new(); lbl_title.text = "DDS:"; grid.add_child(lbl_title)
	dds_label = Label.new(); dds_label.name = "DDSLabel"; grid.add_child(dds_label)
	lbl_title = Label.new(); lbl_title.text = "Time:"; grid.add_child(lbl_title)
	elapsed_time_label = Label.new(); elapsed_time_label.name = "ElapsedTimeLabel"; grid.add_child(elapsed_time_label)
	lbl_title = Label.new(); lbl_title.text = "Hardcore:"; grid.add_child(lbl_title)
	hardcore_status_label = Label.new(); hardcore_status_label.name = "HardcoreStatusLabel"; grid.add_child(hardcore_status_label)
	lbl_title = Label.new(); lbl_title.text = "Spawn Int:"; grid.add_child(lbl_title)
	spawn_interval_label = Label.new(); spawn_interval_label.name = "SpawnIntervalLabel"; grid.add_child(spawn_interval_label)
	lbl_title = Label.new(); lbl_title.text = "Target N:"; grid.add_child(lbl_title)
	target_enemy_count_label = Label.new(); target_enemy_count_label.name = "TargetEnemyCountLabel"; grid.add_child(target_enemy_count_label)
	lbl_title = Label.new(); lbl_title.text = "Active N:"; grid.add_child(lbl_title)
	active_enemy_count_label = Label.new(); active_enemy_count_label.name = "ActiveEnemyCountLabel"; grid.add_child(active_enemy_count_label)
	lbl_title = Label.new(); lbl_title.text = "Threat Pool:"; grid.add_child(lbl_title)
	threat_pool_label = Label.new(); threat_pool_label.name = "ThreatPoolLabel"; grid.add_child(threat_pool_label)
	lbl_title = Label.new(); lbl_title.text = "Player Lvl:"; grid.add_child(lbl_title)
	player_level_label = Label.new(); player_level_label.name = "PlayerLevelLabel"; grid.add_child(player_level_label)
	var active_pool_hbox = HBoxContainer.new(); info_tab_content.add_child(active_pool_hbox) 
	lbl_title = Label.new(); lbl_title.text = "Active Pool:"; active_pool_hbox.add_child(lbl_title)
	active_pool_label = Label.new(); active_pool_label.name = "ActivePoolLabel"; active_pool_hbox.add_child(active_pool_label)
	active_pool_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	info_tab_content.add_child(HSeparator.new())
	var dds_control_hbox = HBoxContainer.new(); info_tab_content.add_child(dds_control_hbox)
	dds_control_hbox.add_child(Label.new()) 
	var set_dds_lbl = Label.new(); set_dds_lbl.text = "Set DDS:"; dds_control_hbox.add_child(set_dds_lbl)
	set_dds_line_edit = LineEdit.new(); set_dds_line_edit.name = "SetDDSLineEdit"; set_dds_line_edit.placeholder_text = "DDS Value"
	set_dds_line_edit.custom_minimum_size = Vector2(80, 0); dds_control_hbox.add_child(set_dds_line_edit)
	set_dds_button = Button.new(); set_dds_button.text = "Set"; dds_control_hbox.add_child(set_dds_button)
	set_dds_button.pressed.connect(Callable(self, "_on_set_dds_button_pressed"))
	var dds_adjust_hbox = HBoxContainer.new(); info_tab_content.add_child(dds_adjust_hbox)
	dds_adjust_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_50_dds_button = Button.new(); add_50_dds_button.text = "+50 DDS"; dds_adjust_hbox.add_child(add_50_dds_button)
	add_50_dds_button.pressed.connect(Callable(self, "_on_adjust_dds_button_pressed").bind(50.0))
	sub_50_dds_button = Button.new(); sub_50_dds_button.text = "-50 DDS"; dds_adjust_hbox.add_child(sub_50_dds_button)
	sub_50_dds_button.pressed.connect(Callable(self, "_on_adjust_dds_button_pressed").bind(-50.0))
	add_200_dds_button = Button.new(); add_200_dds_button.text = "+200 DDS"; dds_adjust_hbox.add_child(add_200_dds_button)
	add_200_dds_button.pressed.connect(Callable(self, "_on_adjust_dds_button_pressed").bind(200.0))
	sub_200_dds_button = Button.new(); sub_200_dds_button.text = "-200 DDS"; dds_adjust_hbox.add_child(sub_200_dds_button)
	sub_200_dds_button.pressed.connect(Callable(self, "_on_adjust_dds_button_pressed").bind(-200.0))
	if is_instance_valid(tab_container):
		tab_container.add_child(info_tab_content); tab_container.set_tab_title(tab_container.get_tab_count() - 1, "Game Info")

func _on_set_dds_button_pressed():
	if not is_instance_valid(game_ui_node) or not game_ui_node.has_method("set_dds_value"): return
	if is_instance_valid(set_dds_line_edit):
		var text_val = set_dds_line_edit.text
		if text_val.is_valid_float(): game_ui_node.set_dds_value(float(text_val)); set_dds_line_edit.text = ""
		else: print_debug("DebugPanel: Invalid DDS value entered: ", text_val)

func _on_adjust_dds_button_pressed(amount: float):
	if not is_instance_valid(game_ui_node) or not game_ui_node.has_method("adjust_dds_value"): return
	game_ui_node.adjust_dds_value(amount)

func _setup_player_stats_tab(): 
	player_stats_tab_content = VBoxContainer.new(); player_stats_tab_content.name = "PlayerStatsTabContent"
	var grid = GridContainer.new(); grid.columns = 2; player_stats_tab_content.add_child(grid)
	ps_max_health_edit = _add_stat_editor_to_grid(grid, "Base Max Health:", "e.g., 100", "max_health", player_stats_node)
	ps_health_regen_edit = _add_stat_editor_to_grid(grid, "Base Health Regen:", "e.g., 0.5", "health_regeneration", player_stats_node)
	ps_numerical_damage_edit = _add_stat_editor_to_grid(grid, "Base Numerical Dmg:", "e.g., 10", "numerical_damage", player_stats_node)
	ps_global_flat_damage_edit = _add_stat_editor_to_grid(grid, "Global Flat Dmg Add:", "e.g., 5", "global_flat_damage_add", player_stats_node)
	ps_attack_speed_mult_edit = _add_stat_editor_to_grid(grid, "Base Atk Speed Mult:", "e.g., 1.0", "attack_speed_multiplier", player_stats_node)
	ps_armor_edit = _add_stat_editor_to_grid(grid, "Base Armor:", "e.g., 0", "armor", player_stats_node)
	ps_move_speed_edit = _add_stat_editor_to_grid(grid, "Base Move Speed:", "e.g., 60", "movement_speed", player_stats_node)
	ps_luck_edit = _add_stat_editor_to_grid(grid, "Base Luck:", "e.g., 0", "luck", player_stats_node)
	var button_hbox = HBoxContainer.new(); button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	player_stats_tab_content.add_child(button_hbox)
	apply_player_stats_button = Button.new(); apply_player_stats_button.text = "Apply Player Stats"
	apply_player_stats_button.pressed.connect(Callable(self, "_on_apply_player_stats_button_pressed")) 
	button_hbox.add_child(apply_player_stats_button)
	reset_player_stats_button = Button.new(); reset_player_stats_button.text = "Reset to Class Defaults"
	reset_player_stats_button.pressed.connect(Callable(self, "_on_reset_player_stats_button_pressed")) 
	button_hbox.add_child(reset_player_stats_button)
	if is_instance_valid(tab_container): 
		tab_container.add_child(player_stats_tab_content)
		tab_container.set_tab_title(tab_container.get_tab_count() - 1, "Player Stats")

func _update_player_stats_display_fields(): 
	if not is_instance_valid(player_stats_node): return
	_update_line_edit_from_stat(ps_max_health_edit, "max_health", player_stats_node)
	_update_line_edit_from_stat(ps_health_regen_edit, "health_regeneration", player_stats_node)
	_update_line_edit_from_stat(ps_numerical_damage_edit, "numerical_damage", player_stats_node)
	_update_line_edit_from_stat(ps_global_flat_damage_edit, "global_flat_damage_add", player_stats_node)
	_update_line_edit_from_stat(ps_attack_speed_mult_edit, "attack_speed_multiplier", player_stats_node)
	_update_line_edit_from_stat(ps_armor_edit, "armor", player_stats_node)
	_update_line_edit_from_stat(ps_move_speed_edit, "movement_speed", player_stats_node)
	_update_line_edit_from_stat(ps_luck_edit, "luck", player_stats_node)

func _on_apply_player_stats_button_pressed(): 
	if not is_instance_valid(player_stats_node): print_debug("DebugPanel ERROR: PlayerStatsComponent not found."); return
	if player_stats_node.has_method("debug_set_base_max_health"): player_stats_node.debug_set_base_max_health(_get_int_from_line_edit(ps_max_health_edit, player_stats_node, "get_base_max_health_for_debug"))
	if player_stats_node.has_method("debug_set_base_health_regeneration"): player_stats_node.debug_set_base_health_regeneration(_get_float_from_line_edit(ps_health_regen_edit, player_stats_node, "get_base_health_regeneration_for_debug"))
	if player_stats_node.has_method("debug_set_base_numerical_damage"): player_stats_node.debug_set_base_numerical_damage(_get_int_from_line_edit(ps_numerical_damage_edit, player_stats_node, "get_base_numerical_damage_for_debug"))
	if player_stats_node.has_method("debug_set_current_global_flat_damage_add"): player_stats_node.debug_set_current_global_flat_damage_add(_get_int_from_line_edit(ps_global_flat_damage_edit, player_stats_node, "get_current_global_flat_damage_add"))
	if player_stats_node.has_method("debug_set_base_attack_speed_multiplier"): player_stats_node.debug_set_base_attack_speed_multiplier(_get_float_from_line_edit(ps_attack_speed_mult_edit, player_stats_node, "get_base_attack_speed_multiplier_for_debug"))
	if player_stats_node.has_method("debug_set_base_armor"): player_stats_node.debug_set_base_armor(_get_int_from_line_edit(ps_armor_edit, player_stats_node, "get_base_armor_for_debug"))
	if player_stats_node.has_method("debug_set_base_movement_speed"): player_stats_node.debug_set_base_movement_speed(_get_float_from_line_edit(ps_move_speed_edit, player_stats_node, "get_base_movement_speed_for_debug"))
	if player_stats_node.has_method("debug_set_base_luck"): player_stats_node.debug_set_base_luck(_get_int_from_line_edit(ps_luck_edit, player_stats_node, "get_base_luck_for_debug"))
	print_debug("DebugPanel: Applied player stat changes."); call_deferred("_update_player_stats_display_fields")

func _on_reset_player_stats_button_pressed(): 
	if not is_instance_valid(player_stats_node): print_debug("DebugPanel ERROR: PlayerStatsComponent not found."); return
	if is_instance_valid(player_stats_node) and player_stats_node.has_method("debug_reset_to_class_defaults"):
		player_stats_node.debug_reset_to_class_defaults(); print_debug("DebugPanel: Player stats reset."); call_deferred("_update_player_stats_display_fields")

# --- WEAPONS TAB ---
func _setup_weapons_tab():
	weapons_tab_content_container = VBoxContainer.new(); weapons_tab_content_container.name = "WeaponsTabContent"
	var available_bp_label = Label.new(); available_bp_label.text = "Available Blueprints:" 
	weapons_tab_content_container.add_child(available_bp_label) 
	available_weapons_list = ItemList.new(); available_weapons_list.name = "AvailableWeaponsList"
	available_weapons_list.select_mode = ItemList.SELECT_SINGLE; available_weapons_list.custom_minimum_size.y = 150
	available_weapons_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	weapons_tab_content_container.add_child(available_weapons_list)
	add_weapon_button = Button.new(); add_weapon_button.name = "AddWeaponButton"; add_weapon_button.text = "Add Selected Weapon to Player"
	add_weapon_button.pressed.connect(Callable(self, "_on_add_weapon_button_pressed")) 
	weapons_tab_content_container.add_child(add_weapon_button)
	weapons_tab_content_container.add_child(HSeparator.new())
	var active_wep_label = Label.new(); active_wep_label.text = "Player's Active Weapons:" 
	weapons_tab_content_container.add_child(active_wep_label) 
	player_active_weapons_list = ItemList.new(); player_active_weapons_list.name = "PlayerActiveWeaponsList"
	player_active_weapons_list.select_mode = ItemList.SELECT_SINGLE; player_active_weapons_list.custom_minimum_size.y = 100
	player_active_weapons_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_active_weapons_list.item_selected.connect(Callable(self, "_on_player_active_weapon_selected")) 
	weapons_tab_content_container.add_child(player_active_weapons_list)
	var available_upg_label = Label.new(); available_upg_label.text = "Available Upgrades for Selected:" 
	weapons_tab_content_container.add_child(available_upg_label) 
	available_upgrades_list = ItemList.new(); available_upgrades_list.name = "AvailableUpgradesList"
	available_upgrades_list.select_mode = ItemList.SELECT_SINGLE; available_upgrades_list.custom_minimum_size.y = 100
	available_upgrades_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	weapons_tab_content_container.add_child(available_upgrades_list)
	apply_upgrade_button = Button.new(); apply_upgrade_button.name = "ApplyUpgradeButton"; apply_upgrade_button.text = "Apply Selected Upgrade"
	apply_upgrade_button.pressed.connect(Callable(self, "_on_apply_upgrade_button_pressed")) 
	weapons_tab_content_container.add_child(apply_upgrade_button)
	if is_instance_valid(tab_container): 
		tab_container.add_child(weapons_tab_content_container)
		tab_container.set_tab_title(tab_container.get_tab_count() - 1, "Weapons")

func _update_weapon_list_display(): 
	if not is_instance_valid(game_node) or not game_node.has_method("get_all_weapon_blueprints_for_debug"):
		if is_instance_valid(available_weapons_list): available_weapons_list.clear(); available_weapons_list.add_item("GameNode error or missing method.")
		return
	if not is_instance_valid(available_weapons_list): return

	available_weapons_list.clear()
	var all_blueprints: Array[WeaponBlueprintData] = game_node.get_all_weapon_blueprints_for_debug() 
	
	if all_blueprints.is_empty(): 
		available_weapons_list.add_item("No weapon blueprints loaded.")
		return

	for weapon_bp_res in all_blueprints: 
		if not is_instance_valid(weapon_bp_res) or not weapon_bp_res is WeaponBlueprintData:
			print_debug("DebugPanel: Skipping invalid entry in weapon blueprints array.")
			continue
			
		var class_name_str = "N/A" 
		if not weapon_bp_res.class_tag_restrictions.is_empty():
			var enum_val = weapon_bp_res.class_tag_restrictions[0] 
			# Ensure PlayerCharacter and PlayerCharacter.BasicClass are valid before using
			if ClassDB.class_exists("PlayerCharacter") and "BasicClass" in PlayerCharacter:
				var basic_class_enum = PlayerCharacter.BasicClass
				if basic_class_enum.values().has(enum_val): # Corrected enum value check
					for key_name in basic_class_enum.keys():
						if basic_class_enum[key_name] == enum_val:
							class_name_str = key_name 
							break
				else:
					class_name_str = "Invalid_Enum_Val" # Value not in enum
			else:
				class_name_str = "PC_Enum_Err" # PlayerCharacter or its BasicClass enum not found
		elif weapon_bp_res.class_tag_restrictions.is_empty():
			class_name_str = "Any Class"

		var item_text = "%s - %s (ID: %s)" % [class_name_str, weapon_bp_res.title, weapon_bp_res.id]
		var idx = available_weapons_list.add_item(item_text)
		available_weapons_list.set_item_metadata(idx, weapon_bp_res) 

func _on_add_weapon_button_pressed():
	if not _are_references_valid() or not is_instance_valid(available_weapons_list): return
	var sel_indices = available_weapons_list.get_selected_items()
	if sel_indices.size() > 0:
		var bp_resource = available_weapons_list.get_item_metadata(sel_indices[0]) as WeaponBlueprintData 
		if is_instance_valid(bp_resource):
			if is_instance_valid(weapon_manager_node) and weapon_manager_node.has_method("add_weapon"):
				weapon_manager_node.add_weapon(bp_resource) 
				call_deferred("_update_player_active_weapons_display") 
				call_deferred("_update_available_upgrades_display") 
			else: print_debug("DebugPanel AddWeapon ERROR: weapon_manager_node invalid or missing add_weapon method.")
		else: print_debug("DebugPanel AddWeapon ERROR: Selected item metadata is not a valid WeaponBlueprintData.")
	
func _update_player_active_weapons_display():
	if not _are_references_valid() or not is_instance_valid(player_active_weapons_list): return
	player_active_weapons_list.clear()
	if not (is_instance_valid(weapon_manager_node) and weapon_manager_node.has_method("get_active_weapons_data_for_level_up")): 
		player_active_weapons_list.add_item("WeaponManager not ready or method missing."); return
	var active_weps_data_list: Array[Dictionary] = weapon_manager_node.get_active_weapons_data_for_level_up() 
	if active_weps_data_list.is_empty(): 
		player_active_weapons_list.add_item("No active weapons."); _update_available_upgrades_display(); return
	for wep_instance_data_dict in active_weps_data_list: 
		var weapon_id = wep_instance_data_dict.get("id", &"UNKNOWN_ID")
		var weapon_level = wep_instance_data_dict.get("weapon_level", 0)
		var weapon_title = str(weapon_id) 
		if is_instance_valid(game_node) and game_node.has_method("get_weapon_blueprint_by_id"):
			var bp_res = game_node.get_weapon_blueprint_by_id(weapon_id) as WeaponBlueprintData
			if is_instance_valid(bp_res): weapon_title = bp_res.title
		var item_text = "%s (Lvl %s)" % [weapon_title, weapon_level]
		var idx = player_active_weapons_list.add_item(item_text)
		player_active_weapons_list.set_item_metadata(idx, wep_instance_data_dict) 
	var selected_indices = player_active_weapons_list.get_selected_items()
	if selected_indices.is_empty(): _update_available_upgrades_display()
	else: _on_player_active_weapon_selected(selected_indices[0])

func _on_player_active_weapon_selected(_index: int):
	if not _are_references_valid() or not is_instance_valid(player_active_weapons_list): return
	var sel_indices = player_active_weapons_list.get_selected_items()
	if sel_indices.size() > 0:
		var selected_weapon_instance_data_dict = player_active_weapons_list.get_item_metadata(sel_indices[0]) as Dictionary
		if selected_weapon_instance_data_dict != null: 
			_update_available_upgrades_display(selected_weapon_instance_data_dict)
		else: _update_available_upgrades_display() 
	else: _update_available_upgrades_display() 

func _update_available_upgrades_display(selected_weapon_instance_data_dict: Dictionary = {}):
	if not _are_references_valid() or not is_instance_valid(available_upgrades_list): return
	available_upgrades_list.clear()
	if selected_weapon_instance_data_dict.is_empty() or not selected_weapon_instance_data_dict.has("id"):
		available_upgrades_list.add_item("Select an active weapon to see upgrades."); return
	var weapon_id_str = selected_weapon_instance_data_dict.get("id")
	if not is_instance_valid(game_node) or not game_node.has_method("get_weapon_next_level_upgrades"):
		available_upgrades_list.add_item("Game node error for upgrades."); return
	var next_upgrades_resources: Array[WeaponUpgradeData] = game_node.get_weapon_next_level_upgrades(weapon_id_str, selected_weapon_instance_data_dict)
	if next_upgrades_resources.is_empty():
		var weapon_bp = game_node.get_weapon_blueprint_by_id(StringName(weapon_id_str)) as WeaponBlueprintData
		var current_level = selected_weapon_instance_data_dict.get("weapon_level", 0)
		if is_instance_valid(weapon_bp) and current_level >= weapon_bp.max_level: available_upgrades_list.add_item("Max level reached.")
		else: available_upgrades_list.add_item("No valid upgrades for next level or prerequisites not met.")
		return
	for upgrade_data_res in next_upgrades_resources: 
		if not is_instance_valid(upgrade_data_res): continue
		var item_text = "%s: %s" % [upgrade_data_res.title, upgrade_data_res.description]
		var idx = available_upgrades_list.add_item(item_text)
		available_upgrades_list.set_item_metadata(idx, upgrade_data_res) 

func _on_apply_upgrade_button_pressed():
	if not _are_references_valid() or \
	   not is_instance_valid(player_active_weapons_list) or \
	   not is_instance_valid(available_upgrades_list): return
	var active_sel_indices = player_active_weapons_list.get_selected_items()
	var upgrade_sel_indices = available_upgrades_list.get_selected_items()
	if active_sel_indices.is_empty() or upgrade_sel_indices.is_empty():
		print_debug("DebugPanel ApplyUpgrade: Select an active weapon AND an upgrade to apply."); return
	
	var selected_weapon_instance_data_dict = player_active_weapons_list.get_item_metadata(active_sel_indices[0]) as Dictionary
	var selected_upgrade_resource = available_upgrades_list.get_item_metadata(upgrade_sel_indices[0]) as WeaponUpgradeData

	# Corrected check: A dictionary is not checked with is_instance_valid, check if it's null
	if selected_weapon_instance_data_dict == null or not is_instance_valid(selected_upgrade_resource):
		print_debug("ERROR (DebugPanel ApplyUpgrade): Invalid weapon (dict is null or metadata wrong) or upgrade resource selected.")
		return

	if is_instance_valid(player_node) and player_node.has_method("apply_upgrade"):
		var weapon_id_to_upgrade = selected_weapon_instance_data_dict.get("id") 
		var upgrade_application_data = { 
			"type": "weapon_upgrade", 
			"weapon_id_to_upgrade": weapon_id_to_upgrade, 
			"resource_data": selected_upgrade_resource 
		}
		player_node.apply_upgrade(upgrade_application_data) 
		
		call_deferred("_update_player_active_weapons_display") 
		var current_active_selection_indices = player_active_weapons_list.get_selected_items()
		if current_active_selection_indices.size() > 0:
			var updated_weapon_data = player_active_weapons_list.get_item_metadata(current_active_selection_indices[0])
			call_deferred("_update_available_upgrades_display", updated_weapon_data if updated_weapon_data is Dictionary else {})
		else:
			call_deferred("_update_available_upgrades_display") 
	else: print_debug("DebugPanel ApplyUpgrade ERROR: player_node invalid or missing apply_upgrade method.")


func _setup_enemy_spawner_tab(): 
	enemy_spawner_tab_content = VBoxContainer.new(); enemy_spawner_tab_content.name = "EnemySpawnerTabContent"
	var grid = GridContainer.new(); grid.columns = 2; enemy_spawner_tab_content.add_child(grid)
	grid.add_child(Label.new()) 
	var enemy_type_lbl = Label.new(); enemy_type_lbl.text = "Enemy Type:"; grid.add_child(enemy_type_lbl)
	enemy_type_option_button = OptionButton.new(); enemy_type_option_button.name = "EnemyTypeOption"
	enemy_type_option_button.item_selected.connect(Callable(self, "_on_debug_enemy_type_selected"))
	grid.add_child(enemy_type_option_button)
	grid.add_child(Label.new()) 
	var elite_type_lbl = Label.new(); elite_type_lbl.text = "Elite Type:"; grid.add_child(elite_type_lbl)
	elite_type_option_button = OptionButton.new(); elite_type_option_button.name = "EliteTypeOption"
	grid.add_child(elite_type_option_button)
	grid.add_child(Label.new()) 
	var count_lbl = Label.new(); count_lbl.text = "Count:"; grid.add_child(count_lbl)
	enemy_spawn_count_spinbox = SpinBox.new(); enemy_spawn_count_spinbox.name = "EnemySpawnCountSpinBox"
	enemy_spawn_count_spinbox.min_value = 1; enemy_spawn_count_spinbox.max_value = 50; enemy_spawn_count_spinbox.value = 1
	grid.add_child(enemy_spawn_count_spinbox)
	spawn_near_player_checkbox = CheckBox.new(); spawn_near_player_checkbox.name = "SpawnNearPlayerCheckbox"
	spawn_near_player_checkbox.text = "Spawn Near Player"; spawn_near_player_checkbox.button_pressed = true 
	enemy_spawner_tab_content.add_child(spawn_near_player_checkbox) 
	spawn_enemy_button = Button.new(); spawn_enemy_button.name = "SpawnEnemyButton"; spawn_enemy_button.text = "Spawn Enemy/Elite"
	spawn_enemy_button.pressed.connect(Callable(self, "_on_spawn_enemy_button_pressed"))
	enemy_spawner_tab_content.add_child(spawn_enemy_button)
	if is_instance_valid(tab_container): 
		tab_container.add_child(enemy_spawner_tab_content)
		tab_container.set_tab_title(tab_container.get_tab_count() - 1, "Enemy Spawner")
	if is_instance_valid(game_node): _populate_enemy_spawn_list()
	if is_instance_valid(enemy_type_option_button) and enemy_type_option_button.item_count > 0:
		_on_debug_enemy_type_selected(0) 

func _populate_enemy_spawn_list(): 
	if not is_instance_valid(game_node) or not game_node.has_method("get_loaded_enemy_definitions_for_debug"):
		if is_instance_valid(enemy_type_option_button): 
			enemy_type_option_button.clear()
			enemy_type_option_button.add_item("GameNode error for enemy defs.")
		return
	if not is_instance_valid(enemy_type_option_button): return
	enemy_type_option_button.clear()
	var enemy_defs: Array[EnemyData] = game_node.get_loaded_enemy_definitions_for_debug()
	if enemy_defs.is_empty(): enemy_type_option_button.add_item("No enemies loaded"); return
	for i in range(enemy_defs.size()):
		var enemy_data = enemy_defs[i]
		if is_instance_valid(enemy_data):
			var display_text = enemy_data.display_name if not enemy_data.display_name.is_empty() else str(enemy_data.id)
			enemy_type_option_button.add_item(display_text + " (ID: " + str(enemy_data.id) + ")", i)
			enemy_type_option_button.set_item_metadata(i, enemy_data.id)

func _on_debug_enemy_type_selected(index: int): 
	if not is_instance_valid(game_node) or \
	   not is_instance_valid(enemy_type_option_button) or \
	   not is_instance_valid(elite_type_option_button): return
	elite_type_option_button.clear()
	elite_type_option_button.add_item("None (Non-Elite)", 0) 
	elite_type_option_button.set_item_metadata(0, &"") 
	if index < 0 or index >= enemy_type_option_button.item_count: return
	var selected_enemy_id_raw = enemy_type_option_button.get_item_metadata(index)
	var selected_enemy_id: StringName = &""
	if typeof(selected_enemy_id_raw) == TYPE_STRING_NAME: selected_enemy_id = selected_enemy_id_raw
	elif typeof(selected_enemy_id_raw) == TYPE_STRING: selected_enemy_id = StringName(selected_enemy_id_raw)
	else: print_debug("DebugPanel ERROR: Invalid metadata type for selected enemy ID."); return
	var selected_enemy_data: EnemyData = null
	if game_node.has_method("get_enemy_data_by_id_for_debug"):
		selected_enemy_data = game_node.get_enemy_data_by_id_for_debug(selected_enemy_id)
	if is_instance_valid(selected_enemy_data) and not selected_enemy_data.elite_types_available.is_empty():
		for i in range(selected_enemy_data.elite_types_available.size()):
			var elite_tag: StringName = selected_enemy_data.elite_types_available[i]
			elite_type_option_button.add_item(str(elite_tag).capitalize(), i + 1) 
			elite_type_option_button.set_item_metadata(i + 1, elite_tag)

func _on_spawn_enemy_button_pressed(): 
	if not is_instance_valid(game_node) or not game_node.has_method("debug_spawn_specific_enemy"):
		print_debug("DebugPanel ERROR: game_node invalid or missing debug_spawn_specific_enemy method."); return
	if not is_instance_valid(enemy_type_option_button) or \
	   not is_instance_valid(elite_type_option_button) or \
	   not is_instance_valid(enemy_spawn_count_spinbox) or \
	   not is_instance_valid(spawn_near_player_checkbox):
		print_debug("DebugPanel ERROR: One or more UI elements for enemy spawner are invalid."); return
	var selected_enemy_idx = enemy_type_option_button.selected
	if selected_enemy_idx < 0: print_debug("DebugPanel: No enemy type selected."); return
	var enemy_id_raw = enemy_type_option_button.get_item_metadata(selected_enemy_idx)
	var enemy_id: StringName = &""
	if typeof(enemy_id_raw) == TYPE_STRING_NAME: enemy_id = enemy_id_raw
	elif typeof(enemy_id_raw) == TYPE_STRING: enemy_id = StringName(enemy_id_raw)
	else: print_debug("DebugPanel ERROR: Invalid metadata type for enemy ID."); return
	var elite_tag_override_raw = elite_type_option_button.get_item_metadata(elite_type_option_button.selected)
	var elite_tag_override: StringName = &""
	if typeof(elite_tag_override_raw) == TYPE_STRING_NAME: elite_tag_override = elite_tag_override_raw
	elif typeof(elite_tag_override_raw) == TYPE_STRING: elite_tag_override = StringName(elite_tag_override_raw)
	var count: int = int(enemy_spawn_count_spinbox.value)
	var near_player: bool = spawn_near_player_checkbox.button_pressed
	game_node.debug_spawn_specific_enemy(enemy_id, elite_tag_override, count, near_player)
	


# --- GAME TUNING TAB ---
func _setup_game_tuning_tab():
	game_tuning_tab_content = VBoxContainer.new(); game_tuning_tab_content.name = "GameTuningTabContent"
	game_tuning_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_tuning_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll_container = ScrollContainer.new() 
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_tuning_tab_content.add_child(scroll_container)
	var tuning_vbox = VBoxContainer.new() 
	tuning_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	scroll_container.add_child(tuning_vbox)
	tuning_vbox.add_child(Label.new()) 
	var gameui_params_label = Label.new(); gameui_params_label.text = "GameUI DDS Parameters:"; tuning_vbox.add_child(gameui_params_label)
	var gameui_grid = GridContainer.new(); gameui_grid.columns = 2; tuning_vbox.add_child(gameui_grid)
	gt_base_dds_tick_edit = _add_tuning_editor(gameui_grid, "Base DDS/30s:", "e.g., 10", "base_dds_per_30_sec_tick", game_ui_node)
	gt_dds_lvl_bonus_edit = _add_tuning_editor(gameui_grid, "DDS Lvl Bonus:", "e.g., 5", "dds_bonus_per_level_up", game_ui_node)
	gt_dds_rapid_lvl_bonus_edit = _add_tuning_editor(gameui_grid, "DDS Rapid Lvl Bonus:", "e.g., 15", "dds_bonus_rapid_level_up", game_ui_node)
	gt_rapid_lvl_thresh_edit = _add_tuning_editor(gameui_grid, "Rapid Lvl Threshold (s):", "e.g., 20", "rapid_level_up_threshold_seconds", game_ui_node)
	gt_hc_dds_extra_sec_edit = _add_tuning_editor(gameui_grid, "HC DDS Extra/sec:", "e.g., 0.75", "hardcore_dds_extra_per_second", game_ui_node)
	gt_hc_lvl_mult_edit = _add_tuning_editor(gameui_grid, "HC Lvl DDS Mult:", "e.g., 1.5", "hardcore_level_up_dds_multiplier", game_ui_node)
	tuning_vbox.add_child(HSeparator.new())
	var gamelogic_params_label = Label.new(); gamelogic_params_label.text = "GameLogic Spawn/Game Parameters:"; tuning_vbox.add_child(gamelogic_params_label)
	var gamelogic_grid = GridContainer.new(); gamelogic_grid.columns = 2; tuning_vbox.add_child(gamelogic_grid)
	gt_dds_spawn_factor_edit = _add_tuning_editor(gamelogic_grid, "DDS Spawn Factor:", "e.g., 0.002", "dds_spawn_rate_factor", game_node)
	gt_hc_spawn_mult_edit = _add_tuning_editor(gamelogic_grid, "HC Spawn Mult:", "e.g., 1.75", "hardcore_spawn_rate_multiplier", game_node)
	gt_base_spawn_int_edit = _add_tuning_editor(gamelogic_grid, "Base Spawn Int (s):", "e.g., 3.5", "base_spawn_interval", game_node)
	gt_min_spawn_int_edit = _add_tuning_editor(gamelogic_grid, "Min Spawn Int (s):", "e.g., 0.25", "min_spawn_interval", game_node)
	gt_enemies_batch_edit = _add_tuning_editor(gamelogic_grid, "Enemies/Batch:", "e.g., 3", "enemies_per_batch", game_node)
	gt_active_pool_refresh_edit = _add_tuning_editor(gamelogic_grid, "Active Pool Refresh DDS:", "e.g., 20", "active_pool_refresh_dds_interval", game_node)
	gt_max_active_types_edit = _add_tuning_editor(gamelogic_grid, "Max Active Types:", "e.g., 7", "max_active_enemy_types", game_node)
	gt_enemy_count_update_dds_edit = _add_tuning_editor(gamelogic_grid, "Enemy Count Update DDS:", "e.g., 35", "enemy_count_update_dds_interval", game_node)
	gt_threat_threshold_edit = _add_tuning_editor(gamelogic_grid, "Threat Threshold:", "e.g., 25", "threat_pool_spawn_threshold", game_node)
	gt_threat_batch_mult_edit = _add_tuning_editor(gamelogic_grid, "Threat Batch Mult:", "e.g., 1.5", "threat_pool_batch_multiplier", game_node)
	gt_culling_time_edit = _add_tuning_editor(gamelogic_grid, "Culling Time (s):", "e.g., 3.0", "culling_timer_wait_time", game_node)
	gt_event_interval_edit = _add_tuning_editor(gamelogic_grid, "Event Interval (s):", "e.g., 35", "random_event_check_interval", game_node)
	gt_fwd_spawn_bias_edit = _add_tuning_editor(gamelogic_grid, "Fwd Spawn Bias (0-1):", "e.g., 0.75", "forward_spawn_bias_chance", game_node)
	gt_spawn_margin_edit = _add_tuning_editor(gamelogic_grid, "Spawn Margin:", "e.g., 100", "spawn_margin", game_node)
	var override_hbox = HBoxContainer.new(); tuning_vbox.add_child(override_hbox)
	gt_override_target_enemies_check = CheckBox.new(); gt_override_target_enemies_check.text = "Override Target Enemies"
	gt_override_target_enemies_check.toggled.connect(Callable(self, "_on_override_target_enemies_toggled"))
	override_hbox.add_child(gt_override_target_enemies_check)
	gt_target_enemies_override_val_edit = LineEdit.new(); gt_target_enemies_override_val_edit.placeholder_text = "Count"
	gt_target_enemies_override_val_edit.custom_minimum_size.x = 60; override_hbox.add_child(gt_target_enemies_override_val_edit)
	gt_target_enemies_override_val_edit.visible = false
	tuning_vbox.add_child(HSeparator.new())
	var button_hbox_tuning = HBoxContainer.new(); button_hbox_tuning.alignment = BoxContainer.ALIGNMENT_CENTER
	tuning_vbox.add_child(button_hbox_tuning)
	apply_game_tuning_button = Button.new(); apply_game_tuning_button.text = "Apply Game Tuning"
	apply_game_tuning_button.pressed.connect(Callable(self, "_on_apply_game_tuning_button_pressed"))
	button_hbox_tuning.add_child(apply_game_tuning_button)
	reset_game_tuning_button = Button.new(); reset_game_tuning_button.text = "Reset Game Tuning to Defaults"
	reset_game_tuning_button.pressed.connect(Callable(self, "_on_reset_game_tuning_button_pressed"))
	button_hbox_tuning.add_child(reset_game_tuning_button)
	if is_instance_valid(tab_container):
		tab_container.add_child(game_tuning_tab_content)
		tab_container.set_tab_title(tab_container.get_tab_count() - 1, "Game Tuning")

func _update_game_tuning_display_fields():
	if not is_instance_valid(game_ui_node) or not is_instance_valid(game_node): return
	_update_tuning_line_edit_from_property(gt_base_dds_tick_edit, game_ui_node, "base_dds_per_30_sec_tick")
	_update_tuning_line_edit_from_property(gt_dds_lvl_bonus_edit, game_ui_node, "dds_bonus_per_level_up")
	_update_tuning_line_edit_from_property(gt_dds_rapid_lvl_bonus_edit, game_ui_node, "dds_bonus_rapid_level_up")
	_update_tuning_line_edit_from_property(gt_rapid_lvl_thresh_edit, game_ui_node, "rapid_level_up_threshold_seconds")
	_update_tuning_line_edit_from_property(gt_hc_dds_extra_sec_edit, game_ui_node, "hardcore_dds_extra_per_second")
	_update_tuning_line_edit_from_property(gt_hc_lvl_mult_edit, game_ui_node, "hardcore_level_up_dds_multiplier")
	_update_tuning_line_edit_from_property(gt_dds_spawn_factor_edit, game_node, "dds_spawn_rate_factor")
	_update_tuning_line_edit_from_property(gt_hc_spawn_mult_edit, game_node, "hardcore_spawn_rate_multiplier")
	_update_tuning_line_edit_from_property(gt_base_spawn_int_edit, game_node, "base_spawn_interval")
	_update_tuning_line_edit_from_property(gt_min_spawn_int_edit, game_node, "min_spawn_interval")
	_update_tuning_line_edit_from_property(gt_enemies_batch_edit, game_node, "enemies_per_batch")
	_update_tuning_line_edit_from_property(gt_active_pool_refresh_edit, game_node, "active_pool_refresh_dds_interval")
	_update_tuning_line_edit_from_property(gt_max_active_types_edit, game_node, "max_active_enemy_types")
	_update_tuning_line_edit_from_property(gt_enemy_count_update_dds_edit, game_node, "enemy_count_update_dds_interval")
	_update_tuning_line_edit_from_property(gt_threat_threshold_edit, game_node, "threat_pool_spawn_threshold")
	_update_tuning_line_edit_from_property(gt_threat_batch_mult_edit, game_node, "threat_pool_batch_multiplier")
	_update_tuning_line_edit_from_property(gt_culling_time_edit, game_node, "culling_timer_wait_time")
	_update_tuning_line_edit_from_property(gt_event_interval_edit, game_node, "random_event_check_interval")
	_update_tuning_line_edit_from_property(gt_fwd_spawn_bias_edit, game_node, "forward_spawn_bias_chance")
	_update_tuning_line_edit_from_property(gt_spawn_margin_edit, game_node, "spawn_margin")
	if is_instance_valid(gt_override_target_enemies_check) and is_instance_valid(game_node) and "debug_override_target_enemies" in game_node:
		gt_override_target_enemies_check.button_pressed = game_node.debug_override_target_enemies
	if is_instance_valid(gt_target_enemies_override_val_edit) and is_instance_valid(game_node) and "debug_target_enemies_value" in game_node:
		gt_target_enemies_override_val_edit.text = str(game_node.debug_target_enemies_value)
		gt_target_enemies_override_val_edit.visible = gt_override_target_enemies_check.button_pressed if is_instance_valid(gt_override_target_enemies_check) else false

func _on_override_target_enemies_toggled(toggled_on: bool):
	if is_instance_valid(gt_target_enemies_override_val_edit):
		gt_target_enemies_override_val_edit.visible = toggled_on
	if not toggled_on and is_instance_valid(game_node) and game_node.has_method("debug_set_target_on_screen_enemies_override"):
		game_node.debug_set_target_on_screen_enemies_override(false) 

func _on_apply_game_tuning_button_pressed():
	if not is_instance_valid(game_ui_node) or not is_instance_valid(game_node): print_debug("DebugPanel ERROR: GameUI or GameNode not valid for applying tuning."); return
	if game_ui_node.has_method("debug_set_base_dds_per_30_sec_tick"): game_ui_node.debug_set_base_dds_per_30_sec_tick(_get_float_from_line_edit(gt_base_dds_tick_edit, game_ui_node, "base_dds_per_30_sec_tick", true))
	if game_ui_node.has_method("debug_set_dds_bonus_per_level_up"): game_ui_node.debug_set_dds_bonus_per_level_up(_get_float_from_line_edit(gt_dds_lvl_bonus_edit, game_ui_node, "dds_bonus_per_level_up", true))
	if game_ui_node.has_method("debug_set_dds_bonus_rapid_level_up"): game_ui_node.debug_set_dds_bonus_rapid_level_up(_get_float_from_line_edit(gt_dds_rapid_lvl_bonus_edit, game_ui_node, "dds_bonus_rapid_level_up", true))
	if game_ui_node.has_method("debug_set_rapid_level_up_threshold_seconds"): game_ui_node.debug_set_rapid_level_up_threshold_seconds(_get_float_from_line_edit(gt_rapid_lvl_thresh_edit, game_ui_node, "rapid_level_up_threshold_seconds", true))
	if game_ui_node.has_method("debug_set_hardcore_dds_extra_per_second"): game_ui_node.debug_set_hardcore_dds_extra_per_second(_get_float_from_line_edit(gt_hc_dds_extra_sec_edit, game_ui_node, "hardcore_dds_extra_per_second", true))
	if game_ui_node.has_method("debug_set_hardcore_level_up_dds_multiplier"): game_ui_node.debug_set_hardcore_level_up_dds_multiplier(_get_float_from_line_edit(gt_hc_lvl_mult_edit, game_ui_node, "hardcore_level_up_dds_multiplier", true))
	if game_node.has_method("debug_set_dds_spawn_rate_factor"): game_node.debug_set_dds_spawn_rate_factor(_get_float_from_line_edit(gt_dds_spawn_factor_edit, game_node, "dds_spawn_rate_factor", true))
	if game_node.has_method("debug_set_hardcore_spawn_rate_multiplier"): game_node.debug_set_hardcore_spawn_rate_multiplier(_get_float_from_line_edit(gt_hc_spawn_mult_edit, game_node, "hardcore_spawn_rate_multiplier", true))
	if game_node.has_method("debug_set_base_spawn_interval"): game_node.debug_set_base_spawn_interval(_get_float_from_line_edit(gt_base_spawn_int_edit, game_node, "base_spawn_interval", true))
	if game_node.has_method("debug_set_min_spawn_interval"): game_node.debug_set_min_spawn_interval(_get_float_from_line_edit(gt_min_spawn_int_edit, game_node, "min_spawn_interval", true))
	if game_node.has_method("debug_set_enemies_per_batch"): game_node.debug_set_enemies_per_batch(_get_int_from_line_edit(gt_enemies_batch_edit, game_node, "enemies_per_batch", true))
	if game_node.has_method("debug_set_active_pool_refresh_dds_interval"): game_node.debug_set_active_pool_refresh_dds_interval(_get_float_from_line_edit(gt_active_pool_refresh_edit, game_node, "active_pool_refresh_dds_interval", true))
	if game_node.has_method("debug_set_max_active_enemy_types"): game_node.debug_set_max_active_enemy_types(_get_int_from_line_edit(gt_max_active_types_edit, game_node, "max_active_enemy_types", true))
	if game_node.has_method("debug_set_enemy_count_update_dds_interval"): game_node.debug_set_enemy_count_update_dds_interval(_get_float_from_line_edit(gt_enemy_count_update_dds_edit, game_node, "enemy_count_update_dds_interval", true))
	if game_node.has_method("debug_set_threat_pool_spawn_threshold"): game_node.debug_set_threat_pool_spawn_threshold(_get_int_from_line_edit(gt_threat_threshold_edit, game_node, "threat_pool_spawn_threshold", true))
	if game_node.has_method("debug_set_threat_pool_batch_multiplier"): game_node.debug_set_threat_pool_batch_multiplier(_get_float_from_line_edit(gt_threat_batch_mult_edit, game_node, "threat_pool_batch_multiplier", true))
	if game_node.has_method("debug_set_culling_timer_wait_time"): game_node.debug_set_culling_timer_wait_time(_get_float_from_line_edit(gt_culling_time_edit, game_node, "culling_timer_wait_time", true))
	if game_node.has_method("debug_set_random_event_check_interval"): game_node.debug_set_random_event_check_interval(_get_float_from_line_edit(gt_event_interval_edit, game_node, "random_event_check_interval", true))
	if game_node.has_method("debug_set_forward_spawn_bias_chance"): game_node.debug_set_forward_spawn_bias_chance(_get_float_from_line_edit(gt_fwd_spawn_bias_edit, game_node, "forward_spawn_bias_chance", true))
	if game_node.has_method("debug_set_spawn_margin"): game_node.debug_set_spawn_margin(_get_float_from_line_edit(gt_spawn_margin_edit, game_node, "spawn_margin", true))
	if is_instance_valid(gt_override_target_enemies_check) and game_node.has_method("debug_set_target_on_screen_enemies_override"):
		var override_enabled = gt_override_target_enemies_check.button_pressed; var override_value = -1
		if override_enabled and is_instance_valid(gt_target_enemies_override_val_edit) and gt_target_enemies_override_val_edit.text.is_valid_int():
			override_value = int(gt_target_enemies_override_val_edit.text)
		game_node.debug_set_target_on_screen_enemies_override(override_enabled, override_value)
	print_debug("DebugPanel: Applied Game Tuning parameters."); call_deferred("_update_game_tuning_display_fields") 

func _on_reset_game_tuning_button_pressed():
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("debug_reset_dds_parameters_to_defaults"):
		game_ui_node.debug_reset_dds_parameters_to_defaults()
	if is_instance_valid(game_node) and game_node.has_method("debug_reset_game_parameters_to_defaults"):
		game_node.debug_reset_game_parameters_to_defaults()
	print_debug("DebugPanel: Reset Game Tuning parameters to defaults."); call_deferred("_update_game_tuning_display_fields")
