# DaggerStrikeController.gd
# REFACTORED: Now a generic sequence player. It reads an "attack_sequence" array
# from its stats and executes each hit with the defined timing and properties.
# CORRECTED: Now reads `base_lifetime` from its stats dictionary, not its parent.
class_name DaggerStrikeController
extends Node2D

@export var hitbox_scene: PackedScene

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _base_direction: Vector2

var _hit_index: int = 0
var _attack_sequence: Array = []

func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats
	_owner_player_stats = p_player_stats
	_base_direction = direction
	_attack_sequence = _specific_stats.get("attack_sequence", [])

	if not is_instance_valid(hitbox_scene):
		print("ERROR: DaggerStrikeController is missing its Hitbox Scene!"); queue_free(); return
	if _attack_sequence.is_empty():
		print("ERROR: DaggerStrikeController has an empty attack_sequence!"); queue_free(); return

	# --- Handle Visuals ---
	if is_instance_valid(animated_sprite):
		# Apply scale and rotation
		var area_scale = float(_specific_stats.get("attack_area_scale", 1.0))
		animated_sprite.scale = Vector2.ONE * area_scale
		if direction != Vector2.ZERO:
			self.rotation = direction.angle()
			if abs(direction.angle()) > PI / 2.0:
				animated_sprite.flip_v = true
		
		# Play the attack animation
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("slash"):
			animated_sprite.play("slash")
		else:
			print_debug("WARNING: 'slash' animation not found in DaggerStrikeController's sprite.")
	
	# --- Start the Attack Sequence ---
	_execute_next_hit()

	# --- CORRECTED LIFETIME LOGIC ---
	# Cleanup timer for the entire controller, reads from the stats dictionary.
	var total_lifetime = float(_specific_stats.get("base_lifetime", 0.3))
	var cleanup_timer = get_tree().create_timer(total_lifetime, true, false, true)
	cleanup_timer.timeout.connect(queue_free)


func _execute_next_hit():
	if _hit_index >= _attack_sequence.size():
		return # Sequence complete

	var current_hit_data = _attack_sequence[_hit_index]
	var delay = float(current_hit_data.get("delay", 0.0))

	if delay > 0.0 and _hit_index > 0: # Only delay after the first hit
		var timer = get_tree().create_timer(delay, true, false, true)
		timer.timeout.connect(_spawn_hitbox.bind(current_hit_data))
	else:
		_spawn_hitbox(current_hit_data)

func _spawn_hitbox(hit_data: Dictionary):
	if not is_instance_valid(hitbox_scene) or not is_instance_valid(_owner_player_stats): return
	
	var owner_player = _owner_player_stats.get_parent()
	if not is_instance_valid(owner_player): return

	var hitbox_instance = hitbox_scene.instantiate() as DaggerHitbox
	
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container): attacks_container.add_child(hitbox_instance)
	else: get_tree().current_scene.add_child(hitbox_instance)

	# Calculate damage for this specific hit
	var player_base_damage = float(_owner_player_stats.get_current_base_numerical_damage())
	var player_global_mult = float(_owner_player_stats.get_current_global_damage_multiplier())
	var weapon_damage_percent = float(_specific_stats.get("weapon_damage_percentage", 0.7))
	var hit_damage_mult = float(hit_data.get("damage_multiplier", 1.0))
	var final_damage = int(round(player_base_damage * weapon_damage_percent * hit_damage_mult * player_global_mult))
	
	# Determine hitbox scale
	var area_scale = float(_specific_stats.get("attack_area_scale", 1.0))

	# Position and initialize the hitbox
	var rotation_offset_degrees = float(hit_data.get("rotation_offset", 0.0))
	var final_direction = _base_direction.rotated(deg_to_rad(rotation_offset_degrees))
	
	hitbox_instance.global_position = owner_player.melee_aiming_dot.global_position
	hitbox_instance.rotation = final_direction.angle()
	hitbox_instance.initialize(final_damage, owner_player, Vector2.ONE * area_scale)
	
	# Prepare for the next hit in the sequence
	_hit_index += 1
	_execute_next_hit()
