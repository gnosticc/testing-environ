# TorrentAttack.gd
# Behavior for the Druid's Torrent.
# A stationary AoE that deals ticking damage to enemies inside it.
#
# UPDATED: Standardized stat key access using PlayerStatKeys.
# UPDATED: Leverages PlayerStats.get_calculated_player_damage for unified damage calculation.
# UPDATED: Uses PlayerStats.get_final_stat for global player stat lookups.
# UPDATED: Uses push_error and push_warning for consistent error reporting.
# UPDATED: Ensures _specific_stats is a deep copy to prevent unintended modifications.

class_name TorrentAttack
extends Area2D

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var damage_tick_timer: Timer = get_node_or_null("DamageTickTimer") as Timer

var _specific_stats: Dictionary = {} # Stores the calculated weapon-specific stats from WeaponManager
var _owner_player_stats: PlayerStats = null # Reference to the player's PlayerStats node
var _damage_per_tick: int # Will be calculated based on player and weapon stats
var _enemies_in_area: Array[BaseEnemy] = [] # Tracks enemies currently inside the AoE

func _ready():
	# Validate essential timer nodes. If any are missing, free the instance immediately.
	if not is_instance_valid(lifetime_timer):
		push_error("ERROR (TorrentAttack): LifetimeTimer node missing! Queueing free."); call_deferred("queue_free"); return
	if not is_instance_valid(damage_tick_timer):
		push_error("ERROR (TorrentAttack): DamageTickTimer node missing! Queueing free."); call_deferred("queue_free"); return
		
	# Connect signals for timers and area entry/exit.
	lifetime_timer.timeout.connect(queue_free)
	damage_tick_timer.timeout.connect(_on_damage_tick)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Play the initial animation for the Torrent effect (e.g., eruption).
	if is_instance_valid(animated_sprite):
		animated_sprite.play("erupt") # Assuming a looping animation named 'erupt' in its SpriteFrames.
	else:
		push_warning("WARNING (TorrentAttack): AnimatedSprite2D node missing.")

# Standardized initialization function called by WeaponManager.
# _direction: The direction vector (unused for stationary AoE, but kept for signature consistency).
# p_attack_stats: Dictionary of specific stats for this weapon instance (already calculated by WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	_specific_stats = p_attack_stats.duplicate(true) # Create a deep copy to ensure isolated data.
	_owner_player_stats = p_player_stats
	
	# Validate player stats reference. If invalid, the attack cannot function correctly.
	if not is_instance_valid(_owner_player_stats):
		push_error("ERROR (TorrentAttack): Owner PlayerStats node is invalid! Cannot calculate damage or scales."); queue_free(); return

	# --- Calculate Damage per Tick (Leveraging unified PlayerStats method) ---
	# Retrieve weapon-specific damage percentage from received stats.
	var weapon_damage_percent = float(_specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 0.6))
	# Calculate the final damage using the player's overall damage formula.
	_damage_per_tick = int(round(_owner_player_stats.get_calculated_player_damage(weapon_damage_percent)))
	
	# --- Set Scale (Visual and Collision Area) ---
	# Retrieve base area scale from received stats.
	var base_area_scale = float(_specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.AREA_SCALE], 1.0))
	# Apply player's global AoE area multiplier using get_final_stat.
	var player_aoe_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	# Apply the combined scale to the entire Area2D node.
	self.scale = Vector2.ONE * base_area_scale * player_aoe_multiplier
	
	# --- Set Timers (Lifetime and Damage Tick) ---
	# Retrieve base lifetime from received stats.
	var base_lifetime = float(_specific_stats.get(&"base_lifetime", 3.0)) # 'base_lifetime' is a direct key from the blueprint.
	# Apply player's global effect duration multiplier using get_final_stat.
	var effect_duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = base_lifetime * effect_duration_multiplier
	lifetime_timer.start() # Start the lifetime timer.
	
	# Retrieve damage tick interval from received stats.
	var tick_interval = float(_specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.DAMAGE_TICK_INTERVAL], 0.5))
	damage_tick_timer.wait_time = tick_interval
	# The damage tick timer is started when the first enemy enters the area (in _on_body_entered).

# Handles when a body enters the Torrent's Area2D.
func _on_body_entered(body: Node2D):
	# Check if the entered body is an enemy and not already tracked.
	if body is BaseEnemy and not _enemies_in_area.has(body):
		var enemy = body as BaseEnemy
		if enemy.is_dead(): return # Do not track dead enemies.
		
		# Apply immediate damage to the enemy upon entry (first hit).
		var owner_player_char = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		enemy.take_damage(_damage_per_tick, owner_player_char)
		
		_enemies_in_area.append(enemy) # Add enemy to the list of enemies inside the area.
		
		# If the damage tick timer is not running, start it now.
		if damage_tick_timer.is_stopped():
			damage_tick_timer.start()

# Handles when a body exits the Torrent's Area2D.
func _on_body_exited(body: Node2D):
	# Check if the exited body is an enemy and is currently tracked.
	if body is BaseEnemy and _enemies_in_area.has(body):
		_enemies_in_area.erase(body) # Remove enemy from the tracking list.
		
		# If no more enemies are in the area, stop the tick timer to save performance.
		if _enemies_in_area.is_empty():
			damage_tick_timer.stop()

# Called when the damage tick timer times out, applying damage to all enemies inside the area.
func _on_damage_tick():
	# If no enemies are in the area, stop the timer (should be handled by _on_body_exited, but as a failsafe).
	if _enemies_in_area.is_empty(): 
		damage_tick_timer.stop()
		return
	
	var owner_player_char = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
	
	# Iterate through a copy of the list to safely remove enemies if they die during iteration.
	for enemy in _enemies_in_area.duplicate():
		if is_instance_valid(enemy) and not enemy.is_dead():
			enemy.take_damage(_damage_per_tick, owner_player_char)
		else:
			_enemies_in_area.erase(enemy) # Remove invalid or dead enemies from the tracking list.
