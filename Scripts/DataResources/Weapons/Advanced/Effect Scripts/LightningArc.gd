# --- REWRITTEN SCRIPT: res://Scripts/Weapons/Advanced/Effects/LightningArc.gd ---
class_name LightningArc
extends Sprite2D

@onready var lifetime_timer: Timer = $LifetimeTimer

func _ready():
	lifetime_timer.timeout.connect(queue_free)

func initialize(start_pos: Vector2, end_pos: Vector2):
	var vector = end_pos - start_pos
	var distance = vector.length()
	var sprite_width = texture.get_width() if texture else 1.0

	global_position = start_pos.lerp(end_pos, 0.5)
	rotation = vector.angle()
	scale.x = distance / sprite_width
	
	lifetime_timer.start()
