# BaseEnemy.gd
# This script defines the base behavior for all enemies, including movement, damage,
# health, death, and elite mechanics.
# VERSION 9.9: Fixed "flushing queries" error by deferring on-death component execution.

extends CharacterBody2D
class_name BaseEnemy

signal killed_by_attacker(attacker_node: Node, killed_enemy_node: Node)
signal attack_animation_completed

# --- AI State Machine ---
enum State { IDLE, CHASING, ATTACKING, DEATH }
var current_state: State = State.IDLE

# --- Core Enemy Stats ---
# ... (variables unchanged) ...
var max_health: float
var current_health: float
var contact_damage: float
var speed: float
var experience_to_drop: int
var armor: float
var is_dead_flag: bool = false
var behavior_tags: Array[StringName] = []
var _player_in_contact_area: bool = false
var _is_nav_ready: bool = false
var _is_data_initialized: bool = false
var _chase_start_requested: bool = false
var _behavior_override_active: bool = false

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var contact_damage_cooldown_timer: Timer = $ContactDamageTimer
@onready var damage_area: Area2D = $DamageArea
@onready var health_bar: ProgressBar = $HealthBar
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var elite_markers_container: Node2D = $EliteMarkersContainer
var status_icon_display: StatusIconDisplay 
var status_effect_component: StatusEffectComponent = null
var _attack_anim_timer: Timer
var _dynamic_nav_manager: DynamicNavigationManager
var _hit_and_run_component: HitAndRunBehavior
var _juggernaut_component: JuggernautBehavior
var _on_death_component: OnDeathBehaviorHandler
var _wave_movement_component: WaveMovementBehavior # New component reference
var _ranged_behavior_component: RangedBehavior
var _orbital_behavior_component: OrbitalBehavior

# --- Formation Logic ---
var horde_manager: HordeFormationManager
var assigned_slot_index: int = -1

# --- Elite Mechanic Nodes ---
# ... (variables unchanged) ...
var phaser_teleport_timer: Timer = null
var summoner_spawn_timer: Timer = null
var shaman_aura: Area2D = null
var shaman_heal_pulse_timer: Timer = null
var time_warper_aura: Area2D = null

# --- Visual & State Variables ---
# ... (variables unchanged) ...
const FLASH_COLOR: Color = Color(1.0, 0.3, 0.3, 1.0)
var _initial_sprite_modulate_from_scene: Color = Color(1.0, 1.0, 1.0, 1.0)
var _final_base_modulate_color: Color = Color(1.0, 1.0, 1.0, 1.0)
const SLOW_TINT_COLOR: Color = Color(0.7, 0.85, 1.0, 1.0)
const FLASH_DURATION: float = 0.2
const ELITE_ICON_SIZE: float = 24.0
var player_node: PlayerCharacter = null
var knockback_velocity: Vector2 = Vector2.ZERO
var external_forces: Vector2 = Vector2.ZERO
var damage_output_multiplier: float = 1.0
var _last_damage_instance_received: int = 0
var base_scene_root_scale: Vector2 = Vector2.ONE
var _sprite_initially_faces_left: bool = false
var is_elite: bool = false
var elite_type_tag: StringName = &""
var is_elite_immovable: bool = false
var _active_minions_by_summoner: Array[Node] = []
var enemy_data_resource: EnemyData
var game_node_ref: Node

# --- Lifecycle & Initialization ---

func _ready():
	base_scene_root_scale = self.scale
	
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0: player_node = players[0] as PlayerCharacter
	else: push_error("BaseEnemy: Player node not found in 'player_char_group'.")
	
	game_node_ref = get_tree().root.get_node_or_null("Game")
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("increment_active_enemy_count"):
		game_node_ref.increment_active_enemy_count()

	_get_status_effect_component_reference()
	
	# --- COMPONENT CHECKS ---
	_hit_and_run_component = get_node_or_null("HitAndRunBehavior")
	_juggernaut_component = get_node_or_null("JuggernautBehavior")
	_on_death_component = get_node_or_null("OnDeathBehaviorHandler")
	_wave_movement_component = get_node_or_null("WaveMovementBehavior")
	_ranged_behavior_component = get_node_or_null("RangedBehavior")
	_orbital_behavior_component = get_node_or_null("OrbitalBehavior")
	# --- END COMPONENT CHECKS ---

	status_icon_display = get_node_or_null("StatusIconDisplay") as StatusIconDisplay
	if is_instance_valid(status_icon_display):
		if status_icon_display.has_method("initialize"):
			status_icon_display.initialize(self)
		else:
			push_warning("BaseEnemy '", name, "': StatusIconDisplay is missing its initialize() method.")
	else:
		push_warning("BaseEnemy '", name, "': StatusIconDisplay node not found. Status icons will not appear.")
		
	horde_manager = get_tree().root.get_node_or_null("Game/HordeFormationManager")
	if not is_instance_valid(horde_manager):
		push_warning("BaseEnemy: HordeFormationManager not found. Enemies will clump.")

	_dynamic_nav_manager = get_tree().root.get_node_or_null("Game/DynamicNavigationManager")
	if is_instance_valid(_dynamic_nav_manager):
		if _dynamic_nav_manager.get("_initial_bake_done"):
			_is_nav_ready = true
		else:
			_dynamic_nav_manager.initial_bake_complete.connect(_on_initial_bake_complete)
	else:
		push_error("BaseEnemy: DynamicNavigationManager not found. Pathfinding will fail.")
	
	_attack_anim_timer = Timer.new()
	_attack_anim_timer.name = "AttackAnimTimer"
	_attack_anim_timer.one_shot = true
	add_child(_attack_anim_timer)
	_attack_anim_timer.timeout.connect(_on_attack_anim_timer_timeout)
	attack_animation_completed.connect(_on_attack_animation_completed)

	if is_instance_valid(contact_damage_cooldown_timer):
		contact_damage_cooldown_timer.timeout.connect(_on_contact_damage_timer_timeout)
	
	if is_instance_valid(damage_area):
		damage_area.body_entered.connect(_on_damage_area_body_entered)
		damage_area.body_exited.connect(_on_damage_area_body_exited)

	_change_state(State.IDLE)


func initialize_from_data(data: EnemyData):
	if not is_instance_valid(data):
		push_error("BaseEnemy '", name, "': Invalid EnemyData provided."); return

	enemy_data_resource = data
	max_health = float(data.base_health)
	contact_damage = float(data.base_contact_damage)
	speed = data.base_speed
	armor = float(data.base_armor)
	experience_to_drop = data.base_exp_drop
	_sprite_initially_faces_left = data.sprite_faces_left_by_default
	behavior_tags = data.behavior_tags.duplicate(true)
	
	current_health = max_health
	
	if is_instance_valid(animated_sprite):
		_final_base_modulate_color = _initial_sprite_modulate_from_scene * data.sprite_modulate_color
		if is_instance_valid(status_effect_component):
			on_status_effects_changed(self)
			
	update_health_bar()
	
	# --- Initialize Components (Simplified) ---
	if is_instance_valid(_hit_and_run_component):
		_hit_and_run_component.initialize(self)
	if is_instance_valid(_juggernaut_component):
		_juggernaut_component.initialize(self)
	if is_instance_valid(_on_death_component):
		_on_death_component.initialize(self)
	if is_instance_valid(_wave_movement_component):
		_wave_movement_component.initialize(self)
	if is_instance_valid(_ranged_behavior_component):
		_ranged_behavior_component.initialize(self)
	if is_instance_valid(_orbital_behavior_component):
		_orbital_behavior_component.initialize(self)
	# --- End Initialize ---
	
	_is_data_initialized = true
	
	call_deferred("_adjust_ui_positions")
	
	call_deferred("_try_start_chasing")

func _adjust_ui_positions():
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
		var frame_texture = animated_sprite.sprite_frames.get_frame_texture(&"walk", 0)
		if not frame_texture:
			frame_texture = animated_sprite.sprite_frames.get_frame_texture(&"idle", 0)
		if frame_texture and is_instance_valid(elite_markers_container):
			var sprite_height = frame_texture.get_height()
			var final_visual_scale_y = scale.y * animated_sprite.scale.y
			elite_markers_container.position.y = - (sprite_height / 2.0) * final_visual_scale_y - 5
			elite_markers_container.position.x = enemy_data_resource.elite_icon_offset.x
			elite_markers_container.position.y += enemy_data_resource.elite_icon_offset.y
	var status_icon_anchor = get_node_or_null("StatusIconAnchor")
	if is_instance_valid(status_icon_display) and is_instance_valid(status_icon_anchor):
		# The StatusIconDisplay is a child of BaseEnemy, so we set its local position
		# to match the local position of the anchor point.
		status_icon_display.position = status_icon_anchor.position

# ... (_on_initial_bake_complete, _try_start_chasing, _start_chasing are unchanged) ...
func _on_initial_bake_complete():
	if not is_instance_valid(self): return
	_is_nav_ready = true
	_try_start_chasing()

func _try_start_chasing():
	if _is_nav_ready and _is_data_initialized and not _chase_start_requested and not is_dead_flag:
		_chase_start_requested = true
		get_tree().create_timer(0, false).timeout.connect(_start_chasing)

func _start_chasing():
	if not is_dead_flag:
		_change_state(State.CHASING)

# --- State Machine & Physics ---

func _physics_process(delta: float):
	if is_dead_flag:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _handle_status_effect_interrupts():
		move_and_slide()
		return

	if _behavior_override_active:
		if abs(velocity.x) > 0.1:
			animated_sprite.flip_h = (velocity.x < 0) if not _sprite_initially_faces_left else (velocity.x > 0)
		if knockback_velocity.length_squared() > 0:
			velocity += knockback_velocity
		if external_forces.length_squared() > 0:
			velocity += external_forces
		move_and_slide()
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 300.0 * delta)
		external_forces = Vector2.ZERO
		return

	var move_speed = _get_modified_speed()
	velocity = Vector2.ZERO

	match current_state:
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, speed * delta * 2)
			_state_transition_logic()
		
		State.CHASING:
			# --- NEW: Delegate to RangedBehavior if applicable ---
			if is_instance_valid(_ranged_behavior_component) and behavior_tags.has(&"ranged"):
				velocity = _ranged_behavior_component.process_behavior(velocity, delta)
			elif is_instance_valid(_orbital_behavior_component) and behavior_tags.has(&"orbital"):
				velocity = _orbital_behavior_component.process_behavior(velocity, delta)
			# --- ELSE: Use existing melee/pathfinding logic ---
			else:
				if is_instance_valid(player_node) and is_instance_valid(navigation_agent):
					var target_position = player_node.global_position
					
					# Juggernauts don't use the formation
					if is_instance_valid(horde_manager) and assigned_slot_index != -1 and not behavior_tags.has(&"juggernaut"):
						target_position += horde_manager.get_slot_offset(assigned_slot_index)
					
					navigation_agent.target_position = target_position
					
					if not navigation_agent.is_navigation_finished():
						var next_pos = navigation_agent.get_next_path_position()
						var move_direction = global_position.direction_to(next_pos)
						velocity = move_direction * move_speed
						
				if is_instance_valid(_wave_movement_component) and behavior_tags.has(&"wave"):
					velocity = _wave_movement_component.get_modified_velocity(delta, velocity)

				# Check for Juggernaut charge conditions
				if is_instance_valid(_juggernaut_component) and behavior_tags.has(&"juggernaut"):
					_juggernaut_component.check_charge_conditions()
			
			_state_transition_logic()

		State.ATTACKING:
			velocity = Vector2.ZERO

	if abs(velocity.x) > 0.1:
		animated_sprite.flip_h = (velocity.x < 0) if not _sprite_initially_faces_left else (velocity.x > 0)

	if knockback_velocity.length_squared() > 0:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 300.0 * delta)

	if external_forces.length_squared() > 0:
		velocity += external_forces

	move_and_slide()
	external_forces = Vector2.ZERO


func _state_transition_logic():
	if not is_instance_valid(player_node):
		_change_state(State.IDLE)

func _change_state(new_state: State):
	if current_state == new_state: return
	
	if current_state == State.CHASING and new_state != State.CHASING:
		if is_instance_valid(horde_manager) and assigned_slot_index != -1:
			horde_manager.release_slot(self)
			assigned_slot_index = -1
	
	print_debug("Enemy '", name, "': Changing state from ", State.keys()[current_state], " to ", State.keys()[new_state])
	current_state = new_state
	
	match current_state:
		State.IDLE:
			_play_animation(&"idle")
		State.CHASING:
			_play_animation(&"walk")
			if is_instance_valid(horde_manager) and behavior_tags.has(&"uses_formation"):
				if assigned_slot_index == -1:
					horde_manager.enqueue_request(self)
		State.ATTACKING:
			_play_animation(&"attack")
			if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames.has_animation(&"attack"):
				var frame_count = animated_sprite.sprite_frames.get_frame_count(&"attack")
				var frame_rate = animated_sprite.sprite_frames.get_animation_speed(&"attack")
				if frame_rate > 0:
					_attack_anim_timer.wait_time = frame_count / frame_rate
					_attack_anim_timer.start()
		State.DEATH:
			_play_animation(&"death")

func _get_modified_speed() -> float:
	var base_move_speed = speed
	
	if behavior_tags.has(&"hit_and_run") and current_state == State.CHASING:
		base_move_speed *= enemy_data_resource.dive_speed_multiplier
	
	return apply_status_effect_speed_modifiers(base_move_speed)

# --- PUBLIC METHOD for components ---
func apply_status_effect_speed_modifiers(p_speed: float) -> float:
	var final_speed = p_speed
	if is_instance_valid(status_effect_component):
		var temp_flat_mod = status_effect_component.get_sum_of_flat_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
		var temp_percent_add_mod = status_effect_component.get_sum_of_percent_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
		var temp_multiplicative_mod = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MOVEMENT_SPEED])
		
		final_speed = (final_speed + temp_flat_mod) * (1.0 + temp_percent_add_mod) * temp_multiplicative_mod
	
	return maxf(0.0, final_speed)

func _on_attack_animation_completed():
	if behavior_tags.has(&"hit_and_run") and is_instance_valid(_hit_and_run_component):
		_hit_and_run_component.start_behavior()
	else:
		_change_state(State.CHASING)

# --- PUBLIC METHOD for components ---
func set_behavior_override(is_active: bool):
	_behavior_override_active = is_active

# ... (rest of the script is unchanged) ...
func _handle_status_effect_interrupts() -> bool:
	if is_instance_valid(status_effect_component):
		if status_effect_component.has_flag(&"is_stunned") or status_effect_component.has_flag(&"is_frozen") or status_effect_component.has_flag(&"is_rooted"):
			velocity = Vector2.ZERO
			_change_state(State.IDLE)
			return true
			
		if status_effect_component.has_flag(&"is_feared"):
			if is_instance_valid(player_node):
				var move_direction = (global_position - player_node.global_position).normalized()
				velocity = move_direction * _get_modified_speed()
				_change_state(State.CHASING)
				return true
	return false

func take_damage(damage_amount: float, attacker_node: Node = null, p_attack_stats: Dictionary = {}, p_weapon_tags: Array[StringName] = []):
	if current_health <= 0 or is_dead_flag: return
	
	var final_damage_taken = damage_amount
	var current_armor_stat = armor
	
	var armor_penetration_value = float(p_attack_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION], 0.0))
	var effective_armor = maxf(0.0, current_armor_stat - armor_penetration_value)
	final_damage_taken = maxf(1.0, final_damage_taken - effective_armor)
	
	if is_instance_valid(status_effect_component):
		var damage_taken_mod_add = status_effect_component.get_sum_of_percent_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_TAKEN_MULTIPLIER])
		var damage_taken_mod_mult = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_TAKEN_MULTIPLIER])
		final_damage_taken *= (1.0 + damage_taken_mod_add)
		final_damage_taken *= damage_taken_mod_mult
		
	_last_damage_instance_received = int(round(final_damage_taken))

	current_health -= final_damage_taken
	update_health_bar()
	_flash_on_hit()

	if is_instance_valid(status_effect_component) and status_effect_component.has_status_effect(&"soaked"):
		var has_relevant_tag = p_weapon_tags.has(&"physical") or p_weapon_tags.has(&"magical")
		if has_relevant_tag:
			if status_effect_component.can_trigger_catalytic_reaction():
				status_effect_component.consume_effect_and_apply_next(&"soaked")
				CombatEvents.emit_signal("catalytic_reaction_requested", self, p_weapon_tags)

	if current_health <= 0:
		_die(attacker_node)

func _die(killer_node: Node = null):
	if is_dead_flag: return
	is_dead_flag = true
	
	_change_state(State.DEATH)
	
	var on_death_effect_duration = 0.0
	if is_instance_valid(_on_death_component):
		on_death_effect_duration = _on_death_component.execute_on_death_effects()
	
	# If no long-running effect is happening, play the death animation now.
	if on_death_effect_duration == 0.0:
		_change_state(State.DEATH)
	
	if is_instance_valid(status_effect_component) and status_effect_component.has_status_effect(&"death_mark"):
		var effect_entry = status_effect_component.active_effects.get("death_mark")
		if effect_entry and effect_entry.has("weapon_stats"):
			CombatEvents.emit_signal("death_mark_triggered", global_position, effect_entry.weapon_stats)
	if is_instance_valid(phaser_teleport_timer): phaser_teleport_timer.queue_free()
	if is_instance_valid(summoner_spawn_timer): summoner_spawn_timer.queue_free()
	if is_instance_valid(shaman_aura): shaman_aura.queue_free()
	if is_instance_valid(shaman_heal_pulse_timer): shaman_heal_pulse_timer.queue_free()
	if is_instance_valid(time_warper_aura): time_warper_aura.queue_free()
	if is_instance_valid(status_effect_component) and status_effect_component.has_status_effect_by_unique_id("ft_lingering_cold_slow"):
		var weapon_stats = status_effect_component.get_stats_from_effect_source_by_unique_id("ft_lingering_cold_slow")
		var spread_radius = float(weapon_stats.get(&"lingering_cold_radius", 75.0))
		var slow_effect_data = load("res://DataResources/StatusEffects/slow_status.tres") as StatusEffectData
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = CircleShape2D.new(); query.shape.radius = spread_radius
		query.transform = Transform2D(0, global_position)
		query.collision_mask = self.collision_layer
		var results = space_state.intersect_shape(query)
		for result in results:
			var collider = result.collider
			if collider != self and collider is BaseEnemy and is_instance_valid(collider) and not collider.is_dead():
				if is_instance_valid(collider.status_effect_component):
					collider.status_effect_component.apply_effect(slow_effect_data, killer_node)
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
		game_node_ref.decrement_active_enemy_count()
	if is_instance_valid(status_effect_component) and (status_effect_component.has_flag(&"is_marked_for_transmutation") or status_effect_component.has_flag(&"is_soaked")):
		if is_instance_valid(player_node):
			var player_stats = player_node.get_node_or_null("PlayerStats")
			if is_instance_valid(player_stats):
				var base_chance = 0.25
				var luck = player_stats.get_final_stat(PlayerStatKeys.Keys.LUCK)
				var final_chance = base_chance + (luck * 0.05)
				if randf() < final_chance:
					call_deferred("_spawn_transmuted_orb")
	if is_instance_valid(status_effect_component):
		status_effect_component._on_owner_death()
	call_deferred("_finish_dying_and_drop_exp")
	emit_signal("killed_by_attacker", killer_node, self)
	set_physics_process(false)
	var col_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(col_shape): col_shape.call_deferred("set_disabled", true)
	if is_instance_valid(damage_area):
		var da_col_shape = damage_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(da_col_shape): da_col_shape.call_deferred("set_disabled", true)
		damage_area.call_deferred("set_monitoring", false)
	
	# --- SOLUTION: Use the calculated duration to delay destruction ---
	var death_anim_duration = 1.0 # Assuming death animation is 1 second
	var total_delay = death_anim_duration + on_death_effect_duration
	get_tree().create_timer(total_delay).timeout.connect(queue_free)
	# --- END SOLUTION ---

# NEW: Public function for OnDeathBehaviorHandler to trigger telegraph visuals
func play_on_death_telegraph(duration: float):
	if not is_instance_valid(animated_sprite): return
	
	animated_sprite.stop()
	
	var original_scale = animated_sprite.scale
	
	var tween = create_tween().set_loops(int(duration / 0.4))
	
	# --- SOLUTION: Corrected Godot 4 Tweening without 'chain()' or 'as_parallel()' ---
	# In Godot 4, you create sequences by calling tween_property one after another.
	# You create parallel animations by setting the final argument of the second
	# tween_property to true, or by calling .as_parallel() on the tweener itself.
	
	# First half of the pulse (0.2 seconds)
	tween.tween_property(animated_sprite, "modulate", Color(1.0, 0.5, 0.5), 0.2)
	tween.parallel().tween_property(animated_sprite, "scale", original_scale * 1.2, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Second half of the pulse (next 0.2 seconds)
	tween.tween_property(animated_sprite, "modulate", _final_base_modulate_color, 0.2)
	tween.parallel().tween_property(animated_sprite, "scale", original_scale, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# --- END SOLUTION ---

	tween.finished.connect(
		func():
			if is_instance_valid(self) and is_instance_valid(animated_sprite):
				animated_sprite.modulate = _final_base_modulate_color
				animated_sprite.scale = original_scale
				_change_state(State.DEATH)
	)

func _on_attack_anim_timer_timeout():
	emit_signal("attack_animation_completed")

func _on_damage_area_body_entered(body: Node2D):
	if body.is_in_group("player_char_group"):
		_player_in_contact_area = true
		if is_instance_valid(contact_damage_cooldown_timer) and contact_damage_cooldown_timer.is_stopped():
			call_deferred("_try_deal_contact_damage")

func _on_damage_area_body_exited(body: Node2D):
	if body.is_in_group("player_char_group"):
		_player_in_contact_area = false

func _on_contact_damage_timer_timeout():
	if _player_in_contact_area:
		call_deferred("_try_deal_contact_damage")
	
func _try_deal_contact_damage():
	if current_state == State.ATTACKING or is_dead_flag: return
	
	if is_instance_valid(status_effect_component):
		if status_effect_component.has_flag(&"is_stunned") or \
			status_effect_component.has_flag(&"is_frozen") or \
			status_effect_component.has_flag(&"is_feared"):
			return
	
	if is_instance_valid(player_node) and player_node.has_method("take_damage"):
		var final_contact_damage = contact_damage * damage_output_multiplier
		player_node.take_damage(final_contact_damage, self)
		
		_change_state(State.ATTACKING)
		contact_damage_cooldown_timer.start()

func _get_status_effect_component_reference():
	status_effect_component = get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if is_instance_valid(status_effect_component):
		if status_effect_component.has_signal("status_effects_changed"):
			if not status_effect_component.is_connected("status_effects_changed", Callable(self, "on_status_effects_changed")):
				status_effect_component.status_effects_changed.connect(Callable(self, "on_status_effects_changed"))
	else:
		push_error("BaseEnemy '", name, "': StatusEffectComponent node not found. Status effects will not work.")

func _play_animation(anim_name: StringName):
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation(anim_name):
			if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
				animated_sprite.play(anim_name)

# This function is now empty and can be removed.
func _handle_on_death_behaviors():
	pass

func _finish_dying_and_drop_exp(p_offset: Vector2 = Vector2.ZERO):
	if self.experience_to_drop <= 0: return
	var actual_exp_scene_path: String = ""
	if is_instance_valid(enemy_data_resource) and not enemy_data_resource.exp_drop_scene_path.is_empty():
		actual_exp_scene_path = enemy_data_resource.exp_drop_scene_path
	else: return
	if not actual_exp_scene_path.is_empty():
		var exp_scene_to_load = load(actual_exp_scene_path) as PackedScene
		if is_instance_valid(exp_scene_to_load):
			var exp_drop_instance = exp_scene_to_load.instantiate()
			var drops_container_node = get_tree().current_scene.get_node_or_null("DropsContainer")
			if is_instance_valid(drops_container_node): drops_container_node.add_child(exp_drop_instance)
			elif get_parent(): get_parent().add_child(exp_drop_instance)
			else: get_tree().current_scene.add_child(exp_drop_instance)
			exp_drop_instance.global_position = self.global_position + p_offset
			if exp_drop_instance.has_method("set_experience_value"):
				exp_drop_instance.set_experience_value(self.experience_to_drop, self.is_elite)
func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		if not is_dead_flag:
			if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
				game_node_ref.decrement_active_enemy_count()
		if is_instance_valid(phaser_teleport_timer): phaser_teleport_timer.queue_free()
		if is_instance_valid(summoner_spawn_timer): summoner_spawn_timer.queue_free()
		if is_instance_valid(shaman_aura): shaman_aura.queue_free()
		if is_instance_valid(shaman_heal_pulse_timer): shaman_heal_pulse_timer.queue_free()
		if is_instance_valid(time_warper_aura): time_warper_aura.queue_free()
func apply_knockback(direction: Vector2, force: float):
	if is_elite_immovable: return
	if is_instance_valid(status_effect_component):
		if status_effect_component.has_flag(&"is_stunned") or status_effect_component.has_flag(&"is_frozen"): return
	knockback_velocity = direction.normalized() * force
func apply_external_force(force: Vector2):
	external_forces += force
func _spawn_transmuted_orb():
	var offset = Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
	_finish_dying_and_drop_exp(offset)
func cull_self_and_report_threat():
	if is_dead_flag: return
	if is_instance_valid(game_node_ref) and is_instance_valid(enemy_data_resource):
		if game_node_ref.has_method("add_to_global_threat_pool"):
			game_node_ref.add_to_global_threat_pool(enemy_data_resource.threat_value_when_culled)
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
		game_node_ref.decrement_active_enemy_count()
	is_dead_flag = true
	queue_free()
func _flash_on_hit():
	if not is_instance_valid(animated_sprite): return
	var current_modulate_before_flash = animated_sprite.modulate
	animated_sprite.modulate = FLASH_COLOR
	var flash_timer = get_tree().create_timer(FLASH_DURATION, true, false, true)
	await flash_timer.timeout
	if is_instance_valid(self) and is_instance_valid(animated_sprite):
		animated_sprite.modulate = current_modulate_before_flash
func update_health_bar():
	if is_instance_valid(health_bar):
		health_bar.max_value = maxf(1.0, max_health)
		health_bar.value = current_health
		health_bar.visible = (current_health < max_health and current_health > 0)
func heal(heal_amount: float):
	if is_dead_flag: return
	current_health = minf(max_health, current_health + heal_amount)
	update_health_bar()
func make_elite(p_elite_type: StringName, p_elite_DDS_contribution: float = 0.0, p_base_data_for_elite: EnemyData = null):
	is_elite = true
	elite_type_tag = p_elite_type
	if is_instance_valid(self): name = name + "_Elite_" + str(elite_type_tag)
	
	# --- SOLUTION: Add Elite Icon ---
	if is_instance_valid(elite_markers_container) and is_instance_valid(game_node_ref):
		var icon_texture = game_node_ref.get_elite_icon(p_elite_type)
		if icon_texture:
			var icon_sprite = Sprite2D.new()
			icon_sprite.texture = icon_texture
			
			# Scale the icon to a consistent size
			var texture_size = icon_texture.get_size()
			var scale_multiplier = enemy_data_resource.elite_icon_scale_multiplier
			if texture_size.x > 0:
				icon_sprite.scale = Vector2.ONE * (ELITE_ICON_SIZE / texture_size.x) * scale_multiplier
			
			elite_markers_container.add_child(icon_sprite)
			
			# Arrange icons horizontally
			var num_icons = elite_markers_container.get_child_count()
			var total_width = 0.0
			for child in elite_markers_container.get_children():
				if child is Sprite2D:
					# Use the icon's actual scaled width for positioning
					total_width += child.texture.get_width() * child.scale.x
			
			var current_x = -total_width / 2.0
			
			for i in range(num_icons):
				var child = elite_markers_container.get_child(i) as Sprite2D
				var child_width = child.texture.get_width() * child.scale.x
				child.position.x = current_x + child_width / 2.0
				current_x += child_width
	# --- END SOLUTION ---

	var true_base_hp = max_health; var true_base_speed = speed
	var true_base_damage = contact_damage; var true_base_exp = experience_to_drop
	var true_base_armor = armor; var true_base_modulate = _initial_sprite_modulate_from_scene
	var true_base_scale = base_scene_root_scale
	var base_data_source = p_base_data_for_elite if is_instance_valid(p_base_data_for_elite) else enemy_data_resource
	if is_instance_valid(base_data_source):
		true_base_hp = float(base_data_source.base_health)
		true_base_speed = base_data_source.base_speed
		true_base_damage = float(base_data_source.base_contact_damage)
		true_base_exp = base_data_source.base_exp_drop
		true_base_armor = float(base_data_source.base_armor)
		if is_instance_valid(animated_sprite):
			true_base_modulate *= base_data_source.sprite_modulate_color
	var health_percent_increase: float = 4.00
	var damage_percent_increase: float = 0.20
	var speed_percent_increase: float = 0.0
	var additional_flat_armor: float = 0.0
	var exp_multiplier: float = 2.0 + (p_elite_DDS_contribution * 0.01)
	var scale_multiplier: float = 2.0
	var elite_tint_overlay = Color(1,1,1,1)
	match elite_type_tag:
		&"brute": damage_percent_increase += 0.30; elite_tint_overlay = Color(1.0, 0.8, 0.8, 1.0)
		&"tank": health_percent_increase += 4.00; additional_flat_armor += 5.0; elite_tint_overlay = Color(0.8, 1.0, 0.8, 1.0)
		&"swift": speed_percent_increase += 0.30; elite_tint_overlay = Color(0.8, 0.8, 1.0, 1.0)
		&"immovable": is_elite_immovable = true; elite_tint_overlay = Color(0.9, 0.9, 0.9, 1.0)
		&"phaser":
			elite_tint_overlay = Color(0.8, 0.5, 1.0, 1.0)
			phaser_teleport_timer = Timer.new(); phaser_teleport_timer.name = "PhaserTimer"
			phaser_teleport_timer.wait_time = base_data_source.phaser_cooldown
			phaser_teleport_timer.one_shot = false
			add_child(phaser_teleport_timer)
			phaser_teleport_timer.timeout.connect(_on_phaser_teleport_timer_timeout)
			phaser_teleport_timer.start()
		&"summoner":
			elite_tint_overlay = Color(1.0, 1.0, 0.5, 1.0)
			summoner_spawn_timer = Timer.new(); summoner_spawn_timer.name = "SummonerTimer"
			summoner_spawn_timer.wait_time = base_data_source.summoner_interval
			summoner_spawn_timer.one_shot = false
			add_child(summoner_spawn_timer)
			summoner_spawn_timer.timeout.connect(_on_summoner_spawn_timer_timeout)
			summoner_spawn_timer.start()
		&"shaman":
			elite_tint_overlay = Color(0.5, 1.0, 0.8, 1.0)
			shaman_aura = Area2D.new(); shaman_aura.name = "ShamanAura"; add_child(shaman_aura)
			var aura_shape = CircleShape2D.new(); aura_shape.radius = base_data_source.shaman_heal_radius
			var aura_col = CollisionShape2D.new(); aura_col.shape = aura_shape; shaman_aura.add_child(aura_col)
			shaman_aura.collision_layer = 0; shaman_aura.collision_mask = 8
			shaman_heal_pulse_timer = Timer.new(); shaman_heal_pulse_timer.name = "ShamanHealTimer"
			shaman_heal_pulse_timer.wait_time = base_data_source.shaman_heal_interval
			shaman_heal_pulse_timer.one_shot = false
			add_child(shaman_heal_pulse_timer)
			shaman_heal_pulse_timer.timeout.connect(_on_shaman_heal_pulse_timer_timeout)
			shaman_heal_pulse_timer.start()
		_: elite_tint_overlay = Color(1.0, 0.9, 0.7, 1.0)
	max_health = true_base_hp * (1.0 + health_percent_increase)
	current_health = max_health
	contact_damage = true_base_damage * (1.0 + damage_percent_increase)
	speed = true_base_speed * (1.0 + speed_percent_increase)
	armor = true_base_armor + additional_flat_armor
	self.scale = true_base_scale * scale_multiplier
	if is_instance_valid(animated_sprite):
		_final_base_modulate_color = _final_base_modulate_color * elite_tint_overlay
		if is_instance_valid(status_effect_component): on_status_effects_changed(self)
	update_health_bar()
func _on_phaser_teleport_timer_timeout():
	if is_dead_flag or not is_instance_valid(player_node): return
	var teleport_distance = enemy_data_resource.phaser_teleport_distance
	var direction_to_player = (global_position - global_position).normalized()
	var random_offset_angle = randf_range(-PI / 4, PI / 4)
	var new_position = player_node.global_position - direction_to_player.rotated(random_offset_angle) * teleport_distance
	global_position = new_position
func _on_summoner_spawn_timer_timeout():
	if is_dead_flag or not is_instance_valid(game_node_ref) or not is_instance_valid(enemy_data_resource): return
	var max_minions = enemy_data_resource.summoner_max_active_minions
	_active_minions_by_summoner = _active_minions_by_summoner.filter(func(m): return is_instance_valid(m))
	if _active_minions_by_summoner.size() >= max_minions: return
	var minion_id_to_spawn = enemy_data_resource.summoner_minion_ids.pick_random() if not enemy_data_resource.summoner_minion_ids.is_empty() else &"slime_green"
	var minion_enemy_data = game_node_ref.get_enemy_data_by_id(minion_id_to_spawn)
	if not is_instance_valid(minion_enemy_data): return
	var minion_scene_path = minion_enemy_data.scene_path
	var minion_scene = load(minion_scene_path) as PackedScene
	if is_instance_valid(minion_scene):
		var minion_instance = minion_scene.instantiate() as BaseEnemy
		minion_instance.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		if minion_instance.has_node("HealthBar"): minion_instance.get_node("HealthBar").visible = false
		var parent_container = get_parent() if is_instance_valid(get_parent()) else get_tree().current_scene
		if is_instance_valid(parent_container):
			parent_container.add_child(minion_instance)
			minion_instance.initialize_from_data(minion_enemy_data)
			_active_minions_by_summoner.append(minion_instance)
		else: minion_instance.queue_free()
func _on_shaman_heal_pulse_timer_timeout():
	if is_dead_flag or not is_instance_valid(shaman_aura) or not is_instance_valid(enemy_data_resource): return
	var heal_amount_percent = enemy_data_resource.shaman_heal_percent
	var overlapping_bodies = shaman_aura.get_overlapping_bodies()
	for body in overlapping_bodies:
		if body == self: continue
		if body is BaseEnemy and not body.is_dead_flag:
			var enemy_to_heal = body as BaseEnemy
			if enemy_to_heal.current_health < enemy_to_heal.max_health:
				var heal_value = int(ceilf(enemy_to_heal.max_health * heal_amount_percent))
				enemy_to_heal.current_health = minf(enemy_to_heal.max_health, enemy_to_heal.current_health + float(heal_value))
				enemy_to_heal.update_health_bar()
func on_status_effects_changed(_owner_node: Node):
	if not is_instance_valid(animated_sprite) or not is_instance_valid(status_effect_component): return
	var applied_tint: Color = _final_base_modulate_color
	if status_effect_component.has_flag(&"is_stunned"): applied_tint *= Color(0.5, 0.5, 0.5, 1.0)
	elif status_effect_component.has_flag(&"is_frozen"): applied_tint *= Color(0.7, 0.9, 1.0, 1.0)
	elif status_effect_component.has_flag(&"is_slowed"): applied_tint *= SLOW_TINT_COLOR
	var old_armor = armor
	var base_armor_val = 0.0
	if is_instance_valid(enemy_data_resource): base_armor_val = float(enemy_data_resource.base_armor)
	var flat_mod = status_effect_component.get_sum_of_flat_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR])
	var percent_add_mod = status_effect_component.get_sum_of_percent_add_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR])
	var mult_mod = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR])
	var new_armor = (base_armor_val + flat_mod) * (1.0 + percent_add_mod) * mult_mod
	armor = new_armor
	var final_damage_mult = 1.0
	var mult_from_status = status_effect_component.get_product_of_multiplicative_modifiers(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_OUTPUT_MULTIPLIER])
	final_damage_mult *= mult_from_status
	self.damage_output_multiplier = final_damage_mult
	set_physics_process(true)
func is_dead() -> bool: return is_dead_flag
func get_current_health() -> float: return current_health
func get_is_elite_immovable() -> bool: return is_elite_immovable
