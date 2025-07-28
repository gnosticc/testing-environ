# EnemyBehaviorHandler.gd
# Path: res://Scripts/Singletons/EnemyBehaviorHandler.gd
# PURPOSE: An Autoload singleton that contains all logic for special enemy behaviors
# defined by the 'behavior_tags' in EnemyData.tres files. This keeps BaseEnemy.gd clean.
# VERSION 2.2: Refined slime splitting logic to only remove the recursive "slime" tag from children.

extends Node

# Called by BaseEnemy when it dies. It checks the enemy's tags and triggers appropriate on-death logic.
func process_on_death_tags(enemy: BaseEnemy):
	# --- Slime Splitting Behavior ---
	if enemy.behavior_tags.has(&"slime"):
		_handle_slime_split(enemy)
	
	# --- Future On-Death Behaviors ---
	# Example:
	# if enemy.behavior_tags.has(&"explodes_on_death"):
	#     _handle_explosion(enemy)
	#
	# if enemy.behavior_tags.has(&"leaves_puddle"):
	#     _handle_puddle_spawn(enemy)


# --- Private Handler Functions for Specific Tags ---

# Contains the logic for the "slime" tag.
func _handle_slime_split(enemy: BaseEnemy):
	# Failsafe checks to ensure we have all necessary references.
	if not is_instance_valid(enemy.game_node_ref) or not is_instance_valid(enemy.enemy_data_resource):
		push_warning("Slime Split failed: Game node or enemy data resource is invalid for enemy: " + enemy.name)
		return

	var scene_to_spawn = load(enemy.enemy_data_resource.scene_path) as PackedScene
	if not is_instance_valid(scene_to_spawn):
		push_error("Slime Split failed: Could not load scene from path: " + enemy.enemy_data_resource.scene_path)
		return

	# Spawn two smaller versions of the slime.
	for i in range(2):
		var smaller_slime = scene_to_spawn.instantiate() as BaseEnemy
		if not is_instance_valid(smaller_slime): continue
		
		var enemies_container = enemy.game_node_ref.get_node_or_null("EnemiesContainer")
		if is_instance_valid(enemies_container):
			enemies_container.add_child(smaller_slime)
		else:
			push_error("Slime Split failed: Could not find 'EnemiesContainer' in Game scene.")
			smaller_slime.queue_free()
			continue

		# Position the smaller slimes slightly apart from the original's death location.
		var offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
		smaller_slime.global_position = enemy.global_position + offset
		
		# Initialize it with the same base data.
		smaller_slime.initialize_from_data(enemy.enemy_data_resource)
		
		# --- FIX: Modify stats AFTER initialization ---
		
		# 1. Set stats for the smaller version.
		smaller_slime.max_health = enemy.enemy_data_resource.base_health * 0.50
		smaller_slime.current_health = smaller_slime.max_health
		smaller_slime.experience_to_drop = 0 # Smaller slimes drop no EXP.
		
		# 2. FIX: Set scale based on the new slime's OWN base scale, not the parent's.
		# This prevents inheriting incorrect scales from elite parents.
		smaller_slime.scale = smaller_slime.base_scene_root_scale * 0.75
		
		# 3. FIX: Only remove the "slime" tag to prevent infinite splitting, keeping other tags.
		smaller_slime.behavior_tags.erase(&"slime")
		
		# Ensure the health bar reflects the new, lower health.
		smaller_slime.update_health_bar()

# --- Placeholder for future on-death behaviors ---
# func _handle_explosion(enemy: BaseEnemy):
#     # Logic to create an explosion at the enemy's position
#     pass
#
# func _handle_puddle_spawn(enemy: BaseEnemy):
#     # Logic to create a slowing/damaging puddle at the enemy's position
#     pass
