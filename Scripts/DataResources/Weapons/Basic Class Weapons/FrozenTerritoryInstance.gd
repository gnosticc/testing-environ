# FrozenTerritoryInstance.gd
# This script controls a single orbiting instance of Frozen Territory.
# CORRECTED: The initialize function now correctly reads the `base_lifetime`
# value from the stats dictionary to ensure proper despawning.
class_name FrozenTerritoryInstance
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

# --- Orbit Properties ---
var owner_player: PlayerCharacter
var orbit_radius: float = 75.0
var rotation_speed: float = 1.0 # Radians per second
var current_angle: float = 0.0

# --- Attack Properties ---
var damage_on_contact: int = 5
var status_effect_to_apply: StatusEffectData = null
var _enemies_hit: Array[Node2D] = []

func _ready():
	var collision_shape = get_node_or_null("CollisionShape2D")
	if is_instance_valid(collision_shape):
		collision_shape.disabled = false
	
	body_entered.connect(_on_body_entered)

# This function is called by the controller that spawns this instance
func initialize(p_owner: PlayerCharacter, p_stats: Dictionary, start_angle: float):
	owner_player = p_owner
	
	orbit_radius = float(p_stats.get("orbit_radius", 75.0))
	
	var rotation_duration = float(p_stats.get("rotation_duration", 3.0))
	if rotation_duration > 0:
		rotation_speed = TAU / rotation_duration
	
	current_angle = start_angle
	
	var player_stats = owner_player.get_node_or_null("PlayerStats") as PlayerStats
	if is_instance_valid(player_stats):
		var player_base_damage = float(player_stats.get_current_base_numerical_damage())
		var player_global_mult = float(player_stats.get_current_global_damage_multiplier())
		var weapon_damage_percent = float(p_stats.get("weapon_damage_percentage", 0.5))
		damage_on_contact = int(round(player_base_damage * weapon_damage_percent * player_global_mult))
	
	var status_effect_path = p_stats.get("status_effect_path", "")
	if ResourceLoader.exists(status_effect_path):
		status_effect_to_apply = load(status_effect_path)

	# --- CORRECTED LIFETIME LOGIC ---
	# The instance now uses the `base_lifetime` passed from the blueprint.
	var lifetime = float(p_stats.get("base_lifetime", 3.0))
	var lifetime_timer = get_tree().create_timer(lifetime, true, false, true)
	lifetime_timer.timeout.connect(queue_free)

func _physics_process(delta: float):
	if not is_instance_valid(owner_player):
		queue_free()
		return
	
	current_angle += rotation_speed * delta
	
	var offset = Vector2.RIGHT.rotated(current_angle) * orbit_radius
	global_position = owner_player.global_position + offset

func _on_body_entered(body: Node2D):
	if _enemies_hit.has(body): return

	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return
		
		_enemies_hit.append(enemy_target)
		
		enemy_target.take_damage(damage_on_contact, owner_player)
		
		if is_instance_valid(status_effect_to_apply):
			var enemy_status_comp = enemy_target.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
			if is_instance_valid(enemy_status_comp):
				enemy_status_comp.apply_effect(status_effect_to_apply, owner_player)
