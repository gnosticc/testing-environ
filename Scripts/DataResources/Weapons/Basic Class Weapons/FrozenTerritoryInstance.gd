# File: res://Scripts/DataResources/Weapons/Basic Class Weapons/FrozenTerritoryInstance.gd
# MODIFIED: All Rimeheart and Lingering Cold connection logic has been removed.
# This script is now much simpler.

class_name FrozenTerritoryInstance
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
var pull_zone: Area2D 

var owner_player: PlayerCharacter
var _owner_player_stats: PlayerStats
var specific_weapon_stats: Dictionary
var orbit_radius: float = 75.0
var rotation_speed: float = 1.0
var current_angle: float = 0.0
var damage_on_contact: int = 0
var _enemies_hit_this_instance: Array[Node2D] = []

var _has_armor_pierce: bool = false
var _has_arctic_vortex: bool = false
var _vortex_pull_strength: float = 50.0

func _ready():
	if not is_instance_valid(collision_shape): queue_free()
	
	pull_zone = get_node_or_null("PullZone")
	if is_instance_valid(pull_zone):
		pull_zone.monitoring = false
	
	body_entered.connect(_on_body_entered)

func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, start_angle: float):
	owner_player = p_owner
	_owner_player_stats = p_owner.player_stats
	specific_weapon_stats = p_stats
	
	if not is_instance_valid(owner_player): queue_free(); return

	orbit_radius = float(specific_weapon_stats.get(&"orbit_radius", 75.0))
	var rotation_duration = float(specific_weapon_stats.get(&"rotation_duration", 3.0))
	if rotation_duration > 0: rotation_speed = TAU / rotation_duration
	current_angle = start_angle
	
	var weapon_damage_percent = float(specific_weapon_stats.get(&"weapon_damage_percentage", 1.0))
	var weapon_tags: Array[StringName] = specific_weapon_stats.get(&"tags", [])
	damage_on_contact = int(round(maxf(1.0, _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags))))

	var area_scale = float(specific_weapon_stats.get(&"area_scale", 1.0))
	self.scale = Vector2.ONE * area_scale

	var duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	var lifetime = float(specific_weapon_stats.get(&"base_lifetime", 3.0)) * duration_multiplier
	get_tree().create_timer(lifetime, true, false, true).timeout.connect(queue_free)
	
	_has_armor_pierce = specific_weapon_stats.get(&"has_armor_pierce", false)
	_has_arctic_vortex = specific_weapon_stats.get(&"has_arctic_vortex", false)
	
	if _has_arctic_vortex and is_instance_valid(pull_zone):
		_vortex_pull_strength = float(specific_weapon_stats.get(&"vortex_pull_strength", 50.0))
		var vortex_radius_mult = float(specific_weapon_stats.get(&"vortex_radius_multiplier", 1.2))
		pull_zone.scale = Vector2.ONE * vortex_radius_mult
		if pull_zone.collision_mask == 0:
			push_warning("Arctic Vortex WARNING: The PullZone Area2D has its Collision Mask set to '0'. It cannot detect enemies.")
		pull_zone.monitoring = true

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free(); return
	
	current_angle += rotation_speed * delta
	var offset = Vector2.RIGHT.rotated(current_angle) * orbit_radius
	global_position = owner_player.global_position + offset

	if _has_arctic_vortex and is_instance_valid(pull_zone):
		for body in pull_zone.get_overlapping_bodies():
			if body is BaseEnemy and is_instance_valid(body) and body.has_method("apply_external_force"):
				var direction_to_orb = (self.global_position - body.global_position).normalized()
				var pull_force = direction_to_orb * _vortex_pull_strength
				body.apply_external_force(pull_force * delta)

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body):
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead() or _enemies_hit_this_instance.has(enemy_target): return
		
		_deal_damage(enemy_target)
		_enemies_hit_this_instance.append(enemy_target)

func _deal_damage(enemy_target: BaseEnemy):
	var attack_stats = {}
	if _has_armor_pierce:
		attack_stats[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]] = 99999.0
	else:
		attack_stats[PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]] = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
	
	enemy_target.take_damage(damage_on_contact, owner_player, attack_stats)
	
	if specific_weapon_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
		var status_apps: Array = specific_weapon_stats.get(&"on_hit_status_applications", [])
		var global_status_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

		for app_data_res in status_apps:
			var app_data = app_data_res as StatusEffectApplicationData
			if is_instance_valid(app_data):
				var final_application_chance = app_data.application_chance + global_status_chance_add
				
				if randf() < clampf(final_application_chance, 0.0, 1.0):
					var id_override = &""
					if specific_weapon_stats.get(&"has_lingering_cold", false):
						id_override = "ft_lingering_cold_slow"
					
					enemy_target.status_effect_component.apply_effect(
						load(app_data.status_effect_resource_path) as StatusEffectData,
						self, 
						specific_weapon_stats,
						app_data.duration_override,
						app_data.potency_override,
						id_override
					)
