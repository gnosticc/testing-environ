# LesserSpiritInstance.gd
# Controls a single orbiting spirit that auto-attacks nearby enemies.
class_name LesserSpiritInstance
extends Node2D

@export var projectile_scene: PackedScene

# --- Orbit Properties ---
var owner_player: PlayerCharacter
var orbit_radius: float = 60.0
var rotation_speed: float = 1.5 # Radians per second
var current_angle: float = 0.0

# --- Attack Properties ---
var attack_cooldown: float = 2.0
var attack_range: float = 300.0
var projectile_damage: int = 7
var projectile_speed: float = 400.0

var _attack_cooldown_timer: Timer

func _ready():
	_attack_cooldown_timer = Timer.new()
	_attack_cooldown_timer.name = "AttackTimer"
	add_child(_attack_cooldown_timer)
	_attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout)

func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, start_angle: float):
	owner_player = p_owner
	
	var player_stats = owner_player.get_node_or_null("PlayerStats") as PlayerStats
	if not is_instance_valid(player_stats): queue_free(); return
	
	orbit_radius = float(p_stats.get("orbit_radius", 60.0))
	var rotation_duration = float(p_stats.get("rotation_duration", 4.0))
	if rotation_duration > 0: rotation_speed = TAU / rotation_duration
	
	attack_cooldown = float(p_stats.get("attack_cooldown", 2.0))
	attack_range = float(p_stats.get("attack_range", 300.0))
	
	var weapon_damage_percent = float(p_stats.get("weapon_damage_percentage", 0.8))
	projectile_damage = int(round(player_stats.get_current_base_numerical_damage() * weapon_damage_percent * player_stats.get_current_global_damage_multiplier()))
	projectile_speed = float(p_stats.get("projectile_speed", 400.0)) * player_stats.get_current_projectile_speed_multiplier()
	
	current_angle = start_angle
	
	_attack_cooldown_timer.wait_time = attack_cooldown
	_attack_cooldown_timer.start()

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free(); return
	
	current_angle += rotation_speed * delta
	var offset = Vector2.RIGHT.rotated(current_angle) * orbit_radius
	global_position = owner_player.global_position + offset

func _on_attack_cooldown_timeout():
	if not is_instance_valid(owner_player) or not is_instance_valid(projectile_scene): return
		
	var target = owner_player._find_nearest_enemy(self.global_position) # Find enemy closest to the spirit
	if is_instance_valid(target) and self.global_position.distance_to(target.global_position) <= attack_range:
		_fire_at_target(target)

func _fire_at_target(target: Node2D):
	var direction_to_target = (target.global_position - global_position).normalized()
	
	var bolt = projectile_scene.instantiate() as SpiritBolt
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container):
		attacks_container.add_child(bolt)
	else:
		get_tree().current_scene.add_child(bolt)
		
	bolt.global_position = self.global_position
	bolt.direction = direction_to_target
	bolt.damage = projectile_damage
	bolt.speed = projectile_speed
	bolt.owner_player = owner_player
