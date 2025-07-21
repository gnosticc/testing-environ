# File: res://Scripts/Weapons/WarhammerAttack.gd
# FIX: Implemented _on_animation_playback_finished wrapper function to correctly
# handle the animation_finished signal and its argument, ensuring queue_free works reliably.

class_name WarhammerAttack
extends Node2D

signal enemy_hit(enemy_node: Node)

@onready var pivot: Node2D = $Pivot
@onready var animated_sprite: Sprite2D = $Pivot/Sprite2D
@onready var damage_area: Area2D = $Pivot/DamageArea
@onready var collision_shape: CollisionShape2D = $Pivot/DamageArea/CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _enemies_hit_this_sweep: Array[Node2D] = []

func _ready():
	# Ensure required nodes are present
	if not is_instance_valid(pivot) or not is_instance_valid(animation_player):
		push_error("WarhammerAttack ERROR: Missing Pivot or AnimationPlayer node. Queueing free.")
		queue_free()
		return
	if not is_instance_valid(damage_area) or not is_instance_valid(collision_shape):
		push_error("WarhammerAttack ERROR: Missing damage area or collision shape. Queueing free.")
		queue_free()
		return
		
	damage_area.body_entered.connect(_on_body_entered)
	
	# Connect the signal to our new wrapper function.
	animation_player.animation_finished.connect(_on_animation_playback_finished)
	
	collision_shape.disabled = true

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()
		
	_apply_visuals_and_timing()
	_start_attack()

func _apply_visuals_and_timing():
	var base_scale_x = float(_specific_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_specific_stats.get(&"inherent_visual_scale_y", 1.0))
	var weapon_area_mult = float(_specific_stats.get(&"area_scale", 1.0))
	var player_aoe_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	var final_scale_x = base_scale_x * weapon_area_mult * player_aoe_mult
	var final_scale_y = base_scale_y * weapon_area_mult * player_aoe_mult
	pivot.scale = Vector2(final_scale_x, final_scale_y)

	var player_attack_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	animation_player.speed_scale = player_attack_speed_mult

func _start_attack():
	_enemies_hit_this_sweep.clear()
	collision_shape.disabled = false
	animation_player.play("swing")

# This new wrapper function safely receives the signal from the AnimationPlayer.
# The 'anim_name' argument is received but ignored, as we just want to know when it's done.
func _on_animation_playback_finished(_anim_name: StringName):
	queue_free() # Now we can safely call queue_free without arguments.

func _on_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit_this_sweep.has(body): return
	
	var enemy_target = body as BaseEnemy
	if enemy_target.is_dead(): return

	_enemies_hit_this_sweep.append(enemy_target)
	var owner_player = _owner_player_stats.get_parent() as PlayerCharacter

	var armor_break_status = load("res://DataResources/StatusEffects/armor_break_status.tres") as StatusEffectData
	if is_instance_valid(armor_break_status) and is_instance_valid(enemy_target.status_effect_component):
		var luck = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.LUCK)
		var base_armor_reduction = float(_specific_stats.get(&"armor_break_base", 10.0))
		var luck_armor_reduction = int(luck) * 3
		var total_reduction = base_armor_reduction + luck_armor_reduction
		enemy_target.status_effect_component.apply_effect(armor_break_status, owner_player, {}, 5.0, -total_reduction)

	var weapon_damage_percent = float(_specific_stats.get(&"weapon_damage_percentage", 1.0))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")
	
	# --- REFACTORED DAMAGE CALCULATION ---
	# Step 1: Get the base damage without tag-specific bonuses.
	var base_damage = _owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
	# Step 2: Apply any tag-specific bonuses to that base damage.
	var calculated_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	# --- END REFACTOR ---
	
	if _owner_player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_SKULLSPLITTER):
		if enemy_target.status_effect_component.has_flag(&"is_slowed") or \
		   enemy_target.status_effect_component.has_flag(&"is_stunned") or \
		   enemy_target.status_effect_component.has_flag(&"is_rooted"):
			calculated_damage *= 2.5

	if _owner_player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_STEADFAST_ADVANCE):
		var status_comp = owner_player.get_node_or_null("StatusEffectComponent")
		var steadfast_buff = load("res://DataResources/StatusEffects/steadfast_advance_buff.tres") as StatusEffectData
		if is_instance_valid(status_comp) and is_instance_valid(steadfast_buff):
			status_comp.apply_effect(steadfast_buff, owner_player)
		else:
			push_warning("WarhammerAttack: Failed to apply Steadfast Advance. Player's StatusEffectComponent or buff data is invalid.")

	if _owner_player_stats.get_flag(PlayerStatKeys.Keys.PLAYER_HAS_CHAMPIONS_RESOLVE):
		if owner_player.has_method("add_temporary_max_health"):
			owner_player.add_temporary_max_health(5.0)

	var final_damage = int(round(maxf(1.0, calculated_damage)))
	enemy_target.take_damage(final_damage, owner_player, {}, weapon_tags)
	
	emit_signal("enemy_hit", enemy_target)
