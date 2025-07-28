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
var _weapon_manager: WeaponManager # Reference to call back for cooldown reduction

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

	# NEW: Connect to the stats_recalculated signal.
	# This ensures the summon updates its stats whenever the player's stats change.
	if _owner_player_stats and not _owner_player_stats.is_connected("stats_recalculated", update_stats):
		_owner_player_stats.stats_recalculated.connect(update_stats)

	update_stats()
	current_angle = start_angle
	if _attack_cooldown_timer.is_stopped():
		_attack_cooldown_timer.start()

# NEW: Add a notification function to disconnect the signal on deletion.
# This is crucial to prevent memory leaks when the summon is removed from the scene.
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_owner_player_stats) and _owner_player_stats.is_connected("stats_recalculated", update_stats):
			_owner_player_stats.stats_recalculated.disconnect(update_stats)

# MODIFIED: This function now accepts optional arguments from the stats_recalculated signal.
func update_stats(p_arg1 = {}, _p_arg2 = 0.0):
	# This function is now called by the stats_recalculated signal (with floats)
	# AND directly by the WeaponManager (with a Dictionary).
	# We only update specific_weapon_stats if a dictionary is passed.
	if p_arg1 is Dictionary and not p_arg1.is_empty():
		specific_weapon_stats = p_arg1.duplicate(true)
		
	if not is_instance_valid(_owner_player_stats): return

	orbit_radius = float(specific_weapon_stats.get(&"orbit_radius", 60.0))
	var rotation_duration = float(specific_weapon_stats.get(&"rotation_duration", 4.0))
	if rotation_duration > 0: rotation_speed = TAU / rotation_duration
	
	attack_range = float(specific_weapon_stats.get(&"attack_range", 180.0))

	# --- CORRECTED COOLDOWN LOGIC ---
	# 1. Always start with the base cooldown value from the weapon's stats.
	var base_cooldown = float(specific_weapon_stats.get(&"attack_cooldown", 2.0))
	
	# 2. Get the player's global multipliers.
	var global_attack_speed_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	var global_cooldown_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_COOLDOWN_REDUCTION_MULT)
	
	# 3. Calculate the final cooldown by applying the multipliers.
	var final_cooldown = base_cooldown
	if global_attack_speed_mult > 0.01:
		final_cooldown /= global_attack_speed_mult
	if global_cooldown_mult > 0.01:
		final_cooldown *= global_cooldown_mult
		
	_attack_cooldown_timer.wait_time = maxf(0.1, final_cooldown)
	# --- END OF CORRECTION ---

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
	if not is_instance_valid(target): return
	var target_id = target.get_instance_id()
	# This timer-based approach prevents the 'Cannot convert argument' error.
	# The 'target' reference is only used when the timer is created. The firing
	# function will then check if the target is still valid when it executes.
	# Bind the instance ID instead of the node itself to prevent errors if the target is destroyed.
	get_tree().create_timer(0.0).timeout.connect(_fire_at_target_by_id.bind(target_id))
	get_tree().create_timer(0.05).timeout.connect(_fire_at_target_by_id.bind(target_id))
	get_tree().create_timer(0.1).timeout.connect(_fire_at_target_by_id.bind(target_id))

# NEW: This function safely retrieves the target from its ID before firing.
func _fire_at_target_by_id(target_id: int):
	var target = instance_from_id(target_id) as Node2D
	# The original _fire_at_target function already handles invalid targets,
	# so we can just call it directly.
	_fire_at_target(target)

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
		(bolt as Node2D).set_attack_properties(direction_to_target, specific_weapon_stats, _owner_player_stats, _weapon_manager)
