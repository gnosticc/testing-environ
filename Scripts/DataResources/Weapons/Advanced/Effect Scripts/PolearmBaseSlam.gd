# --- Path: res://Scripts/Weapons/Advanced/Effects/PolearmBaseSlam.gd ---
class_name PolearmBaseSlam
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer # NEW: Reference to the timer

var _specific_stats: Dictionary

func _ready():
	# Connect the timer's timeout signal to queue_free
	lifetime_timer.timeout.connect(queue_free)

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats):
	# The animation now just plays for visual effect.
	animated_sprite.play("slam")
	# The timer now controls how long the slam effect exists.
	lifetime_timer.start()
	
	# Deal damage once to all enemies in the area
	await get_tree().physics_frame
	var weapon_tags: Array[StringName] = []
	if _specific_stats.has("tags"):
		weapon_tags = _specific_stats.get("tags")

	var base_damage = p_player_stats.get_calculated_base_damage(0.5)
	var damage = p_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	var parent = get_parent()
	if parent is BaseEnemy and is_instance_valid(parent) and not parent.is_dead():
		parent.take_damage(int(round(damage)), p_player_stats.get_parent())
