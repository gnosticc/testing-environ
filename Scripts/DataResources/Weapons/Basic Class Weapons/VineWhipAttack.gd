# VineWhipAttack.gd
# Behavior for the Druid's Vine Whip attack.
# A fast, aimed melee attack with a longer reach.
class_name VineWhipAttack
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D

const SLASH_ANIMATION_NAME = "whip" # Assuming the animation is named 'whip'

var specific_stats: Dictionary = {}   
var owner_player_stats: PlayerStats = null

var _enemies_hit_this_sweep: Array[Node2D] = []
var _is_attack_active: bool = false 
var _current_attack_duration: float = 0.3

func _ready():
	if not is_instance_valid(animated_sprite):
		print("ERROR (VineWhipAttack): AnimatedSprite2D node missing."); call_deferred("queue_free"); return
	else:
		animated_sprite.animation_finished.connect(Callable(self, "_on_animation_finished"))

	if not is_instance_valid(damage_area):
		print_debug("WARNING (VineWhipAttack): DamageArea node missing.")
	else:
		damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
		var collision_shape = damage_area.get_node_or_null("CollisionShape2D")
		if is_instance_valid(collision_shape):
			collision_shape.disabled = true
		else:
			print_debug("WARNING (VineWhipAttack): No CollisionShape2D found under DamageArea.")

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_attack_stats
	owner_player_stats = p_player_stats
	
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()
		if is_instance_valid(animated_sprite):
			if abs(direction.angle()) > PI / 2.0:
				animated_sprite.flip_v = true

	on_stats_or_upgrades_changed()

func on_stats_or_upgrades_changed():
	if not is_instance_valid(self) or specific_stats.is_empty(): return

	var base_scale_x = float(specific_stats.get("inherent_visual_scale_x", 1.0))
	var base_scale_y = float(specific_stats.get("inherent_visual_scale_y", 1.0))
	var player_aoe_mult = 1.0
	if is_instance_valid(owner_player_stats):
		player_aoe_mult = owner_player_stats.get_current_aoe_area_multiplier()
	self.scale = Vector2(base_scale_x * player_aoe_mult, base_scale_y * player_aoe_mult)
	
	var base_duration = float(specific_stats.get("base_attack_duration", 0.3))
	var atk_speed_player_mult = 1.0 
	if is_instance_valid(owner_player_stats):
		atk_speed_player_mult = owner_player_stats.get_current_attack_speed_multiplier()
	var final_attack_speed_mult = atk_speed_player_mult * float(specific_stats.get("weapon_attack_speed_mod", 1.0))
	if final_attack_speed_mult <= 0: final_attack_speed_mult = 0.01
	_current_attack_duration = base_duration / final_attack_speed_mult
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_attack_speed_mult
	
	_start_attack_animation()

func _start_attack_animation():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area):
		call_deferred("queue_free"); return

	_enemies_hit_this_sweep.clear()
	_is_attack_active = true
	var collision_shape = damage_area.get_node_or_null("CollisionShape2D")
	if is_instance_valid(collision_shape): collision_shape.disabled = false

	animated_sprite.play(SLASH_ANIMATION_NAME)
	var duration_finish_timer = get_tree().create_timer(_current_attack_duration, true, false, true)
	duration_finish_timer.timeout.connect(Callable(self, "queue_free"))

func _on_animation_finished():
	if is_instance_valid(animated_sprite) and animated_sprite.animation == SLASH_ANIMATION_NAME:
		pass

func _on_damage_area_body_entered(body: Node2D):
	if not _is_attack_active or not is_instance_valid(body) or _enemies_hit_this_sweep.has(body): return 
	
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return
		_enemies_hit_this_sweep.append(enemy_target)
		
		if not is_instance_valid(owner_player_stats): return

		var player_base_damage = float(owner_player_stats.get_current_base_numerical_damage())
		var player_global_mult = float(owner_player_stats.get_current_global_damage_multiplier())
		var weapon_damage_percent = float(specific_stats.get("weapon_damage_percentage", 1.1)) # 110% base
		
		var final_damage = (player_base_damage * weapon_damage_percent) * player_global_mult
		var final_damage_to_deal = int(round(max(1.0, final_damage)))
		
		var owner_player = owner_player_stats.get_parent() if is_instance_valid(owner_player_stats) else null
		enemy_target.take_damage(final_damage_to_deal, owner_player)
