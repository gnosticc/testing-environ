# BaseEnemy.gd
# Corrected take_damage to properly apply damage multipliers from StatusEffectComponent.
# Includes debug prints for verification.
class_name BaseEnemy
extends CharacterBody2D

signal killed_by_attacker(attacker_node: Node, killed_enemy_node: Node)

@export var max_health: int = 10 
@export var contact_damage: int = 1 
@export var speed: float = 30.0 
@export var experience_to_drop: int = 1 
@export var armor: int = 0 

var current_health: int
var is_dead_flag: bool = false

var _player_in_contact_area: bool = false
var _can_deal_contact_damage_again: bool = true # Retained for potential future logic, but not strictly needed for this timer fix

# --- Node References (Ensure these paths match your BaseEnemy.tscn structure) ---
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var contact_damage_cooldown_timer: Timer = get_node_or_null("ContactDamageTimer") as Timer
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar") as ProgressBar
@onready var separation_detector: Area2D = get_node_or_null("SeparationDetector") as Area2D
@onready var status_effect_component: StatusEffectComponent = get_node_or_null("StatusEffectComponent") as StatusEffectComponent

const FLASH_COLOR: Color = Color(1.0, 0.3, 0.3, 1.0)
var original_modulate_color: Color = Color(1.0, 1.0, 1.0, 1.0)
const FLASH_DURATION: float = 0.2

var player_node: PlayerCharacter = null
const SEPARATION_FORCE_STRENGTH: float = 50.0

var is_elite: bool = false
var elite_type_tag: StringName = &"" 
var base_scene_root_scale: Vector2 = Vector2.ONE 
var _sprite_initially_faces_left: bool = false
var is_elite_immovable: bool = false
var phaser_teleport_timer: Timer = null
var summoner_spawn_timer: Timer = null
var _active_minions_by_summoner: Array[Node] = [] 
var shaman_aura: Area2D = null
var shaman_heal_pulse_timer: Timer = null

var enemy_data_resource: EnemyData 
var game_node_ref 

enum EnemyAnimState { IDLE, WALK, ATTACK, DEATH }
var current_anim_state: EnemyAnimState = EnemyAnimState.IDLE
const MIN_SPEED_FOR_WALK_ANIM: float = 5.0
var _is_contact_attacking: bool = false


func _ready():
	base_scene_root_scale = self.scale
	var players = get_tree().get_nodes_in_group("player_char_group")
	if players.size() > 0: player_node = players[0] as PlayerCharacter
	var main_scene_root = get_tree().current_scene
	if main_scene_root and main_scene_root.has_method("increment_active_enemy_count"):
		game_node_ref = main_scene_root
	elif get_tree().root.get_child_count() > 0:
		var potential_game_node = get_tree().root.get_child(get_tree().root.get_child_count() - 1)
		if potential_game_node and potential_game_node.has_method("increment_active_enemy_count"):
			game_node_ref = potential_game_node
	if is_instance_valid(game_node_ref): game_node_ref.increment_active_enemy_count()
	if is_instance_valid(animated_sprite):
		original_modulate_color = animated_sprite.modulate
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("attack"):
			if not animated_sprite.is_connected("animation_finished", Callable(self, "_on_animated_sprite_animation_finished")):
				animated_sprite.animation_finished.connect(Callable(self, "_on_animated_sprite_animation_finished"))
	if not is_instance_valid(enemy_data_resource):
		current_health = max_health
		update_health_bar()
	if not is_instance_valid(contact_damage_cooldown_timer): print("ERROR (BaseEnemy '", name, "'): ContactDamageTimer node not found.")
	else:
		contact_damage_cooldown_timer.wait_time = 1.0; contact_damage_cooldown_timer.one_shot = false
		if not contact_damage_cooldown_timer.is_connected("timeout", Callable(self, "_on_contact_damage_timer_timeout")):
			contact_damage_cooldown_timer.timeout.connect(Callable(self, "_on_contact_damage_timer_timeout"))
	if not is_instance_valid(damage_area): print("ERROR (BaseEnemy '", name, "'): DamageArea node not found.")
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_damage_area_body_entered")):
			damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
		if not damage_area.is_connected("body_exited", Callable(self, "_on_damage_area_body_exited")):
			damage_area.body_exited.connect(Callable(self, "_on_damage_area_body_exited"))
	if is_instance_valid(status_effect_component) and status_effect_component.has_signal("status_effects_changed"):
		if not status_effect_component.is_connected("status_effects_changed", Callable(self, "on_status_effects_changed")):
			status_effect_component.status_effects_changed.connect(Callable(self, "on_status_effects_changed"))
	if speed > 0 and is_instance_valid(player_node): _update_animation_state()
	else: _set_animation_state(EnemyAnimState.IDLE)


func _physics_process(delta: float):
	if is_dead_flag or _is_contact_attacking: return
	var direction_to_player = Vector2.ZERO
	if is_instance_valid(player_node):
		direction_to_player = (player_node.global_position - global_position).normalized()
	var separation_vec = _calculate_separation_force()
	var final_direction = (direction_to_player + separation_vec).normalized()
	var current_move_speed = speed
	if is_instance_valid(status_effect_component):
		var speed_mult_add = status_effect_component.get_sum_of_additive_modifiers("movement_speed_multiplier")
		var speed_mult_direct = status_effect_component.get_product_of_multiplicative_modifiers("movement_speed_direct_multiplier")
		current_move_speed *= (1.0 + speed_mult_add); current_move_speed *= speed_mult_direct
		current_move_speed = max(0, current_move_speed)
	velocity = final_direction * current_move_speed
	if is_instance_valid(animated_sprite):
		if velocity.x != 0:
			if _sprite_initially_faces_left: animated_sprite.flip_h = (velocity.x > 0.01)
			else: animated_sprite.flip_h = (velocity.x < -0.01)
	move_and_slide()
	_update_animation_state()


func take_damage(amount: int, attacker_node: Node = null, p_attack_stats: Dictionary = {}):
	if current_health <= 0 or is_dead_flag: return
	
	var final_damage_taken = float(amount)
	var current_armor_stat = armor
	var armor_penetration_value = 0.0
	if p_attack_stats.has("armor_pierce"):
		armor_penetration_value = p_attack_stats.get("armor_pierce", 0.0)
		
	var effective_armor = max(0, current_armor_stat * (1.0 - armor_penetration_value))
	final_damage_taken = max(1.0, final_damage_taken - effective_armor)
	print_debug(" Damage after armor: ", final_damage_taken) # DEBUG
	
	if is_instance_valid(status_effect_component):
		var additive_damage_taken_mod = status_effect_component.get_sum_of_additive_modifiers("damage_taken_multiplier")
		if additive_damage_taken_mod != 0.0:
			print_debug(" Vulnerability mod value: ", additive_damage_taken_mod) # DEBUG
		final_damage_taken *= (1.0 + additive_damage_taken_mod)
	
	print_debug(name, " is taking ", final_damage_taken, " damage. Health was: ", current_health)
	current_health -= int(round(final_damage_taken))
	print_debug(" -> Health is now: ", current_health)
	update_health_bar()
	_flash_on_hit()
	
	if current_health <= 0:
		print_debug(" -> Health <= 0. Calling _die().")
		_die(attacker_node)

func initialize_from_data(data: EnemyData):
	if not data is EnemyData:
		print("ERROR (BaseEnemy '", name, "'): Invalid EnemyData provided. Using scene defaults.")
		current_health = max_health; update_health_bar(); return
	enemy_data_resource = data
	max_health = data.base_health; contact_damage = data.base_contact_damage
	speed = data.base_speed; armor = data.base_armor
	experience_to_drop = data.base_exp_drop
	_sprite_initially_faces_left = data.sprite_faces_left_by_default
	current_health = max_health
	if is_instance_valid(animated_sprite):
		animated_sprite.modulate = data.sprite_modulate_color
		original_modulate_color = animated_sprite.modulate
	update_health_bar(); _update_animation_state()

func _update_animation_state():
	if is_dead_flag or _is_contact_attacking or current_anim_state == EnemyAnimState.ATTACK: return
	if velocity.length_squared() > MIN_SPEED_FOR_WALK_ANIM * MIN_SPEED_FOR_WALK_ANIM:
		_set_animation_state(EnemyAnimState.WALK)
	else: _set_animation_state(EnemyAnimState.IDLE)

func _set_animation_state(new_state: EnemyAnimState):
	if new_state == current_anim_state and is_instance_valid(animated_sprite) and animated_sprite.is_playing():
		if new_state == EnemyAnimState.IDLE and animated_sprite.animation == "idle" and not animated_sprite.is_playing(): pass
		else: return
	current_anim_state = new_state
	match current_anim_state:
		EnemyAnimState.IDLE: _play_animation("idle")
		EnemyAnimState.WALK: _play_animation("walk")
		EnemyAnimState.ATTACK: _play_animation("attack")
		EnemyAnimState.DEATH: _play_animation("death")

func _play_animation(anim_name: StringName):
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation(anim_name):
			if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
				animated_sprite.play(anim_name)

func _on_animated_sprite_animation_finished():
	if _is_contact_attacking and animated_sprite.animation == "attack":
		_is_contact_attacking = false; _update_animation_state()
	elif current_anim_state == EnemyAnimState.DEATH and animated_sprite.animation == "death": pass

func _die(killer_node: Node = null):
	if is_dead_flag: return
	print_debug(name, " is entering _die(). Setting is_dead_flag = true.")
	is_dead_flag = true
	_is_contact_attacking = false; _set_animation_state(EnemyAnimState.DEATH)
	if is_instance_valid(phaser_teleport_timer): phaser_teleport_timer.stop()
	if is_instance_valid(summoner_spawn_timer): summoner_spawn_timer.stop()
	if is_instance_valid(shaman_aura): shaman_aura.monitoring = false; shaman_aura.monitorable = false
	if is_instance_valid(shaman_heal_pulse_timer): shaman_heal_pulse_timer.stop()
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
		game_node_ref.decrement_active_enemy_count()
	emit_signal("killed_by_attacker", killer_node, self); set_physics_process(false)
	if is_instance_valid(contact_damage_cooldown_timer): contact_damage_cooldown_timer.stop()
	var col_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(col_shape): col_shape.call_deferred("set_disabled", true)
	if is_instance_valid(damage_area):
		var da_col_shape = damage_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(da_col_shape): da_col_shape.call_deferred("set_disabled", true)
		damage_area.call_deferred("set_monitoring", false)
	if is_instance_valid(separation_detector):
		var sd_col_shape = separation_detector.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(sd_col_shape): sd_col_shape.call_deferred("set_disabled", true)
		separation_detector.call_deferred("set_monitoring", false)
	var death_anim_duration = 0.0
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("death"):
		var frame_count = animated_sprite.sprite_frames.get_frame_count("death")
		var anim_speed = animated_sprite.sprite_frames.get_animation_speed("death")
		if anim_speed > 0: death_anim_duration = float(frame_count) / anim_speed
		if animated_sprite.sprite_frames.get_animation_loop("death"): death_anim_duration = 0.5
	emit_signal("killed_by_attacker", killer_node, self)
	set_physics_process(false)
	var death_timer = get_tree().create_timer(1.0) # Example duration
	death_timer.timeout.connect(Callable(self, "_finish_dying_and_drop_exp"))
	

func _finish_dying_and_drop_exp():
	var final_exp_to_give = self.experience_to_drop; var actual_exp_scene_path = ""
	if is_instance_valid(enemy_data_resource) and not enemy_data_resource.exp_drop_scene_path.is_empty():
		actual_exp_scene_path = enemy_data_resource.exp_drop_scene_path
	else: print_debug("BaseEnemy '", name, "': Missing exp_drop_scene_path. Skipping EXP drop.")
	if not actual_exp_scene_path.is_empty():
		var exp_scene_to_load = load(actual_exp_scene_path) as PackedScene
		if exp_scene_to_load:
			var exp_drop_instance = exp_scene_to_load.instantiate()
			var drops_container_node = get_tree().current_scene.get_node_or_null("DropsContainer")
			if is_instance_valid(drops_container_node): drops_container_node.add_child(exp_drop_instance)
			elif get_parent(): get_parent().add_child(exp_drop_instance)
			else: get_tree().current_scene.add_child(exp_drop_instance)
			exp_drop_instance.global_position = global_position
			if exp_drop_instance.has_method("set_experience_value"):
				exp_drop_instance.set_experience_value(final_exp_to_give, self.is_elite)
			elif "experience_value" in exp_drop_instance:
				exp_drop_instance.experience_value = final_exp_to_give
		else: print("ERROR (BaseEnemy): Could not load EXP drop scene: ", actual_exp_scene_path)
	call_deferred("queue_free")

func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		if not is_dead_flag:
			if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
				game_node_ref.decrement_active_enemy_count()
		if is_instance_valid(phaser_teleport_timer): phaser_teleport_timer.queue_free()
		if is_instance_valid(summoner_spawn_timer): summoner_spawn_timer.queue_free()
		if is_instance_valid(shaman_aura): shaman_aura.queue_free()
		if is_instance_valid(shaman_heal_pulse_timer): shaman_heal_pulse_timer.queue_free()

func cull_self_and_report_threat():
	if is_dead_flag: return
	if is_instance_valid(game_node_ref) and is_instance_valid(enemy_data_resource):
		if game_node_ref.has_method("add_to_global_threat_pool"):
			game_node_ref.add_to_global_threat_pool(enemy_data_resource.threat_value_when_culled)
	if is_instance_valid(game_node_ref) and game_node_ref.has_method("decrement_active_enemy_count"):
		game_node_ref.decrement_active_enemy_count()
	is_dead_flag = true; queue_free()

func _flash_on_hit():
	if not is_instance_valid(animated_sprite): return
	animated_sprite.modulate = FLASH_COLOR
	var flash_timer = get_tree().create_timer(FLASH_DURATION, true, false, true)
	await flash_timer.timeout
	if is_instance_valid(self) and is_instance_valid(animated_sprite):
		animated_sprite.modulate = original_modulate_color

func update_health_bar():
	if is_instance_valid(health_bar):
		health_bar.max_value = max(1, max_health); health_bar.value = current_health
		health_bar.visible = (current_health < max_health and current_health > 0)

func _on_contact_damage_timer_timeout():
	print_debug(name, ": Contact damage timer timeout. Player in area: ", _player_in_contact_area, ", Dead: ", is_dead_flag)
	if is_dead_flag: return
	if _player_in_contact_area:
		_try_deal_contact_damage()
	else:
		if is_instance_valid(contact_damage_cooldown_timer):
			contact_damage_cooldown_timer.stop()


func _on_damage_area_body_entered(body: Node2D):
	if body.is_in_group("player_char_group"):
		print_debug(name, ": Player entered damage area. Initial hit attempt.")
		_player_in_contact_area = true; _try_deal_contact_damage()
		if is_instance_valid(contact_damage_cooldown_timer) and contact_damage_cooldown_timer.is_stopped():
			contact_damage_cooldown_timer.start()

func _on_damage_area_body_exited(body: Node2D):
	if body.is_in_group("player_char_group"):
		print_debug(name, ": Player exited damage area. Stopping timer.")
		_player_in_contact_area = false
		if is_instance_valid(contact_damage_cooldown_timer):
			contact_damage_cooldown_timer.stop()


func _try_deal_contact_damage():
	if not _player_in_contact_area or is_dead_flag or _is_contact_attacking:
		print_debug(name, ": _try_deal_contact_damage aborted. Player in area: ", _player_in_contact_area, ", Dead: ", is_dead_flag, ", Attacking: ", _is_contact_attacking)
		return
	if is_instance_valid(player_node) and player_node.has_method("take_damage"):
		print_debug(name, ": Dealing contact damage to player for ", contact_damage, ".")
		player_node.take_damage(contact_damage, self); _can_deal_contact_damage_again = false
		if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("attack"):
			_is_contact_attacking = true; _set_animation_state(EnemyAnimState.ATTACK)
		if is_instance_valid(contact_damage_cooldown_timer): contact_damage_cooldown_timer.start()

func _calculate_separation_force() -> Vector2:
	var separation_vector = Vector2.ZERO
	if not is_instance_valid(separation_detector): return separation_vector
	var neighbors = separation_detector.get_overlapping_bodies()
	if neighbors.size() > 0:
		for neighbor in neighbors:
			if neighbor != self and neighbor.is_in_group("enemies"):
				var away_from_neighbor = (global_position - neighbor.global_position).normalized()
				separation_vector += away_from_neighbor
		if separation_vector.length_squared() > 0.0001: separation_vector = separation_vector.normalized()
	return separation_vector * SEPARATION_FORCE_STRENGTH

func make_elite(p_elite_type: StringName, p_elite_DDS_contribution: float = 0.0, p_base_data_for_elite: EnemyData = null):
	is_elite = true
	elite_type_tag = p_elite_type
	if is_instance_valid(self):
		name = name + "_Elite_" + str(elite_type_tag)

	var true_base_hp = max_health
	var true_base_speed = speed
	var true_base_damage = contact_damage
	var true_base_exp = experience_to_drop
	var true_base_armor = armor
	var true_base_modulate = original_modulate_color
	var true_base_scale = base_scene_root_scale

	if is_instance_valid(p_base_data_for_elite):
		true_base_hp = p_base_data_for_elite.base_health
		true_base_speed = p_base_data_for_elite.base_speed
		true_base_damage = p_base_data_for_elite.base_contact_damage
		true_base_exp = p_base_data_for_elite.base_exp_drop
		true_base_armor = p_base_data_for_elite.base_armor
		if is_instance_valid(animated_sprite):
			true_base_modulate = p_base_data_for_elite.sprite_modulate_color
	elif is_instance_valid(enemy_data_resource):
		true_base_hp = enemy_data_resource.base_health
		true_base_speed = enemy_data_resource.base_speed
		true_base_damage = enemy_data_resource.base_contact_damage
		true_base_exp = enemy_data_resource.base_exp_drop
		true_base_armor = enemy_data_resource.base_armor
		if is_instance_valid(animated_sprite):
			true_base_modulate = enemy_data_resource.sprite_modulate_color
	
	var health_percent_increase: float = 4.00
	var damage_percent_increase: float = 0.20
	var speed_percent_increase: float = 0.0
	var additional_flat_armor: int = 0
	
	var exp_multiplier: float = 2.0 + (p_elite_DDS_contribution * 0.01)
	var scale_multiplier: float = 2.0

	if is_instance_valid(animated_sprite):
		animated_sprite.modulate = true_base_modulate

	var elite_tint_overlay = Color(1,1,1,1)

	match elite_type_tag:
		&"brute":
			damage_percent_increase += 0.30
			elite_tint_overlay = Color(1.0, 0.8, 0.8, 1.0)
		&"tank":
			health_percent_increase += 4.00; additional_flat_armor += 5
			elite_tint_overlay = Color(0.8, 1.0, 0.8, 1.0)
		&"swift":
			speed_percent_increase += 0.30
			elite_tint_overlay = Color(0.8, 0.8, 1.0, 1.0)
		&"immovable":
			is_elite_immovable = true
			elite_tint_overlay = Color(0.9, 0.9, 0.9, 1.0)
		&"phaser":
			elite_tint_overlay = Color(0.8, 0.5, 1.0, 1.0)
		&"summoner":
			elite_tint_overlay = Color(1.0, 1.0, 0.5, 1.0)
		&"shaman":
			elite_tint_overlay = Color(0.5, 1.0, 0.8, 1.0)
		&"time_warper":
			elite_tint_overlay = Color(0.6, 0.4, 0.8, 1.0)
		_:
			elite_tint_overlay = Color(1.0, 0.9, 0.7, 1.0)

	max_health = int(true_base_hp * (1.0 + health_percent_increase))
	current_health = max_health
	contact_damage = int(true_base_damage * (1.0 + damage_percent_increase))
	speed = true_base_speed * (1.0 + speed_percent_increase)
	armor = true_base_armor + additional_flat_armor
	experience_to_drop = int(true_base_exp * exp_multiplier)
	
	if is_instance_valid(animated_sprite):
		animated_sprite.scale = true_base_scale * scale_multiplier
		animated_sprite.modulate *= elite_tint_overlay
		original_modulate_color = animated_sprite.modulate
		base_scene_root_scale = animated_sprite.scale
	
	update_health_bar()

func on_status_effects_changed(_owner_node: Node): pass
func is_dead() -> bool: return is_dead_flag
func get_current_health() -> int: return current_health
func get_is_elite_immovable() -> bool: return is_elite_immovable
