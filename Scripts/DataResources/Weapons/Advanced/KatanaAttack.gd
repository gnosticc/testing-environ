# File: res://Scripts/Weapons/KatanaAttack.gd
# This script is attached to the individual slash Area2D scene.
# FIX: Now uses a reliable Timer for self-deletion instead of relying on animation signals.
# FIX: Correctly rotates the sprite to account for left-facing default animation.

class_name KatanaAttack
extends Node2D

signal hit_an_enemy(enemy_node: BaseEnemy, damage_dealt: int, is_final_hit: bool)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_area: Area2D = $DamageArea

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _controller: KatanaAttackController
var _enemies_hit_this_sweep: Array[Node2D] = []
var is_final_hit: bool = false

func _ready():
	damage_area.body_entered.connect(_on_body_entered)
	# The connection to animation_finished is removed in favor of a reliable timer.

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, p_controller: KatanaAttackController):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_controller = p_controller
	
	# FIX: Adjust rotation to account for left-facing sprite.
	# Adding PI to the direction's angle effectively rotates the coordinate system
	# by 180 degrees, making the left-facing sprite align correctly.
	self.rotation = direction.angle() + PI
	
	_apply_scaling_and_timing()
	animated_sprite.play("slash")

func _apply_scaling_and_timing():
	var scale_x = float(_specific_stats.get("attack_area_scale_x", 1.0))
	var scale_y = float(_specific_stats.get("attack_area_scale_y", 1.0))
	var player_aoe_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	self.scale = Vector2(scale_x * player_aoe_mult, scale_y * player_aoe_mult)

	var base_duration = float(_specific_stats.get("base_attack_duration", 0.25))
	var weapon_speed_mod = float(_specific_stats.get("weapon_attack_speed_mod", 1.0))
	var player_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	var final_speed_mult = weapon_speed_mod * player_speed_mult
	if final_speed_mult <= 0: final_speed_mult = 0.01 # Prevent division by zero
	animated_sprite.speed_scale = final_speed_mult
	
	# FIX: Create a one-shot timer to guarantee the node is freed.
	var calculated_duration = base_duration / final_speed_mult
	get_tree().create_timer(calculated_duration, true, false, true).timeout.connect(queue_free)


func _on_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit_this_sweep.has(body): return
	
	var enemy_target = body as BaseEnemy
	if enemy_target.is_dead(): return
	
	_enemies_hit_this_sweep.append(body)
	
	var owner_player = _owner_player_stats.get_parent()
	var weapon_damage_percent = float(_specific_stats.get("weapon_damage_percentage", 0.8))
	var hit_damage_mult = float(_specific_stats.get("damage_multiplier", 1.0))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")
	
	# --- REFACTORED DAMAGE CALCULATION ---
	var base_damage = _owner_player_stats.get_calculated_base_damage(weapon_damage_percent * hit_damage_mult)
	var calculated_damage_with_tags = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	# --- END REFACTOR ---
	
	var focus_stacks = 0
	if is_instance_valid(_controller):
		focus_stacks = _controller.get_focus_stacks_for(enemy_target)
	var focus_bonus_mult = 1.0 + (float(focus_stacks) * _specific_stats.get("focus_damage_bonus_per_stack", 0.10))
	
	var final_damage = int(round(calculated_damage_with_tags * focus_bonus_mult))
	
	enemy_target.take_damage(final_damage, owner_player, {}, weapon_tags)
	
	emit_signal("hit_an_enemy", enemy_target, final_damage, is_final_hit)
