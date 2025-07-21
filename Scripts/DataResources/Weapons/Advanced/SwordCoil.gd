# File: res://Scripts/Weapons/SwordCoil.gd
# This script is attached to the root of SwordCoil.tscn.
# It controls the sword's animation and spawns the projectile.
# FIX: This script is now purely for visual effect and no longer spawns projectiles.

class_name SwordCoil
extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var tip_node: Node2D = $Tip # Still needed for the controller to find the tip

func _ready():
	if not is_instance_valid(animation_player):
		push_error("SwordCoil ERROR: Missing AnimationPlayer node.")
		queue_free()

func set_attack_properties(direction: Vector2, _p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	# Point the entire weapon towards the target direction
	self.rotation = direction.angle()
	
	# Scale the animation speed based on player stats
	var player_attack_speed_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	if player_attack_speed_mult <= 0: player_attack_speed_mult = 0.01
	animation_player.speed_scale = player_attack_speed_mult
	
	animation_player.play("fire")
	
	# Set a timer to clean up this node after its scaled animation duration
	var anim = animation_player.get_animation("fire")
	if is_instance_valid(anim):
		var final_lifetime = anim.length / player_attack_speed_mult
		get_tree().create_timer(final_lifetime, true, false, true).timeout.connect(queue_free)
	else:
		# Failsafe cleanup
		get_tree().create_timer(1.0, true, false, true).timeout.connect(queue_free)
