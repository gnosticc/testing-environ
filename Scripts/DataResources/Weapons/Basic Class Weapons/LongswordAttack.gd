# LongswordAttack.gd
# This is the complete and final version of the Longsword attack script.
# DEBUG: Added print statements to confirm Critical Hit and Knight's Resolve application.

class_name LongswordAttack
extends Node2D

signal attack_hit_enemy(hit_count: int)

# --- Node References ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_area: Area2D = $DamageArea
@onready var collision_shape: CollisionPolygon2D = $DamageArea/CollisionPolygon2D

# --- Internal State ---
var specific_stats: Dictionary
var owner_player_stats: PlayerStats

var _enemies_hit_this_sweep: Array[Node2D] = []
var _hit_counter: int = 0
var _is_attack_active: bool = false
var _current_attack_duration: float = 0.4

func _ready():
	tree_exiting.connect(_on_tree_exiting)
	
	if not is_instance_valid(damage_area) or not is_instance_valid(collision_shape):
		push_error("LongswordAttack ERROR: Missing damage area or collision shape. Queueing free.")
		queue_free(); return

	damage_area.body_entered.connect(_on_body_entered)
	collision_shape.disabled = true

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	specific_stats = p_attack_stats
	owner_player_stats = p_player_stats
	
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()
		
	_apply_visuals_and_timing()
	_start_attack_animation()

func _apply_visuals_and_timing():
	if not is_instance_valid(self) or specific_stats.is_empty() or not is_instance_valid(owner_player_stats): return

	var base_scale_x = float(specific_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(specific_stats.get(&"inherent_visual_scale_y", 1.0))
	
	var weapon_area_mult = float(specific_stats.get(&"area_scale", 1.0))
	var weapon_length_mult = float(specific_stats.get(&"length_scale", 1.0))
	var player_aoe_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	
	self.scale = Vector2(base_scale_x * weapon_area_mult * player_aoe_mult, base_scale_y * weapon_length_mult * player_aoe_mult)

	var base_duration = float(specific_stats.get(&"base_attack_duration", 0.4))
	var weapon_atk_speed_mult = float(specific_stats.get(&"attack_speed_multiplier", 1.0))
	var player_atk_speed_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	var final_atk_speed_mult = player_atk_speed_mult * weapon_atk_speed_mult
	
	if final_atk_speed_mult <= 0: final_atk_speed_mult = 0.01
	_current_attack_duration = base_duration / final_atk_speed_mult
	
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_atk_speed_mult

func _start_attack_animation():
	_enemies_hit_this_sweep.clear()
	_hit_counter = 0
	_is_attack_active = true
	collision_shape.disabled = false
	animated_sprite.play("slash")
	get_tree().create_timer(_current_attack_duration, true, false, true).timeout.connect(queue_free)

func _on_body_entered(body: Node2D):
	if not _is_attack_active or not body is BaseEnemy or _enemies_hit_this_sweep.has(body): return
	var weapon_tags: Array[StringName] = []
	if specific_stats.has("tags"):
		weapon_tags = specific_stats.get("tags")
	var enemy_target = body as BaseEnemy
	if enemy_target.is_dead(): return

	_enemies_hit_this_sweep.append(enemy_target)
	_hit_counter += 1
	var owner_player = owner_player_stats.get_parent()

	# --- KNIGHT'S RESOLVE ---
	if specific_stats.get(&"has_knights_resolve", false):
		var status_comp = owner_player.get_node_or_null("StatusEffectComponent")
		if is_instance_valid(status_comp):
			var effect_res = load("res://DataResources/Weapons/Longsword/Effects/knights_resolve_buff.tres") as StatusEffectData
			if is_instance_valid(effect_res):
				status_comp.apply_effect(effect_res, owner_player)
				# DEBUG: Confirm that the buff application is being attempted.
				print_debug("LongswordAttack: Knight's Resolve buff applied.")

	# --- DAMAGE CALCULATION ---
	var damage_to_deal = float(specific_stats.get("final_damage_amount", 10.0))
	
	# --- POWER LUNGE (CRIT) ---
	var weapon_crit_chance = float(specific_stats.get(&"crit_chance", 0.0))
	var total_crit_chance = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE) + weapon_crit_chance
	if randf() < total_crit_chance:
		damage_to_deal *= owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
		# DEBUG: Confirm that a critical hit has occurred.
		print_debug("LongswordAttack: CRITICAL HIT! Damage multiplied to: ", damage_to_deal)

	var attack_stats = { PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION) }
	
	# DEBUG: Print the final damage being dealt to the enemy.
	print_debug("LongswordAttack: Dealing ", int(round(damage_to_deal)), " damage to ", enemy_target.name)
	enemy_target.take_damage(int(round(damage_to_deal)), owner_player, attack_stats, weapon_tags)

func _on_tree_exiting():
	if specific_stats.get(&"has_parry_riposte", false):
		emit_signal("attack_hit_enemy", _hit_counter)
