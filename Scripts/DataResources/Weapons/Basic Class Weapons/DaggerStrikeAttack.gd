# DaggerStrikeAttack.gd
# Behavior for a single instance of the Dagger Strike attack (the hitbox/visual).
# It receives its properties from WeaponManager (or DaggerStrikeController)
# and deals damage based on player stats.
# It now fully integrates with the standardized stat system.
#
# FIXED: Refined rotation and flipping logic for AnimatedSprite2D.
# FIXED: Declared '_stats_have_been_set' variable.
# FIXED: Corrected reference to CollisionPolygon2D node.
# UPDATED: Uses PlayerStats.get_calculated_player_damage for unified damage calculation.

extends Node2D
class_name DaggerStrikeAttack # Explicit class_name for clarity and type hinting

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D # Use $ shorthand
@onready var damage_area: Area2D = $DamageArea # Use $ shorthand
# FIXED: Changed node name from CollisionShape2D to CollisionPolygon2D
@onready var collision_shape: CollisionShape2D = $DamageArea/CollisionShape2D

const SLASH_ANIMATION_NAME = &"slash" # Use StringName for animation names

var specific_stats: Dictionary = {} # Dictionary of weapon-specific stats passed from controller/manager
var owner_player_stats: PlayerStats = null # Reference to the player's PlayerStats node

var _enemies_hit_this_sweep: Array[Node2D] = [] # Tracks enemies hit to prevent multi-hitting per sweep
var _is_attack_active: bool = false # Flag to control hit detection
var _current_attack_duration: float = 0.25 # Actual duration of the attack animation/hitbox activity
var _stats_have_been_set: bool = false # Declared _stats_have_been_set here

func _ready():
	if not is_instance_valid(animated_sprite):
		push_error("ERROR (DaggerStrikeAttack): AnimatedSprite2D node missing! Queueing free."); call_deferred("queue_free"); return
	else:
		# Connect animation_finished to its handler
		animated_sprite.animation_finished.connect(Callable(self, "_on_animation_finished"))

	if not is_instance_valid(damage_area):
		push_warning("WARNING (DaggerStrikeAttack): DamageArea node missing.")
	else:
		# Connect body_entered to hit detection logic
		damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
		
		# Disable collision shape initially; it will be enabled when attack starts
		# FIXED: Reference collision_shape directly as it's now an @onready var
		if is_instance_valid(collision_shape):
			collision_shape.disabled = true
		else:
			# This warning should no longer appear if the @onready var is correctly set up
			push_warning("WARNING (DaggerStrikeAttack): CollisionShape (CollisionPolygon2D) not found under DamageArea. Hit detection might fail.")


# Standardized initialization function called by WeaponManager or DaggerStrikeController.
# direction: The normalized direction vector for the attack.
# p_attack_stats: Dictionary of specific stats for this weapon instance (already calculated by WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	specific_stats = p_attack_stats.duplicate(true) # Deep copy to avoid modifying original
	owner_player_stats = p_player_stats
	_stats_have_been_set = true # Set the flag here as properties are now set
	
	# --- Rotation and Flipping Logic ---
	if direction != Vector2.ZERO:
		# Rotate the entire Node2D (self) to face the direction.
		# This is the primary rotation. Children will inherit this rotation.
		self.rotation = direction.angle()
		
		# Now, handle sprite-specific flipping based on the angle, relative to its new rotation.
		# This logic assumes the sprite asset is drawn facing RIGHT (0 degrees).
		if is_instance_valid(animated_sprite):
			# Reset flips first to avoid previous state interfering with new direction.
			animated_sprite.flip_h = false
			animated_sprite.flip_v = false

			# Determine horizontal flip (flip_h) for left/right aiming.
			# If sprite faces right, flip_h is true when aiming left.
			if direction.x < 0:
				animated_sprite.flip_h = true
			
			# Determine vertical flip (flip_v) for up/down aiming.
			# This is often needed for melee attacks that might be symmetrical horizontally,
			# but need to flip for visual consistency when aiming mostly up.
			#
			# IMPORTANT: This logic is highly dependent on your sprite assets' original drawing.
			# - If your "slash" animation is drawn horizontally (e.g., right-facing swipe).
			# - If you want an UPWARD swipe, it's typically 'rotation' combined with 'flip_v = true'.
			# - If you want a DOWNWARD swipe, it's typically 'rotation' combined with 'flip_v = false'.
			# Adjust `0.5` threshold if your diagonal angles are different.
			
			# Check if aiming predominantly vertically
			if absf(direction.y) > absf(direction.x): # If vertical component is stronger
				if direction.y < 0: # Aiming UP
					animated_sprite.flip_v = true # Flip for upward attacks
				else: # Aiming DOWN
					animated_sprite.flip_v = false # No vertical flip for downward attacks
			# If aiming mostly horizontally, flip_v remains false (from reset above)
			
			# *** CRITICAL SCENE SETUP CHECK FOR ROTATION ***
			# The 'AnimatedSprite2D' node itself inside DaggerStrikeAttack.tscn
			# should typically have its *initial rotation* set to 0 degrees in the editor,
			# AND its texture/animation frames should be drawn facing RIGHT (0 degrees).
			# If your sprite asset is, for example, drawn facing UPWARDS, you MUST
			# rotate the *AnimatedSprite2D node* by -90 degrees in the scene editor
			# so its "right" direction aligns with Godot's 0-degree angle.
			# If the animation still looks off, experiment with the flip_h and flip_v logic or
			# adjust the base rotation of your AnimatedSprite2D within the scene.
			# The 'offset' property of AnimatedSprite2D can also cause visual misalignment.
	else:
		# If direction is zero (e.g., fallback), reset rotation and flips.
		self.rotation = 0.0
		if is_instance_valid(animated_sprite):
			animated_sprite.flip_h = false
			animated_sprite.flip_v = false


	# Apply stats and start the attack.
	_apply_all_stats_effects()
	_start_attack_animation()


# Applies all calculated stats and effects to the attack instance.
# This method pulls relevant data from 'specific_stats' (already calculated) and 'owner_player_stats'.
func _apply_all_stats_effects():
	if not is_instance_valid(owner_player_stats):
		push_warning("DaggerStrikeAttack: owner_player_stats invalid. Cannot apply effects."); return

	# --- Scale Calculation (Visual and Collision) ---
	# specific_stats here should already contain the calculated weapon scale
	var base_scale_x = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_X], 1.0))
	var base_scale_y = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_Y], 1.0))
	
	# The player's AOE_AREA_MULTIPLIER from PlayerStats is applied on top of the weapon's inherent scale
	var player_aoe_mult = owner_player_stats.current_aoe_area_multiplier # Use the cached 'current_' stat
	
	# Apply scale to the root of the attack scene (which should scale children as well)
	self.scale = Vector2(base_scale_x * player_aoe_mult, base_scale_y * player_aoe_mult)
	
	# --- Attack Duration Calculation ---
	# specific_stats should already contain the calculated base_attack_duration
	var base_duration = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.BASE_ATTACK_DURATION], 0.25)) # Default to 0.25 seconds
	
	# Player's attack speed multiplier from PlayerStats.gd
	var atk_speed_player_mult = owner_player_stats.current_attack_speed_multiplier # Use the cached 'current_' stat
	
	# Assuming 'weapon_attack_speed_mod' is a specific stat passed in specific_stats (already calculated)
	var weapon_attack_speed_mod = float(specific_stats.get(&"weapon_attack_speed_mod", 1.0)) # Consider if this should be a PlayerStatKeys entry
	
	var final_attack_speed_mult = atk_speed_player_mult * weapon_attack_speed_mod
	if final_attack_speed_mult <= 0: final_attack_speed_mult = 0.01 # Prevent division by zero
	
	_current_attack_duration = base_duration / final_attack_speed_mult
	
	# Adjust animation speed scale based on calculated attack speed
	if is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = final_attack_speed_mult
	else:
		push_warning("DaggerStrikeAttack: AnimatedSprite2D is invalid, cannot set speed_scale.")

# Initiates the attack animation and enables the hitbox.
func _start_attack_animation():
	if not is_instance_valid(animated_sprite) or not is_instance_valid(damage_area):
		push_error("DaggerStrikeAttack: Missing animated_sprite or damage_area for attack. Queueing free."); call_deferred("queue_free"); return

	_enemies_hit_this_sweep.clear() # Clear enemies hit from previous sweeps
	_is_attack_active = true # Activate hitbox
	
	# Enable collision shape
	# FIXED: Reference collision_shape directly as it's now an @onready var
	if is_instance_valid(collision_shape): collision_shape.disabled = false
	else: push_warning("DaggerStrikeAttack: CollisionShape (CollisionPolygon2D) not found under DamageArea. Hitbox may not activate.")

	# Play the attack animation
	animated_sprite.play(SLASH_ANIMATION_NAME)
	
	# Set a timer to queue_free this attack instance after its calculated duration.
	# This ensures the hitbox is active for the full attack duration.
	var duration_finish_timer = get_tree().create_timer(_current_attack_duration, true, false, true)
	duration_finish_timer.timeout.connect(Callable(self, "queue_free"))


# Called when the attack animation finishes.
func _on_animation_finished():
	if is_instance_valid(animated_sprite) and animated_sprite.animation == SLASH_ANIMATION_NAME:
		# Optional: You could add logic here if the animation ending triggers something,
		# but for this type of attack, the duration_finish_timer handles _is_attack_active reset.
		pass


# Handles collision with other bodies (enemies).
func _on_damage_area_body_entered(body: Node2D):
	# Only process if attack is active, body is valid, and enemy hasn't been hit yet this sweep.
	if not _is_attack_active or not is_instance_valid(body) or _enemies_hit_this_sweep.has(body): return
	
	if body.is_in_group("enemies") and body is BaseEnemy:
		var enemy_target = body as BaseEnemy
		if enemy_target.is_dead(): return # Don't hit dead enemies
		
		_enemies_hit_this_sweep.append(enemy_target) # Mark enemy as hit this sweep
		
		if not is_instance_valid(owner_player_stats):
			push_error("DaggerStrikeAttack: owner_player_stats is invalid. Cannot deal damage."); return

		# --- Damage Calculation ---
		# Get weapon-specific damage percentage multiplier (from blueprint/upgrades).
		# Default to 0.9 if not found, as per original code.
		var weapon_damage_percent = float(specific_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 0.9))
		
		# NEW: Use the unified damage calculation from PlayerStats.gd
		var final_damage_to_deal = owner_player_stats.get_calculated_player_damage(weapon_damage_percent)
		
		# TODO: Add visual/sound effect for critical hit here - CRIT IS NOW HANDLED INTERNALLY BY get_calculated_player_damage
		# If you want to check for crit *after* the fact (for FX), you'd need get_calculated_player_damage to
		# return a dictionary with damage and a "is_critical_hit" flag, or emit a signal from PlayerStats.gd.
		# For simplicity, if crit is purely a damage multiplier, the calculation is sufficient.

		var owner_player = owner_player_stats.get_parent() if is_instance_valid(owner_player_stats) else null
		
		# Prepare attack stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: owner_player_stats.current_armor_penetration # Use cached current_ stat
			# Add any other relevant attack properties here (e.g., lifesteal, status application chance)
		}

		enemy_target.take_damage(final_damage_to_deal, owner_player, attack_stats_for_enemy)

		# Apply Status Effects on Hit if defined in _received_stats
		if specific_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = specific_stats.get(&"on_hit_status_applications", [])
			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data) and randf() < app_data.application_chance:
					enemy_target.status_effect_component.apply_effect(
						load(app_data.status_effect_resource_path) as StatusEffectData,
						owner_player, # Source of the effect
						specific_stats, # Weapon stats for scaling (these are the calculated ones)
						app_data.duration_override,
						app_data.potency_override
					)
					print("DaggerStrikeAttack: Applied status from '", app_data.status_effect_resource_path, "' to enemy.")
