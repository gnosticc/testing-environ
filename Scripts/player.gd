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
var is_invulnerable: bool = false

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
signal player_took_damage_from(attacker_node: Node)

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
	#if is_instance_valid(game_node_ref) and not game_node_ref.is_connected("enemy_was_killed", _on_enemy_was_killed):
		#game_node_ref.enemy_was_killed.connect(_on_enemy_was_killed)
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
	# NEW: Connect to the global combat event bus.
	if not CombatEvents.is_connected("status_effect_applied", Callable(self, "_on_status_effect_applied")):
		CombatEvents.status_effect_applied.connect(_on_status_effect_applied)

# NEW: This function handles all reactive player abilities.
func _on_status_effect_applied(owner: Node, effect_id: StringName, source: Node):
	print("DEBUG (PlayerCharacter): Status effect applied: ID=", effect_id, ", Owner=", owner.name, ", Source=", source.name)
	print("DEBUG (PlayerCharacter): PLAYER_HAS_CHAIN_BASH flag state: ", player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_CHAIN_BASH))

	# Check if this player was the source of the effect.
	if source != self:
		return
		
	# Check if the effect applied was a stun.
	if effect_id == &"stun":
		var stunned_enemy = owner as BaseEnemy
		if not is_instance_valid(stunned_enemy): return

		# Check for Tremorwave
		if player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_TREMORWAVE):
			print("DEBUG (Tremorwave): Player has Tremorwave, applying 'Weakened' to ", stunned_enemy.name)
			var weakened_data = load("res://DataResources/StatusEffects/weakened_status.tres")
			if is_instance_valid(stunned_enemy.status_effect_component):
				stunned_enemy.status_effect_component.apply_effect(weakened_data, self)

		if player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_CHAIN_BASH):
			#print("DEBUG (Chain Bash): Player has Chain Bash, attempting to execute from ", stunned_enemy.name)
			_execute_chain_bash_from_player(stunned_enemy)

func _execute_chain_bash_from_player(stunned_enemy: BaseEnemy):
	var search_radius = 70.0
	var hit_list: Array[BaseEnemy]
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy != stunned_enemy and enemy is BaseEnemy and not enemy.is_dead():
			if stunned_enemy.global_position.distance_to(enemy.global_position) <= search_radius:
				hit_list.append(enemy)

	if hit_list.is_empty(): 
		#print("DEBUG (Chain Bash): No valid targets found in range.")
		return
		
	var damage_to_chain = stunned_enemy._last_damage_instance_received
	if damage_to_chain <= 0: return

	#print("DEBUG (Chain Bash): Found ", hit_list.size(), " targets. Spawning visuals.")
	# Prepare attack_stats once, to be passed to the delayed damage function
	var attack_stats = {
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: self.player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
	}
	for target in hit_list:
		# Spawn the visual immediately (once per target pair)
		var visual = load("res://Scenes/Effects/ChainBashVisual.tscn").instantiate()
		get_tree().current_scene.add_child(visual)
		if visual.has_method("initialize"):
			visual.initialize(stunned_enemy.global_position, target.global_position) # Visual starts playing
		
		# Create a timer to deal damage AFTER the visual has played out
		var damage_delay_seconds = 0.5 # Matches ChainBashVisual's lifetime_timer
		var damage_timer = get_tree().create_timer(damage_delay_seconds)
		# Bind all necessary parameters for _deal_chain_bash_damage, including attack_stats
		damage_timer.timeout.connect(_deal_chain_bash_damage.bind(target, damage_to_chain, attack_stats))

func _deal_chain_bash_damage(target: BaseEnemy, damage: int, attack_stats: Dictionary): # Added attack_stats parameter
	if is_instance_valid(target) and not target.is_dead():
		#print("DEBUG (Chain Bash): Dealing ", damage, " damage to ", target.name, " after delay.")
		# Use the attack_stats passed from the timer binding
		target.take_damage(damage, self, attack_stats)

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

	var current_move_speed = player_stats.current_movement_speed
	
	if input_direction.length_squared() > 0:
		velocity = input_direction.normalized() * current_move_speed
		if animated_sprite:
			if velocity.x < -0.01:
				animated_sprite.flip_h = true
				animated_sprite.offset.x = sprite_flip_x_compensation
			elif velocity.x > 0.01:
				animated_sprite.flip_h = false
				animated_sprite.offset.x = 0.0
			if animated_sprite.animation != &"walk":
				animated_sprite.play(&"walk")
	else:
		velocity = Vector2.ZERO
		if animated_sprite and animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	
	move_and_slide()
	
	# --- REVISED: Health Regeneration ---
	if is_instance_valid(player_stats):
		var current_max_hp = player_stats.current_max_health
		if current_health < current_max_hp:
			# Get both flat and percent-based regen from PlayerStats
			var flat_regen = player_stats.get_final_stat(PlayerStatKeys.Keys.HEALTH_REGENERATION)
			var percent_regen = player_stats.get_final_stat(PlayerStatKeys.Keys.HEALTH_REGEN_PERCENT_MAX_HP)
			
			# Calculate total regeneration for this frame
			var total_regen_per_second = flat_regen + (percent_regen * current_max_hp)
			
			if total_regen_per_second > 0:
				current_health += total_regen_per_second * delta
				current_health = clampf(current_health, 0, current_max_hp)
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
	
# This function is called when an enemy's attack hits the player.
func take_damage(damage_amount: float, attacker: Node2D = null, p_attack_stats: Dictionary = {}):
	if is_invulnerable or is_dead_flag: return

	# --- KNIGHT'S RESOLVE & DAMAGE REDUCTION LOGIC ---
	# Get all relevant damage reduction stats from the PlayerStats node.
	var percent_reduction = player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION)
	var flat_reduction = player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_FLAT_DAMAGE_REDUCTION)
	var armor = player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR)
	var armor_pen = float(p_attack_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION], 0.0))

	# --- DEBUGGING PRINTS ---
	# These prints will show the entire calculation, making it clear if Knight's Resolve is working.
	print_debug("--- Player Taking Damage ---")
	print_debug("Initial Incoming Damage: ", damage_amount)
	print_debug("Player Stats | Percent Reduction: ", percent_reduction, " (From Knight's Resolve, etc.)")
	print_debug("Player Stats | Flat Reduction: ", flat_reduction)
	print_debug("Player Stats | Armor: ", armor)
	print_debug("Attacker Stats | Armor Penetration: ", armor_pen)
	
	# --- DAMAGE CALCULATION PIPELINE ---
	# 1. Leverage (Dodge) Check
	var dodge_chance = player_stats.get_final_stat(PlayerStatKeys.Keys.DODGE_CHANCE)
	if randf() < dodge_chance:
		print("DEBUG (Leverage): DODGE! Incoming damage of ", damage_amount, " was avoided.")
		# Optional: spawn a "Dodge!" text effect here
		return # Stop further processing
	# 1. Apply flat reduction first.
	var damage_after_flat_redux = max(0, damage_amount - flat_reduction)
	
	# 2. Calculate effective armor after penetration.
	var effective_armor = max(0, armor - armor_pen)
	var damage_after_armor = max(0, damage_after_flat_redux - effective_armor)

	# 3. Apply percentage-based reduction last.
	var final_damage = damage_after_armor * (1.0 - percent_reduction)
	final_damage = max(0, final_damage) # Ensure damage never becomes negative.
	
	# --- FINAL DEBUG PRINT ---
	print_debug("Final Calculated Damage to Player: ", final_damage)
	print_debug("--------------------------")

	current_health -= final_damage
	
	emit_signal("health_changed", current_health, player_stats.get_final_stat(PlayerStatKeys.Keys.MAX_HEALTH))
	
	if is_instance_valid(attacker):
		emit_signal("player_took_damage_from", attacker)
		
	if current_health <= 0:
		die() # Assumes a _die() function exists

	#else:
		#start_invulnerability() # Assumes a start_invulnerability() function exists

# NEW: Function to handle Rimeheart logic.
#func _on_enemy_was_killed(enemy_node: BaseEnemy, _killer_node: Node):
	#if not is_instance_valid(enemy_node): return
	#
	## Iterate through all active Frozen Territory orbs.
	#for child in get_children():
		#if child is FrozenTerritoryInstance:
			#var ft_instance = child as FrozenTerritoryInstance
			#if not is_instance_valid(ft_instance): continue
#
			## Check if this orb has the Rimeheart upgrade.
			#if ft_instance.specific_weapon_stats.get(&"has_rimeheart", false):
				## Check if the killed enemy was within the orb's damage area.
				## This requires FrozenTerritoryInstance to have a public list of enemies.
				## For simplicity, we'll check distance.
				#var orbit_center = self.global_position + Vector2.RIGHT.rotated(ft_instance.current_angle) * ft_instance.orbit_radius
				#if enemy_node.global_position.distance_to(orbit_center) <= ft_instance.collision_shape.shape.radius * ft_instance.scale.x:
					#
					#var chance = float(ft_instance.specific_weapon_stats.get(&"rimeheart_chance", 0.25))
					#if randf() < chance:
						## Spawn an icy explosion. We can reuse the SparkExplosion scene for this.
						#var explosion_scene = load("res://Scenes/Weapons/Projectiles/RimeheartExplosion.tscn")
						#if is_instance_valid(explosion_scene):
							#var explosion = explosion_scene.instantiate()
							#get_tree().current_scene.add_child(explosion)
							#explosion.global_position = enemy_node.global_position
							#
							#var damage_percent = float(ft_instance.specific_weapon_stats.get(&"rimeheart_damage_percent", 0.5))
							#var explosion_damage = int(ft_instance.damage_on_contact * damage_percent)
							#var explosion_radius = float(ft_instance.specific_weapon_stats.get(&"rimeheart_radius", 80.0))
							#
							#if explosion.has_method("detonate"):
								#explosion.detonate(explosion_damage, explosion_radius, self, {}, false)
						#break # Only one orb needs to proc the explosion.

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
					# --- NEW: Grant class experience on upgrade ---
					var weapon_bp = game_node_ref.get_weapon_blueprint_by_id(weapon_id_to_upgrade)
					if is_instance_valid(weapon_bp) and not weapon_bp.class_tag_restrictions.is_empty():
						increment_basic_class_level(weapon_bp.class_tag_restrictions[0])
					
					weapon_manager.apply_weapon_upgrade(StringName(weapon_id_to_upgrade), resource)
				else:
					push_error("PlayerCharacter: 'weapon_upgrade' missing weapon_id_to_upgrade or invalid manager.")
			else:
				push_error("PlayerCharacter: 'weapon_upgrade' upgrade_type received non-WeaponUpgradeData resource: ", resource)
		
		"general_upgrade":
			if resource is GeneralUpgradeCardData:
				if is_instance_valid(player_stats) and resource.has_method("get_effects_to_apply"):
					var effects_to_apply = resource.get_effects_to_apply()
					for effect in effects_to_apply:
						# ... (logic for applying general effects is the same)
						pass
			else:
				push_error("PlayerCharacter: 'general_upgrade' upgrade_type received non-GeneralUpgradeCardData resource: ", resource)
		_:
			push_error("PlayerCharacter: apply_upgrade received unknown upgrade type: '", upgrade_type, "'. Resource: ", resource)
	
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
	
