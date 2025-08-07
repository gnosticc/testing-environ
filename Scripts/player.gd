# player.gd

extends CharacterBody2D
class_name PlayerCharacter

# --- Visual Adjustment of Character Sprite ---
@export var sprite_flip_x_compensation: float = 0.0

var current_health: float = 0.0 # Initialized here, will be set from PlayerStats.MAX_HEALTH on init
var current_pickup_magnet_radius: float = 0.0
var is_dead_flag: bool = false # FIXED: Declared is_dead_flag here
var is_invulnerable: bool = false
var _last_known_max_health: float = 0.0 # Initialize here to ensure it's always set

# --- Component References ---
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var player_stats: PlayerStats = $PlayerStats # Reference to the PlayerStats child node
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent
@onready var attacks_container: Node2D # Container for spawned attacks (e.g., projectiles)
@onready var experience_collector_area: Area2D = $ExperienceCollectorArea
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ui_anchor: Marker2D = $AnimatedSprite2D/UIAnchor # Anchor point for UI elements above player
@onready var melee_aiming_dot: Node2D = $MeleeAimingDot

# --- Signals ---
signal health_changed(current_health_value, max_health_value)
signal temp_health_changed(current_temp_health) # NEW: Signal for the temp health bar
signal experience_changed(current_exp, exp_to_next_level, player_level)
signal player_level_up(new_level)
signal player_class_tier_upgraded(new_class_id, contributing_basic_classes)
signal player_has_died
signal player_took_damage_from(attacker_node: Node)

# --- Experience and Leveling Variables ---
var current_experience: int = 0
var experience_to_next_level: int = 10
var current_level: int = 1

const LINEAR_FACTOR_PER_LEVEL: int = 40
const BASE_FOR_EXPONENTIAL_PART: int = 10
const EXPONENTIAL_SCALING_FACTOR: float = 1.25

# --- Class Progression Tracking ---
enum BasicClass {
	NONE, WARRIOR, KNIGHT, ROGUE, WIZARD, DRUID, CONJURER
}
var current_basic_class_enum_val: PlayerCharacter.BasicClass = BasicClass.NONE
var _current_basic_class_string_id: StringName = &"none"
# NEW: Dictionary to track total levels for each basic class.
var basic_class_levels: Dictionary = {
	BasicClass.WARRIOR: 0, BasicClass.KNIGHT: 0, BasicClass.ROGUE: 0,
	BasicClass.WIZARD: 0, BasicClass.DRUID: 0, BasicClass.CONJURER: 0
}
# NEW: Array to track which advanced classes have been unlocked.
var acquired_advanced_classes: Array[StringName] = []
var acquired_general_upgrade_ids: Array[StringName] = []
var current_sprite_preference: String = "default"
var prefer_current_sprite_after_first_advanced: bool = false

# --- Initialization State ---
var _initial_chosen_class_enum: PlayerCharacter.BasicClass = PlayerCharacter.BasicClass.NONE
var _initial_chosen_weapon_id: StringName = &""
var _initial_weapon_equipped: bool = false
var game_node_ref: Node

var _tactician_bonus_armor: int = 0
var _tactician_timer: Timer
var _temp_max_health_bonus: float = 0.0
var _temp_health_decay_timer: Timer

var knockback_velocity: Vector2 = Vector2.ZERO
var external_forces: Vector2 = Vector2.ZERO

const SHADOW_CLONE_SCENE = preload("res://Scenes/Weapons/Advanced/Summons/ShadowClone.tscn")


func _ready():
	# Critical: Ensure PlayerStats and WeaponManager are valid before proceeding.
	if not is_instance_valid(player_stats) or not is_instance_valid(weapon_manager):
		push_error("CRITICAL ERROR (PlayerCharacter): PlayerStats or WeaponManager node missing!"); return

	game_node_ref = get_tree().root.get_node_or_null("Game")

	if is_instance_valid(game_node_ref) and game_node_ref.has_signal("weapon_blueprints_ready"):
		game_node_ref.weapon_blueprints_ready.connect(Callable(self, "_on_game_weapon_blueprints_ready"), CONNECT_ONE_SHOT)
	else:
		push_warning("PlayerCharacter: Game node or 'weapon_blueprints_ready' signal not found. Proceeding with default setup.")
		_on_game_weapon_blueprints_ready()
	if is_instance_valid(game_node_ref) and not game_node_ref.is_connected("enemy_was_killed", Callable(self, "_on_enemy_killed_by_attacker")):
		game_node_ref.enemy_was_killed.connect(Callable(self, "_on_enemy_killed_by_attacker"))

	CombatEvents.death_mark_triggered.connect(_on_death_mark_triggered)
	CombatEvents.lingering_charge_triggered.connect(_on_lingering_charge_triggered)
	
	if experience_collector_area:
		if not experience_collector_area.is_connected("area_entered", Callable(self, "_on_experience_collector_area_entered")):
			experience_collector_area.area_entered.connect(Callable(self, "_on_experience_collector_area_entered"))
	
	experience_to_next_level = calculate_exp_for_next_level(current_level)
	
	_tactician_timer = Timer.new()
	_tactician_timer.name = "TacticianTimer"
	_tactician_timer.wait_time = 1.0
	_tactician_timer.timeout.connect(_on_tactician_timer_timeout)
	add_child(_tactician_timer)

	_temp_health_decay_timer = Timer.new()
	_temp_health_decay_timer.name = "TempHealthDecayTimer"
	_temp_health_decay_timer.wait_time = 1.0
	_temp_health_decay_timer.timeout.connect(_on_temp_health_decay_timeout)
	add_child(_temp_health_decay_timer)

	if is_instance_valid(player_stats):
		if not player_stats.is_connected("stats_recalculated", Callable(self, "_on_player_stats_recalculated")):
			player_stats.stats_recalculated.connect(Callable(self, "_on_player_stats_recalculated"))
	else:
		push_error("PlayerCharacter: PlayerStats node is invalid in _ready().")

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

func _on_enemy_killed_by_attacker(attacker_node: Node, killed_enemy_node: Node):
	# --- Soul Siphon Logic ---
	# This check runs first and does not depend on the attacker.
	if player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_SOUL_SIPHON):
		if CombatTracker.was_enemy_hit_by_weapon_within_seconds(&"warrior_scythe", killed_enemy_node, 0.5):
			var chance = 0.10
			if randf() < chance:
				var base_heal = 3
				var player_luck = player_stats.get_final_stat(PlayerStatKeys.Keys.LUCK)
				var effective_luck = max(1, int(player_luck))
				self.heal(float(base_heal * effective_luck))
				print_debug("Soul Siphon Procced! Healed for ", float(base_heal * effective_luck))

	# --- Rampage Logic ---
	# Second, handle Rampage. This logic no longer checks who the attacker was.
	# It triggers on ANY kill, as long as the player has the upgrade.
	if player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_RAMPAGE):
		var rampage_buff_data = load("res://DataResources/StatusEffects/rampage_buff.tres") as StatusEffectData
		if is_instance_valid(rampage_buff_data) and is_instance_valid(status_effect_component):
			status_effect_component.apply_effect(rampage_buff_data, self)


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

# Finds a specified number of the nearest enemies and returns them in an array.
func _find_nearest_enemies(p_num_to_find: int, p_from_position: Vector2 = Vector2.INF, p_exclude_list: Array = []) -> Array[Node2D]:
	var enemies_in_scene = get_tree().get_nodes_in_group("enemies")
	var valid_enemies = []
	
	var search_origin = p_from_position
	if search_origin == Vector2.INF: search_origin = global_position
	
	if enemies_in_scene.is_empty(): return []
	
	# First, filter out invalid or excluded enemies and calculate distances
	for enemy_node in enemies_in_scene:
		if is_instance_valid(enemy_node) and not p_exclude_list.has(enemy_node) and not enemy_node.is_dead():
			var dist_sq = search_origin.distance_squared_to(enemy_node.global_position)
			valid_enemies.append({"node": enemy_node, "dist_sq": dist_sq})
			
	# Sort the enemies by distance (ascending)
	valid_enemies.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	
	# Get the final list of nodes to return
	var nearest_enemies: Array[Node2D] = []
	var count = min(p_num_to_find, valid_enemies.size())
	for i in range(count):
		nearest_enemies.append(valid_enemies[i].node)
		
	return nearest_enemies

func _on_lingering_charge_triggered(p_position: Vector2, p_weapon_stats: Dictionary, p_source_player: Node, p_dying_enemy: Node):
	# FIX: Use the dying enemy in the exclusion list.
	var nearest_enemy = _find_nearest_enemy(p_position, [p_dying_enemy])
	if is_instance_valid(nearest_enemy):
		if is_instance_valid(nearest_enemy.status_effect_component):
			var conduit_status = load("res://DataResources/StatusEffects/living_conduit_status.tres") as StatusEffectData
			if is_instance_valid(conduit_status):
				print_debug("  Applying fresh Living Conduit status.")
				# Pass the original source player, not self.
				nearest_enemy.status_effect_component.apply_effect(conduit_status, p_source_player, p_weapon_stats)

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
	if not is_instance_valid(player_stats): return

	var new_max_health = player_stats.current_max_health
	var new_magnet_range = player_stats.current_magnet_range
	
	var health_percentage = 1.0
	if _last_known_max_health > 0:
		health_percentage = current_health / _last_known_max_health
	
	current_health = clampf(new_max_health * health_percentage, 0.0, new_max_health)
	
	if new_max_health > 0 and current_health < 0.01 and health_percentage > 0:
		current_health = 1.0
	
	_last_known_max_health = new_max_health

	if player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_TACTICIAN) and _tactician_timer.is_stopped():
		_tactician_timer.start()
		
	if current_pickup_magnet_radius != new_magnet_range:
		current_pickup_magnet_radius = new_magnet_range
		update_experience_collector_radius()

	emit_signal("health_changed", current_health, get_max_health_value())


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

	# Add any external forces (like from the gravity well) to the velocity
	if external_forces.length_squared() > 0:
		velocity += external_forces
		
	move_and_slide()

	# Reset external forces each frame so they don't accumulate indefinitely
	external_forces = Vector2.ZERO

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
# The logic here is corrected to ensure temporary health is used as a buffer first.
func take_damage(damage_amount: float, attacker: Node2D = null, p_attack_stats: Dictionary = {}, _p_weapon_tags: Array[StringName] = []):
	if is_invulnerable or is_dead_flag: return

	# --- Calculate Final Damage ---
	var final_armor = player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR)
	if player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_TACTICIAN):
		final_armor += _tactician_bonus_armor
		_tactician_bonus_armor = 0
		
	var percent_reduction = player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_PERCENT_DAMAGE_REDUCTION)
	var flat_reduction = player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_FLAT_DAMAGE_REDUCTION)
	var armor_pen = float(p_attack_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION], 0.0))

	# --- INSERTED DEBUG BLOCK ---
	print_debug("--- Player Taking Damage ---")
	print_debug("Initial Incoming Damage: ", damage_amount)
	print_debug("Player Stats | Percent Reduction: ", percent_reduction, " (From Knight's Resolve, etc.)")
	print_debug("Player Stats | Flat Reduction: ", flat_reduction)
	print_debug("Player Stats | Armor: ", final_armor)
	print_debug("Attacker Stats | Armor Penetration: ", armor_pen)
	# --- END INSERTED DEBUG BLOCK ---

	var dodge_chance = player_stats.get_final_stat(PlayerStatKeys.Keys.DODGE_CHANCE)
	if randf() < dodge_chance:
		print("DEBUG (Leverage): DODGE! Incoming damage of ", damage_amount, " was avoided.")
		return

	var damage_after_flat = maxf(0.0, damage_amount - flat_reduction)
	var effective_armor = maxf(0.0, final_armor - armor_pen)
	var damage_after_armor = maxf(0.0, damage_after_flat - effective_armor)
	var final_damage = damage_after_armor * (1.0 - percent_reduction)
	
	# --- Apply Damage to Health Pools (Corrected Logic) ---
	var remaining_damage = final_damage
	
	# 1. Absorb damage with temporary health first.
	if _temp_max_health_bonus > 0:
		var damage_to_temp_hp = min(_temp_max_health_bonus, remaining_damage)
		_temp_max_health_bonus -= damage_to_temp_hp
		remaining_damage -= damage_to_temp_hp
		emit_signal("temp_health_changed", _temp_max_health_bonus) # NEW: Emit signal
		print_debug("Champion's Resolve: Temp HP absorbed ", damage_to_temp_hp, " damage. Remaining temp HP: ", _temp_max_health_bonus)

	# 2. Apply any leftover damage to the main health pool.
	if remaining_damage > 0:
		current_health -= remaining_damage
		emit_signal("health_changed", current_health, get_max_health_value())
	
	# --- Post-Damage Checks & Signal Emission ---
	if is_instance_valid(attacker):
		emit_signal("player_took_damage_from", attacker)
		
	if current_health <= 0:
		# Check for death-defying effects like Philosopher's Stone
		var weapon_manager = get_node_or_null("WeaponManager")
		if is_instance_valid(weapon_manager):
			var weapon_entry_index = weapon_manager._get_weapon_entry_index_by_id(&"alchemist_experimental_materials")
			if weapon_entry_index != -1:
				var weapon_entry = weapon_manager.active_weapons[weapon_entry_index]
				var controller = weapon_entry.get("persistent_instance")
				if is_instance_valid(controller) and controller.is_philosophers_stone_ready():
					controller.trigger_philosophers_stone_cooldown()
					current_health = get_max_health_value()
					emit_signal("health_changed", current_health, get_max_health_value())
					return # Prevent death
		
		# If no death-defying effects, the player dies.
		die()
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
func _on_tactician_timer_timeout():
	if _tactician_bonus_armor < 9999:
		_tactician_bonus_armor += 1
		player_stats.recalculate_all_stats() # Update stats to reflect new armor

func _on_temp_health_decay_timeout():
	if _temp_max_health_bonus > 0:
		_temp_max_health_bonus = max(0.0, _temp_max_health_bonus - 10.0)
		emit_signal("temp_health_changed", _temp_max_health_bonus) # NEW: Emit signal
		print_debug("Champion's Resolve: Decayed 10 temp HP. Remaining: ", _temp_max_health_bonus)
	else:
		_temp_health_decay_timer.stop()
		print_debug("Champion's Resolve: Temp HP fully decayed. Timer stopped.")

func add_temporary_max_health(amount: float):
	var old_bonus = _temp_max_health_bonus
	_temp_max_health_bonus = min(500.0, _temp_max_health_bonus + amount)
	emit_signal("temp_health_changed", _temp_max_health_bonus) # NEW: Emit signal
	print_debug("Champion's Resolve: Gained ", amount, " temp HP. Total temp HP: ", _temp_max_health_bonus)
	
	if _temp_health_decay_timer.is_stopped():
		_temp_health_decay_timer.start()
		print_debug("Champion's Resolve: Decay timer started.")
	
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
						if resource.class_tag_restrictions[0] is int:
							increment_basic_class_level(resource.class_tag_restrictions[0])
		
		"weapon_upgrade":
			if resource is WeaponUpgradeData:
				var weapon_id_to_upgrade = upgrade_data_wrapper.get("weapon_id_to_upgrade", &"")
				if weapon_id_to_upgrade != &"" and is_instance_valid(weapon_manager) and weapon_manager.has_method("apply_weapon_upgrade"):
					weapon_manager.apply_weapon_upgrade(StringName(weapon_id_to_upgrade), resource)
					
					var weapon_bp = game_node_ref.get_weapon_blueprint_by_id(weapon_id_to_upgrade)
					if is_instance_valid(weapon_bp) and not weapon_bp.class_tag_restrictions.is_empty():
						if weapon_bp.class_tag_restrictions[0] is int:
							increment_basic_class_level(weapon_bp.class_tag_restrictions[0])

		"general_upgrade":
			if resource is GeneralUpgradeCardData:
				# NEW: Add the ID of the chosen upgrade to our tracking list.
				acquired_general_upgrade_ids.append(resource.id)
				for effect in resource.effects:
					if effect.target_scope == &"player_stats":
						if effect is StatModificationEffectData:
							player_stats.apply_stat_modification(effect)
						elif effect is CustomFlagEffectData:
							player_stats.apply_custom_flag(effect)

		
		"advanced_class_unlock":
			if resource is PlayerClassTierData:
				var class_tier_data = resource as PlayerClassTierData
				if not acquired_advanced_classes.has(class_tier_data.class_id):
					acquired_advanced_classes.append(class_tier_data.class_id)
					print("Advanced Class Unlocked: ", class_tier_data.display_name)

					# MODIFIED: Apply permanent stat bonuses using the new dedicated function.
					for effect_data in class_tier_data.permanent_stat_bonuses:
						if is_instance_valid(effect_data) and effect_data.target_scope == &"player_stats":
							if effect_data is StatModificationEffectData:
								# This now calls the new function in PlayerStats to directly modify base values.
								player_stats.apply_permanent_base_stat_bonus(effect_data)
							elif effect_data is CustomFlagEffectData:
								player_stats.apply_custom_flag(effect_data)
					
					emit_signal("player_class_tier_upgraded", class_tier_data.class_id, [])
				else:
					push_warning("PlayerCharacter: Tried to unlock an already acquired advanced class: ", class_tier_data.class_id)
		_:
			push_error("PlayerCharacter: apply_upgrade received unknown upgrade type: '", upgrade_type, "'. Resource: ", resource)
	
	if is_instance_valid(player_stats) and player_stats.has_method("recalculate_all_stats"):
		player_stats.recalculate_all_stats()

# NEW: Function to increment the level count for a basic class.
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
	var base_max = 0.0
	if is_instance_valid(player_stats):
		base_max = player_stats.current_max_health
	return base_max # This now correctly returns only the permanent max health

func get_ui_anchor_global_position() -> Vector2:
	if is_instance_valid(ui_anchor): return ui_anchor.global_position
	return self.global_position

func _find_nearest_enemy(p_from_position: Vector2 = Vector2.INF, p_exclude_list: Array = []) -> Node2D:
	var enemies_in_scene = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy: Node2D = null; var min_dist_sq = INF

	var search_origin = p_from_position
	if search_origin == Vector2.INF: search_origin = global_position
	if enemies_in_scene.is_empty(): return null
	for enemy_node in enemies_in_scene:
		# FIX: Incorporate the exclude list into the check
		if not is_instance_valid(enemy_node) or p_exclude_list.has(enemy_node): continue
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
	
# FIX: Added the missing function that SwordCoilProjectile needs.
func get_total_levels_for_class(class_enum_to_check: BasicClass) -> int:
	if not is_instance_valid(weapon_manager): return 0
	
	var total_levels = 0
	# Iterate through the definitive list of active weapons.
	for weapon_data in weapon_manager.active_weapons:
		# Access the loaded blueprint resource directly.
		var blueprint = weapon_data.get("blueprint_resource") as WeaponBlueprintData
		if is_instance_valid(blueprint):
			# Check if the weapon's class tags include the one we're looking for.
			if blueprint.class_tag_restrictions.has(class_enum_to_check):
				total_levels += weapon_data.get("weapon_level", 0)
				
	return total_levels

func _on_death_mark_triggered(enemy_position: Vector2, clone_stats: Dictionary):
	if not is_instance_valid(self) or not is_instance_valid(player_stats): return

	if is_instance_valid(SHADOW_CLONE_SCENE):
		var clone = SHADOW_CLONE_SCENE.instantiate()
		get_tree().current_scene.add_child(clone)
		clone.global_position = enemy_position
		
		# The clone needs a direction to face. We'll have it face away from the player.
		var direction = (enemy_position - self.global_position).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT

		if clone.has_method("initialize"):
			clone.initialize(direction, clone_stats, player_stats)

func get_current_velocity() -> Vector2:
	return velocity

func apply_external_force(force: Vector2):
	external_forces += force

# NEW: Public debug functions to be called by the DebugPanel.

# Sets the level of a specific basic class manually.
func debug_set_basic_class_level(class_enum: BasicClass, level: int):
	if basic_class_levels.has(class_enum):
		basic_class_levels[class_enum] = max(0, level)
	else:
		push_warning("PlayerCharacter DEBUG: Attempted to set level for invalid class enum: ", class_enum)

# Resets all class progression data to its initial state.
func debug_reset_class_progression():
	for key in basic_class_levels:
		basic_class_levels[key] = 0
	acquired_advanced_classes.clear()
	print("PlayerCharacter DEBUG: Class progression has been reset.")

# Applies a general upgrade by wrapping it in the expected dictionary format
# and calling the existing apply_upgrade function.
func debug_add_general_upgrade(upgrade_data: GeneralUpgradeCardData):
	if not is_instance_valid(upgrade_data):
		push_error("PlayerCharacter DEBUG: Tried to add an invalid GeneralUpgradeCardData.")
		return
		
	var upgrade_wrapper = {
		"type": "general_upgrade",
		"resource_data": upgrade_data
	}
	apply_upgrade(upgrade_wrapper)
	print("PlayerCharacter DEBUG: Applied general upgrade '", upgrade_data.id, "'.")

# Clears all acquired general upgrades and recalculates stats to remove their effects.
func debug_reset_general_upgrades():
	acquired_general_upgrade_ids.clear()
	if is_instance_valid(player_stats):
		# We need to re-initialize the player's stats from their class base
		# to effectively remove all modifiers applied by the general upgrades.
		var class_data = game_node_ref.get_player_class_data_by_id(_current_basic_class_string_id)
		if is_instance_valid(class_data):
			player_stats.initialize_base_stats(class_data)
			# Re-apply any advanced class bonuses after the reset
			for class_id in acquired_advanced_classes:
				# This part assumes a function exists to get class tier data by id
				# We will add this to game.gd if it doesn't exist.
				pass # Placeholder for re-applying advanced class stats
			player_stats.recalculate_all_stats()
	print("PlayerCharacter DEBUG: All general upgrades have been reset.")
