# File: res/Scripts/Weapons/Projectiles/PhantomBashExplosion.gd
# REVISED: Now uses call_deferred for robust, safe damage detection and cleanup.
# FIX: Added an await physics_frame after enabling the collision shape to ensure overlaps are detected.
# NEW FIX: Enhanced collision shape activation with deferred radius setting and explicit monitoring toggle.
# NEW FIX: Added a small explicit timer before physics_frame await for more reliable Area2D activation.
# NEW: Added debug print for visual scaling.
# NEW FIX: Scaled the CollisionShape2D to be 25% larger than the animated sprite's intended diameter.

class_name PhantomBashExplosion
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Variables to hold the detonation data
var _damage: int
var _radius: float
var _source_node: Node
var _attack_stats: Dictionary
var _specific_stats: Dictionary

func _ready():
	# The node starts completely inert.
	# FIX: Use set_deferred to ensure these changes are safe if _ready is ever called in a sensitive context.
	collision_shape.set_deferred("disabled", true)
	animated_sprite.visible = false
	animated_sprite.stop()
	
	# Connect the signal here. It will fire once the animation is played.
	animated_sprite.animation_finished.connect(_on_animation_finished)

# This is called by ShieldBashAttack after a 1-second delay.
func detonate(damage: int, radius: float, source_node: Node, attack_stats: Dictionary, p_weapon_stats: Dictionary):
	if not is_instance_valid(self): return

	# Store the data for when the animation finishes.
	_damage = damage
	_radius = radius
	_source_node = source_node
	_attack_stats = attack_stats
	_specific_stats = p_weapon_stats # Store the weapon stats
	
	# --- VISUAL SCALING LOGIC ---
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
		var sprite_texture = animated_sprite.sprite_frames.get_frame_texture("explode", 0)
		var base_width = 0.0
		if is_instance_valid(sprite_texture): # Ensure texture is valid before getting width
			base_width = float(sprite_texture.get_width())

		if base_width > 0:
			var desired_diameter = _radius * 2.0
			var scale_factor = desired_diameter / base_width
			animated_sprite.scale = Vector2.ONE * scale_factor
			#print("PhantomBashExplosion: detonate - Visual scale: desired_diameter=", desired_diameter, ", base_width=", base_width, ", scale_factor=", scale_factor, ", final_scale=", animated_sprite.scale)
		else:
			#push_warning("PhantomBashExplosion WARNING: 'explode' animation texture base width is 0 or texture is invalid. Cannot scale animation.")
			# If scaling fails, set a default small scale to prevent it from being huge
			animated_sprite.scale = Vector2(0.1, 0.1) # Fallback to a small size

	# Make the animation visible and play it. The damage will happen on the last frame.
	if is_instance_valid(animated_sprite):
		animated_sprite.visible = true
		animated_sprite.play("explode")

# This function is now called ONLY when the "explode" animation completes.
func _on_animation_finished():
	if not is_instance_valid(self): return
	
	# Defer the entire damage and cleanup process to the next idle frame.
	# This is the safest way to interact with the physics engine after a state change.
	call_deferred("_deal_damage_and_cleanup")

func _deal_damage_and_cleanup():
	if not is_instance_valid(self): return

	# Ensure the collision_shape node itself is valid
	if not is_instance_valid(collision_shape):
		push_error("PhantomBashExplosion ERROR: CollisionShape2D node is invalid. Cannot enable collision.")
		queue_free()
		return # Exit early

	# Ensure the shape resource is valid AND is a CircleShape2D
	if not is_instance_valid(collision_shape.shape) or not (collision_shape.shape is CircleShape2D):
		push_error("PhantomBashExplosion ERROR: CollisionShape2D's shape is invalid or not a CircleShape2D. Cannot enable collision.")
		queue_free()
		return # Exit early

	# Print state before changes
	#print("PhantomBashExplosion: _deal_damage_and_cleanup - Before activation: disabled=", collision_shape.disabled, ", monitoring=", self.monitoring)

	# NEW FIX: Calculate the collision radius to be 25% larger than the visual radius.
	var collision_radius = _radius * 1.25 # _radius is the base for visual diameter, so this makes the collision radius 25% larger than the visual radius.
	(collision_shape.shape as CircleShape2D).call_deferred("set", &"radius", collision_radius)
	
	# Enable the hitbox using set_deferred
	collision_shape.set_deferred("disabled", false)

	# Force a re-evaluation of the Area2D's monitoring state by deferring a disable-then-enable.
	# This is often the trick for stubborn Area2D detection issues.
	self.set_deferred("monitoring", false)
	self.set_deferred("monitoring", true)

	# NEW FIX: Add a very small explicit timer BEFORE awaiting the physics frame.
	# This gives Godot's deferred queue a tiny buffer to process the set_deferred calls.
	#print("PhantomBashExplosion: _deal_damage_and_cleanup - Waiting 0.02s (for deferred calls to process).")
	await get_tree().create_timer(0.02).timeout # Slightly increased delay from 0.01

	# Await one physics frame AFTER all deferred changes are scheduled.
	# This is crucial for the physics server to process all the 'set_deferred' calls.
	#print("PhantomBashExplosion: _deal_damage_and_cleanup - Awaiting next physics frame.")
	await get_tree().physics_frame
	
	# Print state immediately after physics frame update
	#print("PhantomBashExplosion: _deal_damage_and_cleanup - After physics frame: disabled=", collision_shape.disabled, ", monitoring=", self.monitoring)

	var bodies = get_overlapping_bodies()
	#print("PhantomBashExplosion at ", global_position, ": Detected ", bodies.size(), " overlapping bodies.") # Debug print
	for body in bodies:
		if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
			var weapon_tags: Array[StringName] = []
			if _specific_stats.has("tags"):
				weapon_tags = _specific_stats.get("tags")
			body.take_damage(_damage, _source_node, _attack_stats, weapon_tags) # Pass tags
			#print("  -> Hit enemy: ", body.name, " (ID: ", body.get_instance_id(), ") for ", _damage, " damage.") # Debug print
		#else:
			#print("  -> Detected body ", body.name, " but it's not a valid enemy or is dead.") # Debug print
			#
	# Now that the work is done, remove the node.
	queue_free()
