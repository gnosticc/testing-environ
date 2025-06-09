# LesserSpirit.gd
# Controls the behavior of a summoned Lesser Spirit.
# It follows the player and periodically fires at the nearest enemy.
class_name LesserSpirit
extends CharacterBody2D

@export var projectile_scene: PackedScene

# --- Behavior Stats ---
var follow_distance: float = 50.0
var movement_speed: float = 120.0
var attack_cooldown: float = 2.5
var projectile_damage: int = 8
var projectile_speed: float = 350.0

# --- References ---
var owner_player: PlayerCharacter
var attack_cooldown_timer: Timer

func _ready():
	# The spirit's stats and references are passed in by the WeaponManager.
	# The ready function is intentionally simple.
	pass

func initialize(p_owner: PlayerCharacter, p_stats: Dictionary):
	owner_player = p_owner
	
	# Read stats from the dictionary provided by the WeaponManager
	follow_distance = float(p_stats.get("follow_distance", 50.0))
	movement_speed = float(p_stats.get("movement_speed", 120.0))
	attack_cooldown = float(p_stats.get("attack_cooldown", 2.5))
	
	var player_stats = owner_player.get_node_or_null("PlayerStats") as PlayerStats
	if is_instance_valid(player_stats):
		var player_base_damage = float(player_stats.get_current_base_numerical_damage())
		var player_global_mult = float(player_stats.get_current_global_damage_multiplier())
		var weapon_damage_percent = float(p_stats.get("weapon_damage_percentage", 0.6))
		projectile_damage = int(round(player_base_damage * weapon_damage_percent * player_global_mult))
	
	# Set up the attack timer
	attack_cooldown_timer = Timer.new()
	attack_cooldown_timer.name = "SpiritAttackTimer"
	attack_cooldown_timer.wait_time = attack_cooldown
	attack_cooldown_timer.one_shot = false
	add_child(attack_cooldown_timer)
	attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout)
	attack_cooldown_timer.start()

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free()
		return
	
	# Move towards a point near the player
	var direction_to_player = (owner_player.global_position - global_position)
	if direction_to_player.length() > follow_distance:
		velocity = direction_to_player.normalized() * movement_speed
	else:
		velocity = Vector2.ZERO
		
	move_and_slide()

func _on_attack_cooldown_timeout():
	if not is_instance_valid(owner_player) or not is_instance_valid(projectile_scene):
		return
		
	var target = owner_player._find_nearest_enemy()
	if is_instance_valid(target):
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
