# ======================================================================
# MODIFIED SCRIPT: DaggerStrikeAttack.gd
# Path: res://Scripts/Weapons/DaggerStrikeAttack.gd
# FIX: The creation of the cleave visual effect is now deferred to
# prevent physics state crashes.
# ======================================================================

class_name DaggerStrikeAttack
extends Node2D

signal hit_enemy_for_combo(enemy_node: Node)
signal dealt_damage(enemy_node: Node, damage_amount: int)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_area: Area2D = $DamageArea
@onready var collision_shape: CollisionShape2D = $DamageArea/CollisionShape2D

var specific_stats: Dictionary = {}
var owner_player_stats: PlayerStats = null

var _enemies_hit_this_sweep: Array[Node2D] = []
var _is_attack_active: bool = false
var _current_attack_duration: float
var _stats_have_been_set: bool = false
var _scene_file: PackedScene

func _ready():
	if not is_instance_valid(animated_sprite):
		push_error("ERROR (DaggerStrikeAttack): AnimatedSprite2D node missing!"); call_deferred("queue_free"); return
	else:
		animated_sprite.animation_finished.connect(Callable(self, "_on_animation_finished"))
	if not is_instance_valid(damage_area):
		push_warning("WARNING (DaggerStrikeAttack): DamageArea node missing.")
	else:
		damage_area.body_entered.connect(Callable(self, "_on_body_entered"))
		if not is_instance_valid(collision_shape):
			push_warning("WARNING (DaggerStrikeAttack): CollisionShape not found under DamageArea.")
	
	# The collision shape is now enabled/disabled only when the attack starts and ends.

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_attack_stats.duplicate(true)
	owner_player_stats = p_player_stats
	_stats_have_been_set = true
	
	var scene_path = specific_stats.get("scene_file_path", "")
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		_scene_file = load(scene_path)
	else:
		push_warning("DaggerStrikeAttack: scene_file_path not found in stats or is invalid. Cleave visual may fail.")
	
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()
		if is_instance_valid(animated_sprite):
			animated_sprite.flip_h = false; animated_sprite.flip_v = false
			if direction.x < 0: animated_sprite.flip_h = true
			if absf(direction.y) > absf(direction.x):
				if direction.y < 0: animated_sprite.flip_v = true
				else: animated_sprite.flip_v = false
	else:
		self.rotation = 0.0
		if is_instance_valid(animated_sprite):
			animated_sprite.flip_h = false; animated_sprite.flip_v = false
	_apply_all_stats_effects(); _start_attack_animation()

func initialize_as_visual_effect_only(p_scale_multiplier: float = 0.3):
	_is_attack_active = false
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(animated_sprite):
		self.scale *= p_scale_multiplier
		animated_sprite.modulate = Color(1, 1, 1, 0.7)
		animated_sprite.play("slash")

func _apply_all_stats_effects():
	if not is_instance_valid(owner_player_stats):
		push_warning("DaggerStrikeAttack: owner_player_stats invalid."); return

	var attack_area_scale_x = float(specific_stats.get(&"attack_area_scale_x", 1.0))
	var attack_area_scale_y = float(specific_stats.get(&"attack_area_scale_y", 1.0))
	var player_aoe_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	self.scale = Vector2(attack_area_scale_x * player_aoe_multiplier, attack_area_scale_y * player_aoe_multiplier)
	
	if specific_stats.get("is_finishing_blow_visual", false):
		self.scale *= 1.25
		if is_instance_valid(animated_sprite):
			animated_sprite.modulate = Color.GOLD
			
	var base_duration = float(specific_stats.get(&"base_attack_duration", 0.25))
	var player_attack_speed_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	var weapon_attack_speed_mod = float(specific_stats.get(&"weapon_attack_speed_mod", 1.0)) 
	var final_attack_speed_multiplier = player_attack_speed_multiplier * weapon_attack_speed_mod
	if final_attack_speed_multiplier <= 0: final_attack_speed_multiplier = 0.01
	_current_attack_duration = base_duration / final_attack_speed_multiplier
	
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_attack_speed_multiplier

func _start_attack_animation():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area):
		call_deferred("queue_free"); return
	_enemies_hit_this_sweep.clear(); _is_attack_active = true
	if is_instance_valid(collision_shape): collision_shape.disabled = false
	animated_sprite.play("slash")
	var duration_finish_timer = get_tree().create_timer(_current_attack_duration, true, false, true)
	duration_finish_timer.timeout.connect(queue_free)

func _on_animation_finished():
	if not _is_attack_active:
		queue_free()

func _on_body_entered(body: Node2D):
	if not _is_attack_active or not is_instance_valid(body) or _enemies_hit_this_sweep.has(body): return
	
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return
		
		_enemies_hit_this_sweep.append(enemy_target)
		if not is_instance_valid(owner_player_stats):
			push_error("DaggerStrikeAttack: owner_player_stats is invalid."); return

		var owner_player = owner_player_stats.get_parent()
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		
		_deal_damage_and_effects(enemy_target, owner_player, attack_stats_for_enemy)
		
		var has_cleave = specific_stats.get(&"has_cleave", false)
		var cleave_chance = float(specific_stats.get(&"cleave_chance", 0.0))
		if has_cleave and randf() < cleave_chance:
			var cleave_target = _find_cleave_target(enemy_target.global_position)
			if is_instance_valid(cleave_target):
				_enemies_hit_this_sweep.append(cleave_target)
				_deal_damage_and_effects(cleave_target, owner_player, attack_stats_for_enemy)
				
				## FIX: Defer the entire creation of the visual cue to prevent physics state errors.
				call_deferred("_spawn_cleave_visual_cue", cleave_target.global_position, self.rotation)

## NEW: This function handles the creation of the visual cue safely.
func _spawn_cleave_visual_cue(position: Vector2, p_rotation: float):
	if is_instance_valid(_scene_file):
		var visual_cue = _scene_file.instantiate()
		get_tree().current_scene.add_child(visual_cue)
		visual_cue.global_position = position
		visual_cue.rotation = p_rotation
		if visual_cue.has_method("initialize_as_visual_effect_only"):
			# This call is now safe because the entire function was deferred.
			visual_cue.initialize_as_visual_effect_only(0.3)
					
func _deal_damage_and_effects(target_enemy: BaseEnemy, p_owner_player: PlayerCharacter, p_attack_stats: Dictionary):
	if not is_instance_valid(target_enemy): return
	
	var weapon_damage_percent = float(specific_stats.get(&"weapon_damage_percentage", 0.9))
	var hit_damage_mult = float(specific_stats.get("damage_multiplier", 1.0))
	var weapon_tags: Array[StringName] = specific_stats.get(&"tags", [])
	var calculated_damage_float = owner_player_stats.get_calculated_player_damage(weapon_damage_percent * hit_damage_mult, weapon_tags)
	
	var weapon_crit_chance = float(specific_stats.get(&"crit_chance", 0.0))
	var total_crit_chance = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE) + weapon_crit_chance
	if randf() < total_crit_chance:
		var player_crit_mult = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
		var weapon_crit_mult = float(specific_stats.get(&"crit_damage_multiplier", 1.0))
		calculated_damage_float *= (player_crit_mult + weapon_crit_mult - 1.0)

	var final_damage_to_deal = int(round(maxf(1.0, calculated_damage_float)))
	target_enemy.take_damage(final_damage_to_deal, p_owner_player, p_attack_stats)
	
	var global_lifesteal_percent = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
	if global_lifesteal_percent > 0:
		var heal_amount = final_damage_to_deal * global_lifesteal_percent
		if is_instance_valid(p_owner_player) and p_owner_player.has_method("heal"):
			p_owner_player.heal(heal_amount)
	
	if specific_stats.has(&"on_hit_status_applications") and is_instance_valid(target_enemy.status_effect_component):
		var status_apps: Array = specific_stats.get(&"on_hit_status_applications", [])
		var global_status_chance_add = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

		for app_data_res in status_apps:
			var app_data = app_data_res as StatusEffectApplicationData
			if is_instance_valid(app_data):
				var final_application_chance = app_data.application_chance + global_status_chance_add
				final_application_chance = clampf(final_application_chance, 0.0, 1.0)
				
				if randf() < final_application_chance:
					target_enemy.status_effect_component.apply_effect(
						load(app_data.status_effect_resource_path) as StatusEffectData,
						p_owner_player,
						specific_stats,
						app_data.duration_override,
						app_data.potency_override
					)
	
	emit_signal("hit_enemy_for_combo", target_enemy)
	emit_signal("dealt_damage", target_enemy, final_damage_to_deal)

func _find_cleave_target(hit_position: Vector2) -> BaseEnemy:
	var cleave_radius = float(specific_stats.get(&"cleave_radius", 100.0))
	var best_target: BaseEnemy = null
	var min_dist_sq = cleave_radius * cleave_radius
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or _enemies_hit_this_sweep.has(enemy) or not (enemy is BaseEnemy): continue
		var enemy_base = enemy as BaseEnemy
		if enemy_base.is_dead(): continue
		
		var dist_sq = hit_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_target = enemy_base
			
	return best_target
