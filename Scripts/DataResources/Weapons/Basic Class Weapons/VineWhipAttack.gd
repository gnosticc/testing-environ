# VineWhipAttack.gd
# Behavior for the Druid's Vine Whip attack.
# A fast, aimed melee attack with a longer reach.
#
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage multipliers.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.
# FIXED: Ensures a minimum of 1 damage is dealt.
# UPDATED: Uses PlayerStatKeys for all stat lookups.

class_name VineWhipAttack
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D

const SLASH_ANIMATION_NAME = &"whip" # Using StringName for animation names

var specific_stats: Dictionary = {}   # Stores the calculated weapon-specific stats from WeaponManager
var owner_player_stats: PlayerStats = null # Reference to the player's PlayerStats node

var _enemies_hit_this_sweep: Array[Node2D] = [] # Tracks enemies hit per attack instance to prevent multiple hits
var _is_attack_active: bool = false # Flag to control hit detection
var _current_attack_duration: float # Calculated duration of the attack animation/hitbox activity

func _ready():
	# Validate essential nodes. If any are missing, free the instance immediately.
	if not is_instance_valid(animated_sprite):
		push_error("ERROR (VineWhipAttack): AnimatedSprite2D node missing! Queueing free."); call_deferred("queue_free"); return
	else:
		# Connect animation_finished to its handler.
		animated_sprite.animation_finished.connect(Callable(self, "_on_animation_finished"))

	if not is_instance_valid(damage_area):
		push_warning("WARNING (VineWhipAttack): DamageArea node missing. Hit detection might not work.")
	else:
		damage_area.body_entered.connect(Callable(self, "_on_body_entered"))
		
		# Get and disable the collision shape initially. It will be enabled when the attack starts.
		var collision_shape = damage_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(collision_shape):
			collision_shape.disabled = true
		else:
			push_warning("WARNING (VineWhipAttack): No CollisionShape2D found under DamageArea. Hit detection might fail.")

# Standardized initialization function called by WeaponManager.
# direction: The normalized direction vector for the attack.
# p_attack_stats: Dictionary of specific stats for this weapon instance (already calculated by WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_attack_stats.duplicate(true) # Create a deep copy to ensure isolated data.
	owner_player_stats = p_player_stats
	
	# Set the rotation of the entire Node2D (self) to face the attack direction.
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()
		if is_instance_valid(animated_sprite):
			# Apply vertical flip if the attack is aimed predominantly upwards or downwards.
			# This logic might need fine-tuning based on the sprite's original orientation.
			if absf(direction.angle()) > PI / 2.0: # Roughly aiming left half
				animated_sprite.flip_v = true # Flip for visual consistency
			else:
				animated_sprite.flip_v = false # No flip for right half
			# Also ensure horizontal flip is reset if previously set
			animated_sprite.flip_h = false
	else:
		# Default to no rotation if direction is zero (e.g., fallback scenario)
		self.rotation = 0.0
		if is_instance_valid(animated_sprite):
			animated_sprite.flip_h = false
			animated_sprite.flip_v = false

	# Apply all calculated stats and start the animation.
	_apply_all_stats_and_start_animation()

# Applies all calculated stats and effects to the attack instance.
# This method pulls relevant data from 'specific_stats' (calculated by WeaponManager)
# and 'owner_player_stats' (cached current_ properties from PlayerStats).
func _apply_all_stats_and_start_animation():
	if not is_instance_valid(self) or specific_stats.is_empty() or not is_instance_valid(owner_player_stats):
		push_error("ERROR (VineWhipAttack): Cannot apply stats or start animation. Missing owner_player_stats or specific_stats. Queueing free."); call_deferred("queue_free"); return

	# --- Scale Calculation (Visual and Collision Area) ---
	# Retrieve base visual scales from received stats, using PlayerStatKeys.
	var base_scale_x = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_X], 1.0))
	var base_scale_y = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_Y], 1.0))
	
	# Apply player's global AoE area multiplier from PlayerStats.
	var player_aoe_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER)
	
	# Apply the combined scale to the entire Node2D node (which includes the sprite and hitbox).
	self.scale = Vector2(base_scale_x * player_aoe_multiplier, base_scale_y * player_aoe_multiplier)
	
	# --- Attack Duration Calculation ---
	# Retrieve base attack duration from received stats, using PlayerStatKeys.
	var base_duration = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.BASE_ATTACK_DURATION], 0.3)) # Default to 0.3 seconds
	
	# Apply player's attack speed multiplier from PlayerStats.
	var player_attack_speed_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	
	# The blueprint currently has "weapon_attack_speed_mod" as a direct key.
	# If this is a weapon-specific multiplier (not a PlayerStatKeys enum), keep it as is.
	var weapon_attack_speed_mod = float(specific_stats.get(&"weapon_attack_speed_mod", 1.0)) 
	
	var final_attack_speed_multiplier = player_attack_speed_multiplier * weapon_attack_speed_mod
	if final_attack_speed_multiplier <= 0: final_attack_speed_multiplier = 0.01 # Prevent division by zero
	
	_current_attack_duration = base_duration / final_attack_speed_multiplier
	
	# Adjust animation speed scale based on calculated attack speed.
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_attack_speed_multiplier
	else:
		push_warning("WARNING (VineWhipAttack): AnimatedSprite2D is invalid, cannot set speed_scale.")
	
	_start_attack_animation()

# Initiates the attack animation and enables the hitbox.
func _start_attack_animation():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area):
		call_deferred("queue_free"); return # Self-destruct if essential nodes are missing.

	_enemies_hit_this_sweep.clear() # Clear the list of hit enemies for this new attack instance.
	_is_attack_active = true # Activate the hitbox.
	
	# Enable the collision shape for hit detection.
	var collision_shape = damage_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(collision_shape): 
		collision_shape.disabled = false
	else:
		push_warning("WARNING (VineWhipAttack): CollisionShape2D not found. Hitbox may not activate.")

	animated_sprite.play(SLASH_ANIMATION_NAME) # Play the attack animation.
	
	# Set a one-shot timer to queue_free this attack instance after its calculated duration.
	# This ensures the hitbox is active for the full attack duration and then cleaned up.
	var duration_finish_timer = get_tree().create_timer(_current_attack_duration, true, false, true)
	duration_finish_timer.timeout.connect(Callable(self, "queue_free"))

# Called when the attack animation finishes (e.g., if it's a non-looping animation).
func _on_animation_finished():
	if is_instance_valid(animated_sprite) and animated_sprite.animation == SLASH_ANIMATION_NAME:
		# For the Vine Whip, the duration_finish_timer handles the full lifecycle,
		# so specific logic here might not be necessary unless you have unique post-animation effects.
		pass

# Handles collision when a body enters the `damage_area`.
func _on_body_entered(body: Node2D):
	# Only process if the attack is active, the body is valid, and hasn't been hit yet by this specific attack instance.
	if not _is_attack_active or not is_instance_valid(body) or _enemies_hit_this_sweep.has(body): return 
	
	# Check if the collided body is an enemy and can take damage.
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return # Do not hit dead enemies.

		_enemies_hit_this_sweep.append(enemy_target) # Mark this enemy as hit by this attack instance.
		
		if not is_instance_valid(owner_player_stats): 
			push_error("ERROR (VineWhipAttack): Owner PlayerStats node is invalid! Cannot deal damage."); return

		# --- Damage Calculation (Leveraging unified PlayerStats method) ---
		# Retrieve weapon-specific damage percentage from received stats.
		var weapon_damage_percent = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.1)) # Default to 110% of player's numerical damage.
		# Retrieve weapon tags to pass to the damage calculation.
		var weapon_tags: Array[StringName] = specific_stats.get(&"tags", [])

		# Calculate the final damage using the player's overall damage formula, including tags.
		var calculated_damage_float = owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
		var final_damage_to_deal = int(round(maxf(1.0, calculated_damage_float))) # Ensure minimum 1 damage and round to int.
		
		var owner_player_char = owner_player_stats.get_parent() if is_instance_valid(owner_player_stats) else null
		
		# Prepare attack-specific stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
			# Add any other relevant attack properties here (e.g., lifesteal, status application chance)
		}

		enemy_target.take_damage(final_damage_to_deal, owner_player_char, attack_stats_for_enemy)

		# --- Apply Lifesteal ---
		var global_lifesteal_percent = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = final_damage_to_deal * global_lifesteal_percent
			if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
				owner_player_char.heal(heal_amount)

		# --- Apply Status Effects on Hit ---
		if specific_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = specific_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					# Combine base application chance with global status effect chance addition.
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0) # Clamp between 0 and 1.
					
					if randf() < final_application_chance:
						enemy_target.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData,
							owner_player_char, # Source of the effect.
							specific_stats, # Weapon stats for scaling of the status effect.
							app_data.duration_override,
							app_data.potency_override
						)
						# print("VineWhipAttack: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.
