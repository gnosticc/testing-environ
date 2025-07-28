# DynamicNavigationManager.gd
# This script creates and manages a large, moving navigation region that follows the player.
# This provides a seemingly "endless" pathfinding area for enemies in an infinite world.
# VERSION 3.7: FINAL FIX 3 - Removed redundant and erroneous parse_source_geometry_data call.

class_name DynamicNavigationManager extends Node2D

# Signal emitted after the first navigation mesh is successfully baked.
signal initial_bake_complete

# --- Configuration ---
@export var region_size: Vector2 = Vector2(8000, 8000)
@export var update_interval: float = 0.5
@export var update_threshold_percent: float = 0.5

# --- Node References ---
@onready var _nav_region: NavigationRegion2D = $DynamicNavRegion

# --- Private Variables ---
var _player_node: PlayerCharacter
var _update_timer: Timer
var _initial_bake_done: bool = false
var _is_baking: bool = false # To prevent multiple bakes at once

func _ready():
	# Find the player node
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0:
		_player_node = players[0] as PlayerCharacter
	else:
		push_error("DynamicNavigationManager: Player node not found. Disabling manager.")
		set_process(false)
		return

	# 1. Verify the NavigationRegion2D node from the scene
	if not is_instance_valid(_nav_region):
		push_error("DynamicNavigationManager: Child node named 'DynamicNavRegion' not found! Please add a NavigationRegion2D as a child to this node in the editor.")
		set_process(false)
		return

	# Defer the initial setup and bake by one frame
	await get_tree().process_frame

	# 2. Center the region on the player's starting position
	_update_navigation_region_position()

	# 3. Bake the initial navigation mesh
	_bake_navigation_mesh()

	# 4. Set up a timer to periodically check for updates
	_update_timer = Timer.new()
	_update_timer.name = "NavUpdateTimer"
	_update_timer.wait_time = update_interval
	_update_timer.one_shot = false
	add_child(_update_timer)
	_update_timer.timeout.connect(_on_update_timer_timeout)
	_update_timer.start()

# --- Private Methods ---

func _on_update_timer_timeout():
	if not is_instance_valid(_player_node):
		return

	var distance_from_center = _player_node.global_position - self.global_position
	var threshold = region_size * update_threshold_percent

	if abs(distance_from_center.x) > threshold.x or abs(distance_from_center.y) > threshold.y:
		_update_navigation_region_position()
		_bake_navigation_mesh()

func _update_navigation_region_position():
	if not is_instance_valid(_player_node):
		return
	print_debug("Re-centering navigation manager on player at: ", _player_node.global_position)
	self.global_position = _player_node.global_position
	
	# After moving the node in the scene tree, we MUST explicitly tell the
	# NavigationServer where the region now is.
	if is_instance_valid(_nav_region) and _nav_region.get_rid().is_valid():
		NavigationServer2D.region_set_transform(_nav_region.get_rid(), _nav_region.global_transform)


func _bake_navigation_mesh():
	if _is_baking:
		return
	_is_baking = true

	var new_nav_poly = NavigationPolygon.new()
	var source_geometry_data = NavigationMeshSourceGeometryData2D.new()
	var half_size = region_size / 2.0
	var rectangle_points = PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	])
	source_geometry_data.add_traversable_outline(rectangle_points)
	
	# --- SOLUTION ---
	# The asynchronous bake_from_source_geometry_data function handles parsing internally.
	# The previous, explicit call to parse_source_geometry_data was both redundant
	# and, as you correctly pointed out, had the wrong number of arguments.
	# Removing it fixes the crash.
	# --- END SOLUTION ---
	
	var on_bake_finished_callable = Callable(self, "_on_bake_finished").bind(new_nav_poly)
	NavigationServer2D.bake_from_source_geometry_data(new_nav_poly, source_geometry_data, on_bake_finished_callable)

func _on_bake_finished(baked_polygon: NavigationPolygon):
	_nav_region.navigation_polygon = baked_polygon
	
	# It's good practice to set the transform again after assigning a new polygon.
	# This ensures sync even if the node hasn't moved but the mesh has changed.
	if is_instance_valid(_nav_region) and _nav_region.get_rid().is_valid():
		NavigationServer2D.region_set_transform(_nav_region.get_rid(), _nav_region.global_transform)

	_is_baking = false
	
	if not _initial_bake_done:
		_initial_bake_done = true
		print_debug("Initial navigation bake complete and mesh assigned.")
		emit_signal("initial_bake_complete")
