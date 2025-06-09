# MothGolem.gd
# Controls the behavior of a summoned Moth Golem.
# CORRECTED: Added the missing `SEEKING_TARGET` state to the State enum.
class_name MothGolem
extends CharacterBody2D

# State machine for the Golem's AI
enum State { IDLE, FOLLOWING_PLAYER, SEEKING_TARGET, CHASING_TARGET, ATTACKING }
var current_state: State = State.IDLE

# --- References ---
var owner_player: PlayerCharacter
var player_stats: PlayerStats
var target_enemy: BaseEnemy = null
var last_player_attacker: BaseEnemy = null

# --- Core Stats ---
var movement_speed: float = 80.0
var max_follow_distance: float = 400.0
var attack_range: float = 30.0
var attack_cooldown: float = 1.8
var damage: int = 20
var base_scale: float = 1.0

# --- Components ---
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var attack_cooldown_timer: Timer = get_node_or_null("AttackCooldownTimer")
@onready var melee_attack_area: Area2D = get_node_or_null("MeleeAttackArea")

# This function is called by the WeaponManager when the Golem is first summoned.
func initialize(p_owner: PlayerCharacter, p_stats: Dictionary):
	owner_player = p_owner
	player_stats = owner_player.get_node("PlayerStats")

	if not owner_player.is_connected("attacked_by_enemy", Callable(self, "_on_player_attacked")):
		owner_player.attacked_by_enemy.connect(self._on_player_attacked)
	
	update_stats(p_stats) # Apply initial stats

# This function can be called by WeaponManager later when the weapon levels up.
func update_stats(p_stats: Dictionary):
	movement_speed = float(p_stats.get("movement_speed", 80.0))
	max_follow_distance = float(p_stats.get("max_follow_distance", 400.0))
	attack_range = float(p_stats.get("attack_range", 30.0))
	attack_cooldown = float(p_stats.get("attack_cooldown", 1.8))
	base_scale = float(p_stats.get("base_visual_scale", 1.0))
	
	var weapon_level = p_stats.get("weapon_level", 1)
	var scale_per_level = float(p_stats.get("scale_increase_per_level", 0.05))
	var final_scale = base_scale + (scale_per_level * (weapon_level - 1))
	self.scale = Vector2.ONE * final_scale

	if is_instance_valid(player_stats):
		var weapon_damage_percent = float(p_stats.get("weapon_damage_percentage", 1.8))
		damage = int(round(player_stats.get_current_base_numerical_damage() * weapon_damage_percent))
	
	if is_instance_valid(attack_cooldown_timer):
		attack_cooldown_timer.wait_time = attack_cooldown

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free(); return

	match current_state:
		State.IDLE:
			animated_sprite.play("idle")
			if get_tree().get_nodes_in_group("enemies").size() > 0:
				change_state(State.SEEKING_TARGET)
			elif global_position.distance_to(owner_player.global_position) > max_follow_distance:
				change_state(State.FOLLOWING_PLAYER)

		State.FOLLOWING_PLAYER:
			animated_sprite.play("walk")
			var dir = (owner_player.global_position - global_position).normalized()
			velocity = dir * movement_speed
			move_and_slide()
			if global_position.distance_to(owner_player.global_position) < max_follow_distance * 0.8:
				change_state(State.IDLE)
		
		State.SEEKING_TARGET:
			_find_new_target()
			if is_instance_valid(target_enemy): change_state(State.CHASING_TARGET)
			else: change_state(State.IDLE)

		State.CHASING_TARGET:
			if not is_instance_valid(target_enemy) or target_enemy.is_dead():
				change_state(State.SEEKING_TARGET); return

			if global_position.distance_to(target_enemy.global_position) <= attack_range:
				change_state(State.ATTACKING)
			else:
				animated_sprite.play("walk")
				var dir = (target_enemy.global_position - global_position).normalized()
				velocity = dir * movement_speed
				move_and_slide()
			
			if global_position.distance_to(owner_player.global_position) > max_follow_distance:
				target_enemy = null; change_state(State.FOLLOWING_PLAYER)

		State.ATTACKING:
			velocity = Vector2.ZERO
			if not is_instance_valid(target_enemy) or target_enemy.is_dead():
				change_state(State.SEEKING_TARGET); return
			
			if global_position.distance_to(target_enemy.global_position) > attack_range * 1.1:
				change_state(State.CHASING_TARGET); return
			
			if attack_cooldown_timer.is_stopped():
				_perform_attack()

func _perform_attack():
	attack_cooldown_timer.start()
	animated_sprite.play("attack")
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(target_enemy):
		for body in melee_attack_area.get_overlapping_bodies():
			if body == target_enemy:
				target_enemy.take_damage(damage, owner_player)
				break

func _on_player_attacked(enemy_node: Node):
	if enemy_node is BaseEnemy and is_instance_valid(enemy_node) and not enemy_node.is_dead():
		last_player_attacker = enemy_node
		target_enemy = enemy_node
		change_state(State.CHASING_TARGET)

func _find_new_target():
	var highest_health = -1; var best_target = null
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is BaseEnemy and not enemy.is_dead():
			if enemy.current_health > highest_health:
				highest_health = enemy.current_health
				best_target = enemy
	target_enemy = best_target

func change_state(new_state: State):
	if current_state == new_state: return
	current_state = new_state
