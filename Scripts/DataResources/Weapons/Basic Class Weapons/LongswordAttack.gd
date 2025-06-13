# LongswordAttack.gd
# Behavior for a single instance of the Longsword attack (hitbox/visual).
# It receives its properties from WeaponManager and deals damage based on player stats.
# It now fully integrates with the standardized stat system.
#
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage multipliers.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.
# FIXED: Ensures a minimum of 1 damage is dealt.
# FIXED: Corrected @onready var type hint for CollisionPolygon2D.

extends Node2D
class_name LongswordAttack

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D
@onready var collision_shape: CollisionPolygon2D = get_node_or_null("$DamageArea/CollisionPolygon2D") as CollisionPolygon2D # Corrected to CollisionPolygon2D


const SLASH_ANIMATION_NAME = &"slash" # Use StringName for animation names for consistency

var specific_stats: Dictionary = {} # Dictionary of weapon-specific stats passed from WeaponManager
var owner_player_stats: PlayerStats = null # Reference to the player's PlayerStats node

var _enemies_hit_this_sweep: Array[Node2D] = []
var _is_attack_active: bool = false
var _current_attack_duration: float = 0.4 # Default, will be calculated

func _ready():
	if not is_instance_valid(animated_sprite):
		push_error("ERROR (LongswordAttack): AnimatedSprite2D node missing! Queueing free."); call_deferred("queue_free"); return
	else:
		animated_sprite.animation_finished.connect(Callable(self, "_on_animation_finished"))

	if not is_instance_valid(damage_area):
		push_warning("WARNING (LongswordAttack): DamageArea node missing.")
	else:
		damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
		
		if not is_instance_valid(collision_shape): # Check validity after @onready
			push_warning("WARNING (LongswordAttack): CollisionPolygon2D not found. Hit detection might fail.")
		else:
			collision_shape.disabled = true # Start disabled, enable when attack starts


# Standardized initialization function called by WeaponManager
# direction: The normalized direction vector for the attack.
# p_attack_stats: Dictionary of specific stats for this weapon instance (already calculated by WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_attack_stats.duplicate(true) # Deep copy to avoid modifying original
	owner_player_stats = p_player_stats
	
	# --- Rotation Logic ---
	# Set the rotation of the entire attack node to face the target direction.
	if direction != Vector2.ZERO:
		self.rotation = direction.angle()
	else:
		self.rotation = 0.0 # Default to facing right if no direction provided

	# This function applies all calculated stats and starts the animation
	_apply_all_stats_and_start_animation()

# Applies all calculated stats and effects to the attack instance.
# This method pulls relevant data from 'specific_stats' (already calculated by WeaponManager)
# and 'owner_player_stats' (cached current_ properties).
func _apply_all_stats_and_start_animation():
	if not is_instance_valid(self) or specific_stats.is_empty() or not is_instance_valid(owner_player_stats):
		push_error("ERROR (LongswordAttack): Cannot apply stats or start animation. Missing owner_player_stats or specific_stats."); 
		call_deferred("queue_free"); return

	# --- Scale Calculation (Visual and Collision) ---
	# specific_stats here should already contain the calculated weapon scale
	var base_scale_x = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_X], 1.0))
	var base_scale_y = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_Y], 1.0))
	
	# The player's AOE_AREA_MULTIPLIER from PlayerStats is applied on top of the weapon's inherent scale
	var player_aoe_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.AOE_AREA_MULTIPLIER) # Use get_final_stat
	
	# Apply scale to the root of the attack scene (which should scale children as well)
	self.scale = Vector2(base_scale_x * player_aoe_multiplier, base_scale_y * player_aoe_multiplier)
	
	# --- Attack Duration Calculation ---
	# specific_stats should already contain the calculated base_attack_duration
	var base_duration = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.BASE_ATTACK_DURATION], 0.4)) # Default to 0.4 seconds
	
	# Player's attack speed multiplier from PlayerStats.gd
	var player_attack_speed_multiplier = owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER) # Use get_final_stat
	
	# Assuming 'weapon_attack_speed_mod' is a specific stat passed in specific_stats (already calculated)
	var weapon_attack_speed_mod = float(specific_stats.get(&"weapon_attack_speed_mod", 1.0)) 
	
	var final_attack_speed_multiplier = player_attack_speed_multiplier * weapon_attack_speed_mod
	if final_attack_speed_multiplier <= 0: final_attack_speed_multiplier = 0.01 # Prevent division by zero
	
	_current_attack_duration = base_duration / final_attack_speed_multiplier
	
	# Adjust animation speed scale based on calculated attack speed
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_attack_speed_multiplier
	else:
		push_warning("LongswordAttack: AnimatedSprite2D is invalid, cannot set speed_scale.")
	
	_start_attack_animation()

func _start_attack_animation():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area):
		push_error("LongswordAttack: Missing animated_sprite or damage_area for attack. Queueing free."); call_deferred("queue_free"); return

	_enemies_hit_this_sweep.clear()
	_is_attack_active = true
	
	if is_instance_valid(collision_shape):
		collision_shape.disabled = false
	else:
		push_warning("LongswordAttack: CollisionPolygon2D not found. Hitbox may not activate.")

	animated_sprite.play(SLASH_ANIMATION_NAME)
	# Use a timer to ensure the attack area is disabled after the duration, even if animation loops
	var duration_finish_timer = get_tree().create_timer(_current_attack_duration, true, false, true)
	duration_finish_timer.timeout.connect(Callable(self, "queue_free")) # Attack queues free after its duration

func _on_animation_finished():
	if is_instance_valid(animated_sprite) and animated_sprite.animation == SLASH_ANIMATION_NAME:
		# The duration timer will handle queue_free, this is just for visual cleanup
		pass

func _on_damage_area_body_entered(body: Node2D):
	if not _is_attack_active or not is_instance_valid(body): return
	if _enemies_hit_this_sweep.has(body): return
	
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return
		
		_enemies_hit_this_sweep.append(enemy_target)
		
		if not is_instance_valid(owner_player_stats):
			push_error("ERROR (LongswordAttack): owner_player_stats is invalid. Cannot deal damage."); return

		# --- Damage Calculation ---
		# Get weapon-specific damage percentage multiplier (from blueprint/upgrades).
		# Default to 2.0 (200%) if not found, as per original code.
		var weapon_damage_percent = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 2.0))
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
							owner_player_char, # Source of the effect (the player).
							specific_stats, # Weapon stats for scaling (these are the calculated ones)
							app_data.duration_override,
							app_data.potency_override
						)
						# print("LongswordAttack: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.
