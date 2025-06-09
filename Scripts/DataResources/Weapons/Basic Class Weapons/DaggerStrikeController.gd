# DaggerStrikeController.gd
# This script manages the complex sequence of hits for the Dagger Strike weapon.
# It reads an "attack_sequence" array from its stats and executes each hit
# by spawning instances of the DaggerStrikeAttack scene with appropriate timing and properties.

class_name DaggerStrikeController
extends Node2D

@export var hitbox_scene: PackedScene # The PackedScene for the individual DaggerStrikeAttack (e.g., DaggerStrikeAttack.tscn)

# --- Node References ---
# Added: Reference to the AnimatedSprite2D on this controller node.
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

# --- Internal State ---
var _specific_stats: Dictionary # Weapon-specific stats for the Dagger Strike (from WeaponBlueprintData/UpgradeData)
var _owner_player_stats: PlayerStats # Reference to the player's PlayerStats node
var _base_direction: Vector2 # The initial direction of the Dagger Strike (e.g., player aiming direction)

var _hit_index: int = 0 # Current index in the _attack_sequence
var _attack_sequence: Array = [] # The sequence of hits to execute (loaded from _specific_stats)

func _ready():
	# No specific _ready logic needed here, as initialization is handled by set_attack_properties.
	pass


# Standardized initialization function called by WeaponManager.
# direction: The base direction for the entire Dagger Strike sequence.
# p_attack_stats: The weapon's specific_stats dictionary.
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats.duplicate(true) # Deep copy to prevent modifying original
	_owner_player_stats = p_player_stats
	_base_direction = direction.normalized() if direction.length_squared() > 0 else Vector2.RIGHT # Ensure normalized direction
	
	_attack_sequence = _specific_stats.get(&"attack_sequence", []) # Get the attack sequence from stats

	if not is_instance_valid(hitbox_scene):
		push_error("ERROR (DaggerStrikeController): 'hitbox_scene' is not assigned or is invalid! Queueing free."); queue_free(); return
	if _attack_sequence.is_empty():
		push_error("ERROR (DaggerStrikeController): 'attack_sequence' is empty in weapon specific stats! Queueing free."); queue_free(); return

	# --- Handle Controller's Visuals (if any) ---
	# The controller itself might have an animated sprite for the overall effect.
	if is_instance_valid(animated_sprite):
		# Apply scale for the overall attack visual (e.g., if the controller has a sprite)
		var attack_area_scale = float(_specific_stats.get(&"attack_area_scale", 1.0))
		animated_sprite.scale = Vector2.ONE * attack_area_scale * _owner_player_stats.get_final_stat(GameStatConstants.Keys.AOE_AREA_MULTIPLIER)
		
		# Set rotation of the controller's sprite (if it has one)
		if _base_direction != Vector2.ZERO:
			self.rotation = _base_direction.angle()
			if absf(_base_direction.angle()) > PI / 2.0:
				animated_sprite.flip_v = true # Flip based on overall attack direction
		
		# Play the overall attack animation (if the controller has one, e.g., a "wind-up")
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(&"slash"): # Example animation name
			animated_sprite.play(&"slash")
		else:
			push_warning("WARNING (DaggerStrikeController): 'slash_controller' animation not found or sprite missing.")
	
	# --- Start the Attack Sequence ---
	_hit_index = 0 # Reset hit index for a new sequence
	_execute_next_hit()

	# --- Controller's Lifetime Logic ---
	# This timer is for the entire controller node, which manages the sequence.
	# The individual hitboxes will have their own lifetime.
	var total_lifetime = float(_specific_stats.get(&"base_lifetime", 0.3)) # From weapon blueprint or upgrades
	
	# Consider factoring in player's effect duration multiplier for the controller's lifetime
	var effect_duration_mult = _owner_player_stats.get_final_stat(GameStatConstants.Keys.EFFECT_DURATION_MULTIPLIER)
	total_lifetime *= effect_duration_mult

	var cleanup_timer = get_tree().create_timer(total_lifetime, true, false, true)
	cleanup_timer.timeout.connect(Callable(self, "queue_free")) # Queue free the controller after its lifetime


# Executes the next hit in the attack sequence.
func _execute_next_hit():
	if _hit_index >= _attack_sequence.size():
		return # Sequence complete, all hits spawned

	var current_hit_data = _attack_sequence[_hit_index]
	var delay = float(current_hit_data.get(&"delay", 0.0)) # Delay for this hit

	# Only apply delay *after* the first hit (i.e., for subsequent hits in the sequence)
	if delay > 0.0 and _hit_index > 0:
		var timer = get_tree().create_timer(delay, true, false, true)
		timer.timeout.connect(Callable(self, "_spawn_hitbox").bind(current_hit_data))
	else:
		# Spawn immediately for the first hit or if no delay
		_spawn_hitbox(current_hit_data)

# Spawns a single instance of the DaggerStrikeAttack (hitbox).
# hit_data: Dictionary containing specific parameters for this particular hit (e.g., damage multiplier, rotation offset).
func _spawn_hitbox(hit_data: Dictionary):
	if not is_instance_valid(hitbox_scene):
		push_error("ERROR (DaggerStrikeController): 'hitbox_scene' is invalid when trying to spawn hitbox."); return
	if not is_instance_valid(_owner_player_stats):
		push_error("ERROR (DaggerStrikeController): _owner_player_stats is invalid when trying to spawn hitbox."); return
	
	var owner_player = _owner_player_stats.get_parent() # Get PlayerCharacter reference
	if not is_instance_valid(owner_player):
		push_error("ERROR (DaggerStrikeController): PlayerCharacter is invalid when trying to spawn hitbox."); return

	var hitbox_instance = hitbox_scene.instantiate() as DaggerStrikeAttack # Instantiate the individual attack scene
	if not is_instance_valid(hitbox_instance):
		push_error("ERROR (DaggerStrikeController): Failed to instantiate DaggerStrikeAttack scene."); return
	
	# Add the hitbox instance to the appropriate container (e.g., AttacksContainer).
	var attacks_container = get_tree().current_scene.get_node_or_null("AttacksContainer")
	if is_instance_valid(attacks_container): attacks_container.add_child(hitbox_instance)
	else: get_tree().current_scene.add_child(hitbox_instance) # Fallback to current scene root

	# Calculate specific position and rotation for this hit.
	var rotation_offset_degrees = float(hit_data.get(&"rotation_offset", 0.0)) # Offset for this hit from base direction
	var final_direction = _base_direction.rotated(deg_to_rad(rotation_offset_degrees))
	
	# Position the hitbox (e.g., at the player's aiming dot for melee attacks).
	# This assumes melee_aiming_dot is a Marker2D on PlayerCharacter.
	if is_instance_valid(owner_player.melee_aiming_dot):
		hitbox_instance.global_position = owner_player.melee_aiming_dot.global_position
	else:
		hitbox_instance.global_position = owner_player.global_position # Fallback to player center
	
	# Create a copy of the weapon's overall specific_stats for this individual hit.
	# Then, apply any hit-specific multipliers defined in hit_data.
	var hit_specific_stats = _specific_stats.duplicate(true)
	var hit_damage_mult = float(hit_data.get(&"damage_multiplier", 1.0))
	
	# Update the 'weapon_damage_percentage' in the hit_specific_stats for this hit.
	# This allows individual hits in the sequence to have different damage modifiers.
	var current_weapon_damage_percent = float(hit_specific_stats.get(&"weapon_damage_percentage", 1.0))
	hit_specific_stats[&"weapon_damage_percentage"] = current_weapon_damage_percent * hit_damage_mult

	# Call the standardized initialization function on the individual hitbox instance.
	# This passes all necessary data for the hitbox to calculate its own damage, scale, etc.
	if hitbox_instance.has_method("set_attack_properties"):
		hitbox_instance.set_attack_properties(final_direction, hit_specific_stats, _owner_player_stats)
	else:
		push_error("ERROR (DaggerStrikeController): Spawned hitbox instance '", hitbox_instance.name, "' is missing 'set_attack_properties' method.")
	
	# Prepare for the next hit in the sequence.
	_hit_index += 1
	_execute_next_hit() # Call recursively (or iteratively) for the next hit
