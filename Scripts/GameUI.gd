# GameUI.gd
# Path: res://Scripts/GameUI.gd
# Manages HUD elements and calculates the Dynamic Difficulty Score (DDS).
# Added tunable parameters and setters for debug panel.
extends Control

signal difficulty_tier_increased(new_tier) 
signal dds_changed(new_dds_score)          
signal hardcore_phase_activated() 

# --- Node References ---
@onready var player_health_bar: ProgressBar = $HUDLayer/PlayerHealthBar
@onready var gameplay_timer_label: Label = $HUDLayer/GameplayTimerLabel
@onready var one_second_tick_timer: Timer = $HUDLayer/OneSecondTickTimer
@onready var temp_exp_bar: ProgressBar = $HUDLayer/TempExpBar
@onready var temp_exp_bar_visibility_timer: Timer = $HUDLayer/TempExpBarVisibilityTimer
@onready var dds_label: Label = $HUDLayer/DDSLabel 
@onready var culled_enemies_label: Label = $HUDLayer/CulledEnemiesLabel 
@onready var threat_pool_label: Label = $HUDLayer/ThreatPoolLabel

# --- Gameplay Timer & Legacy Difficulty Variables ---
var elapsed_seconds: int = 0
var current_difficulty_tier: int = 0
var next_difficulty_increase_time: int = 20
const DIFFICULTY_INTERVAL: int = 20 # Original interval for legacy tier
const MAX_DIFFICULTY_TIERS_FOR_SPAWN_RATE: int = 20 

# --- Player Reference ---
var player_node: PlayerCharacter

# --- UI Positioning Constants ---
const HEALTH_BAR_Y_OFFSET: float = -40.0
const HEALTH_BAR_X_OFFSET: float = -5.0
const EXP_BAR_Y_OFFSET_FROM_HEALTH: float = 3.0

# --- DDS Variables (Now Tunable) ---
var dynamic_difficulty_score: float = 0.0
var base_dds_per_30_sec_tick: float = 10.0
var dds_bonus_per_level_up: float = 5.0
var dds_bonus_rapid_level_up: float = 15.0 # Additional
var rapid_level_up_threshold_seconds: float = 20.0
var time_of_last_level_up: float = 0.0

# Store original defaults for reset
const ORIGINAL_BASE_DDS_PER_30_SEC_TICK: float = 10.0
const ORIGINAL_DDS_BONUS_PER_LEVEL_UP: float = 5.0
const ORIGINAL_DDS_BONUS_RAPID_LEVEL_UP: float = 15.0
const ORIGINAL_RAPID_LEVEL_UP_THRESHOLD_SECONDS: float = 20.0

# --- Hardcore Ramp Variables (Now Tunable) ---
const HARDCORE_MODE_START_SECONDS: int = 9000 # This remains const as it's a fixed game event time
var is_hardcore_phase: bool = false
var hardcore_dds_extra_per_second: float = 0.75
var hardcore_level_up_dds_multiplier: float = 1.5

const ORIGINAL_HARDCORE_DDS_EXTRA_PER_SECOND: float = 0.75
const ORIGINAL_HARDCORE_LEVEL_UP_DDS_MULTIPLIER: float = 1.5

func _ready():
	if player_health_bar:
		player_health_bar.visible = true; player_health_bar.max_value = 100; player_health_bar.value = 100
	else: print("ERROR (GameUI): PlayerHealthBar node not found.")
	if temp_exp_bar: temp_exp_bar.visible = false
	else: print("ERROR (GameUI): TempExpBar node not found.")
	if gameplay_timer_label: gameplay_timer_label.text = format_time(elapsed_seconds)
	else: print("ERROR (GameUI): GameplayTimerLabel node not found.")
	if dds_label: _update_dds_label()
	else: print("ERROR (GameUI): DDSLabel node not found.")
	if culled_enemies_label: update_culled_enemies_display(0)
	else: print("ERROR (GameUI): CulledEnemiesLabel node not found.")
	if threat_pool_label: update_threat_pool_display(0)
	else: print("ERROR (GameUI): ThreatPoolLabel node not found.")

	call_deferred("_attempt_player_connections")

	if one_second_tick_timer:
		if not one_second_tick_timer.is_connected("timeout", Callable(self, "_on_one_second_tick_timer_timeout")):
			one_second_tick_timer.timeout.connect(self._on_one_second_tick_timer_timeout)
		if one_second_tick_timer.is_stopped() and not one_second_tick_timer.autostart:
			one_second_tick_timer.start()
	else: print("ERROR (GameUI): OneSecondTickTimer node not found.")
		
	if temp_exp_bar_visibility_timer:
		if not temp_exp_bar_visibility_timer.is_connected("timeout", Callable(self, "_on_temp_exp_bar_visibility_timer_timeout")):
			temp_exp_bar_visibility_timer.timeout.connect(self._on_temp_exp_bar_visibility_timer_timeout)
	else: print("ERROR (GameUI): TempExpBarVisibilityTimer node not found.")
	
	emit_signal("dds_changed", dynamic_difficulty_score)

func _attempt_player_connections():
	await get_tree().process_frame 
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		player_node = players[0] as PlayerCharacter
		if is_instance_valid(player_node):
			if player_node.has_signal("health_changed"): player_node.health_changed.connect(self._on_player_health_changed)
			if player_node.has_signal("experience_changed"): player_node.experience_changed.connect(self._on_player_experience_changed)
			if player_node.has_signal("player_level_up"): player_node.player_level_up.connect(self._on_player_level_up_for_dds)
			time_of_last_level_up = elapsed_seconds
		else: print_debug("CRITICAL ERROR (GameUI): Player node became invalid during connection setup.")
	else: print_debug("CRITICAL ERROR (GameUI): Player node not found in group 'player_char_group'.")

func _process(delta: float): # UI Positioning Logic
	if not is_instance_valid(player_node) or not is_instance_valid(player_health_bar): return 
	var current_cam: Camera2D = get_viewport().get_camera_2d()
	if not is_instance_valid(current_cam) or not current_cam is Camera2D: return

	if player_node.has_method("get_ui_anchor_global_position"):
		var anchor_world_pos: Vector2 = player_node.get_ui_anchor_global_position()
		var anchor_screen_pos: Vector2 = Vector2.ZERO
		if current_cam.has_method("unproject_position"):
			anchor_screen_pos = current_cam.unproject_position(anchor_world_pos)
		elif current_cam.has_method("get_camera_transform"): 
			var camera_transform_val: Transform2D = current_cam.get_camera_transform() 
			var canvas_transform_val: Transform2D = get_viewport().get_canvas_transform()
			var combined_transform: Transform2D = canvas_transform_val * camera_transform_val
			anchor_screen_pos = combined_transform * anchor_world_pos
		else: anchor_screen_pos = get_viewport().get_visible_rect().size / 2.0
		
		var health_bar_pos_x = anchor_screen_pos.x - (player_health_bar.size.x / 2.0) + HEALTH_BAR_X_OFFSET
		var health_bar_pos_y = anchor_screen_pos.y + HEALTH_BAR_Y_OFFSET - player_health_bar.size.y 
		player_health_bar.global_position = Vector2(health_bar_pos_x, health_bar_pos_y)
		if is_instance_valid(temp_exp_bar) and temp_exp_bar.visible:
			var exp_bar_pos_x = anchor_screen_pos.x - (temp_exp_bar.size.x / 2.0) + HEALTH_BAR_X_OFFSET
			var exp_bar_pos_y = player_health_bar.global_position.y + player_health_bar.size.y + EXP_BAR_Y_OFFSET_FROM_HEALTH
			temp_exp_bar.global_position = Vector2(exp_bar_pos_x, exp_bar_pos_y)

func _on_one_second_tick_timer_timeout():
	elapsed_seconds += 1
	if gameplay_timer_label: gameplay_timer_label.text = format_time(elapsed_seconds)
	var dds_increment_this_tick: float = 0.0
	if elapsed_seconds > 0 and elapsed_seconds % 20 == 0:
		dds_increment_this_tick += base_dds_per_30_sec_tick # Use variable
	if not is_hardcore_phase and elapsed_seconds >= HARDCORE_MODE_START_SECONDS:
		is_hardcore_phase = true
		print_debug("GAMEUI: HARDCORE PHASE ACTIVATED!")
		emit_signal("hardcore_phase_activated")
	if is_hardcore_phase:
		dds_increment_this_tick += hardcore_dds_extra_per_second # Use variable
	if dds_increment_this_tick > 0.0:
		dynamic_difficulty_score += dds_increment_this_tick
		emit_signal("dds_changed", dynamic_difficulty_score)
		_update_dds_label()
	if current_difficulty_tier < MAX_DIFFICULTY_TIERS_FOR_SPAWN_RATE:
		if elapsed_seconds >= next_difficulty_increase_time:
			current_difficulty_tier += 1
			next_difficulty_increase_time += DIFFICULTY_INTERVAL
			emit_signal("difficulty_tier_increased", current_difficulty_tier)

func _on_player_level_up_for_dds(_new_level: int):
	if not is_instance_valid(player_node): return
	var dds_bonus_this_level: float = dds_bonus_per_level_up # Use variable
	var time_since_last = elapsed_seconds - time_of_last_level_up
	if time_of_last_level_up > 0 and time_since_last < rapid_level_up_threshold_seconds: # Use variable
		dds_bonus_this_level += dds_bonus_rapid_level_up # Use variable
	if is_hardcore_phase:
		dds_bonus_this_level *= hardcore_level_up_dds_multiplier # Use variable
	dynamic_difficulty_score += dds_bonus_this_level
	time_of_last_level_up = elapsed_seconds
	emit_signal("dds_changed", dynamic_difficulty_score)
	_update_dds_label()

func _update_dds_label():
	if is_instance_valid(dds_label):
		dds_label.text = "DDS: %d" % [round(dynamic_difficulty_score)]

func update_culled_enemies_display(count: int):
	if is_instance_valid(culled_enemies_label):
		culled_enemies_label.text = "Active Enemies: %d" % [count]

func update_threat_pool_display(threat_level: int):
	if is_instance_valid(threat_pool_label):
		threat_pool_label.text = "Threat Pool: %d" % [threat_level]

# --- Public Methods for DebugPanel to Manipulate DDS ---
func set_dds_value(new_value: float):
	dynamic_difficulty_score = max(0.0, new_value)
	_update_dds_label(); emit_signal("dds_changed", dynamic_difficulty_score)
	print_debug("GameUI DEBUG: DDS manually set to: ", dynamic_difficulty_score)

func adjust_dds_value(amount: float):
	dynamic_difficulty_score = max(0.0, dynamic_difficulty_score + amount)
	_update_dds_label(); emit_signal("dds_changed", dynamic_difficulty_score)
	print_debug("GameUI DEBUG: DDS adjusted by: ", amount, ". New DDS: ", dynamic_difficulty_score)

# --- NEW: Debug Setters for DDS Parameters ---
func debug_set_base_dds_per_30_sec_tick(value: float):
	base_dds_per_30_sec_tick = max(0.0, value)
	print_debug("GameUI DEBUG: base_dds_per_30_sec_tick set to: ", base_dds_per_30_sec_tick)
func debug_set_dds_bonus_per_level_up(value: float):
	dds_bonus_per_level_up = max(0.0, value)
	print_debug("GameUI DEBUG: dds_bonus_per_level_up set to: ", dds_bonus_per_level_up)
func debug_set_dds_bonus_rapid_level_up(value: float):
	dds_bonus_rapid_level_up = max(0.0, value)
	print_debug("GameUI DEBUG: dds_bonus_rapid_level_up set to: ", dds_bonus_rapid_level_up)
func debug_set_rapid_level_up_threshold_seconds(value: float):
	rapid_level_up_threshold_seconds = max(1.0, value) # Must be at least 1s
	print_debug("GameUI DEBUG: rapid_level_up_threshold_seconds set to: ", rapid_level_up_threshold_seconds)
func debug_set_hardcore_dds_extra_per_second(value: float):
	hardcore_dds_extra_per_second = max(0.0, value)
	print_debug("GameUI DEBUG: hardcore_dds_extra_per_second set to: ", hardcore_dds_extra_per_second)
func debug_set_hardcore_level_up_dds_multiplier(value: float):
	hardcore_level_up_dds_multiplier = max(0.0, value)
	print_debug("GameUI DEBUG: hardcore_level_up_dds_multiplier set to: ", hardcore_level_up_dds_multiplier)

func debug_reset_dds_parameters_to_defaults():
	base_dds_per_30_sec_tick = ORIGINAL_BASE_DDS_PER_30_SEC_TICK
	dds_bonus_per_level_up = ORIGINAL_DDS_BONUS_PER_LEVEL_UP
	dds_bonus_rapid_level_up = ORIGINAL_DDS_BONUS_RAPID_LEVEL_UP
	rapid_level_up_threshold_seconds = ORIGINAL_RAPID_LEVEL_UP_THRESHOLD_SECONDS
	hardcore_dds_extra_per_second = ORIGINAL_HARDCORE_DDS_EXTRA_PER_SECOND
	hardcore_level_up_dds_multiplier = ORIGINAL_HARDCORE_LEVEL_UP_DDS_MULTIPLIER
	print_debug("GameUI DEBUG: All DDS calculation parameters reset to defaults.")
	# Optionally, re-emit dds_changed if you want game.gd to immediately react to reset values
	# emit_signal("dds_changed", dynamic_difficulty_score) 


# --- Existing Getters and UI Update Functions ---
func _on_player_health_changed(new_health: int, max_health_val: int):
	if player_health_bar:
		player_health_bar.max_value = max(1, max_health_val); player_health_bar.value = new_health
		player_health_bar.visible = (new_health > 0)
func _on_player_experience_changed(current_exp: int, exp_to_next: int, _player_level: int):
	if temp_exp_bar:
		if exp_to_next > 0: temp_exp_bar.max_value = exp_to_next; temp_exp_bar.value = current_exp
		else: temp_exp_bar.max_value = 1; temp_exp_bar.value = 1     
		if not temp_exp_bar.visible or (is_instance_valid(temp_exp_bar_visibility_timer) and temp_exp_bar_visibility_timer.is_stopped()):
			temp_exp_bar.visible = true 
			if is_instance_valid(temp_exp_bar_visibility_timer): temp_exp_bar_visibility_timer.start()
func _on_temp_exp_bar_visibility_timer_timeout():
	if temp_exp_bar: temp_exp_bar.visible = false
func format_time(total_seconds: int) -> String:
	var hours: int = total_seconds / 3600; var minutes: int = (total_seconds % 3600) / 60
	var seconds: int = total_seconds % 60; return "%02d:%02d:%02d" % [hours, minutes, seconds]
func get_elapsed_seconds() -> int: return elapsed_seconds
func get_current_difficulty_tier() -> int: return current_difficulty_tier
func get_dynamic_difficulty_score() -> float: return dynamic_difficulty_score
func is_in_hardcore_phase() -> bool: return is_hardcore_phase
