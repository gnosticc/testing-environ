# player.gd
class_name PlayerCharacter
extends CharacterBody2D

# --- Visual Adjustment of Character Sprite ---
@export var sprite_flip_x_compensation: float = 0.0

# --- Player Core Stats ---
@export var max_health: int = 100
var current_health: int
@export var speed: float = 60.0
@export var pickup_magnet_base_radius: float = 10.0
var current_pickup_magnet_radius: float

# --- Component References ---
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var player_stats: PlayerStats = $PlayerStats
@onready var attacks_container: Node2D
@onready var experience_collector_area: Area2D = $ExperienceCollectorArea
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ui_anchor: Marker2D = $AnimatedSprite2D/UIAnchor
@onready var melee_aiming_dot: Node2D = $MeleeAimingDot

# --- Signals ---
signal health_changed(current_health_value, max_health_value)
signal experience_changed(current_exp, exp_to_next_level, player_level)
signal player_level_up(new_level)
signal player_class_tier_upgraded(new_class_id, contributing_basic_classes)
signal player_has_died
signal player_took_damage_from(attacker_node)

# --- Experience and Leveling Variables ---
var current_experience: int = 0
var experience_to_next_level: int = 10
var current_level: int = 1

const LINEAR_FACTOR_PER_LEVEL: int = 10
const BASE_FOR_EXPONENTIAL_PART: int = 10
const EXPONENTIAL_SCALING_FACTOR: float = 1.4

# --- Class Progression Tracking ---
enum BasicClass {
	NONE, WARRIOR, KNIGHT, ROGUE, WIZARD, DRUID, CONJURER
}
var current_basic_class_enum_val: PlayerCharacter.BasicClass = BasicClass.NONE
var basic_class_levels: Dictionary = {
	BasicClass.WARRIOR: 0, BasicClass.KNIGHT: 0, BasicClass.ROGUE: 0,
	BasicClass.WIZARD: 0, BasicClass.DRUID: 0, BasicClass.CONJURER: 0
}
const BASIC_CLASS_LEVEL_THRESHOLD_FOR_ADVANCEMENT: int = 10
var acquired_advanced_classes: Array[StringName] = []
var current_sprite_preference: String = "default"
var prefer_current_sprite_after_first_advanced: bool = false

# --- Initialization State ---
var _initial_chosen_class_enum: PlayerCharacter.BasicClass = BasicClass.NONE
var _initial_chosen_weapon_id: StringName = &""
var _initial_weapon_equipped: bool = false
var game_node_ref: Node

func _ready():
	if not is_instance_valid(player_stats):
		print_debug("CRITICAL ERROR (PlayerCharacter): PlayerStats node ($PlayerStats) not found! Aborting _ready.")
		return
	if not is_instance_valid(weapon_manager):
		print_debug("CRITICAL ERROR (PlayerCharacter): WeaponManager node ($WeaponManager) not found! Aborting _ready.")
		return

	if TestStartSettings != null and TestStartSettings.are_test_settings_available() and not TestStartSettings.were_settings_applied_this_run():
		var chosen_class = TestStartSettings.get_chosen_basic_class()
		var chosen_weapon_str = TestStartSettings.get_chosen_weapon_id()
		setup_with_chosen_class_and_weapon(chosen_class, StringName(chosen_weapon_str))
		TestStartSettings.mark_settings_as_applied()
	else:
		setup_with_chosen_class_and_weapon(BasicClass.WARRIOR, &"warrior_scythe")

	if experience_collector_area:
		if not experience_collector_area.is_connected("area_entered", Callable(self, "_on_experience_collector_area_entered")):
			experience_collector_area.area_entered.connect(Callable(self, "_on_experience_collector_area_entered"))
	
	experience_to_next_level = calculate_exp_for_next_level(current_level)
	
	if is_instance_valid(player_stats) and player_stats.has_signal("stats_recalculated"):
		if not player_stats.is_connected("stats_recalculated", Callable(self, "_on_player_stats_recalculated")):
			player_stats.stats_recalculated.connect(Callable(self, "_on_player_stats_recalculated"))
	
	if not is_instance_valid(ui_anchor): print_debug("WARNING (Player): UIAnchor node not found.")
	if not is_instance_valid(melee_aiming_dot): print_debug("ERROR (Player): MeleeAimingDot node not found.")
	if not is_instance_valid(animated_sprite): print_debug("WARNING (Player): AnimatedSprite2D node not found.")

	game_node_ref = get_tree().root.get_node_or_null("Game")
	if is_instance_valid(game_node_ref) and game_node_ref.has_signal("weapon_blueprints_ready"):
		if not game_node_ref.is_connected("weapon_blueprints_ready", Callable(self, "_on_game_weapon_blueprints_ready")):
			game_node_ref.weapon_blueprints_ready.connect(Callable(self, "_on_game_weapon_blueprints_ready"))
			print_debug("PlayerCharacter: Connected to game_node's weapon_blueprints_ready signal.")
		if game_node_ref.has_method("get_all_weapon_blueprints_for_debug") and \
		   not game_node_ref.get_all_weapon_blueprints_for_debug().is_empty():
			print_debug("PlayerCharacter: Blueprints seem already loaded in _ready. Triggering equip via deferred call.")
			call_deferred("_on_game_weapon_blueprints_ready")
	else:
		print_debug("WARNING (PlayerCharacter @ _ready): Could not find game_node ('/root/Game') or it's missing 'weapon_blueprints_ready' signal. Initial weapon equip will rely on deferred fallback.")
		call_deferred("_try_equip_initial_weapon_fallback")


func setup_with_chosen_class_and_weapon(class_enum: PlayerCharacter.BasicClass, weapon_id: StringName):
	_initial_chosen_class_enum = class_enum
	_initial_chosen_weapon_id = weapon_id
	_initial_weapon_equipped = false
	current_basic_class_enum_val = _initial_chosen_class_enum

	var class_name_key_array = BasicClass.keys()
	var class_name_str = "UNKNOWN_CLASS"
	if class_enum >= 0 and class_enum < class_name_key_array.size():
		class_name_str = BasicClass.keys()[class_enum]

	print_debug("PlayerCharacter: Setup with Class Enum: ", class_enum, " (Name: ", class_name_str, "), Weapon ID: '", weapon_id, "'")

	# Initialize player stats based on the chosen class
	_initialize_player_class_and_stats(class_enum) # This will call PlayerStats.initialize_with_class_data

	# Initial stat update based on class data (health, magnet radius)
	call_deferred("_on_player_stats_recalculated") # Ensure stats are reflected after PlayerStats init
	emit_signal("experience_changed", current_experience, experience_to_next_level, current_level)


func _on_game_weapon_blueprints_ready():
	print_debug("PlayerCharacter: Received game.weapon_blueprints_ready signal.")
	_try_equip_initial_weapon()

func _try_equip_initial_weapon_fallback():
	print_debug("PlayerCharacter: Attempting fallback for initial weapon equip (deferred).")
	if not is_instance_valid(game_node_ref):
		game_node_ref = get_tree().root.get_node_or_null("Game")
	_try_equip_initial_weapon()

func _try_equip_initial_weapon():
	if _initial_weapon_equipped:
		return
	if _initial_chosen_weapon_id == &"":
		_initial_weapon_equipped = true
		return

	if not is_instance_valid(weapon_manager):
		print_debug("ERROR (PlayerCharacter @ _try_equip_initial_weapon): WeaponManager node ($WeaponManager) is invalid.")
		_initial_weapon_equipped = true
		return
	
	if not weapon_manager.has_method("add_weapon_from_blueprint_id"):
		print_debug("ERROR (PlayerCharacter @ _try_equip_initial_weapon): WeaponManager instance is missing 'add_weapon_from_blueprint_id' method.")
		_initial_weapon_equipped = true
		return

	print_debug("PlayerCharacter: Attempting to add starting weapon: '", _initial_chosen_weapon_id, "' via WeaponManager.")
	var success = weapon_manager.add_weapon_from_blueprint_id(_initial_chosen_weapon_id)
	
	if success:
		print_debug("PlayerCharacter: WeaponManager successfully processed adding starting weapon '", _initial_chosen_weapon_id, "'.")
	else:
		print_debug("CRITICAL WARNING (PlayerCharacter): WeaponManager failed to add starting weapon '", _initial_chosen_weapon_id, "'. Check WeaponManager and game.gd logs for blueprint loading issues.")
	
	_initial_weapon_equipped = true


func _initialize_player_class_and_stats(p_class_enum: BasicClass = BasicClass.WARRIOR):
	if not is_instance_valid(player_stats): # Guard clause
		print_debug("ERROR (PlayerCharacter): PlayerStats node is not valid in _initialize_player_class_and_stats.")
		_fallback_initialize_stats_directly() # Attempt a basic fallback
		return

	if not player_stats.has_method("initialize_with_class_data"):
		print_debug("ERROR (PlayerCharacter): PlayerStats node is missing 'initialize_with_class_data' method.")
		_fallback_initialize_stats_directly() # Attempt a basic fallback
		return

	current_basic_class_enum_val = p_class_enum
	var class_name_str = ""
	if BasicClass.keys().has(BasicClass.keys()[p_class_enum]): # Check if enum value is valid before getting key
		class_name_str = BasicClass.keys()[p_class_enum].to_lower()
	else:
		print_debug("ERROR (PlayerCharacter): Invalid class enum value provided: ", p_class_enum)
		_fallback_initialize_stats_directly()
		return

	# CORRECTED PATH based on your structure: res://Data/Classes/warrior_class_data.tres
	var class_data_path = "res://Data/Classes/" + class_name_str + "_class_data.tres"
	print_debug("PlayerCharacter: Attempting to load class data from: ", class_data_path)

	if ResourceLoader.exists(class_data_path):
		var class_data_res = load(class_data_path) as PlayerClassData
		if is_instance_valid(class_data_res):
			player_stats.initialize_with_class_data(class_data_res)
			# FIX: Initialize current_health here to ensure it starts at max
			current_health = player_stats.get_max_health()
			print_debug("PlayerCharacter: PlayerStats initialized with class data: ", class_name_str.capitalize())
		else:
			print_debug("ERROR (PlayerCharacter): Failed to load PlayerClassData resource at '", class_data_path, "' (loaded resource is not valid PlayerClassData).")
			_fallback_initialize_stats_directly()
	else:
		print_debug("ERROR (PlayerCharacter): PlayerClassData resource not found at '", class_data_path, "'. Using fallback direct stats init.")
		_fallback_initialize_stats_directly()
	
	# PlayerStats should emit "stats_recalculated" after its initialization,
	# which will trigger _on_player_stats_recalculated in this script to update local speed, health etc.
	# If it doesn't, we might need a direct call or ensure connection.
	if is_instance_valid(player_stats) and player_stats.has_method("recalculate_all_stats") and not player_stats.is_connected("stats_recalculated", Callable(self, "_on_player_stats_recalculated")):
		# This ensures that if PlayerStats doesn't emit in its init, we can trigger it.
		# However, it's better if PlayerStats.initialize_with_class_data ends with recalculate_all_stats() itself.
		print_debug("PlayerCharacter: Manually calling recalculate_all_stats after class init (consider if PlayerStats should do this internally).")
		player_stats.recalculate_all_stats()
	elif not is_instance_valid(player_stats) or not player_stats.has_method("recalculate_all_stats"):
		# If PlayerStats is invalid or has no recalculate, manually update player character properties from defaults.
		_on_player_stats_recalculated() # This will use default self.speed if player_stats is invalid



func _fallback_initialize_stats_directly():
	# This is called if PlayerClassData.tres is missing
	print_debug("PlayerCharacter: Using HARDCODED FALLBACK stats as PlayerClassData was not found/loaded.")
	if is_instance_valid(player_stats) and player_stats.has_method("initialize_with_raw_stats"):
		# Create a dictionary matching the structure PlayerStats.initialize_with_raw_stats expects
		var raw_stats = {
			"base_max_health": 100, "base_health_regeneration": 0.1, "base_numerical_damage": 10,
			"base_global_damage_multiplier": 1.0, "base_attack_speed_multiplier": 1.0,
			"base_armor": 1, "base_armor_penetration": 0.0, "base_movement_speed": 70.0,
			"base_magnet_range": 50.0, "base_experience_gain_multiplier": 1.0,
			"base_aoe_area_multiplier": 1.0, "base_projectile_size_multiplier": 1.0,
			"base_projectile_speed_multiplier": 1.0, "base_effect_duration_multiplier": 1.0,
			"base_crit_chance": 0.05, "base_crit_damage_multiplier": 1.5, "base_luck": 0
		}
		player_stats.initialize_with_raw_stats(raw_stats)
		# FIX: Initialize current_health here to ensure it starts at max after fallback
		current_health = player_stats.get_max_health()
	else:
		print_debug("PlayerCharacter: PlayerStats missing initialize_with_raw_stats. Using very basic defaults.")
		current_health = max_health
		# self.speed is already defaulted by @export
		current_pickup_magnet_radius = pickup_magnet_base_radius
		update_experience_collector_radius()
		emit_signal("health_changed", current_health, max_health)


func _on_player_stats_recalculated():
	print_debug("PlayerCharacter: _on_player_stats_recalculated called.") # Added print
	if not is_instance_valid(player_stats):
		print_debug("PlayerCharacter: _on_player_stats_recalculated called, but player_stats is invalid. Aborting.")
		return

	var new_max_health = player_stats.get_max_health()
	var health_percentage = 1.0
	if max_health > 0 : health_percentage = float(current_health) / float(max_health)
	else: health_percentage = 1.0 if new_max_health > 0 else 0.0 # Handle initial max_health=0

	max_health = new_max_health # Update player's @export var
	current_health = clamp(int(round(new_max_health * health_percentage)), 0, new_max_health)
	if new_max_health > 0 and current_health == 0 and health_percentage > 0:
		current_health = 1 # Ensure at least 1 HP if calculated to 0 but percentage implies >0
	
	# Directly use player_stats.get_movement_speed() in _physics_process
	# self.speed = player_stats.get_movement_speed() # No longer strictly needed to set self.speed here
	
	var new_magnet_range = player_stats.get_magnet_range()
	if current_pickup_magnet_radius != new_magnet_range:
		current_pickup_magnet_radius = new_magnet_range
		update_experience_collector_radius()
			
	print_debug("PlayerCharacter: Health updated to ", current_health, "/", max_health, ". Speed: ", player_stats.get_movement_speed()) # Added print
	emit_signal("health_changed", current_health, new_max_health)


func _physics_process(delta: float):
	var input_direction = Vector2.ZERO
	if Input.is_action_pressed("move_right"): input_direction.x += 1
	if Input.is_action_pressed("move_left"): input_direction.x -= 1
	if Input.is_action_pressed("move_down"): input_direction.y += 1
	if Input.is_action_pressed("move_up"): input_direction.y -= 1

	var current_move_speed = self.speed # Use player's own speed property as base/default
	if is_instance_valid(player_stats) and player_stats.has_method("get_movement_speed"):
		current_move_speed = player_stats.get_movement_speed() # Get dynamically calculated speed
	
	# print_debug("Input: ", input_direction, ", BaseSpeedVar: ", self.speed, ", PlayerStatsSpeed: ", player_stats.get_movement_speed() if is_instance_valid(player_stats) else "N/A", ", CurrentMoveSpeed: ", current_move_speed)

	if input_direction.length_squared() > 0:
		velocity = input_direction.normalized() * current_move_speed
	else:
		velocity = Vector2.ZERO
	
	# print_debug("Velocity: ", velocity) # Uncomment to debug movement values

	if animated_sprite:
		if velocity.x < -0.01:
			animated_sprite.flip_h = true
			animated_sprite.offset.x = sprite_flip_x_compensation
		elif velocity.x > 0.1:
			animated_sprite.flip_h = false
			animated_sprite.offset.x = 0.0
	move_and_slide()
	
	if is_instance_valid(player_stats):
		var regen = player_stats.get_health_regeneration()
		var current_max_hp = player_stats.get_max_health()
		if regen > 0.0 and current_health < current_max_hp:
			current_health += regen * delta
			current_health = min(current_health, current_max_hp)
			emit_signal("health_changed", current_health, current_max_hp)

func _on_experience_collector_area_entered(area: Area2D):
	if area.is_in_group("exp_drops") and area.has_method("collected"):
		var exp_value: int = 0
		if "experience_value" in area: exp_value = area.experience_value
		var exp_gain_mod = 1.0
		if is_instance_valid(player_stats) and player_stats.has_method("get_experience_gain_multiplier"):
			exp_gain_mod = player_stats.get_experience_gain_multiplier()
		var modified_exp_value = int(round(float(exp_value) * exp_gain_mod))
		current_experience += modified_exp_value
		area.collected()
		check_level_up()
		emit_signal("experience_changed", current_experience, experience_to_next_level, current_level)

func check_level_up():
	while current_experience >= experience_to_next_level:
		var exp_cost_of_this_level = experience_to_next_level
		current_level += 1
		current_experience -= exp_cost_of_this_level
		experience_to_next_level = calculate_exp_for_next_level(current_level)
		print("LEVEL UP! Player is now level: ", current_level)
		emit_signal("player_level_up", current_level)

func calculate_exp_for_next_level(player_curr_level: int) -> int:
	if player_curr_level < 1:
		return LINEAR_FACTOR_PER_LEVEL + int(BASE_FOR_EXPONENTIAL_PART * pow(EXPONENTIAL_SCALING_FACTOR, 0.0))
	var linear_part = LINEAR_FACTOR_PER_LEVEL * player_curr_level
	var exponential_part = BASE_FOR_EXPONENTIAL_PART * pow(EXPONENTIAL_SCALING_FACTOR, float(player_curr_level - 1))
	return linear_part + int(exponential_part)
	
func take_damage(amount: int, attacker: Node2D = null):
	print_debug("PlayerCharacter: take_damage called. Initial current_health: ", current_health, ", amount: ", amount) # Added print
	var current_defense = 0
	if is_instance_valid(player_stats) and player_stats.has_method("get_armor"):
		current_defense = player_stats.get_armor()
	print_debug("PlayerCharacter: Defense: ", current_defense) # Added print
	var actual_damage = amount - current_defense
	actual_damage = max(0, actual_damage)
	print_debug("PlayerCharacter: Actual damage after defense: ", actual_damage) # Added print
	current_health -= actual_damage
	current_health = max(0, current_health)
	print_debug("PlayerCharacter: Current health after damage: ", current_health) # Added print
	var current_max_hp = 100
	if is_instance_valid(player_stats) and player_stats.has_method("get_max_health"):
		current_max_hp = player_stats.get_max_health()
	emit_signal("health_changed", current_health, current_max_hp)
	if is_instance_valid(attacker):
		emit_signal("player_took_damage_from", attacker)
	if current_health <= 0: die()

func die():
	print_debug("PlayerCharacter: die() function called! Stack Trace:")
	for s in get_stack():
		print_debug("  Script: ", s.source, ", Function: ", s.function, ", Line: ", s.line)
	print("Player has died! Emitting signal.")
	emit_signal("player_has_died")
	set_physics_process(false); hide()
	var mc = get_node_or_null("CollisionShape2D"); if mc: mc.disabled = true
	
# This is the key function to refactor
func apply_upgrade(upgrade_data_wrapper: Dictionary):
	if not upgrade_data_wrapper is Dictionary:
		print_debug("ERROR (PlayerCharacter): apply_upgrade did not receive a dictionary.")
		return
	
	var upgrade_type = upgrade_data_wrapper.get("type", "")
	var resource = upgrade_data_wrapper.get("resource_data") # Get the actual resource

	print_debug("PlayerCharacter: Applying upgrade. Type: '", upgrade_type, "', Resource: ", resource)

	if upgrade_type == "new_weapon" and resource is WeaponBlueprintData:
		if is_instance_valid(weapon_manager) and weapon_manager.has_method("add_weapon"):
			weapon_manager.add_weapon(resource)
			
	elif upgrade_type == "weapon_upgrade" and resource is WeaponUpgradeData:
		var weapon_id_to_upgrade = upgrade_data_wrapper.get("weapon_id_to_upgrade", &"")
		if weapon_id_to_upgrade == &"":
			print_debug("ERROR (PlayerCharacter): apply_upgrade for WeaponUpgradeData missing 'weapon_id_to_upgrade'.")
			return
		if is_instance_valid(weapon_manager) and weapon_manager.has_method("apply_weapon_upgrade"):
			weapon_manager.apply_weapon_upgrade(StringName(weapon_id_to_upgrade), resource)
			
	elif upgrade_type == "general_upgrade" and resource is GeneralUpgradeCardData:
		if is_instance_valid(player_stats) and player_stats.has_method("apply_effects_from_card"):
			player_stats.apply_effects_from_card(resource)
		else:
			print_debug("ERROR (PlayerCharacter): PlayerStats missing apply_effects_from_card method.")

	# Keep the old dictionary-based fallback for now during transition
	elif upgrade_type == "general_stat_upgrade_OLD":
		if is_instance_valid(player_stats) and player_stats.has_method("apply_stat_upgrade"):
			var stat_key = upgrade_data_wrapper.get("stat_key_target", upgrade_data_wrapper.get("stat"))
			var value = upgrade_data_wrapper.get("value", upgrade_data_wrapper.get("percent_increase", 0.0))
			var is_percentage = "percent_increase" in upgrade_data_wrapper or "percent" in upgrade_data_wrapper.get("modification_type", "")
			var is_multiplicative = "is_multiplicative_percent" in upgrade_data_wrapper or "mult" in upgrade_data_wrapper.get("modification_type", "")
			player_stats.apply_stat_upgrade(stat_key, value, is_percentage, is_multiplicative)
	
	else:
		print_debug("PlayerCharacter: apply_upgrade received unknown upgrade type or invalid resource. Type: '", upgrade_type, "', Resource: ", resource)
	
	if is_instance_valid(player_stats) and player_stats.has_method("recalculate_all_stats"):
		player_stats.recalculate_all_stats()

func update_experience_collector_radius():
	if is_instance_valid(experience_collector_area) and experience_collector_area.get_child_count() > 0:
		var cs = experience_collector_area.get_child(0) as CollisionShape2D
		if is_instance_valid(cs) and cs.shape is CircleShape2D: # Added is_instance_valid for cs
			cs.shape.radius = current_pickup_magnet_radius

func check_for_advanced_class_unlocks() -> Array[Dictionary]:
	var potential_unlocks: Array[Dictionary] = []
	return potential_unlocks

func _create_advanced_class_card_data(adv_class_id: String, from_classes: Array) -> Dictionary:
	return { "id": "unlock_" + adv_class_id.to_lower(), "title": "Become " + adv_class_id,
			 "class_tag": adv_class_id, "description": "Unlock the path of the " + adv_class_id + "!",
			 "type": "advanced_class_unlock", "advanced_class_id": adv_class_id,
			 "unlocked_from": from_classes, "icon_path": "" }

func change_player_sprite_for_class(class_id_or_default: String): current_sprite_preference = class_id_or_default
func get_current_experience() -> int: return current_experience
func get_experience_to_next_level() -> int: return experience_to_next_level
func get_current_level() -> int: return current_level
func get_current_health() -> int: return current_health
func get_max_health() -> int:
	if is_instance_valid(player_stats) and player_stats.has_method("get_max_health"):
		return player_stats.get_max_health()
	return 100

func get_ui_anchor_global_position() -> Vector2:
	if is_instance_valid(ui_anchor): return ui_anchor.global_position
	elif is_instance_valid(animated_sprite): return animated_sprite.global_position
	return self.global_position

func _find_nearest_enemy(p_from_position: Vector2 = Vector2.INF) -> Node2D:
	var enemies_in_scene = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy: Node2D = null; var min_dist_sq = INF
	var search_origin = p_from_position
	if search_origin == Vector2.INF: search_origin = global_position
	if enemies_in_scene.is_empty(): return null
	for enemy_node in enemies_in_scene:
		if not is_instance_valid(enemy_node): continue
		var dist_sq = search_origin.distance_squared_to(enemy_node.global_position)
		if dist_sq < min_dist_sq: min_dist_sq = dist_sq; nearest_enemy = enemy_node
	return nearest_enemy

func get_active_weapons_data_for_level_up() -> Array[Dictionary]:
	if is_instance_valid(weapon_manager) and weapon_manager.has_method("get_active_weapons_data_for_level_up"):
		return weapon_manager.get_active_weapons_data_for_level_up()
	print_debug("WARNING (Player): WeaponManager not found or missing 'get_active_weapons_data_for_level_up'.")
	return []

func get_basic_class_levels_for_level_up() -> Dictionary:
	return basic_class_levels.duplicate(true)

func get_acquired_advanced_classes_for_level_up() -> Array[StringName]:
	return acquired_advanced_classes

func get_current_basic_class_enum() -> PlayerCharacter.BasicClass:
	return current_basic_class_enum_val

func heal(amount: int):
	if current_health <= 0:
		return
	
	print_debug("PlayerCharacter: heal() called with amount: ", amount)

	var actual_max_health = max_health
	if is_instance_valid(player_stats) and player_stats.has_method("get_max_health"):
		actual_max_health = player_stats.get_max_health()
	current_health = clamp(current_health + amount, 0, actual_max_health)
	emit_signal("health_changed", current_health, actual_max_health)
