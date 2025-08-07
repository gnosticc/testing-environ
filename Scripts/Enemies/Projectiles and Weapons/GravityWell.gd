# GravityWell.gd
# This script controls a vortex that applies a continuous force to the player.
#
# FIX: Moved all configuration logic from _ready() into initialize(). This resolves a
#      race condition where _ready() was being called with default class variables
#      before initialize() could provide the correct values from the EnemyData.tres file.
# FIX: Visual scaling for the animated sprite is now set to half the radius, making
#      the visual effect smaller than its collision area as requested.

class_name GravityWell
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var pull_strength: float = 20.0
var pull_duration: float = 1.0
var radius: float = 50.0

var _player_ref: PlayerCharacter = null

# Called by OnDeathBehaviorHandler to set up the effect.
func initialize(p_radius: float, p_strength: float, p_duration: float):
	# Store the values from the EnemyData.tres file
	radius = p_radius
	pull_strength = p_strength
	pull_duration = p_duration

	# --- All configuration logic is now here, ensuring it uses the correct values ---

	# Configure the Area2D's shape with the correct radius.
	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
	else:
		push_warning("GravityWell is missing or has an incorrect CollisionShape2D.")
		queue_free()
		return
	
	# Play the vortex animation and set up the scaling tween.
	if is_instance_valid(animated_sprite):
		animated_sprite.play("active")
		
		var target_scale = Vector2.ONE
		var frame_texture = animated_sprite.sprite_frames.get_frame_texture(&"active", 0)
		if is_instance_valid(frame_texture):
			var sprite_base_width = frame_texture.get_width()
			if sprite_base_width > 0:
				# FIX: The desired visual diameter is now set to the radius (half the full diameter)
				# to make the visual effect smaller than its collision area.
				var desired_diameter = radius
				var scale_factor = desired_diameter / sprite_base_width
				target_scale = Vector2.ONE * scale_factor
		
		var tween = create_tween()
		var grow_time = 0.3
		var shrink_time = 0.3
		var sustain_time = pull_duration - grow_time - shrink_time

		animated_sprite.scale = Vector2.ZERO
		
		tween.tween_property(animated_sprite, "scale", target_scale, grow_time).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		
		if sustain_time > 0:
			tween.tween_interval(sustain_time)
			
		tween.tween_property(animated_sprite, "scale", Vector2.ZERO, shrink_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Start a timer to destroy this effect after its duration expires.
	get_tree().create_timer(pull_duration).timeout.connect(queue_free)

# The _ready() function now only connects signals, which is safe to do at any time.
func _ready():
	# Connect signals to track when the player enters or leaves the effect.
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
func _physics_process(delta: float):
	# If the player is inside the area, apply the pull force.
	if is_instance_valid(_player_ref):
		var direction_to_center = (self.global_position - _player_ref.global_position).normalized()
		var force_vector = direction_to_center * pull_strength
		
		# Assumes the player has a function to receive external forces.
		if _player_ref.has_method("apply_external_force"):
			_player_ref.apply_external_force(force_vector)

func _on_body_entered(body: Node2D):
	if body.is_in_group("player_char_group"):
		_player_ref = body as PlayerCharacter

func _on_body_exited(body: Node2D):
	if body == _player_ref:
		_player_ref = null
