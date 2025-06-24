# File: res/Scripts/DataResources/Weapons/Basic Class Weapons/LesserSpiritInstance.gd
# REVISED: Ethereal Barrage timer logic is now self-contained and safe.

class_name LesserSpiritInstance
extends Node2D

@export var projectile_scene: PackedScene

var owner_player: PlayerCharacter
var _owner_player_stats: PlayerStats
var specific_weapon_stats: Dictionary
var orbit_radius: float = 60.0
var rotation_speed: float = 1.5
var current_angle: float = 0.0
var attack_cooldown: float = 2.0
var attack_range: float = 180.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _attack_cooldown_timer: Timer

func _ready():
	# Setup is handled in initialize
	pass

func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, start_angle: float):
	owner_player = p_owner
	_owner_player_stats = owner_player.player_stats
	specific_weapon_stats = p_stats

	if not is_instance_valid(owner_player) or not is_instance_valid(_owner_player_stats):
		push_error("LesserSpiritInstance ERROR: Player or PlayerStats invalid. Queueing free."); queue_free(); return
	
	if not is_instance_valid(_attack_cooldown_timer):
		_attack_cooldown_timer = Timer.new()
		_attack_cooldown_timer.name = "AttackTimer"
		add_child(_attack_cooldown_timer)
		_attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout)
	
	update_stats()
	current_angle = start_angle
	if _attack_cooldown_timer.is_stopped():
		_attack_cooldown_timer.start()

func update_stats(new_stats: Dictionary = {}):
	if not new_stats.is_empty():
		specific_weapon_stats = new_stats.duplicate(true)
	if not is_instance_valid(_owner_player_stats): return

	orbit_radius = float(specific_weapon_stats.get(&"orbit_radius", 60.0))
	var rotation_duration = float(specific_weapon_stats.get(&"rotation_duration", 4.0))
	if rotation_duration > 0: rotation_speed = TAU / rotation_duration
	
	attack_cooldown = float(specific_weapon_stats.get(&"attack_cooldown", 2.0))
	attack_range = float(specific_weapon_stats.get(&"attack_range", 180.0))
	
	var final_cooldown = attack_cooldown / _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	_attack_cooldown_timer.wait_time = maxf(0.1, final_cooldown)

	var base_scale_x = float(specific_weapon_stats.get(&"inherent_visual_scale_x", 0.08))
	var base_scale_y = float(specific_weapon_stats.get(&"inherent_visual_scale_y", 0.08))
	var player_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	self.scale = Vector2(base_scale_x * player_size_mult, base_scale_y * player_size_mult)

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free(); return
	
	current_angle += rotation_speed * delta
	var offset = Vector2.RIGHT.rotated(current_angle) * orbit_radius
	global_position = owner_player.global_position + offset

func _on_attack_cooldown_timeout():
	if not is_instance_valid(owner_player): return
		
	var target = owner_player._find_nearest_enemy(self.global_position)
	if is_instance_valid(target) and self.global_position.distance_to(target.global_position) <= attack_range:
		if specific_weapon_stats.get(&"has_ethereal_barrage", false):
			var proc_chance = float(specific_weapon_stats.get(&"ethereal_barrage_proc_chance", 0.0))
			if randf() < proc_chance:
				# Use call_deferred to avoid potential issues if called from a sensitive context
				call_deferred("_fire_ethereal_barrage", target)
				return
		
		_fire_at_target(target)

func _fire_ethereal_barrage(target: Node2D):
	# This timer-based approach prevents the 'Cannot convert argument' error.
	# The 'target' reference is only used when the timer is created. The firing
	# function will then check if the target is still valid when it executes.
	get_tree().create_timer(0.0).timeout.connect(_fire_at_target.bind(target))
	get_tree().create_timer(0.05).timeout.connect(_fire_at_target.bind(target))
	get_tree().create_timer(0.1).timeout.connect(_fire_at_target.bind(target))

func _fire_at_target(target: Node2D):
	# CORE FIX: Check if the target is still valid before firing.
	if not is_instance_valid(target) or (target is BaseEnemy and target.is_dead()):
		return

	if not is_instance_valid(projectile_scene): return
		
	var direction_to_target = (target.global_position - global_position).normalized()
	var bolt = projectile_scene.instantiate()
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(bolt)
	else:
		get_tree().current_scene.add_child(bolt)
		
	bolt.global_position = self.global_position
	
	if bolt.has_method("set_attack_properties"):
		(bolt as Node2D).set_attack_properties(direction_to_target, specific_weapon_stats, _owner_player_stats)
