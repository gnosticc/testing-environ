# LesserSpiritInstance.gd
# Controls a single orbiting spirit that auto-attacks nearby enemies.
# CORRECTED: Now properly instantiates and fires the SpiritBolt projectile.

class_name LesserSpiritInstance
extends Node2D

@export var projectile_scene: PackedScene

# --- Orbit Properties ---
var owner_player: PlayerCharacter
var _owner_player_stats: PlayerStats
var specific_weapon_stats: Dictionary
var orbit_radius: float = 60.0
var rotation_speed: float = 1.5
var current_angle: float = 0.0

# --- Attack Properties ---
var attack_cooldown: float = 2.0
var attack_range: float = 300.0

var _attack_cooldown_timer: Timer

# --- Visual Nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready():
	# Initialization is handled by the initialize function
	pass

func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, start_angle: float):
	owner_player = p_owner
	_owner_player_stats = owner_player.player_stats
	specific_weapon_stats = p_stats

	if not is_instance_valid(owner_player) or not is_instance_valid(_owner_player_stats):
		push_error("LesserSpiritInstance ERROR: Player or PlayerStats invalid. Queueing free."); queue_free(); return
	if not is_instance_valid(animated_sprite):
		push_warning("LesserSpiritInstance WARNING: AnimatedSprite2D missing.")

	# Setup the attack timer
	if not is_instance_valid(_attack_cooldown_timer):
		_attack_cooldown_timer = Timer.new()
		_attack_cooldown_timer.name = "AttackTimer"
		add_child(_attack_cooldown_timer)
		_attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout)
	
	update_stats(p_stats) # Apply initial stats
	current_angle = start_angle
	_attack_cooldown_timer.start()

func update_stats(p_stats: Dictionary):
	if not p_stats.is_empty():
		specific_weapon_stats = p_stats
	if not is_instance_valid(_owner_player_stats): return

	orbit_radius = float(specific_weapon_stats.get(&"orbit_radius", 60.0))
	var rotation_duration = float(specific_weapon_stats.get(&"rotation_duration", 4.0))
	if rotation_duration > 0: rotation_speed = TAU / rotation_duration
	
	attack_cooldown = float(specific_weapon_stats.get(&"attack_cooldown", 2.0))
	attack_range = float(specific_weapon_stats.get(&"attack_range", 300.0))
	
	_attack_cooldown_timer.wait_time = attack_cooldown
	_apply_visual_scale()

func _apply_visual_scale():
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
	if not is_instance_valid(owner_player) or not is_instance_valid(projectile_scene): return
		
	var target = owner_player._find_nearest_enemy(self.global_position)
	if is_instance_valid(target) and self.global_position.distance_to(target.global_position) <= attack_range:
		_fire_at_target(target)

func _fire_at_target(target: Node2D):
	if not is_instance_valid(projectile_scene):
		push_error("LesserSpiritInstance ERROR: projectile_scene is not set!"); return
		
	var direction_to_target = (target.global_position - global_position).normalized()
	
	# --- CORRECTED LOGIC ---
	# 1. Instantiate the projectile scene.
	var bolt = projectile_scene.instantiate()
	if not is_instance_valid(bolt):
		push_error("LesserSpiritInstance ERROR: Failed to instantiate projectile bolt!"); return

	# 2. Add it to a container so it exists independently.
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(bolt)
	else:
		get_tree().current_scene.add_child(bolt) # Fallback
		
	bolt.global_position = self.global_position
	
	# 3. Pass all necessary stats to the projectile itself. The projectile will handle the damage.
	if bolt.has_method("set_attack_properties"):
		# We pass the spirit's 'specific_weapon_stats' directly to the projectile.
		(bolt as Node2D).set_attack_properties(direction_to_target, specific_weapon_stats, _owner_player_stats)
	else:
		push_warning("LesserSpiritInstance: SpiritBolt instance is missing 'set_attack_properties' method.")
