# TorrentAttack.gd
# Behavior for the Druid's Torrent.
# A stationary AoE that deals ticking damage to enemies inside it.
#
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage multipliers.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.
# UPDATED: Uses PlayerStatKeys for all stat lookups.
# FIXED: Ensures a minimum of 1 damage is dealt.

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
	var weapon_tags: Array[StringName] = _specific_stats.get(&"tags", []) # Retrieve weapon tags
	# Calculate the final damage using the player's overall damage formula, including tags.
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags) # Pass tags
	_damage_per_tick = int(round(maxf(1.0, calculated_damage_float))) # Ensure minimum 1 damage.
	
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
		
		var owner_player_char = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		
		# Prepare attack stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
		}
		
		# Apply immediate damage to the enemy upon entry (first hit).
		enemy.take_damage(_damage_per_tick, owner_player_char, attack_stats_for_enemy)
		
		_enemies_in_area.append(enemy) # Add enemy to the list of enemies inside the area.
		
		# --- Apply Lifesteal ---
		var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = _damage_per_tick * global_lifesteal_percent
			if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
				owner_player_char.heal(heal_amount)

		# --- Apply Status Effects on Hit ---
		if _specific_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy.status_effect_component):
			var status_apps: Array = _specific_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0)
					
					if randf() < final_application_chance:
						enemy.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData,
							owner_player_char, # Source of the effect (the player).
							_specific_stats, # Weapon stats for scaling of the status effect.
							app_data.duration_override,
							app_data.potency_override
						)
						# print("TorrentAttack: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.
		
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
			# Prepare attack stats for status effects in case the tick itself applies them
			var attack_stats_for_enemy: Dictionary = {
				PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
			}
			enemy.take_damage(_damage_per_tick, owner_player_char, attack_stats_for_enemy)

			# --- Apply Lifesteal on Tick Damage ---
			var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
			if global_lifesteal_percent > 0:
				var heal_amount = _damage_per_tick * global_lifesteal_percent
				if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
					owner_player_char.heal(heal_amount)
			
			# --- Apply Status Effects on Tick (if configured in blueprint) ---
			# TorrentAttack.gd will need to have its _specific_stats include 'on_hit_status_applications'
			# if you want its ticks to apply status effects.
			if _specific_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy.status_effect_component):
				var status_apps: Array = _specific_stats.get(&"on_hit_status_applications", [])
				var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

				for app_data_res in status_apps:
					var app_data = app_data_res as StatusEffectApplicationData
					if is_instance_valid(app_data):
						var final_application_chance = app_data.application_chance + global_status_effect_chance_add
						final_application_chance = clampf(final_application_chance, 0.0, 1.0)
						
						if randf() < final_application_chance:
							enemy.status_effect_component.apply_effect(
								load(app_data.status_effect_resource_path) as StatusEffectData,
								owner_player_char, # Source of the effect.
								_specific_stats, # Weapon stats for scaling of the status effect.
								app_data.duration_override,
								app_data.potency_override
							)
							# print("TorrentAttack: Applied status from tick '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.
		else:
			_enemies_in_area.erase(enemy) # Remove invalid or dead enemies from the tracking list.
