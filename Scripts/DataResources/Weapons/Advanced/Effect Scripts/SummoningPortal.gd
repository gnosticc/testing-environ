# File: SummoningPortal.gd
# Attach to: SummoningPortal.tscn
# REVISED: Now uses a Timer for robust self-deletion.
# --------------------------------------------------------------------
class_name SummoningPortal
extends AnimatedSprite2D

@onready var lifetime_timer: Timer = $LifetimeTimer

func _ready():
	self.play("default")
	lifetime_timer.start()
	lifetime_timer.timeout.connect(queue_free)
