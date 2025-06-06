# MothGolem.gd
# Attached to the root CharacterBody2D of MothGolem.tscn
extends CharacterBody2D

class_name MothGolem

# --- Base Stats (from blueprint, modified by player stats) ---
var final_damage_amount: int = 14
var final_attack_interval: float = 1.0 
var final_movement_speed: float = 75.0 
var final_visual_scale: Vector2 = Vector2(1.0, 1.0)

# --- Behavior Config ---
const LEASH_DISTANCE: float = 150.0 
const ATTACK_REACH: float = 30.0    # Radius of the AttackRangeArea's CollisionShape2D
# STOPPING_DISTANCE_ENEMY should be less than ATTACK_REACH to ensure overlap
const STOPPING_DISTANCE_ENEMY: float = ATTACK_REACH * .1 # Stop a bit before the full reach
const STOPPING_DISTANCE_PLAYER: float = 40.0
const ENEMY_DETECTION_RADIUS: float = 200.0 

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("Visual") as AnimatedSprite2D
@onready var attack_range_area: Area2D = get_node_or_null("AttackRangeArea") as Area2D 
@onready var attack_timer: Timer = get_node_or_null("AttackTimer") as Timer 
@onready var leash_check_timer: Timer = get_node_or_null("LeashCheckTimer") as Timer 
@onready var navigation_agent: NavigationAgent2D = get_node_or_null("NavigationAgent") as NavigationAgent2D

# --- State & Targeting ---
var player_node: PlayerCharacter 
var current_target: Node2D = null
var prioritized_target: Node2D = null 
var is_returning_to_player: bool = false
var _enemies_in_attack_range: Array[Node2D] = [] 

enum GolemState { IDLE, SEEKING_ENEMY, ATTACKING, RETURNING_TO_PLAYER }
var current_state: GolemState = GolemState.IDLE

var _stats_have_been_set: bool = false 
var _received_stats_on_init : Dictionary
var _is_stagger_animation_playing: bool = false # To manage stagger animation state

func _ready():
	if not is_instance_valid(player_node):
		var parent = get_parent()
		if parent is PlayerCharacter: player_node = parent
		if not is_instance_valid(player_node):
			print("ERROR (MothGolem): Player node not set or found!")
			queue_free(); return

	if is_instance_valid(player_node) and player_node.has_signal("player_took_damage_from"):
		if not player_node.is_connected("player_took_damage_from", Callable(self, "on_player_damaged")):
			player_node.player_took_damage_from.connect(Callable(self, "on_player_damaged"))

	if not is_instance_valid(animated_sprite): print("ERROR (MothGolem): Visual node missing!")
	else: # Connect animation finished signal if sprite exists
		if not animated_sprite.is_connected("animation_finished", Callable(self, "_on_animated_sprite_animation_finished")):
			animated_sprite.animation_finished.connect(Callable(self, "_on_animated_sprite_animation_finished"))

	if not is_instance_valid(attack_range_area): print("ERROR (MothGolem): AttackRangeArea missing!")
	else:
		attack_range_area.body_entered.connect(_on_attack_range_area_body_entered)
		attack_range_area.body_exited.connect(_on_attack_range_area_body_exited)
		var attack_shape = attack_range_area.get_node_or_null("CollisionShape2D")
		if is_instance_valid(attack_shape) and attack_shape.shape is CircleShape2D:
			attack_shape.shape.radius = ATTACK_REACH 

	if not is_instance_valid(attack_timer): print("ERROR (MothGolem): AttackTimer missing!")
	else:
		attack_timer.timeout.connect(_on_attack_timer_timeout)

	if is_instance_valid(leash_check_timer): 
		leash_check_timer.timeout.connect(_check_leash_distance)
	
	if not is_instance_valid(navigation_agent):
		print("WARNING (MothGolem): NavigationAgent2D not found. Golem will use simple movement.")
	else:
		navigation_agent.path_desired_distance = 5.0 
		navigation_agent.target_desired_distance = STOPPING_DISTANCE_ENEMY 
		navigation_agent.avoidance_enabled = true # Consider enabling for better group movement

	if _stats_have_been_set: 
		_apply_all_stats(_received_stats_on_init)
		_update_state() 
	
	_play_animation("idle") 


func set_owner_stats(stats: Dictionary):
	_received_stats_on_init = stats.duplicate(true)
	_stats_have_been_set = true 

	if is_inside_tree(): 
		_apply_all_stats(_received_stats_on_init)
		_update_state()

func _apply_all_stats(stats: Dictionary):
	var base_w_damage = stats.get("damage", 14)
	var p_dmg_mult = stats.get("damage_multiplier", 1.0)
	var p_flat_dmg = stats.get("base_damage_bonus", 0.0)
	final_damage_amount = int(round(base_w_damage * p_dmg_mult + p_flat_dmg))

	var p_attack_speed_mult = stats.get("attack_speed_multiplier", 1.0)
	if p_attack_speed_mult <= 0: p_attack_speed_mult = 0.01
	var base_attack_interval = stats.get("attack_interval", 1.0) 
	final_attack_interval = base_attack_interval / p_attack_speed_mult
	if is_instance_valid(attack_timer):
		attack_timer.wait_time = final_attack_interval

	final_movement_speed = stats.get("movement_speed_pet", 75.0) 
	
	var weapon_inherent_scl_val = stats.get("inherent_visual_scale", Vector2(1.0, 1.0))
	var weapon_inherent_base_scale: Vector2
	if weapon_inherent_scl_val is Vector2: weapon_inherent_base_scale = weapon_inherent_scl_val
	elif weapon_inherent_scl_val is float: weapon_inherent_base_scale = Vector2(weapon_inherent_scl_val, weapon_inherent_scl_val)
	else: weapon_inherent_base_scale = Vector2(1.0, 1.0)
	
	var player_pet_size_mult = stats.get("pet_size_multiplier", 1.0) # Assuming this stat exists in PlayerStats
	final_visual_scale.x = weapon_inherent_base_scale.x * player_pet_size_mult
	final_visual_scale.y = weapon_inherent_base_scale.y * player_pet_size_mult
	
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_visual_scale
	var body_collision_shape = get_node_or_null("CollisionShape2D") 
	if is_instance_valid(body_collision_shape): body_collision_shape.scale = final_visual_scale


func _physics_process(delta: float):
	if not is_instance_valid(player_node): return

	var target_pos_for_movement: Vector2 = Vector2.ZERO
	var is_actively_moving_to_target = false

	if is_returning_to_player:
		target_pos_for_movement = player_node.global_position
		if global_position.distance_to(player_node.global_position) < STOPPING_DISTANCE_PLAYER: 
			is_returning_to_player = false
			velocity = Vector2.ZERO 
			_update_state() 
		else:
			_move_towards(target_pos_for_movement)
			is_actively_moving_to_target = true
	elif is_instance_valid(current_target):
		target_pos_for_movement = current_target.global_position
		is_actively_moving_to_target = true
		_move_towards(target_pos_for_movement)
		# Face target - assuming sprite faces LEFT by default
		if is_instance_valid(animated_sprite) and global_position.distance_to(target_pos_for_movement) > 1.0 : 
			var direction_to_target = (target_pos_for_movement - global_position).normalized()
			if direction_to_target.x > 0.01 : # Target is to the right of Golem
				animated_sprite.flip_h = true # Flip to face right
			elif direction_to_target.x < -0.01: # Target is to the left of Golem
				animated_sprite.flip_h = false # Default left-facing
	else: 
		_update_state() 
		velocity = Vector2.ZERO 
		if not _is_stagger_animation_playing: _play_animation("idle")
	
	if not is_actively_moving_to_target and not is_returning_to_player: 
		if global_position.distance_to(player_node.global_position) > LEASH_DISTANCE * 0.75: 
			is_returning_to_player = true
	
	if velocity.length_squared() > 0.01: 
		move_and_slide()
	else: 
		velocity = Vector2.ZERO


func _move_towards(target_pos: Vector2): 
	var desired_stopping_dist = STOPPING_DISTANCE_ENEMY
	if is_returning_to_player:
		desired_stopping_dist = STOPPING_DISTANCE_PLAYER

	if global_position.distance_to(target_pos) < desired_stopping_dist:
		velocity = Vector2.ZERO
		if not is_returning_to_player and is_instance_valid(current_target) and _enemies_in_attack_range.has(current_target):
			_try_start_attack_timer() 
		if not _is_stagger_animation_playing: _play_animation("idle")
		return

	if is_instance_valid(navigation_agent) and navigation_agent.target_position != target_pos : # Only update if target changed
		navigation_agent.set_target_position(target_pos)
		
	if is_instance_valid(navigation_agent) and navigation_agent.is_target_reachable():
		var next_path_pos = navigation_agent.get_next_path_position()
		velocity = (next_path_pos - global_position).normalized() * final_movement_speed
		# Check if navigation agent is "done" or very close to its final target point
		if navigation_agent.is_target_reached() or global_position.distance_to(target_pos) < desired_stopping_dist:
			velocity = Vector2.ZERO # Stop precisely
			if not is_returning_to_player and is_instance_valid(current_target) and _enemies_in_attack_range.has(current_target):
				_try_start_attack_timer()
	else: # Simple movement if no navigation agent or target not reachable
		velocity = (target_pos - global_position).normalized() * final_movement_speed
	
	if velocity.length_squared() > 0.01 and not _is_stagger_animation_playing: _play_animation("move")
	elif not _is_stagger_animation_playing: _play_animation("idle")


func _update_state():
	if is_returning_to_player: return 

	var old_target = current_target
	if is_instance_valid(prioritized_target) and _is_target_valid(prioritized_target):
		current_target = prioritized_target
		current_state = GolemState.SEEKING_ENEMY
	else:
		prioritized_target = null
		var nearest_enemy = _find_nearest_enemy_to_self()
		if is_instance_valid(nearest_enemy):
			current_target = nearest_enemy
			current_state = GolemState.SEEKING_ENEMY
		else:
			current_target = null
			current_state = GolemState.IDLE 
			if is_instance_valid(player_node) and global_position.distance_to(player_node.global_position) > LEASH_DISTANCE * 0.75: 
				is_returning_to_player = true
	
	if old_target != current_target:
		if is_instance_valid(attack_timer): attack_timer.stop()


func _find_nearest_enemy_to_self() -> Node2D:
	var closest_enemy: Node2D = null; var min_dist_sq = ENEMY_DETECTION_RADIUS * ENEMY_DETECTION_RADIUS 
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if _is_target_valid(enemy):
			var dist_sq = global_position.distance_squared_to(enemy.global_position)
			if dist_sq < min_dist_sq: min_dist_sq = dist_sq; closest_enemy = enemy
	return closest_enemy

func _is_target_valid(target_node: Node2D) -> bool:
	if not is_instance_valid(target_node) or not target_node.is_inside_tree(): return false
	if target_node.has_method("is_dead") and target_node.is_dead(): return false
	if target_node.has_method("get_current_health") and target_node.get_current_health() <= 0 : return false
	return true

func _check_leash_distance():
	if not is_returning_to_player and current_state != GolemState.ATTACKING and is_instance_valid(player_node):
		if global_position.distance_to(player_node.global_position) > LEASH_DISTANCE:
			is_returning_to_player = true; current_target = null; prioritized_target = null


func _on_attack_range_area_body_entered(body: Node2D):
	if body.is_in_group("enemies"):
		if not _enemies_in_attack_range.has(body): _enemies_in_attack_range.append(body)
		if body == current_target: _try_start_attack_timer()


func _on_attack_range_area_body_exited(body: Node2D):
	if body.is_in_group("enemies"):
		if _enemies_in_attack_range.has(body): _enemies_in_attack_range.erase(body)
		if body == current_target and is_instance_valid(attack_timer): 
			attack_timer.stop(); _update_state() 

func _try_start_attack_timer():
	if is_instance_valid(current_target) and _enemies_in_attack_range.has(current_target):
		if is_instance_valid(attack_timer) and attack_timer.is_stopped():
			attack_timer.start(); _perform_attack_action() 
		current_state = GolemState.ATTACKING
	elif current_state == GolemState.ATTACKING: 
		if is_instance_valid(attack_timer): attack_timer.stop()
		_update_state()


func _on_attack_timer_timeout():
	if is_instance_valid(current_target) and _enemies_in_attack_range.has(current_target) and _is_target_valid(current_target):
		_perform_attack_action()
	else: 
		if is_instance_valid(attack_timer): attack_timer.stop()
		_update_state() 


func _perform_attack_action():
	if not is_instance_valid(current_target): 
		if is_instance_valid(attack_timer): attack_timer.stop()
		_update_state(); return
	
	_play_animation("attack_stagger") 
	if current_target.has_method("take_damage"):
		current_target.take_damage(final_damage_amount)


func _play_animation(anim_name: String):
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation(anim_name):
			if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
				# For attack_stagger, we want it to play even if the current anim is idle/move
				if anim_name == "attack_stagger":
					_is_stagger_animation_playing = true
					animated_sprite.play(anim_name)
				elif not _is_stagger_animation_playing: # Don't interrupt stagger with move/idle
					animated_sprite.play(anim_name)


func _on_animated_sprite_animation_finished():
	# If the stagger animation finished, go back to idle or move
	if animated_sprite.animation == "attack_stagger":
		_is_stagger_animation_playing = false
		if velocity.length_squared() > 0.01:
			_play_animation("move")
		else:
			_play_animation("idle")


func on_player_damaged(attacker: Node2D): 
	if _is_target_valid(attacker):
		prioritized_target = attacker; current_target = attacker 
		is_returning_to_player = false; current_state = GolemState.SEEKING_ENEMY
