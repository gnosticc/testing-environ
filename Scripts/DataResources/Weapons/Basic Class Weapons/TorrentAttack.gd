# TorrentAttack.gd
# Behavior for the Druid's Torrent.
# A stationary AoE that deals ticking damage to enemies inside it.
class_name TorrentAttack
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var damage_tick_timer: Timer = get_node_or_null("DamageTickTimer") as Timer

var _specific_stats: Dictionary = {}
var _owner_player_stats: PlayerStats = null
var _damage_per_tick: int = 5
var _enemies_in_area: Array[BaseEnemy] = []

func _ready():
	if not is_instance_valid(lifetime_timer) or not is_instance_valid(damage_tick_timer):
		print("ERROR (TorrentAttack): Timer nodes are missing!"); queue_free(); return
		
	lifetime_timer.timeout.connect(queue_free)
	damage_tick_timer.timeout.connect(_on_damage_tick)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if is_instance_valid(animated_sprite):
		animated_sprite.play("erupt") # Assuming a looping animation named 'erupt'

func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	
	if not is_instance_valid(_owner_player_stats): queue_free(); return

	# --- Calculate Damage ---
	var player_base_damage = float(_owner_player_stats.get_current_base_numerical_damage())
	var player_global_mult = float(_owner_player_stats.get_current_global_damage_multiplier())
	var weapon_damage_percent = float(_specific_stats.get("weapon_damage_percentage", 0.6))
	_damage_per_tick = int(round(player_base_damage * weapon_damage_percent * player_global_mult))
	
	# --- Set Scale ---
	var area_scale = float(_specific_stats.get("area_scale", 1.0))
	var player_aoe_mult = _owner_player_stats.get_current_aoe_area_multiplier()
	self.scale = Vector2.ONE * area_scale * player_aoe_mult
	
	# --- Set Timers ---
	var base_lifetime = float(_specific_stats.get("base_lifetime", 3.0))
	var duration_mult = _owner_player_stats.get_current_effect_duration_multiplier()
	lifetime_timer.wait_time = base_lifetime * duration_mult
	lifetime_timer.start()
	
	var tick_interval = float(_specific_stats.get("damage_tick_interval", 0.5))
	damage_tick_timer.wait_time = tick_interval
	# The first tick happens on body_entered, so the timer starts then.

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and not _enemies_in_area.has(body):
		var enemy = body as BaseEnemy
		if enemy.is_dead(): return
		
		# First hit is immediate
		enemy.take_damage(_damage_per_tick, _owner_player_stats.get_parent())
		_enemies_in_area.append(enemy)
		
		# If the tick timer isn't running, start it now.
		if damage_tick_timer.is_stopped():
			damage_tick_timer.start()

func _on_body_exited(body: Node2D):
	if body is BaseEnemy and _enemies_in_area.has(body):
		_enemies_in_area.erase(body)
		
		# If no more enemies are in the area, stop the tick timer to save performance
		if _enemies_in_area.is_empty():
			damage_tick_timer.stop()

func _on_damage_tick():
	if _enemies_in_area.is_empty(): return
	
	# Create a copy for safe iteration, in case an enemy dies and is removed
	for enemy in _enemies_in_area.duplicate():
		if is_instance_valid(enemy) and not enemy.is_dead():
			enemy.take_damage(_damage_per_tick, _owner_player_stats.get_parent())
