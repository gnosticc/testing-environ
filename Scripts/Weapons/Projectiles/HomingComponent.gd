# HomingComponent.gd
# REVISED: Now finds a new target if the current one becomes invalid.

class_name HomingComponent
extends Node

var target: Node2D = null
var is_active: bool = false
var turn_rate: float = 4.0

func _physics_process(delta: float):
	# --- CORE FIX ---
	# Check if the target is still valid. If not, try to find a new one.
	if not is_instance_valid(target) or (target is BaseEnemy and (target as BaseEnemy).is_dead()):
		target = _find_nearest_enemy() # Find a new target
		if not is_instance_valid(target):
			is_active = false # Deactivate if no new targets are found
			return

	if not is_active or not is_instance_valid(get_parent()):
		is_active = false
		return

	var parent_projectile = get_parent()
	if not is_instance_valid(parent_projectile):
		is_active = false
		return
		
	var direction_to_target = (target.global_position - parent_projectile.global_position).normalized()
	var current_direction = parent_projectile.velocity.normalized()
	var new_direction = current_direction.slerp(direction_to_target, turn_rate * delta)
	
	var projectile_speed = 0.0
	if "final_speed" in parent_projectile:
		projectile_speed = parent_projectile.final_speed
	
	parent_projectile.velocity = new_direction * projectile_speed
	parent_projectile.rotation = new_direction.angle()
	
func activate(p_target: Node2D):
	if is_instance_valid(p_target):
		target = p_target
		is_active = true
		set_physics_process(true)

# New helper function to find the nearest valid enemy.
func _find_nearest_enemy() -> Node2D:
	var parent_node = get_parent()
	if not is_instance_valid(parent_node): return null

	var enemies_in_scene = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy: Node2D = null
	var min_dist_sq = INF
	for enemy_node in enemies_in_scene:
		if is_instance_valid(enemy_node) and not (enemy_node as BaseEnemy).is_dead():
			var dist_sq = parent_node.global_position.distance_squared_to(enemy_node.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				nearest_enemy = enemy_node
	return nearest_enemy

func _ready():
	set_physics_process(false)
