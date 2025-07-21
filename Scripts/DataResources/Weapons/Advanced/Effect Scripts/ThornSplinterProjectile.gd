# File: ThornSplinterProjectile.gd
# Attach to: ThornSplinterProjectile.tscn (root Area2D)
# Purpose: Controls the small, damaging splinters from Thorn Nova.
# REVISED: Added _owner_player_stats declaration and logic to read scale from blueprint.

class_name ThornSplinterProjectile
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _direction: Vector2
var _speed: float = 400.0
var _damage: int

var _owner_player: PlayerCharacter
var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats # Declaration added

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

func initialize(p_direction: Vector2, p_stats: Dictionary, p_player_stats: PlayerStats):
	_direction = p_direction.normalized()
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats # Assign the variable
	_owner_player = p_player_stats.get_parent()

	rotation = _direction.angle()
	
	# Calculate damage based on the splinter-specific stat in the blueprint
	var splinter_damage_percent = float(_specific_stats.get("splinter_damage_percentage", 0.5))
	var weapon_tags: Array[StringName] = _specific_stats.get("tags", [])
	var base_damage = _owner_player_stats.get_calculated_base_damage(splinter_damage_percent)
	var final_damage = _owner_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	_damage = final_damage	
	# Apply scale from blueprint
	var splinter_scale = float(_specific_stats.get("splinter_scale", 0.6))
	self.scale = Vector2.ONE * splinter_scale
	
	lifetime_timer.start()
	animated_sprite.play("fly")

func _physics_process(delta: float):
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")
		body.take_damage(_damage, _owner_player, {}, weapon_tags) # Pass tags
		queue_free() # Destroy on first hit
