# scythe_attack.gd
# REVISED: The on-hit healing logic has been removed. This script's only
# responsibility is now to deal damage and report any successful hits to the
# CombatTracker singleton for the new Soul Siphon implementation.

class_name ScytheAttack
extends Node2D

signal reaping_momentum_hit(hit_count: int)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_area: Area2D = $DamageArea
@onready var collision_shape: CollisionShape2D = $DamageArea/CollisionShape2D

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _enemies_hit_this_sweep: Array[Node2D] = []
var _is_attack_active: bool = false
var _current_attack_duration: float = 0.5
var _hit_counter: int = 0

func _ready():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area) or not is_instance_valid(collision_shape):
		queue_free(); return
	damage_area.body_entered.connect(_on_body_entered)
	collision_shape.disabled = true
	tree_exiting.connect(_on_tree_exiting)

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats, _p_weapon_manager: WeaponManager):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	if direction != Vector2.ZERO: self.rotation = direction.angle()
	_apply_visuals_and_timing()
	_start_attack_animation()

func _apply_visuals_and_timing():
	if not is_instance_valid(self) or _specific_stats.is_empty() or not is_instance_valid(_owner_player_stats): return
	var base_scale_x = float(_specific_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_specific_stats.get(&"inherent_visual_scale_y", 1.0))
	var weapon_aoe_mult = float(_specific_stats.get(&"area_scale", 1.0))
	var player_aoe_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	self.scale = Vector2(base_scale_x * weapon_aoe_mult * player_aoe_mult, base_scale_y * weapon_aoe_mult * player_aoe_mult)
	
	var base_duration = float(_specific_stats.get(&"base_attack_duration", 0.5))
	var player_attack_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	if player_attack_speed_mult <= 0: player_attack_speed_mult = 0.01
	_current_attack_duration = base_duration / player_attack_speed_mult
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = player_attack_speed_mult

func _start_attack_animation():
	_enemies_hit_this_sweep.clear()
	_is_attack_active = true
	collision_shape.disabled = false
	animated_sprite.play("slash")
	get_tree().create_timer(_current_attack_duration, true, false, true).timeout.connect(queue_free)

func _on_body_entered(body: Node2D):
	if not _is_attack_active or not is_instance_valid(body) or _enemies_hit_this_sweep.has(body): return
	
	if body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return
		_enemies_hit_this_sweep.append(enemy_target)
		
		var owner_player = _owner_player_stats.get_parent() as PlayerCharacter
		if not is_instance_valid(owner_player): return

		var weapon_damage_percent = float(_specific_stats.get(&"weapon_damage_percentage", 1.5))
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")
			
		# --- REFACTORED DAMAGE CALCULATION ---
		var base_damage = _owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
		var calculated_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
		# --- END REFACTOR ---

		var reaping_bonus = float(_specific_stats.get(&"reaping_momentum_accumulated_bonus", 0.0))
		calculated_damage += reaping_bonus

		var final_damage_to_deal = int(round(maxf(1.0, calculated_damage)))
		
		var attack_stats_for_enemy = { PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION) }
		
		# --- FIX: Record the hit BEFORE dealing damage ---
		CombatTracker.record_hit(&"warrior_scythe", enemy_target)
		
		# Now, deal the damage. If this is fatal, the death signal will fire,
		# but the CombatTracker will already have the necessary information.
		enemy_target.take_damage(final_damage_to_deal, owner_player, attack_stats_for_enemy, weapon_tags)
		
		if _specific_stats.get(&"has_reaping_momentum", false):
			_hit_counter += 1
		
		var on_hit_applications = _specific_stats.get(&"on_hit_status_applications", []) as Array
		if not on_hit_applications.is_empty():
			var enemy_status_comp = enemy_target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
			if is_instance_valid(enemy_status_comp):
				var global_status_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)
				for app_data_res in on_hit_applications:
					if app_data_res is StatusEffectApplicationData:
						var final_chance = app_data_res.application_chance + global_status_chance_add
						if randf() < final_chance:
							enemy_status_comp.apply_effect(load(app_data_res.status_effect_resource_path) as StatusEffectData, owner_player, _specific_stats, app_data_res.duration_override, app_data_res.potency_override)

func _on_tree_exiting():
	if _specific_stats.get(&"has_reaping_momentum", false) and _hit_counter > 0:
		emit_signal("reaping_momentum_hit", _hit_counter)
