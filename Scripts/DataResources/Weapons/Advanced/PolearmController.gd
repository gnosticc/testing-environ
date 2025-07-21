# --- Path: res://Scripts/Weapons/Advanced/PolearmController.gd ---
# UPDATED: Added logic to handle the "Flowing Strikes" upgrade.
# The controller now checks for the 'has_flowing_strikes' flag and has a chance
# to spawn a second sweep attack.

class_name PolearmController
extends Node2D

@export var attack_scene: PackedScene
@export var base_slam_scene: PackedScene

@onready var phalanx_stance_timer: Timer = $PhalanxStanceTimer
@onready var phalanx_mastery_timer: Timer = $PhalanxMasteryTimer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager
var _owner_player: PlayerCharacter
var _is_in_phalanx_stance: bool = false

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	_owner_player = p_player_stats.get_parent()
	
	phalanx_stance_timer.wait_time = float(_specific_stats.get(&"phalanx_stance_time", 0.25))
	phalanx_stance_timer.timeout.connect(_on_phalanx_stance_timer_timeout)
	phalanx_mastery_timer.timeout.connect(_on_phalanx_mastery_timer_timeout)

func update_stats(new_stats: Dictionary):
	_specific_stats = new_stats

func _physics_process(_delta):
	if not is_instance_valid(_owner_player):
		queue_free()
		return
		
	if _owner_player.velocity.length_squared() > 1.0:
		if _is_in_phalanx_stance:
			_exit_phalanx_stance()
		if not phalanx_stance_timer.is_stopped():
			phalanx_stance_timer.stop()
	else:
		if phalanx_stance_timer.is_stopped():
			phalanx_stance_timer.start()

func attack():
	var attack_type = "sweep"
	if _is_in_phalanx_stance:
		attack_type = "thrust"
	
	_spawn_attack_instance(attack_type)
	
	# --- NEW: Flowing Strikes Logic ---
	# Only check for a proc if the attack was a sweep.
	if attack_type == "sweep" and _specific_stats.get(&"has_flowing_strikes", false):
		var chance = float(_specific_stats.get(&"flowing_strikes_chance", 0.4))
		if randf() < chance:
			# Use a timer to spawn the second sweep after a short delay for visual clarity.
			get_tree().create_timer(0.25).timeout.connect(_spawn_attack_instance.bind("sweep"))

	# Restart the main weapon cooldown after the initial attack is launched.
	var weapon_entry_index = _weapon_manager._get_weapon_entry_index_by_id(_specific_stats.get("id"))
	if weapon_entry_index != -1:
		var weapon_entry = _weapon_manager.active_weapons[weapon_entry_index]
		var timer = weapon_entry.get("cooldown_timer") as Timer
		if not is_instance_valid(timer): return

		var cooldown_time = _weapon_manager.get_weapon_cooldown_value(weapon_entry)

		if attack_type == "thrust":
			var thrust_mod = float(_specific_stats.get(&"thrust_cooldown_modifier", 1.0))
			cooldown_time *= thrust_mod
		
		timer.wait_time = maxf(0.05, cooldown_time)
		timer.start()

# Helper function to spawn a single attack instance.
func _spawn_attack_instance(attack_type: String):
	if not is_instance_valid(self): return # Safety check if controller is freed mid-timer
	
	var attack_instance = attack_scene.instantiate()
	_owner_player.add_child(attack_instance)
	attack_instance.global_position = _owner_player.global_position
	
	if attack_instance.has_method("initialize"):
		attack_instance.initialize(attack_type, _specific_stats, _owner_player_stats, _weapon_manager)


func _on_phalanx_stance_timer_timeout():
	if not _is_in_phalanx_stance:
		_enter_phalanx_stance()

func _enter_phalanx_stance():
	_is_in_phalanx_stance = true
	if _specific_stats.get(&"has_aegis_stance", false):
		var knight_levels = _owner_player.get_total_levels_for_class(PlayerCharacter.BasicClass.KNIGHT)
		var armor_bonus = knight_levels * 5
		var aegis_buff = load("res://DataResources/StatusEffects/aegis_of_the_sentinel_buff.tres") as StatusEffectData
		if is_instance_valid(aegis_buff):
			_owner_player.status_effect_component.apply_effect(aegis_buff, _owner_player, {}, -1.0, float(armor_bonus), &"aegis_stance_buff")
	
	if _specific_stats.get(&"has_phalanx_mastery", false):
		phalanx_mastery_timer.start()

func _exit_phalanx_stance():
	_is_in_phalanx_stance = false
	if _specific_stats.get(&"has_aegis_stance", false):
		_owner_player.status_effect_component.remove_effect_by_unique_id(&"aegis_stance_buff")
	
	if not phalanx_mastery_timer.is_stopped():
		phalanx_mastery_timer.stop()

func _on_phalanx_mastery_timer_timeout():
	if not _is_in_phalanx_stance: return
	
	var slam_radius = 250.0
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead() and _owner_player.global_position.distance_to(enemy.global_position) <= slam_radius:
			var slam_instance = base_slam_scene.instantiate()
			enemy.add_child(slam_instance)
			slam_instance.global_position = enemy.global_position
			if slam_instance.has_method("initialize"):
				slam_instance.initialize(_specific_stats, _owner_player_stats)
			
	phalanx_mastery_timer.start()
