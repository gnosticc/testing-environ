# --- Path: res://Scripts/Weapons/Advanced/BrambleCenserController.gd ---
class_name BrambleCenserController
extends Node2D

@export var attack_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager
var _owner_player: PlayerCharacter

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	_owner_player = p_player_stats.get_parent()

func update_stats(new_stats: Dictionary):
	_specific_stats = new_stats

func attack():
	if not is_instance_valid(attack_scene): 
		push_error("BrambleCenserController: Attack Scene is not assigned in the Inspector!")
		return

	var attack_instance = attack_scene.instantiate()
	_owner_player.add_child(attack_instance)
	attack_instance.global_position = _owner_player.global_position
	
	if attack_instance.has_method("initialize"):
		attack_instance.initialize(_specific_stats, _owner_player_stats, _weapon_manager)
	
	# Restart cooldown
	var weapon_entry_index = _weapon_manager._get_weapon_entry_index_by_id(_specific_stats.get("id"))
	if weapon_entry_index != -1:
		_weapon_manager._restart_weapon_cooldown(_weapon_manager.active_weapons[weapon_entry_index])
