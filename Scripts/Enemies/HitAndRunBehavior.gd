# HitAndRunBehavior.gd
# A component that, when added as a child to a BaseEnemy, overrides its
# movement to perform a hit-and-run tactic.
# VERSION 1.1: Refactored to use the owner's NavigationAgent2D for all movement
# and added a proper initialize function to prevent race conditions.

class_name HitAndRunBehavior extends Node

# --- State Machine for this behavior ---
enum State { INACTIVE, RETREATING, STALKING }
var current_state: State = State.INACTIVE

# --- Node References ---
var owner_enemy: BaseEnemy
var player_node: PlayerCharacter
var enemy_data: EnemyData
var navigation_agent: NavigationAgent2D

# --- Timers ---
var _attack_cooldown_timer: Timer
var _stalking_direction_change_timer: Timer

# --- Behavior Variables ---
var _stalking_direction: int = 1

func _ready():
	# Timers are created here, but references are set in initialize()
	_attack_cooldown_timer = Timer.new()
	_attack_cooldown_timer.name = "AttackCooldown"
	_attack_cooldown_timer.one_shot = true
	add_child(_attack_cooldown_timer)
	_attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout)
	
	_stalking_direction_change_timer = Timer.new()
	_stalking_direction_change_timer.name = "StalkingDirectionTimer"
	_stalking_direction_change_timer.wait_time = 1.0
	add_child(_stalking_direction_change_timer)
	_stalking_direction_change_timer.timeout.connect(_on_stalking_direction_change_timer_timeout)
	
	# This component is dormant until activated.
	set_physics_process(false)

func _physics_process(_delta):
	if not is_instance_valid(player_node) or not is_instance_valid(owner_enemy) or owner_enemy.is_dead():
		end_behavior()
		return

	var move_speed = _get_modified_speed()
	var new_velocity = Vector2.ZERO
	var target_position = owner_enemy.global_position

	match current_state:
		State.RETREATING:
			var hover_dist_sq = enemy_data.hover_distance * enemy_data.hover_distance
			var dist_sq_to_player = owner_enemy.global_position.distance_squared_to(player_node.global_position)
			
			if dist_sq_to_player > hover_dist_sq:
				_change_state(State.STALKING)
			else:
				var retreat_angle_rad = deg_to_rad(enemy_data.retreat_angle_variance)
				var random_angle = randf_range(-retreat_angle_rad, retreat_angle_rad)
				var retreat_direction = (owner_enemy.global_position - player_node.global_position).normalized().rotated(random_angle)
				target_position = owner_enemy.global_position + retreat_direction * 200 # Aim for a point far away
		
		State.STALKING:
			var hover_distance = enemy_data.hover_distance
			var direction_to_player = owner_enemy.global_position.direction_to(player_node.global_position)
			var tangent_direction = direction_to_player.orthogonal() * _stalking_direction
			var point_on_circle = player_node.global_position - direction_to_player * hover_distance
			target_position = point_on_circle + tangent_direction * 50 # Aim slightly ahead on the circle

	# Use the NavigationAgent to calculate the path to the target
	navigation_agent.target_position = target_position
	if not navigation_agent.is_navigation_finished():
		var next_path_pos = navigation_agent.get_next_path_position()
		var move_direction = owner_enemy.global_position.direction_to(next_path_pos)
		new_velocity = move_direction * move_speed
	
	# Set the owner's velocity directly.
	owner_enemy.velocity = new_velocity

func _change_state(new_state: State):
	if current_state == new_state: return
	current_state = new_state
	
	match current_state:
		State.INACTIVE:
			set_physics_process(false)
			_stalking_direction_change_timer.stop()
		
		State.RETREATING:
			set_physics_process(true)
			_stalking_direction_change_timer.stop()
			owner_enemy._play_animation(&"walk")
		
		State.STALKING:
			set_physics_process(true)
			_attack_cooldown_timer.wait_time = enemy_data.attack_cooldown
			_attack_cooldown_timer.start()
			_stalking_direction_change_timer.start()
			owner_enemy._play_animation(&"walk")

func _get_modified_speed() -> float:
	var base_move_speed = owner_enemy.speed
	
	match current_state:
		State.RETREATING:
			base_move_speed *= enemy_data.retreat_speed_multiplier
		State.STALKING:
			base_move_speed *= enemy_data.stalking_speed_multiplier
	
	# Let the owner apply its own status effect modifiers
	return owner_enemy.apply_status_effect_speed_modifiers(base_move_speed)

# --- Public API for BaseEnemy to call ---

func initialize(p_owner_enemy: BaseEnemy):
	owner_enemy = p_owner_enemy
	player_node = owner_enemy.player_node
	enemy_data = owner_enemy.enemy_data_resource
	navigation_agent = owner_enemy.navigation_agent

func start_behavior():
	if current_state == State.INACTIVE:
		owner_enemy.set_behavior_override(true)
		_change_state(State.RETREATING)

func end_behavior():
	if current_state != State.INACTIVE:
		owner_enemy.set_behavior_override(false)
		_change_state(State.INACTIVE)
		owner_enemy._change_state(BaseEnemy.State.CHASING)

# --- Timer Callbacks ---

func _on_attack_cooldown_timeout():
	if current_state == State.STALKING:
		end_behavior()

func _on_stalking_direction_change_timer_timeout():
	if current_state == State.STALKING:
		if randf() < enemy_data.stalk_reverse_direction_chance:
			_stalking_direction *= -1
