# File: res/Scripts/Weapons/Projectiles/SparkExplosion.gd
# FIX: Resolved race condition by using state flags to ensure the node is only
# destroyed after both its animation has finished AND its echo has been spawned.

class_name SparkExplosion
extends Area2D

const HITBOX_SCALE_MULTIPLIER = 1.25
const ECHO_DETONATION_DELAY = 0.3

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- NEW: State flags to manage the race condition ---
var _can_echo_flag: bool = false
var _echo_has_spawned: bool = false

func _ready():
	collision_shape.set_deferred("disabled", true)
	animated_sprite.visible = false
	animated_sprite.stop()
	# Connect the signal once. The handler will manage the logic.
	animated_sprite.animation_finished.connect(_on_animation_finished)

func detonate(damage: int, radius: float, source_node: Node, attack_stats: Dictionary, can_echo: bool, p_weapon_stats: Dictionary):
	if not is_instance_valid(self): return

	_can_echo_flag = can_echo

	# --- Visual Setup ---
	var sprite_base_size = animated_sprite.sprite_frames.get_frame_texture(&"default", 0).get_width()
	if sprite_base_size > 0:
		var desired_diameter = radius * 2.0
		var scale_factor = desired_diameter / sprite_base_size
		animated_sprite.scale = Vector2(scale_factor, scale_factor)

	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).call_deferred("set", &"radius", radius * HITBOX_SCALE_MULTIPLIER)

	animated_sprite.visible = true
	animated_sprite.play("default")

	# --- Damage Logic ---
	await get_tree().create_timer(0.02).timeout
	await get_tree().physics_frame
	collision_shape.set_deferred("disabled", false)
	self.set_deferred("monitoring", true)
	await get_tree().physics_frame

	var weapon_tags: Array[StringName] = []
	if p_weapon_stats.has("tags"):
		weapon_tags = p_weapon_stats.get("tags")
		
	var targets_to_hit = get_overlapping_bodies()
	for body in targets_to_hit:
		if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
			body.take_damage(damage, source_node, attack_stats, weapon_tags)

	self.set_deferred("monitoring", false)

	# --- Echo Logic ---
	if _can_echo_flag:
		# Create an independent timer to spawn the echo.
		get_tree().create_timer(ECHO_DETONATION_DELAY).timeout.connect(
			_spawn_echo.bind(damage, radius, source_node, attack_stats, p_weapon_stats, global_position)
		)

# This function is called when the animation finishes playing.
func _on_animation_finished():
	# If we are not expecting an echo, we can free the node immediately.
	# If we ARE expecting an echo, we only free the node if the echo has already spawned.
	if not _can_echo_flag or _echo_has_spawned:
		queue_free()

# This function is called by the SceneTreeTimer for the echo.
func _spawn_echo(damage: int, radius: float, source_node: Node, attack_stats: Dictionary, p_weapon_stats: Dictionary, spawn_position: Vector2):
	# Set the flag to true, indicating the echo has been created.
	_echo_has_spawned = true

	if self.scene_file_path.is_empty():
		push_error("SparkExplosion: Cannot spawn echo because original was not instanced from a scene.")
		# If we can't spawn the echo, check if we should clean up the original node now.
		if not animated_sprite.is_playing():
			queue_free()
		return

	var scene_to_instance = load(self.scene_file_path) as PackedScene
	if not is_instance_valid(scene_to_instance):
		push_error("SparkExplosion: Failed to load own scene for echo from path: " + self.scene_file_path)
		return

	var echo_explosion = scene_to_instance.instantiate() as SparkExplosion
	get_tree().current_scene.add_child(echo_explosion)
	echo_explosion.global_position = spawn_position

	if echo_explosion.has_method("detonate"):
		echo_explosion.call_deferred("detonate", damage, radius, source_node, attack_stats, false, p_weapon_stats)

	# After spawning the echo, check if the original animation has already finished.
	# If it has, we can now safely clean up the original node.
	if not animated_sprite.is_playing():
		queue_free()
