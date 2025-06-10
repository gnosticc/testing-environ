# crossbowbolt.gd
# This script controls the behavior of a single crossbow bolt projectile.
# It receives its properties from WeaponManager and deals damage based on player stats.
# It now fully integrates with the standardized stat system.

extends Area2D

var final_damage_amount: float # Changed to float for consistency with BaseEnemy.take_damage
var final_speed: float = 200.0
var final_applied_scale: Vector2 = Vector2(1,1)
var direction: Vector2 = Vector2.RIGHT # Default value, will be overridden by set_attack_properties

# Pierce-related variables
var max_pierce_count: int = 0
var current_pierce_count: int = 0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite # Use $ shorthand
@onready var lifetime_timer: Timer = $LifetimeTimer # Use $ shorthand
@onready var collision_shape: CollisionShape2D = $CollisionShape2D # Use $ shorthand

var _stats_have_been_set: bool = false # Flag to ensure stats are applied once
var _received_stats: Dictionary = {} # Dictionary of weapon-specific stats passed from WeaponManager
var _owner_player_stats: PlayerStats # Reference to the player's PlayerStats node

func _ready():
	if not is_instance_valid(lifetime_timer):
		push_error("ERROR (CrossbowBolt): LifetimeTimer missing! Queueing free."); call_deferred("queue_free"); return
	else:
		# Connect lifetime timer to free the projectile after its duration.
		if not lifetime_timer.is_connected("timeout", Callable(self, "queue_free")):
			lifetime_timer.timeout.connect(self.queue_free)
	
	# If stats were set via `set_attack_properties` before _ready() (e.g., call_deferred), apply them now.
	if _stats_have_been_set:
		_apply_all_stats_effects()


# Standardized initialization function called by WeaponManager when the attack is spawned.
# p_direction: The normalized direction vector for the projectile.
# p_attack_stats: Dictionary of specific stats for this weapon instance (from WeaponManager).
# p_player_stats: Reference to the player's PlayerStats node.
func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	# Set direction, ensuring it's normalized or defaults to RIGHT.
	direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	_received_stats = p_attack_stats.duplicate(true) # Deep copy to avoid modifying original
	_owner_player_stats = p_player_stats
	_stats_have_been_set = true
	
	# Set the projectile's rotation based on its direction.
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	# Apply all calculated stats and effects. Defer if not yet in tree.
	if is_inside_tree():
		_apply_all_stats_effects()
	else:
		call_deferred("_apply_all_stats_effects")


# Applies all calculated stats and effects to the projectile instance.
func _apply_all_stats_effects():
	if not _stats_have_been_set or not is_instance_valid(_owner_player_stats):
		push_warning("CrossbowBolt: Stats not set or owner_player_stats invalid. Cannot apply effects."); return

	# --- Damage Calculation (Data-Driven) ---
	# Start with player's base numerical damage.
	var player_base_damage = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.NUMERICAL_DAMAGE)
	
	# Apply weapon-specific damage percentage multiplier (from blueprint/upgrades).
	var weapon_damage_percent = _received_stats.get(&"weapon_damage_percentage", 1.0)
	var calculated_damage = player_base_damage * weapon_damage_percent
	
	# Apply player's global damage multiplier.
	calculated_damage *= _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_DAMAGE_MULTIPLIER)

	# Apply Reaping Momentum bonus (Scythe-specific, but example usage)
	var reaping_bonus = _received_stats.get(&"reaping_momentum_bonus_to_apply", 0.0)
	calculated_damage += reaping_bonus

	# Apply Critical Hit logic.
	var crit_chance = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_CHANCE)
	var crit_damage_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.CRIT_DAMAGE_MULTIPLIER)
	
	if randf() < crit_chance:
		calculated_damage *= crit_damage_mult
		# TODO: Add visual/sound effect for critical hit here
		print("CrossbowBolt: Critical Hit!") # For debugging
	
	final_damage_amount = calculated_damage # Assign the final calculated damage

	# --- Projectile Speed Calculation ---
	var base_w_speed = _received_stats.get(&"projectile_speed", 200.0)
	var p_proj_spd_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
	final_speed = base_w_speed * p_proj_spd_mult
	
	# --- Pierce Count ---
	max_pierce_count = _received_stats.get(&"pierce_count", 0) # Get pierce count from weapon stats

	# --- Scale Calculation (Visual and Collision) ---
	var base_scale_x = float(_received_stats.get(&"inherent_visual_scale_x", 1.0))
	var base_scale_y = float(_received_stats.get(&"inherent_visual_scale_y", 1.0))
	var p_proj_size_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SIZE_MULTIPLIER)
	final_applied_scale.x = base_scale_x * p_proj_size_mult
	final_applied_scale.y = base_scale_y * p_proj_size_mult
	
	_apply_visual_scale() # Apply the calculated scale to sprite and collision shape
	
	# --- Lifetime Calculation ---
	var base_lifetime = float(_received_stats.get(&"base_lifetime", 2.0))
	var duration_mult = _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
	lifetime_timer.wait_time = base_lifetime * duration_mult
	
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped():
		lifetime_timer.start()


# Applies the calculated visual scale to the AnimatedSprite2D and CollisionShape2D.
func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	else: push_warning("CrossbowBolt: AnimatedSprite2D is invalid, cannot apply visual scale.")
	
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale
	else: push_warning("CrossbowBolt: CollisionShape2D is invalid, cannot apply collision scale.")


# Handles collision with other bodies.
func _on_body_entered(body: Node2D):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		var enemy_node = body as BaseEnemy
		if is_instance_valid(enemy_node):
			var owner_player = _owner_player_stats.get_parent() if is_instance_valid(_owner_player_stats) else null
			
			# Prepare attack stats to pass to the enemy's take_damage method.
			# This includes armor penetration from the player's stats.
			var attack_stats_for_enemy: Dictionary = {
				# Pass player's armor penetration for enemy's damage calculation.
				PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.ARMOR_PENETRATION]: _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ARMOR_PENETRATION)
				# Add any other relevant attack stats here (e.g., lifesteal, status application chance)
			}
			
			enemy_node.take_damage(final_damage_amount, owner_player, attack_stats_for_enemy)
			
			current_pierce_count += 1
			if current_pierce_count > max_pierce_count:
				call_deferred("queue_free") # Projectile consumed all pierces, queue for removal.

			# Apply Status Effects on Hit if defined in _received_stats
			if _received_stats.has(&"on_hit_status_applications") and is_instance_valid(enemy_node.status_effect_component):
				var status_apps: Array = _received_stats.get(&"on_hit_status_applications", [])
				for app_data_res in status_apps:
					var app_data = app_data_res as StatusEffectApplicationData
					if is_instance_valid(app_data) and randf() < app_data.application_chance:
						# Pass weapon_stats to StatusEffectComponent for scaling if needed
						enemy_node.status_effect_component.apply_effect(
							load(app_data.status_effect_resource_path) as StatusEffectData,
							owner_player, # Source of the effect
							_received_stats, # Weapon stats for scaling
							app_data.duration_override,
							app_data.potency_override
						)
						print("CrossbowBolt: Applied status from '", app_data.status_effect_resource_path, "' to enemy.")


	# If hitting a world obstacle, the projectile is destroyed.
	elif body.is_in_group("world_obstacles"):
		call_deferred("queue_free")
