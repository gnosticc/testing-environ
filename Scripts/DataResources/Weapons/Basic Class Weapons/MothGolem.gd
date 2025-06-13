# MothGolem.gd
# Controls the behavior of a summoned Moth Golem.
# CORRECTED: Features a more robust state machine to prevent "state thrashing"
# and ensures the golem commits to and completes its attack animation.

class_name MothGolem
extends CharacterBody2D

# State machine for the Golem's AI
enum State { IDLE, FOLLOWING_PLAYER, CHASING_TARGET, ATTACKING }
var current_state: State = State.IDLE

# --- References ---
var owner_player: PlayerCharacter
var _owner_player_stats: PlayerStats
var target_enemy: BaseEnemy

# --- Core Stats ---
var movement_speed: float = 100.0
var max_follow_distance: float = 250.0
var player_detection_range: float = 200.0
var attack_range: float = 30.0
var attack_cooldown: float = 1.8
var damage: int = 20
var base_scale: float = 1.0

var specific_weapon_stats: Dictionary

# --- Components ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_cooldown_timer: Timer = $AttackCooldownTimer
@onready var melee_attack_area: Area2D = $MeleeAttackArea
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D

signal instances_spawned(summon_id: StringName, spawned_instances: Array[Node2D])

func _ready():
	# Initialization is deferred to set_attack_properties
	pass
	
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_owner_player_stats) and _owner_player_stats.is_connected("stats_recalculated", _on_player_stats_recalculated):
			_owner_player_stats.stats_recalculated.disconnect(_on_player_stats_recalculated)

func set_attack_properties(_p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	owner_player = p_player_stats.get_parent() as PlayerCharacter
	_owner_player_stats = p_player_stats
	specific_weapon_stats = p_attack_stats

	if not is_instance_valid(owner_player) or not is_instance_valid(_owner_player_stats):
		push_error("MothGolem ERROR: Player or PlayerStats invalid. Queueing free."); queue_free(); return

	# Connect signals
	if not owner_player.is_connected("attacked_by_enemy", on_player_damaged):
		owner_player.attacked_by_enemy.connect(on_player_damaged)
	if not animated_sprite.is_connected("animation_finished", _on_attack_animation_finished):
		animated_sprite.animation_finished.connect(_on_attack_animation_finished)
	if not _owner_player_stats.is_connected("stats_recalculated", _on_player_stats_recalculated):
		_owner_player_stats.stats_recalculated.connect(_on_player_stats_recalculated, CONNECT_DEFERRED)
	if not melee_attack_area.is_connected("body_entered", _on_melee_attack_area_hit_detected):
		melee_attack_area.body_entered.connect(_on_melee_attack_area_hit_detected)        

	attack_cooldown_timer.one_shot = true
	attack_cooldown_timer.autostart = false
	
	var area_collision_shape = melee_attack_area.get_child(0) as CollisionShape2D
	if is_instance_valid(area_collision_shape):
		area_collision_shape.disabled = true

	update_stats(specific_weapon_stats)

	var weapon_id_for_tracking = specific_weapon_stats.get(&"weapon_id", &"moth_golem")
	emit_signal("instances_spawned", weapon_id_for_tracking, [self])

func _on_player_stats_recalculated(_new_max_health, _new_movement_speed):
	update_stats({})

func update_stats(p_stats: Dictionary):
	if not p_stats.is_empty():
		specific_weapon_stats = p_stats
	if not is_instance_valid(_owner_player_stats): return

	movement_speed = float(specific_weapon_stats.get(&"movement_speed", 80.0))
	max_follow_distance = float(specific_weapon_stats.get(&"follow_distance", 250.0))
	player_detection_range = float(specific_weapon_stats.get(&"detection_range", 300.0))
	attack_range = float(specific_weapon_stats.get(&"attack_range", 30.0))
	attack_cooldown = float(specific_weapon_stats.get(&"attack_cooldown", 1.8))
	base_scale = float(specific_weapon_stats.get(&"base_visual_scale", 1.0))
	
	var weapon_level = int(specific_weapon_stats.get(&"weapon_level", 1))
	var scale_per_level = float(specific_weapon_stats.get(&"scale_increase_per_level", 0.05))
	
	var weapon_damage_percent = float(specific_weapon_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.8))
	var global_summon_damage_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER)
	var summon_damage_percent_final = weapon_damage_percent * global_summon_damage_mult
	var weapon_tags: Array[StringName] = specific_weapon_stats.get(&"tags", [])
	damage = int(round(maxf(1.0, _owner_player_stats.get_calculated_player_damage(summon_damage_percent_final, weapon_tags))))
	
	var global_summon_cdr_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_COOLDOWN_REDUCTION_PERCENT)
	attack_cooldown_timer.wait_time = attack_cooldown * (1.0 - global_summon_cdr_percent)

	var final_scale = base_scale + (scale_per_level * (weapon_level - 1))
	self.scale = Vector2.ONE * final_scale

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free(); return

	# The ATTACKING state is now handled by animation signals, not the physics process.
	# This prevents it from being interrupted every frame.
	if current_state == State.ATTACKING:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed * delta * 5)
	else:
		match current_state:
			State.IDLE:
				animated_sprite.play("idle")
				velocity = velocity.move_toward(Vector2.ZERO, movement_speed * delta * 5)
				_find_new_target()
				if _is_target_valid(target_enemy):
					_change_state(State.CHASING_TARGET)
				elif global_position.distance_to(owner_player.global_position) > 25:
					_change_state(State.FOLLOWING_PLAYER)

			State.FOLLOWING_PLAYER:
				animated_sprite.play("walk")
				var dir_to_player = (owner_player.global_position - global_position).normalized()
				velocity = dir_to_player * movement_speed
				_find_new_target()
				if _is_target_valid(target_enemy):
					_change_state(State.CHASING_TARGET)
				elif global_position.distance_to(owner_player.global_position) < 20:
					_change_state(State.IDLE)

			State.CHASING_TARGET:
				if not _is_target_valid(target_enemy):
					_change_state(State.IDLE); return
				
				if target_enemy.global_position.distance_to(owner_player.global_position) > max_follow_distance:
					target_enemy = null
					_change_state(State.FOLLOWING_PLAYER)
					return

				var distance_to_target = global_position.distance_to(target_enemy.global_position)
				if distance_to_target <= attack_range:
					if attack_cooldown_timer.is_stopped():
						_change_state(State.ATTACKING)
				else:
					animated_sprite.play("walk")
					var dir_to_enemy = (target_enemy.global_position - global_position).normalized()
					velocity = dir_to_enemy * movement_speed

	if velocity.length_squared() > 1:
		animated_sprite.flip_h = velocity.x < 0

	move_and_slide()

func _change_state(new_state: State):
	if current_state == new_state: return
	current_state = new_state
	
	if new_state == State.ATTACKING:
		_perform_attack_action()

func _perform_attack_action():
	velocity = Vector2.ZERO
	attack_cooldown_timer.start()
	animated_sprite.play("attack")
	
	# Enable hitbox at the start of the attack animation
	var area_collision_shape = melee_attack_area.get_child(0) as CollisionShape2D
	if is_instance_valid(area_collision_shape):
		area_collision_shape.disabled = false

func _on_attack_animation_finished():
	if animated_sprite.animation != "attack": return

	# Disable hitbox after the animation finishes
	var area_collision_shape = melee_attack_area.get_child(0) as CollisionShape2D
	if is_instance_valid(area_collision_shape):
		area_collision_shape.disabled = true

	# After attacking, decide what to do next
	_change_state(State.IDLE)

func _on_melee_attack_area_hit_detected(body: Node2D):
	if not (body.is_in_group("enemies") and body is BaseEnemy): return

	var enemy_target = body as BaseEnemy
	if _is_target_valid(enemy_target):
		var owner_player_char = owner_player
		var attack_stats_for_enemy = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		enemy_target.take_damage(damage, owner_player_char, attack_stats_for_enemy)
		
		# Apply lifesteal and other on-hit effects here...

func on_player_damaged(attacker: Node2D):
	if _is_target_valid(attacker):
		target_enemy = attacker as BaseEnemy
		_change_state(State.CHASING_TARGET)

func _find_new_target():
	target_enemy = null
	var enemies = get_tree().get_nodes_in_group("enemies")
	var best_target_distance_sq = INF
	
	var search_origin = global_position
	var search_range_sq = player_detection_range * player_detection_range
	
	for enemy in enemies:
		if _is_target_valid(enemy):
			var dist_from_golem_sq = search_origin.distance_squared_to(enemy.global_position)
			if dist_from_golem_sq < search_range_sq and dist_from_golem_sq < best_target_distance_sq:
				best_target_distance_sq = dist_from_golem_sq
				target_enemy = enemy as BaseEnemy

func _is_target_valid(target_node: Node) -> bool:
	return is_instance_valid(target_node) and target_node.is_inside_tree() and not (target_node as BaseEnemy).is_dead()
