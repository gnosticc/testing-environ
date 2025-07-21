# --- Path: res://Scripts/Weapons/Advanced/Summons/Caltrop.gd ---
class_name Caltrop
extends Area2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _damage: int
var _owner_player: PlayerCharacter
var _specific_stats: Dictionary


func _ready():
	collision_shape.disabled = true
	animation_player.animation_finished.connect(_on_animation_finished)
	lifetime_timer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)
	
func initialize(p_damage: int, p_owner_player: PlayerCharacter):
	_damage = p_damage
	_owner_player = p_owner_player
	animation_player.play("deploy")

func _on_animation_finished(_anim_name):
	collision_shape.disabled = false
	lifetime_timer.start()
	
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _on_body_entered(body: Node2D):
	if body is BaseEnemy and is_instance_valid(body) and not body.is_dead():
		var weapon_tags: Array[StringName] = []
		if _specific_stats.has("tags"):
			weapon_tags = _specific_stats.get("tags")

		body.take_damage(_damage, _owner_player, {}, weapon_tags) # Now safely passing the correct type
		queue_free()
