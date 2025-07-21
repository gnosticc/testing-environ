# --- Path: res://Scripts/Weapons/Advanced/Summons/CaltropController.gd ---
class_name CaltropController
extends Node2D

@export var caltrop_scene: PackedScene

func initialize(clone_slash_damage: float, p_owner_player: PlayerCharacter):
	if not is_instance_valid(caltrop_scene): queue_free(); return
	
	var caltrop_damage = int(round(clone_slash_damage * 0.40))
	var num_caltrops = 4
	
	for i in range(num_caltrops):
		# FIX: Add the caltrop to the main scene tree, not this controller.
		var caltrop = caltrop_scene.instantiate()
		get_tree().current_scene.add_child(caltrop)
		caltrop.global_position = self.global_position # Start at the controller's position
		caltrop.rotation = randf_range(0, TAU)
		if caltrop.has_method("initialize"):
			caltrop.initialize(caltrop_damage, p_owner_player)
			
	queue_free()
