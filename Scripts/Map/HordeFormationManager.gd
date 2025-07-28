# HordeFormationManager.gd
# This node creates and manages a formation of "attack slots" around the player.
# VERSION 2.1: Fixed "signal already connected" error by checking before connecting.
# Also fixed a bug in the queue processing loop to make it more robust.

class_name HordeFormationManager extends Node

@export var number_of_slots: int = 32
@export var formation_radius: float = 125.0
@export var requests_to_process_per_frame: int = 10

# --- Private Variables ---
var _slots: Array[Vector2] = []
var _slot_occupied: Array[bool] = []
var _enemy_assignments: Dictionary = {} # Key: enemy instance, Value: slot index
var _request_queue: Array[BaseEnemy] = []

@onready var player_node: PlayerCharacter = null

func _ready():
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		player_node = players[0]
	else:
		push_error("HordeFormationManager: Player not found! Disabling.")
		set_process(false)
		return
		
	_generate_formation_slots()
	_slot_occupied.resize(number_of_slots)
	_slot_occupied.fill(false)

func _process(_delta):
	if _request_queue.is_empty():
		return
		
	var processed_count = 0
	# --- BUG FIX: Iterate backwards when removing from an array ---
	# This prevents skipping elements, which can happen when iterating forwards
	# while removing items from the same array.
	var i = _request_queue.size() - 1
	while i >= 0 and processed_count < requests_to_process_per_frame:
		var enemy = _request_queue[i]
		if is_instance_valid(enemy):
			# If the enemy is still chasing, try to assign it a slot.
			if enemy.current_state == BaseEnemy.State.CHASING:
				_find_and_assign_slot(enemy)
			
			processed_count += 1
		
		# Always remove the enemy from the queue after processing.
		_request_queue.remove_at(i)
		i -= 1
	# --- END BUG FIX ---


func _generate_formation_slots():
	_slots.clear()
	if number_of_slots <= 0: return
	
	var angle_step = TAU / number_of_slots
	for i in range(number_of_slots):
		var angle = i * angle_step
		var offset = Vector2.RIGHT.rotated(angle) * formation_radius
		_slots.append(offset)

func _find_and_assign_slot(enemy: BaseEnemy):
	if not is_instance_valid(enemy): return
	
	# Find the closest, unoccupied slot to the requesting enemy.
	var best_slot_index = -1
	var closest_dist_sq = INF
	
	for i in range(_slots.size()):
		if not _slot_occupied[i]:
			var slot_world_pos = player_node.global_position + _slots[i]
			var dist_sq = enemy.global_position.distance_squared_to(slot_world_pos)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				best_slot_index = i
				
	if best_slot_index != -1:
		# Assign the slot
		_slot_occupied[best_slot_index] = true
		_enemy_assignments[enemy] = best_slot_index
		enemy.assigned_slot_index = best_slot_index # Tell the enemy its new slot
		
		# --- SOLUTION: Check before connecting the signal ---
		# This prevents the "signal is already connected" error by ensuring we only
		# connect the death-watch signal once per enemy lifetime.
		var release_callable = Callable(self, "release_slot").bind(enemy)
		if not enemy.is_connected("tree_exiting", release_callable):
			enemy.connect("tree_exiting", release_callable, CONNECT_ONE_SHOT)
		# --- END SOLUTION ---

# --- Public API ---

func enqueue_request(enemy: BaseEnemy):
	# Instead of processing immediately, add the enemy to a queue.
	if is_instance_valid(enemy) and not _request_queue.has(enemy):
		_request_queue.append(enemy)

func release_slot(enemy: BaseEnemy):
	if _enemy_assignments.has(enemy):
		var slot_index = _enemy_assignments[enemy]
		if slot_index >= 0 and slot_index < _slot_occupied.size():
			_slot_occupied[slot_index] = false
		_enemy_assignments.erase(enemy)

func get_slot_offset(index: int) -> Vector2:
	if index >= 0 and index < _slots.size():
		return _slots[index]
	return Vector2.ZERO
