# File: res://Scripts/Weapons/Advanced/ReinforcementsController.gd
# This controller is the central factory for all Mechamaster turrets.
# It is a persistent node that manages independent timers for each turret type.
class_name ReinforcementsController
extends Node2D

# --- Turret Scenes (Assign in Inspector) ---
@export var sentry_turret_scene: PackedScene
@export var artillery_bot_scene: PackedScene
@export var hunter_killer_bot_scene: PackedScene
@export var aegis_protector_scene: PackedScene

# --- Node References ---
@onready var sentry_timer: Timer = $SentryTimer
@onready var artillery_timer: Timer = $ArtilleryTimer
@onready var hunter_killer_timer: Timer = $HunterKillerTimer
@onready var aegis_timer: Timer = $AegisTimer
@onready var assembly_line_timer: Timer = $AssemblyLineTimer

# --- Internal State ---
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager
var _owner_player: PlayerCharacter

# This is called once by WeaponManager when the weapon is first acquired.
func initialize(p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	_owner_player = p_player_stats.get_parent()

	# Connect all timers to their respective spawn functions
	sentry_timer.timeout.connect(_spawn_sentry_turret)
	artillery_timer.timeout.connect(_spawn_artillery_bot)
	hunter_killer_timer.timeout.connect(_spawn_hunter_killer_bot)
	aegis_timer.timeout.connect(_spawn_aegis_protector)
	assembly_line_timer.timeout.connect(_spawn_random_turret_from_assembly)
	
	# Initial stat update and timer start
	update_stats(p_stats)

# This is called by WeaponManager whenever an upgrade is applied to this weapon.
func update_stats(new_stats: Dictionary):
	_specific_stats = new_stats
	
	# Update and manage the timer for each turret type based on whether it's unlocked.
	_update_timer(sentry_timer, "sentry_deployment_cooldown", true) # Sentry is always unlocked
	_update_timer(artillery_timer, "artillery_deployment_cooldown", _specific_stats.get("has_artillery_bot", false))
	_update_timer(hunter_killer_timer, "hunter_killer_deployment_cooldown", _specific_stats.get("has_hk_bot", false))
	_update_timer(aegis_timer, "aegis_deployment_cooldown", _specific_stats.get("has_aegis_protector", false))
	_update_timer(assembly_line_timer, "assembly_line_cooldown", _specific_stats.get("has_assembly_line", false))

# Helper function to manage a timer's state and cooldown.
func _update_timer(timer: Timer, cooldown_key: String, is_active: bool):
	if not is_instance_valid(timer): return
	
	if is_active:
		var base_cooldown = float(_specific_stats.get(cooldown_key, 5.0))
		# Apply weapon-specific cooldown reduction from upgrades like "Mobile Emplacements".
		var weapon_cdr = float(_specific_stats.get("turret_deployment_cdr", 0.0))
		
		# REMOVED: The line fetching global_cooldown_reduction_mult has been removed.
		# The final_cooldown calculation now only uses the weapon-specific modifier.
		var final_cooldown = base_cooldown * (1.0 - weapon_cdr)
		timer.wait_time = max(0.1, final_cooldown)
		
		if timer.is_stopped():
			timer.start()
	else:
		if not timer.is_stopped():
			timer.stop()

# --- Spawn Functions ---

func _spawn_sentry_turret():
	_spawn_turret(sentry_turret_scene, 100.0)
	_update_timer(sentry_timer, "sentry_deployment_cooldown", true) # Restart timer

func _spawn_artillery_bot():
	_spawn_turret(artillery_bot_scene, 100.0)
	_update_timer(artillery_timer, "artillery_deployment_cooldown", true)

func _spawn_hunter_killer_bot():
	_spawn_turret(hunter_killer_bot_scene, 100.0)
	_update_timer(hunter_killer_timer, "hunter_killer_deployment_cooldown", true)

func _spawn_aegis_protector():
	# Aegis Protector spawns closer to the player
	_spawn_turret(aegis_protector_scene, 30.0)
	_update_timer(aegis_timer, "aegis_deployment_cooldown", true)

func _spawn_random_turret_from_assembly():
	var available_turrets = []
	if is_instance_valid(sentry_turret_scene): available_turrets.append({"scene": sentry_turret_scene, "range": 100.0})
	if _specific_stats.get("has_artillery_bot", false): available_turrets.append({"scene": artillery_bot_scene, "range": 100.0})
	if _specific_stats.get("has_hk_bot", false): available_turrets.append({"scene": hunter_killer_bot_scene, "range": 100.0})
	if _specific_stats.get("has_aegis_protector", false): available_turrets.append({"scene": aegis_protector_scene, "range": 30.0})
	
	if not available_turrets.is_empty():
		var chosen_turret = available_turrets.pick_random()
		_spawn_turret(chosen_turret.scene, chosen_turret.range)
		
	_update_timer(assembly_line_timer, "assembly_line_cooldown", true)

# Generic turret spawning logic
func _spawn_turret(scene: PackedScene, spawn_radius: float):
	if not is_instance_valid(scene) or not is_instance_valid(_owner_player):
		return

	var turret_instance = scene.instantiate()
	# Add to a general container in the main scene to keep things tidy
	var summons_container = get_tree().current_scene.get_node_or_null("SummonsContainer")
	if is_instance_valid(summons_container):
		summons_container.add_child(turret_instance)
	else:
		get_tree().current_scene.add_child(turret_instance)

	# Calculate random spawn position
	var random_angle = randf_range(0, TAU)
	var random_distance = randf_range(spawn_radius * 0.5, spawn_radius)
	var spawn_position = _owner_player.global_position + Vector2.RIGHT.rotated(random_angle) * random_distance
	turret_instance.global_position = spawn_position
	
	if turret_instance.has_method("initialize"):
		turret_instance.initialize(_specific_stats, _owner_player_stats)
