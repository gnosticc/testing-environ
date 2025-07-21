# GameUI.gd
# Path: res://Scripts/GameUI.gd
# Manages HUD elements and calculates the Dynamic Difficulty Score (DDS).
# Added tunable parameters and setters for debug panel.
# Updated error reporting and consistency.
#
# FIXED: UI positioning logic for health/exp bars using correct world-to-canvas transform.
# ADDED: Extensive debug prints to _process to diagnose UI positioning issues.
# FIXED: Corrected Transform2D multiplication for Vector2.
# FIXED: Changed world-to-screen conversion to use Camera2D.get_viewport_position().

extends Control

signal difficulty_tier_increased(new_tier)
signal dds_changed(new_dds_score)
signal hardcore_phase_activated()

# --- Node References ---
@onready var player_health_bar: ProgressBar = $HUDLayer/PlayerHealthBar
@onready var temp_health_bar: ProgressBar = $HUDLayer/TempHealthBar # NEW: Reference for the temp health bar
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
var player_node: PlayerCharacter # Reference to the player character instance

# --- UI Positioning Constants ---
const HEALTH_BAR_Y_OFFSET: float = -40.0
const HEALTH_BAR_X_OFFSET: float = -5.0
const TEMP_HEALTH_BAR_Y_OFFSET: float = -7.0 # NEW: Small offset to stack above main bar
const EXP_BAR_Y_OFFSET_FROM_HEALTH: float = 3.0

# --- DDS Variables (Now Tunable) ---
var dynamic_difficulty_score: float = 0.0
@export var base_dds_per_30_sec_tick: float = 10.0
@export var dds_bonus_per_level_up: float = 5.0
@export var dds_bonus_rapid_level_up: float = 15.0 # Additional bonus for rapid level-ups
@export var rapid_level_up_threshold_seconds: float = 20.0 # Time threshold for rapid level-up bonus
var time_of_last_level_up: float = 0.0

# Store original defaults for reset
const ORIGINAL_BASE_DDS_PER_30_SEC_TICK: float = 10.0
const ORIGINAL_DDS_BONUS_PER_LEVEL_UP: float = 5.0
const ORIGINAL_DDS_BONUS_RAPID_LEVEL_UP: float = 15.0
const ORIGINAL_RAPID_LEVEL_UP_THRESHOLD_SECONDS: float = 20.0

# --- Hardcore Ramp Variables (Now Tunable) ---
const HARDCORE_MODE_START_SECONDS: int = 9000 # This remains const as it's a fixed game event time
var is_hardcore_phase: bool = false
@export var hardcore_dds_extra_per_second: float = 0.75 # Additional DDS gained per second in hardcore mode
@export var hardcore_level_up_dds_multiplier: float = 1.5 # Multiplier for level-up DDS bonus in hardcore mode

const ORIGINAL_HARDCORE_DDS_EXTRA_PER_SECOND: float = 0.75
const ORIGINAL_HARDCORE_LEVEL_UP_DDS_MULTIPLIER: float = 1.5

func _ready():
	# Initialize and check validity of all @onready node references.
	if player_health_bar:
		player_health_bar.visible = true
		player_health_bar.max_value = 100 # Initial max_value
		player_health_bar.value = 100 # Initial value
	else: push_error("GameUI: PlayerHealthBar node not found.")
	
	# --- NEW: Temporary Health Bar Setup ---
	if temp_health_bar:
		temp_health_bar.visible = false # Start hidden
		var temp_health_style = StyleBoxFlat.new()
		temp_health_style.bg_color = Color("#4a90e2") # A nice blue color
		temp_health_bar.add_theme_stylebox_override("fill", temp_health_style)
	else:
		push_error("GameUI: TempHealthBar node not found.")

	if temp_exp_bar: temp_exp_bar.visible = false
	else: push_error("GameUI: TempExpBar node not found.")

	if gameplay_timer_label: gameplay_timer_label.text = format_time(elapsed_seconds)
	else: push_error("GameUI: GameplayTimerLabel node not found.")

	if dds_label: _update_dds_label()
	else: push_error("GameUI: DDSLabel node not found.")

	if culled_enemies_label: update_culled_enemies_display(0)
	else: push_error("GameUI: CulledEnemiesLabel node not found.")

	if threat_pool_label: update_threat_pool_display(0)
	else: push_error("GameUI: ThreatPoolLabel node not found.")

	# Attempt to connect to the player node after a frame to ensure it's ready.
	call_deferred("_attempt_player_connections")

	# Setup one-second tick timer for gameplay clock and DDS calculation.
	if one_second_tick_timer:
		if not one_second_tick_timer.is_connected("timeout", Callable(self, "_on_one_second_tick_timer_timeout")):
			one_second_tick_timer.timeout.connect(self._on_one_second_tick_timer_timeout)
		if one_second_tick_timer.is_stopped() and not one_second_tick_timer.autostart: # Start if not autostarting
			one_second_tick_timer.start()
	else: push_error("GameUI: OneSecondTickTimer node not found.")
		
	if temp_exp_bar_visibility_timer:
		if not temp_exp_bar_visibility_timer.is_connected("timeout", Callable(self, "_on_temp_exp_bar_visibility_timer_timeout")):
			temp_exp_bar_visibility_timer.timeout.connect(self._on_temp_exp_bar_visibility_timer_timeout)
	else: push_error("GameUI: TempExpBarVisibilityTimer node not found.")
	
	# Emit initial DDS change to inform game.gd of starting DDS.
	emit_signal("dds_changed", dynamic_difficulty_score)


# Attempts to connect to the PlayerCharacter node.
# This uses 'await get_tree().process_frame' to ensure the player node is ready in the tree.
func _attempt_player_connections():
	await get_tree().process_frame
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		player_node = players[0] as PlayerCharacter
		if is_instance_valid(player_node):
			# Connect to player's health, experience, and level-up signals.
			if player_node.has_signal("health_changed"): player_node.health_changed.connect(self._on_player_health_changed)
			if player_node.has_signal("experience_changed"): player_node.experience_changed.connect(self._on_player_experience_changed)
			if player_node.has_signal("player_level_up"): player_node.player_level_up.connect(self._on_player_level_up_for_dds)
			# NEW: Connect to the new temporary health signal
			if player_node.has_signal("temp_health_changed"): player_node.temp_health_changed.connect(self._on_player_temp_health_changed)

			time_of_last_level_up = elapsed_seconds # Initialize for rapid level-up calculation
		else: push_error("GameUI: Player node became invalid during connection setup. Check player scene.")
	else: push_error("GameUI: Player node not found in group 'player_char_group'. Ensure player is in the scene and grouped correctly.")


func _process(delta: float): # UI Positioning Logic (e.g., health bar above player)
	if not is_instance_valid(player_node) or not is_instance_valid(player_health_bar): return
	
	var current_cam: Camera2D = get_viewport().get_camera_2d()
	if not is_instance_valid(current_cam):
		print("GameUI DEBUG: Camera is invalid in _process, cannot position UI.")
		return

	var anchor_world_pos: Vector2
	if player_node.has_method("get_ui_anchor_global_position"):
		anchor_world_pos = player_node.get_ui_anchor_global_position()
	else:
		# Fallback if anchor method is missing. This assumes player's global_position is center-bottom or center.
		anchor_world_pos = player_node.global_position

	
	# FIXED: Use Camera2D.get_viewport_transform() for correct world-to-viewport pixel conversion.
	# This Transformation handles camera position, zoom, and rotation relative to the world.
	# The output is in viewport (screen) coordinates.
	var anchor_screen_pos: Vector2 = current_cam.get_viewport_transform() * anchor_world_pos
	

	# Position health bar relative to the player's screen position.
	# health_bar_pos_x calculates the X position to center the bar horizontally.
	# health_bar_pos_y calculates the Y position to place the bar above the anchor point,
	# considering its own height.
	var health_bar_pos_x = anchor_screen_pos.x - (player_health_bar.size.x / 2.0) + HEALTH_BAR_X_OFFSET
	var health_bar_pos_y = anchor_screen_pos.y + HEALTH_BAR_Y_OFFSET - player_health_bar.size.y
	
	var final_health_bar_position = Vector2(health_bar_pos_x, health_bar_pos_y)
	player_health_bar.global_position = final_health_bar_position

	# --- NEW: Position the temporary health bar ---
	if is_instance_valid(temp_health_bar):
		# Position it slightly above the main health bar
		var temp_health_bar_pos = final_health_bar_position + Vector2(0, TEMP_HEALTH_BAR_Y_OFFSET)
		temp_health_bar.global_position = temp_health_bar_pos
		# Ensure its size matches the main health bar
		temp_health_bar.size = player_health_bar.size
		
	# Position temporary EXP bar if visible.
	if is_instance_valid(temp_exp_bar) and temp_exp_bar.visible:
		var exp_bar_pos_x = anchor_screen_pos.x - (temp_exp_bar.size.x / 2.0) + HEALTH_BAR_X_OFFSET
		# Position below health bar. Use the calculated bottom of the health bar as a reference.
		var exp_bar_pos_y = final_health_bar_position.y + player_health_bar.size.y + EXP_BAR_Y_OFFSET_FROM_HEALTH
		temp_exp_bar.global_position = Vector2(exp_bar_pos_x, exp_bar_pos_y)
		
# --- NEW: Handler for the temporary health signal ---
func _on_player_temp_health_changed(current_temp_health: float):
	if not is_instance_valid(temp_health_bar): return
	
	# The cap for Champion's Resolve is 300
	temp_health_bar.max_value = 300.0
	temp_health_bar.value = current_temp_health
	temp_health_bar.visible = current_temp_health > 0.01

# Called every second by one_second_tick_timer.
func _on_one_second_tick_timer_timeout():
	elapsed_seconds += 1
	if gameplay_timer_label: gameplay_timer_label.text = format_time(elapsed_seconds)
	
	var dds_increment_this_tick: float = 0.0
	
	# Base DDS gain over time.
	if elapsed_seconds > 0 and elapsed_seconds % 20 == 0: # Note: original comment said 30 sec tick, but logic is 20 sec.
		dds_increment_this_tick += base_dds_per_30_sec_tick
	
	# Check for Hardcore Phase activation.
	if not is_hardcore_phase and elapsed_seconds >= HARDCORE_MODE_START_SECONDS:
		is_hardcore_phase = true
		print("GAMEUI: HARDCORE PHASE ACTIVATED!")
		emit_signal("hardcore_phase_activated") # Notify game.gd or other systems
	
	# Add extra DDS in hardcore phase.
	if is_hardcore_phase:
		dds_increment_this_tick += hardcore_dds_extra_per_second
	
	# Update DDS if there's any increment.
	if dds_increment_this_tick > 0.0:
		dynamic_difficulty_score += dds_increment_this_tick
		emit_signal("dds_changed", dynamic_difficulty_score) # Notify game.gd of DDS change
		_update_dds_label() # Update DDS display

	# Legacy difficulty tier increase (separate from DDS, for specific triggers if any).
	if current_difficulty_tier < MAX_DIFFICULTY_TIERS_FOR_SPAWN_RATE:
		if elapsed_seconds >= next_difficulty_increase_time:
			current_difficulty_tier += 1
			next_difficulty_increase_time += DIFFICULTY_INTERVAL
			emit_signal("difficulty_tier_increased", current_difficulty_tier)


# Called when the player levels up. Calculates and applies DDS bonus.
func _on_player_level_up_for_dds(_new_level: int):
	if not is_instance_valid(player_node): return
	
	var dds_bonus_this_level: float = dds_bonus_per_level_up
	var time_since_last = elapsed_seconds - time_of_last_level_up
	
	# Apply rapid level-up bonus if applicable.
	if time_of_last_level_up > 0 and time_since_last < rapid_level_up_threshold_seconds:
		dds_bonus_this_level += dds_bonus_rapid_level_up
	
	# Apply hardcore phase multiplier to level-up bonus.
	if is_hardcore_phase:
		dds_bonus_this_level *= hardcore_level_up_dds_multiplier
	
	dynamic_difficulty_score += dds_bonus_this_level
	time_of_last_level_up = elapsed_seconds # Update last level-up time
	
	emit_signal("dds_changed", dynamic_difficulty_score) # Notify game.gd of DDS change
	_update_dds_label() # Update DDS display


# Updates the DDS label on the UI.
func _update_dds_label():
	if is_instance_valid(dds_label):
		dds_label.text = "DDS: %d" % [round(dynamic_difficulty_score)]


# Updates the label displaying the count of active culled enemies.
func update_culled_enemies_display(count: int):
	if is_instance_valid(culled_enemies_label):
		culled_enemies_label.text = "Active Enemies: %d" % [count]


# Updates the label displaying the global threat pool level.
func update_threat_pool_display(threat_level: int):
	if is_instance_valid(threat_pool_label):
		threat_pool_label.text = "Threat Pool: %d" % [threat_level]


# --- Public Methods for DebugPanel to Manipulate DDS ---
func set_dds_value(new_value: float):
	dynamic_difficulty_score = maxf(0.0, new_value) # Use maxf
	_update_dds_label()
	emit_signal("dds_changed", dynamic_difficulty_score)
	print("GameUI DEBUG: DDS manually set to: ", dynamic_difficulty_score)

func adjust_dds_value(amount: float):
	dynamic_difficulty_score = maxf(0.0, dynamic_difficulty_score + amount) # Use maxf
	_update_dds_label()
	emit_signal("dds_changed", dynamic_difficulty_score)
	print("GameUI DEBUG: DDS adjusted by: ", amount, ". New DDS: ", dynamic_difficulty_score)

# --- NEW: Debug Setters for DDS Parameters (Tunable via Debug Panel) ---
func debug_set_base_dds_per_30_sec_tick(value: float):
	base_dds_per_30_sec_tick = maxf(0.0, value)
	print("GameUI DEBUG: base_dds_per_30_sec_tick set to: ", base_dds_per_30_sec_tick)

func debug_set_dds_bonus_per_level_up(value: float):
	dds_bonus_per_level_up = maxf(0.0, value)
	print("GameUI DEBUG: dds_bonus_per_level_up set to: ", dds_bonus_per_level_up)

func debug_set_dds_bonus_rapid_level_up(value: float):
	dds_bonus_rapid_level_up = maxf(0.0, value)
	print("GameUI DEBUG: dds_bonus_rapid_level_up set to: ", dds_bonus_rapid_level_up)

func debug_set_rapid_level_up_threshold_seconds(value: float):
	rapid_level_up_threshold_seconds = maxf(1.0, value) # Must be at least 1s
	print("GameUI DEBUG: rapid_level_up_threshold_seconds set to: ", rapid_level_up_threshold_seconds)

func debug_set_hardcore_dds_extra_per_second(value: float):
	hardcore_dds_extra_per_second = maxf(0.0, value)
	print("GameUI DEBUG: hardcore_dds_extra_per_second set to: ", hardcore_dds_extra_per_second)

func debug_set_hardcore_level_up_dds_multiplier(value: float):
	hardcore_level_up_dds_multiplier = maxf(0.0, value)
	print("GameUI DEBUG: hardcore_level_up_dds_multiplier set to: ", hardcore_level_up_dds_multiplier)

func debug_reset_dds_parameters_to_defaults():
	base_dds_per_30_sec_tick = ORIGINAL_BASE_DDS_PER_30_SEC_TICK
	dds_bonus_per_level_up = ORIGINAL_DDS_BONUS_PER_LEVEL_UP
	dds_bonus_rapid_level_up = ORIGINAL_DDS_BONUS_RAPID_LEVEL_UP
	rapid_level_up_threshold_seconds = ORIGINAL_RAPID_LEVEL_UP_THRESHOLD_SECONDS
	hardcore_dds_extra_per_second = ORIGINAL_HARDCORE_DDS_EXTRA_PER_SECOND
	hardcore_level_up_dds_multiplier = ORIGINAL_HARDCORE_LEVEL_UP_DDS_MULTIPLIER
	print("GameUI DEBUG: All DDS calculation parameters reset to defaults.")
	# Optionally, re-emit dds_changed if you want game.gd to immediately react to reset values
	# emit_signal("dds_changed", dynamic_difficulty_score)


# --- Existing Getters and UI Update Functions ---
# Handles player health changes and updates the health bar.
func _on_player_health_changed(new_health_val: float, max_health_val: float): # Changed to float for consistency
	if player_health_bar:
		# Ensure max_value is at least 1 to prevent division by zero in ProgressBar
		player_health_bar.max_value = maxf(1.0, max_health_val)
		player_health_bar.value = new_health_val
		player_health_bar.visible = (new_health_val > 0) # Hide if health is 0 or less
	else: push_warning("GameUI: PlayerHealthBar is invalid, cannot update health display.")

# Handles player experience changes and updates the temporary EXP bar.
func _on_player_experience_changed(current_exp: int, exp_to_next: int, _player_level: int):
	if temp_exp_bar:
		if exp_to_next > 0:
			temp_exp_bar.max_value = exp_to_next
			temp_exp_bar.value = current_exp
		else: # Avoid division by zero if exp_to_next is 0 (e.g., at max level)
			temp_exp_bar.max_value = 1
			temp_exp_bar.value = 1
		
		# Show the bar if it's not visible or if the timer has stopped (meaning it just became invisible)
		if not temp_exp_bar.visible or (is_instance_valid(temp_exp_bar_visibility_timer) and temp_exp_bar_visibility_timer.is_stopped()):
			temp_exp_bar.visible = true
			if is_instance_valid(temp_exp_bar_visibility_timer): temp_exp_bar_visibility_timer.start() # Restart timer
	else: push_warning("GameUI: TempExpBar is invalid, cannot update experience display.")

# Hides the temporary EXP bar after its visibility timer times out.
func _on_temp_exp_bar_visibility_timer_timeout():
	if temp_exp_bar: temp_exp_bar.visible = false
	else: push_warning("GameUI: TempExpBar is invalid, cannot hide experience display.")

# Formats total seconds into HH:MM:SS string.
func format_time(total_seconds: int) -> String:
	var hours: int = total_seconds / 3600
	var minutes: int = (total_seconds % 3600) / 60
	var seconds: int = total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

# Getters for external systems (e.g., game.gd) to query UI state.
func get_elapsed_seconds() -> int: return elapsed_seconds
func get_current_difficulty_tier() -> int: return current_difficulty_tier
func get_dynamic_difficulty_score() -> float: return dynamic_difficulty_score
func is_in_hardcore_phase() -> bool: return is_hardcore_phase
