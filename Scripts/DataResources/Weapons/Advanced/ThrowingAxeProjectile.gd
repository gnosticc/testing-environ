# Path: res://Scripts/Weapons/Advanced/ThrowingAxeProjectile.gd
# ===================================================================
class_name ThrowingAxeProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _splinter_scene: PackedScene
var _direction: Vector2
var _speed: float
var _enemies_hit: Array[Node2D] = []
var _pierce_count: int = 0
var _ricochet_count: int = 0
var _is_returning: bool = false

func _ready():
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats, p_splinter_scene: PackedScene):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_splinter_scene = p_splinter_scene
	
	rotation = _direction.angle()
	
	_speed = 350.0 * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	_pierce_count = int(_specific_stats.get(&"pierce_count", 1))
	_ricochet_count = int(_specific_stats.get(&"ricochet_count", 0))
	
	var lifetime = 0.9 * _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = lifetime
	lifetime_timer.start()
	
	animated_sprite.play("fly")

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_lifetime_expired():
	if _is_returning:
		call_deferred("queue_free")
	else:
		_is_returning = true
		_direction *= -1.0
		rotation = _direction.angle()
		_enemies_hit.clear()
		lifetime_timer.start()

func _on_body_entered(body: Node2D):
	if not (body is BaseEnemy) or _enemies_hit.has(body):
		return
		
	var enemy = body as BaseEnemy
	if enemy.is_dead(): return
	
	_enemies_hit.append(enemy)
	
	var weapon_damage_percent = float(_specific_stats.get(&"weapon_damage_percentage", 1.8))
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")
	var base_damage = _owner_player_stats.get_calculated_base_damage(weapon_damage_percent)
	var calculated_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	
	if _specific_stats.get(&"has_execute_damage", false):
		var missing_health_percent = 1.0 - (enemy.current_health / enemy.max_health)
		var health_tier_size = float(_specific_stats.get(&"execute_health_tier", 0.10))
		var bonus_per_tier = float(_specific_stats.get(&"execute_bonus_per_tier", 0.05))
		
		var tiers = 0
		if health_tier_size > 0:
			tiers = floor(missing_health_percent / health_tier_size)
		
		var damage_multiplier = 1.0
		if tiers > 0:
			damage_multiplier = 1.0 + (tiers * bonus_per_tier)
			calculated_damage *= damage_multiplier
		
		# Enhanced debug print that always fires
		#print("--- AXE EXECUTE DEBUG ---")
		#print("  Target HP: %.1f / %.1f (%.1f%% missing)" % [enemy.current_health, enemy.max_health, missing_health_percent * 100])
		#print("  Tiers (at %.0f%% per tier): %d" % [health_tier_size * 100, tiers])
		#print("  Damage Multiplier: %.2fx" % damage_multiplier)
		#print("  Final Damage Dealt: %d" % int(round(calculated_damage)))
		#print("-------------------------")

	var owner_player = _owner_player_stats.get_parent()
	var is_crit = false
	if randf() < _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE):
		calculated_damage *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
		is_crit = true

	enemy.take_damage(int(round(calculated_damage)), owner_player, {}, weapon_tags) # Pass tags
	
	if is_crit and _specific_stats.get(&"has_wild_regeneration", false):
		_trigger_wild_regeneration()
	
	if _specific_stats.get(&"has_splintering_impact", false):
		call_deferred("_trigger_splintering_impact", enemy.global_position, owner_player, calculated_damage)

	if _specific_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy.status_effect_component):
		var status_apps: Array = _specific_stats.get(&"on_hit_status_applications", [])
		for app_data_res in status_apps:
			if app_data_res is StatusEffectApplicationData:
				var app_data = app_data_res as StatusEffectApplicationData
				enemy.status_effect_component.apply_effect(
					load(app_data.status_effect_resource_path),
					owner_player,
					_specific_stats
				)
	
	if _ricochet_count > 0:
		_ricochet_count -= 1
		var new_target = _find_new_ricochet_target(enemy.global_position)
		if is_instance_valid(new_target):
			_direction = (new_target.global_position - global_position).normalized()
			rotation = _direction.angle()
			return
	
	if _pierce_count > 0:
		_pierce_count -= 1
		return
		
	call_deferred("queue_free")

func _find_new_ricochet_target(hit_position: Vector2) -> Node2D:
	var best_target: Node2D = null
	var min_dist_sq = 200.0 * 200.0
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or _enemies_hit.has(enemy): continue
		var dist_sq = hit_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_target = enemy
	return best_target

func _trigger_wild_regeneration():
	var player_status_comp = _owner_player_stats.get_parent().get_node_or_null("StatusEffectComponent")
	if not is_instance_valid(player_status_comp): return
	
	var wild_regen_buff = load("res://DataResources/StatusEffects/wild_regeneration_buff.tres") as StatusEffectData
	if not is_instance_valid(wild_regen_buff): return
	
	var luck = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.LUCK)
	var healing_rate = max(4.0, float(int(luck) * 4))
	
	player_status_comp.apply_effect(wild_regen_buff, _owner_player_stats.get_parent(), {}, -1.0, healing_rate)

func _trigger_splintering_impact(position: Vector2, p_owner_player: PlayerCharacter, axe_hit_damage: float):
	if not is_instance_valid(_splinter_scene): return
	var splinter_count = 6
	var angle_step = TAU / float(splinter_count)
	
	var splinter_damage = int(round(axe_hit_damage * 0.25))

	for i in range(splinter_count):
		var splinter = _splinter_scene.instantiate() as SplinterProjectile
		get_tree().current_scene.add_child(splinter)
		splinter.global_position = position
		var dir = Vector2.RIGHT.rotated(i * angle_step + randf_range(-0.2, 0.2))
		splinter.initialize(dir, _owner_player_stats, p_owner_player, splinter_damage, _specific_stats)
