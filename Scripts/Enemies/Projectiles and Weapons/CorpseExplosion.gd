# CorpseExplosion.gd
# This script controls the behavior of the on-death explosion effect.
# It should be attached to an Area2D node which is the root of the scene.
# The scene should also contain an AnimatedSprite2D and a CollisionShape2D.

class_name CorpseExplosion
extends Area2D

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- Stats ---
var damage: float = 25.0
# The default radius is now only a fallback.
var radius: float = 100.0

# --- State ---
var has_hit_player: bool = false # Ensures the explosion only damages the player once.

# This function is called by the OnDeathBehaviorHandler to configure the explosion.
func initialize(p_damage: float, p_radius: float):
	damage = p_damage
	radius = p_radius
	
	# We can't wait for _ready(), as it can fire before this function is called.
	# We get the node references directly. This is safe because initialize() is
	# called AFTER the node has been added to the scene tree, so its children exist.
	var cs = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(cs) and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = radius
	else:
		push_warning("CorpseExplosion: Could not find or set radius on CollisionShape2D during initialization.")
		
	# --- SOLUTION: Scale the AnimatedSprite2D to match the new radius ---
	var sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(sprite) and is_instance_valid(sprite.sprite_frames):
		# Assumes the animation is named "explode" and has at least one frame.
		var frame_texture = sprite.sprite_frames.get_frame_texture(&"explode", 0)
		if is_instance_valid(frame_texture):
			var sprite_base_width = frame_texture.get_width()
			if sprite_base_width > 0:
				# The desired visual width of the sprite should be twice the radius (the diameter).
				var desired_width = radius * 2.0
				var scale_factor = desired_width / sprite_base_width
				sprite.scale = Vector2.ONE * scale_factor
	# --- END SOLUTION ---

func _ready():
	# --- Initialization and Safety Checks ---
	if not is_instance_valid(animated_sprite) or not is_instance_valid(collision_shape):
		push_error("CorpseExplosion is missing AnimatedSprite2D or CollisionShape2D child.")
		queue_free()
		return
		
	# The radius and sprite scale are now set in initialize(), so we no longer need to set them here.

	# --- Connect Signals for Lifecycle Management ---
	animated_sprite.animation_finished.connect(_on_animation_finished)
	self.body_entered.connect(_on_body_entered)

	# --- Start the Effect ---
	animated_sprite.play("explode") # Assumes your animation is named "explode"
	
	call_deferred("set_monitoring", true)


func _on_body_entered(body: Node2D):
	if not has_hit_player and body.is_in_group("player_char_group"):
		has_hit_player = true
		
		if body.has_method("take_damage"):
			body.take_damage(damage, self, {})


func _on_animation_finished():
	queue_free()
