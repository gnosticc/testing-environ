# ShieldBashAttack.gd
# Behavior for the Shield Bash attack. Deals damage and applies knockback.
#
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage multipliers.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.
# FIXED: Ensures a minimum of 1 damage is dealt.

extends Area2D # Inherits Area2D, assuming it's the root node for this attack

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var collision_shape: CollisionPolygon2D = get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer

var specific_stats: Dictionary = {} # Dictionary of weapon-specific stats passed from WeaponManager
var owner_player_stats: PlayerStats = null # Reference to the player's PlayerStats node
var _enemies_hit_this_sweep: Array[Node2D] = []

func _ready():
	if not is_instance_valid(animated_sprite): push_error("ERROR (ShieldBashAttack): No AnimatedSprite2D found!");
	if not is_instance_valid(collision_shape): push_error("ERROR (ShieldBashAttack): No CollisionPolygon2D found!"); queue_free(); return
	if not is_instance_valid(lifetime_timer): push_error("ERROR (ShieldBashAttack): No LifetimeTimer found!"); queue_free(); return
	
	lifetime_timer.timeout.connect(Callable(self, "queue_free")) # Connect to queue_free directly
	body_entered.connect(Callable(self, "_on_body_entered")) # Ensure signal is connected

	# Enable collision shape at start, it will be handled by the timer.
	if is_instance_valid(collision_shape):
		collision_shape.disabled = false
	else:
		push_warning("WARNING (ShieldBashAttack): CollisionShape is invalid. Hit detection might not work.")


# Standardized initialization function called by WeaponManager.
# direction: The normalized direction vector for the attack.
# p_attack_stats: Dictionary of specific stats for this weapon instance (already calculated by WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_attack_stats.duplicate(true) # Deep copy
	owner_player_stats = p_player_stats
	
	# --- Sprite & Node Rotation/Flipping Logic ---
	if is_instance_valid(animated_sprite):
		# Assuming the original sprite asset (in the editor) is drawn facing LEFT (e.g., a shield facing left).
		# We first universally flip it horizontally to make it behave as if it's facing RIGHT (Godot's 0 degree).
		# This makes the subsequent rotation logic consistent.
		animated_sprite.flip_h = true # Always flip initially for left-facing assets

	if direction != Vector2.ZERO:
		# Rotate the entire Area2D node to face the target direction.
		self.rotation = direction.angle()
		
		if is_instance_valid(animated_sprite):
			# Now, apply a vertical flip if the attack is aimed mostly to the "left" side
			# of the screen, which would typically cause a right-facing sprite to appear
			# upside down without this flip.
			# If the angle is roughly within the left half-circle (-PI/2 to -3PI/2, or 90 to 270 degrees)
			# or more simply, if the direction's x component is negative.
			if direction.x < 0: # Aiming left, flip sprite vertically to maintain correct orientation
				animated_sprite.flip_v = true
			else:
				animated_sprite.flip_v = false # No vertical flip when aiming right

	# --- Attack Duration ---
	# specific_stats should already contain the calculated base_attack_duration
	var base_duration = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.BASE_ATTACK_DURATION], 0.2)) # Default to 0.2 seconds
	
	# Player's effect duration multiplier from PlayerStats.gd
	var effect_duration_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER) # Use get_final_stat
	
	lifetime_timer.wait_time = base_duration * effect_duration_multiplier
	lifetime_timer.start()

	# Start animation if available
	if is_instance_valid(animated_sprite):
		animated_sprite.play("bash") # Or "bash", "attack" etc. assuming your SpriteFrames has this animation

func _on_body_entered(body: Node2D):
	if _enemies_hit_this_sweep.has(body): return # Prevent multiple hits on the same enemy per bash

	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return # Don't hit dead enemies
		
		_enemies_hit_this_sweep.append(enemy_target) # Mark enemy as hit this sweep
		
		if not is_instance_valid(owner_player_stats):
			push_error("ERROR (ShieldBashAttack): owner_player_stats is invalid. Cannot deal damage."); return

		# --- Damage Calculation ---
		# Get weapon-specific damage percentage multiplier (from blueprint/upgrades).
		# Default to 1.2 (120%) if not found.
		var weapon_damage_percent = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.2))
		# Retrieve weapon tags to pass to the damage calculation.
		var weapon_tags: Array[StringName] = specific_stats.get(&"tags", [])

		# Use the unified damage calculation from PlayerStats.gd, passing weapon tags.
		var calculated_damage_float = owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
		var final_damage_to_deal = int(round(maxf(1.0, calculated_damage_float))) # Ensure minimum 1 damage.
		
		var owner_player_char = owner_player_stats.get_parent() if is_instance_valid(owner_player_stats) else null
		
		# Prepare attack stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION) # Use get_final_stat
			# Add any other relevant attack properties here (e.g., lifesteal, status application chance)
		}

		enemy_target.take_damage(final_damage_to_deal, owner_player_char, attack_stats_for_enemy)
		
		# --- Apply Lifesteal ---
		var global_lifesteal_percent = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = final_damage_to_deal * global_lifesteal_percent
			if is_instance_valid(owner_player_char) and owner_player_char.has_method("heal"):
				owner_player_char.heal(heal_amount)

		# --- Apply Knockback ---
		# Assuming "knockback_strength" is a property directly on the blueprint's initial_specific_stats
		# or an upgrade that applies to the weapon.
		var knockback_strength = float(specific_stats.get(&"knockback_strength", 150.0))
		if knockback_strength > 0 and enemy_target.has_method("apply_knockback"):
			# Knockback direction is always away from the player's center, not the bash's center
			var knockback_direction = (enemy_target.global_position - owner_player_char.global_position).normalized() # Use owner_player_char
			enemy_target.apply_knockback(knockback_direction, knockback_strength)

		# Apply Status Effects on Hit if defined in specific_stats (passed from WeaponManager)
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
							owner_player_char, # Source of the effect
							specific_stats, # Weapon stats for scaling (these are the calculated ones)
							app_data.duration_override,
							app_data.potency_override
						)
						# print("ShieldBashAttack: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.
