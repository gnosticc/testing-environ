# File: res://Scripts/Weapons/Controllers/SparkAttackController.gd
# Purpose: Orchestrates firing for the Spark weapon. Handles "Twin Flames".
class_name SparkAttackController
extends Node2D

# Assign SparkProjectile.tscn to this in the Inspector.
@export var projectile_scene: PackedScene

# --- Internal State ---
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _direction: Vector2

func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	if not is_instance_valid(projectile_scene):
		push_error("SparkAttackController ERROR: Projectile Scene not assigned!"); queue_free(); return

	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_direction = p_direction

	# --- Twin Flames Logic ---
	var has_twin_flames = _specific_stats.get(&"has_twin_flames", false)
	
	_fire_projectile() # Fire the first projectile immediately.
	
	if has_twin_flames:
		# If the upgrade is active, create a timer to fire the second projectile.
		var twin_flame_timer = get_tree().create_timer(0.2, true, false, true)
		twin_flame_timer.timeout.connect(_fire_projectile)

	# This controller has served its purpose. It sets timers and then removes itself.
	# We need to make sure it exists long enough for the timer to fire.
	get_tree().create_timer(0.3).timeout.connect(queue_free)

func _fire_projectile():
	if not is_instance_valid(self) or not is_instance_valid(projectile_scene): return

	var projectile_instance = projectile_scene.instantiate()
	var owner_player = _owner_player_stats.get_parent()

	# Add to a container to keep the main scene clean.
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(projectile_instance)
	else:
		get_tree().current_scene.add_child(projectile_instance)
	
	projectile_instance.global_position = owner_player.global_position
	
	if projectile_instance.has_method("set_attack_properties"):
		projectile_instance.set_attack_properties(_direction, _specific_stats, _owner_player_stats)
