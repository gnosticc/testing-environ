# --- Path: res://Scripts/Weapons/Advanced/Effects/ThornBurst.gd ---
class_name ThornBurst
extends Node2D

const THORN_PROJECTILE_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/ThornProjectile.tscn")

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	var num_thorns = 8
	var angle_step = TAU / float(num_thorns)
	
	for i in range(num_thorns):
		var thorn = THORN_PROJECTILE_SCENE.instantiate()
		add_child(thorn)
		thorn.global_position = global_position
		var direction = Vector2.RIGHT.rotated(i * angle_step)
		thorn.initialize(direction, p_stats, p_player_stats)
	
	get_tree().create_timer(0.1).timeout.connect(queue_free)
