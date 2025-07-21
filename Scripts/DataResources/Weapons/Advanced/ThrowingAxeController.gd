# Path: res://Scripts/Weapons/Advanced/ThrowingAxeController.gd
# ===================================================================
class_name ThrowingAxeController
extends Node2D

@export var axe_projectile_scene: PackedScene
@export var splinter_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	if not is_instance_valid(axe_projectile_scene):
		push_error("ThrowingAxeController: Axe Projectile Scene is not assigned!"); queue_free(); return
	
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = _p_weapon_manager

	var has_tornado_axe = _specific_stats.get(&"has_tornado_axe", false)
	
	if has_tornado_axe:
		_execute_tornado_axe(direction)
	else:
		_execute_normal_throw(direction)
	
	queue_free()

func _execute_normal_throw(direction: Vector2):
	var final_direction = direction
	if _specific_stats.get(&"has_frenzied_hurl", false):
		var random_angle_offset = deg_to_rad(randf_range(-5.0, 5.0))
		final_direction = direction.rotated(random_angle_offset)
	
	_spawn_axe_instance(final_direction)

func _execute_tornado_axe(base_direction: Vector2):
	for i in range(3):
		var random_angle_offset = deg_to_rad(randf_range(-20.0, 20.0))
		var final_direction = base_direction.rotated(random_angle_offset)
		_spawn_axe_instance(final_direction)

func _spawn_axe_instance(direction: Vector2):
	var owner_player = _owner_player_stats.get_parent()
	var projectile_instance = axe_projectile_scene.instantiate() as ThrowingAxeProjectile
	
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(projectile_instance)
	else:
		get_tree().current_scene.add_child(projectile_instance)
	
	projectile_instance.global_position = owner_player.global_position
	
	if projectile_instance.has_method("initialize"):
		projectile_instance.initialize(direction, _specific_stats, _owner_player_stats, splinter_scene)
