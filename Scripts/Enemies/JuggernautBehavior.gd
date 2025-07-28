# JuggernautBehavior.gd
# A component that gives an enemy a powerful, telegraphed charging attack.
# VERSION 1.8: Added a tunable homing/course-correction feature to the charge.

class_name JuggernautBehavior extends Node

enum State { INACTIVE, TELEGRAPHING, CHARGING, STUNNED }
var current_state: State = State.INACTIVE

# --- Node References ---
var owner_enemy: BaseEnemy
var player_node: PlayerCharacter
var enemy_data: EnemyData
var charge_cast: ShapeCast2D

# --- Timers ---
var _charge_trigger_timer: Timer
var _telegraph_timer: Timer
var _stun_timer: Timer

# --- Behavior Variables ---
var _charge_direction: Vector2
var _charge_distance_traveled: float = 0.0
var _is_initialized: bool = false

func _ready():
	_charge_trigger_timer = Timer.new()
	_charge_trigger_timer.name = "ChargeTriggerTimer"
	_charge_trigger_timer.one_shot = true
	add_child(_charge_trigger_timer)
	_charge_trigger_timer.timeout.connect(_on_charge_trigger_timer_timeout)
	
	_telegraph_timer = Timer.new()
	_telegraph_timer.name = "TelegraphTimer"
	_telegraph_timer.one_shot = true
	add_child(_telegraph_timer)
	_telegraph_timer.timeout.connect(_on_telegraph_timer_timeout)
	
	_stun_timer = Timer.new()
	_stun_timer.name = "StunTimer"
	_stun_timer.one_shot = true
	add_child(_stun_timer)
	_stun_timer.timeout.connect(_on_stun_timer_timeout)
	
	set_physics_process(false)

func _physics_process(delta):
	if not is_instance_valid(player_node) or not is_instance_valid(owner_enemy) or owner_enemy.is_dead():
		end_behavior()
		return
		
	if current_state == State.CHARGING:
		if not is_instance_valid(charge_cast):
			end_charge()
			return

		var move_speed = _get_modified_speed()
		
		# --- SOLUTION: Add weak homing/course correction ---
		# On each frame, calculate the ideal direction to the player.
		var ideal_direction = owner_enemy.global_position.direction_to(player_node.global_position)
		# Interpolate the current charge direction slightly towards the ideal direction.
		# A higher homing_strength value in the .tres file will make the turn sharper.
		_charge_direction = _charge_direction.lerp(ideal_direction, enemy_data.charge_homing_strength * delta)
		# --- END SOLUTION ---

		var move_vector = _charge_direction * move_speed
		
		# Configure and execute the shapecast to detect hits.
		charge_cast.target_position = move_vector * delta
		charge_cast.force_shapecast_update()
		
		if charge_cast.is_colliding():
			var collider = charge_cast.get_collider(0)
			if collider == player_node:
				owner_enemy.call_deferred("_try_deal_contact_damage")
				end_charge()
				return
		
		# Move the enemy
		owner_enemy.velocity = move_vector
		_charge_distance_traveled += move_vector.length() * delta
		
		if _charge_distance_traveled >= enemy_data.charge_max_distance:
			end_charge()

func _change_state(new_state: State):
	if current_state == new_state: return
	current_state = new_state
	
	match current_state:
		State.INACTIVE:
			set_physics_process(false)
			owner_enemy.set_behavior_override(false)
		
		State.TELEGRAPHING:
			set_physics_process(false)
			owner_enemy.velocity = Vector2.ZERO
			owner_enemy.set_behavior_override(true)
			_telegraph_timer.wait_time = enemy_data.charge_telegraph_duration
			_telegraph_timer.start()
			
			var tween = create_tween().set_loops(2)
			tween.tween_property(owner_enemy.animated_sprite, "modulate", Color.RED, 0.2)
			tween.tween_property(owner_enemy.animated_sprite, "modulate", owner_enemy._final_base_modulate_color, 0.2)
		
		State.CHARGING:
			set_physics_process(true)
			_charge_distance_traveled = 0.0
			_charge_direction = owner_enemy.global_position.direction_to(player_node.global_position)
		
		State.STUNNED:
			set_physics_process(false)
			owner_enemy.velocity = Vector2.ZERO
			_stun_timer.wait_time = enemy_data.post_charge_stun_duration
			_stun_timer.start()

# --- Public API ---
func initialize(p_owner_enemy: BaseEnemy):
	owner_enemy = p_owner_enemy
	player_node = owner_enemy.player_node
	enemy_data = owner_enemy.enemy_data_resource

func check_charge_conditions():
	if not _is_initialized:
		charge_cast = owner_enemy.get_node_or_null("ChargeCast") as ShapeCast2D
		if not is_instance_valid(charge_cast):
			push_error("JuggernautBehavior could not find its required sibling node 'ChargeCast'. Disabling component.")
			set_process(false)
			set_physics_process(false)
			return
		_is_initialized = true

	if current_state != State.INACTIVE or not is_instance_valid(player_node):
		return
		
	var dist_to_player = owner_enemy.global_position.distance_to(player_node.global_position)
	
	if dist_to_player > enemy_data.charge_trigger_range:
		_charge_trigger_timer.stop()
		_change_state(State.TELEGRAPHING)
	elif dist_to_player > enemy_data.normal_chase_range:
		if _charge_trigger_timer.is_stopped():
			_charge_trigger_timer.wait_time = enemy_data.charge_trigger_timer
			_charge_trigger_timer.start()
	else:
		_charge_trigger_timer.stop()

func end_charge():
	if current_state == State.CHARGING:
		_change_state(State.STUNNED)

func end_behavior():
	if current_state != State.INACTIVE:
		_change_state(State.INACTIVE)

func _get_modified_speed() -> float:
	var base_move_speed = owner_enemy.speed
	
	if current_state == State.CHARGING:
		base_move_speed *= enemy_data.charge_speed_multiplier
	
	return owner_enemy.apply_status_effect_speed_modifiers(base_move_speed)

# --- Timer Callbacks ---
func _on_charge_trigger_timer_timeout():
	_change_state(State.TELEGRAPHING)

func _on_telegraph_timer_timeout():
	if current_state == State.TELEGRAPHING:
		_change_state(State.CHARGING)

func _on_stun_timer_timeout():
	if current_state == State.STUNNED:
		end_behavior()
