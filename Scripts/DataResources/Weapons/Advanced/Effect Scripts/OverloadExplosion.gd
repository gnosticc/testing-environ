# Path: res://Scripts/Weapons/Advanced/Effects/OverloadExplosion.gd
class_name OverloadExplosion
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer
var _specific_stats: Dictionary
func _ready():
	# FIX: Connect the timer's timeout signal to queue_free to ensure deletion.
	lifetime_timer.timeout.connect(queue_free)

func initialize(p_damage: int, p_radius: float, p_source_player: PlayerCharacter):
	# Configure the explosion's properties
	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = p_radius
	
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("explode", 0)
	if is_instance_valid(sprite_texture):
		var texture_size = sprite_texture.get_width()
		var desired_diameter = p_radius * 2
		animated_sprite.scale = Vector2.ONE * (desired_diameter / texture_size)

	animated_sprite.play("explode")
	
	# Use a short timer to delay the damage check, allowing the physics engine to update.
	get_tree().create_timer(0.02, false).timeout.connect(_deal_damage.bind(p_damage, p_source_player))
	
	# Start the main lifetime timer to clean up the node after its animation.
	lifetime_timer.start()

func _deal_damage(p_damage: int, p_source_player: PlayerCharacter):
	# By the time this function is called, the physics server has had time to register the Area2D.
	if not is_instance_valid(self):
		return

	var targets_hit = 0
	# Enable monitoring right before the check, and disable it right after.
	monitoring = true
	await get_tree().physics_frame # Wait one more frame just to be safe
	for body in get_overlapping_bodies():
		if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
			var weapon_tags: Array[StringName] = []
			if _specific_stats.has("tags"):
				weapon_tags = _specific_stats.get("tags")
			body.take_damage(p_damage, p_source_player, {}, weapon_tags)
			targets_hit += 1
	monitoring = false
	
	print("OVERLOAD PROC: Dealt ", p_damage, " damage to ", targets_hit, " enemies.")
