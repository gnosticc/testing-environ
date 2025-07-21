# File: res://Scripts/Weapons/Advanced/ChromaticAberrationController.gd
# Attach to: ChromaticAberrationController.tscn (Root Node2D)
# Purpose: This is the main controller spawned by WeaponManager. It finds a target
# and launches the UnstableOrb projectile.
# UPDATED: Now spawns projectiles from its own position, not the player's.

class_name ChromaticAberrationController
extends Node2D

@export var projectile_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	if not is_instance_valid(projectile_scene):
		push_error("ChromaticAberrationController: Projectile Scene is not assigned! Aborting attack.")
		queue_free()
		return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	var owner_player = _owner_player_stats.get_parent()

	var main_target = _find_random_enemy()
	if not is_instance_valid(main_target):
		queue_free() # No valid targets, do nothing.
		return

	# Spawn the primary projectile
	_spawn_projectile(main_target)

	# The controller's job is done after spawning the projectile.
	queue_free()

func _find_random_enemy() -> BaseEnemy:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var valid_enemies: Array[BaseEnemy] = []
	for enemy in enemies:
		if enemy is BaseEnemy and is_instance_valid(enemy) and not enemy.is_dead():
			valid_enemies.append(enemy)
	
	if valid_enemies.is_empty():
		return null
	else:
		return valid_enemies.pick_random()

func _spawn_projectile(target_enemy: BaseEnemy):
	var projectile = projectile_scene.instantiate()
	
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(projectile)
	else:
		get_tree().current_scene.add_child(projectile)

	# FIX: Spawn the projectile from this controller's position, not the player's.
	projectile.global_position = self.global_position
	
	if projectile.has_method("initialize"):
		projectile.initialize(target_enemy, _specific_stats, _owner_player_stats, _weapon_manager)
