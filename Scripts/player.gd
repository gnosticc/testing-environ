# player.gd
# This script manages the player's core behavior, input, health, experience,
# and acts as the central hub for interacting with PlayerStats and WeaponManager.
# It now fully integrates with the standardized stat system using PlayerStatKeys.
#
# UPDATED: Re-added player walk/idle animation logic.
# UPDATED: Implemented UI anchoring logic for health/exp bars using GameUI's public methods.
# FIXED: Declared 'is_dead_flag' variable.
# FIXED: Resolved "parameter named 'new_max_health' declared in this scope" error.
# FIXED: Ensured _last_known_max_health is initialized correctly.
# ADDED: get_current_basic_class_id() for PlayerStats debug reset.

extends CharacterBody2D
class_name PlayerCharacter

# --- Visual Adjustment of Character Sprite ---
@export var sprite_flip_x_compensation: float = 0.0

# --- Player Core Variables (now primarily derived from PlayerStats) ---
# These variables hold the CURRENT state of health and magnet radius,
# which are updated based on the calculations in PlayerStats.gd.
var current_health: float = 0.0 # Initialized here, will be set from PlayerStats.MAX_HEALTH on init
var current_pickup_magnet_radius: float = 0.0
var is_dead_flag: bool = false # FIXED: Declared is_dead_flag here

# Store the last known max health to correctly scale current health percentage
var _last_known_max_health: float = 0.0 # Initialize here to ensure it's always set

# --- Component References ---
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var player_stats: PlayerStats = $PlayerStats # Reference to the PlayerStats child node
@onready var attacks_container: Node2D # Container for spawned attacks (e.g., projectiles)
@onready var experience_collector_area: Area2D = $ExperienceCollectorArea
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ui_anchor: Marker2D = $AnimatedSprite2D/UIAnchor # Anchor point for UI elements above player
@onready var melee_aiming_dot: Node2D = $MeleeAimingDot

# --- Signals ---
signal health_changed(current_health_value, max_health_value)
signal experience_changed(current_exp, exp_to_next_level, player_level)
signal player_level_up(new_level)
signal player_class_tier_upgraded(new_class_id, contributing_basic_classes)
signal player_has_died
signal player_took_damage_from(attacker_node)
signal attacked_by_enemy(enemy_node: Node)

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
var _current_basic_class_string_id: StringName = &"none" # NEW: Stores StringName ID for PlayerStats debug reset
var basic_class_levels: Dictionary = {
	BasicClass.WARRIOR: 0, BasicClass.KNIGHT: 0, BasicClass.ROGUE: 0,
	BasicClass.WIZARD: 0, BasicClass.DRUID: 0, BasicClass.CONJURER: 0
}
const BASIC_CLASS_LEVEL_THRESHOLD_FOR_ADVANCEMENT: int = 10
var acquired_advanced_classes: Array[StringName] = []
var current_sprite_preference: String = "default"
var prefer_current_sprite_after_first_advanced: bool = false

# --- Initialization State ---
var _initial_chosen_class_enum: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE
var _initial_chosen_weapon_id: StringName = &""
var _initial_weapon_equipped: bool = false
var game_node_ref: Node # Reference to the global Game node (Main scene's root)


func _ready():
	# Critical: Ensure PlayerStats and WeaponManager are valid before proceeding.
	if not is_instance_valid(player_stats) or not is_instance_valid(weapon_manager):
		push_error("CRITICAL ERROR (PlayerCharacter): PlayerStats or WeaponManager node missing!"); return

	# Get reference to the global Game node. It might not be ready yet.
	game_node_ref = get_tree().root.get_node_or_null("Game")

	# Connect to the game node's 'weapon_blueprints_ready' signal to ensure
	# weapon blueprints are loaded before attempting to equip the initial weapon.
	if is_instance_valid(game_node_ref) and game_node_ref.has_signal("weapon_blueprints_ready"):
		game_node_ref.weapon_blueprints_ready.connect(Callable(self, "_on_game_weapon_blueprints_ready"), CONNECT_ONE_SHOT)
	else:
		push_warning("PlayerCharacter: Game node or 'weapon_blueprints_ready' signal not found. Proceeding with default setup.")
		_on_game_weapon_blueprints_ready() # Call directly for immediate setup

	# Connect to experience collection area
	if experience_collector_area:
		if not experience_collector_area.is_connected("area_entered", Callable(self, "_on_experience_collector_area_entered")):
			experience_collector_area.area_entered.connect(Callable(self, "_on_experience_collector_area_entered"))
	
	# Initial experience calculation for level 1
	experience_to_next_level = calculate_exp_for_next_level(current_level)
	
	# Connect to player_stats' 'stats_recalculated' signal.
	# This signal will trigger when player stats change (e.g., from upgrades),
	# allowing PlayerCharacter to update its derived properties like current_health.
	if is_instance_valid(player_stats):
		if not player_stats.is_connected("stats_recalculated", Callable(self, "_on_player_stats_recalculated")):
			player_stats.stats_recalculated.connect(Callable(self, "_on_player_stats_recalculated"))
	else:
		push_error("PlayerCharacter: PlayerStats node is invalid in _ready().")


# This function is called when 'game.gd' signals that weapon blueprints are ready.
# It then proceeds with the initial player and weapon setup.
func _on_game_weapon_blueprints_ready():
	# Determine initial class and weapon based on test settings or defaults.
	if TestStartSettings != null and TestStartSettings.are_test_settings_available() and not TestStartSettings.were_settings_applied_this_run():
		_initial_chosen_class_enum = TestStartSettings.get_chosen_basic_class()
		_initial_chosen_weapon_id = TestStartSettings.get_chosen_weapon_id() # Returns StringName
		TestStartSettings.mark_settings_as_applied()
	else:
		# Default fallback if no test settings are found or already applied.
		_initial_chosen_class_enum = BasicClass.WARRIOR
		_initial_chosen_weapon_id = &"warrior_scythe"

	# Initialize player class and stats first.
	_initialize_player_class_and_stats(_initial_chosen_class_enum)
	
	# Then attempt to equip the initial weapon.
	_try_equip_initial_weapon()

	# Emit initial experience signal (health_changed will be emitted by _on_player_stats_recalculated)
	emit_signal("experience_changed", current_experience, experience_to_next_level, current_level)


# Initializes the player's class and sets up their base stats via PlayerStats.gd.
func _initialize_player_class_and_stats(p_class_enum: BasicClass):
	if not is_instance_valid(player_stats):
		push_error("PlayerCharacter: PlayerStats node is not valid for initialization!"); return

	current_basic_class_enum_val = p_class_enum
	# Store the StringName ID of the basic class for use (e.g., by PlayerStats debug reset)
	_current_basic_class_string_id = BasicClass.keys()[p_class_enum].to_lower()

	var class_data_path = "res://Data/Classes/" + _current_basic_class_string_id + "_class_data.tres"

	var class_data_res: PlayerClassData = null
	if ResourceLoader.exists(class_data_path):
		class_data_res = load(class_data_path) as PlayerClassData
	
	if is_instance_valid(class_data_res):
		player_stats.initialize_base_stats(class_data_res)
		# Set current_health based on the newly initialized max health from PlayerStats
		# _on_player_stats_recalculated will be called right after this via the signal
		# and will correctly set current_health based on the new max health.
	else:
		push_error("PlayerCharacter: Failed to load PlayerClassData at '", class_data_path, "'. Initializing with fallback stats.")
		_fallback_initialize_stats_directly()
	
	# Recalculation will be triggered by player_stats.stats_recalculated signal,
	# which we connected in _ready().

# Fallback function to initialize player stats with hardcoded values
# if PlayerClassData cannot be loaded.
func _fallback_initialize_stats_directly():
	if not is_instance_valid(player_stats):
		push_error("PlayerCharacter: Cannot fallback initialize stats, PlayerStats node is invalid!"); return

	# Use standardized keys for fallback stats
	var raw_stats = {
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAX_HEALTH]: 100.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.HEALTH_REGENERATION]: 0.1,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.NUMERICAL_DAMAGE]: 10.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.GLOBAL_DAMAGE_MULTIPLIER]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: 0.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED]: 70.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAGNET_RANGE]: 50.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.EXPERIENCE_GAIN_MULTIPLIER]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER]: 1.0,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CRIT_CHANCE]: 0.05,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER]: 1.5,
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.LUCK]: 0.0
	}
	# Pass these raw stats to PlayerStats for initialization
	player_stats.initialize_base_stats_with_raw_dict(raw_stats)
	# current_health will be set by _on_player_stats_recalculated, which is called by initialize_base_stats_with_raw_dict
	push_warning("PlayerCharacter: Fallback stats applied. Ensure PlayerStats has 'initialize_base_stats_with_raw_dict' method.")


# Attempts to equip the initial weapon set during setup.
# This should run after weapon blueprints are confirmed loaded.
func _try_equip_initial_weapon():
	if _initial_weapon_equipped: return # Prevent double equipping

	# No initial weapon chosen, or WeaponManager isn't valid
	if _initial_chosen_weapon_id == &"" or not is_instance_valid(weapon_manager):
		_initial_weapon_equipped = true; return

	# Get the full blueprint resource from the game node
	if not is_instance_valid(game_node_ref):
		game_node_ref = get_tree().root.get_node_or_null("Game")
		if not is_instance_valid(game_node_ref):
			push_error("PlayerCharacter: Game node is not valid, cannot get weapon blueprint!"); return

	var weapon_blueprint = game_node_ref.get_weapon_blueprint_by_id(_initial_chosen_weapon_id)
	
	if is_instance_valid(weapon_blueprint):
		var success = weapon_manager.add_weapon(weapon_blueprint)
		if success and not weapon_blueprint.class_tag_restrictions.is_empty():
			# This implies that the blueprint's first class tag restriction is the class to increment.
			# Ensure this logic is correct for your game design.
			increment_basic_class_level(weapon_blueprint.class_tag_restrictions[0])
	else:
		push_error("PlayerCharacter: Failed to get weapon blueprint for ID: ", _initial_chosen_weapon_id)
	
	_initial_weapon_equipped = true


# This function is triggered by PlayerStats.gd whenever its stats are recalculated.
# PlayerCharacter updates its own derived properties here.
func _on_player_stats_recalculated(new_max_health_from_signal: float, new_movement_speed_from_signal: float):
	# Renamed parameters to avoid shadowing, although using the provided signal args is preferred.
	# The goal is to update current_health and current_pickup_magnet_radius.
	
	if not is_instance_valid(player_stats): return # Safety check

	# Retrieve the actual calculated max health and magnet range from PlayerStats.
	# Using the current_ (cached) properties on player_stats is the most consistent approach
	# as these are already updated by PlayerStats.recalculate_all_stats().
	var new_max_health = player_stats.current_max_health
	var new_magnet_range = player_stats.current_magnet_range
	
	# --- Health Scaling Logic ---
	# Calculate health percentage based on the *old* max health to maintain relative health.
	# We use _last_known_max_health which was correctly set during the *previous* recalculation or initialization.
	var health_percentage = 1.0
	if _last_known_max_health > 0: # Avoid division by zero if this is the very first initialization
		health_percentage = current_health / _last_known_max_health
	
	# Apply the percentage to the new max health to determine the new current health.
	current_health = clampf(new_max_health * health_percentage, 0.0, new_max_health)
	
	# Safety check: If max health is positive but current health became very small (e.g., due to float precision)
	# and the player was not dead, ensure they have at least 1 HP.
	if new_max_health > 0 and current_health < 0.01 and health_percentage > 0:
		current_health = 1.0
	
	# Update the _last_known_max_health for the next recalculation.
	_last_known_max_health = new_max_health
	
	# --- Magnet Range Update ---
	if current_pickup_magnet_radius != new_magnet_range:
		current_pickup_magnet_radius = new_magnet_range
		update_experience_collector_radius() # Call your method to update the actual Area2D radius

	# --- Signal Emission for UI Updates ---
	emit_signal("health_changed", current_health, new_max_health)

	# The new_movement_speed_from_signal argument can be used here if PlayerCharacter
	# needs to directly react to movement speed changes beyond just fetching it in _physics_process.
	# For example, if you have a temporary speed buff visual effect.


func _physics_process(delta: float):
	var input_direction = Vector2.ZERO
	if Input.is_action_pressed("move_right"): input_direction.x += 1
	if Input.is_action_pressed("move_left"): input_direction.x -= 1
	if Input.is_action_pressed("move_down"): input_direction.y += 1
	if Input.is_action_pressed("move_up"): input_direction.y -= 1

	# Get current movement speed from PlayerStats (using cached property for efficiency)
	var current_move_speed = player_stats.current_movement_speed
	
	if input_direction.length_squared() > 0:
		velocity = input_direction.normalized() * current_move_speed
		# Animated Sprite flipping logic
		if animated_sprite:
			if velocity.x < -0.01:
				animated_sprite.flip_h = true
				animated_sprite.offset.x = sprite_flip_x_compensation
			elif velocity.x > 0.01: # Check for positive velocity to ensure it's moving right
				animated_sprite.flip_h = false
				animated_sprite.offset.x = 0.0
			# Play walk animation
			if animated_sprite.animation != &"walk":
				animated_sprite.play(&"walk")
	else:
		velocity = Vector2.ZERO
		# Play idle animation if not moving
		if animated_sprite and animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	
	move_and_slide()
	
	# Health Regeneration
	if is_instance_valid(player_stats):
		var regen = player_stats.current_health_regeneration # Use cached current_ stat
		var current_max_hp = player_stats.current_max_health # Use cached current_ stat
		if regen > 0.0 and current_health < current_max_hp:
			current_health += regen * delta
			current_health = clampf(current_health, 0, current_max_hp) # Use clampf for floats
			emit_signal("health_changed", current_health, current_max_hp)


func _on_experience_collector_area_entered(area: Area2D):
	if area.is_in_group("exp_drops") and area.has_method("collected"):
		var exp_value: int = 0
		if area.has_method("get_experience_value"): # Prefer method if exists
			exp_value = area.get_experience_value()
		elif "experience_value" in area: # Fallback to property if method doesn't exist
			exp_value = area.experience_value
			
		# Get experience gain multiplier from PlayerStats (using cached property)
		var exp_gain_mod = player_stats.current_experience_gain_multiplier
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
		emit_signal("player_level_up", current_level)
		# Game.gd should listen to this signal and display the level-up screen.
		
		print("Player Leveled Up! New Level: ", current_level, ", Next Exp: ", experience_to_next_level)


func calculate_exp_for_next_level(player_curr_level: int) -> int:
	if player_curr_level < 1:
		return LINEAR_FACTOR_PER_LEVEL + int(BASE_FOR_EXPONENTIAL_PART * pow(EXPONENTIAL_SCALING_FACTOR, 0.0))
	var linear_part = LINEAR_FACTOR_PER_LEVEL * player_curr_level
	var exponential_part = BASE_FOR_EXPONENTIAL_PART * pow(EXPONENTIAL_SCALING_FACTOR, float(player_curr_level - 1))
	return linear_part + int(exponential_part)
	
func take_damage(amount: float, attacker: Node2D = null, p_attack_stats: Dictionary = {}): # Changed amount to float for consistency
	if current_health <= 0 or is_dead_flag: return # Do not take damage if dead or already dying
	
	# Apply global flat damage reduction first (from player's current_global_flat_damage_reduction)
	var incoming_damage = amount - player_stats.current_global_flat_damage_reduction
	incoming_damage = maxf(0.0, incoming_damage) # Ensure damage doesn't go below zero after flat reduction

	var current_armor = player_stats.current_armor # Use cached current_ stat
	var armor_penetration_value = float(p_attack_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION], 0.0)) # Get penetration from incoming attack

	# Calculate effective armor after penetration
	var effective_armor = maxf(0.0, current_armor - armor_penetration_value)
	
	# Basic damage reduction: raw damage - effective armor
	var actual_damage = maxf(0.0, incoming_damage - effective_armor)

	# Apply DAMAGE_REDUCTION_MULTIPLIER (from player's own buffs or debuffs)
	var damage_reduction_mult_val = player_stats.get_final_stat(PlayerStatKeys.Keys.DAMAGE_REDUCTION_MULTIPLIER)
	actual_damage *= (1.0 - damage_reduction_mult_val) # Assuming this is a reduction, so (1.0 - value)
	actual_damage = maxf(0.0, actual_damage) # Ensure damage doesn't go negative after reduction

	# Apply GLOBAL_PERCENT_DAMAGE_REDUCTION
	var global_percent_reduction = player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION)
	actual_damage *= (1.0 - global_percent_reduction)
	actual_damage = maxf(0.0, actual_damage)

	current_health = maxf(0.0, current_health - actual_damage)
	
	var current_max_hp = player_stats.current_max_health # Use cached current_ stat
	emit_signal("health_changed", current_health, current_max_hp)
	
	if is_instance_valid(attacker):
		emit_signal("player_took_damage_from", attacker)
		emit_signal("attacked_by_enemy", attacker)
		
	if current_health <= 0: die()


func die():
	if is_dead_flag: return # Prevent double death
	is_dead_flag = true
	emit_signal("player_has_died")
	set_physics_process(false) # Stop player movement/physics
	visible = false # Hide player sprite
	var mc = get_node_or_null("CollisionShape2D"); if is_instance_valid(mc): mc.disabled = true
	
func apply_upgrade(upgrade_data_wrapper: Dictionary):
	if not upgrade_data_wrapper is Dictionary:
		push_error("ERROR (PlayerCharacter): apply_upgrade did not receive a dictionary.")
		return
	
	var upgrade_type = upgrade_data_wrapper.get("type", "")
	var resource = upgrade_data_wrapper.get("resource_data")

	if not is_instance_valid(resource):
		push_error("ERROR (PlayerCharacter): apply_upgrade received wrapper with invalid or missing resource_data. Type: ", upgrade_type)
		return

	match upgrade_type:
		"new_weapon":
			if resource is WeaponBlueprintData:
				if is_instance_valid(weapon_manager) and weapon_manager.has_method("add_weapon"):
					var success = weapon_manager.add_weapon(resource)
					if success and not resource.class_tag_restrictions.is_empty():
						increment_basic_class_level(resource.class_tag_restrictions[0])
			else:
				push_error("PlayerCharacter: 'new_weapon' upgrade_type received non-WeaponBlueprintData resource: ", resource)
		"weapon_upgrade":
			if resource is WeaponUpgradeData:
				var weapon_id_to_upgrade = upgrade_data_wrapper.get("weapon_id_to_upgrade", &"")
				if weapon_id_to_upgrade != &"" and is_instance_valid(weapon_manager) and weapon_manager.has_method("apply_weapon_upgrade"):
					weapon_manager.apply_weapon_upgrade(StringName(weapon_id_to_upgrade), resource)
				else:
					push_error("PlayerCharacter: 'weapon_upgrade' missing weapon_id_to_upgrade or invalid manager.")
			else:
				push_error("PlayerCharacter: 'weapon_upgrade' upgrade_type received non-WeaponUpgradeData resource: ", resource)
		"general_upgrade":
			if resource is GeneralUpgradeCardData:
				# GeneralUpgradeCardData should contain an array of EffectData.
				# We now iterate over its effects and apply them individually.
				# This requires GeneralUpgradeCardData to have a 'get_effects_to_apply' method.
				if is_instance_valid(player_stats) and resource.has_method("get_effects_to_apply"):
					var effects_to_apply = resource.get_effects_to_apply()
					for effect in effects_to_apply:
						if not is_instance_valid(effect):
							push_warning("PlayerCharacter: General upgrade contains invalid (null) effect.")
							continue

						if effect is StatModificationEffectData:
							player_stats.apply_stat_modification(effect)
						elif effect is CustomFlagEffectData:
							player_stats.apply_custom_flag(effect)
						elif effect is TriggerAbilityEffectData:
							push_warning("PlayerCharacter: TriggerAbilityEffectData in GeneralUpgradeCardData is not yet fully implemented for direct application by PlayerCharacter.")
							# Implement handling for TriggerAbilityEffectData here (e.g., call a method on PlayerCharacter)
						elif effect is StatusEffectApplicationData:
							# For GeneralUpgrades, status effects usually apply to the player.
							if is_instance_valid(player_stats) and is_instance_valid(get_node_or_null("StatusEffectComponent")):
								var status_comp = get_node("StatusEffectComponent") as StatusEffectComponent
								var app_data = effect as StatusEffectApplicationData
								if is_instance_valid(status_comp) and is_instance_valid(app_data) and randf() < app_data.application_chance:
									status_comp.apply_effect(
										load(app_data.status_effect_resource_path) as StatusEffectData,
										self, # Source is player
										{}, # No weapon stats for scaling
										app_data.duration_override,
										app_data.potency_override
									)
							else:
								push_warning("PlayerCharacter: StatusEffectComponent not found for applying general upgrade status effect.")
						else:
							push_warning("PlayerCharacter: General upgrade contains unhandled effect type: ", effect.get_class())
				else:
					push_error("PlayerCharacter: GeneralUpgradeCardData missing 'get_effects_to_apply' method or player_stats invalid.")
			else:
				push_error("PlayerCharacter: 'general_upgrade' upgrade_type received non-GeneralUpgradeCardData resource: ", resource)
		_:
			push_error("PlayerCharacter: apply_upgrade received unknown upgrade type: '", upgrade_type, "'. Resource: ", resource)
	
	# After applying upgrades, signal PlayerStats to recalculate all its derived stats.
	if is_instance_valid(player_stats) and player_stats.has_method("recalculate_all_stats"):
		player_stats.recalculate_all_stats()

# --- NEW FUNCTION for Class Progression ---
func increment_basic_class_level(class_enum: BasicClass):
	if basic_class_levels.has(class_enum):
		basic_class_levels[class_enum] += 1
		print("Class Level Up! %s is now level %d" % [BasicClass.keys()[class_enum], basic_class_levels[class_enum]])
	else:
		push_warning("WARNING (PlayerCharacter): Tried to increment unknown class enum: ", class_enum)

# --- Existing Helper & Getter Functions ---
func update_experience_collector_radius():
	if is_instance_valid(experience_collector_area) and experience_collector_area.get_child_count() > 0:
		var cs = experience_collector_area.get_child(0) as CollisionShape2D
		if is_instance_valid(cs) and cs.shape is CircleShape2D:
			cs.shape.radius = current_pickup_magnet_radius
		else:
			push_warning("PlayerCharacter: ExperienceCollectorArea's first child is not a valid CollisionShape2D with a CircleShape2D.")
	else:
		push_warning("PlayerCharacter: ExperienceCollectorArea is invalid or has no children.")


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
func get_current_health_value() -> float: return current_health
func get_max_health_value() -> float:
	if is_instance_valid(player_stats):
		return player_stats.current_max_health # Use the cached current_max_health
	return 0.0

func get_ui_anchor_global_position() -> Vector2:
	if is_instance_valid(ui_anchor): return ui_anchor.global_position
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
	return []

func get_basic_class_levels_for_level_up() -> Dictionary:
	return basic_class_levels.duplicate(true)

func get_acquired_advanced_classes_for_level_up() -> Array[StringName]:
	return acquired_advanced_classes

func get_current_basic_class_enum() -> PlayerCharacter.BasicClass:
	return current_basic_class_enum_val

# NEW: Helper to get the StringName ID of the current basic class
func get_current_basic_class_id() -> StringName:
	return _current_basic_class_string_id

func heal(amount: float):
	if current_health <= 0: return
	var actual_max_health = get_max_health_value()
	current_health = clampf(current_health + amount, 0, actual_max_health)
	emit_signal("health_changed", current_health, actual_max_health)
