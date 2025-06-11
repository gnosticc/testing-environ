# ShortbowArrow.gd
# Behavior for the Shortbow's arrow projectile. This script is designed to be a generic, reusable projectile.
#
# UPDATED: Passes weapon tags to PlayerStats.get_calculated_player_damage for tag-specific damage modifiers.
# UPDATED: Integrates GLOBAL_PROJECTILE_PIERCE_COUNT_ADD for additional piercing.
# UPDATED: Integrates GLOBAL_PROJECTILE_MAX_RANGE_ADD for projectile lifetime.
# UPDATED: Integrates GLOBAL_LIFESTEAL_PERCENT for healing.
# UPDATED: Integrates GLOBAL_STATUS_EFFECT_CHANCE_ADD for status effect application.

class_name ShortbowArrow
extends Area2D

# These variables will be set by _apply_all_stats_effects based on _received_stats.
var final_damage_amount: int
var final_speed: float
var final_applied_scale: Vector2
var direction: Vector2 = Vector2.RIGHT # Default direction, will be overridden by set_attack_properties

var max_pierce_count: int
var current_pierce_count: int = 0 # Tracks how many enemies this projectile has pierced through

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

var _stats_have_been_set: bool = false # Flag to ensure stats are applied only once
var _received_stats: Dictionary = {} # Dictionary of weapon-specific stats passed from WeaponManager
var _owner_player_stats: PlayerStats # Reference to the player's PlayerStats node

func _ready():
	# Validate essential nodes. If any are missing, free the instance immediately.
	if not is_instance_valid(lifetime_timer):
		push_error("ERROR (ShortbowArrow): LifetimeTimer node missing! Queueing free."); call_deferred("queue_free"); return
	else:
		# Connect the lifetime timer to automatically free the projectile when its duration ends.
		if not lifetime_timer.is_connected("timeout", Callable(self, "queue_free")):
			lifetime_timer.timeout.connect(self.queue_free)
	
	# If set_attack_properties was called before _ready() (e.g., via call_deferred), apply stats now.
	if _stats_have_been_set:
		_apply_all_stats_effects()

func _physics_process(delta: float):
	# Move the projectile based on its direction and calculated speed.
	global_position += direction * final_speed * delta

# Standardized initialization function called by WeaponManager (or ShortbowAttackController).
# p_direction: The normalized direction vector for the projectile.
# p_attack_stats: Dictionary of specific stats for this weapon instance (already calculated by WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	# Normalize the direction vector; if zero, default to pointing right.
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true) # Deep copy the received stats for this instance.
	_owner_player_stats = p_player_stats
	_stats_have_been_set = true # Mark that properties have been set.
	
	# Set the projectile's visual rotation to match its movement direction.
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	# If the node is already in the scene tree, apply stats immediately. Otherwise, _ready will handle it.
	if is_inside_tree():
		_apply_all_stats_effects()

# Applies all calculated stats and effects to the projectile instance.
# This method pulls relevant data from '_received_stats' (calculated by WeaponManager)
# and '_owner_player_stats' (cached current_ properties from PlayerStats).
func _apply_all_stats_effects():
	# Safety checks to ensure necessary data and references are valid.
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats):
		push_warning("WARNING (ShortbowArrow): Stats not set or owner_player_stats invalid. Cannot apply effects."); return

	# --- Damage Calculation (Leveraging unified PlayerStats method) ---
	# Retrieve weapon-specific damage percentage from received stats.
	var weapon_damage_percent = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.WEAPON_DAMAGE_PERCENTAGE], 1.0))
	# Retrieve weapon tags to pass to the damage calculation.
	var weapon_tags: Array[StringName] = _received_stats.get(&"tags", [])
	# Calculate the final damage using the player's overall damage formula, including tags.
	var calculated_damage_float = _owner_player_stats.get_calculated_player_damage(weapon_damage_percent, weapon_tags)
	final_damage_amount = int(round(maxf(1.0, calculated_damage_float))) # Ensure minimum 1 damage.
	
	# --- Projectile Speed Calculation ---
	# Retrieve base projectile speed from received stats.
	var base_projectile_speed = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PROJECTILE_SPEED], 160.0)
	# Apply player's global projectile speed multiplier using get_final_stat.
	var player_projectile_speed_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	final_speed = base_projectile_speed * player_projectile_speed_multiplier
	
	# --- Pierce Count Setup ---
	# Retrieve base pierce count from received stats.
	var base_pierce_count = _received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.PIERCE_COUNT], 0)
	# Apply global projectile pierce count addition.
	var global_pierce_add = int(_owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_PIERCE_COUNT_ADD))
	max_pierce_count = base_pierce_count + global_pierce_add
	
	# --- Scale Calculation (Visual and Collision) ---
	# Retrieve inherent visual scales from received stats.
	var base_scale_x = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_X], 1.0))
	var base_scale_y = float(_received_stats.get(PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.INHERENT_VISUAL_SCALE_Y], 1.0))
	# Apply player's global projectile size multiplier.
	var player_projectile_size_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	final_applied_scale.x = base_scale_x * player_projectile_size_multiplier
	final_applied_scale.y = base_scale_y * player_projectile_size_multiplier
	
	_apply_visual_scale() # Apply the calculated scale to the sprite and collision shape.
	
	# --- Lifetime Calculation ---
	# Retrieve base lifetime from received stats.
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 2.0)) # 'base_lifetime' is a direct key in blueprint.
	# Apply player's global effect duration multiplier.
	var effect_duration_multiplier = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	# Apply global projectile max range addition to lifetime for ranged projectiles.
	# This implies that added range translates to longer flight time.
	var global_max_range_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
	# A simple way to integrate: add proportional lifetime based on speed and range add.
	# Adjust this formula if a different scaling is desired.
	if final_speed > 0:
		base_lifetime += (global_max_range_add / final_speed) * 0.5 # Example: 0.5 factor for tuning

	lifetime_timer.wait_time = base_lifetime * effect_duration_multiplier
	
	# Start the lifetime timer if it's not already running.
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped():
		lifetime_timer.start()

# Applies the calculated visual scale to the AnimatedSprite2D and CollisionShape2D nodes.
func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	else: push_warning("WARNING (ShortbowArrow): AnimatedSprite2D is invalid, cannot apply visual scale.")
	
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale
	else: push_warning("WARNING (ShortbowArrow): CollisionShape2D is invalid, cannot apply collision scale.")

# Handles collision with other bodies.
func _on_body_entered(body: Node2D):
	# Check if the collided body is an enemy and can take damage.
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		var enemy_target = body as BaseEnemy
		if not is_instance_valid(enemy_target) or enemy_target.is_dead(): return # Do not hit dead enemies.

		var owner_player = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
		
		# Prepare attack-specific stats to pass to the enemy's take_damage method.
		# This includes armor penetration from the player's stats for accurate damage calculation.
		var attack_stats_for_enemy: Dictionary = {
			PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION) # Use get_final_stat.
			# Add any other relevant attack properties here (e.g., status application chance)
		}

		# Deal damage to the enemy.
		enemy_target.take_damage(final_damage_amount, owner_player, attack_stats_for_enemy)
		
		# --- Apply Lifesteal ---
		var global_lifesteal_percent = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_LIFESTEAL_PERCENT)
		if global_lifesteal_percent > 0:
			var heal_amount = final_damage_amount * global_lifesteal_percent
			if is_instance_valid(owner_player) and owner_player.has_method("heal"):
				owner_player.heal(heal_amount)

		# --- Apply Status Effects on Hit ---
		# Retrieve status application data from _received_stats (passed from WeaponManager).
		if _received_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_target.status_effect_component):
			var status_apps: Array = _received_stats.get(&"on_hit_status_applications", [])
			var global_status_effect_chance_add = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_STATUS_EFFECT_CHANCE_ADD)

			for app_data_res in status_apps:
				var app_data = app_data_res as StatusEffectApplicationData
				if is_instance_valid(app_data):
					# Combine base application chance with global status effect chance addition.
					var final_application_chance = app_data.application_chance + global_status_effect_chance_add
					final_application_chance = clampf(final_application_chance, 0.0, 1.0) # Clamp between 0 and 1.
					
					if randf() < final_application_chance:
						enemy_target.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData, # Load StatusEffectData from path.
							owner_player, # Source of the effect (the player).
							_received_stats, # Pass weapon stats for scaling of the status effect.
							app_data.duration_override,
							app_data.potency_override
						)
						# print("ShortbowArrow: Applied status from '", app_data.status_effect_resource_path, "' to enemy.") # Debug print.

		# --- Handle Pierce Count ---
		current_pierce_count += 1
		# If the projectile has pierced more enemies than allowed by its max_pierce_count, queue it for removal.
		# (max_pierce_count represents how many enemies it can pass *through*, so if current_pierce_count
		# exceeds this, it means it has hit its final enemy).
		if current_pierce_count > max_pierce_count:
			call_deferred("queue_free") # Use call_deferred for safe removal during physics processing.
		# Note: If GLOBAL_PROJECTILE_FORK_COUNT_ADD or GLOBAL_PROJECTILE_BOUNCE_COUNT_ADD were to be implemented
		# for this projectile, their logic would go here or in a separate function.

	# If the projectile hits a world obstacle, destroy it.
	elif body.is_in_group("world_obstacles"):
		call_deferred("queue_free") # Use call_deferred for safe removal.
