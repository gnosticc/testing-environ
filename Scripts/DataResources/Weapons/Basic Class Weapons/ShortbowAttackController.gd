# Scripts/DataResources/Weapons/Basic Class Weapons/ShortbowAttackController.gd
# MODIFIED SCRIPT
# This script manages the firing pattern for the Shortbow. It is now refactored
# to use a queue and a Timer, removing the 'async' keyword and making the
# multi-shot behavior more robust and consistent with project standards.
# NEW: Implemented simultaneous firing for 'Arrow Storm' upgrade.

class_name ShortbowAttackController
extends Node2D

@export var arrow_scene: PackedScene

var _received_stats: Dictionary
var _owner_player_stats: PlayerStats

## NEW: Queue and Timer for handling multi-shot volleys without async/await.
## The queue can now hold either single shot dictionaries or arrays of shot dictionaries (for simultaneous volleys).
var _shot_queue: Array = []
var _shot_timer: Timer

func _ready():
	# Create and configure the timer for handling delays between shots.
	_shot_timer = Timer.new()
	_shot_timer.name = "ShotDelayTimer"
	_shot_timer.one_shot = true # The timer fires once per shot delay.
	add_child(_shot_timer)
	_shot_timer.timeout.connect(_process_shot_queue)

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_received_stats = p_attack_stats.duplicate(true)
	_owner_player_stats = p_player_stats

	if not is_instance_valid(arrow_scene):
		push_error("ERROR (ShortbowAttackController): Arrow scene not assigned!"); queue_free(); return

	var has_hail_of_arrows = _received_stats.get(&"has_hail_of_arrows", false)
	var arrows_per_direction = int(_received_stats.get(&"arrows_per_direction", 1))
	var is_storm_shot = _received_stats.get("is_arrow_storm_shot", false)

	_shot_queue.clear() # Clear any previous queue content

	if is_storm_shot:
		# For Arrow Storm, fire arrows in all active directions simultaneously.
		# The 'arrows_per_direction' stat now dictates how many *volleys* (sets of simultaneous arrows) to fire.
		# Arrow Storm itself triples the base arrow count.
		var total_volleys = arrows_per_direction * 3 # Each volley will contain multiple arrows

		var directions_for_volley: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT]
		if has_hail_of_arrows:
			directions_for_volley.append(Vector2.UP)
			directions_for_volley.append(Vector2.DOWN)

		# Build the queue with arrays of directions for simultaneous firing
		for i in range(total_volleys):
			var volley_shots: Array[Dictionary] = []
			for dir_vec in directions_for_volley:
				volley_shots.append({"direction": dir_vec})
			_shot_queue.append(volley_shots) # Each item in queue is now an array (a volley)
		
		print_debug("ShortbowAttackController: Queuing ", total_volleys, " Arrow Storm volleys. Each volley will fire ", directions_for_volley.size(), " arrows simultaneously.")
	else:
		# For non-Arrow Storm modes, maintain the existing sequential firing per direction.
		# Double Shot (if active) already modifies 'arrows_per_direction' in WeaponManager.
		print_debug("ShortbowAttackController: Queuing ", arrows_per_direction, " sequential arrows per direction.")
		_build_sequential_shot_queue(Vector2.LEFT, arrows_per_direction)
		_build_sequential_shot_queue(Vector2.RIGHT, arrows_per_direction)
		if has_hail_of_arrows:
			_build_sequential_shot_queue(Vector2.UP, arrows_per_direction)
			_build_sequential_shot_queue(Vector2.DOWN, arrows_per_direction)
	
	# Start processing the queue.
	if not _shot_queue.is_empty():
		_process_shot_queue()
	else:
		queue_free()

# Helper function to build the queue for sequential firing (non-Arrow Storm)
func _build_sequential_shot_queue(direction: Vector2, number_of_arrows: int):
	for i in range(number_of_arrows):
		var shot_info = {
			"direction": direction,
		}
		_shot_queue.append(shot_info)

func _process_shot_queue():
	if _shot_queue.is_empty():
		queue_free()
		return

	var next_item = _shot_queue.pop_front()
	
	if next_item is Array: # This is an Arrow Storm volley (array of shots)
		print_debug("ShortbowAttackController: Firing Arrow Storm volley with ", next_item.size(), " arrows. ", _shot_queue.size(), " volleys remaining.")
		for shot_info in next_item:
			_fire_arrow(shot_info.direction)
	else: # This is a regular single arrow shot (dictionary with direction)
		print_debug("ShortbowAttackController: Fired single arrow. ", _shot_queue.size(), " shots remaining in queue.")
		_fire_arrow(next_item.direction)
	
	if not _shot_queue.is_empty():
		var intra_shot_delay = float(_received_stats.get(&"shot_delay", 0.1))
		_shot_timer.wait_time = intra_shot_delay
		_shot_timer.start()

func _fire_arrow(direction: Vector2):
	if not is_instance_valid(arrow_scene): return
	
	var arrow_stats = _received_stats.duplicate(true)
	var arrow_instance = arrow_scene.instantiate()
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	
	if is_instance_valid(attacks_container):
		attacks_container.add_child(arrow_instance)
	else:
		get_tree().current_scene.add_child(arrow_instance)
	
	arrow_instance.global_position = self.global_position

	if arrow_instance.has_method("set_attack_properties"):
		arrow_instance.set_attack_properties(direction, arrow_stats, _owner_player_stats)
	else:
		push_error("ShortbowAttackController: Spawned arrow is missing 'set_attack_properties' method.")
