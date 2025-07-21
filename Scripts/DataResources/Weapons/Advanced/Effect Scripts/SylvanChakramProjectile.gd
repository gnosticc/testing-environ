# File: SylvanChakramProjectile.gd
# Attach to: SylvanChakramProjectile.tscn (root Area2D)
# Purpose: Controls the behavior of the main chakram, including its arcing
# return path, damage dealing, and spawning of orbiting companions.
# REVISED: Corrected Thorn Nova logic to ensure the second burst is properly delayed.

class_name SylvanChakramProjectile
extends Area2D

signal returned_to_player

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# --- Internal State & Properties ---
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager
var _owner_player: PlayerCharacter
var _scene_resource: PackedScene
var _specific_weapon_stats: Dictionary

var _direction: Vector2
var _speed: float
var _damage: int
var _max_pierce_count: int
var _current_pierce_count: int = 0
var _enemies_hit: Array[Node2D] = []

# --- Flight Path State ---
enum FlightState { THROWING, ARCING, RETURNING, FINISHED }
var _flight_state = FlightState.THROWING
var _distance_traveled: float = 0.0
var _throw_distance: float
var _arc_center: Vector2
var _arc_start_angle: float
var _arc_current_angle: float
var _arc_total_angle: float = deg_to_rad(90.0)
var _arc_angle_traveled_so_far: float = 0.0
var _arc_direction_mod: float = 1.0
var _arc_radius: float

# --- Companion State ---
var _is_companion: bool = false
var _orbit_radius: float = 0.0
var _orbit_speed: float = 0.0
var _orbit_angle: float = 0.0

const THORN_NOVA_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/ThornSplinterProjectile.tscn")

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager, p_scene_resource: PackedScene):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	_owner_player = p_player_stats.get_parent()
	_scene_resource = p_scene_resource

	rotation = _direction.angle()
	
	_speed = float(_specific_stats.get("projectile_speed", 350.0)) * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	_max_pierce_count = int(_specific_stats.get("pierce_count", 999))
	_throw_distance = float(_specific_stats.get("throw_distance", 150.0))
	
	var weapon_damage_percent = float(_specific_stats.get("main_damage_percentage", 1.1))
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage	
	var main_scale = float(_specific_stats.get("main_chakram_scale", 1.0))
	self.scale = Vector2.ONE * main_scale
	
	lifetime_timer.start()
	animated_sprite.play("fly")
	
	if not _is_companion:
		_spawn_companions()

func _physics_process(delta: float):
	if _is_companion:
		_companion_orbit_process(delta)
		return

	if not is_instance_valid(_owner_player) or _flight_state == FlightState.FINISHED:
		return

	match _flight_state:
		FlightState.THROWING:
			var move_vector = _direction * _speed * delta
			global_position += move_vector
			_distance_traveled += move_vector.length()
			rotation += TAU * 2 * delta

			if _distance_traveled >= _throw_distance:
				_start_arc_phase()

		FlightState.ARCING:
			var angular_velocity = _speed / _arc_radius
			var angle_delta = angular_velocity * delta
			
			_arc_current_angle += angle_delta * _arc_direction_mod
			_arc_angle_traveled_so_far += angle_delta
			
			global_position = _arc_center + Vector2.RIGHT.rotated(_arc_current_angle) * _arc_radius
			rotation += TAU * 2 * delta

			if _arc_angle_traveled_so_far >= _arc_total_angle:
				_start_return_phase()

		FlightState.RETURNING:
			_direction = (_owner_player.global_position - global_position).normalized()
			global_position += _direction * _speed * delta
			rotation += TAU * 2 * delta

			if global_position.distance_to(_owner_player.global_position) < 15.0:
				_on_return_to_player()

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not _enemies_hit.has(body):
		var enemy = body as BaseEnemy
		if enemy.is_dead(): return
		
		if not _is_companion and _current_pierce_count >= _max_pierce_count:
			return

		_current_pierce_count += 1
		_enemies_hit.append(enemy)
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")
		enemy.take_damage(_damage, _owner_player, {}, weapon_tags)
		
		if _is_companion:
			print_debug("Companion Chakram Hit: Dealt ", _damage, " damage to ", enemy.name)

func _start_arc_phase():
	_flight_state = FlightState.ARCING
	_enemies_hit.clear()
	_current_pierce_count = 0
	_arc_angle_traveled_so_far = 0.0
	
	if _specific_stats.get("has_crescent_sweep", false):
		_arc_total_angle = PI
	else:
		_arc_total_angle = deg_to_rad(90.0)

	_arc_center = _owner_player.global_position
	_arc_radius = global_position.distance_to(_arc_center)
	
	if _arc_radius < 1.0:
		_start_return_phase()
		return
	
	var vector_to_start = (global_position - _arc_center).normalized()
	
	_arc_direction_mod = 1.0 
	if _specific_stats.get("is_mirrored_arc", false):
		_arc_direction_mod = -1.0
	
	_arc_start_angle = vector_to_start.angle()
	_arc_current_angle = _arc_start_angle

func _start_return_phase():
	_flight_state = FlightState.RETURNING
	_enemies_hit.clear()
	_current_pierce_count = 0

func _on_return_to_player():
	if _flight_state == FlightState.FINISHED:
		return
	_flight_state = FlightState.FINISHED

	var thorn_nova_active = _specific_stats.get("has_thorn_nova", false)
	var returning_burst_active = _specific_stats.get("has_returning_burst", false)
	
	if thorn_nova_active:
		# Always fire the first nova if the base upgrade is active.
		_spawn_thorn_nova()
		
		# If the second upgrade is also active, schedule the second nova.
		if returning_burst_active:
			var burst_delay = 0.2
			# Create a timer to spawn the second nova.
			var nova2_timer = get_tree().create_timer(burst_delay)
			nova2_timer.timeout.connect(_spawn_thorn_nova)
			
			# Create a separate timer to free this node, ensuring it lives long enough.
			var cleanup_timer = get_tree().create_timer(burst_delay + 0.1)
			cleanup_timer.timeout.connect(queue_free)
		else:
			# If only the first upgrade is active, free the node after a short delay.
			var cleanup_timer = get_tree().create_timer(0.1)
			cleanup_timer.timeout.connect(queue_free)
	else:
		# If neither upgrade is active, free the node immediately.
		queue_free()


func _spawn_thorn_nova():
	if not is_instance_valid(self) or not is_instance_valid(THORN_NOVA_SCENE): return
	var splinter_count = int(_specific_stats.get("thorn_nova_splinter_count", 8))
	var angle_step = TAU / float(splinter_count)
	
	for i in range(splinter_count):
		var splinter = THORN_NOVA_SCENE.instantiate()
		get_tree().current_scene.add_child(splinter)
		splinter.global_position = _owner_player.global_position
		var direction = Vector2.RIGHT.rotated(i * angle_step)
		if splinter.has_method("initialize"):
			splinter.initialize(direction, _specific_stats, _owner_player_stats)

func _spawn_companions():
	if not is_instance_valid(_scene_resource):
		push_warning("SylvanChakramProjectile: Cannot spawn companions, scene resource is invalid.")
		return
		
	var companions_to_spawn: Array[Dictionary] = []
	
	if _specific_stats.get("has_companion_chakram", false):
		companions_to_spawn.append({"radius_mod": 0, "speed_mod": 0.0, "angle": 0.0})
	
	if _specific_stats.get("has_sylvan_companion", false):
		var start_angle = PI if companions_to_spawn.size() > 0 else 0.0
		companions_to_spawn.append({"radius_mod": 1, "speed_mod": 1.5, "angle": start_angle})
		
	if companions_to_spawn.is_empty(): return
	
	var companion_scale = float(_specific_stats.get("companion_chakram_scale", 0.5))
	var orbit_radius_base = float(_specific_stats.get("companion_orbit_radius", 25.0))
	var orbit_speed_base = float(_specific_stats.get("companion_orbit_speed", 4.0))
	
	for config in companions_to_spawn:
		var companion = _scene_resource.instantiate() as SylvanChakramProjectile
		add_child(companion)
		
		var orbit_radius = orbit_radius_base + (config.radius_mod * 10)
		var orbit_speed = orbit_speed_base + config.speed_mod
		companion._configure_as_companion(orbit_radius, orbit_speed, _specific_stats, _owner_player_stats, companion_scale, config.angle)

func _configure_as_companion(orbit_rad: float, orbit_spd: float, stats: Dictionary, p_stats: PlayerStats, p_scale: float, initial_angle: float):
	_is_companion = true
	_orbit_radius = orbit_rad
	_orbit_speed = orbit_spd
	_orbit_angle = initial_angle
	
	lifetime_timer.stop()
	self.scale = Vector2.ONE * p_scale
	
	var companion_dmg_percent = float(stats.get("companion_damage_percentage", 0.7))
	var weapon_tags: Array[StringName] = stats.get("tags", [])
	var base_damage = p_stats.get_calculated_base_damage(companion_dmg_percent)
	var final_damage = p_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage	
	self.collision_layer = 4
	self.collision_mask = 136
	
	if is_instance_valid(collision_shape):
		collision_shape.disabled = false
	
	set_physics_process(true)
	_companion_orbit_process(0)

func _companion_orbit_process(delta: float):
	if not is_instance_valid(get_parent()):
		queue_free()
		return
		
	_orbit_angle += _orbit_speed * delta
	position = Vector2.RIGHT.rotated(_orbit_angle) * _orbit_radius
	rotation += TAU * 3 * delta
