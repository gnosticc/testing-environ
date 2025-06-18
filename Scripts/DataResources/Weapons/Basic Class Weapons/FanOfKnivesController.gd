# ======================================================================
# 1. NEW SCENE SCRIPT: FanOfKnivesController.gd
# This script is attached to a simple Node2D scene. Its only job is to
# fire a volley of projectiles in a circle.
# Path: res://Scripts/Weapons/Projectiles/FanOfKnivesController.gd
# ======================================================================

class_name FanOfKnivesController
extends Node2D

## Assign your new spectral knife projectile scene in the Inspector.
@export var knife_projectile_scene: PackedScene

# This function is called by DaggerStrikeController.gd on the final hit.
# It receives the damage calculated from that final, powerful dagger slash.
func initialize(damage_per_knife: int, p_player_stats: PlayerStats):
	if not is_instance_valid(knife_projectile_scene):
		push_error("FanOfKnivesController: knife_projectile_scene is not set!")
		queue_free()
		return

	var number_of_knives = 5
	var angle_step = TAU / float(number_of_knives) # TAU is a full circle

	for i in range(number_of_knives):
		var knife_instance = knife_projectile_scene.instantiate()
		var direction = Vector2.RIGHT.rotated(i * angle_step)
		
		# Add to a container to keep the scene tree clean
		var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
		if is_instance_valid(attacks_container):
			attacks_container.add_child(knife_instance)
		else:
			get_tree().current_scene.add_child(knife_instance)

		# Position the knife at the player's location and initialize it
		knife_instance.global_position = self.global_position
		if knife_instance.has_method("setup"):
			# Pass damage, direction, and player stats to the projectile.
			# The projectile will handle its own speed and lifetime.
			knife_instance.setup(damage_per_knife, direction, p_player_stats)
	
	# The controller's job is done after spawning the volley.
	queue_free()
