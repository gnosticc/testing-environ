# --- Path: res://Scripts/Weapons/Advanced/ShurikenController.gd ---
class_name ShurikenController
extends Node2D

@export var shuriken_projectile_scene: PackedScene # This should be renamed to shuriken_projectile_scene in your editor

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	if not is_instance_valid(shuriken_projectile_scene):
		push_error("ShurikenController: Projectile Scene is not assigned!"); queue_free(); return
	
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats

	var has_twin_throw = _specific_stats.get(&"has_twin_throw", false)
	
	if has_twin_throw:
		_spawn_shuriken_instance(direction.rotated(deg_to_rad(5)))
		_spawn_shuriken_instance(direction.rotated(deg_to_rad(-5)))
	else:
		_spawn_shuriken_instance(direction)
	
	queue_free()

func _spawn_shuriken_instance(direction: Vector2):
	var owner_player = _owner_player_stats.get_parent()
	var projectile_instance = shuriken_projectile_scene.instantiate() as ShurikenProjectile
	
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(projectile_instance)
	else:
		get_tree().current_scene.add_child(projectile_instance)
	
	projectile_instance.global_position = owner_player.global_position
	
	if projectile_instance.has_method("initialize"):
		projectile_instance.initialize(direction, _specific_stats, _owner_player_stats)
