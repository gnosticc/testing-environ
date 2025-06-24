# File: res/Scripts/Weapons/Summons/ProtectiveDustCloud.gd
# FIXED: The crash is resolved by correctly getting the player's StatusEffectComponent.
# ADDED: Debug prints to show armor calculation.
# ADDED: Now accepts a radius to control its size.

class_name ProtectiveDustCloud
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var refresh_timer: Timer = $RefreshTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _player_node: PlayerCharacter
var _buff_data: StatusEffectData

func _ready():
	lifetime_timer.timeout.connect(queue_free)
	refresh_timer.timeout.connect(_on_refresh_tick)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	animated_sprite.play("default")
	
# The initialize function now accepts a radius parameter.
func initialize(player: PlayerCharacter, buff_data: StatusEffectData, p_radius: float):
	_player_node = player
	_buff_data = buff_data
	
	# Set the size of the cloud's collision shape based on the passed-in radius.
	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = p_radius
	
	lifetime_timer.start()
	
	# Check if player is already inside when the cloud spawns
	await get_tree().physics_frame
	if get_overlapping_bodies().has(_player_node):
		_on_body_entered(_player_node)

func _on_refresh_tick():
	if not is_instance_valid(_player_node): return
	# The timer only runs if the player is inside, so we can just re-apply the buff.
	_apply_buff()

func _on_body_entered(body: Node2D):
	if body == _player_node:
		refresh_timer.start()
		_apply_buff()

func _on_body_exited(body: Node2D):
	if body == _player_node:
		refresh_timer.stop()

func _apply_buff():
	# CRASH FIX: The StatusEffectComponent is a child of the player node, not a property.
	# We must get it using get_node().
	var player_status_comp = _player_node.get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if not is_instance_valid(player_status_comp):
		push_error("ProtectiveDustCloud ERROR: Player is missing a valid StatusEffectComponent node.")
		return
		
	if not is_instance_valid(_player_node.player_stats):
		push_error("ProtectiveDustCloud ERROR: Player is missing a valid PlayerStats node.")
		return

	# DEBUG PRINT: Show the calculation for the armor buff.
	var luck = _player_node.player_stats.get_final_stat(PlayerStatKeys.Keys.LUCK)
	var armor_from_luck = min(15, int(luck)) # Cap bonus from luck at 15
	var total_armor_to_grant = 10 + armor_from_luck
	
	print("Protective Dust: Applying buff. Base Armor: 10, Player Luck: ", int(luck), ", Bonus Armor from Luck: ", armor_from_luck, ", Total Armor Granted: ", total_armor_to_grant)

	# The potency_override is used to pass the calculated armor value to the status effect.
	player_status_comp.apply_effect(_buff_data, _player_node, {}, 5.0, float(total_armor_to_grant))
