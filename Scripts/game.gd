# game.gd
# Main game logic.
# Manages enemy spawning, DDS, level-up options, and acts as a central hub
# for various game systems.
# It now fully integrates with the standardized stat system using PlayerStatKeys.

extends Node2D

# --- Preloads ---
const GAME_OVER_SCREEN_SCENE = preload("res://Scenes/UI/GameOverScreen.tscn")
const LEVEL_UP_SCREEN_SCENE = preload("res://Scenes/UI/NewLevelUpScreen.tscn")

@onready var enemy_spawn_timer: Timer = $EnemySpawnTimer
@onready var enemies_container: Node2D = $EnemiesContainer
@onready var drops_container: Node2D = $DropsContainer
@onready var boss_container: Node2D = $BossContainer
var camera: Camera2D
var game_ui_node: Node # Type hint for the GameUI node
var game_over_screen_instance: CanvasLayer # Instance of the game over UI
var level_up_screen_instance: CanvasLayer
var player_node: PlayerCharacter # Reference to the player character

# --- Spawn Configuration (Tunable) ---
@export var spawn_margin: float = 100.0
@export var player_movement_threshold: float = 20.0
@export var forward_spawn_bias_chance: float = 0.75
var enemies_per_batch_calculated: int = 3 # This will be calculated from base_enemies_per_batch and DDS

const ORIGINAL_SPAWN_MARGIN: float = 100.0
const ORIGINAL_PLAYER_MOVEMENT_THRESHOLD: float = 20.0
const ORIGINAL_FORWARD_SPAWN_BIAS_CHANCE: float = 0.75
const ORIGINAL_BASE_SPAWN_INTERVAL: float = 3.5
const ORIGINAL_MIN_SPAWN_INTERVAL: float = 0.25
const ORIGINAL_ENEMIES_PER_BATCH: int = 3 # Original constant for batch size

# --- Spawn Interval Scaling (Tunable) ---
var base_spawn_interval: float = 3.5
var min_spawn_interval: float = 0.25
var current_spawn_interval: float

# --- NEW: Spawn Batch Size Scaling (Tunable) ---
@export var base_enemies_per_batch: int = 3
@export var max_enemies_per_batch: int = 30
@export var dds_for_max_batch_size: float = 3000.0 # DDS at which the max batch size is reached

# --- DDS & Difficulty Scaling (Tunable) ---
var current_dds: float = 0.0
var is_currently_hardcore_phase: bool = false
@export var dds_spawn_rate_factor: float = 0.0020
@export var hardcore_spawn_rate_multiplier: float = 1.75

const ORIGINAL_DDS_SPAWN_RATE_FACTOR: float = 0.0020
const ORIGINAL_HARDCORE_SPAWN_RATE_MULTIPLIER: float = 1.75

# --- Enemy Definitions & Active Pool (Tunable) ---
@export var enemy_data_files: Array[String] = [
	"res://DataResources/Enemies/slime_green_data.tres",
	"res://DataResources/Enemies/slime_blue_data.tres",
	"res://DataResources/Enemies/slime_red_data.tres",
	"res://DataResources/Enemies/slime_tall_light_blue_data.tres"
]
var loaded_enemy_definitions: Array[EnemyData] = [] # Stores loaded EnemyData resources

@export var max_active_enemy_types: int = 7 # Max distinct enemy types in the active pool
var current_active_enemy_pool: Array[EnemyData] = [] # The pool of enemies currently eligible to spawn
var last_active_pool_refresh_dds: float = -200.0 # DDS at which the pool was last refreshed
@export var active_pool_refresh_dds_interval: float = 20.0 # How often (in DDS) the pool refreshes

const ORIGINAL_MAX_ACTIVE_ENEMY_TYPES: int = 7
const ORIGINAL_ACTIVE_POOL_REFRESH_DDS_INTERVAL: float = 20.0

# --- Enemy Count Management (Tunable) ---
var current_active_enemy_count: int = 0
var target_on_screen_enemies: int = 15 # Desired number of enemies on screen (scales with DDS)
@export var enemy_count_update_dds_interval: float = 35.0 # How often (in DDS) to update target_on_screen_enemies
var last_enemy_count_update_dds: float = -100.0 # DDS at which target_on_screen_enemies was last updated
@export var debug_override_target_enemies: bool = false
@export var debug_target_enemies_value: int = 15

const ORIGINAL_ENEMY_COUNT_UPDATE_DDS_INTERVAL: float = 35.0

# --- Global Threat Pool (Tunable) ---
var global_unspent_threat_pool: int = 0
@export var threat_pool_spawn_threshold: int = 6 # DDS accumulated to trigger a threat spawn batch
@export var threat_pool_batch_multiplier: float = 2.0 # Multiplier for threat spawn batch size
var culling_check_timer: Timer
@export var culling_timer_wait_time: float = 3.0 # Interval for checking enemies to cull

const ORIGINAL_THREAT_POOL_SPAWN_THRESHOLD: int = 25
const ORIGINAL_THREAT_POOL_BATCH_MULTIPLIER: float = 1.5
const ORIGINAL_CULLING_TIMER_WAIT_TIME: float = 3.0

# --- Boss & Event Management (Tunable Random Event Interval) ---
var boss_encounters: Array[Dictionary] = [
	{"id": "slime_king", "dds_trigger": 700, "scene_path": "res://Scenes/Bosses/slime_king_boss.tscn", "cleared": false, "reward_dds_bonus": 150},
	{"id": "hardcore_challenger_1", "dds_trigger": 4500, "scene_path": "res://Scenes/Bosses/hardcore_boss_1.tscn", "cleared": false, "reward_dds_bonus": 300, "is_hardcore_boss": true},
]
var current_boss_active: bool = false
var current_boss_node: Node2D = null

var random_event_definitions: Array[Dictionary] = [
	{"id": "altered_slime_king_event", "display_name": "A Familiar Ooze Returns!", "min_dds": 1000, "max_dds": 2000, "weight": 10, "type": "altered_boss", "original_boss_id": "slime_king", "alteration_level": 1},
	{"id": "elite_ambush_event", "display_name": "Elite Ambush!", "min_dds": 500, "max_dds": -1, "weight": 15, "type": "elite_wave", "duration": 25.0, "spawn_interval_multiplier": 0.5, "num_elites_to_spawn": 5},
	{"id": "hardcore_onslaught", "display_name": "Hardcore Onslaught!", "min_dds": 4200, "max_dds": -1, "weight": 30, "type": "special_wave", "duration": 45.0, "spawn_interval_multiplier": 0.2, "only_hardcore_enemies": true}
]
var time_since_last_random_event_check: float = 0.0
@export var random_event_check_interval: float = 35.0
var random_event_miss_streak: int = 0
var current_event_active: bool = false
var current_event_id: String = ""
var current_event_end_timer: Timer = null

const ORIGINAL_RANDOM_EVENT_CHECK_INTERVAL: float = 35.0

# --- Weapon Blueprint Loading (NEW SYSTEM) ---
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
	"res://DataResources/Weapons/MothGolem/conjurer_moth_golem_blueprint.tres"
]

var all_loaded_weapon_blueprints: Array[WeaponBlueprintData] = [] # All blueprints loaded at startup
var weapon_blueprints_by_id: Dictionary = {} # Dictionary for quick lookup by ID

# --- General Upgrades (Now uses GeneralUpgradeCardData resources) ---
@export var general_upgrade_card_paths: Array[String] = [] # Paths to GeneralUpgradeCardData.tres files
var loaded_general_upgrades: Array[GeneralUpgradeCardData] = [] # Loaded GeneralUpgradeCardData resources

# Signal to indicate that all weapon blueprints are loaded and ready.
# PlayerCharacter.gd will connect to this to ensure proper initialization.
signal weapon_blueprints_ready


func _ready():
	_load_all_weapon_blueprints()
	_test_print_loaded_weapon_blueprints() # For debug purposes
	_load_all_general_upgrades()
	# Crucial: Emit this signal AFTER all blueprints are loaded.
	emit_signal("weapon_blueprints_ready")

	current_spawn_interval = base_spawn_interval
	camera = get_viewport().get_camera_2d()

	# Load all EnemyData resources from paths.
	for path in enemy_data_files:
		var enemy_data_res = load(path) as EnemyData
		if is_instance_valid(enemy_data_res): loaded_enemy_definitions.append(enemy_data_res)
		else: push_error("game.gd: Failed to load EnemyData resource at: ", path)
	# Sort enemy definitions by their min_DDS_to_spawn for efficient pool selection.
	if not loaded_enemy_definitions.is_empty():
		loaded_enemy_definitions.sort_custom(func(a,b): return a.min_DDS_to_spawn < b.min_DDS_to_spawn)

	game_ui_node = get_node_or_null("GameUI")
	if is_instance_valid(game_ui_node):
		if game_ui_node.has_signal("dds_changed"):
			if not game_ui_node.is_connected("dds_changed", Callable(self, "_on_dds_changed")):
				game_ui_node.dds_changed.connect(Callable(self, "_on_dds_changed"))
		# Get initial DDS and hardcore phase status from GameUI
		if game_ui_node.has_method("get_dynamic_difficulty_score"): current_dds = game_ui_node.get_dynamic_difficulty_score()
		if game_ui_node.has_method("is_in_hardcore_phase"): is_currently_hardcore_phase = game_ui_node.is_in_hardcore_phase()
		
		_update_target_on_screen_enemies(); last_enemy_count_update_dds = current_dds
		_refresh_active_enemy_pool(); last_active_pool_refresh_dds = current_dds
	else: push_error("game.gd: GameUI node not found. Ensure it's in the scene and named 'GameUI'.")

	# Setup enemy spawn timer. Only start if camera is valid.
	if not is_instance_valid(camera):
		push_warning("game.gd: Camera not found, EnemySpawnTimer will not start.")
		if is_instance_valid(enemy_spawn_timer): enemy_spawn_timer.stop()
	else:
		if is_instance_valid(enemy_spawn_timer):
			enemy_spawn_timer.wait_time = current_spawn_interval
			if not enemy_spawn_timer.is_connected("timeout", Callable(self, "_on_enemy_spawn_timer_timeout")):
				enemy_spawn_timer.timeout.connect(Callable(self, "_on_enemy_spawn_timer_timeout"))
			enemy_spawn_timer.start()

	# Get player reference and connect to player death and level up signals.
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		player_node = players[0] as PlayerCharacter
		if player_node.has_signal("player_has_died"): player_node.player_has_died.connect(Callable(self, "_on_player_has_died"))
		if player_node.has_signal("player_level_up"): player_node.player_level_up.connect(Callable(self, "_on_player_level_up"))
	else:
		push_error("game.gd: PlayerCharacter node not found in 'player_char_group'.")
	
	_update_spawn_interval_from_dds()

	# Setup enemy culling timer.
	culling_check_timer = Timer.new(); culling_check_timer.name = "EnemyCullingTimer"
	culling_check_timer.wait_time = culling_timer_wait_time
	culling_check_timer.one_shot = false
	culling_check_timer.timeout.connect(Callable(self, "_on_culling_check_timer_timeout"))
	add_child(culling_check_timer); culling_check_timer.start()

# Loads all WeaponBlueprintData resources from specified paths.
func _load_all_weapon_blueprints():
	all_loaded_weapon_blueprints.clear()
	weapon_blueprints_by_id.clear()
	for path in weapon_blueprint_files:
		var bp_res = load(path) as WeaponBlueprintData
		if is_instance_valid(bp_res):
			all_loaded_weapon_blueprints.append(bp_res)
			if bp_res.id != &"":
				weapon_blueprints_by_id[bp_res.id] = bp_res
			else:
				push_warning("game.gd: WeaponBlueprintData at '", path, "' has an empty ID. Skipping.")
		else:
			push_error("game.gd: Failed to load WeaponBlueprintData from path: ", path)

# Loads all GeneralUpgradeCardData resources from specified paths.
func _load_all_general_upgrades():
	loaded_general_upgrades.clear()
	for path in general_upgrade_card_paths:
		var card_res = load(path) as GeneralUpgradeCardData
		if is_instance_valid(card_res):
			loaded_general_upgrades.append(card_res)
		else:
			push_error("game.gd: Failed to load GeneralUpgradeCardData from path: ", path)


# Debug function to print details of all loaded weapon blueprints.
func _test_print_loaded_weapon_blueprints():
	print("--- Loaded Weapon Blueprints Test ---")
	if all_loaded_weapon_blueprints.is_empty():
		print("No weapon blueprints were loaded or found in 'weapon_blueprint_files' array.")
		return

	for bp_data in all_loaded_weapon_blueprints:
		if not is_instance_valid(bp_data):
			print("  Found an invalid blueprint in the loaded list.")
			continue
		
		print("Weapon ID: '", bp_data.id, "', Title: '", bp_data.title, "'")
		var scene_path_str = "N/A"
		if is_instance_valid(bp_data.weapon_scene) and bp_data.weapon_scene.resource_path != "":
			scene_path_str = bp_data.weapon_scene.resource_path
		print("  Scene: ", scene_path_str)
		print("  Cooldown: ", bp_data.cooldown, ", Max Level: ", bp_data.max_level)
		print("  Initial Specific Stats: ", bp_data.initial_specific_stats)
		print("  Available Upgrades (%s):" % bp_data.available_upgrades.size())
		for upgrade_res_idx in range(bp_data.available_upgrades.size()):
			var upgrade_res = bp_data.available_upgrades[upgrade_res_idx]
			if not is_instance_valid(upgrade_res) or not upgrade_res is WeaponUpgradeData:
				print("    - Invalid upgrade resource found at index ", upgrade_res_idx, " in blueprint's available_upgrades array. Type: ", typeof(upgrade_res))
				continue
			
			var upg_data = upgrade_res as WeaponUpgradeData
			print("    - Upgrade [", upgrade_res_idx, "] ID: '", upg_data.upgrade_id, "', Title: '", upg_data.title, "'")
			print("      Effects (%s):" % upg_data.effects.size())
			for effect_res_idx in range(upg_data.effects.size()):
				var effect_res = upg_data.effects[effect_res_idx]
				if not is_instance_valid(effect_res):
					print("        Effect [", effect_res_idx, "]: Invalid resource.")
					continue
				print("        Effect [", effect_res_idx, "] TypeID: '", effect_res.effect_type_id, "' (Class: '", effect_res.get_class(),"')")
				
				if effect_res is StatModificationEffectData:
					var stat_mod = effect_res as StatModificationEffectData
					# CORRECTED: Use get_value() from StatModificationEffectData
					var effect_val = stat_mod.get_value()
					print("          StatMod: Scope='", stat_mod.target_scope, "', Key='", stat_mod.stat_key, "', Type='", stat_mod.modification_type, "', Val=", effect_val)
				
				elif effect_res is CustomFlagEffectData:
					var flag_mod = effect_res as CustomFlagEffectData
					print("          FlagMod: Scope='", flag_mod.target_scope, "', Key='", flag_mod.flag_key, "', Val=", flag_mod.flag_value)
				
				elif effect_res is TriggerAbilityEffectData:
					var trigger_mod = effect_res as TriggerAbilityEffectData
					print("          TriggerAbility: Scope='", trigger_mod.target_scope, "', ID='", trigger_mod.ability_id, "', Params=", trigger_mod.ability_params)
				
				elif effect_res is StatusEffectApplicationData:
					var status_app_mod = effect_res as StatusEffectApplicationData
					print("          StatusApp: Scope='", status_app_mod.target_scope, "', Path='", status_app_mod.status_effect_resource_path, "', Chance=", status_app_mod.application_chance, ", DurationOvr=", status_app_mod.duration_override)
				
				else:
					print("          Unknown/Base EffectData: DevNote='", effect_res.developer_note, "'")
		print("---")


func _physics_process(delta: float):
	# If a boss or event is active, regular enemy spawning is paused.
	if current_boss_active or current_event_active: return
	
	# Update time since last random event check.
	time_since_last_random_event_check += delta


func increment_active_enemy_count():
	current_active_enemy_count += 1
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("update_culled_enemies_display"):
		game_ui_node.update_culled_enemies_display(current_active_enemy_count)

func decrement_active_enemy_count():
	current_active_enemy_count = max(0, current_active_enemy_count - 1)
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("update_culled_enemies_display"):
		game_ui_node.update_culled_enemies_display(current_active_enemy_count)

func add_to_global_threat_pool(amount: int):
	global_unspent_threat_pool += amount
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("update_threat_pool_display"):
		game_ui_node.update_threat_pool_display(global_unspent_threat_pool)

# Called by GameUI when DDS changes. Updates difficulty parameters.
func _on_dds_changed(new_dds_score: float):
	var previous_dds_for_bucketing = current_dds
	current_dds = new_dds_score
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("is_in_hardcore_phase"):
		is_currently_hardcore_phase = game_ui_node.is_in_hardcore_phase()
	
	_update_spawn_interval_from_dds()
	
	# Check if enemy count target needs to be updated (based on DDS "buckets")
	var old_enemy_count_bucket = floor(previous_dds_for_bucketing / enemy_count_update_dds_interval)
	var new_enemy_count_bucket = floor(new_dds_score / enemy_count_update_dds_interval)
	if new_enemy_count_bucket > old_enemy_count_bucket or last_enemy_count_update_dds < 0:
		_update_target_on_screen_enemies(); last_enemy_count_update_dds = new_dds_score
	
	# Check if active enemy pool needs to be refreshed
	var old_dds_bucket_pool = floor(previous_dds_for_bucketing / active_pool_refresh_dds_interval)
	var new_dds_bucket_pool = floor(new_dds_score / active_pool_refresh_dds_interval)
	if new_dds_bucket_pool > old_dds_bucket_pool or last_active_pool_refresh_dds < 0:
		_refresh_active_enemy_pool(); last_active_pool_refresh_dds = new_dds_score

# _update_target_on_screen_enemies
# This function calculates the desired number of enemies on screen based on game progression.
# It implements a "training wheels" phase and a scalable DDS-based system.
func _update_target_on_screen_enemies():
	if debug_override_target_enemies:
		target_on_screen_enemies = debug_target_enemies_value
		return

	var time_elapsed_minutes = 0.0
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("get_elapsed_seconds"):
		time_elapsed_minutes = float(game_ui_node.get_elapsed_seconds()) / 60.0

	var calculated_target: int
	
	# Initial "Training Wheels" Phase (First 3 minutes)
	# Smoothly scales the enemy cap from 10 to 30 over the first 3 minutes.
	if time_elapsed_minutes < 3.0:
		calculated_target = int(lerpf(10.0, 30.0, time_elapsed_minutes / 3.0))
	else:
		# Main Game Phase (DDS-based scaling)
		# Smoothly scales the enemy cap from 30 up to 400 as DDS goes from 0 to 4000.
		var start_enemies = 30.0
		var end_enemies = 400.0
		var start_dds = 0.0
		var end_dds = 4000.0
		
		# Remap the current DDS value from the DDS range to the enemy count range.
		# The clamp ensures we don't go below the minimum or above the maximum.
		calculated_target = int(remap(current_dds, start_dds, end_dds, start_enemies, end_enemies))
		calculated_target = clamp(calculated_target, int(start_enemies), int(end_enemies))

	# Apply the hardcore phase multiplier
	if is_currently_hardcore_phase:
		target_on_screen_enemies = int(calculated_target * 1.35)
		target_on_screen_enemies = min(target_on_screen_enemies, 550) # Increased hardcore cap
	else:
		target_on_screen_enemies = calculated_target

# Adjusts the enemy spawn interval based on DDS and hardcore phase.
func _update_spawn_interval_from_dds():
	if is_instance_valid(enemy_spawn_timer):
		var interval_divisor = 1.0 + (dds_spawn_rate_factor * current_dds)
		if is_currently_hardcore_phase: interval_divisor *= hardcore_spawn_rate_multiplier
		current_spawn_interval = base_spawn_interval / interval_divisor
		current_spawn_interval = maxf(min_spawn_interval, current_spawn_interval) # Use maxf for floats
		enemy_spawn_timer.wait_time = current_spawn_interval
		
		# Start timer if it's stopped and no boss/event is active
		if enemy_spawn_timer.is_stopped() and not current_boss_active and not current_event_active :
			enemy_spawn_timer.start()
		# If timer is already running, starting it again effectively just updates wait_time.
		# No need for the 'else if' part from original code.

# Refreshes the pool of enemies eligible to spawn based on current DDS.
func _refresh_active_enemy_pool():
	if loaded_enemy_definitions.is_empty(): return
	var dds_eligible_enemies: Array[EnemyData] = []
	for enemy_data_res in loaded_enemy_definitions:
		if not is_instance_valid(enemy_data_res): continue
		var max_dds = enemy_data_res.max_DDS_to_spawn
		# Check if enemy is within its min/max DDS spawn range
		if current_dds >= enemy_data_res.min_DDS_to_spawn and \
		   (current_dds < max_dds or max_dds < 0.0): # -1.0 means never phases out
			dds_eligible_enemies.append(enemy_data_res)
	
	current_active_enemy_pool.clear()
	if dds_eligible_enemies.is_empty():
		push_warning("game.gd: No DDS-eligible enemies found for current DDS: ", current_dds); return
	
	# Sort eligible enemies by their "relevance" to current DDS, then by spawn weight.
	dds_eligible_enemies.sort_custom(func(a,b):
		var relevance_a = absf(current_dds - a.min_DDS_to_spawn)
		var relevance_b = absf(current_dds - b.min_DDS_to_spawn)
		if absf(relevance_a - relevance_b) < 0.01 : return a.spawn_weight > b.spawn_weight # Tie-break by weight
		return relevance_a < relevance_b
	)
	
	var temp_pool: Array[EnemyData] = []
	var current_slot_cost_filled = 0
	var added_enemy_ids: Dictionary = {} # To prevent adding duplicate enemy types to pool

	# Prioritize adding enemies that are most relevant to the current DDS
	for enemy_data in dds_eligible_enemies:
		if added_enemy_ids.has(enemy_data.id): continue # Skip if already added
		# Check if adding this enemy type exceeds the max_active_enemy_types limit
		if current_slot_cost_filled + enemy_data.ideal_active_pool_slot_cost <= max_active_enemy_types:
			temp_pool.append(enemy_data)
			added_enemy_ids[enemy_data.id] = true
			current_slot_cost_filled += enemy_data.ideal_active_pool_slot_cost
		if current_slot_cost_filled >= max_active_enemy_types: break # Stop if pool is full
	
	# If the pool is not yet full, fill it with remaining eligible enemies (shuffled)
	if current_slot_cost_filled < max_active_enemy_types and dds_eligible_enemies.size() > temp_pool.size():
		var remaining_eligible_shuffled = dds_eligible_enemies.filter(func(ed): return not added_enemy_ids.has(ed.id))
		remaining_eligible_shuffled.shuffle() # Randomize the order
		for enemy_data in remaining_eligible_shuffled:
			if added_enemy_ids.has(enemy_data.id): continue
			if current_slot_cost_filled + enemy_data.ideal_active_pool_slot_cost <= max_active_enemy_types:
				temp_pool.append(enemy_data)
				added_enemy_ids[enemy_data.id] = true
				current_slot_cost_filled += enemy_data.ideal_active_pool_slot_cost
			if current_slot_cost_filled >= max_active_enemy_types: break
	
	current_active_enemy_pool = temp_pool
	# print("Active Enemy Pool Refreshed (DDS ", current_dds, "): ", current_active_enemy_pool.map(func(e): return e.id))

# Selects a random enemy from the active pool, weighted by spawn_weight.
func _select_enemy_from_active_pool() -> EnemyData:
	if current_active_enemy_pool.is_empty(): return null
	
	var total_weight: float = 0.0
	for edr in current_active_enemy_pool: total_weight += edr.spawn_weight
	
	if total_weight <= 0.0: # Fallback if all weights are zero
		return current_active_enemy_pool.pick_random()
	
	var rand_w = randf() * total_weight
	var current_w_sum: float = 0.0
	for edrc in current_active_enemy_pool:
		current_w_sum += edrc.spawn_weight
		if rand_w <= current_w_sum: return edrc
	
	return current_active_enemy_pool.pick_random() # Fallback, should ideally not be reached

# Calculates a suitable spawn position for an enemy.
func _calculate_spawn_position_for_enemy(near_player: bool = false, offset_vector: Vector2 = Vector2.ZERO) -> Vector2:
	if not is_instance_valid(camera) or not is_instance_valid(player_node): return Vector2.ZERO
	
	if near_player: # Spawn close to player (e.g., for specific events)
		var random_angle = randf_range(0, TAU)
		var random_distance = randf_range(75, 125) # Distance from player
		return player_node.global_position + Vector2.RIGHT.rotated(random_angle) * random_distance + offset_vector
	
	var spawn_position = Vector2.ZERO
	var viewport_pixel_size = get_viewport().get_visible_rect().size
	var camera_current_zoom = camera.zoom
	
	# Calculate world view dimensions based on camera zoom
	var world_view_width = viewport_pixel_size.x / camera_current_zoom.x
	var world_view_height = viewport_pixel_size.y / camera_current_zoom.y
	
	var top_left_global = camera.global_position - Vector2(world_view_width / 2.0, world_view_height / 2.0)
	var min_x_visible = top_left_global.x
	var max_x_visible = top_left_global.x + world_view_width
	var min_y_visible = top_left_global.y
	var max_y_visible = top_left_global.y + world_view_height
	
	var side = randi() % 4 # 0=top, 1=bottom, 2=left, 3=right
	
	# Apply forward spawn bias if player is moving significantly
	if player_node.get_velocity().length_squared() > (player_movement_threshold * player_movement_threshold):
		var player_velocity = player_node.get_velocity().normalized()
		var forward_side = -1 # -1 means no specific forward side
		
		# Determine which side is "forward" based on dominant movement axis
		if abs(player_velocity.x) > abs(player_velocity.y): # Moving mostly horizontally
			forward_side = 3 if player_velocity.x > 0 else 2 # Right if positive X, Left if negative X
		else: # Moving mostly vertically
			forward_side = 1 if player_velocity.y > 0 else 0 # Down if positive Y, Up if negative Y
		
		# Apply bias
		if randf() < forward_spawn_bias_chance: side = forward_side
	
	# Determine spawn position based on chosen side
	match side:
		0: spawn_position = Vector2(randf_range(min_x_visible, max_x_visible), min_y_visible - spawn_margin) # Top
		1: spawn_position = Vector2(randf_range(min_x_visible, max_x_visible), max_y_visible + spawn_margin) # Bottom
		2: spawn_position = Vector2(min_x_visible - spawn_margin, randf_range(min_y_visible, max_y_visible)) # Left
		3: spawn_position = Vector2(max_x_visible + spawn_margin, randf_range(min_y_visible, max_y_visible)) # Right
	
	return spawn_position + offset_vector

# Spawns an actual enemy instance into the scene.
func _spawn_actual_enemy(enemy_data: EnemyData, position: Vector2, force_elite_type: StringName = &""):
	if not is_instance_valid(enemy_data) or enemy_data.scene_path.is_empty():
		push_error("game.gd: Cannot spawn enemy. Invalid EnemyData or empty scene path for ID: ", enemy_data.id if is_instance_valid(enemy_data) else "N/A"); return
	
	var enemy_scene = load(enemy_data.scene_path) as PackedScene
	if not is_instance_valid(enemy_scene):
		push_error("game.gd: Failed to load enemy scene from path: ", enemy_data.scene_path); return
	
	var enemy_instance = enemy_scene.instantiate() as BaseEnemy
	if not is_instance_valid(enemy_instance):
		push_error("game.gd: Failed to instantiate enemy scene: ", enemy_data.scene_path); return

	enemy_instance.global_position = position
	enemies_container.add_child(enemy_instance) # Add to container for organization

	# Initialize enemy with its data
	if enemy_instance.has_method("initialize_from_data"):
		enemy_instance.initialize_from_data(enemy_data)
	else:
		push_warning("game.gd: Spawned enemy '", enemy_data.display_name, "' is missing 'initialize_from_data' method.")
	
	var dds_contrib_elite = current_dds - enemy_data.min_DDS_to_spawn
	
	# Determine if enemy should be elite
	if force_elite_type != &"": # If an elite type is explicitly forced (e.g., by an event)
		var can_be_this_elite = enemy_data.elite_types_available.has(force_elite_type)
		if can_be_this_elite or force_elite_type == &"debug_generic_elite": # "debug_generic_elite" is a special bypass
			if enemy_instance.has_method("make_elite"):
				enemy_instance.make_elite(force_elite_type, dds_contrib_elite, enemy_data)
			else:
				push_warning("game.gd: Enemy '", enemy_data.display_name, "' is missing 'make_elite' method for forced elite type.")
	else: # Regular elite spawning chance
		var elite_c = 0.0 # Base elite chance
		if current_dds >= enemy_data.min_DDS_for_elites_to_appear:
			elite_c = 0.05 + (dds_contrib_elite * 0.0002) # Scaling elite chance
			elite_c = clampf(elite_c, 0.0, 0.60) # Clamp max regular elite chance
		if is_currently_hardcore_phase: elite_c = minf(0.85, elite_c * 1.5) # Boost in hardcore phase
		
		if randf() < elite_c and not enemy_data.elite_types_available.is_empty():
			var chosen_tag = enemy_data.elite_types_available.pick_random()
			if enemy_instance.has_method("make_elite"):
				enemy_instance.make_elite(chosen_tag, dds_contrib_elite, enemy_data)
			else:
				push_warning("game.gd: Enemy '", enemy_data.display_name, "' is missing 'make_elite' method for random elite type.")
	
	# Set experience to drop for non-elite enemies (elites might have different drop logic)
	# This part assumes 'experience_to_drop' is a direct property on the BaseEnemy script.
	if not enemy_instance.is_elite: # Assuming BaseEnemy.is_elite is a property
		if "experience_to_drop" in enemy_instance:
			enemy_instance.experience_to_drop = enemy_data.base_exp_drop
		else:
			push_warning("game.gd: Enemy '", enemy_data.display_name, "' is not elite but missing 'experience_to_drop' property.")


# --- NEW HELPER FUNCTION ---
# Calculates how many enemies should be in a single spawn batch based on DDS.
func _get_current_enemies_per_batch() -> int:
	# Remap the current DDS value to the desired batch size range.
	var batch_size = remap(current_dds, 0.0, dds_for_max_batch_size, float(base_enemies_per_batch), float(max_enemies_per_batch))
	# Clamp the result to ensure it doesn't go below the base or above the max.
	return int(clampf(batch_size, float(base_enemies_per_batch), float(max_enemies_per_batch)))
	
# --- Main Game Loop & Spawning Logic ---
func _on_enemy_spawn_timer_timeout():
	if not is_instance_valid(camera) or not is_instance_valid(player_node): return
	if current_boss_active: return # Do not spawn regular enemies during boss fights

	var current_enemies_per_batch_actual = _get_current_enemies_per_batch() # Use the calculated batch size
	var spawned_from_threat = false

	# Spawn enemies from global threat pool if threshold is met
	if global_unspent_threat_pool >= threat_pool_spawn_threshold:
		var num_threat_spawn = int(ceil(current_enemies_per_batch_actual * threat_pool_batch_multiplier))
		for _i in range(num_threat_spawn):
			# Break if screen is too crowded
			if current_active_enemy_count >= target_on_screen_enemies + current_enemies_per_batch_actual: break
			var enemy_data = _select_enemy_from_active_pool()
			if is_instance_valid(enemy_data): _spawn_actual_enemy(enemy_data, _calculate_spawn_position_for_enemy())
			else: push_warning("game.gd: No eligible enemy data for threat spawn pool.")
		global_unspent_threat_pool = max(0, global_unspent_threat_pool - threat_pool_spawn_threshold)
		spawned_from_threat = true

	# Regular enemy spawning if current count is below target or if a threat spawn just happened (to fill up)
	if current_active_enemy_count < target_on_screen_enemies or spawned_from_threat:
		var num_regular_spawn = current_enemies_per_batch_actual
		# If threat spawned, reduce regular spawn to avoid overfilling
		if spawned_from_threat and current_enemies_per_batch_actual > 1:
			num_regular_spawn = max(1, int(current_enemies_per_batch_actual / 2.0)) # Use division for float precision
		for _i in range(num_regular_spawn):
			# Break if screen is getting too crowded even with regular spawns
			if current_active_enemy_count >= target_on_screen_enemies + (current_enemies_per_batch_actual / 2): break
			var enemy_data = _select_enemy_from_active_pool()
			if is_instance_valid(enemy_data): _spawn_actual_enemy(enemy_data, _calculate_spawn_position_for_enemy())
			else: push_warning("game.gd: No eligible enemy data for regular spawn pool.")

# Checks for enemies far off-screen and culls them, adding to threat pool.
func _on_culling_check_timer_timeout():
	if not is_instance_valid(player_node) or not is_instance_valid(camera): return
	if current_boss_active: return # Do not cull during boss fights
	
	var viewport_size_length = get_viewport().get_visible_rect().size.length()
	# Define culling distance: 1.25 times the diagonal length of the visible viewport.
	var cull_dist_sq = pow(viewport_size_length * 1.25, 2)
	
	# Duplicate children array to allow safe removal during iteration
	for child_node in enemies_container.get_children().duplicate():
		if child_node is BaseEnemy:
			var enemy = child_node as BaseEnemy
			if is_instance_valid(enemy) and not enemy.is_dead_flag: # Only cull living enemies
				if enemy.global_position.distance_squared_to(player_node.global_position) > cull_dist_sq:
					if enemy.has_method("cull_self_and_report_threat"):
						enemy.cull_self_and_report_threat()
					else:
						push_warning("game.gd: Enemy '", enemy.name, "' is missing 'cull_self_and_report_threat' method.")


# --- Debug & Getter Functions ---
func get_loaded_enemy_definitions_for_debug() -> Array[EnemyData]: return loaded_enemy_definitions
func get_enemy_data_by_id_for_debug(id: StringName) -> EnemyData:
	for enemy_data_res in loaded_enemy_definitions:
		if is_instance_valid(enemy_data_res) and enemy_data_res.id == id: return enemy_data_res
	return null
func get_current_dds_for_debug() -> float: return current_dds

func get_all_weapon_blueprints_for_debug() -> Array[WeaponBlueprintData]:
	return all_loaded_weapon_blueprints

func get_weapon_blueprint_by_id(weapon_id_to_find: StringName) -> WeaponBlueprintData:
	if weapon_blueprints_by_id.has(weapon_id_to_find):
		return weapon_blueprints_by_id[weapon_id_to_find]
	return null

# Gets a list of available upgrades for a specific weapon for the level-up screen.
func get_weapon_next_level_upgrades(weapon_id_str: String, current_weapon_instance_data: Dictionary) -> Array[WeaponUpgradeData]:
	var weapon_bp = get_weapon_blueprint_by_id(StringName(weapon_id_str))
	if not is_instance_valid(weapon_bp): return []
	
	var current_level = current_weapon_instance_data.get("weapon_level", 0)
	var specific_stats = current_weapon_instance_data.get("specific_stats", {}) # Weapon's current specific stats
	
	if current_level >= weapon_bp.max_level: return [] # No more upgrades if max level reached
	
	var valid_next_upgrades: Array[WeaponUpgradeData] = []
	for upgrade_data_res in weapon_bp.available_upgrades:
		if not is_instance_valid(upgrade_data_res) or not upgrade_data_res is WeaponUpgradeData: continue
		var upgrade_data = upgrade_data_res as WeaponUpgradeData
		
		# Check if the upgrade has already been acquired
		var acquired_flag_key_to_check: StringName = &""
		if upgrade_data.set_acquired_flag_on_weapon != &"":
			acquired_flag_key_to_check = upgrade_data.set_acquired_flag_on_weapon
		elif upgrade_data.max_stacks == 1: # For single-stack upgrades without explicit flag, generate a default flag.
			acquired_flag_key_to_check = StringName(str(upgrade_data.upgrade_id) + "_acquired")
		
		# If a flag key exists, check if the weapon already has that flag.
		if acquired_flag_key_to_check != &"" and specific_stats.get(acquired_flag_key_to_check, false) == true:
			continue # Skip if already acquired
		
		# Check prerequisites
		var prerequisites_met = true
		for prereq_id_sname in upgrade_data.prerequisites_on_this_weapon:
			var prereq_upgrade_def = weapon_bp.get_upgrade_by_id(prereq_id_sname)
			var prereq_flag_key_to_check: StringName = &""
			
			if is_instance_valid(prereq_upgrade_def) and prereq_upgrade_def.set_acquired_flag_on_weapon != &"":
				prereq_flag_key_to_check = prereq_upgrade_def.set_acquired_flag_on_weapon
			elif is_instance_valid(prereq_upgrade_def):
				prereq_flag_key_to_check = StringName(str(prereq_upgrade_def.upgrade_id) + "_acquired")
			else:
				push_warning("game.gd: Prerequisite upgrade '", prereq_id_sname, "' for '", upgrade_data.upgrade_id, "' not found in blueprint. Skipping this upgrade.")
				prerequisites_met = false; break # Prereq not found, so not met.

			if not specific_stats.get(prereq_flag_key_to_check, false) == true:
				prerequisites_met = false; break # Prereq flag not set
		
		if not prerequisites_met: continue # Skip if prerequisites are not met
		
		valid_next_upgrades.append(upgrade_data)
	return valid_next_upgrades

# --- Level Up Logic ---
# Handles player leveling up, pausing the game, and displaying upgrade options.
func _on_player_level_up(_new_level: int):
	# Ensure player node is valid. If not, unpause and exit.
	if not is_instance_valid(player_node):
		get_tree().paused = false
		push_error("game.gd: Player node is invalid on level-up. Cannot display upgrades.")
		return
	
	get_tree().paused = true # Pause the game for level-up screen
	
	# Clean up any existing level-up screen instance
	if is_instance_valid(level_up_screen_instance):
		level_up_screen_instance.queue_free()
		level_up_screen_instance = null
	
	# Load the level-up screen scene
	if not is_instance_valid(LEVEL_UP_SCREEN_SCENE):
		get_tree().paused = false
		push_error("game.gd: LEVEL_UP_SCREEN_SCENE preload is invalid. Cannot display upgrades.")
		return
	
	level_up_screen_instance = LEVEL_UP_SCREEN_SCENE.instantiate()
	if not is_instance_valid(level_up_screen_instance):
		get_tree().paused = false
		push_error("game.gd: Failed to instantiate level-up screen. Cannot display upgrades.")
		return
	
	var chosen_options: Array = _get_upgrade_options_for_player() # Get available upgrade options
	
	if chosen_options.is_empty(): # If no upgrades are available, unpause and exit
		if is_instance_valid(level_up_screen_instance): level_up_screen_instance.queue_free()
		get_tree().paused = false
		push_warning("game.gd: No upgrade options available for player level-up. Skipping level-up screen.")
		return
		
	# Display options to the player
	if level_up_screen_instance.has_method("display_options"):
		# Use call_deferred to ensure the level-up screen is ready in the tree before display.
		level_up_screen_instance.call_deferred("display_options", chosen_options)
	else:
		get_tree().paused = false
		push_error("game.gd: Level-up screen instance is missing 'display_options' method.")
		return
	
	add_child(level_up_screen_instance) # Add the level-up screen to the scene tree
	
	# Connect to the 'upgrade_chosen' signal from the level-up screen
	if level_up_screen_instance.has_signal("upgrade_chosen"):
		if not level_up_screen_instance.is_connected("upgrade_chosen", Callable(self, "_on_upgrade_chosen")):
			level_up_screen_instance.upgrade_chosen.connect(Callable(self, "_on_upgrade_chosen"))
	else:
		push_warning("game.gd: Level-up screen instance is missing 'upgrade_chosen' signal.")
	
	level_up_screen_instance.process_mode = Node.PROCESS_MODE_ALWAYS # Ensure UI processes while game is paused

# Generates a list of upgrade options for the player to choose from.
# This function aims to prevent duplicate upgrades in the same selection.
func _get_upgrade_options_for_player() -> Array:
	var options_pool: Array = []
	var offered_ids_this_run: Array = []

	# 1. Get General Upgrades
	for card_res in loaded_general_upgrades:
		if is_instance_valid(card_res) and not offered_ids_this_run.has(card_res.id):
			var card_presentation = {
				"id_for_card_selection": card_res.id,
				"title": card_res.title,
				"description": card_res.description,
				# FIXED: Check if the icon is valid before accessing its resource_path.
				"icon_path": card_res.icon.resource_path if is_instance_valid(card_res.icon) else "",
				"type": "general_upgrade",
				"resource_data": card_res
			}
			options_pool.append(card_presentation)
			offered_ids_this_run.append(card_res.id)

	# 2. Get Weapon Upgrades
	if is_instance_valid(player_node) and player_node.has_method("get_active_weapons_data_for_level_up"):
		var player_active_weapons: Array[Dictionary] = player_node.get_active_weapons_data_for_level_up()
		for active_weapon_dict in player_active_weapons:
			var weapon_id_sname = active_weapon_dict.get("id") as StringName
			if weapon_id_sname == &"": continue
			
			var next_upgrades: Array[WeaponUpgradeData] = get_weapon_next_level_upgrades(str(weapon_id_sname), active_weapon_dict)
			for upgrade_res in next_upgrades:
				var unique_selection_id = str(weapon_id_sname) + "_" + str(upgrade_res.upgrade_id)
				if not offered_ids_this_run.has(unique_selection_id):
					var upgrade_card_presentation = {
						"id_for_card_selection": unique_selection_id,
						"title": upgrade_res.title,
						"description": upgrade_res.description,
						# FIXED: Check if the icon is valid before accessing its resource_path.
						"icon_path": upgrade_res.icon.resource_path if is_instance_valid(upgrade_res.icon) else "",
						"type": "weapon_upgrade",
						"weapon_id_to_upgrade": weapon_id_sname,
						"resource_data": upgrade_res
					}
					options_pool.append(upgrade_card_presentation)
					offered_ids_this_run.append(unique_selection_id)

	# 3. Get New Weapons if slots are available
	if is_instance_valid(player_node) and player_node.has_method("get_active_weapons_data_for_level_up"):
		var current_player_weapons = player_node.get_active_weapons_data_for_level_up()
		if current_player_weapons.size() < player_node.weapon_manager.max_weapons:
			var potential_new_weapons_pool : Array = []
			for bp_data in all_loaded_weapon_blueprints:
				if not is_instance_valid(bp_data): continue
				var bp_id_sname = bp_data.id
				var already_have_it = false
				for p_wep_dict in current_player_weapons:
					if p_wep_dict.get("id") == bp_id_sname: already_have_it = true; break
				
				if not already_have_it and not offered_ids_this_run.has(bp_id_sname):
					var new_weapon_offer_presentation = {
						"id_for_card_selection": bp_id_sname,
						"type": "new_weapon",
						"title": bp_data.title,
						"description": bp_data.description,
						# FIXED: Check if the icon is valid before accessing its resource_path.
						"icon_path": bp_data.icon.resource_path if is_instance_valid(bp_data.icon) else "",
						"resource_data": bp_data
					}
					potential_new_weapons_pool.append(new_weapon_offer_presentation)
					offered_ids_this_run.append(bp_id_sname)
			
			if not potential_new_weapons_pool.is_empty():
				options_pool.append(potential_new_weapons_pool.pick_random())

	# Final Selection Logic
	options_pool.shuffle()
	var final_chosen_options: Array = []
	for option_data_dict in options_pool:
		if final_chosen_options.size() >= 3: break
		final_chosen_options.append(option_data_dict)
			
	if final_chosen_options.is_empty():
		final_chosen_options.append({"title": "Continue", "description": "No new upgrades this level.", "type": "skip"})
	
	return final_chosen_options

# Called when the player chooses an upgrade from the level-up screen.
func _on_upgrade_chosen(chosen_upgrade_data_wrapper: Dictionary):
	if not is_instance_valid(player_node) or not player_node.has_method("apply_upgrade"):
		get_tree().paused = false
		push_error("game.gd: Player node is invalid or missing 'apply_upgrade' method on upgrade chosen.")
		return
	
	if chosen_upgrade_data_wrapper.get("type") != "skip":
		player_node.apply_upgrade(chosen_upgrade_data_wrapper)
		
	# Clean up the level-up screen and unpause the game.
	if is_instance_valid(level_up_screen_instance):
		level_up_screen_instance.queue_free()
		level_up_screen_instance = null
	get_tree().paused = false

# Handles player death, pauses game, and instantiates game over screen.
func _on_player_has_died():
	if is_instance_valid(enemy_spawn_timer): enemy_spawn_timer.stop()
	if is_instance_valid(culling_check_timer): culling_check_timer.stop()
	
	# Stop physics processing for all enemies in container
	if is_instance_valid(enemies_container):
		for enemy_child in enemies_container.get_children():
			if is_instance_valid(enemy_child) and enemy_child.has_method("set_physics_process"):
				enemy_child.set_physics_process(false)
	
	var game_over_scene_res = load(GAME_OVER_SCREEN_SCENE.resource_path) as PackedScene
	if is_instance_valid(game_over_scene_res):
		if is_instance_valid(game_over_screen_instance): game_over_screen_instance.queue_free() # Ensure no old instance
		game_over_screen_instance = game_over_scene_res.instantiate()
		add_child(game_over_screen_instance)
		
		# Connect to restart signal
		if game_over_screen_instance.has_signal("restart_game_requested"):
			if not game_over_screen_instance.is_connected("restart_game_requested", Callable(self, "_on_restart_game_requested")):
				game_over_screen_instance.restart_game_requested.connect(Callable(self, "_on_restart_game_requested"))
		
		game_over_screen_instance.process_mode = Node.PROCESS_MODE_ALWAYS # Ensure UI processes while game is paused
		get_tree().paused = true
	else:
		push_error("game.gd: Game Over Screen scene could not be loaded or is invalid.")

# Handles request to restart the game from the game over screen.
func _on_restart_game_requested():
	if is_instance_valid(game_over_screen_instance):
		game_over_screen_instance.queue_free()
	get_tree().paused = false # Unpause before reloading scene
	var error_code = get_tree().reload_current_scene() # Reload the current scene
	if error_code != OK: push_error("game.gd: Failed to reload scene. Error Code: ", error_code)

func _on_player_class_tier_upgraded(new_class_id: String, _contributing_basic_classes: Array):
	print("game.gd: Player class tier upgraded to ", new_class_id)
	pass # Implement specific logic here if needed

func _on_difficulty_tier_increased(new_tier: int):
	print("game.gd: Difficulty tier increased to ", new_tier)
	pass # Implement specific logic here if needed


# --- DEBUG SETTERS for game.gd parameters ---
# These functions allow external debug tools (like a debug panel) to modify
# game parameters at runtime. They often trigger recalculations.
func debug_set_dds_spawn_rate_factor(value: float):
	dds_spawn_rate_factor = maxf(0.0001, value)
	_update_spawn_interval_from_dds()
	print("game.gd DEBUG: dds_spawn_rate_factor set to: ", dds_spawn_rate_factor)

func debug_set_hardcore_spawn_rate_multiplier(value: float):
	hardcore_spawn_rate_multiplier = maxf(0.1, value)
	_update_spawn_interval_from_dds()
	print("game.gd DEBUG: hardcore_spawn_rate_multiplier set to: ", hardcore_spawn_rate_multiplier)

func debug_set_base_spawn_interval(value: float):
	base_spawn_interval = maxf(0.05, value)
	_update_spawn_interval_from_dds()
	print("game.gd DEBUG: base_spawn_interval set to: ", base_spawn_interval)

func debug_set_min_spawn_interval(value: float):
	min_spawn_interval = maxf(0.01, value)
	_update_spawn_interval_from_dds()
	print("game.gd DEBUG: min_spawn_interval set to: ", min_spawn_interval)

func debug_set_enemies_per_batch(value: int):
	# This function is now deprecated in favor of _get_current_enemies_per_batch()
	# which scales with DDS. It's left here for compatibility if external debug tools
	# still try to call it, but its effect will be limited.
	enemies_per_batch_calculated = max(1, value) # Directly set the calculated variable
	print("game.gd DEBUG: enemies_per_batch set to (manual override, will be scaled by DDS unless debug_override_target_enemies is used): ", enemies_per_batch_calculated)

func debug_set_active_pool_refresh_dds_interval(value: float):
	active_pool_refresh_dds_interval = maxf(5.0, value)
	print("game.gd DEBUG: active_pool_refresh_dds_interval set to: ", active_pool_refresh_dds_interval)

func debug_set_max_active_enemy_types(value: int):
	max_active_enemy_types = max(1, value)
	_refresh_active_enemy_pool() # Refresh pool immediately to reflect change
	print("game.gd DEBUG: max_active_enemy_types set to: ", max_active_enemy_types)

func debug_set_enemy_count_update_dds_interval(value: float):
	enemy_count_update_dds_interval = maxf(5.0, value)
	print("game.gd DEBUG: enemy_count_update_dds_interval set to: ", enemy_count_update_dds_interval)

func debug_set_target_on_screen_enemies_override(enable: bool, value: int = -1):
	debug_override_target_enemies = enable
	if enable and value >= 0:
		debug_target_enemies_value = max(1, value)
		_update_target_on_screen_enemies() # Update target immediately
		print("game.gd DEBUG: Target enemies OVERRIDDEN to: ", target_on_screen_enemies)
	elif not enable:
		_update_target_on_screen_enemies() # Revert to DDS-based calculation
		print("game.gd DEBUG: Target enemies override REMOVED. Current target: ", target_on_screen_enemies)

func debug_set_threat_pool_spawn_threshold(value: int):
	threat_pool_spawn_threshold = max(1, value)
	print("game.gd DEBUG: threat_pool_spawn_threshold set to: ", threat_pool_spawn_threshold)

func debug_set_threat_pool_batch_multiplier(value: float):
	threat_pool_batch_multiplier = maxf(0.1, value)
	print("game.gd DEBUG: threat_pool_batch_multiplier set to: ", threat_pool_batch_multiplier)

func debug_set_culling_timer_wait_time(value: float):
	culling_timer_wait_time = maxf(0.5, value)
	if is_instance_valid(culling_check_timer):
		culling_check_timer.wait_time = culling_timer_wait_time
		if not culling_check_timer.is_stopped(): culling_check_timer.start() # Restart to apply new wait_time
	print("game.gd DEBUG: culling_timer_wait_time set to: ", culling_timer_wait_time)

func debug_set_random_event_check_interval(value: float):
	random_event_check_interval = maxf(1.0, value)
	print("game.gd DEBUG: random_event_check_interval set to: ", random_event_check_interval)

func debug_set_forward_spawn_bias_chance(value: float):
	forward_spawn_bias_chance = clampf(value, 0.0, 1.0)
	print("game.gd DEBUG: forward_spawn_bias_chance set to: ", forward_spawn_bias_chance)

func debug_set_spawn_margin(value: float):
	spawn_margin = maxf(10.0, value)
	print("game.gd DEBUG: spawn_margin set to: ", spawn_margin)

# Resets all tunable game parameters to their original default constants.
func debug_reset_game_parameters_to_defaults():
	spawn_margin = ORIGINAL_SPAWN_MARGIN
	player_movement_threshold = ORIGINAL_PLAYER_MOVEMENT_THRESHOLD
	forward_spawn_bias_chance = ORIGINAL_FORWARD_SPAWN_BIAS_CHANCE
	base_spawn_interval = ORIGINAL_BASE_SPAWN_INTERVAL
	min_spawn_interval = ORIGINAL_MIN_SPAWN_INTERVAL
	enemies_per_batch_calculated = ORIGINAL_ENEMIES_PER_BATCH # Reset calculated variable
	dds_spawn_rate_factor = ORIGINAL_DDS_SPAWN_RATE_FACTOR
	hardcore_spawn_rate_multiplier = ORIGINAL_HARDCORE_SPAWN_RATE_MULTIPLIER
	max_active_enemy_types = ORIGINAL_MAX_ACTIVE_ENEMY_TYPES
	active_pool_refresh_dds_interval = ORIGINAL_ACTIVE_POOL_REFRESH_DDS_INTERVAL
	enemy_count_update_dds_interval = ORIGINAL_ENEMY_COUNT_UPDATE_DDS_INTERVAL
	debug_override_target_enemies = false
	threat_pool_spawn_threshold = ORIGINAL_THREAT_POOL_SPAWN_THRESHOLD
	threat_pool_batch_multiplier = ORIGINAL_THREAT_POOL_BATCH_MULTIPLIER
	culling_timer_wait_time = ORIGINAL_CULLING_TIMER_WAIT_TIME
	
	if is_instance_valid(culling_check_timer):
		culling_check_timer.wait_time = culling_timer_wait_time # Apply new wait time
	
	random_event_check_interval = ORIGINAL_RANDOM_EVENT_CHECK_INTERVAL
	
	# Trigger recalculations based on reset values
	_update_spawn_interval_from_dds()
	_update_target_on_screen_enemies()
	_refresh_active_enemy_pool()
	
	print("game.gd DEBUG: All tunable game parameters reset to defaults.")

# --- Debug spawn function for specific enemies ---
func debug_spawn_specific_enemy(enemy_id: StringName, elite_type_override: StringName, count: int, near_player: bool):
	print("game.gd: DEBUG SPAWN REQUEST - ID: ", enemy_id, ", Elite: ", elite_type_override, ", Count: ", count, ", Near Player: ", near_player)

	if not is_instance_valid(player_node):
		push_error("game.gd ERROR: Player node is not valid. Cannot spawn enemies."); return
	if not is_instance_valid(enemies_container):
		push_error("game.gd ERROR: Enemies container is not valid. Cannot spawn enemies."); return
	# Ensure the debug helper method exists, which it should as it's defined below
	if not has_method("get_enemy_data_by_id_for_debug"):
		push_error("game.gd ERROR: Missing 'get_enemy_data_by_id_for_debug' method."); return

	var enemy_data_to_spawn: EnemyData = get_enemy_data_by_id_for_debug(enemy_id)

	if not is_instance_valid(enemy_data_to_spawn):
		push_error("game.gd ERROR: EnemyData not found for ID: ", enemy_id, ". Cannot spawn."); return

	for i in range(count):
		# Break if max target enemies is reached, plus a small buffer to avoid overspawning massively
		# This uses the dynamically calculated 'target_on_screen_enemies'
		if current_active_enemy_count >= target_on_screen_enemies * 2:
			print("game.gd: Aborting debug spawn, current_active_enemy_count (", current_active_enemy_count, ") exceeds target (", target_on_screen_enemies, ").")
			break

		var spawn_position = _calculate_spawn_position_for_enemy(near_player)
		_spawn_actual_enemy(enemy_data_to_spawn, spawn_position, elite_type_override)
		print("game.gd: Spawned enemy: ", enemy_data_to_spawn.display_name, " (Elite: ", elite_type_override, ") at ", spawn_position)
