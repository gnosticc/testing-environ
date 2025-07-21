# File: EldritchOrb.gd
# Attach to: EldritchOrb.tscn
# --------------------------------------------------------------------
class_name EldritchOrb
extends Area2D

@onready var pulse_timer: Timer = $PulseTimer
@onready var lifetime_timer: Timer = $LifetimeTimer

const SPLINTER_SCENE = preload("res://Scenes/Weapons/Advanced/Effect Scenes/EldritchOrbSplinter.tscn")

var _direction: Vector2
var _speed: float
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _parent_echo_instance_id: int

func _ready():
	pulse_timer.timeout.connect(_fire_splinter_volley)
	lifetime_timer.timeout.connect(queue_free)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats, p_parent_echo_id: int):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_parent_echo_instance_id = p_parent_echo_id
	
	_speed = float(p_stats.get("eldritch_orb_velocity", 80.0))
	pulse_timer.wait_time = float(p_stats.get("eldritch_orb_pulse_interval", 0.5))
	lifetime_timer.wait_time = float(p_stats.get("eldritch_orb_lifetime", 4.0))
	
	var base_scale = float(p_stats.get("eldritch_orb_scale", 1.0))
	var global_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2.ONE * base_scale * global_size_mult
	
	pulse_timer.start()
	lifetime_timer.start()

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _fire_splinter_volley():
	var angle_step = TAU / 8.0
	for i in range(8):
		var splinter = SPLINTER_SCENE.instantiate()
		get_tree().current_scene.add_child(splinter)
		splinter.global_position = self.global_position
		var direction = Vector2.RIGHT.rotated(i * angle_step)
		splinter.initialize(direction, _specific_stats, _owner_player_stats, _parent_echo_instance_id)
