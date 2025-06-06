# exp_drop.gd
extends Area2D

@export var experience_value: int = 2 
@export var magnet_speed: float = 150.0 
@export var magnet_activation_distance: float = 80.0 

var _magnet_activation_distance_sq: float
var player_node 
var physics_frames_active: int = 0 

var is_elite_drop: bool = false

const ELITE_DROP_COLOR_A: Color = Color(1.0, 0.9, 0.3, 1.0) # Bright Yellow/Gold
const ELITE_DROP_COLOR_B: Color = Color(1.0, 0.6, 0.0, 1.0) # Orange
const ELITE_FLASH_CYCLE_DURATION: float = 0.8 
const ELITE_SCALE_PULSE_AMOUNT: float = 1.15 
const ELITE_SCALE_PULSE_DURATION: float = 0.4 # Should be ELITE_FLASH_CYCLE_DURATION / 2.0 for sync

@onready var sprite: Sprite2D = $Sprite2D # Ensure your visual node is named "Sprite2D"

var _color_tween: Tween = null
var _scale_tween: Tween = null

func _ready():
	set_physics_process(true) 
	add_to_group("exp_drops")
	_magnet_activation_distance_sq = magnet_activation_distance * magnet_activation_distance
	process_mode = Node.PROCESS_MODE_ALWAYS 
	if magnet_speed > 0.0:
		_find_player_node() 
	
	if is_elite_drop: # If set_experience_value was called before _ready
		# is_node_ready() will be false here, so deferring is correct
		call_deferred("_start_elite_visual_effects") 

func _notification(what: int):
	if what == NOTIFICATION_PREDELETE: 
		_kill_tweens() 
	# if what == NOTIFICATION_PARENTED:
		# var parent_node = get_parent()
	# if what == NOTIFICATION_EXIT_TREE:
		# pass

func _kill_tweens():
	if is_instance_valid(_color_tween):
		_color_tween.kill()
		_color_tween = null
	if is_instance_valid(_scale_tween):
		_scale_tween.kill()
		_scale_tween = null

func _find_player_node():
	if is_instance_valid(player_node): return 
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0: player_node = players[0]

func _physics_process(delta: float):
	physics_frames_active += 1
	if not is_instance_valid(player_node):
		if magnet_speed > 0.0: _find_player_node() 
		if not is_instance_valid(player_node): 
			return 
	if magnet_speed <= 0.0: 
		return

	var direction_to_player = player_node.global_position - global_position
	var distance_sq_to_player = direction_to_player.length_squared()

	if distance_sq_to_player < _magnet_activation_distance_sq:
		var movement_vector = direction_to_player.normalized() * magnet_speed * delta
		global_position += movement_vector

func set_experience_value(value: int, p_is_elite: bool = false):
	experience_value = value
	is_elite_drop = p_is_elite

	if is_elite_drop:
		# Use is_node_ready() to check if _ready() has completed
		if is_node_ready() and is_instance_valid(sprite): 
			_start_elite_visual_effects()
		else: 
			call_deferred("_start_elite_visual_effects")

func _start_elite_visual_effects():
	if not is_instance_valid(self) or not is_inside_tree(): return 
	if not is_instance_valid(sprite): return
	
	_kill_tweens() 

	var original_scale = sprite.scale 
	if original_scale == Vector2.ZERO: original_scale = Vector2.ONE

	_color_tween = create_tween().set_loops()
	_color_tween.set_trans(Tween.TRANS_SINE)
	_color_tween.set_ease(Tween.EASE_IN_OUT)
	sprite.modulate = ELITE_DROP_COLOR_A # Set initial color for the tween
	_color_tween.tween_property(sprite, "modulate", ELITE_DROP_COLOR_B, ELITE_FLASH_CYCLE_DURATION / 2.0)
	_color_tween.tween_property(sprite, "modulate", ELITE_DROP_COLOR_A, ELITE_FLASH_CYCLE_DURATION / 2.0)

	_scale_tween = create_tween().set_loops().set_parallel(true)
	_scale_tween.set_trans(Tween.TRANS_SINE)
	_scale_tween.set_ease(Tween.EASE_IN_OUT)
	_scale_tween.tween_property(sprite, "scale", original_scale * ELITE_SCALE_PULSE_AMOUNT, ELITE_FLASH_CYCLE_DURATION / 2.0)
	_scale_tween.tween_property(sprite, "scale", original_scale, ELITE_FLASH_CYCLE_DURATION / 2.0)


func collected():
	_kill_tweens() 
	queue_free()
