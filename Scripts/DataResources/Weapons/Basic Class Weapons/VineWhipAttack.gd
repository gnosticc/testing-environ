# File: res://Scripts/Weapons/VineWhipAttack.gd
# REFACTORED: Handles conditional tip activation, data-driven tip scaling, and visual flash.
# FIX: Now correctly calls initialize() on the TipFlash instance.

class_name VineWhipAttack
extends Node2D

signal enemy_hit(enemy_node: Node)

const TIP_FLASH_SCENE = preload("res://Scenes/Effects/TipFlash.tscn")
const ENTANGLE_SCENE = preload("res://Scenes/Weapons/Projectiles/Entangle.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_area_main: Area2D = $DamageAreaMain
@onready var damage_area_tip: Area2D = $DamageAreaTip

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _enemies_hit_this_sweep: Dictionary = {}

var _is_attack_active: bool = false

func _ready():
	damage_area_main.body_entered.connect(_on_body_entered.bind("main"))
	damage_area_tip.body_entered.connect(_on_body_entered.bind("tip"))
	animated_sprite.animation_finished.connect(queue_free)

	# Disable collision shapes initially. They are enabled in _start_attack.
	damage_area_main.get_node("CollisionShapeMain").disabled = true
	damage_area_tip.get_node("CollisionShapeTip").disabled = true

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	rotation = direction.angle()
	
	_apply_scaling()
	_apply_timing()
	_start_attack()

func _apply_scaling():
	var base_scale_x = float(_specific_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_specific_stats.get(&"inherent_visual_scale_y", 1.0))
	var area_scale_mod = float(_specific_stats.get(&"area_scale", 1.0))
	var player_aoe_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	
	# Scale the entire whip node (main body and tip areas together)
	scale = Vector2(base_scale_x * area_scale_mod * player_aoe_mult, base_scale_y * area_scale_mod * player_aoe_mult)

	# Conditionally scale the tip area separately
	if _specific_stats.get(&"has_cracking_whip", false):
		var tip_scale_multiplier = float(_specific_stats.get(&"cracking_whip_tip_scale", 1.0))
		damage_area_tip.scale = Vector2.ONE * tip_scale_multiplier

func _apply_timing():
	var player_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	animated_sprite.speed_scale = player_speed_mult

func _start_attack():
	_is_attack_active = true
	damage_area_main.get_node("CollisionShapeMain").disabled = false
	
	# Only enable the tip hitbox if the upgrade has been acquired
	if _specific_stats.get(&"has_cracking_whip", false):
		damage_area_tip.get_node("CollisionShapeTip").disabled = false
		
	animated_sprite.play("whip")

func _on_body_entered(body: Node2D, part_hit: String):
	if not _is_attack_active or not (body is BaseEnemy) or _enemies_hit_this_sweep.has(body):
		return
		
	var enemy_target = body as BaseEnemy
	if enemy_target.is_dead(): return
	
	var final_damage_multiplier = 1.0

	if part_hit == "tip" and _specific_stats.get(&"has_cracking_whip", false):
		final_damage_multiplier += 1.0
		if is_instance_valid(TIP_FLASH_SCENE):
			var flash_instance = TIP_FLASH_SCENE.instantiate()
			get_tree().current_scene.add_child(flash_instance)
			flash_instance.global_position = enemy_target.global_position
			if flash_instance.has_method("initialize"):
				flash_instance.initialize(40.0)

	if _specific_stats.get(&"has_constricting_grip", false):
		if CombatTracker.was_enemy_hit_by_weapon_within_seconds(&"druid_vine_whip", enemy_target, 4.0):
			final_damage_multiplier += 0.5
			
	_enemies_hit_this_sweep[enemy_target] = true
	_deal_damage_to_enemy(enemy_target, final_damage_multiplier)
	
	# --- REVISED: Entangling Vines Logic ---
	# Check for the chance to apply the root effect.
	var entangle_chance = float(_specific_stats.get(&"entangling_vines_chance", 0.0))
	if entangle_chance > 0 and randf() < entangle_chance:
		# Apply the root status effect data to the enemy.
		var root_status_data = load("res://DataResources/StatusEffects/root_status.tres") as StatusEffectData
		if is_instance_valid(root_status_data) and is_instance_valid(enemy_target.status_effect_component):
			enemy_target.status_effect_component.apply_effect(root_status_data, _owner_player_stats.get_parent())
		
		# Spawn the visual effect.
		if is_instance_valid(ENTANGLE_SCENE):
			var entangle_instance = ENTANGLE_SCENE.instantiate()
			if entangle_instance.has_method("initialize"):
				entangle_instance.initialize(enemy_target)
			else:
				# Fallback if initialize fails
				enemy_target.add_child(entangle_instance)
	
	emit_signal("enemy_hit", enemy_target)

func _deal_damage_to_enemy(enemy_target: BaseEnemy, damage_multiplier: float):
	# ... (this function remains identical to the previous version) ...
	var owner_player_char = _owner_player_stats.get_parent()
	var weapon_damage_percent = float(_specific_stats.get(&"weapon_damage_percentage", 1.1))
	var weapon_tags: Array[StringName] = _specific_stats.get(&"tags", [])
	
	var base_damage = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
	var final_damage = base_damage * damage_multiplier
	
	var attack_stats_for_enemy = {
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
	}
	
	enemy_target.take_damage(int(round(maxf(1.0, final_damage))), owner_player_char, attack_stats_for_enemy)
	
	if _specific_stats.has(&"on_hit_status_applications"):
		var status_apps: Array = _specific_stats.get(&"on_hit_status_applications", [])
		for app_data_res in status_apps:
			var app_data = app_data_res as StatusEffectApplicationData
			if is_instance_valid(app_data) and randf() < app_data.application_chance:
				enemy_target.status_effect_component.apply_effect(
					load(app_data.status_effect_resource_path), owner_player_char, _specific_stats,
					app_data.duration_override, app_data.potency_override
				)
