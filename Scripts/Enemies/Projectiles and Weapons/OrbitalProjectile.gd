# OrbitalProjectile.gd
# A simple projectile that is positioned by its parent (the OrbitalBehavior component).
# It deals damage on overlap with the player and then destroys itself.

class_name OrbitalProjectile
extends Area2D

var damage: float = 5.0

func _ready():
	# Connect the body_entered signal to the damage function.
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	# Check if the body that entered is the player.
	if body.is_in_group("player_char_group"):
		if body.has_method("take_damage"):
			body.take_damage(damage, self, {})
		
		# The orb is consumed on impact.
		queue_free()
