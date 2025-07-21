# File: PhantomReachHomingComponent.gd
# Attach to: PhantomReachProjectile.tscn -> HomingComponent node
# --------------------------------------------------------------------
class_name PhantomReachHomingComponent
extends Node

var target: Node2D = null
var is_active: bool = false
var turn_rate: float = 12.0
var parent_projectile: Area2D

func _physics_process(delta: float):
	if not is_instance_valid(target) or (target is BaseEnemy and (target as BaseEnemy).is_dead()):
		target = _find_nearest_enemy()
		if not is_instance_valid(target):
			is_active = false
			return

	if not is_active or not is_instance_valid(parent_projectile):
		is_active = false
		return

	var projectile_speed = 0.0
	if "_speed" in parent_projectile:
		projectile_speed = parent_projectile._speed
		
	var direction_to_target = (target.global_position - parent_projectile.global_position).normalized()
	var current_direction = Vector2.RIGHT.rotated(parent_projectile.rotation)
		
	var new_direction = current_direction.slerp(direction_to_target, turn_rate * delta)
	
	parent_projectile.global_position += new_direction * projectile_speed * delta
	parent_projectile.rotation = new_direction.angle()
	
func activate(p_target: Node2D):
	if is_instance_valid(p_target):
		target = p_target
		is_active = true
		set_physics_process(true)

func _find_nearest_enemy() -> Node2D:
	if not is_instance_valid(parent_projectile): return null

	var enemies_in_scene = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy: Node2D = null
	var min_dist_sq = INF
	for enemy_node in enemies_in_scene:
		if is_instance_valid(enemy_node) and not (enemy_node as BaseEnemy).is_dead():
			var dist_sq = parent_projectile.global_position.distance_squared_to(enemy_node.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				nearest_enemy = enemy_node
	return nearest_enemy

func _ready():
	parent_projectile = get_parent()
	set_physics_process(false)
