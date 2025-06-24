# File: res://Scripts/Weapons/Projectiles/SparkExplosion.gd
# Purpose: Attached to SparkExplosion.tscn.
# FIX: Re-introduced 'await get_tree().physics_frame' safely within a deferred
# context to ensure overlaps are detected before querying.
# NEW FIX: Ensure the explosion node remains in the scene long enough to deal damage
# by deferring its queue_free to after its main logic.

class_name SparkExplosion
extends Area2D

# You can adjust this to make the hitbox larger than the visual. 1.0 = same size.
const HITBOX_SCALE_MULTIPLIER = 1.25
# NEW: Define a delay for the echo explosion.
const ECHO_DETONATION_DELAY = 0.3 # Adjust this value as needed (e.g., 0.1 seconds)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(collision_shape):
		push_error("SparkExplosion ERROR: Scene is missing AnimatedSprite2D or CollisionShape2D.")
		queue_free()
		return
	# REMOVED: animated_sprite.animation_finished.connect(queue_free)
	# This connection is moved to the detonate function to ensure proper timing.

# This function is called by SparkProjectile.gd to trigger the explosion.
func detonate(damage: int, radius: float, source_node: Node, attack_stats: Dictionary, can_echo: bool):
	# DEBUG: Print the damage value received by this explosion instance and its position
	#print("SparkExplosion: Detonating at pos ", global_position, " with damage: ", damage, " (Echoable: ", can_echo, ")")

	# Set the collision shape's radius to match the explosion's area of effect.
	if collision_shape.shape is CircleShape2D:
		# Apply the multiplier here to make the hitbox bigger
		(collision_shape.shape as CircleShape2D).radius = radius * HITBOX_SCALE_MULTIPLIER
	
	# Scale the animation to visually match the damage radius.
	var sprite_base_size = animated_sprite.sprite_frames.get_frame_texture(&"default", 0).get_width()
	if sprite_base_size > 0:
		var scale_factor = (radius * 2.0) / sprite_base_size
		animated_sprite.scale = Vector2(scale_factor, scale_factor)

	# Play the "default" animation.
	if animated_sprite.sprite_frames.has_animation(&"default"):
		animated_sprite.play("default")
	else:
		push_warning("SparkExplosion WARNING: 'default' animation not found. The effect will be invisible.")
		# If no animation, ensure it's still freed after a short delay.
		get_tree().create_timer(0.1, true, false, true).timeout.connect(queue_free)

	# FIX: Await a physics frame. Since this `detonate` function is called
	# via `call_deferred` from `SparkProjectile`, it is safe to `await` here.
	# This ensures the physics server has processed the new Area2D's presence
	# and updated its list of overlapping bodies before we query them.
	await get_tree().physics_frame
	
	# NEW: Additional small delay for echo explosions to ensure physics updates.
	# This specifically targets the case where the echo's Area2D might not
	# immediately register overlaps even after the first physics frame.
	# This check `if not can_echo:` ensures this delay is only for the echo.
	if not can_echo:
		#print("SparkExplosion: Echo detected. Adding a small pre-detonation delay...")
		await get_tree().create_timer(0.02).timeout # A very short, explicit delay
		#print("SparkExplosion: Echo pre-detonation delay finished.")


	var bodies_to_damage = get_overlapping_bodies()
	#print("SparkExplosion at ", global_position, ": Detected ", bodies_to_damage.size(), " overlapping bodies.")
	for body in bodies_to_damage:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			var enemy_target = body as BaseEnemy
			if is_instance_valid(enemy_target) and not enemy_target.is_dead():
				enemy_target.take_damage(damage, source_node, attack_stats)
				#print("  -> Hit enemy: ", enemy_target.name, " (ID: ", enemy_target.get_instance_id(), ") for ", damage, " damage.")
			#else:
				#print("  -> Detected body ", body.name, " but it's not a valid enemy or is dead.")
		#else:
			#print("  -> Detected body ", body.name, " is not an enemy or lacks 'take_damage' method.")
	
	# --- Echo Element Logic ---
	if can_echo:
		# MODIFIED: Use a timer to add a specific delay before spawning the echo.
		# This ensures the echo detonation is delayed by ECHO_DETONATION_DELAY seconds.
		get_tree().create_timer(ECHO_DETONATION_DELAY, true, false, true).timeout.connect(
			_spawn_echo.bind(damage, radius, source_node, attack_stats)
		)
	
	# NEW FIX: Ensure the explosion node is eventually freed *after* the echo timer
	# has had a chance to trigger. Set the timer to be ECHO_DETONATION_DELAY + a small buffer.
	get_tree().create_timer(ECHO_DETONATION_DELAY + 0.1, true, false, true).timeout.connect(queue_free)


# Spawns the second, non-echoing explosion.
func _spawn_echo(damage: int, radius: float, source_node: Node, attack_stats: Dictionary):
	# DEBUG: Indicate when the echo is about to be spawned.
	#print("SparkExplosion: Spawning echo at ", global_position, ". Will call detonate deferred.")

	# Ensure the original explosion was instanced from a scene file.
	if self.scene_file_path.is_empty():
		push_error("SparkExplosion: Cannot spawn echo because original was not instanced from a scene.")
		return

	# Load the scene file to create a new, complete instance.
	var scene_to_instance = load(self.scene_file_path) as PackedScene
	if not is_instance_valid(scene_to_instance):
		push_error("SparkExplosion: Failed to load own scene for echo from path: " + self.scene_file_path)
		return
	
	var echo_explosion = scene_to_instance.instantiate()
	
	# Add to the same parent as the original explosion.
	get_parent().add_child(echo_explosion)
	echo_explosion.global_position = self.global_position

	# NEW FIX: Force a re-evaluation of the Area2D's monitoring state via deferred calls.
	# This can sometimes help an Area2D immediately register its overlaps after being added.
	# This is less critical now due to the added `await` in `detonate`, but kept for robustness.
	echo_explosion.set_deferred("monitoring", false)
	echo_explosion.set_deferred("monitoring", true)
	
	if echo_explosion.has_method("detonate"):
		# NEW FIX: Defer the detonate call for the echo explosion.
		# This gives the newly instantiated Area2D a moment to register in the physics
		# world before it attempts to detect overlaps, preventing the "blocking" issue.
		echo_explosion.call_deferred("detonate", damage, radius, source_node, attack_stats, false)
