# MothGolem.gd (Signal Disconnect Fix)
# This script controls the behavior of the Moth Golem summon.
# FIX: The _notification function now disconnects from the correct player signal
# ('player_took_damage_from') upon deletion, preventing a crash.

class_name MothGolem
extends CharacterBody2D

# The enum defines all possible states for the golem.
enum State { IDLE, FOLLOWING_PLAYER, CHASING_TARGET, ATTACKING, GUARDIAN_READY, PRIMAL_FURY }
var current_state: State = State.IDLE

@export var pacing_distance_buffer: float = 20.0
# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_cooldown_timer: Timer = $AttackCooldownTimer
@onready var melee_attack_area: Area2D = $MeleeAttackArea
@onready var proc_check_timer: Timer = $ProcCheckTimer
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent

# --- Scene Preloads ---
const CRUSHING_BLOW_SCENE = preload("res://Scenes/Weapons/Summons/GolemSmashEffect.tscn")
const PROTECTIVE_DUST_SCENE = preload("res://Scenes/Weapons/Summons/ProtectiveDustCloud.tscn")
const CAUSTIC_AURA_SCENE = preload("res://Scenes/Weapons/Summons/CausticAura.tscn")
const PRIMAL_FURY_BUFF = preload("res://DataResources/StatusEffects/primal_fury_buff.tres")

# --- References ---
var owner_player: PlayerCharacter
var _owner_player_stats: PlayerStats
var target_enemy: BaseEnemy
var specific_weapon_stats: Dictionary
var _last_attacker: BaseEnemy

# --- Core Stats & State ---
var movement_speed: float = 100.0
var player_detection_range: float = 150.0
var follow_distance: float = 150.0 # NEW: Added class variable for tethering
var attack_range: float = 30.0
var attack_cooldown: float = 1.8
var damage: int = 20
var golem_crit_chance: float = 0.0
var base_scale: float = 1.0
var _guardian_spirit_buff_active: bool = false
var _caustic_aura_instance: Node2D
var _fury_tween: Tween

# --- Signals ---
signal instances_spawned(summon_id: StringName, spawned_instances: Array[Node2D])

# --- Initialization & Cleanup ---

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_owner_player_stats) and _owner_player_stats.is_connected("stats_recalculated", _on_player_stats_recalculated):
			_owner_player_stats.stats_recalculated.disconnect(_on_player_stats_recalculated)
		# FIX: Disconnect from the correct signal name.
		if is_instance_valid(owner_player) and owner_player.is_connected("player_took_damage_from", on_player_damaged):
			owner_player.player_took_damage_from.disconnect(on_player_damaged)
		if is_instance_valid(_caustic_aura_instance):
			_caustic_aura_instance.queue_free()
		if is_instance_valid(_fury_tween):
			_fury_tween.kill()

func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, _start_angle: float):
	owner_player = p_owner
	_owner_player_stats = p_owner.player_stats
	specific_weapon_stats = p_stats

	if not is_instance_valid(owner_player):
		queue_free()
		return

	if owner_player.has_signal("player_took_damage_from"):
		owner_player.player_took_damage_from.connect(on_player_damaged)
	else:
		push_warning("MothGolem WARNING: PlayerCharacter is missing the 'player_took_damage_from' signal.")

	animated_sprite.animation_finished.connect(_on_attack_animation_finished)
	status_effect_component.status_effects_changed.connect(_on_status_effects_changed)
	proc_check_timer.timeout.connect(_on_proc_check_timeout)
	melee_attack_area.body_entered.connect(_on_melee_attack_area_hit)
	
	if _owner_player_stats and not _owner_player_stats.is_connected("stats_recalculated", _on_player_stats_recalculated):
		_owner_player_stats.stats_recalculated.connect(_on_player_stats_recalculated)

	var area_collision_shape = melee_attack_area.get_node("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(area_collision_shape):
		area_collision_shape.disabled = true

	update_stats()
	proc_check_timer.start()
	
	var weapon_id = specific_weapon_stats.get(&"weapon_id", &"conjurer_moth_golem")
	emit_signal("instances_spawned", weapon_id, [self])
	
	_change_state(State.IDLE)


func update_stats(new_stats: Dictionary = {}):
	if not new_stats.is_empty():
		specific_weapon_stats = new_stats.duplicate(true)
	if not is_instance_valid(_owner_player_stats): return

	movement_speed = float(specific_weapon_stats.get(&"movement_speed", 100.0))
	player_detection_range = float(specific_weapon_stats.get(&"player_detection_range", 150.0))
	# FIX: Correctly read the follow_distance from the stats.
	follow_distance = float(specific_weapon_stats.get(&"follow_distance", 150.0))
	attack_range = float(specific_weapon_stats.get(&"attack_range", 30.0))
	attack_cooldown = float(specific_weapon_stats.get(&"attack_cooldown", 1.8))
	golem_crit_chance = float(specific_weapon_stats.get(&"crit_chance", 0.0))
	var base_visual_scale = float(specific_weapon_stats.get(&"base_visual_scale", 1.0))
	var scale_increase_per_level = float(specific_weapon_stats.get(&"scale_increase_per_level", 0.0))
	var weapon_level = int(specific_weapon_stats.get("weapon_level", 1))

	var bonus_scale = float(weapon_level - 1) * scale_increase_per_level
	base_scale = base_visual_scale + bonus_scale
	
	var final_attack_area_scale = float(specific_weapon_stats.get(&"attack_area_scale", 1.0))
	
	if is_instance_valid(status_effect_component):
		var fury_area_mult = status_effect_component.get_product_of_multiplicative_modifiers(&"attack_area_scale")
		final_attack_area_scale *= fury_area_mult

	melee_attack_area.scale = Vector2.ONE * final_attack_area_scale * base_scale
	animated_sprite.scale = Vector2.ONE * base_scale
	
	var weapon_damage_percent = float(specific_weapon_stats.get(&"weapon_damage_percentage", 1.8))
	var weapon_tags: Array[StringName] = specific_weapon_stats.get(&"tags", [])
	var summon_damage_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER)
	var final_damage_percent = weapon_damage_percent * summon_damage_mult

	if is_instance_valid(status_effect_component):
		var fury_damage_mult = status_effect_component.get_product_of_multiplicative_modifiers(&"weapon_damage_percentage")
		final_damage_percent *= fury_damage_mult
	
	var base_damage = _owner_player_stats.get_calculated_base_damage(final_damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	damage = int(round(maxf(1.0, final_damage)))
	
	var final_cooldown = attack_cooldown
	
	if is_instance_valid(status_effect_component):
		var fury_cooldown_mult = status_effect_component.get_product_of_multiplicative_modifiers(&"attack_cooldown")
		final_cooldown *= fury_cooldown_mult
		
	final_cooldown /= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	attack_cooldown_timer.wait_time = maxf(0.1, final_cooldown)
	
	var has_caustic_aura = specific_weapon_stats.get(&"has_caustic_aura", false)
	if has_caustic_aura and not is_instance_valid(_caustic_aura_instance):
		_caustic_aura_instance = CAUSTIC_AURA_SCENE.instantiate()
		get_tree().current_scene.add_child(_caustic_aura_instance)
	elif not has_caustic_aura and is_instance_valid(_caustic_aura_instance):
		_caustic_aura_instance.queue_free()
		_caustic_aura_instance = null
	
	if is_instance_valid(_caustic_aura_instance):
		_caustic_aura_instance.initialize(self, specific_weapon_stats, self.damage)
	
	_update_visual_state()


# --- State Machine & AI Logic ---

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free(); return

	if is_instance_valid(_caustic_aura_instance):
		_caustic_aura_instance.global_position = self.global_position

	var next_state = _get_next_state()
	_change_state(next_state)

	match current_state:
		State.IDLE, State.GUARDIAN_READY, State.PRIMAL_FURY:
			velocity = velocity.move_toward(Vector2.ZERO, movement_speed * delta * 5)
		State.FOLLOWING_PLAYER:
			velocity = (owner_player.global_position - global_position).normalized() * movement_speed
		State.CHASING_TARGET:
			if _is_target_valid(target_enemy):
				var distance_to_target = global_position.distance_to(target_enemy.global_position)
				var pacing_range = attack_range + pacing_distance_buffer
				
				if distance_to_target > pacing_range:
					# Rush the target directly when far away.
					velocity = (target_enemy.global_position - global_position).normalized() * movement_speed
				else:
					# When close, pace the enemy by matching its velocity and adding a nudge.
					var steering_force = (target_enemy.global_position - global_position).normalized() * (movement_speed * 0.5)
					var desired_velocity = target_enemy.velocity + steering_force
					
					# Clamp the golem's speed to its maximum.
					if desired_velocity.length() > movement_speed:
						desired_velocity = desired_velocity.normalized() * movement_speed
						
					velocity = velocity.lerp(desired_velocity, delta * 5.0)
			else:
				velocity = Vector2.ZERO
		State.ATTACKING:
			velocity = Vector2.ZERO

	if velocity.length_squared() > 1:
		animated_sprite.flip_h = velocity.x < 0
	move_and_slide()


func _get_next_state() -> State:
	if current_state == State.ATTACKING:
		return State.ATTACKING

	# FIX: If the golem is currently returning to the player, it must finish before doing anything else.
	if current_state == State.FOLLOWING_PLAYER:
		# Check if it has arrived back at the player.
		if global_position.distance_squared_to(owner_player.global_position) <= 25 * 25:
			# It has arrived. Now it can look for a target.
			pass # Allow the rest of the function to execute.
		else:
			# Still too far, must continue following.
			return State.FOLLOWING_PLAYER

	# If not currently returning, check if it SHOULD be returning.
	if global_position.distance_squared_to(owner_player.global_position) > follow_distance * follow_distance:
		return State.FOLLOWING_PLAYER

	_find_new_target()
	
	if _is_target_valid(target_enemy):
		var is_in_range = global_position.distance_squared_to(target_enemy.global_position) <= attack_range * attack_range
		
		if is_in_range and attack_cooldown_timer.is_stopped():
			return State.ATTACKING
		else:
			return State.CHASING_TARGET
	else:
		if status_effect_component.has_status_effect(&"primal_fury_buff"):
			return State.PRIMAL_FURY
		elif _guardian_spirit_buff_active:
			return State.GUARDIAN_READY
		else:
			return State.IDLE

func _change_state(new_state: State):
	if current_state == new_state: return
	current_state = new_state
	match new_state:
		State.IDLE: animated_sprite.play("idle")
		State.FOLLOWING_PLAYER, State.CHASING_TARGET: animated_sprite.play("walk")
		State.GUARDIAN_READY: animated_sprite.play("guardian")
		State.PRIMAL_FURY: animated_sprite.play("fury")
		State.ATTACKING:
			animated_sprite.play("attack")
			get_node("MeleeAttackArea/CollisionShape2D").disabled = false

func _find_new_target():
	# FIX: Check if _last_attacker is still a valid instance before using it.
	if is_instance_valid(_last_attacker) and _is_target_valid(_last_attacker):
		target_enemy = _last_attacker
		return
		
	_last_attacker = null
	target_enemy = null
	var enemies = get_tree().get_nodes_in_group("enemies")
	var best_target_distance_sq = player_detection_range * player_detection_range
	for enemy in enemies:
		if _is_target_valid(enemy):
			var dist_from_golem_sq = global_position.distance_squared_to(enemy.global_position)
			if dist_from_golem_sq < best_target_distance_sq:
				best_target_distance_sq = dist_from_golem_sq
				target_enemy = enemy as BaseEnemy

# --- Event Handlers & Attack Logic ---

func _on_player_stats_recalculated(_new_health: float, _new_speed: float):
	update_stats()

func _on_attack_animation_finished():
	if animated_sprite.animation == "attack":
		get_node("MeleeAttackArea/CollisionShape2D").disabled = true
		attack_cooldown_timer.start()
		
		# FIX: Add a guard clause to check if target_enemy is still valid before accessing it.
		if is_instance_valid(target_enemy):
			if _is_target_valid(target_enemy) and target_enemy == _last_attacker:
				_last_attacker = null

		_change_state(State.IDLE)
		_update_visual_state()

func _on_melee_attack_area_hit(body: Node2D):
	if not (body is BaseEnemy and _is_target_valid(body)): return
	
	var final_damage = float(damage)
	if _guardian_spirit_buff_active:
		final_damage *= 4.0
		_guardian_spirit_buff_active = false
		_update_visual_state()
	
	var total_crit_chance = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE) + golem_crit_chance
	if randf() < total_crit_chance:
		final_damage *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)

	var weapon_tags: Array[StringName] = []
	if specific_weapon_stats.has("tags"):
		weapon_tags = specific_weapon_stats.get("tags")
	body.take_damage(int(round(final_damage)), owner_player, {}, weapon_tags) # Pass tags
	
	if specific_weapon_stats.get(&"has_crushing_blows", false):
		if randf() < float(specific_weapon_stats.get(&"crushing_blow_chance", 0.0)):
			var smash_effect = CRUSHING_BLOW_SCENE.instantiate()
			get_tree().current_scene.add_child(smash_effect)
			smash_effect.initialize(global_position, damage, specific_weapon_stats, owner_player, self)

func on_player_damaged(attacker_node: Node2D):
	if not is_instance_valid(attacker_node) or not (attacker_node is BaseEnemy): return
	if specific_weapon_stats.get(&"has_guardian_spirit", false) and not _guardian_spirit_buff_active:
		_guardian_spirit_buff_active = true
		_last_attacker = attacker_node as BaseEnemy
		_update_visual_state()

func _on_proc_check_timeout():
	if specific_weapon_stats.get(&"has_protective_dust", false):
		if randf() < float(specific_weapon_stats.get(&"protective_dust_proc_chance", 0.0)):
			var cloud = PROTECTIVE_DUST_SCENE.instantiate()
			get_tree().current_scene.add_child(cloud)
			cloud.global_position = global_position
			var cloud_radius = float(specific_weapon_stats.get(&"protective_dust_cloud_radius", 50.0))
			cloud.initialize(owner_player, load("res://DataResources/StatusEffects/protective_dust_buff.tres"), cloud_radius)
	if specific_weapon_stats.get(&"has_primal_fury", false):
		if randf() < float(specific_weapon_stats.get(&"primal_fury_proc_chance", 0.0)):
			status_effect_component.apply_effect(PRIMAL_FURY_BUFF, self)

func _on_status_effects_changed(_owner_node = null):
	update_stats()

func _update_visual_state():
	if is_instance_valid(_fury_tween):
		_fury_tween.kill()
		_fury_tween = null
	
	if status_effect_component.has_status_effect(&"primal_fury_buff"):
		_fury_tween = create_tween().set_loops()
		_fury_tween.tween_property(animated_sprite, "modulate", Color.RED, 0.2).set_trans(Tween.TRANS_SINE)
		_fury_tween.tween_property(animated_sprite, "modulate", Color.YELLOW, 0.2).set_trans(Tween.TRANS_SINE)
	elif _guardian_spirit_buff_active:
		animated_sprite.modulate = Color(0.5, 1.0, 0.5, 1.0)
	else:
		animated_sprite.modulate = Color.WHITE

func _is_target_valid(target: Node) -> bool:
	return is_instance_valid(target) and target is BaseEnemy and not target.is_dead()
