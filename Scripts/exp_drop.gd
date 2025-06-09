# exp_drop.gd
# This script manages the behavior of experience orb drops, including their magnet
# effect towards the player and elite visual effects.
extends Area2D

@export var experience_value: int = 2 # The base experience value this orb provides
@export var magnet_speed: float = 150.0 # Speed at which the orb magnets to the player
@export var magnet_activation_distance: float = 80.0 # Distance at which magnet effect activates

var _magnet_activation_distance_sq: float # Squared distance for performance
var player_node: PlayerCharacter # Reference to the player character
var physics_frames_active: int = 0 # Counter for physics frames (can be used for delayed magnet activation)

var is_elite_drop: bool = false # Flag to indicate if this is an elite EXP drop

# Elite drop visual constants
const ELITE_DROP_COLOR_A: Color = Color(1.0, 0.9, 0.3, 1.0) # Bright Yellow/Gold
const ELITE_DROP_COLOR_B: Color = Color(1.0, 0.6, 0.0, 1.0) # Orange
const ELITE_FLASH_CYCLE_DURATION: float = 0.8 # Duration for one full color/scale pulse cycle
const ELITE_SCALE_PULSE_AMOUNT: float = 1.15 # Max scale during pulse
const ELITE_SCALE_PULSE_DURATION: float = 0.4 # Should be ELITE_FLASH_CYCLE_DURATION / 2.0 for sync

@onready var sprite: Sprite2D = $Sprite2D # Ensure your visual node is named "Sprite2D"

var _color_tween: Tween = null # Tween for color pulsating effect
var _scale_tween: Tween = null # Tween for scale pulsating effect

func _ready():
	set_physics_process(true) # Ensure physics_process is active
	add_to_group("exp_drops") # Add to group for easy collection by player
	_magnet_activation_distance_sq = magnet_activation_distance * magnet_activation_distance
	process_mode = Node.PROCESS_MODE_ALWAYS # Ensure processing even if game is paused (e.g., during level-up)
	
	if magnet_speed > 0.0:
		call_deferred("_find_player_node") # Defer finding player to ensure it's in the tree
	
	# Start elite visual effects if it's already marked as an elite drop.
	# Deferred call ensures _ready has finished and nodes are ready.
	if is_elite_drop:
		call_deferred("_start_elite_visual_effects")

func _notification(what: int):
	# Clean up tweens when the node is being deleted to prevent errors.
	if what == NOTIFICATION_PREDELETE:
		_kill_tweens()

# Stops and nullifies any active tweens to prevent memory leaks or errors.
func _kill_tweens():
	if is_instance_valid(_color_tween):
		_color_tween.kill()
		_color_tween = null
	if is_instance_valid(_scale_tween):
		_scale_tween.kill()
		_scale_tween = null

# Attempts to find the player node by looking in the "player_char_group".
func _find_player_node():
	if is_instance_valid(player_node): return
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		player_node = players[0] as PlayerCharacter
		if not is_instance_valid(player_node):
			push_error("ExpDrop: Found player_char_group, but player_node is invalid after cast.")
	else:
		push_warning("ExpDrop: Player node not found in group 'player_char_group'. Magnet will not work.")


func _physics_process(delta: float):
	physics_frames_active += 1
	
	# If player_node isn't found yet, try to find it again (only if magnet is active)
	if not is_instance_valid(player_node):
		if magnet_speed > 0.0: _find_player_node()
		if not is_instance_valid(player_node): return # If still not found, return

	if magnet_speed <= 0.0: return # No magnet effect if speed is zero

	var direction_to_player = player_node.global_position - global_position
	var distance_sq_to_player = direction_to_player.length_squared()

	# If player is within magnet activation distance, move towards player.
	if distance_sq_to_player < _magnet_activation_distance_sq:
		var movement_vector = direction_to_player.normalized() * magnet_speed * delta
		global_position += movement_vector

# Sets the experience value of the orb and its elite status.
# value: The integer experience value.
# p_is_elite: True if this drop is from an elite enemy, triggering visual effects.
func set_experience_value(value: int, p_is_elite: bool = false):
	experience_value = value
	is_elite_drop = p_is_elite

	# If it's an elite drop, start visual effects.
	# Check is_node_ready() to ensure _ready() has completed and @onready nodes are set.
	# If not ready, defer the call.
	if is_elite_drop:
		if is_node_ready() and is_instance_valid(sprite):
			_start_elite_visual_effects()
		else:
			call_deferred("_start_elite_visual_effects")

# Starts the pulsating color and scale visual effects for elite EXP drops.
func _start_elite_visual_effects():
	# Ensure the node is valid and in the scene tree before starting tweens.
	if not is_instance_valid(self) or not is_inside_tree(): return
	if not is_instance_valid(sprite):
		push_error("ExpDrop: Sprite2D node is invalid, cannot start elite visual effects.")
		return
	
	_kill_tweens() # Stop any existing tweens before creating new ones

	var original_scale = sprite.scale
	if original_scale == Vector2.ZERO: original_scale = Vector2.ONE # Prevent issues if scale is 0

	# Color Tween: Fades between two elite colors. Loops indefinitely.
	_color_tween = create_tween().set_loops()
	_color_tween.set_trans(Tween.TRANS_SINE) # Smooth transition
	_color_tween.set_ease(Tween.EASE_IN_OUT)
	sprite.modulate = ELITE_DROP_COLOR_A # Set initial color
	_color_tween.tween_property(sprite, "modulate", ELITE_DROP_COLOR_B, ELITE_FLASH_CYCLE_DURATION / 2.0)
	_color_tween.tween_property(sprite, "modulate", ELITE_DROP_COLOR_A, ELITE_FLASH_CYCLE_DURATION / 2.0)

	# Scale Tween: Pulses the scale. Loops indefinitely, parallel to color tween.
	_scale_tween = create_tween().set_loops().set_parallel(true)
	_scale_tween.set_trans(Tween.TRANS_SINE) # Smooth transition
	_scale_tween.set_ease(Tween.EASE_IN_OUT)
	# Tween to larger scale, then back to original.
	_scale_tween.tween_property(sprite, "scale", original_scale * ELITE_SCALE_PULSE_AMOUNT, ELITE_FLASH_CYCLE_DURATION / 2.0)
	_scale_tween.tween_property(sprite, "scale", original_scale, ELITE_FLASH_CYCLE_DURATION / 2.0)


# Called when the player collects the experience orb.
func collected():
	_kill_tweens() # Stop all tweens before removal
	queue_free() # Remove the experience orb from the scene
