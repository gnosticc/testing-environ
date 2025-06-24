# File: res/Scripts/Weapons/TorrentAttack.gd
# REVISED: Now handles Maelstrom wave spawning independently of enemies being present.

class_name TorrentAttack
extends Area2D

const MAELSTROM_WAVE_SCENE = preload("res://Scenes/Weapons/Projectiles/TorrentWave.tscn")
const SLOW_STATUS_DATA = preload("res://DataResources/StatusEffects/slow_status.tres")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var damage_tick_timer: Timer = $DamageTickTimer

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _damage_per_tick: int
var _enemies_in_area: Array[BaseEnemy] = []
var _unique_enemies_hit: Array[BaseEnemy] = []

func _ready():
	lifetime_timer.timeout.connect(_on_lifetime_expired)
	damage_tick_timer.timeout.connect(_on_damage_tick)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	animated_sprite.play("erupt")

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats

	if not is_instance_valid(_owner_player_stats): queue_free(); return

	var weapon_damage_percent = float(_specific_stats.get(&"weapon_damage_percentage", 0.6))
	var weapon_tags: Array[StringName] = _specific_stats.get(&"tags", [])
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
	_damage_per_tick = int(round(maxf(1.0, calculated_damage_float)))
	
	var base_area_scale = float(_specific_stats.get(&"area_scale", 1.0))
	var player_aoe_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	scale = Vector2.ONE * base_area_scale * player_aoe_multiplier
	
	var base_lifetime = float(_specific_stats.get(&"base_lifetime", 3.0))
	var effect_duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = base_lifetime * effect_duration_multiplier
	lifetime_timer.start()
	
	var tick_interval = float(_specific_stats.get(&"damage_tick_interval", 0.5))
	damage_tick_timer.wait_time = tick_interval
	
	if _specific_stats.get(&"has_maelstrom", false):
		damage_tick_timer.start()

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not _enemies_in_area.has(body):
		var enemy = body as BaseEnemy
		if enemy.is_dead(): return
		
		if not _unique_enemies_hit.has(enemy):
			_unique_enemies_hit.append(enemy)

		_apply_damage_and_effects(enemy)
		_enemies_in_area.append(enemy)
		
		if not _specific_stats.get(&"has_maelstrom", false) and damage_tick_timer.is_stopped():
			damage_tick_timer.start()

func _on_body_exited(body: Node2D):
	if body is BaseEnemy and _enemies_in_area.has(body):
		_enemies_in_area.erase(body)
		
		if not _specific_stats.get(&"has_maelstrom", false) and _enemies_in_area.is_empty():
			damage_tick_timer.stop()

func _on_damage_tick():
	if _specific_stats.get(&"has_maelstrom", false):
		_spawn_maelstrom_wave()
		
	if _enemies_in_area.is_empty(): return

	for enemy in _enemies_in_area.duplicate():
		if is_instance_valid(enemy) and not enemy.is_dead():
			_apply_damage_and_effects(enemy)
		else:
			_enemies_in_area.erase(enemy)
			
func _apply_damage_and_effects(enemy: BaseEnemy):
	var owner_player_char = _owner_player_stats.get_parent()
	var attack_stats = {
		PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
	}
	enemy.take_damage(_damage_per_tick, owner_player_char, attack_stats)
	
	if _specific_stats.get(&"has_drenching_force", false) and is_instance_valid(enemy.status_effect_component):
		enemy.status_effect_component.apply_effect(SLOW_STATUS_DATA, owner_player_char, {}, 1.0)

func _spawn_maelstrom_wave():
	if not is_instance_valid(MAELSTROM_WAVE_SCENE): return
		
	var wave_instance = MAELSTROM_WAVE_SCENE.instantiate()
	get_tree().current_scene.add_child(wave_instance)
	wave_instance.global_position = self.global_position
	
	var wave_damage = int(round(_damage_per_tick * 1.0))
	var random_direction = Vector2.RIGHT.rotated(randf_range(0, TAU))
	
	if wave_instance.has_method("initialize"):
		wave_instance.initialize(wave_damage, random_direction, _owner_player_stats)

func _on_lifetime_expired():
	if _specific_stats.get(&"has_devastation", false):
		var num_ticks = lifetime_timer.wait_time / damage_tick_timer.wait_time
		var total_damage = int(round(_damage_per_tick * num_ticks))
		
		for enemy in _unique_enemies_hit:
			if is_instance_valid(enemy) and not enemy.is_dead():
				var owner_player_char = _owner_player_stats.get_parent()
				var attack_stats = {
					PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
				}
				enemy.take_damage(total_damage, owner_player_char, attack_stats)
	
	queue_free()
