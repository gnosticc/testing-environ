# game.gd
# Main game logic.
# Corrected LEVEL_UP_SCREEN_SCENE preload to point to NewLevelUpScreen.tscn
# _get_upgrade_options_for_player is still simplified for this test.
extends Node2D

# --- Preloads ---
const GAME_OVER_SCREEN_SCENE = preload("res://Scenes/UI/GameOverScreen.tscn")
const LEVEL_UP_SCREEN_SCENE = preload("res://Scenes/UI/NewLevelUpScreen.tscn") # CORRECTED PATH)

@onready var enemy_spawn_timer: Timer = $EnemySpawnTimer
@onready var enemies_container: Node2D = $EnemiesContainer
@onready var drops_container: Node2D = $DropsContainer
@onready var boss_container: Node2D = $BossContainer 
var camera: Camera2D
var game_ui_node
var game_over_screen_instance
var level_up_screen_instance
var player_node: PlayerCharacter

# --- Spawn Configuration (Tunable) ---
@export var spawn_margin: float = 100.0
@export var player_movement_threshold: float = 20.0 
@export var forward_spawn_bias_chance: float = 0.75 
var base_spawn_interval: float = 3.5 
var min_spawn_interval: float = 0.25 
var current_spawn_interval: float
var enemies_per_batch: int = 3 

const ORIGINAL_SPAWN_MARGIN: float = 100.0
const ORIGINAL_PLAYER_MOVEMENT_THRESHOLD: float = 20.0
const ORIGINAL_FORWARD_SPAWN_BIAS_CHANCE: float = 0.75
const ORIGINAL_BASE_SPAWN_INTERVAL: float = 3.5
const ORIGINAL_MIN_SPAWN_INTERVAL: float = 0.25
const ORIGINAL_ENEMIES_PER_BATCH: int = 3

# --- DDS & Difficulty Scaling (Tunable) ---
var current_dds: float = 0.0
var is_currently_hardcore_phase: bool = false
var dds_spawn_rate_factor: float = 0.0020 
var hardcore_spawn_rate_multiplier: float = 1.75 

const ORIGINAL_DDS_SPAWN_RATE_FACTOR: float = 0.0020
const ORIGINAL_HARDCORE_SPAWN_RATE_MULTIPLIER: float = 1.75

# --- Enemy Definitions & Active Pool (Tunable) ---
@export var enemy_data_files: Array[String] = [
	"res://DataResources/Enemies/slime_green_data.tres",
	"res://DataResources/Enemies/slime_blue_data.tres", 
	"res://DataResources/Enemies/slime_red_data.tres",   
	"res://DataResources/Enemies/slime_tall_light_blue_data.tres" 
]
var loaded_enemy_definitions: Array[EnemyData] = []

var max_active_enemy_types: int = 7 
var current_active_enemy_pool: Array[EnemyData] = []
var last_active_pool_refresh_dds: float = -200.0 
var active_pool_refresh_dds_interval: float = 20.0 

const ORIGINAL_MAX_ACTIVE_ENEMY_TYPES: int = 7
const ORIGINAL_ACTIVE_POOL_REFRESH_DDS_INTERVAL: float = 20.0

# --- Enemy Count Management (Tunable) ---
var current_active_enemy_count: int = 0
var target_on_screen_enemies: int = 15 
var enemy_count_update_dds_interval: float = 35.0 
var last_enemy_count_update_dds: float = -100.0 
var debug_override_target_enemies: bool = false
var debug_target_enemies_value: int = 15

const ORIGINAL_ENEMY_COUNT_UPDATE_DDS_INTERVAL: float = 35.0

# --- Global Threat Pool (Tunable) ---
var global_unspent_threat_pool: int = 0
var threat_pool_spawn_threshold: int = 25 
var threat_pool_batch_multiplier: float = 1.5 
var culling_check_timer: Timer 
var culling_timer_wait_time: float = 3.0

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
var random_event_check_interval: float = 35.0 
var random_event_miss_streak: int = 0
var current_event_active: bool = false
var current_event_id: String = ""
var current_event_end_timer: Timer = null

const ORIGINAL_RANDOM_EVENT_CHECK_INTERVAL: float = 35.0

# --- Weapon Blueprint Loading (NEW SYSTEM) ---
@export var weapon_blueprint_files: Array[String] = [
	"res://DataResources/Weapons/Scythe/scythe_blueprint.tres" 
]
var all_loaded_weapon_blueprints: Array[WeaponBlueprintData] = [] 
var weapon_blueprints_by_id: Dictionary = {} 

# --- General Upgrades (To be replaced by GeneralUpgradeCardData resources later) ---
@export var general_upgrade_card_paths: Array[String] = [] 
var loaded_general_upgrades: Array[GeneralUpgradeCardData] = [] 
var _temp_old_general_stat_upgrades: Array[Dictionary] = [ 
	{"id": "gen_max_health_1", "title": "Vitality", "description": "Increases Max Health by 20.", "type": "stat_boost_flat", "stat_key_target": "max_health", "value": 20.0, "modification_type": "flat_add", "target_scope": "player_stats"},
	{"id": "gen_speed_1", "title": "Swiftness", "description": "Increases Movement Speed by 7%.", "type": "stat_boost_percent", "stat_key_target": "movement_speed", "value": 0.07, "modification_type": "percent_add_to_base", "target_scope": "player_stats"},
	{"id": "gen_might_1", "title": "Might", "description": "Increases global flat damage by 3.", "type": "stat_boost_flat", "stat_key_target": "global_flat_damage_add", "value": 3.0, "modification_type": "flat_add", "target_scope": "player_stats"}
]

signal weapon_blueprints_ready


func _ready():
	_load_all_weapon_blueprints() 
	_test_print_loaded_weapon_blueprints() 
	_load_all_general_upgrades()
	emit_signal("weapon_blueprints_ready") 

	current_spawn_interval = base_spawn_interval 
	camera = get_viewport().get_camera_2d()

	for path in enemy_data_files:
		var enemy_data_res = load(path) as EnemyData
		if enemy_data_res: loaded_enemy_definitions.append(enemy_data_res)
		else: print("ERROR (game.gd): Failed to load EnemyData resource at: ", path)
	if not loaded_enemy_definitions.is_empty():
		loaded_enemy_definitions.sort_custom(func(a,b): return a.min_DDS_to_spawn < b.min_DDS_to_spawn)

	game_ui_node = get_node_or_null("GameUI")
	if is_instance_valid(game_ui_node):
		if game_ui_node.has_signal("dds_changed"):
			if not game_ui_node.is_connected("dds_changed", Callable(self, "_on_dds_changed")):
				game_ui_node.dds_changed.connect(Callable(self, "_on_dds_changed"))
		if game_ui_node.has_method("get_dynamic_difficulty_score"): current_dds = game_ui_node.get_dynamic_difficulty_score()
		if game_ui_node.has_method("is_in_hardcore_phase"): is_currently_hardcore_phase = game_ui_node.is_in_hardcore_phase()
		
		_update_target_on_screen_enemies(); last_enemy_count_update_dds = current_dds
		_refresh_active_enemy_pool(); last_active_pool_refresh_dds = current_dds
		if game_ui_node.has_method("update_culled_enemies_display"): game_ui_node.update_culled_enemies_display(current_active_enemy_count)
		if game_ui_node.has_method("update_threat_pool_display"): game_ui_node.update_threat_pool_display(global_unspent_threat_pool)
	else: print("ERROR (game.gd): GameUI node not found.")

	if not is_instance_valid(camera):
		if is_instance_valid(enemy_spawn_timer): enemy_spawn_timer.stop()
	else:
		if is_instance_valid(enemy_spawn_timer):
			enemy_spawn_timer.wait_time = current_spawn_interval
			if not enemy_spawn_timer.is_connected("timeout", Callable(self, "_on_enemy_spawn_timer_timeout")):
				enemy_spawn_timer.timeout.connect(Callable(self, "_on_enemy_spawn_timer_timeout"))
			enemy_spawn_timer.start()

	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		player_node = players[0] as PlayerCharacter
		if player_node.has_signal("player_has_died"): player_node.player_has_died.connect(Callable(self, "_on_player_has_died"))
		if player_node.has_signal("player_level_up"): player_node.player_level_up.connect(Callable(self, "_on_player_level_up"))
		if player_node.has_signal("player_class_tier_upgraded"): player_node.player_class_tier_upgraded.connect(Callable(self, "_on_player_class_tier_upgraded"))
	
	_update_spawn_interval_from_dds()

	culling_check_timer = Timer.new(); culling_check_timer.name = "EnemyCullingTimer"
	culling_check_timer.wait_time = culling_timer_wait_time 
	culling_check_timer.one_shot = false
	culling_check_timer.timeout.connect(Callable(self, "_on_culling_check_timer_timeout"))
	add_child(culling_check_timer); culling_check_timer.start()

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
				print_debug("ERROR (game.gd): WeaponBlueprintData at '", path, "' has an empty ID.")
		else:
			print_debug("ERROR (game.gd): Failed to load WeaponBlueprintData from path: ", path)

func _load_all_general_upgrades(): 
	loaded_general_upgrades.clear()
	for path in general_upgrade_card_paths:
		var card_res = load(path) as GeneralUpgradeCardData
		if is_instance_valid(card_res):
			loaded_general_upgrades.append(card_res)
		else:
			print_debug("ERROR (game.gd): Failed to load GeneralUpgradeCardData from path: ", path)


func _test_print_loaded_weapon_blueprints():
	print_debug("--- Loaded Weapon Blueprints Test ---")
	if all_loaded_weapon_blueprints.is_empty():
		print_debug("No weapon blueprints were loaded or found in 'weapon_blueprint_files' array.")
		return

	for bp_data in all_loaded_weapon_blueprints:
		if not is_instance_valid(bp_data):
			print_debug("  Found an invalid blueprint in the loaded list.")
			continue
		
		print_debug("Weapon ID: '", bp_data.id, "', Title: '", bp_data.title, "'")
		var scene_path_str = "N/A"
		if is_instance_valid(bp_data.weapon_scene) and bp_data.weapon_scene.resource_path != "":
			scene_path_str = bp_data.weapon_scene.resource_path
		print_debug("  Scene: ", scene_path_str)
		print_debug("  Cooldown: ", bp_data.cooldown, ", Max Level: ", bp_data.max_level)
		print_debug("  Initial Specific Stats: ", bp_data.initial_specific_stats)
		print_debug("  Available Upgrades (%s):" % bp_data.available_upgrades.size())
		for upgrade_res_idx in range(bp_data.available_upgrades.size()):
			var upgrade_res = bp_data.available_upgrades[upgrade_res_idx]
			if upgrade_res is WeaponUpgradeData:
				var upg_data = upgrade_res as WeaponUpgradeData
				print_debug("    - Upgrade [", upgrade_res_idx, "] ID: '", upg_data.upgrade_id, "', Title: '", upg_data.title, "'")
				print_debug("      Effects (%s):" % upg_data.effects.size())
				for effect_res_idx in range(upg_data.effects.size()):
					var effect_res = upg_data.effects[effect_res_idx]
					if not is_instance_valid(effect_res):
						print_debug("        Effect [", effect_res_idx, "]: Invalid resource.")
						continue
					print_debug("        Effect [", effect_res_idx, "] TypeID: '", effect_res.effect_type_id, "' (Class: '", effect_res.get_class(),"')")
					
					if effect_res is StatModificationEffectData:
						var stat_mod = effect_res as StatModificationEffectData
						# CORRECTED: Use get_value() instead of .value
						var effect_val = stat_mod.get_value() 
						print_debug("          StatMod: Scope='", stat_mod.target_scope, "', Key='", stat_mod.stat_key, "', Type='", stat_mod.modification_type, "', Val=", effect_val)
					
					elif effect_res is CustomFlagEffectData:
						var flag_mod = effect_res as CustomFlagEffectData
						# Corrected to use target_scope from base class
						print_debug("          FlagMod: Scope='", flag_mod.target_scope, "', Key='", flag_mod.flag_key, "', Val=", flag_mod.flag_value)
					
					elif effect_res is TriggerAbilityEffectData:
						var trigger_mod = effect_res as TriggerAbilityEffectData
						# Corrected to use target_scope from base class
						print_debug("          TriggerAbility: Scope='", trigger_mod.target_scope, "', ID='", trigger_mod.ability_id, "', Params=", trigger_mod.ability_params)
					
					elif effect_res is StatusEffectApplicationData:
						var status_app_mod = effect_res as StatusEffectApplicationData
						# Corrected to use target_scope from base class
						print_debug("          StatusApp: Scope='", status_app_mod.target_scope, "', Path='", status_app_mod.status_effect_resource_path, "', Chance=", status_app_mod.application_chance, ", DurationOvr=", status_app_mod.duration_override)
					
					else:
						print_debug("          Unknown/Base EffectData: DevNote='", effect_res.developer_note, "'")
			else:
				print_debug("    - Invalid upgrade resource found at index ", upgrade_res_idx, " in blueprint's available_upgrades array. Type: ", typeof(upgrade_res))
		print_debug("---")

func _physics_process(delta: float):
	if current_boss_active or current_event_active: return
	if not current_boss_active and not current_event_active:
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

func _on_dds_changed(new_dds_score: float):
	var previous_dds_for_bucketing = current_dds 
	current_dds = new_dds_score 
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("is_in_hardcore_phase"):
		is_currently_hardcore_phase = game_ui_node.is_in_hardcore_phase()
	_update_spawn_interval_from_dds()
	var old_enemy_count_bucket = floor(previous_dds_for_bucketing / enemy_count_update_dds_interval)
	var new_enemy_count_bucket = floor(new_dds_score / enemy_count_update_dds_interval)
	if new_enemy_count_bucket > old_enemy_count_bucket or last_enemy_count_update_dds < 0: 
		_update_target_on_screen_enemies(); last_enemy_count_update_dds = new_dds_score
	var old_dds_bucket_pool = floor(previous_dds_for_bucketing / active_pool_refresh_dds_interval)
	var new_dds_bucket_pool = floor(new_dds_score / active_pool_refresh_dds_interval)
	if new_dds_bucket_pool > old_dds_bucket_pool or last_active_pool_refresh_dds < 0: 
		_refresh_active_enemy_pool(); last_active_pool_refresh_dds = new_dds_score

func _update_target_on_screen_enemies():
	if debug_override_target_enemies:
		target_on_screen_enemies = debug_target_enemies_value
		return 
	var time_elapsed_minutes = 0.0
	if is_instance_valid(game_ui_node) and game_ui_node.has_method("get_elapsed_seconds"):
		time_elapsed_minutes = float(game_ui_node.get_elapsed_seconds()) / 60.0
	var calculated_target: int
	if time_elapsed_minutes < 6.0: calculated_target = int(lerpf(10.0, 30.0, time_elapsed_minutes / 6.0))
	elif time_elapsed_minutes < 8.0: calculated_target = int(lerpf(30.0, 40.0, (time_elapsed_minutes - 6.0) / 2.0))
	elif current_dds < 800: calculated_target = int(lerpf(40.0, 80.0, current_dds / 800.0))
	elif current_dds < 2500: calculated_target = int(lerpf(80.0, 150.0, (current_dds - 800.0) / 1700.0))
	elif current_dds < 4000: calculated_target = int(lerpf(150.0, 200.0, (current_dds - 2500.0) / 1500.0))
	else: calculated_target = 200
	if is_currently_hardcore_phase:
		target_on_screen_enemies = int(calculated_target * 1.35); target_on_screen_enemies = min(target_on_screen_enemies, 275)
	else: target_on_screen_enemies = clamp(calculated_target, 10, 200)

func _update_spawn_interval_from_dds():
	if is_instance_valid(enemy_spawn_timer):
		var interval_divisor = 1.0 + (dds_spawn_rate_factor * current_dds)
		if is_currently_hardcore_phase: interval_divisor *= hardcore_spawn_rate_multiplier
		current_spawn_interval = base_spawn_interval / interval_divisor
		current_spawn_interval = max(min_spawn_interval, current_spawn_interval)
		enemy_spawn_timer.wait_time = current_spawn_interval
		if enemy_spawn_timer.is_stopped() and not current_boss_active and not current_event_active : enemy_spawn_timer.start()
		elif not enemy_spawn_timer.is_stopped(): enemy_spawn_timer.start()

func _refresh_active_enemy_pool():
	if loaded_enemy_definitions.is_empty(): return
	print_debug("--- Refreshing Active Enemy Pool (DDS: %.1f) ---" % current_dds)
	var dds_eligible_enemies: Array[EnemyData] = []
	for enemy_data_res in loaded_enemy_definitions:
		if not is_instance_valid(enemy_data_res): continue 
		var max_dds = enemy_data_res.max_DDS_to_spawn
		if current_dds >= enemy_data_res.min_DDS_to_spawn and \
		   (current_dds < max_dds or max_dds < 0.0): 
			dds_eligible_enemies.append(enemy_data_res)
	current_active_enemy_pool.clear()
	if dds_eligible_enemies.is_empty(): 
		print_debug("No DDS eligible enemies found for active pool.")
		print_debug("---------------------------------------------------")
		return
	dds_eligible_enemies.sort_custom(func(a,b): 
		var relevance_a = abs(current_dds - a.min_DDS_to_spawn)
		var relevance_b = abs(current_dds - b.min_DDS_to_spawn)
		if abs(relevance_a - relevance_b) < 0.01 : return a.spawn_weight > b.spawn_weight 
		return relevance_a < relevance_b
	)
	var temp_pool: Array[EnemyData] = []; var current_slot_cost_filled = 0
	var added_enemy_ids: Dictionary = {}
	for enemy_data in dds_eligible_enemies:
		if added_enemy_ids.has(enemy_data.id): continue
		if current_slot_cost_filled + enemy_data.ideal_active_pool_slot_cost <= max_active_enemy_types:
			temp_pool.append(enemy_data); added_enemy_ids[enemy_data.id] = true
			current_slot_cost_filled += enemy_data.ideal_active_pool_slot_cost
		if current_slot_cost_filled >= max_active_enemy_types: break
	if current_slot_cost_filled < max_active_enemy_types and dds_eligible_enemies.size() > temp_pool.size():
		var remaining_eligible_shuffled = dds_eligible_enemies.filter(func(ed): return not added_enemy_ids.has(ed.id))
		remaining_eligible_shuffled.shuffle()
		for enemy_data in remaining_eligible_shuffled:
			if added_enemy_ids.has(enemy_data.id): continue
			if current_slot_cost_filled + enemy_data.ideal_active_pool_slot_cost <= max_active_enemy_types:
				temp_pool.append(enemy_data); added_enemy_ids[enemy_data.id] = true
				current_slot_cost_filled += enemy_data.ideal_active_pool_slot_cost
			if current_slot_cost_filled >= max_active_enemy_types: break
	current_active_enemy_pool = temp_pool

func _select_enemy_from_active_pool() -> EnemyData:
	if current_active_enemy_pool.is_empty(): return null
	var total_weight: float = 0.0
	for edr in current_active_enemy_pool: total_weight += edr.spawn_weight
	if total_weight <= 0.0: return current_active_enemy_pool.pick_random() if not current_active_enemy_pool.is_empty() else null
	var rand_w = randf() * total_weight; var current_w_sum: float = 0.0
	for edrc in current_active_enemy_pool:
		current_w_sum += edrc.spawn_weight
		if rand_w <= current_w_sum: return edrc
	return current_active_enemy_pool.pick_random() if not current_active_enemy_pool.is_empty() else null

func _calculate_spawn_position_for_enemy(near_player: bool = false, offset_vector: Vector2 = Vector2.ZERO) -> Vector2:
	if not is_instance_valid(camera) or not is_instance_valid(player_node): return Vector2.ZERO
	if near_player:
		var random_angle = randf_range(0, TAU)
		var random_distance = randf_range(75, 125) 
		return player_node.global_position + Vector2.RIGHT.rotated(random_angle) * random_distance + offset_vector
	var spawn_position = Vector2.ZERO
	var viewport_pixel_size = get_viewport().get_visible_rect().size; var camera_current_zoom = camera.zoom
	var world_view_width = viewport_pixel_size.x / camera_current_zoom.x; var world_view_height = viewport_pixel_size.y / camera_current_zoom.y
	var top_left_global = camera.global_position - Vector2(world_view_width / 2.0, world_view_height / 2.0)
	var min_x_visible = top_left_global.x; var max_x_visible = top_left_global.x + world_view_width
	var min_y_visible = top_left_global.y; var max_y_visible = top_left_global.y + world_view_height
	var side = randi() % 4
	if player_node.get_velocity().length_squared() > (player_movement_threshold * player_movement_threshold):
		var player_velocity = player_node.get_velocity(); var forward_side = -1
		if abs(player_velocity.x) > abs(player_velocity.y): forward_side = 3 if player_velocity.x > 0 else 2
		else: forward_side = 1 if player_velocity.y > 0 else 0
		if randf() < forward_spawn_bias_chance: side = forward_side
	match side:
		0: spawn_position = Vector2(randf_range(min_x_visible, max_x_visible), min_y_visible - spawn_margin)
		1: spawn_position = Vector2(randf_range(min_x_visible, max_x_visible), max_y_visible + spawn_margin)
		2: spawn_position = Vector2(min_x_visible - spawn_margin, randf_range(min_y_visible, max_y_visible))
		3: spawn_position = Vector2(max_x_visible + spawn_margin, randf_range(min_y_visible, max_y_visible))
	return spawn_position + offset_vector

func _spawn_actual_enemy(enemy_data: EnemyData, position: Vector2, force_elite_type: StringName = &""):
	if not is_instance_valid(enemy_data) or enemy_data.scene_path.is_empty(): 
		print_debug("ERROR (_spawn_actual_enemy): Invalid enemy_data or empty scene_path for ID: ", enemy_data.id if is_instance_valid(enemy_data) else "UNKNOWN")
		return
	var enemy_scene = load(enemy_data.scene_path) as PackedScene
	if not enemy_scene: print_debug("ERROR (_spawn_actual_enemy): Could not load scene: ", enemy_data.scene_path); return
	
	var enemy_instance = enemy_scene.instantiate() as BaseEnemy
	if not is_instance_valid(enemy_instance): 
		print_debug("ERROR (_spawn_actual_enemy): Failed to instance: ", enemy_data.scene_path)
		return

	enemy_instance.global_position = position
	enemies_container.add_child(enemy_instance) 

	if enemy_instance.has_method("initialize_from_data"): 
		enemy_instance.initialize_from_data(enemy_data)
	
	var dds_contrib_elite = current_dds - enemy_data.min_DDS_to_spawn
	
	if force_elite_type != &"": 
		var can_be_this_elite = enemy_data.elite_types_available.has(force_elite_type)
		if can_be_this_elite or force_elite_type == &"debug_generic_elite":
			if enemy_instance.has_method("make_elite"):
				enemy_instance.make_elite(force_elite_type, dds_contrib_elite, enemy_data)
	else: 
		var elite_c = 0.0
		if current_dds >= enemy_data.min_DDS_for_elites_to_appear:
			elite_c = 0.05 + (dds_contrib_elite * 0.0002); elite_c = clamp(elite_c, 0.0, 0.60)
		if is_currently_hardcore_phase: elite_c = min(0.85, elite_c * 1.5)
		if randf() < elite_c and not enemy_data.elite_types_available.is_empty():
			var chosen_tag = enemy_data.elite_types_available.pick_random()
			if enemy_instance.has_method("make_elite"): 
				enemy_instance.make_elite(chosen_tag, dds_contrib_elite, enemy_data)
	
	if not enemy_instance.is_elite and "experience_to_drop" in enemy_instance:
		enemy_instance.experience_to_drop = enemy_data.base_exp_drop
	
func _on_enemy_spawn_timer_timeout():
	if not is_instance_valid(camera) or not is_instance_valid(player_node): return
	if current_boss_active or current_event_active: return
	var spawned_from_threat = false
	if global_unspent_threat_pool >= threat_pool_spawn_threshold:
		var num_threat_spawn = int(ceil(enemies_per_batch * threat_pool_batch_multiplier))
		for _i in range(num_threat_spawn):
			if current_active_enemy_count >= target_on_screen_enemies + enemies_per_batch: break
			var enemy_data = _select_enemy_from_active_pool()
			if is_instance_valid(enemy_data): _spawn_actual_enemy(enemy_data, _calculate_spawn_position_for_enemy())
		global_unspent_threat_pool = max(0, global_unspent_threat_pool - threat_pool_spawn_threshold)
		if is_instance_valid(game_ui_node) and game_ui_node.has_method("update_threat_pool_display"):
			game_ui_node.update_threat_pool_display(global_unspent_threat_pool)
		spawned_from_threat = true
	if current_active_enemy_count < target_on_screen_enemies or spawned_from_threat:
		var num_regular_spawn = enemies_per_batch
		if spawned_from_threat and enemies_per_batch > 1 : num_regular_spawn = max(1, enemies_per_batch / 2)
		for _i in range(num_regular_spawn):
			if current_active_enemy_count >= target_on_screen_enemies + (enemies_per_batch / 2): break
			var enemy_data = _select_enemy_from_active_pool()
			if is_instance_valid(enemy_data): _spawn_actual_enemy(enemy_data, _calculate_spawn_position_for_enemy())

func _on_culling_check_timer_timeout():
	if not is_instance_valid(player_node) or not is_instance_valid(camera): return
	if current_boss_active or current_event_active: return
	var cull_dist_sq = pow(get_viewport().get_visible_rect().size.length() * 1.75, 2)
	for child_node in enemies_container.get_children().duplicate():
		if child_node is BaseEnemy:
			var enemy = child_node as BaseEnemy
			if is_instance_valid(enemy) and not enemy.is_dead_flag:
				if enemy.global_position.distance_squared_to(player_node.global_position) > cull_dist_sq:
					if enemy.has_method("cull_self_and_report_threat"): enemy.cull_self_and_report_threat()

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
	for bp_data in all_loaded_weapon_blueprints:
		if is_instance_valid(bp_data) and bp_data.id == weapon_id_to_find:
			return bp_data
	print_debug("WARNING (game.gd): get_weapon_blueprint_by_id: Blueprint '", weapon_id_to_find, "' not found.")
	return null

func get_weapon_next_level_upgrades(weapon_id_str: String, current_weapon_instance_data: Dictionary) -> Array[WeaponUpgradeData]: 
	var weapon_bp = get_weapon_blueprint_by_id(StringName(weapon_id_str))
	if not is_instance_valid(weapon_bp): 
		print_debug("get_weapon_next_level_upgrades: Blueprint not found for ID: ", weapon_id_str)
		return []
	var current_level = current_weapon_instance_data.get("weapon_level", 0)
	var specific_stats = current_weapon_instance_data.get("specific_stats", {})
	if current_level >= weapon_bp.max_level: return []
	var valid_next_upgrades: Array[WeaponUpgradeData] = []
	for upgrade_data_res in weapon_bp.available_upgrades:
		if not is_instance_valid(upgrade_data_res) or not upgrade_data_res is WeaponUpgradeData: continue
		var upgrade_data = upgrade_data_res as WeaponUpgradeData
		var acquired_flag_to_check = upgrade_data.set_acquired_flag_on_weapon 
		if acquired_flag_to_check == &"" and upgrade_data.max_stacks == 1: 
			acquired_flag_to_check = StringName(str(upgrade_data.upgrade_id) + "_acquired")
		if acquired_flag_to_check != &"" and specific_stats.get(acquired_flag_to_check, false) == true: continue 
		var prerequisites_met = true
		for prereq_id_sname in upgrade_data.prerequisites_on_this_weapon:
			var prereq_upgrade_def = weapon_bp.get_upgrade_by_id(prereq_id_sname) 
			var prereq_flag_key_to_check = prereq_id_sname 
			if is_instance_valid(prereq_upgrade_def) and prereq_upgrade_def.set_acquired_flag_on_weapon != &"":
				prereq_flag_key_to_check = prereq_upgrade_def.set_acquired_flag_on_weapon
			elif is_instance_valid(prereq_upgrade_def): 
				prereq_flag_key_to_check = StringName(str(prereq_upgrade_def.upgrade_id) + "_acquired")
			if not specific_stats.get(prereq_flag_key_to_check, false) == true:
				prerequisites_met = false; break
		if not prerequisites_met: continue
		valid_next_upgrades.append(upgrade_data)
	return valid_next_upgrades

func _on_player_level_up(new_level: int): 
	if not is_instance_valid(player_node): get_tree().paused = false; return
	get_tree().paused = true
	if is_instance_valid(level_up_screen_instance): level_up_screen_instance.queue_free(); level_up_screen_instance = null
	
	if not is_instance_valid(LEVEL_UP_SCREEN_SCENE): 
		get_tree().paused = false; 
		print_debug("ERROR (game.gd): LEVEL_UP_SCREEN_SCENE is not a valid scene. Check path.")
		return
	
	level_up_screen_instance = LEVEL_UP_SCREEN_SCENE.instantiate()
	if not is_instance_valid(level_up_screen_instance): 
		get_tree().paused = false; 
		print_debug("ERROR (game.gd): Failed to instance LevelUpScreen scene.")
		return
	
	var chosen_options: Array = _get_upgrade_options_for_player() 
	
	print_debug("game.gd: _on_player_level_up - chosen_options to display: ", chosen_options) 
	
	if chosen_options.is_empty():
		if is_instance_valid(level_up_screen_instance): level_up_screen_instance.queue_free()
		get_tree().paused = false; print_debug("No upgrade options available for level up."); return
		
	if level_up_screen_instance.has_method("display_options"):
		# Using call_deferred again, as the "Array to Array" issue was likely a type hint problem
		# which we solved by changing the signature in NewLevelUpScreen.gd
		level_up_screen_instance.call_deferred("display_options", chosen_options) 
	else: 
		get_tree().paused = false; 
		print_debug("ERROR (game.gd): The new LevelUpScreen instance is missing the 'display_options' method.")
		return
	
	add_child(level_up_screen_instance)
	if level_up_screen_instance.has_signal("upgrade_chosen"):
		if not level_up_screen_instance.is_connected("upgrade_chosen", Callable(self, "_on_upgrade_chosen")):
			level_up_screen_instance.upgrade_chosen.connect(Callable(self, "_on_upgrade_chosen"))
	level_up_screen_instance.process_mode = Node.PROCESS_MODE_ALWAYS

# The key function to modify is _get_upgrade_options_for_player
func _get_upgrade_options_for_player() -> Array: 
	print_debug("--- Getting Upgrade Options (With Full Resource Data) ---")
	var options_pool: Array = [] 

	# 1. Get General Upgrades (from loaded .tres files)
	for card_res in loaded_general_upgrades: 
		if is_instance_valid(card_res):
			# TODO: Add prerequisite and stack limit checks for general upgrades
			var card_presentation = {
				"id_for_card_selection": str(card_res.id),
				"title": card_res.title, "description": card_res.description,
				"icon_path": card_res.icon.resource_path if is_instance_valid(card_res.icon) else "",
				"type": "general_upgrade", 
				"resource_data": card_res # RESTORED
			}
			options_pool.append(card_presentation)
	# Fallback to old general upgrades if new system is empty (temporary during transition)
	if loaded_general_upgrades.is_empty() and not _temp_old_general_stat_upgrades.is_empty(): 
		for old_gen_upgrade_dict in _temp_old_general_stat_upgrades:
			var temp_card_dict = old_gen_upgrade_dict.duplicate(true)
			temp_card_dict["type"] = "general_stat_upgrade_OLD" 
			temp_card_dict["id_for_card_selection"] = old_gen_upgrade_dict.id
			options_pool.append(temp_card_dict)

	# 2. Get Weapon Upgrades
	if is_instance_valid(player_node) and player_node.has_method("get_active_weapons_data_for_level_up"):
		var player_active_weapons_instance_data: Array[Dictionary] = player_node.get_active_weapons_data_for_level_up()
		var offered_weapon_ids_for_upgrade_this_round : Array[StringName] = []
		for active_weapon_dict in player_active_weapons_instance_data:
			var weapon_id_sname = active_weapon_dict.get("id") as StringName
			if weapon_id_sname == null or weapon_id_sname == &"": continue
			var next_upgrades_for_this_weapon: Array[WeaponUpgradeData] = get_weapon_next_level_upgrades(str(weapon_id_sname), active_weapon_dict)
			if not next_upgrades_for_this_weapon.is_empty():
				var chosen_upgrade_res = next_upgrades_for_this_weapon.pick_random()
				var upgrade_card_presentation = {
					"id_for_card_selection": str(weapon_id_sname) + "_" + str(chosen_upgrade_res.upgrade_id),
					"title": chosen_upgrade_res.title, "description": chosen_upgrade_res.description,
					"icon_path": chosen_upgrade_res.icon.resource_path if is_instance_valid(chosen_upgrade_res.icon) else "",
					"type": "weapon_upgrade", "weapon_id_to_upgrade": str(weapon_id_sname), 
					"resource_data": chosen_upgrade_res # RESTORED
				}
				options_pool.append(upgrade_card_presentation)
				offered_weapon_ids_for_upgrade_this_round.append(weapon_id_sname)

	# 3. Offer New Weapons
	if is_instance_valid(player_node) and player_node.has_method("get_active_weapons_data_for_level_up"):
		var current_player_active_weapons = player_node.get_active_weapons_data_for_level_up()
		if current_player_active_weapons.size() < 6: 
			var potential_new_weapons_pool : Array = []
			for bp_data in all_loaded_weapon_blueprints:
				if not is_instance_valid(bp_data): continue
				var bp_id_sname = bp_data.id; var already_have_it = false
				for p_wep_dict in current_player_active_weapons:
					if p_wep_dict.get("id") == bp_id_sname: already_have_it = true; break
				if not already_have_it: 
					var can_offer_to_class = true
					if not bp_data.class_tag_restrictions.is_empty():
						if is_instance_valid(player_node) and player_node.has_method("get_current_basic_class_enum"):
							var player_class_enum = player_node.get_current_basic_class_enum()
							if not player_class_enum in bp_data.class_tag_restrictions: can_offer_to_class = false
						else: can_offer_to_class = false 
					if can_offer_to_class:
						var new_weapon_offer_presentation = {
							"id_for_card_selection": str(bp_id_sname), "type": "new_weapon", 
							"title": bp_data.title, "description": bp_data.description,
							"icon_path": bp_data.icon.resource_path if is_instance_valid(bp_data.icon) else "",
							"resource_data": bp_data # RESTORED
						}
						potential_new_weapons_pool.append(new_weapon_offer_presentation)
			if not potential_new_weapons_pool.is_empty():
				potential_new_weapons_pool.shuffle(); options_pool.append(potential_new_weapons_pool[0])

	options_pool.shuffle(); var final_chosen_options: Array = []; var offered_ids_this_selection: Array[StringName] = [] 
	for option_data_dict in options_pool:
		if final_chosen_options.size() >= 3: break
		var current_card_id_raw = option_data_dict.get("id_for_card_selection", option_data_dict.get("id"))
		var current_card_id = StringName(str(current_card_id_raw)) if current_card_id_raw != null else StringName(str(randi()))
		if not offered_ids_this_selection.has(current_card_id):
			final_chosen_options.append(option_data_dict); offered_ids_this_selection.append(current_card_id)
	if final_chosen_options.is_empty() and not _temp_old_general_stat_upgrades.is_empty(): 
		var fallback_option = _temp_old_general_stat_upgrades.pick_random().duplicate(true)
		fallback_option["id_for_card_selection"] = fallback_option.get("id") 
		fallback_option["type"] = "general_stat_upgrade_OLD"
		final_chosen_options.append(fallback_option)
	if final_chosen_options.is_empty():
		final_chosen_options.append({"title": "Continue", "description": "No new upgrades this level.", "type": "skip", "id_for_card_selection": "skip_level"})
	return final_chosen_options


func _on_upgrade_chosen(chosen_upgrade_data_wrapper: Dictionary): 
	if not is_instance_valid(player_node) or not player_node.has_method("apply_upgrade"):
		print_debug("ERROR: Player node or apply_upgrade method missing.")
		if is_instance_valid(level_up_screen_instance): level_up_screen_instance.queue_free(); level_up_screen_instance = null
		get_tree().paused = false; return
	
	# For this test, PlayerCharacter.apply_upgrade will need to know how to handle these simplified dicts
	# OR we restore resource_data if the simple dicts pass the call_deferred test.
	# var data_to_apply = chosen_upgrade_data_wrapper.get("resource_data", chosen_upgrade_data_wrapper) 
	var data_to_apply = chosen_upgrade_data_wrapper # Passing the simplified dictionary for now

	if chosen_upgrade_data_wrapper.get("type") != "skip": 
		player_node.apply_upgrade(data_to_apply) 
	if is_instance_valid(level_up_screen_instance):
		level_up_screen_instance.queue_free(); level_up_screen_instance = null
	get_tree().paused = false

func _on_player_has_died(): 
	if is_instance_valid(enemy_spawn_timer): enemy_spawn_timer.stop()
	if is_instance_valid(culling_check_timer): culling_check_timer.stop()
	if is_instance_valid(enemies_container):
		for enemy_child in enemies_container.get_children():
			if enemy_child.has_method("set_physics_process"): enemy_child.set_physics_process(false)
	var game_over_scene_res = load("res://Scenes/UI/GameOverScreen.tscn") as PackedScene 
	if game_over_scene_res:
		if is_instance_valid(game_over_screen_instance): game_over_screen_instance.queue_free()
		game_over_screen_instance = game_over_scene_res.instantiate(); add_child(game_over_screen_instance)
		if game_over_screen_instance.has_signal("restart_game_requested"):
			if not game_over_screen_instance.is_connected("restart_game_requested", Callable(self, "_on_restart_game_requested")):
				game_over_screen_instance.restart_game_requested.connect(Callable(self, "_on_restart_game_requested"))
		if game_over_screen_instance.has_method("set_process_mode"): game_over_screen_instance.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
func _on_restart_game_requested(): 
	if game_over_screen_instance and is_instance_valid(game_over_screen_instance):
		game_over_screen_instance.queue_free()
	get_tree().paused = false
	var error_code = get_tree().reload_current_scene()
	if error_code != OK: print("ERROR (Level): Failed to reload scene. Code: ", error_code)
func _on_player_class_tier_upgraded(new_class_id: String, _contributing_basic_classes: Array): 
	print("Level: Player class tier upgraded to ", new_class_id)
	pass
func _on_difficulty_tier_increased(new_tier: int): 
	pass

# --- DEBUG SETTERS for game.gd parameters ---
func debug_set_dds_spawn_rate_factor(value: float): dds_spawn_rate_factor = max(0.0001, value); _update_spawn_interval_from_dds(); print_debug("game.gd DEBUG: dds_spawn_rate_factor set to: ", dds_spawn_rate_factor)
func debug_set_hardcore_spawn_rate_multiplier(value: float): hardcore_spawn_rate_multiplier = max(0.1, value); _update_spawn_interval_from_dds(); print_debug("game.gd DEBUG: hardcore_spawn_rate_multiplier set to: ", hardcore_spawn_rate_multiplier)
func debug_set_base_spawn_interval(value: float): base_spawn_interval = max(0.05, value); _update_spawn_interval_from_dds(); print_debug("game.gd DEBUG: base_spawn_interval set to: ", base_spawn_interval)
func debug_set_min_spawn_interval(value: float): min_spawn_interval = max(0.01, value); _update_spawn_interval_from_dds(); print_debug("game.gd DEBUG: min_spawn_interval set to: ", min_spawn_interval)
func debug_set_enemies_per_batch(value: int): enemies_per_batch = max(1, value); print_debug("game.gd DEBUG: enemies_per_batch set to: ", enemies_per_batch)
func debug_set_active_pool_refresh_dds_interval(value: float): active_pool_refresh_dds_interval = max(5.0, value); print_debug("game.gd DEBUG: active_pool_refresh_dds_interval set to: ", active_pool_refresh_dds_interval)
func debug_set_max_active_enemy_types(value: int): max_active_enemy_types = max(1, value); _refresh_active_enemy_pool(); print_debug("game.gd DEBUG: max_active_enemy_types set to: ", max_active_enemy_types)
func debug_set_enemy_count_update_dds_interval(value: float): enemy_count_update_dds_interval = max(5.0, value); print_debug("game.gd DEBUG: enemy_count_update_dds_interval set to: ", enemy_count_update_dds_interval)
func debug_set_target_on_screen_enemies_override(enable: bool, value: int = -1):
	debug_override_target_enemies = enable
	if enable and value >= 0: debug_target_enemies_value = max(1, value); target_on_screen_enemies = debug_target_enemies_value; print_debug("game.gd DEBUG: Target enemies OVERRIDDEN to: ", target_on_screen_enemies)
	elif not enable: _update_target_on_screen_enemies(); print_debug("game.gd DEBUG: Target enemies override REMOVED. Current target: ", target_on_screen_enemies)
func debug_set_threat_pool_spawn_threshold(value: int): threat_pool_spawn_threshold = max(1, value); print_debug("game.gd DEBUG: threat_pool_spawn_threshold set to: ", threat_pool_spawn_threshold)
func debug_set_threat_pool_batch_multiplier(value: float): threat_pool_batch_multiplier = max(0.1, value); print_debug("game.gd DEBUG: threat_pool_batch_multiplier set to: ", threat_pool_batch_multiplier)
func debug_set_culling_timer_wait_time(value: float):
	culling_timer_wait_time = max(0.5, value)
	if is_instance_valid(culling_check_timer): culling_check_timer.wait_time = culling_timer_wait_time; if not culling_check_timer.is_stopped(): culling_check_timer.start() 
	print_debug("game.gd DEBUG: culling_timer_wait_time set to: ", culling_timer_wait_time)
func debug_set_random_event_check_interval(value: float): random_event_check_interval = max(1.0, value); print_debug("game.gd DEBUG: random_event_check_interval set to: ", random_event_check_interval)
func debug_set_forward_spawn_bias_chance(value: float): forward_spawn_bias_chance = clamp(value, 0.0, 1.0); print_debug("game.gd DEBUG: forward_spawn_bias_chance set to: ", forward_spawn_bias_chance)
func debug_set_spawn_margin(value: float): spawn_margin = max(10.0, value); print_debug("game.gd DEBUG: spawn_margin set to: ", spawn_margin)
func debug_reset_game_parameters_to_defaults():
	spawn_margin = ORIGINAL_SPAWN_MARGIN; player_movement_threshold = ORIGINAL_PLAYER_MOVEMENT_THRESHOLD; forward_spawn_bias_chance = ORIGINAL_FORWARD_SPAWN_BIAS_CHANCE
	base_spawn_interval = ORIGINAL_BASE_SPAWN_INTERVAL; min_spawn_interval = ORIGINAL_MIN_SPAWN_INTERVAL
	enemies_per_batch = ORIGINAL_ENEMIES_PER_BATCH; dds_spawn_rate_factor = ORIGINAL_DDS_SPAWN_RATE_FACTOR
	hardcore_spawn_rate_multiplier = ORIGINAL_HARDCORE_SPAWN_RATE_MULTIPLIER
	max_active_enemy_types = ORIGINAL_MAX_ACTIVE_ENEMY_TYPES
	active_pool_refresh_dds_interval = ORIGINAL_ACTIVE_POOL_REFRESH_DDS_INTERVAL
	enemy_count_update_dds_interval = ORIGINAL_ENEMY_COUNT_UPDATE_DDS_INTERVAL
	debug_override_target_enemies = false 
	threat_pool_spawn_threshold = ORIGINAL_THREAT_POOL_SPAWN_THRESHOLD
	threat_pool_batch_multiplier = ORIGINAL_THREAT_POOL_BATCH_MULTIPLIER
	culling_timer_wait_time = ORIGINAL_CULLING_TIMER_WAIT_TIME
	if is_instance_valid(culling_check_timer): culling_check_timer.wait_time = culling_timer_wait_time
	random_event_check_interval = ORIGINAL_RANDOM_EVENT_CHECK_INTERVAL
	_update_spawn_interval_from_dds(); _update_target_on_screen_enemies(); _refresh_active_enemy_pool()
	print_debug("game.gd DEBUG: All tunable game parameters reset to defaults.")
# Add this function to your game.gd script

func debug_spawn_specific_enemy(enemy_id: StringName, elite_type_override: StringName, count: int, near_player: bool):
	print_debug("game.gd: DEBUG SPAWN REQUEST - ID: ", enemy_id, ", Elite: ", elite_type_override, ", Count: ", count, ", Near Player: ", near_player)

	if not is_instance_valid(player_node):
		print_debug("game.gd ERROR: Player node is not valid. Cannot spawn enemies.")
		return
	if not is_instance_valid(enemies_container):
		print_debug("game.gd ERROR: Enemies container is not valid. Cannot spawn enemies.")
		return
	if not has_method("get_enemy_data_by_id_for_debug"):
		print_debug("game.gd ERROR: Missing 'get_enemy_data_by_id_for_debug' method.")
		return

	var enemy_data_to_spawn: EnemyData = get_enemy_data_by_id_for_debug(enemy_id)

	if not is_instance_valid(enemy_data_to_spawn):
		print_debug("game.gd ERROR: EnemyData not found for ID: ", enemy_id, ". Cannot spawn.")
		return

	for i in range(count):
		# Break if max target enemies is reached, plus a small buffer to avoid overspawning massively
		if current_active_enemy_count >= target_on_screen_enemies * 2:
			print_debug("game.gd: Aborting debug spawn, current_active_enemy_count (", current_active_enemy_count, ") exceeds target (", target_on_screen_enemies, ").")
			break

		var spawn_position = _calculate_spawn_position_for_enemy(near_player)
		_spawn_actual_enemy(enemy_data_to_spawn, spawn_position, elite_type_override)
		print_debug("game.gd: Spawned enemy: ", enemy_data_to_spawn.display_name, " (Elite: ", elite_type_override, ") at ", spawn_position)
